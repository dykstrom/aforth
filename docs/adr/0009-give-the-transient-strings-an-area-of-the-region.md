# 0009. Give the transient strings an area of the region

*2026-09-15*

## Context

Ticket 001 added `S"`. Typed at the prompt rather than compiled into a definition, it has to leave
the parsed bytes somewhere that outlives the words which follow it on the line. aforth carves one
anonymous mapping into fixed areas at start-up, and three places could have held them without a new
area.

`PAD` was the obvious one. It is 4 KiB, already carved, and no word writes it. Forth-2012 3.3.3.6
puts the contents of `PAD` under the complete control of the user, so no standard word may place
anything there. The pictured output buffer was the second. It holds a number while `<# ... #>`
builds one, and `.R` reads a string out of it across a call to `SPACES`, so it is live at times.
The third was `HERE`, which is where `WORD` copies its counted string. The next definition compiled
would overwrite it.

Forth-2012 11.3.4, in the File-Access chapter this epic implements, also requires at least two
buffers of at least 80 characters each, so that `S" a" S" b"` leaves both strings where they were
put. One shared buffer fails that wherever it lives.

## Decision

We will give the region a new area, `SBUF_OFF`, of 16 KiB. It holds four buffers of 4 KiB, which an
interpreted `S"` takes in turn. Each buffer is as large as the input buffer, and an assembly-time
check in `src/include/machine.h` fails the build if it is ever smaller.

## Consequences

A string parsed out of a line always fits a buffer whole, so `S"` needs no length test at run time
and no new error number. Four strings are live at once rather than the two the standard asks for.
That count is not a judgement about how many a program wants. `REGION_SIZE` must stay a whole
number of 16 KiB pages, so 16 KiB is the smallest area that keeps it one, and a buffer the size of
the input buffer divides it into four.

The region grew by 16 KiB of address space. Untouched pages of an anonymous mapping are never
faulted in, so a program that never types `S"` pays nothing for them. A saved image will carry the
area when warm start lands. Two more cells are fixed in the user area, `UV_SBUF` and
`UV_SBUF_NEXT`.

One constraint follows for later work. The input buffer may not grow past a transient buffer.
Tickets 002 and 005 give an included file an input source of its own, and if one of those gets a
line buffer larger than 4 KiB, the check fires and both sizes have to move together.
