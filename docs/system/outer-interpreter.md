# The outer interpreter

How a typed line becomes work. The loop is `machine_quit` in `src/outer.S`, the
words it exposes — `STATE`, `ABORT`, `QUIT` and `BYE` — are in
`src/words/quit.S`, and the two routines it calls to get into the machine are
`machine_refill` and `machine_execute` at the bottom of `src/interpreter.S`.

## The loop, and the routine under it

`main` calls `machine_quit` after the banner. It reads a line, hands it to
`interpret_source`, and decides what the number that comes back means.

`interpret_source` is the half that consumes a parse area. It cuts a name out of
the current source and does one of three things with the name:

- the dictionary holds it, so the word runs;
- it converts in `BASE`, so the cell is pushed;
- neither, so it is an error.

`STATE` decides the first two. While it says compiling, a word's token is
compiled instead of run — unless its entry is marked `F_IMMEDIATE`, which is how
`;` and `[` get their chance to end the definition — and a number is compiled as
a literal instead of pushed. See [compiling.md](compiling.md).

When the parse area is used up it returns 0, and `machine_quit` prints ` ok` and
a newline and reads the next line. That is where the older Forths put it, and it
is why `readline` is given an empty prompt: nothing is printed in front of what
the user types. An empty line prints ` ok` like any other.

`EVALUATE` calls `interpret_source` too, which is the reason it is a routine of
its own rather than the body of the loop. See [input.md](input.md).

### It returns every error and raises none

That matters in both directions, and it is the one thing to keep true when
touching it.

`machine_quit` calls it from **outside** `aforth_enter`, where a raise would
unwind `sp` to a frame that has already been popped — the trap the last section
of this file describes for `ROOM`. `EVALUATE` calls it from **inside** one,
where a raise would unwind past `EVALUATE` and skip the input source it has to
pop.

So the undefined-word path calls `err_name` to remember the name and returns
`ERR_UNDEFINED_WORD` rather than branching to `undefined_word`, which raises.
`'` still goes through `undefined_word`; it is a word, and a word may raise.
`dict_comma` and `dict_compile_literal` already reported rather than raised, and
those numbers are returned as they stand.

`ERR_ABORT` and `ERR_QUIT` come back the same way. They are not failures, and
telling them apart is the caller's job: `machine_quit` restarts, and `EVALUATE`
re-raises so that they reach the loop from inside a string the way they would
from any word.

The loop is assembly because it is what enters the machine and reads what
unwound it. A `QUIT` written in Forth would need `CATCH` and `THROW` to tell an
error from a word that finished. The loop came before both, and it has not
moved since. It runs the same parts the words do rather than parts of its
own: `parse_name_impl`
cuts the name, `dict_find` searches, `number_impl` converts. `?NUMBER` is
`number_impl` and nothing else, so the word and the interpreter cannot disagree
about what a number is.

`STATE` is a user variable and the word pushes the address of the cell.
`machine_quit` zeroes it when it restarts — at start-up, and after `QUIT`,
`ABORT` or a reported error — and not when it refills, so a definition may be
typed on as many lines as the programmer likes and an error abandons it.

## Into the machine and back

A word found by name is run by `machine_execute`, which builds the two-cell list
`{xt, (STOP)}` in its own frame and hands it to `aforth_enter`. A token list is
cells of offsets and nothing more, so it may sit on the C stack; `(STOP)` is
what returns out of it. Both routines live in `src/interpreter.S` because the
tokens they name are symbols only the assembler building that file has.

Nothing may be kept in a register across `machine_execute`. A word is free to
use x27 and x28, and `ACCEPT` does, so the name last parsed lives in
`machine_quit`'s frame.

## One path out

Every guard, every word that raises, and both of `ABORT` and `QUIT` go through
`machine_error` to the routine in `UV_ABORT`. That routine is `quit_abort`, and
it is one instruction: leave the machine through `enter_return`, carrying the
error number as `aforth_enter`'s result. It prints nothing itself: what a number
means is `machine_quit`'s to decide, which is how `ABORT` and `QUIT` leave the
machine the way an error does and still say nothing.

`machine_quit` reads the number and decides.

| Number | What it means | What the loop does |
|--------|---------------|--------------------|
| 0 | the parse area is empty | print ` ok`, read the next line |
| `ERR_QUIT` | `QUIT` ran, or `-56 THROW` | empty the return stack, read the next line |
| `ERR_ABORT` | `ABORT` ran, or `-1 THROW` | empty both stacks, read the next line |
| anything else | a failure | report it, then empty both stacks and read the next line |

