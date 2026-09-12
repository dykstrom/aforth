# AGENTS.md

## What is this

aforth is a Forth system written in ARM64 assembly, targeting the Forth-2012
standard. It is meant for anyone who wants a Forth on ARM64, not for internal use
only. macOS/ARM64 is the primary development platform; the system is also meant to
build and run on Linux/ARM64. Development has just started. The machine model, the
inner interpreter, the stack words, the arithmetic, logic and memory words, the
text and number output words, the input words, the parsing and lookup words and
the outer interpreter are in place. The binary builds its dictionary at
start-up, prints a banner, and then reads and runs Forth until BYE or end of
input. There is no way to define a word yet.

## Stack

| Piece | Choice |
|-------|--------|
| Language | ARM64 assembly, assembled with the clang integrated assembler |
| Platforms | macOS/ARM64 (primary), Linux/ARM64 |
| System interface | libc. Call libc in preference to raw syscalls, so the same source builds on both platforms |
| Line editing | libedit, called through its readline-compatible API. A system library on macOS; `libedit-dev` on Linux |
| Build | make and clang, no other build tooling |
| Linux testing | Native arm64 runner in CI; Docker container locally, from macOS. See `docs/system/ci.md` |

## Directory index

| Path | What's there |
|------|-------------|
| `src/` | ARM64 assembly sources. `aforth.S` holds `main`; `machine.S` allocates the region, starts the machine and holds every routine that reaches libc for input or output; `interpreter.S` holds `DOCOL`, `EXIT`, `EXECUTE`, `(STOP)`, the start-up routines and `aforth_enter`, and builds the dictionary image by including the files in `src/words/`; `outer.S` holds the `QUIT` loop, the one error path and the error messages. |
| `src/words/` | The built-in words, one file per kind: `stack.S`, `arithmetic.S`, `memory.S`, `output.S`, `input.S`, `parsing.S` and `quit.S`. These are `#include`d by `interpreter.S`, not assembled on their own: every entry has to be in one assembler pass. Include order is definition order. See `docs/system/inner-interpreter.md` for which file a new word goes in. |
| `src/include/` | Headers included by the sources. `platform.h` holds every macOS/Linux difference; `machine.h` holds the register convention, the region layout and the stack macros; `dict.h` holds the dictionary format and the macros that define a word. |
| `test/` | `run-tests.sh` holds the helpers and the run order; the cases are in `test/cases/`, one file per kind of word, mirroring `src/words/`. Every case pipes Forth source into the built binary and compares its output, its error output or its exit status. See `docs/system/testing.md`. |
| `docker/` | `Dockerfile` for the Linux/ARM64 build and test environment. |
| `.github/workflows/` | CI. `macos.yml` and `linux.yml` each run `make` then `make test` on their platform. |
| `build/` | Build output. Generated, git-ignored. |
| `docs/` | Durable project context. Sub-folder layout below shows where each kind of doc goes. |

```
docs/
├── system/         ← what the code does today (updated as code changes)
├── architecture/   ← what the system must do (updated when rules change)
├── adr/            ← architecture decisions (immutable once shipped)
├── reference/      ← long-form rationale (append-only)
└── working-notes/  ← research; NOT authoritative — rules live in architecture/ + adr/
```

`docs/architecture/design-goals.md` holds the binding rules, drawn from the ADRs in
`docs/adr/`. Read it before writing implementation code: several rules forbid the
obvious approach. The dictionary may hold no absolute code addresses and aforth
generates no code at runtime (ADR 0005), text is UTF-8 bytes with no wide-character
representation (ADR 0004), and configuration is Forth source with no parser (ADR 0003).
Eight registers belong to the Forth machine, and x16, x17 and x18 may not be used at
all (ADR 0006). Before adding a Forth word, read
`docs/system/inner-interpreter.md`: the entry format and the five rules the
defining macros impose are there. `docs/system/arithmetic.md` records the
choices Forth-2012 leaves open, such as which way division rounds,
`docs/system/output.md` the one path every printed byte takes and how a number
is formatted, `docs/system/input.md` how a line arrives and what `KEY` does to
the terminal, `docs/system/parsing.md` how a name is cut out and looked up,
`docs/system/outer-interpreter.md` the `QUIT` loop and the one path every error
takes, and `docs/system/assembler.md` the toolchain's own traps.

## Commands

| What | Command |
|------|---------|
| Build | `make` |
| Run | `make run` |
| Tests | `make test` (builds first, then runs `test/run-tests.sh`) |
| Linux/ARM64 build and test | `make docker-test` (needs a running Docker daemon) |
| Build without the stack guards | `make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS`. A variable set on the `make` command line replaces `ASFLAGS` instead of adding to it, which is why the Makefile reads a separate `EXTRA_ASFLAGS`. |
| Test without the stack guards | `make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS test`, on one command line. `make` hands the flags to the suite in `AFORTH_ASFLAGS`, which is how the suite knows to skip the cases that expect a guard to fire; running `make test` afterwards on its own reports the flag as absent and the skipped cases fail. |

## Gotchas

- The assembler has traps of its own, and they are in `docs/system/assembler.md`: the
  `.S` extension, `//` as the only safe comment, the two constructs clang accepts on
  macOS and refuses on Linux, and where platform differences belong. Read it before
  writing assembly.
- `stderr` is a libc variable, not a function, and its symbol differs between the
  platforms: `__stderrp` on macOS, `stderr` on Linux. Reaching it from assembly is
  awkward, so aforth writes errors to file descriptor 2 with `write`, sizing the
  message with `strlen`. See `write_stderr` in `src/machine.S`.
- VS Code's C/C++ extension claims `.h` files and parses the headers in `src/include/` as C++,
  which leaves several `cpptools-srv` processes running at full CPU: those headers are assembly,
  full of `.macro`, `.set` and `.irp`. Point `files.associations` at an assembly grammar for `*.S`
  and `src/include/*.h`, and list both in `C_Cpp.files.exclude`. `.vscode/` is git-ignored, so each
  developer sets this up locally.
- Call libc variadic functions with care. Apple's ARM64 ABI passes variadic
  arguments on the stack; the Linux AAPCS passes them in registers. So a `printf`
  call with arguments needs different code per platform. The skeleton calls
  `puts`, which is not variadic, to sidestep this.
- Entry is `main`, not `_start`, so the C runtime initialises libc before aforth
  runs. This follows from the design goal of calling libc rather than syscalls.
- aforth is Apache-2.0, so it must not link a GPL-licensed library. GNU readline
  is GPLv3 and therefore out; line editing uses libedit through readline's API.
  New source files need the two SPDX header lines the existing files carry.
  See `docs/adr/0002-license-under-apache-2-0.md`.
