# Benchmark

What one Forth word costs in aforth and how that was measured; what the two
optimisations [ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md)
named are worth; what the stack guards cost and what would make them cheaper;
and where aforth stands against two other Forths on the same machine. The
benchmarks are in `test/bench/`; `make bench` runs one.

Everything here was measured for ticket 012. A later change to the register
convention or to dispatch has these numbers to beat.

## What came out

| Question | Answer |
|----------|--------|
| What does a word dispatched cost? | 0.45 to 0.48 ns, two cycles, on an M4 Max at 4.46 GHz |
| Is inlining `NEXT` worth it? | Yes, and it is the largest effect here: one shared copy is 48% slower |
| Is the cached top worth it? | Yes, but only 10%, against the large factor the folklore implies |
| What do the stack guards cost? | 8% on ordinary words, 17% on `PICK` and `ROLL` |
| Would hoisting `S0` into x27 pay for itself? | It buys 3.5% for one register and 6% for two — about a third of what the guards cost. Real, but small for the price |
| What does the index code field's extra load cost? | Nothing that sixteen passes of the benchmark can measure |
| Does Linux/ARM64 differ? | No, on every figure |
| What does printing a character cost? | 341 ns on macOS and 132 ns on Linux — several hundred words |

The thread running through all of it: **this core has issue width to spare
while it waits on the dispatch chain, so instructions are nearly free and
serial dependencies and mispredicted branches are not.** Every result above is
a consequence of that, and none of them would transfer unchanged to a narrower
machine.

## What there is to run

Two benchmarks, both a single `BEGIN ... UNTIL` loop, both standard Forth-2012
that runs unchanged in arm64th and SwiftForth as well as in aforth.

| File | What it is | Words per iteration |
|------|-----------|--------------------|
| `test/bench/mix.f` | A mix of stack and arithmetic words | 23 |
| `test/bench/pick.f` | `PICK` and `ROLL`, for the guard they pay | 27 |

Every word in either loop is a handful of instructions, so nearly all of what
is measured is dispatch rather than work. That is deliberate: it is the most
sensitive body available for pricing the inner interpreter, and therefore an
**upper bound** on what a change to dispatch buys real code. A program that
divides, prints or calls libc will see a fraction of these differences.

There are two files because the guards are not all the same. A word that reads
the data stack pays `NEED`; `PICK` and `ROLL` cannot, because the depth they
require is whatever number the user put on the stack, so they pay `NEED 1` and
then `NEEDX`, which computes the depth in full. Pricing the guards on `mix.f`
alone would measure `NEED` and call it the answer.

```
make bench                              # mix.f on ./build/aforth
make bench BENCH_FILE=pick
make docker-bench                       # the same, on Linux/ARM64
test/bench/run-bench.sh -f pick aforth=./build/aforth arm64th sf
```

`run-bench.sh` takes a list of systems, each optionally `label=command`, and any
command that reads Forth on standard input and stops at `BYE` will do. It is
not part of `make test`, which has to stay fast.

### The benchmarks are commented in the ordinary way