Every input source above the terminal is dropped in all three of the last rows,
and every file among them is closed. Forth-2012 says `QUIT` returns control to
the terminal, and an error inside an included file must not leave the loop
reading a file nobody is watching. The drop and the close are both `src_reset`.
Nothing reaches either, because `include_impl` pops and closes on every path
out of its own.

The rest of the line goes with it in every case but the first. That is what
`ABORT` means, and it is why `fnord 1 .` prints the message and no `1`.

`BYE` does not come this way. It calls `exit`, which ends the process and
flushes the stdio buffer libedit prints its own output through; aforth's own
output has nothing in it, every byte having left through `write` already. End of
input does the same thing more quietly: `machine_quit` prints a newline, so a
terminal's next prompt starts on a line of its own, and returns to `main`.

## The messages

`quit_report` in `src/outer.S` writes them on file descriptor 2, as
`write_stderr` does, and the text lives beside it.

| Number | Code | Text |
|--------|------|------|
| `ERR_ABORT_QUOTE` | -2 | `aforth: ` and the program's message, or `aforth: aborted` when the message is empty |
| `ERR_DS_OVERFLOW` | -3 | `aforth: data stack overflow` |
| `ERR_DS_UNDERFLOW` | -4 | `aforth: data stack underflow` |
| `ERR_RS_OVERFLOW` | -5 | `aforth: return stack overflow` |
| `ERR_RS_UNDERFLOW` | -6 | `aforth: return stack underflow` |
| `ERR_DICT_FULL` | -8 | `aforth: dictionary full` |
| `ERR_DIV_ZERO` | -10 | `aforth: divide by zero` |
| `ERR_UNDEFINED_WORD` | -13 | `aforth: undefined word: ` and the name |
| `ERR_NO_NAME` | -16 | `aforth: name expected` |
| `ERR_HOLD_OVERFLOW` | -17 | `aforth: pictured output overflow` |
| `ERR_STRING_TOO_LONG` | -18 | `aforth: counted string too long` |
| `ERR_NAME_TOO_LONG` | -19 | `aforth: name too long` |
| `ERR_CONTROL_FLOW` | -22 | `aforth: unstructured control flow` |
| `ERR_OPEN_FAILED` | -38 | `aforth: cannot open file: ` and the name |
| `ERR_UNTERMINATED_COMMENT` | -39 | `aforth: unterminated comment` |
| `ERR_LINE_TOO_LONG` | -256 | `aforth: input line too long` |
| `ERR_SOURCE_TOO_DEEP` | -257 | `aforth: input sources nested too deep` |
| `ERR_DEFER_UNSET` | -258 | `aforth: deferred word not set` |
| any other | | `aforth: exception ` and the number in signed decimal |

Each number is the code Forth-2012 gives the condition in its table of
`THROW` codes, so a program that catches one sees the number any other system
would hand it. The standard keeps -1 to -255 for its own codes and -256 to
-4095 for a system's. The table has no code for the last three rows, so they
take system codes from -256 down, and `ERR_REPORTED` is -259.

`ERR_ABORT` (-1), `ERR_QUIT` (-56) and `ERR_REPORTED` print nothing.
`quit_report` matches each number exactly, so the order of the numbers means
nothing, and a new error needs a compare and a message of its own. A number
with no compare prints as a number, which is how `42 THROW` says what it threw.
`err_signed` writes it, the signed form of the `err_number` that writes a line
number.

`ERR_REPORTED` means the failure has already said what it was. `include_impl`
raises it after writing the message and the traceback itself, because the file
name and the line number live in a frame that is gone by the time the loop
reads the number. `machine_quit` needs no branch for it: `quit_report` returns
without printing, and the loop empties both stacks as it does for any failure.
See [files.md](files.md).

`ERR_UNDEFINED_WORD` and `ERR_OPEN_FAILED` are the two that name something, and
they share one tail in `quit_report`. `err_name` in `src/machine.S` takes
the name in x0 and x1 and puts it in `UV_ERR_ADDR` and `UV_ERR_LEN`.
`undefined_word` is `err_name` and a raise, which is what `'` uses;
`interpret_source` calls `err_name` and returns the number instead, so the
interpreter and `'` print the same message by two routes. The name points into
the input buffer and the message is written before anything refills it. `'` at
the end of a line has no name to give and its message stops after `word`.
`included_impl` calls `err_name` too, with the name of the file it could not
open.

