# AGENTS.md

## What is this

aforth is a Forth system written in ARM64 assembly, targeting the Forth-2012
standard. It is meant for anyone who wants a Forth on ARM64, not for internal use
only. macOS/ARM64 is the primary development platform; the system is also meant to
build and run on Linux/ARM64. Development has just started: the repository holds a
build skeleton that prints a banner and exits, and no Forth is implemented yet.

## Stack

| Piece | Choice |
|-------|--------|
| Language | ARM64 assembly, assembled with the clang integrated assembler |
| Platforms | macOS/ARM64 (primary), Linux/ARM64 |
| System interface | libc. Call libc in preference to raw syscalls, so the same source builds on both platforms |
| Build | make and clang, no other build tooling |
| Linux testing | Native arm64 runner in CI; Docker container locally, from macOS. See `docs/system/ci.md` |

## Directory index

| Path | What's there |
|------|-------------|
| `src/` | ARM64 assembly sources, one flat directory. `aforth.S` holds `main`. |
| `src/include/` | Headers included by the sources. `platform.h` holds every macOS/Linux difference. |
| `test/` | `run-tests.sh` runs the built binary and checks its output and exit status. |
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

## Commands

| What | Command |
|------|---------|
| Build | `make` |
| Run | `make run` |
| Tests | `make test` (builds first, then runs `test/run-tests.sh`) |
| Linux/ARM64 build and test | `make docker-test` (needs a running Docker daemon) |

## Gotchas

- Sources use the `.S` extension, not `.s`. clang runs the C preprocessor on `.S`
  only. Rename a file to `.s` and its `#include "platform.h"` is skipped in
  silence, so the platform macros expand to nothing.
- Every macOS/Linux difference belongs in `src/include/platform.h`, not inline in
  a source file. It currently covers four: the Mach-O underscore prefix on C
  symbols (`CSYM`), the read-only data section name (`SECTION_RODATA`), the
  ELF-only `.type` and `.size` directives (`FUNC_TYPE`, `FUNC_SIZE`), and the
  `adrp` low-bits relocation syntax (`adr_sym`).
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
