# 0016. Use the Forth-2012 THROW codes as error numbers

*2026-11-21*

## Context

aforth numbered its errors 1 to 21 in its own order. `CATCH` hands a program
the number of what failed, and Forth-2012 says a system that throws on a
condition in its table must use the code the table gives: -4 for a stack
underflow, -13 for an undefined word. The suite's Exception file checks -13.
One alternative kept the positive numbers inside aforth and translated them at
`CATCH` and `THROW`. That keeps two numberings in step for good, and a
program's `5 THROW` would collide with internal error 5 unless the mapping
covered every number in both directions.

## Decision

We will make every error number the code Forth-2012 gives the condition. A
condition the table has no code for takes a system code from -256 down, which
is the range the standard leaves to a system.

## Consequences

There is one number space. A word raises the number a program would see, and a
number a program throws is reported by the same routine. `quit_report` now
matches each number exactly instead of comparing ranges, so the order of the
numbers means nothing. A new error needs a compare and a message of its own. A
number with no message prints as `aforth: exception` and the number.

`ABORT` is -1 and `QUIT` is -56, so `-1 THROW` acts as `ABORT` and `-56 THROW`
acts as `QUIT`. `CATCH` must not catch -56. `QUIT` empties the return stack,
which takes every `CATCH` frame with it, so `CATCH` raises -56 again and it
reaches the loop.
