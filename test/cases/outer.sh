# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The outer interpreter: the QUIT loop, the words that leave it, and the one
# path every error takes. See docs/system/outer-interpreter.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

# The one case that runs the binary itself rather than through a helper: every
# helper drops the banner, and this is the case that wants it. It passes
# DEFAULT_ARGS by hand for the same reason the helpers do.
check "prints its banner" "aforth 0.0.0" \
  "$(printf '' | "$BIN" $DEFAULT_ARGS 2>/dev/null | sed -n 1p)"

# A line that runs without error ends in ok, so the first case proves the whole
# loop: refill, parse, look up, convert a number, execute, and report.
prints "interprets a line"           '2 3 + .'     '5  ok'
prints "converts a negative number"  '-42 .'       '-42  ok'
prints "says ok on an empty line"    ''            ' ok'

# DECIMAL and HEX are run by the same loop that then converts FF, so this fails
# unless BASE is read for every name rather than once a line.
prints "follows BASE within a line"  'HEX FF . DECIMAL 255 .' 'FF 255  ok'

# Three lines, so the ok after each one has to be its own.
prints "says ok once per line" '1 .
2 .
3 .' '1  ok
2  ok
3  ok'

prints "EXECUTE runs a token"        "1 2 ' + EXECUTE ." '3  ok'

# How far STATE's address lies from BASE's is checked as well as what it holds.
# Reading alone is not enough: this case passed against a STATE that handed out
# BASE's address, because any writable cell reads back. The distance is the one
# machine.h sets, UV_STATE minus UV_BASE. What STATE holds while the loop is
# compiling is in test/cases/compile.sh, where something can be compiling.
prints "STATE is its own cell"  'STATE BASE - . STATE @ .' '8 0  ok'

# The errors. Each names what failed, and nothing reaches stdout.
raises "names an undefined word"     'fnord'   'aforth: undefined word: fnord'

# ' raises the same error through the same routine, so the two agree.
raises "names a word ' cannot find"  "' fnord" 'aforth: undefined word: fnord'

# The input buffer holds 4096 bytes and a line of exactly that many is read.
prints "reads a line of 4096 bytes"  "$(printf '%4096s' '')" ' ok'
raises "reports a line of 4097 bytes" "$(printf '%4097s' '')" \
  'aforth: input line too long'

# Filling the data stack by typing numbers goes through the interpreter's own
# room check rather than the ROOM macro, which would unwind to a frame that is
# already gone. Nothing else exercises that check, and it stays in the build
# without the stack guards. The stack holds 8192 cells and a line holds 4096
# bytes, so it takes five lines to fill.
numbers=' 1'
while [ "${#numbers}" -lt 4080 ]; do numbers="$numbers$numbers"; done
raises "reports an overflow from typed numbers" \
  "$numbers
$numbers
$numbers
$numbers
$numbers" 'aforth: data stack overflow'

# An error ends the line it happened on: the . after the bad name never runs.
prints "drops the rest of a failed line" 'fnord 1 .' ''

# And the line after it does run, which is the whole point of ABORT over exit.
prints "carries on after an error" 'fnord
1 .' '1  ok'

# ABORT empties both stacks and says nothing. QUIT empties the return stack
# only, which is what tells the two apart.
prints "ABORT empties the data stack" '1 2 ABORT
.S' '<0>  ok'
raises "ABORT prints no message"        '1 2 ABORT' ''
prints "QUIT keeps the data stack"      '1 2 QUIT
.S' '<2> 1 2  ok'

# What each one does to the return stack can only be seen through a guard, so
# those two cases are in test/cases/guards.sh.

# BYE ends the process, so the line after it is never read.
prints "BYE stops reading" '1 .
BYE
99 .' '1  ok'
exits  "BYE exits successfully" '1 .
BYE
99 .' 0

# End of input ends the session the same way.
exits  "exits successfully at end of input" '1 .' 0

# Nested input sources.
#
# What the sources do while they are being read is in test/cases/input.sh.
# These cases are what says the interpreter is back at the terminal afterwards:
# the observable behaviour, whichever part of the code delivers it. Today that
# is EVALUATE popping its own source as the error passes through it, not
# src_reset, which no case can reach — see the comment on src_reset.

# Eight levels nest and a ninth does not. The definition recurses through
# EVALUATE, so each call stacks one more source until the guard fires.
raises "a source too deep is reported" ': DEEP S" DEEP" EVALUATE ;
DEEP' 'aforth: input sources nested too deep'

# Where the limit falls, rather than only that there is one. Each Ln stacks one
# more source than the one below it, so L8 uses every level and L9 wants one
# that is not there. An off-by-one in SRC_LEVELS moves exactly these two.
NEST_DEFS=': L1 S" 1 2 +" EVALUATE ;
: L2 S" L1" EVALUATE ;
: L3 S" L2" EVALUATE ;
: L4 S" L3" EVALUATE ;
: L5 S" L4" EVALUATE ;
: L6 S" L5" EVALUATE ;
: L7 S" L6" EVALUATE ;
: L8 S" L7" EVALUATE ;
: L9 S" L8" EVALUATE ;'
prints "eight sources nest" "$NEST_DEFS
L8 ." ' ok
 ok
 ok
 ok
 ok
 ok
 ok
 ok
 ok
3  ok'
raises "a ninth source does not" "$NEST_DEFS
L9 ." 'aforth: input sources nested too deep'

# An error inside a string ends the line it was on, as any error does, and the
# next line still runs at the terminal.
raises "an error inside EVALUATE names the word" 'S" fnord" EVALUATE' \
  'aforth: undefined word: fnord'
prints "an error inside EVALUATE drops the rest of the line" \
  'S" fnord" EVALUATE 1 .
2 .' '2  ok'
prints "an error inside EVALUATE unwinds the sources" 'S" fnord" EVALUATE
SOURCE-ID .' '0  ok'
prints "a source too deep unwinds the sources" ': DEEP S" DEEP" EVALUATE ;
DEEP
SOURCE-ID .' ' ok
0  ok'

# ABORT and QUIT reach the loop from inside a string the same way they reach it
# from a word, so each still does what it does to the stacks.
prints "ABORT inside EVALUATE empties the data stack" '1 2 S" ABORT" EVALUATE
.S' '<0>  ok'
prints "QUIT inside EVALUATE keeps the data stack" '1 2 S" QUIT" EVALUATE
.S' '<2> 1 2  ok'
