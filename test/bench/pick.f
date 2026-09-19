\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykstrom
\
\ aforth's second benchmark: a loop built around PICK and ROLL.
\
\ It exists because the stack guards are not all the same. A word that reads
\ the data stack pays NEED, which is a load, a subtract and a compare against
\ a constant. PICK and ROLL cannot: the depth they require is whatever number
\ the user put on the stack, so they pay NEED 1 first and then NEEDX, which
\ computes the depth in full and compares it against a register. Pricing the
\ guards on test/bench/mix.f alone would measure NEED and call it the answer.
\
\ The loop is 27 words long. Seven of them are guarded by NEEDX:
\
\    5 PICK   at depths 4 3 2 1 0, each behind a literal
\    2 ROLL   1 ROLL twice, which is SWAP twice and so leaves the stack alone
\   20 other  the seven literals, the six operators, R@ >R R> 1- DUP 0=
\             and the branch UNTIL compiles
\
\ Five working values sit under the counter and stay five: every PICK has an
\ operator behind it that consumes what it pushed, and 1 ROLL twice is SWAP
\ twice. The top value goes through a chain of reversible steps and is mixed
\ with the counter, so it ends up depending on every iteration rather than on
\ the last few; the four under it never change. Five numbers printed, four of
\ them 4 3 2 1, is therefore a check on the depth as well as on the work.
\
\ words-per-iteration: 27
\
\ The count comes from ITERS, which test/bench/run-bench.sh writes ahead of
\ this file. The answer is printed behind a # so that the harness can find
\ it whatever banner the system wrote first. See docs/system/benchmark.md.

: BENCH ( n -- a b c d e )
  1 2 3 4 5 5 ROLL              \ five values, with the count back on top
  BEGIN
    >R
    4 PICK + 3 PICK XOR 2 PICK + 1 PICK XOR 0 PICK DROP
    R@ XOR
    1 ROLL 1 ROLL
    R> 1- DUP 0=
  UNTIL
  DROP ;

ITERS BENCH
CR 35 EMIT . . . . . CR
