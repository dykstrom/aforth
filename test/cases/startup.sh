# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The command line, and the two files cold start reads.
#
# ADR 0003 requires --no-init, so that a test run and a bug report do not
# depend on whoever's machine they run on, and --init <file>, so that one can
# be named. args_parse in src/aforth.S reads them and cold_start acts on what
# they decided. See docs/system/startup.md.
#
# Every case here names its own command line as the fourth argument, which is
# what stops run-tests.sh adding --no-init to it. The cases that read a config
# file name '' instead, which is no arguments at all: --no-init would be the
# one thing that stopped them reading it.
#
# The config directory is a temporary one, pointed at with XDG_CONFIG_HOME, so
# that no case here depends on the developer's own ~/.config or writes to it.
#
# Sourced by test/run-tests.sh, which defines check, prints, raises, exits and
# guards.

ARG_DIR=$(mktemp -d)
printf '\n' > "$ARG_DIR/some.f"

INIT_DIR=$(mktemp -d)
mkdir -p "$INIT_DIR/config/aforth" "$INIT_DIR/home/.config/aforth" \
         "$INIT_DIR/empty" "$INIT_DIR/broken/aforth"
printf '%s\n' ': CONFIG-INIT 7 ;' > "$INIT_DIR/config/aforth/init.f"
printf '%s\n' ': HOME-INIT 8 ;'   > "$INIT_DIR/home/.config/aforth/init.f"
printf '%s\n' ': NAMED-INIT 11 ;' > "$INIT_DIR/named.f"
printf '%s\n' ': FIRST-INIT 1 ;'  > "$INIT_DIR/first.f"
printf '%s\n' ': SECOND-INIT 2 ;' > "$INIT_DIR/second.f"
printf '1 1 +\nNOT-A-WORD\n'      > "$INIT_DIR/broken/aforth/init.f"
printf ': T 1 ABORT" no config" ;\n1 1 +\nT\n' > "$INIT_DIR/aborts.f"

# From here to the end of the file, aforth looks for the user's init.f in a
# temporary directory. It is set before the first case rather than beside the
# cases that care, because a case running with no arguments at all would
# otherwise read whatever the developer has in ~/.config/aforth.
XDG_CONFIG_HOME="$INIT_DIR/empty"
export XDG_CONFIG_HOME

prints "no arguments at all still works" '1 .' '1  ok' ''
prints "--no-init is accepted"           '1 .' '1  ok' '--no-init'

# A usage error is written before the banner, so nothing reaches file
# descriptor 1 at all.
raises "an unknown argument is reported" \
  '1 .' 'aforth: unknown argument: --wat' '--wat'
prints "and nothing is printed on stdout" '1 .' '' '--wat'
exits  "and the status is 1"              '1 .' 1 '--wat'

raises "--init with no file after it" \
  '1 .' 'aforth: --init needs a file' '--init'
exits  "--init with no file exits 1" '1 .' 1 '--init'

# The two flags contradict each other, so giving both is an error rather than
# a guess about which was meant. The order on the line does not matter.
raises "--no-init before --init is an error" \
  '1 .' 'aforth: --no-init and --init cannot both be given' \
  '--no-init --init a'
raises "--no-init after --init is an error" \
  '1 .' 'aforth: --no-init and --init cannot both be given' \
  '--init a --no-init'
exits  "and both together exit 1" '1 .' 1 '--no-init --init a'

# --help, which is the whole of what the binary says about its own arguments,
# so these cases compare the whole of it rather than a line.
#
# The binary is run directly rather than through prints: out drops line 1 to
# discard the banner, and the banner is the first line of what --help prints.
# The text is in double quotes so the apostrophes need no escaping, which makes
# the $ of XDG_CONFIG_HOME the one thing that does.
HELP_TEXT="aforth 0.0.0

Usage: aforth [OPTION]...

  --help         show this help and exit
  --init <file>  read <file> instead of the user's init.f
  --no-init      do not read the user's init.f

At start-up aforth reads aforth.f from beside the binary, then
\$XDG_CONFIG_HOME/aforth/init.f, or ~/.config/aforth/init.f when
that variable is unset."

