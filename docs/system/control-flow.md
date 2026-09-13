# Control flow

How a definition branches. The two branch primitives are in
`src/interpreter.S` with the rest of the inner interpreter, and the words that
compile them are in `src/words/control.S`. What `:` and `;` do around them is in
[compiling.md](compiling.md).

## The branch primitives

`(BRANCH)` and `(0BRANCH)` each take one cell out of the list they are running,
the way `(LIT)` does. That cell is a **distance in cells**, counted from the
token after it, so 0 carries straight on and a negative number jumps back. It is
not an address, which is what keeps a definition that branches as relocatable as
one that does not (ADR 0005).

`(BRANCH)` always jumps. `(0BRANCH)` pops a flag and jumps only when it is
false. Both are hidden, as `(LIT)` is: a programmer who typed one would jump by
whatever token came next.

Nothing compiles a branch but the words below, so the distance and the word that
writes it are never far apart.

## The control-flow stack

Forth-2012 allows the control-flow stack to be the data stack, and aforth uses
it. An item on it is the address of a cell in the dictionary — where a forward
branch's distance has still to be written, or where a backward branch is to
land. It is an address rather than an offset because it never leaves the data
stack and never reaches the dictionary.

| Word | Control-flow effect | What it compiles |
|------|--------------------|------------------|
| `IF` | ( -- orig ) | `(0BRANCH)` and a distance to fill in |
| `ELSE` | ( orig1 -- orig2 ) | `(BRANCH)` and a distance to fill in, then resolves orig1 |
| `THEN` | ( orig -- ) | nothing; resolves orig |
| `BEGIN` | ( -- dest ) | nothing |
| `UNTIL` | ( dest -- ) | `(0BRANCH)` back to dest |
| `AGAIN` | ( dest -- ) | `(BRANCH)` back to dest |
| `WHILE` | ( dest -- orig dest ) | `(0BRANCH)` and a distance to fill in |
| `REPEAT` | ( orig dest -- ) | `(BRANCH)` back to dest, then resolves orig |

Three routines in `src/words/control.S` do the writing, so the arithmetic for a
distance is in one place: `cf_forward` compiles a branch and a distance of 0 and
gives back where that 0 is, `cf_backward` compiles a branch that lands on a
given address, and `cf_resolve` fills in a 0 left by `cf_forward`.

`WHILE` leaves its two items the other way up from the order it built them,
because `REPEAT` wants to close the loop before it resolves the test.

## A number is not a place

Sharing the data stack means a plain number sitting on it looks exactly like a
place to branch to. `2 THEN` would otherwise store through address 2 and kill
the process, which no error in aforth is allowed to do.

So `cf_check` tests every item before anything is written through it: the
address must be a cell boundary, at or after the dictionary base, and no further
than `HERE`. Anything else raises `ERR_CONTROL_FLOW` — `aforth: unstructured
control flow`. The check runs before the word writes anything, so a definition
that fails is not left half-built by that word.

The check cannot catch everything. A number that happens to be a cell-aligned
address inside the dictionary passes it and branches somewhere meaningless.
Forth-2012 calls that an ambiguous condition, and aforth leaves it as one.

A definition whose `IF` never reaches a `THEN` is the other half of the same
thing. The distance stays 0, so the branch carries straight on, and the place to
write it stays on the data stack until the next error empties it.

## `EXIT` and `RECURSE`

`EXIT` is the same word it has always been — it pops the return stack — and
nothing about it changed here. Compiled inside a definition it leaves that
definition, which is how a program gets out of a `BEGIN AGAIN` loop.

`RECURSE` compiles the definition being written. Its own name cannot reach it:
`:` hides the entry until `;` unhides it, so a name inside a definition means
the word that was there before. `RECURSE` reads `LATEST` instead and works out
the code field's offset from it, which is the arithmetic the `HEADER` macro does
at assembly time and `dict_find` does at `df_found` — the third copy of it, and
the reason each carries a comment naming the others.

## What is not here

`DO LOOP +LOOP ?DO LEAVE UNLOOP I J` were cut from the epic: a counted loop
needs a loop-control stack, which is a second mechanism rather than more of this
one. `CASE OF ENDOF ENDCASE` are not implemented either.

## Where the tests are

`test/cases/control.sh`. A loop is checked by what it prints on each turn rather
than by the number it leaves, because a loop that ran once and a loop that ran
three times can leave the same number. The depth guards are in
`test/cases/guards.sh` with the rest, and `(0BRANCH)` is reached there through a
word that compiles it, being hidden.

Control flow is also why `test/run-tests.sh` runs the binary under a timeout: a
word can loop forever now, and one that does would hang the whole suite instead
of failing its own case. See [testing.md](testing.md).
