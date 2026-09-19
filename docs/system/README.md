# system/

What aforth's code does today. One file per area, so that a reader — or an agent
— can get up to speed on the machine, the interpreter or the build without
reading every `.S` file.

If you are working in an area that has a file here, trust it. It is meant to be
the most accurate picture of how things actually work.

## The files

| File | What it covers |
|------|----------------|
| [`inner-interpreter.md`](inner-interpreter.md) | the entry format, and the five rules the defining macros impose |
| [`arithmetic.md`](arithmetic.md) | the choices Forth-2012 leaves open, such as which way division rounds |
| [`output.md`](output.md) | the one path every printed byte takes, and how a number is formatted |
| [`input.md`](input.md) | how a line arrives, how input sources nest, and what `KEY` does to the terminal |
| [`parsing.md`](parsing.md) | how a name is cut out and looked up |
| [`outer-interpreter.md`](outer-interpreter.md) | the `QUIT` loop, and the one path every error takes |
| [`compiling.md`](compiling.md) | how the dictionary grows, and what `:` and `;` build |
| [`control-flow.md`](control-flow.md) | how a definition branches |
| [`files.md`](files.md) | how a file is opened, read and included, and what an ior carries |
| [`startup.md`](startup.md) | what `main` does in order, what the three command-line flags decide, and which of the two init files cold start may miss in silence |
| [`testing.md`](testing.md) | how to write a case, and the ways a case passes while testing nothing |
| [`benchmark.md`](benchmark.md) | what a word costs, and how to measure it again |
| [`assembler.md`](assembler.md) | the toolchain's own traps |
| [`ci.md`](ci.md) | the two workflows, and why the Linux runner is pinned |

## What goes here

- One file per meaningful area, kebab-case, in aforth's own vocabulary:
  `inner-interpreter.md`, `control-flow.md`, `assembler.md`. The table above is
  the set as it stands.
- Concise prose. Name the routine, name the file, and say the thing the code
  cannot say about itself — why a guard may not be used here, which of two
  routines reports and which raises, what the standard left open and which way
  aforth went.
- Every file opens by naming where its code lives, so a reader lands in the
  right file first.

## What does not go here

- *Why* a rule exists → [`../adr/`](../adr/) for the decision,
  [`../reference/`](../reference/) for the long argument. A system file records
  the resulting convention.
- The rules themselves → [`../architecture/`](../architecture/).
- Thinking still in motion → [`../working-notes/`](../working-notes/).
- Anything planned rather than built. These files describe what *is*.
- What the code already documents. If you can read the routine and know the
  answer, the doc does not need to repeat it — a line of assembly and a line of
  prose describing it drift apart on different schedules.

## Lifecycle

Updated **in the same change as the code**. A change that adds a convention,
moves a word to another file, or invalidates a sentence here corrects this
folder in that same change. A stale system doc is worse than a missing one,
because it is trusted.

`benchmark.md` is the one file with a companion in `reference/`: it holds the
figures a change has to beat, and
[`../reference/dispatch-performance.md`](../reference/dispatch-performance.md)
holds how they were obtained.
