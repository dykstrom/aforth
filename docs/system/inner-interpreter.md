# The dictionary and the inner interpreter

How a word is stored and how it runs. The format is in `src/include/dict.h`,
the words and the start-up routines in `src/interpreter.S`, and the registers
and the region in `src/include/machine.h`.

## A dictionary entry

| Offset | Size | Field |
|--------|------|-------|
| 0 | cell | link: the previous entry as an offset from `DBASE`, 0 ends the chain |
| 8 | byte | flag bits: `F_IMMEDIATE`, `F_HIDDEN` |
| 9 | byte | name length in bytes |
| 10 | bytes | the name, UTF-8, stored as typed |
| | pad | to the next cell |
| N-8 | cell | does-cell: the token list a `DOES>` word runs, as an offset from `DBASE`, or 0 |
| N | cell | code field: the index of the routine that runs the word |
| N+8 | cells | parameter field: a colon definition's token list |

An execution token is the offset of a code field from `DBASE`. Nothing in the
dictionary is an address, so an entry means the same thing in a process that
loaded the binary somewhere else. `dict_find` in `src/words/parsing.S` is the
search that turns a name into one of those tokens; see [parsing.md](parsing.md).

The dictionary's first cell is reserved, so no entry and no code field lies at
offset 0. That leaves 0 free as the token meaning "no such word", which is what
name lookup returns when it finds nothing.

The name is not cell-aligned, and nothing reads it a cell at a time: a
character is a byte, so comparison is byte by byte.

The does-cell is below the code field, so a body starts one cell after the code
field in every entry, and only `DODOES` and `(DOES>)` read or write it. It is 0
in every built-in entry. See [compiling.md](compiling.md).

Four routines work out where the code field starts from the name's length:
`dict_find`, `header_impl`, `RECURSE` and `(DOES>)`. All four use the `CFOFF`
macro in `dict.h`, which is the arithmetic the `HEADER` macro does at assembly
time. Write `CFOFF` rather than the arithmetic, so that a fifth copy cannot
drift from the other four.

## Dispatch

`NEXT` reads the next token, adds `DBASE` to reach the code field, reads the
index there, and indexes the table `XTAB` points at to get the address to
branch to. `DISPATCH` is that same tail, for a word that already has a code
field in `W`. Both clobber `x9` and `W`.

`NEXT` is a macro, so every primitive ends with its own copy and each gets its
own branch-predictor entry. That is worth 48%: a build with one shared `NEXT`
executes two fewer instructions per word and is half again as slow. See
[benchmark.md](benchmark.md). `EXECUTE` is `NEXT` reading its token from the
stack instead of the list.

`DOCOL` is the code field of every colon definition: it pushes `IP` on the
return stack and points `IP` at the parameter field. `EXIT` pops it back.
Neither is reached by name; `DOCOL` has no entry at all, because it is not a
word. `DOCON`, `DOVAR`, `DODOES`, `DODEFER` and `DOMARKER` are the other five
code fields, for a word made by `CONSTANT` or `VALUE`, one made by `CREATE`, one
that `DOES>` has given a does-part, one made by `DEFER`, and one made by
`MARKER`, and they have no entry either. See
[compiling.md](compiling.md).

`F_IMMEDIATE` and `F_HIDDEN` are both read by then. The outer interpreter runs
an immediate word rather than compiling it, and `dict_find` walks past a hidden
one — which is what `(STOP)`, `(LIT)`, `(BRANCH)`, `(0BRANCH)`, `(DO)`,
`(LOOP)`, `(+LOOP)`, `(?DO)`, `(S")`, `(ABORT")`, `(DOES>)`, `(TO)` and
`(DEFER)` are, what a definition is between `:` and `;`, and what one made by
`:NONAME` stays.

## Adding a word

`DEFCODE` defines a word in assembly, `DEFWORD` one as a list of tokens.
Every word carries its stack effect as a comment on the defining line, in the
notation Forth-2012 uses for it:

```
        DEFCODE "DUP", 3, dup           // ( x -- x x )
        NEED    1
        ROOM    1
        DPUSHM
        NEXT

        DEFWORD "2*", 2, two_star       // ( x1 -- x2 )
        TOKEN   dup
        TOKEN   plus
        ENDWORD
```

`CODE` is `DEFCODE` without the entry, for a code-field routine that is not a
word: `DOCOL`, `DOCON`, `DOVAR`, `DODOES`, `DODEFER` and `DOMARKER` are defined
with it.

`DEFALIAS` gives a word written in assembly a second name. The entry takes the
other word's code field and has no body, so the alias costs one header and
runs exactly as the other word does. `COMPILE,`, `VALUE` and `IS` are the three:

```
        DEFALIAS "COMPILE,", 8, compile_comma, comma    // ( xt -- )
```

### Names that need escaping

