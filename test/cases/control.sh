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

# What every word here says when it is handed something that is not a place in
# the dictionary, or a LEAVE with no loop to leave.
CF='aforth: unstructured control flow'

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

# The counted loop. Each case says what it printed on every turn, for the same
# reason the BEGIN loops above do.
prints "DO LOOP counts from the index up to the limit" ': T 3 0 DO I . LOOP ;
T' ' ok
0 1 2  ok'

prints "a counted loop counts over a negative range" ': T 0 -3 DO I . LOOP ;
T' ' ok
-3 -2 -1  ok'

# J reads the index of the loop outside this one, two cells further down the
# return stack than the one I reads. Printing both on every turn of the inner
# loop is what tells them apart.
prints "J reads the next loop out" ': T 2 0 DO 2 0 DO J . I . LOOP LOOP ;
T' ' ok
0 0 0 1 1 0 1 1  ok'

# The turn that ends the loop drops both parameters, so what EXIT finds
# underneath them is the address DOCOL saved and the definition returns to its
# caller. A loop that left them would return to a limit instead.
prints "a loop that runs out leaves the return stack as it found it" \
  ': T 3 0 DO LOOP 42 ;
T .' ' ok
42  ok'

# UNLOOP drops the parameters of a loop that has not ended, which is what lets
# the EXIT after it leave the definition. The 99 never prints: it is there to
# say that the definition really left rather than fell out of the loop.
prints "UNLOOP EXIT leaves the definition from inside the loop" \
  ': T 10 0 DO I 3 = IF UNLOOP EXIT THEN I . LOOP 99 . ;
T' ' ok
0 1 2  ok'

# A loop body holds a branch and spans lines, as an IF body may.
prints "IF nests inside a counted loop" ': T 5 0 DO I 2 MOD 0= IF I . THEN
LOOP ;
T' ' ok
 ok
0 2 4  ok'

# +LOOP with a step over one stops at the first index past the limit, and never
# meets the limit exactly, which is what the equality LOOP tests for would need.
prints "+LOOP steps by more than one" ': T 10 0 DO I . 3 +LOOP ;
T' ' ok
0 3 6 9  ok'

# A negative step counts down and stops on the limit rather than one short of
# it: the loop ends when the index crosses the boundary below it.
prints "+LOOP counts down on a negative step" ': T 0 10 DO I . -1 +LOOP ;
T' ' ok
10 9 8 7 6 5 4 3 2 1 0  ok'

prints "?DO runs the loop when the range is not empty" ': T 3 0 ?DO I . LOOP ;
T' ' ok
0 1 2  ok'

# The case DO cannot do: an empty range runs no times instead of counting the
# whole cell range.
prints "?DO skips the loop when the range is empty" ': T 5 5 ?DO I . LOOP ;
T' ' ok
 ok'

# A skipped loop pushes no parameters, so the definition still finds the
# address DOCOL saved and returns to its caller.
prints "a skipped ?DO leaves the return stack alone" ': T 5 5 ?DO LOOP 42 ;
T .' ' ok
42  ok'

# LEAVE under an IF is the case a list of unresolved branches exists for: on
# the control-flow stack its branch would sit on top of IF\'s, and THEN would
# resolve the wrong one. Both branches land where they should here.
prints "LEAVE inside IF ends the loop" ': T 10 0 DO I . I 2 = IF LEAVE THEN LOOP ;
T' ' ok
0 1 2  ok'

# Two of them in one body, each under its own IF. The 99 says the definition
# carried on after the loop rather than leaving it altogether.
prints "a loop may hold more than one LEAVE" \
  ': T 10 0 DO I . I 2 = IF LEAVE THEN I 5 = IF LEAVE THEN LOOP 99 . ;
T' ' ok
0 1 2 99  ok'

# LEAVE ends the loop it stands in and no other: the outer loop runs its second
# turn, where the inner one leaves after one number.
prints "LEAVE ends the inner loop only" \
  ': T 2 0 DO 5 0 DO I . J 1 = IF LEAVE THEN LOOP LOOP ;
T' ' ok
0 1 2 3 4 0  ok'

# LEAVE drops the loop parameters as UNLOOP does, so what follows the loop runs
# and the definition returns.
prints "LEAVE drops the loop parameters" ': T 10 0 DO LEAVE LOOP 42 ;
T .' ' ok
42  ok'

