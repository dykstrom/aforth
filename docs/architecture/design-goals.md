# Design goals

What aforth must be: the goals that decide what the system is for, what it runs on, and what it
may not trade away. The rules for writing the machine that satisfies them are in
[machine-rules.md](machine-rules.md).

Source: the project's design goals as stated by the developer. Goals that are not settled are not
rules; they are tracked in
[working-notes/open-design-questions.md](../working-notes/open-design-questions.md).

The goals are not ranked, except where a rule states a trade-off.

## Standard

- aforth MUST implement Forth-2012.
- aforth MAY implement a word outside the Core word set — one from Core Extensions, one from
  another word set, or one from no standard at all — when it simplifies the work in hand or is
  worth having on its own. Core Extensions is already well represented: `NIP TUCK PICK ROLL TRUE
  FALSE <> 0<> 0> U> 2>R 2R> 2R@ HEX ERASE .R U.R PARSE PARSE-NAME REFILL UNUSED \`. `.S` and
  `WORDS` are from Programming-Tools, and `?NUMBER` is not a Forth-2012 word at all.
- A word that is not in Forth-2012 at all MUST be recorded as such in the `docs/system/` file for
  its area, so that a reader can tell what is portable Forth from what is aforth's own.

## Platforms and language

- aforth MUST build and run on macOS/ARM64 and on Linux/ARM64.
- macOS/ARM64 is the primary development platform.
- Source MUST be ARM64 assembly, assembled with the clang integrated assembler.

## Portability

- Code SHOULD call libc rather than raw syscalls, so one source builds on both platforms.

## Warm start

- aforth MUST support warm start.
- Code MUST be relocatable, and nothing aforth saves may depend on the address the process
  happened to load at. What that forbids in the dictionary, and what a code field and an execution
  token hold instead, is in [machine-rules.md](machine-rules.md).
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
- aforth MUST report a file it was told to read and cannot, and MUST NOT report a file it only
  looked for and did not find. The user's `init.f` is the only file aforth looks for; the system
  file beside the binary and the file `--init` names are both told-to-read. A file aforth looks for
  MUST be asked about before it is opened, so that a missing one costs no message.
- A file aforth cannot read MUST NOT stop start-up. Each file is attempted on its own, the prompt
  comes up either way, and the exit status stays 0. Only a command line that will not parse exits 1.
- A later file aforth reads by itself, such as a history file or a saved image, MUST be settled as
  told-to-read or looked-for before it is written.
- Source: [ADR 0011](../adr/0011-report-a-file-aforth-was-told-to-read.md).

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
