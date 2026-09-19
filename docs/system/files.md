# Files

How aforth opens and reads a file. The words are in `src/words/file.S`, the four
routines that reach libc are `file_open`, `file_read`, `file_seek` and
`file_close` in `src/machine.S`, and the platform differences they need are in
`src/include/platform.h`.

This is the reading half of the optional File-Access word set, the four words
that ask a file about itself, and the three that read a program out of one.
Writing, creating and deleting are not implemented, and neither is `BIN`, there
being no binary access method to modify. `REQUIRE` and `REQUIRED` are not
either, so nothing tracks what has already been loaded. `FILE-STATUS` is from
the extension set rather than the main one, as `.S` and `WORDS` are from
Programming-Tools.

## A fileid, a fam and an ior

A **fileid** is the descriptor `open` returned. A descriptor is never 0, 1 or 2
as long as the process was given its three standard ones, which is what
`SOURCE-ID` needs: it has to tell a file from the 0 that means the terminal.
aforth does not check. A process started with file descriptor 0 closed would
give its first file the fileid 0, and that process has no terminal to confuse it
with.

A **fam** is the flag word `open` takes. `R/O` is `O_RDONLY`, which is 0 on both
platforms. Making a fam the flag itself is what will make `W/O` and `R/W` one
constant each when writing lands.

An **ior** is 0 or an `errno`. Forth-2012 leaves an ior implementation-defined,
and an `errno` is a number a person can look up. `ENOENT` is 2 and `EBADF` is 9
on both platforms, so the cases assert those as plain numbers.

No file word raises, with one exception. Each reports on the stack and the
program decides. `INCLUDED` and `INCLUDE` are the exception, because their stack
effects have no ior to report with, so a file that will not open raises
`ERR_OPEN_FAILED`. See [outer-interpreter.md](outer-interpreter.md).

## `READ-LINE` reads ahead and seeks back

There is no buffer. ADR 0007 keeps aforth holding none, and reading through
stdio would have been the first buffering in the system. So `READ-LINE` reads a
whole buffer's worth, looks for the newline itself, and puts the file position
back to just after it:

```
  read(fd, c-addr, u1)             -> n bytes
  scan the n bytes for 0x0a        -> found at index i
  lseek(fd, i + 1 - n, SEEK_CUR)   -> back over what came after it
```

Two system calls a line, and no state anywhere. The kernel's file position is
the only position there is, so `FILE-POSITION` will be right without
subtracting what was read but not yet given out — which is what a buffer would
have cost.

The four ways it can end are four sentences of Forth-2012.

| What arrived | u2 | flag | ior |
|--------------|----|------|-----|
| nothing | 0 | false | 0 |
| a newline at index i | i | true | 0 |
| the buffer filled, no newline | u1 | true | 0 |
| fewer than u1, no newline | what arrived | true | 0 |

The third is "when u1 = u2 the line terminator has yet to be reached", and the
next call carries on inside the same line. The fourth is the last line of a file
that does not end in one: it is a successful read, and the call after it is the
one that reports the end.

A carriage return immediately in front of the newline goes with it. The standard
allows up to two line-terminating characters and lets a program depend on
neither being left in the buffer, so a file edited on Windows gives the same
lengths as one edited here rather than failing on a word with an invisible
character stuck to it. A carriage return anywhere else is an ordinary character.

`file_read` calls `read` again until the buffer is full or `read` returns 0, so
a short read cannot be mistaken for the end of a line. `READ-FILE` is that loop
and nothing else.

## Asking a file about itself

A size and a position are doubles, which Forth-2012 requires. A cell is 64 bits
here, so every position a file can have fits the low half and the high half is
always 0 coming out. Both are pushed anyway, because the stack effect is the
contract, and a double is `( lo hi )` with the high half on top — the order `M*`
leaves one in.

`FILE-POSITION` is one seek from where the file stands. `REPOSITION-FILE` is one
from the start, and a high half that is not 0 names a position no `off_t` holds:
it reports `EINVAL`, which is 22 on both platforms, rather than truncating the
number and seeking somewhere surprising.

`FILE-SIZE` takes three seeks. It remembers where the file stands, goes to the
end, and puts it back, because Forth-2012 says the operation must not affect the
file position:

```
  lseek(fd, 0, SEEK_CUR)      -> where the file stands
  lseek(fd, 0, SEEK_END)      -> the size
  lseek(fd, there, SEEK_SET)  -> put it back
```

`fstat` would be one call instead of three, at the price of `struct stat`, whose
size and field offsets differ between the platforms the way `struct termios`
does, and whose symbol on glibc has not always been the obvious one. Three seeks
of a routine that already exists is the cheaper trade on a word nothing calls in
a loop.

`FILE-STATUS` asks `access` whether the file is there and opens nothing. Its `x`
is 0 and carries nothing at all. Forth-2012 makes it implementation-defined, and
a meaning invented before something needs one is a meaning a program can come to
depend on. It gets one when a word wants it.

`file_open` and `file_status` both need the name as a C string, so both carve a
`PATH_BUF` buffer in their own frame and fill it through `path_copy` in
`src/machine.S`.

## Including a file

`INCLUDE-FILE`, `INCLUDED` and `INCLUDE` all end in `include_impl`, which makes
the file the input source, interprets it line by line, and closes it.

| Word | Stack effect | What it is handed |
|------|--------------|-------------------|
| `INCLUDE-FILE` | `( i*x fileid -- j*x )` | a file the program already opened |
| `INCLUDED` | `( i*x c-addr u -- j*x )` | a name on the stack |
| `INCLUDE` | `( i*x "<spaces>name" -- j*x )` | a name on the line |

