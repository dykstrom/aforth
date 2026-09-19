# docs/

Everything written about aforth lives here, sorted by what each file is for.

Before you read a doc, you need to know what kind it is. There are three, and
they have different update rules:

```
docs/
├── system/         ← DESCRIPTIVE  — what the code does today (updated as code changes)
├── architecture/   ← PRESCRIPTIVE — what the code must do (updated as rules change)
├── adr/            ← HISTORICAL   — one decision each (immutable once shipped)
├── reference/      ← HISTORICAL   — the long argument behind a decision (append-only)
└── working-notes/  ← HISTORICAL   — research; not authoritative until promoted
```

| Folder | Holds | Update semantics |
|---|---|---|
| [`system/`](system/) | How the machine, the interpreter, the words, the build and the tests actually work. Binding context for anyone working in those areas. | Updated in the same change as the code. |
| [`architecture/`](architecture/) | `design-goals.md`, what aforth must be; `machine-rules.md`, the rules for writing it. MUST voice, each rule citing its ADR. | Updated when the rules change. |
| [`adr/`](adr/) | One architectural decision per file, with its context and consequences. | Immutable once shipped; supersede, never edit. |
| [`reference/`](reference/) | The full argument behind a decision, too long for an ADR — `dispatch-performance.md` is the one so far. | Append-only; revised deliberately. |
| [`working-notes/`](working-notes/) | Thinking still in motion. Nothing here is a rule. | In motion until promoted. |

## How content flows

A question starts as a working note. If it resolves a structural choice, an ADR
records the decision. If the argument behind it is longer than an ADR should be,
the substance is promoted into `reference/` and the note is frozen. The rule the
decision imposes goes into `architecture/`, and `system/` describes the code that
satisfies it.

```
working-notes/ ──→ reference/ ──→ adr/       how the decision was made

                   adr/ ──→ architecture/    the rule, in force

                            ↓

                          system/            the code that satisfies it
```

aforth has walked that whole path once:
[`working-notes/dispatch-cost-of-index-code-fields.md`](working-notes/dispatch-cost-of-index-code-fields.md)
asked what an index code field costs,
[`reference/dispatch-performance.md`](reference/dispatch-performance.md)
answered it with measurements, [ADR 0005](adr/0005-indirect-threading-with-index-code-fields.md)
records the decision, [`architecture/machine-rules.md`](architecture/machine-rules.md)
states the rule, and [`system/inner-interpreter.md`](system/inner-interpreter.md)
describes the dispatch that results.

## What does not go here

- Source, scripts and build output — those live in `src/`, `lib/`, `test/` and
  `build/`.
- Anything the code already says. A doc that repeats a routine's comment goes
  stale on its own schedule.

Each sub-folder has a README with its own rules. Read it before adding a file
there.
