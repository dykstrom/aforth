# The assembler

aforth is assembled by the clang integrated assembler, targeting Mach-O on
macOS and ELF on Linux. The two targets differ in ways that break a build
instead of warning, and clang refuses some things GNU as accepts. Read this
before writing assembly; every entry below cost a build to find.

## Sources are `.S`, never `.s`

clang runs the C preprocessor on `.S` only. Rename a file to `.s` and its
`#include "platform.h"` is skipped in silence, so every platform macro expands
to nothing.

## Comments are `//`

`;` starts a comment in Mach-O ARM64 assembly but *separates statements* on
Linux, so a `;` comment assembles on macOS and fails every Linux build.
`/* */` works, because these are `.S` files and cpp strips it before the
assembler sees it, but an editor that treats `.S` as assembly does not
highlight it. `//` is understood by cpp and by both assemblers.

Keep an escaped double quote out of a comment. It leaves some editors
highlighting the rest of the file as one long string, which is why the escaped
word names live in `inner-interpreter.md` and not in a comment in
`src/include/dict.h`.

## A cpp macro cannot expand to several statements

cpp joins its expansion onto one line, and macOS then drops everything after
the first `;`. Where one list has to drive several directives, use `.irp` over
a comma-separated cpp macro, which puts each directive on its own line.
`AFORTH_PRIM_LIST` in `src/include/dict.h` is the example.

## A conditional branch cannot name a symbol in another file

On macOS clang reports `conditional branch requires assembler-local label`. So
a check that branches to a handler elsewhere tests the good case and jumps over
an unconditional branch instead. The stack guards and `NONZERO` in
`src/include/machine.h` are both written that way, and it costs nothing on the
path a word actually takes. Each expansion needs its own local label, so they
build one with `\@`, the macro invocation counter.

## A symbol holding a label difference cannot be reassigned

clang refuses this on Linux and accepts it on macOS, so it builds on the
development machine and fails in CI. A running offset through a data structure
must therefore be plain arithmetic on numbers, not the difference between two
labels. That is why a dictionary entry declares its name's length rather than
measuring it; see `inner-interpreter.md`.

## Large immediates take two instructions

`add` and `sub` take `lsl #12`, but `movz` takes a shift of only 0, 16, 32 or
48. `machine_init` in `src/machine.S` builds `REGION_SIZE` from its two 16-bit
halves for that reason.

## `CSYM` cannot take a macro

`CSYM` is `_##name` on macOS and plain `name` on Linux, and the two behave
differently when the argument is itself a macro: cpp expands an argument it
substitutes, but not one it pastes. So `CSYM(SOME_MACRO)` resolves on Linux and
spells the symbol `_SOME_MACRO` on macOS, where the link then fails naming a
symbol nobody wrote.

A platform difference that is itself a C symbol name therefore spells the
assembler symbol out per platform, underscore included. `ERRNO_FN` in
`src/include/platform.h` is the one that does, and [files.md](files.md) says
what it is for.

## A Mach-O build cannot catch a mistake in an ELF-only directive

`FUNC_TYPE` and `FUNC_SIZE` expand to nothing on macOS, so a misplaced or
malformed one builds cleanly on the development machine and fails, or lies,
only on Linux. The same goes for anything else the table below makes
platform-specific.

clang cross-assembles, so the check costs a second and needs no container:

```
for f in src/*.S; do
  clang --target=aarch64-unknown-linux-gnu -g -Wall -Isrc/include -c -o /dev/null $f
done
```

`make docker-test` is the full check; this is the one to run while editing.

Every `.globl` routine carries both directives, `FUNC_TYPE` after the `.globl`
and `FUNC_SIZE` after the routine's last instruction, so that an ELF backtrace
or profile names every aforth routine rather than some of them. `FUNC_SIZE`
measures from the label to wherever it is written, so it goes after the last
exit path, not after the first `ret`.

## Platform differences live in `src/include/platform.h`

Never inline in a source file. The header covers these:

| Macro | The difference |
|-------|----------------|
| `CSYM` | the Mach-O underscore prefix on C symbols |
| `SECTION_RODATA` | the read-only data section name |
| `FUNC_TYPE`, `FUNC_SIZE` | the ELF-only `.type` and `.size` directives |
| `adr_sym` | the `adrp` low-bits relocation syntax |
| `MMAP_FLAGS` | the flags for one private anonymous mapping |
| `LC_CTYPE` | `setlocale`'s category number |
| `TERMIOS_SIZE`, `TERMIOS_LFLAG_OFF`, `T_ICANON`, `T_ECHO` | the shape of `struct termios` and the two bits `KEY` clears |
| `ERRNO_FN` | the function `errno` is a macro over |
| `ENAMETOOLONG` | the one `errno` aforth produces itself |