A name is a name. aforth searches no path, and it resolves a relative name
against the working directory rather than the directory of the file doing the
including. So a file that includes another has to name it absolutely, or be run
from the right directory.

`INCLUDE` is a token list over `PARSE-NAME` and `INCLUDED`, so a name it does
not find on the line arrives at `INCLUDED` as a length of 0 and raises
`ERR_NO_NAME`.

### The line buffer is in the frame

A file source cannot read into the shared input buffer. The line that called
the include is still in there, and the saved `>IN` of the level below points
into it, so overwriting it would lose the rest of that line and
`INCLUDE lib.f MAIN` would never run `MAIN`.

`include_impl` therefore takes `TIB_SIZE` bytes of its own C stack frame and
points `UV_TIB` at them. The frame lives exactly as long as the source level
does, which is what makes it the right place. `EVALUATE` already points
`UV_TIB` at bytes it does not own, so an address from `SOURCE` was never
promised to be inside the region. Eight levels is about 35 KiB of C stack, and
the region does not change. See [input.md](input.md).

### Every path out closes the file

Forth-2012 makes `INCLUDE-FILE` close the file: "When the end of the file is
reached, close the file and restore the input source specification to its saved
value." `INCLUDED` is that word with an `open` in front of it, so it does not
close the file a second time.

The standard leaves "the status (open or closed) of any files that were being
interpreted" implementation-defined when an error stops the interpreting.
aforth closes there too, so one rule covers every path out. A program that
wants its descriptor back after a failure has to keep its own copy before it
calls, and `CATCH` does not exist yet for it to notice the failure with.

`include_impl` reports rather than raises, which is what lets it close at all. A
raise would unwind past its frame before the close, and that frame holds the
buffer the source is still reading. `interpret_source` and `refill_impl` both
report for the same reason.

`src_reset` closes any fileid still stacked when `machine_quit` restarts.
Nothing reaches it, because `include_impl` closes on every path. It is a
backstop, in the same way and for the same reason the rest of `src_reset` is.

### An error says which file and which line

The file name and the line number live in `include_impl`'s frame and in the
user variables of the level it is about to give up. Both are gone by the time
`machine_quit` reads the error number, so `include_impl` writes its own line of
the message as it unwinds, while its frame is still alive.

```
aforth: undefined word: hello
aforth:   in /tmp/lib/bad.f, line 1
aforth:   included from /tmp/lib/outer.f, line 2
```

The innermost one calls `quit_report` for the message itself and then writes
`in`. Each one above it writes `included from`. It then raises `ERR_REPORTED`,
which has no message of its own, so `machine_quit` clears up and prints
nothing more. `ABORT` and `QUIT` pass through untouched and print nothing:
they are not failures.

`INCLUDE-FILE` is handed a descriptor and never sees a name, so its line reads
`in a file, line 1`. An `EVALUATE` between two files adds no line, a string
level having neither a name nor a line.

### Cold start includes the same way

`cold_start` in `src/aforth.S` calls `included_impl` for each of the two init
files, so an init file is an included file in every respect: it nests input
sources the same way, it is closed on every path out, and an error in it names
the file and the line. What differs is only who reports what, and which failures
are allowed to pass in silence. See [startup.md](startup.md).

## What a line costs

470 ns on macOS, measured over a million `READ-LINE` calls — a thousand
readings of a thousand-line file — against a control that opened and closed the
same file as many times and cost nothing measurable. One `EMIT` is about 341 ns
on the same machine, so a line read costs a little more than a character
printed, which is what two system calls against one predicts.

A 200-line init file therefore costs about 94 µs to read, which is what cold
start pays for the two files it reads. The figure is not in `make bench`: that
harness prices dispatch, and this is not on the dispatch path. See
[benchmark.md](benchmark.md).

## The platform differences

Two more entries in `src/include/platform.h`, which is where every one of them
belongs.

`errno` is a macro over a function that hands back a pointer to the int, and the
function differs: `__error` on macOS, `__errno_location` on Linux. `ERRNO_FN` is
the assembler symbol, spelled out per platform rather than written through
`CSYM`, because `CSYM` pastes its argument and would not expand a macro handed
to it.

`ENAMETOOLONG` is 63 on macOS and 36 on Linux. It is the one `errno` aforth
produces itself: `open` takes a C string and a Forth string has no terminator
after it, so `file_open` copies the name into its own frame and terminates it
there, and a name longer than `PATH_BUF` fails without asking the kernel.

`open`, `close` and `access` return an `int`, so the result arrives in `w0` and
the top half of `x0` is undefined. Each is sign-extended with `sxtw` before
anything compares it against -1. The two platforms leave different rubbish up
there, and the Linux suite is what caught it: a failed `access` read as
4294967295 rather than -1, so `FILE-STATUS` reported that as its ior. `read` and
`lseek` need none of this, returning `ssize_t` and `off_t`, which fill the
register.

`open` is the first variadic libc function aforth calls. It is safe to call
because only its two named arguments are passed, and a call that passes no
variadic argument is the same instruction sequence on both platforms. Apple's
ABI puts a variadic argument on the stack and the Linux AAPCS puts it in a
register, so a call that passed one — `open` with a creation mode, when writing
lands — would need different code per platform.

## Where the tests are

`test/cases/file.sh`. Every case there needs a file with exact bytes, including
one whose last line has no terminator, which an editor would quietly add. So the
files are made with `printf` in a `mktemp -d` directory when the case file is
sourced, and removed at the end, rather than checked in.

The include cases are there too: the three words, that the rest of the calling
line still runs, that the descriptor comes back after the close, the traceback
an error prints, the ninth source that is too deep, and the file line too long
for the buffer. What `(` does inside a file is in `test/cases/parsing.sh`
instead, beside the rest of that word. See [testing.md](testing.md).
