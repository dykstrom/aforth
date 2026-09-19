# Benchmark

What one Forth word costs, and how to measure it again. The benchmarks are in
`test/bench/`; `make bench` runs one.

These are the figures a change to dispatch or to the register convention has to
beat. How they were obtained, what each variant build changed, and what the
results mean is a longer argument, and it is in
[reference/dispatch-performance.md](../reference/dispatch-performance.md).

## What there is to run

Two benchmarks, both a single `BEGIN ... UNTIL` loop, both standard Forth-2012
that runs unchanged in arm64th and SwiftForth as well as in aforth.

| File | What it is | Words per iteration |
|------|-----------|--------------------|
| `test/bench/mix.f` | A mix of stack and arithmetic words | 23 |
| `test/bench/pick.f` | `PICK` and `ROLL`, for the guard they pay | 27 |

There are two because the guards are not all the same. A word that reads the
data stack pays `NEED`; `PICK` and `ROLL` cannot, because the depth they require
is whatever number the user put on the stack, so they pay `NEED 1` and then
`NEEDX`, which computes the depth in full. Pricing the guards on `mix.f` alone
would measure `NEED` and call it the answer.

Every word in either loop is a handful of instructions, so nearly all of what is
measured is dispatch rather than work. That is deliberate, and it makes every
figure here an **upper bound** on what a change to dispatch buys real code.

```
make bench                              # mix.f on ./build/aforth
make bench BENCH_FILE=pick
make docker-bench                       # the same, on Linux/ARM64
test/bench/run-bench.sh -f pick aforth=./build/aforth arm64th sf
```

`run-bench.sh` takes a list of systems, each optionally `label=command`, and any
command that reads Forth on standard input and stops at `BYE` will do. It is not
part of `make test`, which has to stay fast.

Each benchmark ends by printing a line beginning with `#` holding the values it
finished on. The body is depth-neutral and its values change every iteration and
depend on the iteration count, so that line is a checksum: every system and
every build must print the same one. `run-bench.sh` compares them and marks a
row whose line differs rather than reporting a time for it.

`BENCH_ITERS` is large on purpose, and `BENCH_POINTS` of 3 or more is what makes
the `drift` column report anything. Read `drift` before believing a small
difference: it is the worst residual of the fit as a percentage, it stays under
one per cent on a quiet machine, and a row showing ten per cent measured the
machine rather than the build.

## The machine these figures came from

| | |
|---|---|
| Machine | Apple M4 Max, 12 performance cores and 4 efficiency cores |
| Measured clock | 4.46 GHz, from a chain of dependent `add` instructions |
| macOS | 26.5.2, build 25F84 |
| Assembler | Apple clang 21.0.0 (clang-2100.1.1.101) |
| Linux | Debian stable-slim in Docker, on the same host |
| Load while measuring | an interactive desktop; `drift` says how much that showed |

## The figures to beat

| Benchmark | per iteration | per word | cycles per word |
|-----------|--------------:|---------:|----------------:|
| `mix.f` | 10.33 ns | 0.449 ns | 2.00 |
| `pick.f` | 12.93 ns | 0.479 ns | 2.14 |

Two cycles per word, at about six and a half instructions retired per cycle.
The dispatch chain is three dependent L1 loads, so six or seven dispatches are
in flight at once. **This core has issue width to spare while it waits on that
chain, so instructions are nearly free and serial dependencies and mispredicted
branches are not.** Every result below follows from it, and none of them would
transfer unchanged to a narrower machine.

| Question | Answer |
|----------|--------|
| Is inlining `NEXT` worth it? | Yes, and it is the largest effect measured: one shared copy is 48% slower |
| Is the cached top worth it? | Yes, but only 10%, against the large factor the folklore implies |
| What do the stack guards cost? | 8% on ordinary words, 17% on `PICK` and `ROLL`. They are two-fifths of every instruction executed and under a fifth of the time |
| Would hoisting `S0` into x27 pay for itself? | It buys 3.5% for one register and 6% for two, against the 13% removing the guards buys. Real, but small for the price |
| What does the index code field's extra load cost? | Nothing sixteen passes can measure |
| Does Linux/ARM64 differ? | No, on every figure |
| What does printing a character cost? | 341 ns on macOS and 132 ns on Linux — several hundred words |

The last row dwarfs the rest. Every conclusion about dispatch is about tenths of
a nanosecond, and one character printed costs more than seven hundred words
dispatched; see [output.md](output.md) for the one path every byte takes.

## Measuring again

The one rule that matters: **compare ratios taken inside a single pass.** The
baseline's own figure moves by up to 9% between sessions, and two builds running
identical Forth differ by about 7% in a single pass, so a comparison between two
numbers from different sessions says nothing about any effect smaller than that.
[reference/dispatch-performance.md](../reference/dispatch-performance.md) has
the control that measured those bounds, and the correction that was needed when
this rule was broken after it had been written down.
