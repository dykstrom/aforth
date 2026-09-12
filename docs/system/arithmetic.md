# Arithmetic conventions

Forth-2012 leaves several arithmetic details to the implementation and asks
only that they be written down. These are aforth's, and the words are in
`src/interpreter.S`.

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
tests its divisor and takes the error path with `ERR_DIV_ZERO`. Until ticket
008 that path prints a message and exits; afterwards it will be `ABORT`.
Forth-2012 calls a zero divisor an ambiguous condition and permits exactly
this.

## A double is two cells, high one on top

`UM*`, `M*` and the double-dividend words keep the high cell above the low one,
so a case reading `0 1 3 UM/MOD` is the double 2^64 divided by 3.

ARM64 divides 64 bits by 64, not 128, so `UM/MOD` and its signed neighbours go
through `udiv128` in `src/interpreter.S`: one `udiv` when the high cell is
empty, and otherwise shift-and-subtract, sixty-four times. Ticket 012 may want
that faster.

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
same 128-bit division, so it would only be a wrapper. They also keep `DOCOL`
and `EXIT` exercised until `:` arrives in ticket 010.