Both files use `\` for their comments and `( )` for a stack effect, which every
Forth-2012 system has. That was not true when ticket 012 wrote them: aforth had
no comment word at all, so each file opened by defining `\` out of
`SOURCE NIP >IN !` before it could carry so much as a copyright line. Ticket 014
added `(` and `\`, and the definition came out.

The workaround cost 1.1 ms, measured against a comment-free twin of the file at
a thousand iterations, and none of it reached the figure: it was the same 1.1 ms
in every script `run-bench.sh` generates, so it landed in the intercept and
cancelled out of the slope. The null control below measured the same thing from
the other side and found nothing. Both are kept here because the question — does
the work a benchmark does before its loop reach the number? — comes back every
time someone adds a benchmark, and the answer is no.

### The checksum

Each benchmark ends by printing a line beginning with `#` holding the values it
finished on. The body is depth-neutral and its values change every iteration
and depend on the iteration count, so that line is a checksum: every system and
every build must print the same one. `run-bench.sh` compares them and marks a
row whose line differs rather than reporting a time for it. That is what caught
each variant build below being wrong before it was believed.

## How it is timed

aforth has no timing word, and neither has arm64th — no `MS`, no `UTIME`, no
`TIME&DATE`. So the harness times the whole process from outside, which suits
all three systems and keeps the benchmark one loop in one file.

`test/bench/timeit.pl` is the stopwatch: it forks and execs the system directly
rather than through a shell, feeds it the benchmark on standard input, and
discards its output. `run-bench.sh` builds the script by writing the iteration
count ahead of the file as `ITERS`.

Four things make the figure mean something:

**The slope, not the time.** Each system is timed at several iteration counts
and the per-iteration figure is the slope of the least-squares line through
them. The intercept absorbs everything that does not scale with the loop —
process start-up, building the dictionary, reading the file, printing the
answer — so none of it has to be measured or estimated. This is what the first
measurements in
[working-notes/dispatch-cost-of-index-code-fields.md](../working-notes/dispatch-cost-of-index-code-fields.md)
could not do: they subtracted an estimated cost rather than measuring it in
place.

**The points are all long.** They run from `ITERS/2` to `ITERS`, not from a
small count upward. A core coming out of idle takes something like a second to
reach its top clock, so a short run is slower per iteration than a long one and
a line fitted through both is bent — measurably, by five per cent. Choose
`ITERS` so that `ITERS/2` takes about a second in the slowest system being
timed.

**The best of several runs, interleaved and rotated.** The answer for a point
is the shortest time it ever reached, because every disturbance — a timer
interrupt, another process, a migration to an efficiency core — only ever adds.
One repeat runs every point of every system once, so a machine that drifts
drifts under all of them. And the order rotates by one job on each repeat:
without that, one system is always the one that runs first out of idle and
another always last into a warm machine, and a fixed position is a fixed bias.
Adding the rotation moved figures by up to five per cent and brought
independent runs of the whole comparison into agreement.

**The drift column.** It is the worst residual of the fit, as a percentage of
the point it belongs to, and it is the number to look at before believing a
small difference between two rows. On a quiet machine it stays under one per
cent. A row showing ten per cent is a row that measured the machine. With two
points there is no residual to report — a line through two points fits them
exactly — so the column shows a dash, and `-p 3` or more is what buys it.

Even so, two rows within a few per cent of each other are not reliably
distinguishable on a desktop that is also running a browser and a terminal.
Where that mattered below, the whole comparison was run several times and the
spread is quoted.

### The null control

How much of a difference between two rows is real is not a question to answer
by intuition, so it was measured. Three builds that do identical work were
timed against each other over six passes: `mix.f` as it then was, carrying its
own definition of `\`, a twin with that definition and every comment stripped
out, and a second twin with no comments but one dummy dictionary entry of
exactly `\`'s shape.

| | median slope | ratio to the bare twin | range over six passes |
|---|---:|---:|---|
| `mix.f` with its own `\` | 10.415 ns | 1.007 | 0.99 – 1.10 |
| bare twin | 10.328 ns | — | — |
| bare twin plus one entry | 10.416 ns | 1.017 | 0.88 – 1.07 |

Two things come out of it. **The comments cost nothing measurable** — the
commented file lands within one per cent of its bare twin, and the sign of the
difference flips from pass to pass. And **a single pass cannot resolve better
than about seven per cent**, because two builds running identical Forth differ
by that much when nothing separates them but where their dictionaries happened
to land.

That is why every comparison below is quoted as a median over several passes
with its range, and why a range that straddles 1.0 is reported as no effect
rather than as a small one.

## The machine

| | |
|---|---|
| Machine | Apple M4 Max, 12 performance cores and 4 efficiency cores |
| Measured clock | 4.46 GHz, from a chain of dependent `add` instructions |
| macOS | 26.5.2, build 25F84 |
| Assembler | Apple clang 21.0.0 (clang-2100.1.1.101) |
| Linux | Debian stable-slim in Docker, on the same host |
| arm64th | commit 9879b01 of 2026-09-01, built locally |
| SwiftForth | x64-macOS 4.1.2, 22-Jan-2026, under Rosetta 2 |
| Load while measuring | an interactive desktop; `drift` says how much that showed |

The clock figure matters because it turns nanoseconds into cycles, which is the
only unit in which the numbers below can be reasoned about. It is measured
rather than taken from the specification: a loop of dependent `add`
instructions retires one per cycle on any AArch64 core, so its wall time
divided by its length is the clock the core actually ran at. 4.46 GHz against a
published peak of 4.51.

## What a word costs

The shape of every figure below is one primitive, `+`, as the assembler emits
it. Nothing here is unusual about `+`: every one- or two-instruction word has
the same three parts.

```
prim_plus:
        ldr     x9, [x26]               // NEED 2: load S0
        sub     x9, x9, x20             //         S0 - DSP
        cmp     x9, #0x10               //         at least two cells?
        b.ge    ok
        b       ds_underflow
ok:     ldr     x0, [x20], #8           // the word's own work: pop the second
        add     x22, x22, x0            //                      add it to the top
        ldr     x23, [x19], #8          // NEXT: the next token
        add     x23, x24, x23           //       + DBASE = the code field
        ldr     x9,  [x23]              //       the code field = a routine index
        ldr     x9,  [x25, x9, lsl #3]  //       the index = an address
        br      x9                      //       go
```

Eleven instructions run, of which two are the addition. Four are the guard and
five are `NEXT`. Every build has the same three parts, in these counts:

| Build | guard | work | `NEXT` | total |
|-------|------:|-----:|-------:|------:|
| baseline | 4 | 2 | 5 | 11 |
| no guards | 0 | 2 | 5 | 7 |
| shared `NEXT` | 4 | 2 | 6 | 12 |
| memory top | 4 | 4 | 5 | 13 |
| S0 in x27 | 3 | 2 | 5 | 10 |
| `XTAB` fixed up | 4 | 2 | 4 | 10 |

Keep that table beside every measurement below, because the two hardly ever
agree. The shared-`NEXT` build runs *fewer* instructions than the memory-top
build and is four times further from the baseline. The no-guards build removes
four instructions in eleven and is nowhere near four-elevenths faster. On this
core an instruction count predicts almost nothing.

## The variants

Each was built as a separate tree, was checked against the full 408-case test
suite, and printed the benchmark's checksum. None of them is in the repository:
[ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md) and
[ADR 0006](../adr/0006-assign-eight-registers-to-the-forth-machine.md) still
stand, and acting on these results was out of ticket 012's scope. What each one
changed is recorded here so it can be rebuilt in an hour.

**No guards** — `make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS`, which is in the
shipped Makefile. `NEED`, `ROOM`, `RNEED`, `RROOM` and `NEEDX` become empty.

**Shared `NEXT`** — `NEXT` in `src/include/dict.h` becomes `b aforth_next`, and
one copy of the three-instruction sequence plus `DISPATCH` is emitted in
`src/interpreter.S`. `DISPATCH` itself stays inline, `EXECUTE` being its only
other user. Two instructions less per primitive and 2156 bytes less code.

**Memory top** — `TOS` is removed from `src/include/machine.h` altogether, so
that a word still written for a cached top fails to assemble rather than
reading a stale register; all 153 sites were then rewritten. The top item lives
at `[DSP, #-8]`, one cell below where the cached model leaves `DSP`, which
keeps every other item at the address it had: `DGETM`, `DSETM`, `DGETMX`,
`DSETMX`, `DDEPTH` and all four guards are the same instructions as before, and
only the top moves. Two macros, `TGET` and `TSET`, read and write it. A word
that pops has to read the top before it pops and write it back afterwards,
because popping moves the cell the top lives in; that write-back is the cost
being measured. `DS_LO` moves up one cell, because a push writes one cell below
where `DSP` lands, and the data stack therefore holds one item fewer — 8190
rather than 8191. That is the register, counted honestly, and the variant's
copy of `test/cases/guards.sh` fills one item less because of it.

**S0 in x27** — x27 holds `S0` and x28 the data stack's low bound, loaded by
`aforth_enter`, which is the one way into the machine. `NEED`, `ROOM`, `NEEDX`
and `DDEPTH` then compare against a register instead of loading the cell first.
The return stack's guards keep their loads: there is no third register to give
them. Five words — `ELSE`, `C,`, `SPACES`, `.S` and `WORDS` — kept a value in
x27 or x28 across a call, which is what
[ADR 0006](../adr/0006-assign-eight-registers-to-the-forth-machine.md) left
those two registers free for, and each had to save and restore them instead.

**`XTAB` fixed up** — the experiment
[working-notes/dispatch-cost-of-index-code-fields.md](../working-notes/dispatch-cost-of-index-code-fields.md)
described and left for this ticket. A new `machine_fixup_code_fields` walks the
link chain at start-up and rewrites every code field from the index the image
holds to the address of the routine it names; `header_impl` does the same for a
word built at run time; and `DISPATCH` drops its indexed load. `XTAB` stays as
the table the fixup pass reads. The pass is twenty instructions and runs once.

## What dispatch costs today

The baseline build, on the machine above.

| Benchmark | per iteration | per word | cycles per word |
|-----------|--------------:|---------:|----------------:|
| `mix.f` | 10.33 ns | 0.449 ns | 2.00 |
| `pick.f` | 12.93 ns | 0.479 ns | 2.14 |

That confirms the range the first measurements put on it — 0.4 to 0.6 ns for a
word dispatched — and narrows it, this time without subtracting an estimate.

Two cycles per word is the number worth keeping. One iteration of `mix.f` runs
about 296 instructions, counted from the sources, in 46 cycles: **a sustained
six-and-a-bit instructions per cycle.** The dispatch chain alone — token load,
add `DBASE`, code-field load, `XTAB` load, indirect branch — is three dependent
L1 loads and so something like twelve to fifteen cycles of latency. A word
retiring every two cycles with a fifteen-cycle chain in front of it means six or
seven dispatches are in flight at once: the core is decoding one word while the
code-field load of the one before it is still outstanding and the one before
that is still doing arithmetic.

That single fact explains most of what follows. **Instructions are nearly free
on this core; serial dependencies and mispredicted branches are not.**

## The two optimisations ADR 0005 named

ADR 0005 accepted one extra indexed load per dispatch on the grounds that two
other things would matter more. Both now have a number. Each row is the median
of the ratio to the baseline measured *in the same pass*, with the spread over
all passes, because the absolute figures drift between runs and the ratios do
not.

| Variant | `mix.f` | spread | `pick.f` | spread |
|---------|--------:|--------|---------:|--------|
| one shared `NEXT` | **+48%** | 1.48–1.56 | **+47%** | 1.42–1.47 |
| top of stack in memory | **+10%** | 1.05–1.19 | **+10%** | 1.07–1.11 |

Neither spread reaches 1.0. That is the test that matters given the seven per
cent the null control puts on a single pass: the shared-`NEXT` build was slower
in all eleven passes and the memory-top build in all eleven, where two builds
doing the same work flip sign from pass to pass. A ten per cent median that is
above 1.0 eleven times out of eleven is a real ten per cent, even though any one
of those passes on its own would not be worth quoting.

### Inlining `NEXT` is worth far more than expected

Half again as slow, on both benchmarks, in every pass. This is the largest
effect measured anywhere in this ticket, and it is not close.

The shared-`NEXT` build executes *two fewer* instructions per primitive and is
48% slower. Nothing about instruction count explains that. What changes is the
indirect branch: with `NEXT` inlined, the `br x9` inside `prim_plus` only ever
sees what follows `+` in this program, which in a loop is usually the same one
or two words, and the branch predictor gets an entry per word to learn it in.
Collapsing them into one branch site leaves a single entry whose target is a
different word nearly every time.

ADR 0005 expected inlining to matter more than the threading model. It does,
and by a margin that makes the code field's contents look like a rounding
error. The comment in `src/include/dict.h` saying `NEXT` is a macro on purpose
is now a measured claim rather than an expectation.

### The cached top is worth less than expected

Ten per cent, on both benchmarks. That is real and worth having, and it is a
fifth of what inlining `NEXT` buys.

A word like `+` grows from eleven instructions to thirteen: a load of the top
before the pop and a store of it afterwards, because popping moves the cell the
top lives in. Over an iteration of `mix.f` that is 33 extra instructions on
about 296, or 11% more, for 10% more time.

A tenth more instructions for a tenth more time reads like a fair exchange until
it is set beside the guards below, which are two-fifths of every instruction and
under a tenth of the time. The difference is that these particular instructions
are not free. They are a store in one word and a load of the same cell in the
next, so consecutive words are now chained through memory and each pair waits on
store-to-load forwarding. It is the one change measured here that lengthens a
dependency rather than merely adding work beside one, which is why it is the one
whose cost tracks its instruction count at all.

The honest reading is that "keep the top of the stack in a register" is a rule
written for narrower machines, and on this one it is worth ten per cent rather
than the large factor the folklore implies. It also costs the machine a
register: the memory-top build leaves x22 unused, and its data stack holds one
item fewer, because the register really was one extra slot.

The rule in `docs/architecture/design-goals.md` stands — ten per cent on the
most dispatch-heavy code available is not nothing, and giving the register back
buys nothing in particular. But it stands on a smaller margin than ADR 0005
assumed.

## The stack guards

`machine.h` names this ticket as the place the guards get priced. Building with
and without them is the comparison, and `mix.f` and `pick.f` answer different
halves of it.

| Benchmark | with guards | without | guards cost | guard instructions |
|-----------|------------:|--------:|------------:|-------------------:|
| `mix.f` | 10.33 ns | 9.57 ns | **+8%** | 128 of ~296, 43% |
| `pick.f` | 12.93 ns | 11.01 ns | **+17%** | 159 of ~378, 42% |

Read the two right-hand columns together. **The guards are two-fifths of every
instruction aforth executes and under a fifth of its time**, and on `mix.f`
under a tenth. They are close to free, and for the same reason as everything
else here: the core has issue width to spare while it waits on the dispatch
chain, and the guards fill slots that were otherwise idle. Removing 128
instructions from an iteration of `mix.f` saves three and a half cycles out of
forty-six.

### `NEED` and `NEEDX` are not the same guard

Per guard executed, rather than per benchmark:

| Guard | instructions | where | cost each |
|-------|-------------:|-------|----------:|
| `NEED` / `ROOM` / `RNEED` / `RROOM` | 4 | every word that touches a stack | 0.11 cycles |
| `NEEDX`, and the `NEED 1` in front of it | 4 + 5 | `PICK` and `ROLL` only | 0.23 cycles |

Two things make the second row cost twice the first. `PICK` and `ROLL` pay two
guards, not one — `NEED 1` for the count itself, then `NEEDX` for the depth the
count asks for. And `NEEDX` is a longer dependent chain: `DDEPTH` is load,
subtract, shift before the compare, where `NEED` is load, subtract, compare.
The shift is one more link in a chain that cannot be overlapped with itself.

This is what the ticket meant by a single figure for "the guards" hiding more
than it says. The honest statement is that the guards cost 8% on ordinary
words and 17% on a loop built out of `PICK` and `ROLL`.

### Hoisting S0 into a register recovers about a third of the guards

`machine.h` asks whether it pays for itself. It buys something, but much less
than the first reading of these measurements suggested — see the correction
below, which is a lesson about method as much as about registers.

Two variants: `S0` in x27 alone, which leaves x28 free, and `S0` in x27 with the
data stack's low bound in x28, which does not. Every figure is the median of the
ratio to the baseline **measured in the same pass**:

| Build | ratio to baseline | passes below 1.0 | share of the guard cost recovered |
|-------|------------------:|-----------------:|----------------------------------:|
| `S0` in x27 | 0.965 | 5 of 5 | about a third |
| `S0` in x27 and `DS_LO` in x28 | 0.942 | 11 of 13 | about a third to a half |
| guards compiled out entirely | 0.870 | 8 of 8 | all of it, by definition |

So **3.5% for one register and 6% for two**, against the 13% that removing the
guards altogether buys. The direction is solid — the one-register build came out
ahead in all five passes and the two-register build in eleven of thirteen — but
the size is modest, and it is modest on the most dispatch-heavy code in the
project.

The loads are worth more than the rest of the guard, but not by the margin
first claimed. Removing all 128 guard instructions an iteration buys 13%;
removing only the 30 that are loads buys 6%. Per instruction that makes a load
about twice as expensive as the subtract, compare and branch around it, which
is what the load-issue rate suggests — the baseline runs at 2.58 loads a cycle
against the three these cores sustain, and at 6.4 instructions a cycle against
an issue width of eight to ten, so load slots are the scarcer of the two. Twice
as expensive, not infinitely so.

| | instructions | loads | cycles | loads per cycle |
|---|---:|---:|---:|---:|
| baseline | 296 | 119 (32 of them a guard's) | 46.1 | 2.58 |
| `S0` in x27 and `DS_LO` in x28 | 266 | 89 (2 of them a guard's) | 43.4 | 2.05 |

#### The correction, and why it is recorded here

This section first said the hoisted build was *indistinguishable from the build
with the guards compiled out*, and that hoisting therefore recovered the whole
cost of the guards. That was wrong, and the way it went wrong is worth keeping.

The two builds had been measured in different sessions, and their pooled medians
happened to land a fifth of a nanosecond apart — 9.59 ns against 9.57 ns. Read
across sessions like that, they look identical. Timed against each other in the
same pass, they are not close: the hoisted build is 7% to 15% slower than the
no-guard build, in five passes out of five.

This is exactly the error the null control above exists to prevent, made after
that control had been measured and written up. The baseline's own figure moves
by 9% between sessions, so a comparison between two numbers from different
sessions carries that whole spread and says nothing about a 6% effect. Only
ratios taken inside one pass mean anything at this size. Every figure in this
file is now such a ratio, and the ones that were not have been re-measured.

**The price is a register, or both of them.** x27 and x28 are what
[ADR 0006](../adr/0006-assign-eight-registers-to-the-forth-machine.md) left free
so that a word could keep a value across a libc call, and five words use them
for exactly that — `ELSE`, `C,`, `SPACES`, `.S` and `WORDS`. In the variant each
has to save and restore them around its call instead. That is cheap where it
happens, all five being cold. Taking x27 alone is the cheaper half of the
trade: the three words that need only one such register move to x28 and nothing
has to spill, and two-thirds of the gain is still there. Taking both leaves the
machine owning ten of the eleven registers AArch64 makes callee-saved, and every
future word wanting scratch that survives a call reaching for the C stack.
Either way it supersedes part of ADR 0006, and acting on it was out of ticket
012's scope.

## The code field's extra load costs nothing measurable

This is the question [ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md)
left open and
[working-notes/dispatch-cost-of-index-code-fields.md](../working-notes/dispatch-cost-of-index-code-fields.md)
left for this ticket: a code field holds a primitive's index, so dispatch loads
the index and then looks the address up, one indexed load more than a scheme
holding real addresses. The `XTAB`-fixup build removes that load.

Sixteen passes of `mix.f`, eight of them with nothing else competing for the
machine:

| | ratio to baseline | range |
|---|---:|---|
| `mix.f`, 8 dedicated passes | **1.006** | 0.94 – 1.07 |
| `mix.f`, all 16 passes | **1.016** | 0.93 – 1.15 |
| `pick.f`, 3 passes | 0.90 | 0.90 – 0.99 |

**On `mix.f` there is no effect to find.** The median lands within half a per
cent of the baseline and the distribution straddles it evenly; the build with
one fewer instruction in every dispatch is neither faster nor slower than the
one with it. `pick.f` hints at up to ten per cent, on three passes, which is
not enough to claim against sixteen that say nothing.

That confirms the working note's expectation, at the bottom of the range it
gave. The note reasoned that once `NEXT` is inlined the token load and the
`XTAB` load can be hoisted above the primitive's own work and overlap with it,
and predicted "single-digit percent with inlined `NEXT`, much worse without it".
The first half is measured now: not merely single-digit, but under the noise
floor of a careful measurement. The second half is measured too, in the
shared-`NEXT` row above — 48%, which is what the load would have cost had the
hoisting not been there to hide it.

So ADR 0005's accepted cost turns out to be no cost at all on this core, and the
relocation pass the note described — with its extra invariant, its worse failure
mode, and the `:NONAME` problem it would have to solve — buys nothing that can
be measured. The decision stands, and now on evidence rather than on the
argument that it was the cheapest thing to change later.

## Linux/ARM64

The same builds through `docker/Dockerfile`, on the same host, which means a
virtual machine on the same M4 Max. It prices Linux and the toolchain, not the
silicon; a native Linux/ARM64 machine would be a different measurement.

| | macOS | Linux | |
|---|---:|---:|---|
| `mix.f` | 10.33 ns | 10.20 ns | per iteration |
| `mix.f`, no guards | 9.57 ns | 9.31 ns | per iteration |
| `pick.f` | 12.93 ns | 13.36 ns | per iteration |
| guards cost | +8% | +10% | |

Within the spread of the macOS figures on every row. Nothing about the platform
changes any conclusion here, which is the answer that was wanted: the same
source, the same libc-shaped design, and the same speed.

Running the benchmark in the container needs `perl` installed, not just the
`perl-base` that Debian's slim image carries: `Time::HiRes` is core Perl but
Debian splits it out, and `timeit.pl` cannot time anything without it. The test
suite does not need it, using only `alarm` and `exec`. `docker/Dockerfile`
installs it and says why.

## One EMIT costs as much as several hundred words

[output.md](output.md) names this ticket as the place to price the write per
character that `EMIT` and `CR` pay, and that `SPACES` paid until ticket 014.
Not a shipped benchmark, being nothing to do with dispatch, but the same
harness measures it from two throwaway loops that differ only in the middle
word:

```forth
: BENCH BEGIN 32 EMIT 1- DUP 0= UNTIL ;
: BENCH BEGIN 32 DROP 1- DUP 0= UNTIL ;
```

| | macOS | Linux |
|---|---:|---:|
| the loop with `EMIT` | 343.7 ns | 135.3 ns |
| the same loop with `DROP` | 2.7 ns | 3.0 ns |
| **one `EMIT`** | **341 ns** | **132 ns** |
| in words dispatched | about 760 | about 270 |

Both write to `/dev/null`; a terminal or a pipe with a reader costs more. The
gap between the two columns is the `write` syscall, which macOS charges roughly
two and a half times what Linux does — and this is Linux in a virtual machine on
the same host.

The number to take away is the last row. Every conclusion elsewhere in this file
is about tenths of a nanosecond, and a single character printed costs more than
seven hundred of them. Nothing aforth does to its inner interpreter will ever
show up in a program that prints, and buffering output would be worth more than
every dispatch change measured here put together — except that
[ADR 0007](../adr/0007-write-output-on-file-descriptor-1.md) rules a buffer of
aforth's own out, because libedit writes its prompt through stdio and a second
buffer would leave the order of the two to chance. That is a decision with a
price on it now, which it did not have before.

`SPACES` was the one word that could be fixed without reopening that decision,
and ticket 014 fixed it. It writes a run of spaces out of a constant rather than
a byte at a time, which is not a buffer and defers nothing. Padding `42` to a
field of twenty went from 6185 ns to 680 ns. `EMIT` and `CR` have one byte each
and stay as they are.

## Outside bearings

The same two files, unchanged, in two other Forths on the same machine.

| System | `mix.f` per word | vs aforth | `pick.f` per word | vs aforth |
|--------|-----------------:|----------:|------------------:|----------:|
| aforth | 0.448 ns | — | 0.475 ns | — |
| arm64th | 1.765 ns | 3.9× slower | 4.065 ns | 8.6× slower |
| SwiftForth | 0.286 ns | 1.6× faster | 0.291 ns | 1.6× faster |

Both figures are bearings rather than targets, and each for its own reason.

**arm64th** is the more informative of the two. It is a native ARM64 macOS
Forth bootstrapped from arm64 assembly, so nothing is emulated and the
comparison measures the Forth rather than the translation, and it is
indirect-threaded, which is the model ADR 0005 weighed its index code fields
against. What it says is that aforth is in the right neighbourhood — comfortably
so. What it does not say is that indirect threading costs four times, because
the two systems differ in much more than their threading: their primitives are
written differently, arm64th checks no stack depths, and its `PICK` and `ROLL`
look to be colon definitions rather than primitives, which is what the second
column is really reporting. The variant builds above are what isolate the
model; arm64th only says whether the absolute figure is sane.

**SwiftForth is faster than aforth while running under emulation**, and the
right response to that is to read the caveat rather than the number. `sf` is an
x86-64 binary running under Rosetta 2 on Apple silicon, so the comparison
measures the translation as much as the Forth. More to the point, SwiftForth is
a native-code compiler: it inlines primitives into the definition being
compiled and turns `UNTIL` into a machine branch, so it is not dispatching 23
words per iteration at all — it is running straight-line code with no inner
interpreter in it. The per-word column for it is a division by a number that
does not apply. A threaded interpreter losing to a compiler is the expected
result and says nothing about either choice.

## What was decided

Ticket 012 was measurement, and acting on the result was outside it. These are
the decisions taken once the numbers were in, recorded here because the next
person to ask any of these questions will find this file first.

| | Decision |
|---|---|
| The threading model | **Leave it.** ADR 0005 is confirmed on all three counts, and the question is closed |
| `NEXT` inlined per primitive | **Keep.** Worth 48%, the largest effect measured |
| The cached top of stack | **Keep.** Worth 10%, and giving the register back buys nothing |
| The `XTAB` fixup | **Do not build it.** No measurable gain, and it costs a start-up invariant and a worse failure mode |
| The stack guards | **Keep.** 13% for complete stack safety, and the build without them already exists for anyone who disagrees |
| `S0` in x27 | **Not now.** 3.5% for one register, 6% for both; the registers are worth more to the file words and the image format still to be written |
| An output buffer | **Not now.** A new ADR superseding 0007, for an absolute cost that is small in an interactive Forth |
| `SPACES` writing one space per `write` | **Fixed** in ticket 014. Padding `42` to a field of twenty went from 6185 ns to 680 ns |
| No `(` and no `\` | **Fixed** in ticket 014. Both are words now, and the benchmarks dropped their workaround |
| `udiv128`'s bit-at-a-time loop | **Fixed** in ticket 013. Knuth's algorithm D on 32-bit digits, and a `*/` that overflows a cell went from 42.4 ns to 11.6 ns |

The shape of it is that aforth already has the one thing that matters most.
Inlining `NEXT` is worth more than everything else here put together, and it was
done in ticket 002. There is no large win left in dispatch, and the two things
worth doing to this system for speed were both somewhere else, and both are
done: a `SPACES` that does not make a syscall per space, in ticket 014, and a
division that does not loop sixty-four times, in ticket 013.

## What these numbers do not say

- **They are an upper bound.** Both loops are built out of the cheapest words
  in the system, so dispatch is nearly all of what is being timed. A program
  that divides, prints, parses or calls libc spends its time elsewhere and will
  see a fraction of every percentage here. `*/` measured at 4.15 ns, and
  `udiv128`'s long path at about 31 ns before ticket 013 cut it to 1.5. Against
  either of those, a 10% change in dispatch is invisible.
- **They are one core.** Every conclusion above turns on an unusually wide
  out-of-order core with issue slots to spare. A narrower or in-order ARM64
  machine would find the guards expensive and the cached top valuable, because
  there instruction count is the constraint. Nothing here should be read as a
  claim about ARM64 in general.
- **They are one build each.** Changing a variant changes the code layout, and
  layout moves branch-predictor and instruction-cache aliasing around. The null
  control above puts a bound on how much that and the machine together can
  move a single pass — about seven per cent — but does not separate the two.
- **The instruction counts are counted, not measured.** aforth reads no
  performance counters, so "about 296 instructions" comes from reading the
  sources. The times are measured; the instruction counts and the cycle
  arithmetic built on them are arithmetic.
- **The machine was in use.** These were taken on an interactive desktop, not a
  quiet box. The method absorbs most of that and the `drift` column reports the
  rest, but two figures within a few per cent of each other are not reliably
  distinguishable and are not treated as such above.