`ABORT"` and its run-time half `(ABORT")` raise `ERR_ABORT_QUOTE`, and they
store the program's message with `err_name` too. The message comes from
outside aforth, but it needs no early reporting. A compiled message lies
inside the definition, which the unwind leaves alone. An interpreted one
points into the input buffer, like an undefined word's name. Inside a file,
`include_impl` reports it as it reports any failure, so the traceback lines
follow it.

`err_location` writes one line of the traceback under a message, and
`err_number` writes a line number in decimal. The pictured output words would
format a number, but they build into the buffer a program may be part way
through using, and an error must not disturb it.

The message is three writes rather than one formatted string, because aforth
holds no output buffer to format into and `printf` is variadic, which the two
platforms pass differently.

## CATCH and THROW

`CATCH` and `THROW` are in `src/words/exception.S`. `THROW` raises its number
the way every error is raised, through `machine_error` and the vector. `CATCH`
runs its token through `machine_execute`, which is an `aforth_enter` of its
own, so the raise stops there and `CATCH` reads the number as the result.
`EVALUATE` and `include_impl` are on that same path and pop their own input
sources on the way, so the source is back where it was when `CATCH` began.

On a throw, `CATCH` does three things:

- It puts the return stack pointer back to what it was.
- It puts the data stack back to the depth it had once the token was popped.
  The items are not restored: one the thrown-from code changed in place keeps
  its new value, as the suite's test `C4` checks. When the depth already
  matches, the cached top stays. Otherwise `CATCH` reloads the cached top from
  the cell below the restored pointer, where `DPUSHM` would have spilled it.
- It pushes the number.

Both stack pointers wait in `CATCH`'s C stack frame, because the word it runs
is free to use x27 and x28.

`QUIT` is not caught. It empties the return stack, which is where Forth-2012
keeps a `CATCH` frame, so `CATCH` raises `ERR_QUIT` again and it reaches the
loop. `-56 THROW` is `QUIT`'s code and goes the same way. `ABORT` and `ABORT"`
are caught as -1 and -2, which is the Exception extensions' meaning for both.
A caught `ABORT"` prints nothing.

`THROW` sets `UV_ERR_LEN` to 0 before it raises, so that a program's
`-13 THROW` names no word left over from an earlier error, and a `-2 THROW`
repeats no earlier `ABORT"` message.

`UV_CATCH_DEPTH` counts the `CATCH` frames open. `CATCH` adds one before it
runs its token and takes it away on every path back, because every raise
inside it stops at its `aforth_enter` first. `include_impl` reads it: an error
in an included file under a `CATCH` prints nothing and passes the number up as
it came. See [files.md](files.md).

## The one place a guard macro may not go

`ROOM` and `NEED` branch to the handlers in `src/machine.S`, which go through
`UV_ABORT` to `enter_return`, which puts `sp` back to the frame of the last
`aforth_enter`. That frame is gone by the time `machine_quit` pushes a converted
number, the word before it having finished. So the loop makes the same
comparison against `UV_DS_LO` itself and branches to its own reporting. Any code
that runs outside `aforth_enter` has the same problem.

That check stays in the build without the stack guards. It runs once per number
typed rather than once per word executed, so it is not part of what the guards
cost.

The dictionary routines have the same problem and answer it the other way:
`dict_comma` and `dict_set_here` report `ERR_DICT_FULL` rather than raising it,
so that the loop can compile a token and branch to its own reporting while a
word turns the report into a raise with the `RAISE` macro.

## What the tests cover

`test/cases/outer.sh` holds the loop's own behaviour: `ok` per line, `BASE` read
for every name rather than once a line, each message, that an error ends its
line and the next line still runs, what `ABORT` and `QUIT` each empty, and the
exit status after `BYE` and after end of input. `STATE`, `ABORT`, `QUIT` and
`BYE` are checked there as words as well.

What the loop does while `STATE` says compiling is in `test/cases/compile.sh`
instead, beside the words that set it.

`CATCH`, `THROW`, the code each error reaches `CATCH` with, and what a code
nobody catches prints are in `test/cases/exception.sh`. The codes only a stack
guard can raise are in `test/cases/guards.sh`, for the reason below.

What `ABORT` and `QUIT` empty on the return stack is in `test/cases/guards.sh`
instead, because `RNEED` is the only thing that can see it. The build without
the guards has no underflow to report, so the suite leaves that file out and
says so. See [testing.md](testing.md).
