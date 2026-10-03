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
unwound it. A definition can branch now, but a `QUIT` written in Forth would
still need `CATCH` and `THROW` to tell an error from a word that finished, and
aforth has neither. It runs the same parts the words do rather than parts of its
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
| `ERR_QUIT` | `QUIT` ran | empty the return stack, read the next line |
| `ERR_ABORT` | `ABORT` ran | empty both stacks, read the next line |
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

| Number | Text |
|--------|------|
| `ERR_DS_UNDERFLOW` | `aforth: data stack underflow` |
| `ERR_DS_OVERFLOW` | `aforth: data stack overflow` |
| `ERR_RS_UNDERFLOW` | `aforth: return stack underflow` |
| `ERR_RS_OVERFLOW` | `aforth: return stack overflow` |
| `ERR_DIV_ZERO` | `aforth: divide by zero` |
| `ERR_HOLD_OVERFLOW` | `aforth: pictured output overflow` |
| `ERR_LINE_TOO_LONG` | `aforth: input line too long` |
| `ERR_UNDEFINED_WORD` | `aforth: undefined word: ` and the name |
| `ERR_NO_NAME` | `aforth: name expected` |
| `ERR_NAME_TOO_LONG` | `aforth: name too long` |
| `ERR_DICT_FULL` | `aforth: dictionary full` |
| `ERR_CONTROL_FLOW` | `aforth: unstructured control flow` |
| `ERR_SOURCE_TOO_DEEP` | `aforth: input sources nested too deep` |
| `ERR_UNTERMINATED_COMMENT` | `aforth: unterminated comment` |
| `ERR_OPEN_FAILED` | `aforth: cannot open file: ` and the name |
| `ERR_DEFER_UNSET` | `aforth: deferred word not set` |
| `ERR_ABORT_QUOTE` | `aforth: ` and the program's message, or `aforth: aborted` when the message is empty |

`ERR_REPORTED`, `ERR_ABORT` and `ERR_QUIT` print nothing and stay the three
highest numbers: `quit_report` tells a message from a silent exit by comparing
against the last number that has one. That compare names `ERR_ABORT_QUOTE`, so
a new error with a message must be numbered below it. Numbered above it, the
error prints nothing at all. An error added in the middle renumbers the ones
after it, which is allowed — the numbers are runtime only and nothing writes
one to disk.

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

What `ABORT` and `QUIT` empty on the return stack is in `test/cases/guards.sh`
instead, because `RNEED` is the only thing that can see it. The build without
the guards has no underflow to report, so the suite leaves that file out and
says so. See [testing.md](testing.md).
