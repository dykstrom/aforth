# Design goals

The project's binding goals. The machine and the first words are written, so some of these rules
now constrain code that exists; the rest still constrain code that does not.

Source: the project's design goals as stated by the developer. Goals that are not settled are not
rules; they are tracked in
[working-notes/open-design-questions.md](../working-notes/open-design-questions.md).

The goals are not ranked, except where a rule states a trade-off.

## Standard

- aforth MUST implement Forth-2012.

## Platforms and language

- aforth MUST build and run on macOS/ARM64 and on Linux/ARM64.
- macOS/ARM64 is the primary development platform.
- Source MUST be ARM64 assembly, assembled with the clang integrated assembler.

## Portability

- Code SHOULD call libc rather than raw syscalls, so one source builds on both platforms.

## Warm start

- aforth MUST support warm start.
- Code MUST be relocatable.
- The dictionary MUST NOT contain absolute code addresses. A code field MUST hold a primitive's
  index, and a link inside the dictionary MUST be an offset from the dictionary base. Executables
  load at a fresh address on every run, so a saved image holding an absolute address is invalid on
  reload.
- An execution token MUST be the offset of a code field from the dictionary base, never an address
  and never the offset of the entry that carries it. `EXECUTE` adds the base back, and 0 is not a
  token: the dictionary's first cell is reserved so that name lookup can return 0 for a name it did
  not find.
- aforth MUST NOT generate code at runtime. Generated code on macOS/ARM64 requires W^X handling and
  a JIT entitlement, and both platforms require instruction-cache maintenance.
- Source: [ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md).

## Machine model

- The Forth machine MUST live in the eight registers named in `src/include/machine.h`: x19 the
  instruction pointer, x20 the data stack pointer, x21 the return stack pointer, x22 the top data
  stack item, x23 the word register, x24 the dictionary base, x25 the index table base, and x26 the
  user area base.
- The top item of the data stack MUST be held in a register, not in memory.
- The top item MUST be treated as undefined when the stack is empty, so a word that reads the stack
  MUST check the depth first.
- A primitive MUST reach the stacks through the macros in `src/include/machine.h`, and MUST NOT name
  a stack pointer register directly.
- A routine that a word calls MUST NOT change x27 or x28. A primitive may keep values in those two
  registers across a libc call, and a callee that clobbers one takes that away. `write_stderr` in
  `src/machine.S` holds its argument on the stack for this reason.
- x16, x17 and x18 MUST NOT be used. The Mach-O dynamic linker clobbers x16 and x17 at any call,
  and x18 is reserved for the platform on both targets.
- Source: [ADR 0006](../adr/0006-assign-eight-registers-to-the-forth-machine.md).

## Leaving the machine

- Everything that leaves the Forth machine early MUST go through the vector in `UV_ABORT` and out
  of `aforth_enter`, carrying a number. That covers the stack guards, a word that raises, and
  `ABORT` and `QUIT`, which are not failures but must not return to the word that ran them either.
- The routine in the vector MUST NOT print. `machine_quit` reads the number, prints what it means,
  and empties what that number says to empty.
- A guard macro — `NEED`, `ROOM`, `RNEED`, `RROOM` — MUST NOT be used by code running outside
  `aforth_enter`. `enter_return` puts `sp` back to the frame of the last `aforth_enter`, and that
  frame is gone. Such code MUST make the comparison itself, as `machine_quit` does before it pushes
  a number.
- Source: [ADR 0008](../adr/0008-leave-the-machine-through-one-vector.md).

## Usability

- aforth MUST report errors to the user as text messages.
- aforth MUST provide input line editing at the interactive prompt.
- Line editing MUST use libedit, called through its readline-compatible API. The native `el_*` API
  MUST NOT be used: `el_set` is variadic, and the macOS and Linux ARM64 ABIs pass variadic
  arguments differently. Source: [ADR 0001](../adr/0001-use-libedit-for-line-editing.md).
- aforth MUST be able to open an external editor.

## Configurability

- The user MUST be able to configure which editor aforth opens.
- aforth MUST read init files on cold start.
- Configuration MUST be read from `$XDG_CONFIG_HOME/aforth/`, falling back to `~/.config/aforth/`
  when that variable is unset. The same path applies on both platforms.
- The cold-start init file is `init.f` and MUST be executed as Forth source. aforth MUST NOT parse
  a configuration file format.
- Forth source files MUST use the `.f` extension.
- aforth MUST NOT read an init file from the current directory: `init.f` is executed as code, so
  reading one from the working directory would run arbitrary code on start-up. Only the XDG path
  and an explicit `--init <file>` argument may be read.
- aforth MUST accept a `--no-init` flag that skips the init file, so tests and bug reports run
  without user configuration.
- The editor MUST be taken from `$VISUAL`, then `$EDITOR`, then a built-in default of `vi`.
  `init.f` MAY override it.
- Source: [ADR 0003](../adr/0003-configuration-in-xdg-dir-as-forth-source.md).

## Output

- aforth MUST write all output with `write` on file descriptor 1, through `write_stdout` in
  `src/machine.S`.
- aforth MUST NOT print through a stdio stream, `puts` and `printf` included, and MUST NOT hold an
  output buffer of its own. libedit writes its prompt through stdio and flushes it, and a second
  buffer would leave the order of the prompt and the output to the two buffers.
- Source: [ADR 0007](../adr/0007-write-output-on-file-descriptor-1.md).

## Text and characters

- One character MUST be one byte. Text MUST be held as UTF-8-encoded byte sequences.
- `TYPE`, `S"`, the parser, and dictionary name lookup MUST stay byte-oriented.
- Case folding for name lookup MUST cover ASCII `A`-`Z` only. Bytes of 0x80 and above MUST be left
  unchanged.
- aforth MUST call `setlocale(LC_CTYPE, "")` at start-up, before initialising line editing.
- aforth MUST NOT normalize or collate text.
- The Forth-2012 Extended Characters word set is deferred. When implemented it MUST be an optional
  extension declared through `ENVIRONMENT?`.
- Source: [ADR 0004](../adr/0004-represent-text-as-utf-8-bytes.md).

## Testability

- aforth MUST be testable by an automated test suite.
- Linux/ARM64 MUST be testable in a Docker container.

## Performance

- Performance is a goal, but MUST NOT be pursued at the cost of portability or warm start.

## Build environment

- The build MUST use make and clang only.

## Licensing

- aforth is licensed under Apache-2.0, copyright Johan Dykström.
- aforth MUST NOT link a GPL-licensed library, GNU readline included: Apache-2.0 code flows into
  GPLv3 projects, not the reverse.
- Every source file MUST carry an `SPDX-License-Identifier: Apache-2.0` line and a copyright line.
- Source: [ADR 0002](../adr/0002-license-under-apache-2-0.md).
