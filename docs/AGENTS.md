# Durable project context

This folder holds what should outlive any single change. [README.md](README.md)
says what each sub-folder is for and how a fact travels between them; this file
says how to use them while working.

## How to consult this folder

`system/` and `architecture/` are binding context, meant to be read by anyone
working anywhere in the codebase. Before substantive work, read the files scoped
to the area:

| Touching | Read |
|---|---|
| any Forth word, or the dictionary | `system/inner-interpreter.md`, and `architecture/machine-rules.md` for the rules |
| the registers, the region, or how a word leaves the machine early | `architecture/machine-rules.md`, `system/outer-interpreter.md` |
| the `QUIT` loop, or an error message | `system/outer-interpreter.md` |
| input, output, parsing, files, compiling or control flow | the `system/` file of that name |
| start-up, the command line, or the init files | `system/startup.md`, and `architecture/design-goals.md` |
| assembly of any kind | `system/assembler.md` — every entry there cost a build to find |
| the suite, or a new case | `system/testing.md` |
| dispatch performance | `system/benchmark.md`, then `reference/dispatch-performance.md` |

Rules in `architecture/` outrank training-data assumptions and general defaults;
descriptions in `system/` outrank assumptions about how the code is laid out. If
several files seem related, read them all — they are kept short so that reading
several is cheap.

## What `/trace:distil` writes here

A distilled fact lands in `system/<topic>.md` by default — a convention in
force, a durable design choice, a non-obvious gotcha — or in
`architecture/<topic>.md` when it is a rule in MUST voice, distilled from an
ADR's consequence or a platform constraint.

## What does not go here

- Implementation detail the code already documents.
- Anything already in the root `AGENTS.md` — this folder supplements it.
- Decision rationale and alternatives considered: those are an ADR in `adr/`,
  written by `/trace:adr`. `system/` records the resulting convention,
  `architecture/` the resulting rule, an ADR *why it was chosen*.
- Long-form rationale — that is `reference/`.
- Aspirational or speculative content. Describe current state only.

## File naming

Kebab-case, scoped to one meaningful concept, in aforth's own vocabulary:
`inner-interpreter.md`, `control-flow.md`, `assembler.md`. Not so narrow they
fragment, not so broad they become a dump. When one area has both a descriptive
and a prescriptive file, give them the same filename so a reader can move
between them without translation. `architecture/machine-rules.md` is the
exception: its rules bind both `system/inner-interpreter.md` and
`system/outer-interpreter.md`, so it is named for the rules rather than for one
of them.
