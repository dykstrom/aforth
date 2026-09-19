# AGENTS.md

## What is this

aforth is a Forth system written in ARM64 assembly, targeting the Forth-2012
standard. It is meant for anyone who wants a Forth on ARM64, not for internal
use only.

Development is early. The binary builds its dictionary at start-up, prints a
banner, and reads and runs Forth until `BYE` or end of input. There is no
counted loop and no way to write a file. The README's Status section lists the
words that work today, and `docs/system/startup.md` covers the command line and
the two files cold start reads.

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
| `src/` | ARM64 assembly sources. `aforth.S` holds `main`, `args_parse`, which reads the command line, and `cold_start`, which reads the two init files; `machine.S` allocates the region, starts the machine and holds every routine that reaches libc for input, output, or the paths cold start reads; `interpreter.S` holds the code-field routines `DOCOL`, `DOCON` and `DOVAR`, the words `EXIT`, `EXECUTE`, `(STOP)`, `(LIT)`, `(BRANCH)`, `(0BRANCH)` and `(S")`, the start-up routines and the re-entrant `aforth_enter`, and builds the dictionary image by including the files in `src/words/`; `outer.S` holds `interpret_source`, which consumes one parse area, the `QUIT` loop over it, the one error path and the error messages. |
| `src/words/` | The built-in words, one file per kind, in include order: `stack.S`, `arithmetic.S`, `memory.S`, `output.S`, `input.S`, `parsing.S`, `file.S`, `compile.S`, `control.S` and `quit.S`. These are `#include`d by `interpreter.S`, not assembled on their own: every entry has to be in one assembler pass. Include order is definition order, so a file may only compile a token from a file above it. See `docs/system/inner-interpreter.md` for which file a new word goes in. |
| `src/include/` | Headers included by the sources. `platform.h` holds every macOS/Linux difference; `machine.h` holds the register convention, the region layout and the stack macros; `dict.h` holds the dictionary format and the macros that define a word. |
| `lib/` | The part of aforth written in Forth rather than assembly. `aforth.f` is the system file, which `make` copies to `build/aforth.f` and which cold start includes before the prompt; a word goes there when Forth says it more clearly than assembly would and nothing on the dispatch path calls it. |
| `test/` | `run-tests.sh` holds the helpers and the run order; the cases are in `test/cases/`, one file per kind of word, mirroring `src/words/`. Every case pipes Forth source into the built binary and compares its output, its error output or its exit status. See `docs/system/testing.md`. |
| `test/bench/` | The benchmarks and the harness that times them. `mix.f` is a loop of stack and arithmetic words and `pick.f` one of `PICK` and `ROLL`; both are standard Forth that runs in arm64th and SwiftForth as well, so the three can be compared. `run-bench.sh` times a list of systems and `timeit.pl` is the stopwatch. Not part of `make test`. See `docs/system/benchmark.md`. |
| `docker/` | `Dockerfile` for the Linux/ARM64 build and test environment. |
| `.github/workflows/` | CI. `macos.yml` and `linux.yml` each run `make` then `make test` on their platform. |
| `build/` | Build output. Generated, git-ignored. |
| `docs/` | Durable project context. Sub-folder layout below shows where each kind of doc goes. |

## Durable context

```
docs/
├── system/         ← what the code does today (updated as code changes)
├── architecture/   ← what the system must do (updated when rules change)
├── adr/            ← architecture decisions (immutable once shipped)
├── reference/      ← long-form rationale (append-only)
└── working-notes/  ← research; NOT authoritative — rules live in architecture/ + adr/
```

Two files in `docs/architecture/` are binding, both drawn from the ADRs in
`docs/adr/`. `design-goals.md` says what aforth must be: Forth-2012, both ARM64
platforms, warm start, libc over syscalls, and configuration as Forth source
with no parser (ADR 0003).

`machine-rules.md` is the one to read before writing implementation code,
because several of its rules forbid the obvious approach.

- The dictionary may hold no absolute code addresses, and aforth generates no
  code at runtime (ADR 0005).
