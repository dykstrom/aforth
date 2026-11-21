# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The Exception word set: CATCH and THROW, and the codes the built-in errors
# reach CATCH with.
#
# A code that a stack guard raises is tested in cases/guards.sh instead, which
# the build without the guards leaves out. Every case here runs in both builds.
#
# The include cases need files, which are made here with printf and removed at
# the end, as cases/file.sh does. A name inside one of them is resolved against
# the working directory, so every name is absolute.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

EXC_DIR=$(mktemp -d)
printf '1 fnord 2\n'                               > "$EXC_DIR/undef.f"
printf 'INCLUDE %s/undef.f\n' "$EXC_DIR"           > "$EXC_DIR/outer.f"
printf '42 THROW\n'                                > "$EXC_DIR/throw.f"

# CATCH and THROW at work.
prints "CATCH pushes 0 after a word that finishes" \
  ": T1 9 ; 1 2 3 ' T1 CATCH .S" '<5> 1 2 3 9 0  ok'
prints "0 THROW does nothing" '1 2 0 THROW .S' '<2> 1 2  ok'
prints "THROW restores the depth CATCH began at" \
  ": T3 7 8 9 99 THROW ; 1 2 ' T3 CATCH .S" '<3> 1 2 99  ok'
prints "THROW restores the depth after the stack was emptied" \
  ": T5 2DROP 2DROP 9999 THROW ; 1 2 3 4 ' T5 CATCH DEPTH . ." '5 9999  ok'

# The 10 under the token is counted down in place to 0 before the throw. The
# depth is restored, not the items, so 0 is what is left there.
prints "THROW from a recursive word keeps what it changed in place" \
  ": T4 1- DUP 0> IF RECURSE ELSE 999 THROW THEN ; 3 10 ' T4 CATCH .S" \
  '<3> 3 0 999  ok'
prints "the word after CATCH in a definition runs" \
  ": T3 99 THROW ; : C3 ['] T3 CATCH 5 ; C3 .S" '<2> 99 5  ok'
prints "an inner CATCH leaves the outer one nothing to catch" \
  ": T3 99 THROW ; : IN ['] T3 CATCH ; ' IN CATCH .S" '<2> 99 0  ok'
prints "a code thrown again reaches the outer CATCH" \
  ": T3 99 THROW ; : IN ['] T3 CATCH THROW ; ' IN CATCH .S" '<1> 99  ok'

# EVALUATE pops its string on the way out, so the rest of the typed line is
# read from the terminal again.
prints "the line after a caught EVALUATE runs from the terminal" \
  "S\" 1 fnord\" ' EVALUATE CATCH . 2DROP 7 ." '-13 7  ok'

# The built-in errors reach CATCH with their Forth-2012 codes, and a caught
# error prints nothing.
prints "a divide by zero is -10" "1 0 ' / CATCH . .S" '-10 <2> 1 0  ok'
prints "ABORT is -1" "1 2 ' ABORT CATCH .S" '<3> 1 2 -1  ok'

# The flag under ABORT"'s message was the 5, so the depth goes back to one item
# and the 77 is what lies there.
prints "ABORT\" with a true flag is -2" \
  ": T10 77 SWAP ABORT\" never shown\" ; 5 ' T10 CATCH .S" '<2> 77 -2  ok'
raises "a caught ABORT\" prints nothing" \
  ": T10 77 SWAP ABORT\" never shown\" ; 5 ' T10 CATCH" ''
prints "ABORT\" with a false flag does nothing" \
  ": T10 77 SWAP ABORT\" never shown\" ; 3 0 ' T10 CATCH .S" '<3> 3 77 0  ok'
prints "an undefined word inside EVALUATE is -13" \
  "S\" fnord\" ' EVALUATE CATCH . 2DROP" '-13  ok'
raises "a caught undefined word prints nothing" \
  "S\" fnord\" ' EVALUATE CATCH" ''
prints "a file INCLUDED cannot open is -38" \
  "S\" $EXC_DIR/nothing-here\" ' INCLUDED CATCH . 2DROP" '-38  ok'
raises "a caught file that cannot open prints nothing" \
  "S\" $EXC_DIR/nothing-here\" ' INCLUDED CATCH" ''
prints "an undefined word inside an included file is -13" \
  "S\" $EXC_DIR/undef.f\" ' INCLUDED CATCH . 2DROP" '-13  ok'
raises "a caught error in an included file prints no traceback" \
  "S\" $EXC_DIR/outer.f\" ' INCLUDED CATCH" ''
prints "a file two levels down still gives -13" \
  "S\" $EXC_DIR/outer.f\" ' INCLUDED CATCH . 2DROP" '-13  ok'

# Once the CATCH has finished, an error in a file reports itself again.
raises "an included file reports again once CATCH is done" \
  ": T3 99 THROW ; ' T3 CATCH DROP
INCLUDE $EXC_DIR/undef.f" "aforth: undefined word: fnord
aforth:   in $EXC_DIR/undef.f, line 1"

# What a code that nobody catches prints.
raises "an uncaught code with no message prints the code" \
  '42 THROW' 'aforth: exception 42'
raises "an uncaught negative code prints its sign" \
  '-9 THROW' 'aforth: exception -9'
raises "the most negative code prints whole" \
  '1 63 LSHIFT THROW' 'aforth: exception -9223372036854775808'
raises "an uncaught standard code prints its message" \
  '-4 THROW' 'aforth: data stack underflow'
raises "-13 THROW names no word from an earlier error" \
  'fnord
-13 THROW' 'aforth: undefined word: fnord
aforth: undefined word'
raises "-1 THROW prints nothing" '1 2 -1 THROW' ''
prints "-1 THROW empties the data stack as ABORT does" '1 2 -1 THROW
.S' '<0>  ok'
raises "-2 THROW says aborted" '-2 THROW' 'aforth: aborted'
raises "-2 THROW does not repeat an earlier ABORT\" message" \
  '1 ABORT" disk full"
-2 THROW' 'aforth: disk full
aforth: aborted'
prints "-56 THROW keeps the data stack as QUIT does" '1 2 -56 THROW
.S' '<2> 1 2  ok'
prints "CATCH does not catch QUIT" "1 2 ' QUIT CATCH 5
.S" '<2> 1 2  ok'
raises "an uncaught code in an included file has a traceback" \
  "INCLUDE $EXC_DIR/throw.f" "aforth: exception 42
aforth:   in $EXC_DIR/throw.f, line 1"

rm -rf "$EXC_DIR"
