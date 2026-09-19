\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykström
\
\ aforth's dispatch benchmark: a mix of stack and arithmetic words.
\
\ The loop is 23 words long and every one of them is a handful of
\ instructions, so almost all of what it measures is dispatch rather than
\ the work being dispatched to. That is the point: it is the most sensitive
\ body available for pricing the inner interpreter, and therefore an upper
\ bound on what a change to dispatch buys real code.
\
\   12 stack words  >R OVER DUP ROT SWAP OVER TUCK DUP SWAP OVER R> DUP
\   10 arithmetic   XOR + 1+ AND - 1- OR * 1- 0=
\    1 control      the branch UNTIL compiles
\
\ The body is depth-neutral and its two values change every iteration, so
\ the two numbers printed at the end are a checksum: every system and every
\ variant build must print the same pair, or it did not run the same work.
\
\ words-per-iteration: 23
\
\ The count comes from ITERS, which test/bench/run-bench.sh writes ahead of
\ this file. The answer is printed behind a # so that the harness can find
\ it whatever banner the system wrote first. See docs/system/benchmark.md.

: BENCH ( n -- x y )
  12345 67 ROT                  \ two seeds, with the count back on top
  BEGIN
    >R
    OVER XOR DUP ROT + SWAP 1+ OVER AND
    TUCK - DUP 1- OR SWAP OVER *
    R> 1- DUP 0=
  UNTIL
  DROP ;

ITERS BENCH
CR 35 EMIT . . CR