check "--help prints the arguments on stdout" \
  "$HELP_TEXT" "$("$BIN" --help 2>/dev/null)"
check "and nothing on stderr" "" "$("$BIN" --help 2>&1 >/dev/null)"
exits "and exits 0" '1 .' 0 '--help'

# It answers and returns before machine_quit, so the 1 . is never read: the
# help is the whole of what comes out.
check "--help reads no input" \
  "$HELP_TEXT" "$(printf '1 .\n' | "$BIN" --help 2>/dev/null)"

# --help is answered where it is found and the rest of the line is not looked
# at, so a mistake after it still prints the help. A mistake before it is
# reached first and reported, which is the same scan working the same way.
check "--help wins over a later bad argument" \
  "$HELP_TEXT" "$("$BIN" --help --wat 2>/dev/null)"
exits "and still exits 0" '1 .' 0 '--help --wat'

raises "a bad argument before --help is still reported" \
  '1 .' 'aforth: unknown argument: --wat' '--wat --help'
exits  "and still exits 1" '1 .' 1 '--wat --help'

# Cold start.
#
# Each init file defines one word and prints nothing, so a case asks for the
# word and reads the answer: that shows the file ran without putting anything
# of its own on stdout, which would push the banner off line 1.

XDG_CONFIG_HOME="$INIT_DIR/config"
export XDG_CONFIG_HOME

prints "an init.f under \$XDG_CONFIG_HOME runs at cold start" \
  'CONFIG-INIT .' '7  ok' ''

# --no-init drops the user's file only. The system file still loads, which is
# what makes the suite exercise it on every one of its other cases.
raises "--no-init skips the user's init.f" \
  'CONFIG-INIT .' 'aforth: undefined word: CONFIG-INIT' '--no-init'
prints "and the system file loads anyway" '5 1 9 WITHIN .' '-1  ok' '--no-init'

# --help returns before cold_start, so neither file is read at all. The word
# the init.f here defines is never asked for: the help is the whole output.
check "--help reads no init file either" \
  "$HELP_TEXT" "$(printf 'CONFIG-INIT .\n' | "$BIN" --help 2>/dev/null)"

# --init replaces the user's file rather than adding to it.
prints "--init reads the file it names" \
  'NAMED-INIT .' '11  ok' "--init $INIT_DIR/named.f"
raises "and the config init.f is left alone" \
  'CONFIG-INIT .' 'aforth: undefined word: CONFIG-INIT' \
  "--init $INIT_DIR/named.f"

# args_parse keeps the last --init, and this is what shows it: before cold
# start there was nothing that read the cell it writes.
prints "the last --init wins" 'SECOND-INIT .' '2  ok' \
  "--init $INIT_DIR/first.f --init $INIT_DIR/second.f"
raises "and the first one is not read" \
  'FIRST-INIT .' 'aforth: undefined word: FIRST-INIT' \
  "--init $INIT_DIR/first.f --init $INIT_DIR/second.f"

# A file named on the command line was asked for, so one that will not open is
# reported. aforth stays usable at the prompt all the same.
raises "--init names a file that is not there" \
  '1 .' "aforth: cannot open file: $INIT_DIR/nothing-here.f" \
  "--init $INIT_DIR/nothing-here.f"
prints "and the prompt still comes up" '1 .' '1  ok' \
  "--init $INIT_DIR/nothing-here.f"
exits  "and the status is still 0" '1 .' 0 "--init $INIT_DIR/nothing-here.f"

prints "--init names a file that is there" \
  '1 .' '1  ok' "--init $ARG_DIR/some.f"

# ABORT" in an init file reports the way any error there does: the message, the
# file and the line, and then the prompt with the stacks empty.
raises 'ABORT" in an --init file names the file and the line' '1 .' \
  "aforth: no config
aforth:   in $INIT_DIR/aborts.f, line 3" "--init $INIT_DIR/aborts.f"
prints "and the prompt comes up with the stacks empty" '.S' '<0>  ok' \
  "--init $INIT_DIR/aborts.f"

