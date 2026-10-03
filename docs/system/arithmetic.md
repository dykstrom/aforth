# Arithmetic conventions

Forth-2012 leaves several arithmetic details to the implementation and asks
only that they be written down. These are aforth's, and the words are in
`src/words/arithmetic.S`.

## Division rounds toward zero

`/`, `MOD`, `/MOD`, `*/` and `*/MOD` all truncate, so the remainder takes the
sign of the dividend: `-22 7 /` is `-3` and `-22 7 MOD` is `-1`. That follows
from using the `sdiv` instruction, and Forth-2012 allows either convention as
long as one system uses one of them throughout.

`SM/REM` is the symmetric division the standard names, and matches the words
above. `FM/MOD` is the floored one: `-7 2 FM/MOD` gives `1 -4` where
`-7 2 SM/REM` gives `-1 -3`. It is implemented as symmetric division plus a
correction, applied when the operands differ in sign and the division was not
exact.

`2/` is an arithmetic shift, as the standard requires, so it floors where `2 /`
truncates: `-1 2/` is `-1`, but `-1 2 /` is `0`.

## Dividing by zero is an error

ARM64 division by zero yields zero and raises nothing, so every dividing word
tests its divisor and raises `ERR_DIV_ZERO`, which prints `aforth: divide by
zero` and empties both stacks as any other error does. Forth-2012 calls a zero
divisor an ambiguous condition and permits exactly this.

## A double is two cells, high one on top

`UM*`, `M*` and the double-dividend words keep the high cell above the low one,
so a case reading `0 1 3 UM/MOD` is the double 2^64 divided by 3.

`S>D` makes a double from a single. The single is the low cell, and the high
cell is its sign copied into every bit, which one arithmetic shift gives.

`2!` and `2@` put the item that was on top at the lower address, as Forth-2012
requires. So a double stored with `2!` has its high cell first in memory, and
`2@` reads it back in the same order.

ARM64 divides 64 bits by 64, not 128, so `UM/MOD` and its signed neighbours go
through `udiv128` in `src/words/arithmetic.S`: one `udiv` when the high cell is
empty, and otherwise Knuth's algorithm D on 32-bit digits, which is two more
`udiv`s and at most two corrections apiece.

The divisor is normalised so that its top digit has its high bit set. That is
what bounds a trial digit to one digit and a correction to two steps, and it is
why the remainder comes out needing a shift back.

aforth does not call the compiler's own 128-bit division. `__udivti3` is
compiler-rt rather than libc, so it is a different library on each platform.
It also computes a full 128-bit quotient, where aforth needs only one that fits
a cell. Timed against each other in C, the runtime call costs about 9.9 ns and
this algorithm about 8.6.

It replaced a loop that shifted and subtracted sixty-four times. On a `*/` whose
product overflows a cell, called in a loop, that took the call from 42.4 ns to
11.6 ns; the digit-at-a-time path adds about 1.5 ns where the old one added
about 31. The same loop with operands whose product fits a cell is unchanged at
about 10 ns, because it never leaves the single `udiv` in front. Measured with
`test/bench/run-bench.sh` on two builds of this loop, five passes each:

```forth
: BENCH ( n -- x )
  0 SWAP
  BEGIN
    >R  1000000000000 1000000000000 999999999999 */  +
    R> 1- DUP 0=
  UNTIL DROP ;
```

A quotient too big for a cell is an ambiguous condition, which reaches `udiv128`
as a high cell no smaller than the divisor. What comes out is whatever the
algorithm makes of it, as it was before, and it still comes out: every
correction adds the divisor's top digit to the running remainder, and two of
those carry it past the point that ends the loop.

## Flags are all bits, shifts are not masked

A true flag is `-1`, every bit set, which is what `csetm` writes. `TRUE` and
`FALSE` push those.

`LSHIFT` and `RSHIFT` pass the count to the instruction, which reads only its
low six bits, so `1 64 LSHIFT` is `1` here rather than `0`. Forth-2012 calls a
count of a cell's width or more an ambiguous condition, so this is conforming
but it is not portable, and a program should not rely on it.

## Two words are token lists, not assembly

`*/` and `*/MOD` are defined as lists of tokens over `M*` and `SM/REM`. That is
not for want of an instruction: both multiply to a double and divide that
double, which is what keeps `n1 n2 */ n3` exact when the product overflows a
cell, and it is what the standard specifies. A primitive would have to call the
same 128-bit division, so it would only be a wrapper.