# ?DO closes with the same word DO does, and its branch past the loop is on the
# same list as the LEAVE, so both land after the LOOP.
prints "LEAVE works inside ?DO" ': T 10 0 ?DO I . I 3 = IF LEAVE THEN LOOP 88 . ;
T' ' ok
0 1 2 3 88  ok'

# A LEAVE with no loop to leave is refused where it is written. What it would
# otherwise compile drops two cells that are not loop parameters.
raises "LEAVE outside a loop is refused" 'LEAVE' "$CF"
raises "LEAVE in a definition with no loop is refused" ': T LEAVE ;' "$CF"

# An error abandons the definition, and the loop being compiled goes with it:
# the LEAVE on the next line has no loop to belong to either.
raises "an abandoned definition leaves no loop open" ': T 3 0 DO NOSUCHWORD LOOP ;
LEAVE' 'aforth: undefined word: NOSUCHWORD
aforth: unstructured control flow'

# Dispatching on a value. The three arms of one CASE, each printing something
# different, so an arm that ran and an arm that was skipped are told apart.
prints "CASE runs the arm that matches" \
  ': T CASE 1 OF ." one" ENDOF 2 OF ." two" ENDOF ." other" ENDCASE ;
1 T 2 T 9 T' ' ok
onetwoother ok'

# Nothing matches and there is no arm for it, so ENDCASE drops the value and
# the definition prints nothing at all.
prints "ENDCASE drops the value no arm matched" ': T CASE 1 OF ." one" ENDOF ENDCASE ;
9 T .S' ' ok
<0>  ok'

# An arm that matches drops the value itself, which is the DROP OF compiles
# after its branch. What the arm leaves is its own.
prints "a matched arm drops the value" ': T CASE 1 OF 42 ENDOF ENDCASE ;
1 T . .S' ' ok
42 <0>  ok'

# A CASE inside a CASE. Each ENDCASE stops on its own marker, so the inner one
# resolves the inner arms and leaves the outer arms alone.
prints "CASE nests inside CASE" \
  ': T CASE 1 OF 10 CASE 10 OF ." a" ENDOF ." b" ENDCASE ENDOF 2 OF 11 CASE 10 OF ." a" ENDOF ." b" ENDCASE ENDOF ." c" ENDCASE ;
1 T 2 T 3 T' ' ok
abc ok'

# IF ELSE THEN inside an arm resolves to that arm's THEN. A branch that reached
# ENDCASE instead would print nothing here and jump past the whole CASE.
prints "IF ELSE THEN nests inside an arm" \
  ': T CASE 1 OF 1 2 > IF ." x" ELSE ." y" THEN ENDOF ." d" ENDCASE ;
1 T 3 T' ' ok
yd ok'

# The default arm may read the value, because ENDCASE has not dropped it yet.
prints "the arm after the last ENDOF may read the value" \
  ': T CASE 1 OF ." one" ENDOF DUP 5 > IF ." big" ELSE ." small" THEN ENDCASE ;
1 T 9 T 2 T' ' ok
onebigsmall ok'

# A CASE inside a counted loop, with a LEAVE in one of its arms. The two
# mechanisms do not touch: the LEAVE ends the loop, not the CASE, and the CASE
# resolves its own arms off the control-flow stack.
prints "LEAVE inside a CASE arm ends the loop" \
  ': T 5 0 DO I CASE 3 OF LEAVE ENDOF I . ENDCASE LOOP 99 . ;
T' ' ok
0 1 2 99  ok'

raises "ENDOF refuses a number that is no place" '2 ENDOF'       "$CF"
raises "ENDCASE refuses a number that is no place" '1 2 ENDCASE' "$CF"

# The control-flow stack is the data stack, so a number left lying about looks
# exactly like a place to branch to. Each of these would write through an
# address of 2 and kill the process without the check.
raises "THEN refuses a number that is no place" '2 THEN'       "$CF"
raises "ELSE refuses a number that is no place" '2 ELSE'       "$CF"
raises "UNTIL refuses a number that is no place" '2 UNTIL'     "$CF"
raises "AGAIN refuses a number that is no place" '2 AGAIN'     "$CF"
raises "REPEAT refuses a number that is no place" '1 2 REPEAT' "$CF"
raises "LOOP refuses a number that is no place" '1 2 LOOP'    "$CF"
raises "+LOOP refuses a number that is no place" '1 2 +LOOP' "$CF"

# The other item DO leaves is the list of LEAVEs the loop has still to resolve,
# and LOOP writes through it, so a number there is refused as well.
raises "LOOP refuses a leave list that is no place" '2 HERE LOOP' "$CF"

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
