# 0008. Leave the Forth machine through one vector

*2026-09-11*

## Context

Ticket 001 put a vector in `UV_ABORT` and pointed the stack guards at it; `abort_stub` printed a
message and exited the process. Ticket 008 has to turn that into an error path that reports and
carries on, and to add `ABORT` and `QUIT`. Those two are not failures, but they share the failures'
problem: neither may return to the word that ran it, and a primitive normally ends with `NEXT`,
which runs the next token in the list. `aforth_enter` already had the mechanism — a routine that
branches to `enter_return` leaves the machine carrying any value in x0, which is how `selftest.S`
catches an abort. The alternative was a second unwind path for `ABORT` and `QUIT`: each emptying
the stacks itself and branching to a label in the loop. That means `src/outer.S` exporting a label
for words to jump into, two ways of putting `sp` back, and two places that reset the stacks. A
further choice was where to print: `abort_stub` printed inside the handler, which would make a word
test that expects an error print a message, and would build the message in a routine that does not
know which word failed.

## Decision

We will give `ABORT` and `QUIT` error numbers of their own, `ERR_ABORT` and `ERR_QUIT`, and send
every exit from the machine — guard, raising word, `ABORT`, `QUIT` — through the vector in
`UV_ABORT` and out of `aforth_enter`. The handler carries the number and prints nothing;
`machine_quit` reads it and decides what to empty and what to say.

## Consequences

There is one place that resets the stacks and one that prints, so a message and a reset cannot
disagree. `word_tests` catches `ABORT` and `QUIT` with the case shape it already had for a divide
by zero, by naming the number the case expects, and stays silent while doing it. `selftest.S` keeps
catching everything by putting its own routine in the vector.

The cost is a constraint on where a guard may be used. `enter_return` puts `sp` back to
`UV_STOP_SP`, the frame of the last `aforth_enter`, so code running outside the machine cannot use
`NEED` or `ROOM`: the frame they would return to is gone. `machine_quit` makes its own comparison
against `UV_DS_LO` before it pushes a number a name converted to. Any later routine that runs
outside `aforth_enter` has the same problem.

`UV_STOP_SP` is one cell, so one level of `aforth_enter` is open at a time. A word that runs the
interpreter from inside the machine — `EVALUATE`, an init file, `CATCH` — has to make that cell a
stack of frames first.
