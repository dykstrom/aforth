# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The outer interpreter: the QUIT loop, the words that leave it, and the one
# path every error takes. See docs/system/outer-interpreter.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

check "prints its banner" "aforth 0.0.0" \
  "$(printf '' | "$BIN" 2>/dev/null | sed -n 1p)"

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

# STATE is written and read back, and how far its address lies from BASE's is
# checked as well. Writing and reading alone is not enough: this case passed
# against a STATE that handed out BASE's address, because any writable cell
# gives back what was put in it. The distance is the one machine.h sets,
# UV_STATE minus UV_BASE.
prints "STATE is its own cell"  'STATE BASE - . TRUE STATE ! STATE @ .' '8 -1  ok'

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
