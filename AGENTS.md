# AGENTS.md

## What is this

aforth is a Forth-2012 system in ARM64 assembly, for anyone who wants a Forth
on ARM64. Development is early: it reads and runs Forth until `BYE` or end of
input. The README's Status section lists what works today.

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
| `src/` | The machine itself, in ARM64 assembly. `aforth.S` is start-up and the command line, `machine.S` is the region and every call into libc, `interpreter.S` is the inner interpreter (code fields such as `DOCOL`, run-time words such as `(LIT)`), and `outer.S` is the `QUIT` loop and the error messages. |
| `src/words/` | The built-in words, one file per kind, such as `stack.S` and `compile.S`. `interpreter.S` includes them in one assembler pass, and include order is definition order. See `docs/system/inner-interpreter.md` for which file a new word goes in. |
| `src/include/` | Headers: `platform.h` for macOS/Linux differences, `machine.h` for the registers and the region, `dict.h` for the dictionary format. |
| `lib/` | `aforth.f`, the system file: words written in Forth, such as `WITHIN` and `VARIABLE`. Cold start includes it before the prompt. `docs/system/startup.md` says which words belong there. |
| `test/` | `run-tests.sh` and the cases in `test/cases/`, one file per kind of word. See `docs/system/testing.md`. |
| `test/bench/` | Benchmarks and the harness that times them, not part of `make test`. See `docs/system/benchmark.md`. |
| `docker/` | The Linux/ARM64 build and test environment. |
| `.github/workflows/` | CI, one workflow per platform. |
| `build/` | Build output. Generated, git-ignored. |
| `docs/` | Durable project context, laid out below. |

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

- Read `docs/system/assembler.md` before writing assembly.
- A libc function that returns `int` leaves junk in the top half of `x0`. Test
  `w0`, or `sxtw` it first. See `docs/system/files.md`.
- Pass no variadic argument to libc, because the two platforms pass one
  differently. See `docs/system/files.md`.
- Write errors with `write_stderr` in `src/machine.S`, not through `stderr`,
  whose symbol differs per platform.
- Link no GPL library, because aforth is Apache-2.0 (ADR 0002). That rules out
  GNU readline. Give every new source file the two SPDX header lines.
- VS Code's C/C++ extension parses `src/include/*.h` as C++ and pins
  `cpptools-srv` at full CPU. Map `*.S` and `src/include/*.h` to an assembly
  grammar in `files.associations`, and list both in `C_Cpp.files.exclude`, in
  your own `.vscode/`, which is git-ignored.
