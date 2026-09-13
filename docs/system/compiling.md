# Colon definitions and dictionary growth

How a word gets into the dictionary at run time. The allocation words are in
`src/words/memory.S`, the defining words in `src/words/compile.S`, the two
code-field routines they point entries at in `src/interpreter.S`, and the half
of the interpret loop that compiles in `src/outer.S`.

## The allocation pointer

`HERE` is a cell in the user area, `UV_HERE`. Two routines in
`src/words/memory.S` write it and nothing else does, so the bound is tested in
one place:

- `dict_set_here` moves it to a given address.
- `dict_comma` stores a cell at it and steps one cell on.

The pointer must stay between `DBASE` and `UV_DICT_END`. A move that would
leave that range writes nothing, leaves `HERE` where it was, and reports
`ERR_DICT_FULL` — `aforth: dictionary full`. The comparison is unsigned, so a
pointer that ran off either end, or wrapped, fails it.

Both routines **report** rather than raise. The outer interpreter calls
`dict_comma` to compile a token, and it runs outside `aforth_enter`, where a
raise would unwind `sp` to a frame that has already been popped — the same
reason the loop makes its own room check for a number it is about to push. A
word turns the report back into a raise with the `RAISE` macro, which is one
compare and a branch to `machine_error`.

`HERE ALLOT , C, ALIGN` are the words over those two routines, and `UNUSED`
says how far `HERE` may still move up, which is the one way a program can see
the bound. `ALLOT` takes a signed count, so a negative one releases space.

`UNUSED` is from the Core Extensions word set rather than Core, as a good many
of the words aforth already had are. It is here because without it a test for
the dictionary's end has to name a number that depends on how big the built-in
image happens to be, and stops pinning the end once the image grows past it.

## Building an entry

`header_impl` in `src/words/compile.S` is the one place an entry is built at run
time, and it lays out exactly what the `HEADER` macro lays out at assembly time:
link, flags, count, the name, pad to a cell, then the code field. It takes the
name, the code field's routine index and the flags byte, and leaves `HERE` on
the cell after the code field — where a parameter field starts — and `LATEST` on
the new entry.

Everything it writes is an offset, an index or a name byte. A dictionary grown
here holds no more absolute addresses than the image it grew from, which is what
ADR 0005 requires of a system that must support warm start.

It raises rather than reporting, because every word that calls it runs inside
`aforth_enter`. Three things stop it:

| Number | Text | When |
|--------|------|------|
| `ERR_NO_NAME` | `aforth: name expected` | nothing left on the line to name |
| `ERR_NAME_TOO_LONG` | `aforth: name too long` | more than 255 bytes, which one count byte cannot hold |
| `ERR_DICT_FULL` | `aforth: dictionary full` | the entry does not fit |

## The three code fields

`DOCOL` was already there. Two more arrive with the defining words, and like
`DOCOL` they are routines with no entry of their own, defined with `CODE`:

| Routine | Built by | What running the word does |
|---------|----------|----------------------------|
| `DOCOL` | `:` | run the token list in the parameter field |
| `DOCON` | `CONSTANT` | push the cell in the parameter field |
| `DOVAR` | `CREATE`, and so `VARIABLE` | push the address of the parameter field |

`CREATE` reserves no space of its own: the word it makes points at whatever the
program allots next. `VARIABLE` is `CREATE` and one cell, zeroed — Forth-2012
leaves the cell's initial value undefined, and zero is one less thing to be
surprised by.

## Compiling

`STATE` is 0 interpreting and -1 compiling. `machine_quit` reads it for every
name, after the search and after the number conversion:

| STATE | The dictionary holds the name | The name converts | Neither |
|-------|------------------------------|-------------------|---------|
| 0 | run the word | push the cell | `aforth: undefined word` |
| -1 | compile its token, unless the entry is marked `F_IMMEDIATE`, in which case run it | compile `(LIT)` and the cell | the same error |

`(LIT)` is the primitive that pushes the cell following it in the list and steps
over it. It is hidden, as `(STOP)` is: run on its own it would push whatever
token came next and then skip that word. `dict_compile_literal` compiles the two
cells, and it sits in `src/interpreter.S` beside `machine_execute`, because
`(LIT)`'s token is a symbol only the assembler building that file has.

`:` parses a name, builds a header whose code field is `DOCOL`'s index, marks
the entry `F_HIDDEN`, and sets `STATE`. `;` compiles `EXIT`'s token, clears
`F_HIDDEN` and clears `STATE`, and is itself immediate, because the loop is
compiling when it meets it.

The hiding is what makes a name used inside a definition mean the word that was
there before rather than the one being written, so `: X X 2 + ;` builds on the
previous `X`. Forth-2012's `RECURSE` is what a definition calls itself with, and
it is not implemented.

`STATE` outlives a line — `machine_quit` clears it when it restarts, not when it
refills — so the body of a definition may be typed on as many lines as the
programmer likes. The name may not: `:` parses it from the line `:` is on, and
there is nothing left to parse at the end of one.

`[` and `]` switch `STATE` directly, and `LITERAL` compiles the cell on the
stack, which is how a value is worked out while a definition is being written
and then compiled into it. `[CHAR]` is `CHAR` and `LITERAL` in one word.
`IMMEDIATE` marks the newest entry, which is the definition `;` has just ended.

## What an error abandons

An error inside a definition goes out the way every other error does, and
`machine_quit` clears `STATE` before it reads the next line, so the loop is
interpreting again. The half-written entry stays where it is: it was never
unhidden, so name lookup walks past it and nothing can reach it, and the chain
still walks through it to the entries below. It is dictionary space nothing will
use again. Forth-2012 leaves this to the system, and reclaiming it would mean
`HERE` and `LATEST` remembering where the definition began.

## What is not here

`CREATE DOES>` and `POSTPONE` were cut from the epic. `[']` and the string
literals are not implemented. Control flow inside a definition is in
[control-flow.md](control-flow.md), and `RECURSE` is there too, because what it
works around is the hiding `:` and `;` do.

## Where the tests are

`test/cases/compile.sh` for the defining words and for what the loop does with
`STATE`; `test/cases/memory.sh` for `HERE UNUSED ALLOT , C, ALIGN` and for the
bound each of them reports on. Every case that measures the allocation pointer
prints how far it moved rather than where it stands, the region landing wherever
the process put it. See [testing.md](testing.md).
