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
false. `(LOOP)`, `(+LOOP)` and `(?DO)` take a distance in the same shape; they
are under [the counted loop](#the-counted-loop) below, because each reads the
return stack as well. All of them are hidden, as `(LIT)` is: a programmer who
typed one would jump by whatever token came next.

Nothing compiles a branch but the words below, so the distance and the word that
writes it are never far apart.

## The control-flow stack

Forth-2012 allows the control-flow stack to be the data stack, and aforth uses
it. An item on it is the address of a cell in the dictionary — where a forward
branch's distance has still to be written, or where a backward branch is to
land. It is an address rather than an offset because it never leaves the data
stack and never reaches the dictionary.

A counted loop leaves a second item under that one, the list of `LEAVE`s the
loop outside it is still collecting. That one is not a place at all; it is
described under [the counted loop](#the-counted-loop).

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
| `DO` | ( -- leave-sys dest ) | `(DO)` |
| `?DO` | ( -- leave-sys dest ) | `(?DO)` and a distance on the leave list |
| `LOOP` | ( leave-sys dest -- ) | `(LOOP)` back to dest, then resolves the list |
| `+LOOP` | ( leave-sys dest -- ) | `(+LOOP)` back to dest, then resolves the list |
| `LEAVE` | ( -- ) | `UNLOOP`, `(BRANCH)` and a distance on the list |
| `CASE` | ( -- case-sys ) | nothing |
| `OF` | ( -- of-sys ) | `OVER`, `=`, `(0BRANCH)` and a distance, then `DROP` |
| `ENDOF` | ( case-sys1 of-sys -- case-sys2 ) | `(BRANCH)` and a distance to fill in, then resolves of-sys |
| `ENDCASE` | ( case-sys -- ) | `DROP`, then resolves every of-sys above the marker |

Three routines in `src/words/control.S` do the writing, so the arithmetic for a
distance is in one place: `cf_forward` compiles a branch and a distance of 0 and
gives back where that 0 is, `cf_backward` compiles a branch that lands on a
given address, and `cf_resolve` fills in a 0 left by `cf_forward`.

`WHILE` leaves its two items the other way up from the order it built them,
because `REPEAT` wants to close the loop before it resolves the test.

## The counted loop

`DO` and `LOOP` are shaped like `BEGIN` and `UNTIL`. `DO` compiles `(DO)` and
leaves the place a turn of the loop starts; `LOOP` compiles `(LOOP)` and a
backward distance to it, through the same `cf_backward` every other backward
branch uses. `cf_check` guards that `dest` exactly as it guards `UNTIL`'s.

`DO` leaves one more item under it, and `LOOP` takes both. That second item is
the list of unresolved `LEAVE`s belonging to the loop this one is inside of,
and [leaving a loop early](#leaving-a-loop-early) below says what it is for.

The loop's parameters live on the **return stack**, two cells per loop: the
limit underneath and the index on top. `(DO)` puts them there, `I` reads the
top cell, `J` reads two cells further down, and `UNLOOP` drops both.

```
RSP+0    inner index     what I and (LOOP) read
RSP+8    inner limit     what (LOOP) compares against
RSP+16   outer index     what J reads
RSP+24   outer limit
RSP+32   the IP DOCOL saved for the definition
```

The index is on top because `I` and `(LOOP)` read it far more often than
anything reads the limit. They are two plain cells rather than a biased index —
the index held as `index - limit + MIN-INT`, so that the standard's loop
boundary lands on the hardware's signed-overflow bit. That form buys two
instructions a turn and costs two on every `I`, which is below what
[dispatch-performance.md](../reference/dispatch-performance.md) can measure.

Sharing the return stack is what makes a loop cost no area of its own, and it
is where three ambiguous conditions come from. Forth-2012 leaves all three
ambiguous, and aforth leaves them as they are rather than spending a cell on
catching them:

- `I` inside a word *called* from a loop body reads the address `DOCOL` saved
  for that word and not the index. The same goes for `J` and a loop nested
  inside a called word: the call puts a cell between the two frames.
- `EXIT` inside an unfinished loop returns to a loop parameter. `UNLOOP` before
  it is what makes an early return work, and is the reason `UNLOOP` exists.
- A `>R` still unbalanced when `(LOOP)` runs leaves it reading the parked cell
  as the index. A `>R` and its `R>` belong in the same breath.

`(LOOP)` tests for equality, which is what Forth-2012 asks for: add one to the
index and leave when it equals the limit. So a loop whose limit is its starting
index does not run no times — `0 0 DO LOOP` counts the whole cell range before
the index meets 0 again. `?DO` is the standard's word for the other reading,
and aforth has not got it yet.

The turn that ends the loop drops both parameters, so a loop that runs out
needs no `UNLOOP` after it.

`+LOOP` takes a signed step off the data stack instead of adding one. It cannot
test for equality, because a step over one steps past the limit without ever
meeting it. Forth-2012 puts the end of the loop at the boundary between
`limit - 1` and `limit` and asks whether the step carried the index over it,
and `(+LOOP)` asks the same question the other way round: it subtracts the
limit from the index before and after the step and ends the loop when those two
differ in sign. A negative step therefore counts down to the limit and stops on
it, where `LOOP` would run past.

`?DO` is the loop that runs no times over an empty range. `(?DO)` compares the
limit with the starting index, and pushes nothing and jumps past the whole loop
when they are equal. That forward distance is written by the `LOOP` or `+LOOP`
that closes the loop, because where the loop ends is not known until then.

## Leaving a loop early

`LEAVE` drops the loop parameters and branches past the closing word. It
compiles `UNLOOP` for the first half, so one word takes a loop's parameters off
the return stack.

The second half is the awkward one. A `LEAVE` may stand anywhere in the body
and appear any number of times, and only the closing `LOOP` knows where its
branch lands. That place to write cannot wait on the control-flow stack: the
control-flow stack is the data stack, and in `IF LEAVE THEN` the `LEAVE` would
push its branch on top of `IF`'s. `THEN` resolves whatever is on top, so it
would point the `LEAVE` at itself and leave `IF`'s branch unresolved.

So the places to write are a list, threaded through the very cells the
distances go in. Each cell holds the offset of the cell before it until the
closing word writes the real distance over it, so the list costs no memory of
its own and nothing absolute is written into the dictionary (ADR 0005).
`?DO`'s branch over the loop is on the same list, because it lands in the same
place.

`UV_LEAVE` is the head of the list, and holds three kinds of value:

| Value | Means |
|-------|-------|
| -1 | no loop is being compiled |
| 0 | a loop is open and nothing is on its list |
| an offset | the newest cell waiting for a distance |

`DO` and `?DO` push the old head on the control-flow stack and start an empty
list, and the closing word puts it back, so a loop inside a loop keeps a list
of its own. `cf_leave_check` guards the head on the way back for the reason
`cf_check` exists: the next `LOOP` writes through the list.

`machine_quit` puts `UV_LEAVE` back to -1 when it abandons a definition, beside
the `STATE` it clears there, so an error inside a loop does not leave the system
believing one is open.

The -1 is also what lets `LEAVE` refuse a definition with no loop in it.
Forth-2012 calls that an ambiguous condition and allows a system to do as it
likes, but what aforth would otherwise compile is dangerous: the `UNLOOP` would
drop two cells that are not loop parameters, its guard would pass because two
cells are there, and the `EXIT` at the end of the definition would return into
a data cell. So `LEAVE` raises `ERR_CONTROL_FLOW` instead, where the programmer
wrote it.

## Dispatching on a value

`CASE` leaves a marker on the control-flow stack, each `OF` compiles a test
that falls through to the next arm when it does not match, each `ENDOF` ends an
arm with a branch to the end, and `ENDCASE` points every one of those branches
at what follows it.

`OF` compiles the standard's own definition of itself, `OVER = IF DROP`. The
`DROP` goes after the branch's distance, so it runs on a match and not on a
miss, and the value stays on the stack for the next arm to test. `ENDOF` is
`ELSE` — the same routine does both, and Forth-2012 defines it that way.

This is what one `CASE` compiles to:

```
(LIT) 1  OVER  =  (0BRANCH) a1   DROP  (S") "one" TYPE  (BRANCH) e1
a1 lands here
(LIT) 2  OVER  =  (0BRANCH) a2   DROP  (S") "two" TYPE  (BRANCH) e2
a2 lands here
(S") "other" TYPE
DROP                                   the value no arm matched
e1 and e2 land here
```

The branches `ENDCASE` resolves wait on the control-flow stack, above the
marker, which is where a `LEAVE`'s branch cannot wait. The difference is that an
`ENDOF` always closes at the depth the `ENDOF` before it closed at, so nothing
belonging to an arm can come between two of them, and `ENDCASE` walks them in
one run. A `CASE` inside a loop and a `LEAVE` inside one of its arms therefore
do not touch: the `LEAVE` is on the loop's list and ends the loop, and the arms
are on the control-flow stack.

The marker is 0, which `cf_check` rejects as a place, so `ENDCASE` can tell it
from an arm without a second kind of item. A `CASE` inside a `CASE` leaves a
marker of its own, and each `ENDCASE` stops on the nearest one.

`ENDCASE` is the one word here that compiles before it checks. It has no
choice: the branches must land after the `DROP` it compiles, and how many of
them there are is not known until the stack is walked. Each place is still
checked before `ENDCASE` writes through that place, and the depth is checked on
every turn, so a stack that runs out reports rather than reading past its end.

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
the reason each carries a comment naming the others. `:NONAME` builds an entry
too, with a name of no bytes, so `RECURSE` works in a definition with no name
as it does in a named one.

## What is not here

Nothing is. Every control-flow word of Forth-2012's CORE and CORE-EXT sets is
here.

Two things a reader may come looking for are elsewhere. `?OF` is not in the
standard, so aforth does not have it. `[IF] [ELSE] [THEN]` choose what the text
interpreter reads rather than what a definition runs; they belong to the
TOOLS-EXT word set and not to this file.

## Where the tests are

`test/cases/control.sh`. A loop is checked by what it prints on each turn rather
than by the number it leaves, because a loop that ran once and a loop that ran
three times can leave the same number. The depth guards are in
`test/cases/guards.sh` with the rest, and `(0BRANCH)` is reached there through a
word that compiles it, being hidden.

Control flow is also why `test/run-tests.sh` runs the binary under a timeout: a
word can loop forever now, and one that does would hang the whole suite instead
of failing its own case. See [testing.md](testing.md).
