#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Runs the aforth binary and checks its observable behaviour.
# Usage: test/run-tests.sh ./build/aforth
#
# Every case pipes Forth source in and compares what comes out. The binary
# reads until end of input, so each run gets a whole script on stdin. Ticket
# 009 builds this out into a suite with a case per word; what is here covers
# the outer interpreter itself.

set -eu

BIN="${1:-./build/aforth}"
failures=0

check() {
  name="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    echo "       expected: $expected"
    echo "       actual:   $actual"
    failures=$((failures + 1))
  fi
}

# Run the source in $1 and print what reaches stdout, the banner dropped.
# Errors go to file descriptor 2, so they are not in what this returns.
out() {
  printf '%s' "$1" | "$BIN" 2>/dev/null | sed 1d
}

# The same, but what reaches file descriptor 2.
err() {
  printf '%s' "$1" | "$BIN" 2>&1 >/dev/null
}

check "prints its banner" "aforth 0.0.0" \
  "$(printf '' | "$BIN" 2>/dev/null | sed -n 1p)"

# A line that runs without error ends in ok, so the first case proves the whole
# loop: refill, parse, look up, convert a number, execute, and report.
check "interprets a line" "5  ok" "$(out '2 3 + .
')"

# DECIMAL and HEX are run by the same loop that then converts FF, so this fails
# unless BASE is read for every name rather than once a line.
check "follows BASE within a line" "FF 255  ok" "$(out 'HEX FF . DECIMAL 255 .
')"

check "converts a negative number" "-42  ok" "$(out '-42 .
')"

check "says ok on an empty line" " ok" "$(out '
')"

# Three lines, so the ok after each one has to be its own.
check "says ok once per line" "1  ok
2  ok
3  ok" "$(out '1 .
2 .
3 .
')"

# The errors. Each names what failed, and nothing reaches stdout.
check "names an undefined word" "aforth: undefined word: fnord" "$(err 'fnord
')"

# ' raises the same error through the same routine, so the two agree.
check "names a word ' cannot find" "aforth: undefined word: fnord" "$(err "' fnord
")"

# A guard's message is only there to check when the build carries the guards.
# make passes its assembler flags in AFORTH_ASFLAGS so that this can tell.
case "${AFORTH_ASFLAGS:-}" in
  *-DAFORTH_NO_STACK_CHECKS*)
    echo "skip - reports a stack underflow (built without the guards)"
    ;;
  *)
    check "reports a stack underflow" "aforth: data stack underflow" "$(err 'DUP
')"
    ;;
esac

check "reports a divide by zero" "aforth: divide by zero" "$(err '1 0 /
')"

# Filling the data stack by typing numbers goes through the interpreter's own
# room check rather than the ROOM macro, which would unwind to a frame that is
# already gone. Nothing else exercises that check. The stack holds 8192 cells
# and a line holds 4096 bytes, so it takes five lines to fill.
numbers=' 1'
while [ "${#numbers}" -lt 4080 ]; do numbers="$numbers$numbers"; done
check "reports an overflow from typed numbers" "aforth: data stack overflow" \
  "$(err "$numbers
$numbers
$numbers
$numbers
$numbers
")"

# An error ends the line it happened on: the . after the bad name never runs.
check "drops the rest of a failed line" "" "$(out 'fnord 1 .
')"

# And the line after it does run, which is the whole point of ABORT over exit.
check "carries on after an error" "1  ok" "$(out 'fnord
1 .
')"

# ABORT empties the data stack, so .S on the next line counts nothing.
check "ABORT empties the data stack" "<0>  ok" "$(out '1 2 ABORT
.S
')"

check "ABORT prints no message" "" "$(err '1 2 ABORT
')"

# QUIT leaves the data stack alone, which is what tells it from ABORT.
check "QUIT keeps the data stack" "<2> 1 2  ok" "$(out '1 2 QUIT
.S
')"

# BYE ends the process, so the line after it is never read.
check "BYE stops reading" "1  ok" "$(out '1 .
BYE
99 .
')"
printf '1 .\nBYE\n99 .\n' | "$BIN" >/dev/null 2>&1 || bye_status=$?
check "BYE exits successfully" "0" "${bye_status:-0}"

# End of input ends the session the same way, and prints a newline so that a
# terminal's next prompt starts on a line of its own.
printf '1 .\n' | "$BIN" >/dev/null 2>&1 || eof_status=$?
check "exits successfully at end of input" "0" "${eof_status:-0}"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