- Eight registers belong to the Forth machine, and x16, x17 and x18 may not be
  used at all (ADR 0006).
- Everything that leaves the machine early goes through one vector (ADR 0008).
- Every byte printed goes out on file descriptor 1 (ADR 0007).
- Text is UTF-8 bytes, with no wide-character representation (ADR 0004).

`docs/system/` describes what the code does today, one file per area.
[`docs/system/README.md`](docs/system/README.md) indexes them and says what each
one covers. Read `inner-interpreter.md` before adding a Forth word.

## Commands

| What | Command |
|------|---------|
| Build | `make` |
| Run | `make run` |
| List the arguments | `./build/aforth --help` |
| Run without the user's init file | `./build/aforth --no-init`, or `--init <file>` to name one instead. The suite and `make bench` both pass `--no-init` |
| Tests | `make test` (builds first, then runs `test/run-tests.sh`) |
| Benchmark | `make bench`. `BENCH_FILE` picks `mix` or `pick`; `BENCH_ITERS`, `BENCH_REPS` and `BENCH_POINTS` trade time for precision. To compare systems, call the harness directly: `test/bench/run-bench.sh aforth=./build/aforth arm64th sf` |
| Linux/ARM64 benchmark | `make docker-bench`. On an Apple silicon host this is a virtual machine, so it prices Linux rather than the silicon |
| Linux/ARM64 build and test | `make docker-test` (needs a running Docker daemon) |
| Build without the stack guards | `make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS`. A variable set on the `make` command line replaces `ASFLAGS` instead of adding to it, which is why the Makefile reads a separate `EXTRA_ASFLAGS`. |
| Test without the stack guards | `make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS test`, on one command line. `make` hands the flags to the suite in `AFORTH_ASFLAGS`, which is how the suite knows to skip the cases that expect a guard to fire; running `make test` afterwards on its own reports the flag as absent and the skipped cases fail. |

## Writing comments and docs

A comment or a doc says what the code does now, and what it is prepared for. It
does not say what the code used to do, and it does not name a ticket or an
issue. A reader has neither the tracker nor the history. Where code looks the
way it does because of something that happened, give the reason and not the
date: "aforth holds no output buffer, so a message is several `write` calls" is
a reason a reader can act on. The historical record is `docs/adr/`, immutable
once shipped, and `docs/working-notes/`, frozen once promoted.

## Gotchas

- Read `docs/system/assembler.md` before writing assembly. Every trap in it cost
  a build to find.
- A libc function that returns `int` leaves its result in `w0`, and the top half
  of `x0` is unspecified. Compare `w0`, or sign-extend with `sxtw` first, and
  never test the full `x0`. The two platforms leave different bits up there.
  See `docs/system/files.md`.
- Pass no variadic argument to libc. Apple's ARM64 ABI puts one on the stack and
  the Linux AAPCS puts it in a register, so a call that passes one needs
  different code per platform. `open` is the one variadic function aforth calls,
  and only its two named arguments are passed. See `docs/system/files.md`.
- `stderr` is a libc variable, not a function, and its symbol differs between the
  platforms: `__stderrp` on macOS, `stderr` on Linux. Reaching it from assembly is
  awkward, so aforth writes errors to file descriptor 2 with `write`, sizing the
  message with `strlen`. See `write_stderr` in `src/machine.S`.
- aforth is Apache-2.0, so it must not link a GPL-licensed library. GNU readline
  is GPLv3 and therefore out; line editing uses libedit through readline's API.
  New source files need the two SPDX header lines the existing files carry.
  See `docs/adr/0002-license-under-apache-2-0.md`.
- VS Code's C/C++ extension parses the headers in `src/include/` as C++ and
  leaves `cpptools-srv` processes at full CPU. Those headers are assembly. Point
  `files.associations` at an assembly grammar for `*.S` and `src/include/*.h`,
  and list both in `C_Cpp.files.exclude`. `.vscode/` is git-ignored, so each
  developer sets this up locally.
