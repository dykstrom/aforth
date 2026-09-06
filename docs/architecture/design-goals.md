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
