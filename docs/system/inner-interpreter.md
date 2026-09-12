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
| N | cell | code field: the index of the routine that runs the word |
| N+8 | cells | parameter field: a colon definition's token list |

An execution token is the offset of a code field from `DBASE`. Nothing in the
dictionary is an address, so an entry means the same thing in a process that
loaded the binary somewhere else. `dict_find` in `src/interpreter.S` is the
search that turns a name into one of those tokens; see [parsing.md](parsing.md).

The dictionary's first cell is reserved, so no entry and no code field lies at
offset 0. That leaves 0 free as the token meaning "no such word", which is what
name lookup returns when it finds nothing.

The name is not cell-aligned, and nothing reads it a cell at a time: a
character is a byte, so comparison is byte by byte.

## Dispatch

`NEXT` reads the next token, adds `DBASE` to reach the code field, reads the
index there, and indexes the table `XTAB` points at to get the address to
branch to. `DISPATCH` is that same tail, for a word that already has a code
field in `W`. Both clobber `x9` and `W`.

`NEXT` is a macro, so every primitive ends with its own copy and each gets its
own branch-predictor entry. `EXECUTE` is `NEXT` reading its token from the
stack instead of the list.

`DOCOL` is the code field of every colon definition: it pushes `IP` on the
return stack and points `IP` at the parameter field. `EXIT` pops it back.
Neither is reached by name; `DOCOL` has no entry at all, because it is not a
word.

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
word: `DOCOL` is defined with it.

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
| `\` | `"\\"` | `5c` |

The declared length is the length of the name, not of the string that spells
it, so `."` is 2 and `\` is 1. A wrong count is a build error rather than a
corrupt entry, so this is a thing to get wrong once.

Five rules govern them.

- **Name the routine in `AFORTH_PRIM_LIST` first.** That list in `dict.h`
  assigns every code-field routine its index and drives `machine_build_xtab`, so
  a name in it must exist as `prim_<name>` somewhere or the link fails. Append to
  it, never insert: a code field holds an index, so renumbering changes the
  meaning of every image already written.
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
`DICT_END`. Put a new word in the file its kind names.

| File | Words |
|------|-------|
| `stack.S` | the stack shuffles, the return stack transfers, `PICK` and `ROLL` |
| `arithmetic.S` | the arithmetic, the mixed precision, the logic, the comparisons, and `udiv128` |
| `memory.S` | `@ ! C@ C!` and the rest that address memory |
| `output.S` | everything that prints, and the pictured output routines |
| `input.S` | `SOURCE >IN REFILL ACCEPT KEY` |
| `parsing.S` | the parsers, `dict_find`, `digit_value`, `number_impl` |
| `quit.S` | `STATE ABORT QUIT BYE` |

Include order is definition order, so a word may only compile a token from a
file above its own. The fragments cannot be assembled on their own; the
Makefile's glob is `src/*.S` and does not reach into `src/words/`.

`DOCOL`, `EXIT`, `EXECUTE` and `(STOP)` stay in `src/interpreter.S`. They are the
inner interpreter rather than words a program reaches for.

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
`test/cases/` its kind names, and a line in `test/cases/guards.sh` if it reads a
stack. See [testing.md](testing.md), which also lists six ways a case passes
while testing nothing.


## Start-up

`machine_init` carves the region, then calls two routines in `interpreter.S`:

- `machine_build_xtab` writes each routine's address into the table at
  `XTAB`. This is the only place aforth writes a real code address, and it
  writes them again on every run.
- `machine_load_dictionary` copies the assembled image to `DBASE` with `memcpy`
  and points `HERE` past it and `LATEST` at its newest entry. A plain copy is
  the whole of it: the image holds offsets, indices and name bytes, so there is
  nothing to fix up. The object file carries no relocations for it.

## Getting into the machine

`aforth_enter` runs a token list and returns when a word runs `(STOP)`: 0 when
the list reached its end, and the error number when something unwound it. The
outer interpreter is what calls it. `machine_execute` runs one word by building
`{xt, (STOP)}` in its own frame, and `machine_refill` runs `REFILL`; both are at
the bottom of `src/interpreter.S`, because the tokens they name are symbols only
the assembler building that file has. See
[outer-interpreter.md](outer-interpreter.md).

`(STOP)` is hidden, so name lookup will not find it. A programmer who compiled
it into a definition would unwind the outer interpreter from under it.

Only one level of `aforth_enter` is open at a time. `UV_STOP_SP` is a single
cell, so entering the machine from inside it would lose the outer frame, and
nothing does.