A name is passed as a quoted string, which is what lets a word be named with a
comma: without the quotes it would separate the defining macro's own arguments.
A double quote or a backslash in a name is escaped as it would be in any
string.

| Forth word | written as | name stored |
|------------|------------|-------------|
| `,` | `","` | `2c` |
| `."` | `".\""` | `2e 22` |
| `S"` | `"S\""` | `53 22` |
| `S\"` | `"S\\\""` | `53 5c 22` |
| `\` | `"\\"` | `5c` |

The declared length is the length of the name, not of the string that spells
it, so `."` is 2, `\` is 1 and `S\"` is 3. A wrong count is a build error
rather than a corrupt entry, so this is a thing to get wrong once.

The coverage check in `test/run-tests.sh` reads these names out of the sources
and undoes both escapes, so a name holding a quote reaches it whole. See
[testing.md](testing.md), which also has the one name that check cannot really
see.

### The symbols a label makes

The label is not only a name for the reader. The defining macros build symbols
out of it, and a routine that picks one of those names fails the build:

| Symbol | What it is | Made by |
|--------|-----------|---------|
| `ent_<label>` | the entry | `HEADER` |
| `cf_<label>` | the code field | `HEADER` |
| `TOK_<label>` | the token, an offset from `DBASE` | `HEADER` |
| `XT_<label>` | the code field's index | `AFORTH_PRIM_LIST` |
| `prim_<label>` | the routine's first instruction | `CODE` |

So a helper routine may not be called `cf_<label>` for a word that exists.
`cf_check`, `cf_forward`, `cf_backward` and `cf_resolve` are safe because
aforth has no words named `CHECK`, `FORWARD`, `BACKWARD` or `RESOLVE`. The
routine `ELSE` and `ENDOF` share is `else_impl` and not `cf_else`, because
`cf_else` is `ELSE`'s own code field. `header_impl`, `include_impl` and
`number_impl` are named the same way.

The build reports this as `symbol 'cf_else' is already defined` against a line
in `<instantiation>`, which is inside the macro's expansion. It does not name
the routine that took the name.

Five rules govern them.

- **Name the routine in `AFORTH_PRIM_LIST` first.** That list in `dict.h`
  assigns every code-field routine its index and drives `machine_build_xtab`, so
  a name in it must exist as `prim_<name>` somewhere or the link fails. The
  order is free to change today, because every code field in the image is
  assembled from the list in the same pass; it stops being free once aforth can
  save a dictionary, a saved code field holding an index.
- **Give the word its stack effect.** On the defining line, as above.
- **Declare the name's length.** Two assembly-time checks catch a wrong one, so
  a mistake is a build error rather than a corrupt entry.
- **A token is a backward reference.** `TOKEN` needs the word already defined,
  exactly as Forth does when it compiles one.
- **All entries belong in one assembler pass.** The macros track their place in
  the image with a running offset that exists only inside the assembler building
  it. A second object file would build a second image whose links do not reach
  the first.

### Which file a new word goes in

The entries are in `src/words/`, one file per kind of word, and
`src/interpreter.S` pulls them in with `#include` between `DICT_BEGIN` and
`DICT_END`. Put a new word in the file its kind names. A word written in Forth
goes in `lib/aforth.f` instead, and the table does not list those; see
[startup.md](startup.md) for which words qualify.

| File | Words |
|------|-------|
| `stack.S` | the stack shuffles, the return stack transfers, `PICK` and `ROLL` |
| `arithmetic.S` | the arithmetic, the mixed precision, the logic, the comparisons, and `udiv128` |
| `memory.S` | `@ ! C@ C!` and the rest that address memory, and `HERE UNUSED PAD ALLOT , C, ALIGN` with the two routines that move the allocation pointer |
| `output.S` | everything that prints, and the pictured output routines |
| `input.S` | `SOURCE >IN SOURCE-ID REFILL ACCEPT KEY EVALUATE`, and the input source stack |
| `parsing.S` | the parsers, `dict_find`, `digit_value`, `number_impl`, and `ENVIRONMENT?` |
| `file.S` | `R/O OPEN-FILE CLOSE-FILE READ-FILE READ-LINE FILE-SIZE FILE-POSITION REPOSITION-FILE FILE-STATUS`, and `INCLUDE-FILE INCLUDED` with `include_impl` under them |
| `compile.S` | `CREATE : ; :NONAME IMMEDIATE [ ] LITERAL [CHAR] CONSTANT VALUE TO DEFER IS MARKER COMPILE, POSTPONE >BODY DOES>`, the string literals `S"`, `S\"` and `."`, `ABORT"`, and `header_impl` |
| `control.S` | `IF ELSE THEN BEGIN UNTIL WHILE REPEAT AGAIN RECURSE DO ?DO LOOP +LOOP I J UNLOOP LEAVE CASE OF ENDOF ENDCASE`, and the routines that write a branch distance |
| `quit.S` | `STATE ABORT QUIT BYE` |

