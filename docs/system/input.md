# Input

How a line reaches aforth. The words are in `src/words/input.S`, the two
routines that call the library and the terminal are `read_line` and `read_byte`
in `src/machine.S`, and the buffer they fill is the input area of the region
described in `src/include/machine.h`.

## The seven user variables, and the stack of sources under them

Four cells describe the source being read now. `UV_TIB` is its address,
`UV_TIB_LEN` how many bytes it holds, `UV_TO_IN` how far a parser has read, and
`UV_SOURCE_ID` where it came from — 0 the terminal, -1 a string, or a fileid.
`SOURCE` reports the first two, `>IN` hands out the address of the third and
`SOURCE-ID` the value of the fourth.

Three more ride along so that an error inside an included file can say where it
happened. `UV_SRC_LINE` is which line of the file the level is on, and
`UV_SRC_NAME` and `UV_SRC_NAME_LEN` are the name it was opened by. `REFILL`
counts the lines and `include_impl` sets the name. A terminal or a string level
leaves all three at 0, and no word reads any of them.

A source pushed on top of another saves those seven cells into a slot in the
user area and installs its own. `src_push`, `src_pop`, `src_restore` and
`src_reset` in `src/words/input.S` are the only routines that touch the stack of
saved ones, so every word that parses reads the same cells however deep the
nesting goes, and `>IN` hands out one fixed address — which it must, because a
program may store through it. The slot layout and the level count are in
`src/include/machine.h`.

A ninth level is `ERR_SOURCE_TOO_DEEP`, which prints `aforth: input sources
nested too deep`. `src_push` reports that number rather than raising it, because
`include_impl` opens the file before it pushes and a raise would leave that file
open with nothing holding its descriptor.

A file level's line buffer is not in the region at all. `include_impl` takes it
from its own C stack frame, whose life is exactly the life of the level. See
[files.md](files.md).

`REFILL` puts the offset back to 0 on every line, which is what the standard
requires of it, and sets the length to 0 at end of input so there is nothing
left to parse.

## `EVALUATE`, and why the machine nests

`EVALUATE` makes a string the input source, interprets it, and puts the source
back. Forth-2012 makes the string "both the input source and input buffer", so
nothing is copied and a string level needs no buffer of its own — it points
straight at the caller's bytes. A file level cannot do that, and takes its
buffer from `include_impl`'s frame.

It has to interpret **and return**, so that the word after it in a definition
runs afterwards. `: F S" 1 2 +" EVALUATE . ;` must have run the string before
the `.` does. So a word interprets from inside a word, and `aforth_enter` had to
learn to nest: it saves the entry below it in its own frame, both the `UV_STOP_SP`
that entry left and its `IP`, because that entry is part of the way through a
token list and this one is about to point `IP` at another. Nothing else is
saved. The stacks are shared on purpose — `EVALUATE`'s stack effect is `i*x` to
`j*x` — and `W` is scratch.

The interpreting itself is `interpret_source` in `src/outer.S`, which the `QUIT`
loop calls too. It returns every error and raises none, and
[outer-interpreter.md](outer-interpreter.md) says why. `EVALUATE` pops its
source first and raises afterwards, so an error, an `ABORT` or a `QUIT` inside a
string reaches the loop the way it would from any word. `include_impl` does the
same for a file, and any later word that installs a source must pop it the same
way, before it passes an error on, or the source stays stacked.

That popping is also what unwinds the stack after a failure: the error comes
back to each `EVALUATE` in the chain as a number and each pops its own source.
`src_reset` in `machine_quit` makes the invariant true at the one place that
restarts the loop, and no case in the suite can reach it. It closes any fileid
still stacked as well as dropping the levels.

## `REFILL` has three arms, and `refill_impl` is where they are

`UV_SOURCE_ID` says where the next line comes from. 0 is the terminal, -1 is a
string, and anything else is a fileid.

| Source | What `REFILL` does |
|--------|--------------------|
| the terminal | `read_line`, through libedit |
| a string | returns false and touches nothing |
| a file | `file_read_line`, and adds 1 to `UV_SRC_LINE` |

The body is `refill_impl`, a routine rather than only the word, because
`include_impl` and `(` both need to refill without running a token list. It
returns the flag in x0 and an error number in x1 and raises nothing. The
`REFILL` word turns that number into a raise. `include_impl` turns it into its
own error path, which it must: a raise from inside would unwind past the frame
holding the file's line buffer before the file is closed.

A read that fails ends a file source rather than reporting. Forth-2012 makes an
I/O exception while reading an included file an ambiguous condition, and an
invalid fileid handed to `INCLUDE-FILE` is the way to reach it. That include
finishes having interpreted nothing.

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

`REFILL` puts each non-empty line in the history, and only at the terminal:
`read_line`'s third argument says whether the user typed it, and only the
terminal's arm passes 1. `ACCEPT` puts none there either — a program reading
data is not a command the user typed.

A string has no next line, so Forth-2012 asks `REFILL` to return false for one
and do nothing else at all. It must not zero the length, which would destroy the
string it is being asked to leave alone.

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
an error. A typed line of exactly 4096 bytes is accepted.

A file line gets the same answer by a different test, and the two disagree on
one length. `file_read_line` returns at most what it was given and reports in
x3 whether a newline ended the line, so a full buffer that no newline ended is
what `refill_impl` raises on. It cannot see the newline one byte past the
buffer, so a **file** line of exactly 4096 bytes raises where a typed one of
that length does not. The line is counted before it is measured, so the message
names the line that was too long rather than the one before it.

`ACCEPT` truncates instead of raising, because receiving at most the count it
was given is the word's own contract. It returns how much it took, so a caller
can see the truncation.

## Who calls REFILL

`machine_quit` in `src/outer.S`, once per line, through `machine_refill`. A
false flag is end of input and ends the session. See
[outer-interpreter.md](outer-interpreter.md). A program may call it itself, and
inside a string it gets false.

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