# --init with an empty string after it named a file too, badly. It is answered
# rather than quietly turned into the config file. The binary is run directly
# here because the helpers split their fourth argument on white space, which is
# what drops an empty argument.
check "--init with an empty path names no file" \
  'aforth: name expected' \
  "$(printf '1 .\n' | "$BIN" --init '' 2>&1 >/dev/null)"

# The file aforth looks for rather than is told to read. Not having one is the
# ordinary case: nothing is said, nothing is created, and the status is 0.
XDG_CONFIG_HOME="$INIT_DIR/empty"

prints "no init.f says nothing on stdout" '1 .' '1  ok' ''
raises "and nothing on stderr"            '1 .' ''       ''
exits  "and exits 0"                      '1 .' 0        ''
check  "and creates nothing" "" "$(find "$INIT_DIR/empty" -mindepth 1)"

# An error in an init file names the file and the line it happened on, and
# leaves aforth at the prompt with the stacks empty rather than half
# configured. The 1 1 + on the line above the error is what shows the data
# stack was emptied.
XDG_CONFIG_HOME="$INIT_DIR/broken"

raises "an error in init.f names the file and the line" '1 .' \
  "aforth: undefined word: NOT-A-WORD
aforth:   in $INIT_DIR/broken/aforth/init.f, line 2" ''
prints "and the prompt comes up with the stacks empty" '.S' '<0>  ok' ''
exits  "and the status is still 0"                     '1 .' 0 ''

# An init.f that is there and will not open is a different case from one that
# is not there, and it is reported. root reads a file whatever its mode says,
# so the case cannot show anything when the suite runs as root — which it does
# in the Linux container.
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$INIT_DIR/unreadable/aforth"
  printf '%s\n' '1 .' > "$INIT_DIR/unreadable/aforth/init.f"
  chmod 000 "$INIT_DIR/unreadable/aforth/init.f"
  XDG_CONFIG_HOME="$INIT_DIR/unreadable"

  raises "an init.f that will not open is reported" '1 .' \
    "aforth: cannot open file: $INIT_DIR/unreadable/aforth/init.f" ''
  prints "and the prompt still comes up" '1 .' '1  ok' ''

  chmod 644 "$INIT_DIR/unreadable/aforth/init.f"
else
  echo "skip - an init.f that will not open (root reads it anyway)"
fi

# $HOME/.config is the fallback ADR 0003 names, and it is the same path on both
# platforms. HOME is put back afterwards: the cases below it do not care, but a
# suite that leaves it moved is a trap for the next one written.
unset XDG_CONFIG_HOME
STARTUP_HOME="$HOME"
HOME="$INIT_DIR/home"
export HOME

prints "\$HOME/.config/aforth/init.f is the fallback" \
  'HOME-INIT .' '8  ok' ''

HOME="$STARTUP_HOME"
export HOME
XDG_CONFIG_HOME="$INIT_DIR/empty"
export XDG_CONFIG_HOME

# The system file is found beside the binary, so a copy of it somewhere else
# has no aforth.f next to it and says so. A copy rather than a move: the build
# tree is left alone whatever this case does.
#
# The path is taken through pwd -P because the message holds the one realpath
# resolved, and on macOS mktemp hands back /var/..., which is a symlink to
# /private/var/....
SYS_DIR=$(cd "$(mktemp -d)" && pwd -P)
cp "$BIN" "$SYS_DIR/aforth"

check "a binary with no system file beside it says so" \
  "aforth: cannot open file: $SYS_DIR/aforth.f" \
  "$(printf '1 .\n' | "$SYS_DIR/aforth" --no-init 2>&1 >/dev/null)"
check "and the prompt still comes up" \
  '1  ok' \
  "$(printf '1 .\n' | "$SYS_DIR/aforth" --no-init 2>/dev/null | sed 1d)"

cp "$HERE/../lib/aforth.f" "$SYS_DIR/aforth.f"
check "and finds it once it is beside the binary" \
  '-1  ok' \
  "$(printf '5 1 9 WITHIN .\n' | "$SYS_DIR/aforth" --no-init 2>/dev/null | sed 1d)"

rm -rf "$ARG_DIR" "$INIT_DIR" "$SYS_DIR"
