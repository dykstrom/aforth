# 0012. Keep a counted loop's parameters on the return stack

*2026-09-22*

## Context

`DO LOOP` needs somewhere to keep a limit and an index while the loop runs, and
three places were open. A stack of its own costs a new area in the region and a
register or a user variable to address it. The data stack puts the parameters
under everything the loop body pushes. The return stack is already there, grows
and shrinks with the definition being run, and already holds the address
`DOCOL` saved.

What the two cells hold was the second question. Plain cells hold the limit and
the index as they are. A biased index holds `index - limit + MIN-INT`, which
moves the boundary Forth-2012 defines for `+LOOP` onto the bit ARM64's `adds`
sets on signed overflow. The biased form saves two instructions on every turn
of a loop and costs two on every `I`, a difference below what
[dispatch-performance.md](../reference/dispatch-performance.md) can resolve.
With nothing to choose on speed, what the cells say to a reader decided it.

## Decision

We will keep a loop's parameters on the return stack, two cells per loop, the
limit underneath and the index on top. `(DO)` pushes them, `I` reads the top
cell, `J` reads two cells further down, and `UNLOOP` drops both. The turn that
ends the loop drops them itself.

## Consequences

A loop costs no area of the region and no register. `EXIT` can leave a
definition from inside a loop, because `UNLOOP` puts the return stack back the
way `EXIT` needs it. `+LOOP`, `?DO` and `LEAVE` extend the same frame.

Three things Forth-2012 leaves ambiguous now behave one particular way, and
aforth catches none of them. `I` inside a word called from a loop body reads
the address `DOCOL` saved for that word. `J` finds the loop outside this one
only while both loops are in the same definition. A `>R` still unbalanced when
`(LOOP)` runs leaves it reading the parked cell as the index.

`I` stays one load. The cost lands on `+LOOP`, which has to test for the
boundary crossing itself: a subtraction, an exclusive or and a sign test rather
than one flag. That test is exact for every loop that can finish. It is wrong
only for a loop that wraps the whole cell range without passing its limit,
which needs about 10^18 turns to reach.
