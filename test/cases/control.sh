# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Control flow inside a definition.
#
# Each case defines a word on one line and runs it on the next, so the expected
# text holds one ok per line. A loop is checked by what it prints on each turn
# rather than by its result alone: a loop that ran once and a loop that ran
# three times can leave the same number on the stack.
#
# See docs/system/control-flow.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

# Both ways through IF THEN, in one definition, so a branch that always jumps
# and one that never does are told apart.
prints "IF THEN runs the body on a true flag" ': ABS2 DUP 0< IF NEGATE THEN ;
-5 ABS2 . 5 ABS2 .' ' ok
5 5  ok'

# ELSE, printing a different character each way. A missing branch over the
# false half would print both.
prints "IF ELSE THEN takes one half or the other" \
  ': SIGN? DUP 0> IF [CHAR] P ELSE [CHAR] N THEN EMIT DROP ;
1 SIGN? -1 SIGN?' ' ok
PN ok'

# Written over two lines, which also says that a definition holding a branch may
# span them: the distance is worked out from where HERE stands, not from the
# line the word was typed on.
prints "IF nests inside IF" \
  ': N DUP 0> IF DUP 5 > IF [CHAR] B ELSE [CHAR] S THEN
       ELSE [CHAR] Z THEN EMIT DROP ;
9 N 2 N -1 N' ' ok
 ok
BSZ ok'

# The three loops, each counting down from three, so each prints the same
# thing by a different route.
prints "BEGIN UNTIL loops until the flag is true" \
  ': CD BEGIN DUP . 1 - DUP 0= UNTIL DROP ;
3 CD' ' ok
3 2 1  ok'

prints "BEGIN WHILE REPEAT tests before the body" \
  ': CW BEGIN DUP 0> WHILE DUP . 1 - REPEAT DROP ;
3 CW' ' ok
3 2 1  ok'

# WHILE on a flag that is false the first time round: the body never runs, so
# nothing is printed and the count comes out untouched.
prints "BEGIN WHILE REPEAT may run its body no times" \
  ': CW BEGIN DUP 0> WHILE DUP . 1 - REPEAT ;
0 CW .' ' ok
0  ok'

prints "BEGIN AGAIN loops until something leaves it" \
  ': CA BEGIN DUP . 1 - DUP 0= IF DROP EXIT THEN AGAIN ;
3 CA' ' ok
3 2 1  ok'

prints "a loop nests inside a loop" \
  ': ROW 0 BEGIN DUP 3 < WHILE DUP . 1+ REPEAT DROP [CHAR] | EMIT ;
: GRID 0 BEGIN DUP 2 < WHILE ROW CR 1+ REPEAT DROP ;
GRID' ' ok
 ok
0 1 2 |
0 1 2 |
 ok'

# EXIT leaves the definition, so what follows it never runs.
prints "EXIT leaves the definition" ': E 1 . EXIT 2 . ;
E' ' ok
1  ok'

# RECURSE reaches the definition being written, which its own name cannot: the
# entry is hidden until ; . Factorial exercises the recursion and the base
# case, and 10 FACT is past what a single multiply would give.
prints "RECURSE calls the definition being written" \
  ': FACT DUP 1 > IF DUP 1 - RECURSE * ELSE DROP 1 THEN ;
5 FACT . 0 FACT . 10 FACT .' ' ok
120 1 3628800  ok'

# The name inside the definition is still the previous word of that name, which
# is what RECURSE exists to work around.
prints "a name inside a definition is not the definition" ': F 1 ;
: F F 2 + ;
F .' ' ok
 ok
3  ok'

# The control-flow stack is the data stack, so a number left lying about looks
# exactly like a place to branch to. Each of these would write through an
# address of 2 and kill the process without the check.
CF='aforth: unstructured control flow'
raises "THEN refuses a number that is no place" '2 THEN'       "$CF"
raises "ELSE refuses a number that is no place" '2 ELSE'       "$CF"
raises "UNTIL refuses a number that is no place" '2 UNTIL'     "$CF"
raises "AGAIN refuses a number that is no place" '2 AGAIN'     "$CF"
raises "REPEAT refuses a number that is no place" '1 2 REPEAT' "$CF"

# Zero is the one that would otherwise pass a bounds test written the other way
# round, and an address past HERE is the other end of the same check.
raises "THEN refuses zero"          '0 THEN'      "$CF"
raises "THEN refuses an odd address" 'HERE 1 + THEN' "$CF"
raises "THEN refuses an address past HERE" 'HERE 8 + THEN' "$CF"

# A definition left unfinished does not crash: the distance stays zero, which
# branches nowhere, and the place to write stays on the data stack.
prints "IF with no THEN falls through" ': Y 1 IF 42 ;
DROP 1 Y .' ' ok
42  ok'
