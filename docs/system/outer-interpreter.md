# The outer interpreter

How a typed line becomes work. The loop is `machine_quit` in `src/outer.S`, the
words it exposes are in `src/interpreter.S`, and the two routines it calls to
get into the machine are `machine_refill` and `machine_execute` at the bottom of
that file.

## The loop

`main` calls `machine_quit` after the banner. It reads a line, cuts a name out
of it, and does one of three things with the name:

- the dictionary holds it, so the word runs;
- it converts in `BASE`, so the cell is pushed;
- neither, so it is an error.

When the line is used up, aforth prints ` ok` and a newline and reads the next
one. That is where the older Forths put it, and it is why `readline` is given an
empty prompt: nothing is printed in front of what the user types. An empty line
prints ` ok` like any other.

The loop is assembly because a token list cannot branch until ticket 011. It
runs the same parts the words do rather than parts of its own: `parse_name_impl`
cuts the name, `dict_find` searches, `number_impl` converts. `?NUMBER` is
`number_impl` and nothing else, so the word and the interpreter cannot disagree
about what a number is.

`STATE` is a user variable and the word pushes the address of the cell.
`machine_quit` zeroes it before every line. Nothing writes it until ticket 010
puts the loop's compiling half in.

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
| 0 | the word finished | take the next name |
| `ERR_QUIT` | `QUIT` ran | empty the return stack, read the next line |
| `ERR_ABORT` | `ABORT` ran | empty both stacks, read the next line |
| anything else | a failure | report it, then empty both stacks and read the next line |

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

Only the last names anything. `undefined_word` in `src/machine.S` takes the name
in x0 and x1 and puts it in `UV_ERR_ADDR` and `UV_ERR_LEN` before raising, so
the interpreter and `'` print the same message. The name points into the input
buffer and the message is written before anything refills it. `'` at the end of
a line has no name to give and its message stops after `word`.

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
typed rather than once per word executed, so it is not what ticket 012 prices.

## What the tests cover

`test/cases/outer.sh` holds the loop's own behaviour: `ok` per line, `BASE` read
for every name rather than once a line, each message, that an error ends its
line and the next line still runs, what `ABORT` and `QUIT` each empty, and the
exit status after `BYE` and after end of input. `STATE`, `ABORT`, `QUIT` and
`BYE` are checked there as words as well.

What `ABORT` and `QUIT` empty on the return stack is in `test/cases/guards.sh`
instead, because `RNEED` is the only thing that can see it. The build without
the guards has no underflow to report, so the suite leaves that file out and
says so. See [testing.md](testing.md).
