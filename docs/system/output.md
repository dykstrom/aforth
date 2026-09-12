# Output

How aforth writes text and formats numbers. The words are in
`src/interpreter.S`, the one routine that reaches libc is `write_stdout` in
`src/machine.S`, and the buffer they build numbers in is the pictured output
area of the region described in `src/include/machine.h`.

## One path, and no buffer

Every byte aforth prints goes through `write_stdout`: `write` on file
descriptor 1, one call per `EMIT`, per `TYPE`, per line of the banner. Nothing
is buffered, so there is no flushing rule to get wrong and no difference
between what a terminal sees and what a pipe sees. The test suite compares
captured output line by line for that reason.

fd 1 rather than stdio, because `stdout` is a libc variable whose symbol
differs between the platforms — `__stdoutp` on macOS, `stdout` on Linux — which
is the same reason errors go to fd 2 through `write_stderr`. `main` prints the
banner with `puts_stdout` rather than `puts` so that a buffered banner cannot
overtake an unbuffered number.

The cost is a `write` per character out of `EMIT`, `CR` and `SPACES`. `SPACES`
writes one space at a time rather than a run of them, because the only buffer
it could build a run in is the pictured output buffer, and `.R` calls `SPACES`
while holding the string `#>` just handed it. Ticket 012 is the place to price
all of this.

## Numbers are built in the hold buffer

`<# # #S HOLD SIGN #>` are the standard's own words and they work the standard's
own way: the buffer fills downward from its end, `UV_HOLD` in the user area is
the pointer, and `#>` reports the address and the length of what has
accumulated. The address is the pointer itself, so a string must be typed
before the next `<#` moves it.

`#` divides the double it is given by `BASE` in two steps, because the quotient
of a double is a double: the high half divides on its own, and its remainder
rides above the low half into `udiv128`. Dividing the low half alone would
overflow the quotient the moment the high half reached `BASE`.

A digit under ten is `0` to `9` and one over it is `A` to `Z`, so bases up to 36
print. `BASE` outside 2 to 36 is an ambiguous condition in Forth-2012, and
aforth does not range-check it, but neither of the two that would misbehave
gets away with it: a `BASE` of 0 raises the divide by zero every dividing word
raises, since `#` divides by it, and a `BASE` of 1 divides a number by itself
forever and ends in the pictured output overflow below rather than in a hang.
A `BASE` above 36 prints the characters that follow `Z` in ASCII.

### Overrunning the buffer is an error

The buffer is 4 KiB, which is 4096 digits against a cell's worst case of 64, so
only a runaway loop reaches the bottom of it. `HOLD` and `#` guard the pointer
with `HOLDROOM` and raise `ERR_HOLD_OVERFLOW`, which prints
`aforth: pictured output overflow`. Like `NONZERO`, that guard stays in the
build that compiles the stack guards out: it catches a real error, not a slip
in aforth's own bookkeeping.

## Every printing word follows BASE

`BASE` is a user variable: the word pushes the address of the cell and `@` and
`!` do the rest. `DECIMAL` and `HEX` write it directly, there being no literal
to compile until ticket 010.

`.`, `U.`, `.R` and `U.R` are token lists over the pictured output words, which
is what the standard's own definitions look like and what keeps them all
honest: there is one place a digit is made, and `#` reads `BASE` there.
`FALSE` stands in for the zero high half of a double in those lists, nothing
being able to compile a literal zero yet.

`.` and `U.` print a trailing space. `.R` and `U.R` pad on the left and print
nothing extra; a number already wider than the field is printed in full,
because `SPACES` does nothing with a count of zero or less.

`.S` is assembly, because it loops and there is no control flow until ticket
011, but it holds its digits through the same routine `#S` does, so it follows
`BASE` too. It prints the depth in angle brackets and then the items deepest
first, each followed by a space — `<3> 1 2 3 ` — the form gforth and SwiftForth
use. An item is printed as `.` prints it, sign and all, and an empty stack
prints `<0> `. It reads the items rather than popping them, so it leaves the
stack exactly as it found it.

## Where the tests are

The words' stack effects are in `word_tests`, which runs before the banner: a
case that printed would land above it. What they print is checked by
`test/run-tests.sh`, which feeds the binary Forth source and compares what comes
out.

Errors do not come this way. They go to file descriptor 2 through
`write_stderr`, and what each one says is in
[outer-interpreter.md](outer-interpreter.md).
