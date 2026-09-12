# Input

How a line reaches aforth. The words are in `src/interpreter.S`, the two
routines that call the library and the terminal are `read_line` and `read_byte`
in `src/machine.S`, and the buffer they fill is the input area of the region
described in `src/include/machine.h`.

## The buffer and the three user variables

Ticket 001 carved a 4 KiB input buffer and three cells in the user area
describe it: `UV_TIB` is its address, `UV_TIB_LEN` how many bytes the last line
put there, and `UV_TO_IN` how far a parser has read. `SOURCE` reports the first
two and `>IN` hands out the address of the third. Ticket 007 is the first thing
that moves the offset; until then it is 0 whenever anything looks.

`REFILL` puts the offset back to 0 on every line, which is what the standard
requires of it, and sets the length to 0 at end of input so there is nothing
left to parse.

## libedit, through readline's API

`readline` does the editing, the history and the terminal handling, and it is
called through libedit's readline-compatible API — never the native `el_*` one,
whose `el_set` is variadic and would need different code per platform
(ADR 0001). The line comes back `malloc`'d without its newline and is freed in
`read_line`.

The library is `-ledit`, in the Makefile's `LDLIBS`.

It is linked dynamically on both platforms. macOS has libedit at
`/usr/lib/libedit.3.dylib`, so nothing is needed to build or to run. On Linux
the build needs `libedit-dev` and a machine that only runs the binary needs
`libedit2`, which is a different package: without it the dynamic loader fails
before `main` with `libedit.so.2: cannot open shared object file`, and aforth
never gets to report it. A binary built in `docker/Dockerfile` therefore does
not start on a stock Debian. What a release could do about that is in
[working-notes/shipping-a-linux-binary.md](../working-notes/shipping-a-linux-binary.md).

`REFILL` puts each non-empty line in the history. `ACCEPT` puts none there: a
program reading data is not a command the user typed.

`main` calls `setlocale(LC_CTYPE, "")` before `machine_init` and so before any
libedit call, as ADR 0004 requires. Without it the process runs in the C locale
and editing treats each byte of a multi-byte character as a character.

## KEY reads one byte in raw mode

`KEY` clears `ICANON` and `ECHO`, reads one byte from file descriptor 0, and
puts the terminal back as it found it. That is what makes it return on the
keystroke instead of at the end of a line, and what keeps the byte off the
screen. `struct termios` differs between the platforms in size, in the offset
of `c_lflag` and in the value of `ICANON`, so the four numbers live in
`src/include/platform.h`.

`tcgetattr` fails when stdin is not a terminal, and `KEY` then does the plain
one-byte read, which is what a piped script needs. At end of input `KEY` gives
-1, which is not a character: the standard leaves it no way to report one.

`KEY` and `REFILL` can be mixed. `KEY` reads the descriptor directly while
`REFILL` goes through libedit, and libedit stops at the newline and keeps
nothing back, so a `KEY` after a `REFILL` gets the next byte of the stream.
That was measured on macOS and on Linux; no API promises it, so a change of
library is a reason to measure it again.

## Two limits

A line longer than the 4 KiB buffer raises `ERR_LINE_TOO_LONG`, which prints
`aforth: input line too long`. `REFILL` is given the untruncated length for
that purpose. Half a line is valid Forth missing its tail, which is worse than
an error. A line of exactly 4096 bytes is accepted.

`ACCEPT` truncates instead of raising, because receiving at most the count it
was given is the word's own contract. It returns how much it took, so a caller
can see the truncation.

## Who calls REFILL

`machine_quit` in `src/outer.S`, once per line, through `machine_refill`. A
false flag is end of input and ends the session. See
[outer-interpreter.md](outer-interpreter.md).

`REFILL` pushes a flag, so it needs one free cell on the data stack. The stack
area holds 8192 cells, and a line can therefore leave at most 8191 of them
occupied. A line that fills the stack to the brim still reports `ok`, and the
`REFILL` starting the next line then raises `ERR_DS_OVERFLOW` before it reads
anything: the message arrives after the line that caused it and names no word.
`test/cases/guards.sh` counts the lines that reported `ok` for that reason, the
message alone being unable to say which guard fired.

A case for `REFILL`, `ACCEPT` or `KEY` is in `test/cases/input.sh`, and it is
written knowing what the suite pipes in: the word reads the rest of the case's
own source, so the case carries the line it will read. See
[testing.md](testing.md).
