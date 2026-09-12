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

## Platform differences live in `src/include/platform.h`

Never inline in a source file. The header covers five: the Mach-O underscore
prefix on C symbols (`CSYM`), the read-only data section name
(`SECTION_RODATA`), the ELF-only `.type` and `.size` directives (`FUNC_TYPE`,
`FUNC_SIZE`), the `adrp` low-bits relocation syntax (`adr_sym`), and the `mmap`
flags for one private anonymous mapping (`MMAP_FLAGS`).