The table is in include order, and include order is definition order: a word
may only compile a token from a file above its own. That is why `output.S`
comes after `stack.S` and `arithmetic.S` — `.` compiles `DUP` and `ABS`. The
fragments cannot be assembled on their own; the Makefile's glob is `src/*.S` and does not
reach into `src/words/`.

`DOCOL`, `DOCON`, `DOVAR`, `DODOES`, `DODEFER`, `DOMARKER`, `EXIT`, `EXECUTE`,
`(STOP)`, `(LIT)`, `(BRANCH)`, `(0BRANCH)`, `(DO)`, `(LOOP)`, `(+LOOP)`,
`(?DO)`, `(S")`, `(ABORT")`, `(DOES>)`, `(TO)` and `(DEFER)` stay in
`src/interpreter.S`. They are the inner interpreter rather than words a program
reaches for. The twelve after `(STOP)` are hidden for the same reason: each is
the run-time half of a word the programmer writes, so a programmer who typed
one would push, jump, print, store, strand a pair of cells or rewrite the
newest word by whatever came next.
`(S")` reads a count and then that many bytes rather than one cell; the shape
is in [compiling.md](compiling.md). `(DO)` reads nothing out of the list, but
leaves a frame on the return stack that only `(LOOP)`, `(+LOOP)`, `UNLOOP` or
`LEAVE` takes off again; see [control-flow.md](control-flow.md).

Nothing else may go into `SECTION_RODATA` between `DICT_BEGIN` and `DICT_END`,
and that now means inside any of the files in `src/words/`. The image is
whatever lies between those two labels, so a stray string would be copied into
the dictionary as if it were an entry. A `.text` routine between entries is fine
and several sit there — `dict_find`, `udiv128`, the pictured output routines —
because they land in a different section.

## Writing a word for the cached top

The top of the data stack is in a register and the items below it are in
memory, so a word is not written the way a memory-only Forth writes it. `DROP`
is a load, `DUP` is a store, and a word that only rearranges the stack does it
in place with `DGETM` and `DSETM` rather than popping and pushing its way
through. `machine.h` documents those macros and the depth arithmetic; the point
here is that a word must be written for that convention rather than translated
into it.

Two consequences catch people out. The cached top is undefined when the stack
is empty, so a word that reads the stack needs its guard before it reads
anything. And the first push spills that undefined value into the cell below
the bottom of the stack, so the deepest item lives at `S0 - 16`, not `S0 - 8`.

## Testing a word

Every word is tested from Forth source, by `test/run-tests.sh` feeding the built
binary and comparing what comes out. A new word needs a case in the file of
`test/cases/` its kind names, and one or two lines in `test/cases/guards.sh`: a
depth case if it reads a stack, and a room case if it pushes onto one. A word
that does both needs both. See [testing.md](testing.md), which also lists eight
ways a case passes while testing nothing.


## Start-up

`machine_init` carves the region, then calls two routines in `interpreter.S`:

- `machine_build_xtab` writes each routine's address into the table at
  `XTAB`. This is the only place aforth writes a real code address, and it
  writes them again on every run.
- `machine_load_dictionary` copies the assembled image to `DBASE` with `memcpy`
  and points `HERE` past it and `LATEST` at its newest entry. A plain copy is
  the whole of it: the image holds offsets, indices and name bytes, so there is
  nothing to fix up. The object file carries no relocations for it.

What the dictionary grows afterwards is built by `header_impl`, which lays out
the same fields the `HEADER` macro lays out here and writes the same kinds of
value. See [compiling.md](compiling.md).

## Getting into the machine

`aforth_enter` runs a token list and returns when a word runs `(STOP)`: 0 when
the list reached its end, and the error number when something unwound it. The
outer interpreter is what calls it. `machine_execute` runs one word by building
`{xt, (STOP)}` in its own frame, `machine_refill` runs `REFILL`, and
`dict_compile_literal` compiles `(LIT)` and a cell; all three are at the bottom
of `src/interpreter.S`, because the tokens they name are symbols only the
assembler building that file has. See
[outer-interpreter.md](outer-interpreter.md).

`(STOP)` is hidden, so name lookup will not find it. A programmer who compiled
it into a definition would unwind the outer interpreter from under it.

`aforth_enter` nests. Each entry saves two things in its own frame: the
`UV_STOP_SP` the entry below it left, so that one cell is really the top of a
stack, and `IP`, because the entry below it is part of the way through a token
list and this one is about to point `IP` at another. `EVALUATE` is what needs
both — it interprets from inside a word — and [input.md](input.md) has the
whole of why. Nothing else is saved: the stacks are shared on purpose and `W` is
scratch.
