# Design goals

The project's binding goals. No implementation exists yet, so every rule here constrains code that
has not been written.

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
- aforth MUST NOT generate code at runtime. Generated code on macOS/ARM64 requires W^X handling and
  a JIT entitlement, and both platforms require instruction-cache maintenance.
- Source: [ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md).

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
