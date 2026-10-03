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

`PAD`, also Core Extensions, is not in the dictionary at all. It is an area of
its own in the region, `PAD_OFF` in `src/include/machine.h`, so it stays put
while `HERE` moves and `/PAD` can report a fixed size. Forth-2012 3.3.3.6 gives
it to the program, so no word of aforth's writes there.

## Building an entry

`header_impl` in `src/words/compile.S` is the one place an entry is built at run
time, and it lays out exactly what the `HEADER` macro lays out at assembly time:
link, flags, count, the name, pad to a cell, the does-cell, then the code field.
It takes the name, the code field's routine index and the flags byte, and leaves
`HERE` on the cell after the code field — where a parameter field starts — and
`LATEST` on the new entry.

The does-cell is 0 in every entry until `DOES>` writes it; see
[Defining words of the program's own](#defining-words-of-the-programs-own).
`header_impl` does not store it separately. The loop that zeroes the name's pad
runs up to the code field, and the does-cell is the last cell before it.

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

## The six code fields

`DOCOL` runs a colon definition. Five more arrive with the defining words, and
like `DOCOL` they are routines with no entry of their own, defined with `CODE`:

| Routine | Built by | What running the word does |
|---------|----------|----------------------------|
| `DOCOL` | `:` and `:NONAME` | run the token list in the parameter field |
| `DOCON` | `CONSTANT`, and so `VALUE` | push the cell in the parameter field |
| `DOVAR` | `CREATE`, and so `VARIABLE` and `BUFFER:` | push the address of the parameter field |
| `DODOES` | `CREATE`, then `DOES>` | push the address of the parameter field, then run the token list the does-cell names |
| `DODEFER` | `DEFER` | run the word whose token is in the parameter field |
| `DOMARKER` | `MARKER` | put `HERE` and `LATEST` back to the two offsets in the parameter field |

`CREATE` reserves no space of its own: the word it makes points at whatever the
program allots next. `VARIABLE` is `CREATE` and one cell, zeroed — Forth-2012
leaves the cell's initial value undefined, and zero is one less thing to be
surprised by. `BUFFER:` is `CREATE` and `ALLOT`, and leaves the space as it
found it. A body always starts on a cell, so the space is aligned, as Forth-2012
asks.

## Compiling

`STATE` is 0 interpreting and -1 compiling. `interpret_source` reads it for
every name, after the search and after the number conversion:

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
previous `X`. `RECURSE` is what a definition calls itself with instead, and it
is in [control-flow.md](control-flow.md) with the rest of what it works around.

`STATE` outlives a line — `machine_quit` clears it when it restarts, not when it
refills — so the body of a definition may be typed on as many lines as the
programmer likes. The name may not: `:` parses it from the line `:` is on, and
there is nothing left to parse at the end of one.

`[` and `]` switch `STATE` directly, and `LITERAL` compiles the cell on the
stack, which is how a value is worked out while a definition is being written
and then compiled into it. `[CHAR]` is `CHAR` and `LITERAL` in one word.
`IMMEDIATE` marks the newest entry, which is the definition `;` has just ended.

## String literals

`S"` and `."` are the third shape of inline data, and the first that is not one
cell. A string compiled into a definition is `(S")`'s token, a count cell, the
bytes, and zeroes up to the next cell:

```
  TOK_(S")  |    5    | h e l l o . . . |  the next token
  <- cell ->  <-cell->  <--- one cell --->
```

`(S")` reads the count the way `(LIT)` reads its cell, takes the bytes from
where the list stands, and steps `IP` over `(count + 7) & -8` of them. It is
hidden for the reason `(LIT)` is.

The padding is what keeps a definition holding a string one unbroken run of
cells. A branch distance is counted in cells, so a string that left `HERE`
unaligned would put a fraction of a cell inside the distance `cf_resolve`
works out and nothing in [control-flow.md](control-flow.md) would still hold.
Nothing there had to change.

`dict_compile_string` in `src/words/compile.S` writes all of it. It tests the
room for the token, the count and the padded bytes in one comparison before it
writes any of them, so a string that does not fit reports `ERR_DICT_FULL`
having written nothing — which a run of `dict_comma` calls could not do. The
pad is zeroed, as `header_impl` zeroes a name's pad, so that the same source
builds the same bytes.

`S"`, `."` and `ABORT"` are immediate, and all three parse with a double
quote as the delimiter from where `>IN` stands, through `parse_impl`; see
[parsing.md](parsing.md).
`parse_name_impl` has already stepped past the one space that ended the word's
own name, so `S" ccc"` takes `ccc` and a quote that comes straight away gives
the empty string. A string whose delimiter never comes takes the rest of the
line and raises nothing, which is the choice `(` makes and for the same reason.

While interpreting, `S"` copies the bytes into one of the transient buffers and
`."` writes them straight out. `."` compiles `TYPE`'s token after the string
rather than having a run-time routine of its own, so a printed string leaves in
the one `write` `TYPE` already makes of it.

`ABORT"` lays its message down the same way, then compiles `(ABORT")` after
it. `(ABORT")` pops the flag under the message and raises `ERR_ABORT_QUOTE`
when the flag is true. See [outer-interpreter.md](outer-interpreter.md).
While interpreting, `ABORT"` pops the flag at once and leaves the message in
the input buffer, where it was parsed. Forth-2012 leaves that undefined, so the
interpreted behaviour is aforth's own.

### The transient buffers

Forth-2012 leaves the interpretation semantics of both words undefined in Core
and defines `S"`'s in the File-Access word set, where 11.3.4 asks that the
buffers holding the result be at least 80 characters long and that there be at
least two of them — so `S" a" S" b"` must leave both strings where they were
put.

That rules out `PAD`, whose contents 3.3.3.6 puts under the complete control of
the user: no word in the standard may place anything there. It rules out the
pictured output buffer too, which holds a number being built and which `.R`
reads across a call to `SPACES`.

So the region has an area of its own for them, `SBUF_OFF` in
`src/include/machine.h`, taken round-robin by `sbuf_take` (ADR 0009). There are four
buffers rather than the two the standard asks for because `REGION_SIZE` has to
stay a whole number of 16 KiB pages and 16 KiB is the smallest step that keeps
it one; the slack goes into the count. Each is as large as the input buffer, so
a string parsed out of a line always fits and nothing is truncated — an
assembly-time check in `machine.h` is what keeps that true if either size moves.

A string that `EVALUATE` runs is the source itself rather than a copy in the
input buffer, so it can be longer than a line, and so can an `S"` inside it. An
interpreted `S"` or `S\"` that would not fit its buffer raises
`ERR_LINE_TOO_LONG` — `aforth: input line too long` — rather than writing past
the buffer's end.

What `."` does while interpreting is aforth's own; see
[output.md](output.md).

### Escapes

`S\"` is `S"` with escapes. A backslash and the character after it stand for
one byte, or two for `\m`, and a double quote after a backslash does not end
the string. The escapes are the ones Forth-2012 lists:

| Escape | Byte | | Escape | Byte |
|--------|------|-|--------|------|
| `\a` | 7 | | `\q` | 34 |
| `\b` | 8 | | `\r` | 13 |
| `\e` | 27 | | `\t` | 9 |
| `\f` | 12 | | `\v` | 11 |
| `\l` | 10 | | `\z` | 0 |
| `\m` | 13 10 | | `\"` | 34 |
| `\n` | 10 | | `\\` | 92 |
| `\x` and two hex digits | that byte | | | |

`\n` is a line feed, the newline on both platforms. The letters are lower case
only, as the standard spells them, and the hex digits may be either case. An
escape the standard does not define, and `\x` without two hex digits after it,
give the character after the backslash as it stands. Forth-2012 leaves both
ambiguous. A backslash at the end of the line is dropped, and a string with no
closing quote takes the rest of the line, as `S"` does.

No escape stands for more bytes than it takes to write, so the translated
string is never longer than its source, and `escape_parse` writes the bytes out as it
parses them. While interpreting it writes into the next transient buffer. While
compiling it writes above `HERE`, at the place `dict_compile_string` would copy
them to, which then finds them already there and adds the token, the count and
the pad. A string too long for the dictionary reports `ERR_DICT_FULL` with
`HERE` where it was.

An interpreted `S\"` that would not fit its buffer raises `ERR_LINE_TOO_LONG`,
as `S"` does; see [The transient buffers](#the-transient-buffers).

## What an error abandons

An error inside a definition goes out the way every other error does, and
`machine_quit` clears `STATE` before it reads the next line, so the loop is
interpreting again. The half-written entry stays where it is: it was never
unhidden, so name lookup walks past it and nothing can reach it, and the chain
still walks through it to the entries below. It is dictionary space nothing will
use again. Forth-2012 leaves this to the system, and reclaiming it would mean
`HERE` and `LATEST` remembering where the definition began.

`STATE` is not the only cell it clears. Any user variable that holds
compile-time state has to be put back there too, or the state outlives the
definition that set it. `UV_LEAVE` is the one that does today. It holds the
`LEAVE`s a counted loop has still to resolve, and `machine_quit` sets it back
to -1. So a `LEAVE` typed after a failed definition is refused rather than
compiled into a loop that no longer exists. See
[control-flow.md](control-flow.md).

## Compiling a word from a word

`POSTPONE` parses a name and compiles that word into the definition being
written. It takes one of two paths, and which one depends on whether the entry
is marked immediate:

| The name is | What `POSTPONE` compiles | What that does |
|-------------|--------------------------|----------------|
| immediate | its token | the new word runs it |
| anything else | `(LIT)`, its token, and a comma | the new word compiles it |

`: ENDIF POSTPONE THEN ; IMMEDIATE` is the first. `THEN` is immediate, so
`ENDIF`'s body holds `THEN`'s token and running `ENDIF` runs `THEN`.
`: MAKE-DUP POSTPONE DUP ; IMMEDIATE` is the second. `MAKE-DUP`'s body holds
`(LIT)`, `DUP`'s token and a comma, so running `MAKE-DUP` appends `DUP` to
whatever is being compiled.

The comma in that second row is `COMPILE,`. An execution token in aforth is a
cell holding an offset from the dictionary base, and a token compiled into a
definition is the same cell, so appending one is what `,` does. `COMPILE,` is
therefore a `DEFALIAS` of `,` in `src/words/compile.S`: an entry with `,`'s
code field and no body. `POSTPONE` compiles its token.

`[']` is in `lib/aforth.f`, because Forth says it and aforth needs no assembly
for it:

```
: ['] ( C: "<spaces>name" -- ) ( -- xt ) ' POSTPONE LITERAL ; IMMEDIATE
```

`[']` is `'` and `LITERAL`, which is Forth-2012's own definition of it. It has
compilation semantics only: typed at the prompt it compiles a literal nobody
will run and pushes nothing.

`POSTPONE` reports a name that is not in the dictionary the way `'` does, with
the name in the message, and for the same reason — handing back a token that is
not there only moves the failure to whatever runs it.

`>BODY` turns an execution token into the address of the word's body. A token
is an offset from the dictionary base and a body starts one cell after the code
field, so it is the arithmetic `DOVAR` does, from a token rather than from the
entry dispatch left in `W`. Nothing but the depth is checked: Forth-2012 makes
a token that `CREATE` did not make an ambiguous condition, and `@` does not
check an address either.

## Defining words of the program's own

`DOES>` is what lets a program write a defining word, a word that makes other
words:

```
: CONST ( x "<spaces>name" -- ) CREATE , DOES> ( -- x ) @ ;
42 CONST ANSWER
ANSWER .          \ prints 42
```

The part of `CONST` before `DOES>` runs when `CONST` runs: `CREATE` makes
`ANSWER` and `,` stores 42 in its body. The part after `DOES>` is the does-part,
and it runs every time `ANSWER` runs, with `ANSWER`'s body address on the stack.
Every word `CONST` makes shares the one does-part and has a body of its own.

Three pieces do the work:

- `DOES>` in `src/words/compile.S` is immediate and compiles one token, that of
  `(DOES>)`. The rest of the definition compiles as usual, up to `;` and its
  `EXIT`, and that list of tokens is the does-part.
- `(DOES>)` in `src/interpreter.S` runs inside the defining word. `IP` points
  at the does-part then. It writes `IP` less `DBASE` into the does-cell of the
  entry `LATEST` names and sets that entry's code field to `DODOES`'s index.
  Then it pops `IP`, as `EXIT` does, so the defining word returns to its caller
  and the does-part does not run now.
- `DODOES` pushes the body's address, as `DOVAR` does. Then it pushes `IP` on
  the return stack and points `IP` at `DBASE` plus the does-cell, as `DOCOL`
  does with its own parameter field. The does-part's `EXIT` returns.

The does-cell sits below the code field, between the name's pad and the code
field, so a body starts one cell after the code field in every entry. That is
why `DOVAR`, `>BODY` and dispatch are the same as they were before `DOES>`: none
of them reads the does-cell. The price is one cell on every entry, including
the built-in ones, which never use it. Everything `(DOES>)` writes is an offset
or an index, so a dictionary grown this way still holds no absolute address
(ADR 0005).

Two cases Forth-2012 leaves undefined behave one particular way, and aforth
checks neither:

- `(DOES>)` changes whatever entry `LATEST` names, whether `CREATE` made it or
  not, as `>BODY` accepts any token.
- `DOES>` typed at the prompt compiles `(DOES>)`'s token at `HERE`, as `IF`
  does.

## Values and deferred words

A value and a deferred word each keep one cell in their body, and the words
that change them store into it.

- `VALUE` is `CONSTANT` under a second name, a `DEFALIAS`, so the word it makes
  runs `DOCON` and pushes its cell.
- `DEFER` builds an entry whose code field is `DODEFER`. `DODEFER` reads the
  token in the body and dispatches on it, which is `EXECUTE` reading from the
  body rather than the stack, so a deferred word costs one dispatch more than
  the word it runs.
- `TO` parses a name and stores into that word's body. While interpreting it
  stores at once. While compiling it compiles `(TO)` and the word's token, and
  `(TO)` stores when the definition runs. The token goes in rather than the
  body's address as a literal, because the address is absolute and the token
  is an offset (ADR 0005).
- `IS` is `TO` under a second name, because setting a deferred word is the same
  store.
- `DEFER@` and `DEFER!` are `>BODY @` and `>BODY !`, and `ACTION-OF` is `'` and
  `DEFER@`, compiled when `STATE` says so. All three are in `lib/aforth.f`.

`DEFER` stores the token of `(DEFER)` in every word it makes, and `(DEFER)`
raises `ERR_DEFER_UNSET` — `aforth: deferred word not set`. So a deferred word
run before anything has set it says so, rather than running whatever its body
held. The message cannot name the word, because by the time `(DEFER)` runs,
dispatch has replaced the deferred word's code field in `W` with its own.

Nothing checks that the word `TO` names is a value or that `IS` names a
deferred word. Forth-2012 makes both ambiguous conditions, and `>BODY` does not
check its token either, so `TO` on a constant changes it.

## Definitions with no name

`:NONAME` builds the entry `:` builds but with a name of no bytes, pushes its
execution token, and sets `STATE`. It calls `header_build`, which is
`header_impl` without the two checks on the name.

`;` leaves an entry with no name hidden. Unhidden, it would be the one entry
`FIND` finds for the empty string, and `WORDS` would print it as an empty name.
Otherwise it is an entry like any other: it is in the chain, `RECURSE` finds it
through `LATEST`, and an error part way through abandons it as it would a named
one. The price is the 24 bytes of link, flags, count, pad and does-cell a name
of no bytes still needs.

The token is pushed when `:NONAME` runs, so it sits under whatever the
control-flow words leave on the stack while the body is written, and `;` leaves
it on top.

## Removing words with a marker

`MARKER name` reads `HERE` and `LATEST`, both as offsets from `DBASE`, and then
builds `name` with a code field of `DOMARKER` and those two cells as its body.
Running `name` puts both back. That takes `name` and every entry after it out of
the dictionary: the chain starts below them again, and the space they used is
the next definition's.

Nothing else is put back. aforth has no search order, and everything else a
definition changes is inside the dictionary. A value or a deferred word older
than the marker that holds a token of a word the marker removed keeps that
token, which then names space the next definition will reuse. Forth-2012 leaves
that ambiguous.

## What is not here

`SLITERAL` and the rest of the String word set are not implemented. Control flow inside a definition
is in [control-flow.md](control-flow.md), and `RECURSE` is there too, because
what it works around is the hiding `:` and `;` do.

## Where the tests are

`test/cases/compile.sh` for the defining words, values, deferred words,
`:NONAME`, `MARKER`, the string literals and what the loop does with `STATE`;
`test/cases/memory.sh` for `HERE UNUSED PAD ALLOT , C, ALIGN` and for the
bound each of them reports on. Every case that measures the allocation pointer
prints how far it moved rather than where it stands, the region landing wherever
the process put it. See [testing.md](testing.md).
