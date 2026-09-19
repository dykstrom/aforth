# architecture/

The rules aforth has to follow, written as plain "must do" statements.

`system/` says what the code does — "`dict_find` walks the chain from `LATEST`."
`architecture/` says what it must keep doing — "the dictionary MUST NOT contain
absolute code addresses." Where `adr/` records the decision behind a rule, this
folder records the rule itself.

## The two files

- **`design-goals.md`** — what aforth must *be*. The standard it implements, the
  platforms it runs on, warm start, line editing, configuration, licensing, and
  the one trade-off that is stated as such: performance may not be pursued at
  the cost of portability or warm start.
- **`machine-rules.md`** — what anyone writing the machine must *do*. What the
  dictionary may hold, which registers belong to the Forth machine and which may
  not be touched at all, how a word leaves the machine early, where output goes,
  and what a character is.

Read `machine-rules.md` before writing implementation code. Several of its rules
forbid the approach that would otherwise be obvious.

## What does not go here

- A decision with alternatives considered → an ADR in [`../adr/`](../adr/). An
  ADR records what was chosen and why; this folder records the resulting rule.
- The long argument → [`../reference/`](../reference/). A rule cites it; it does
  not reproduce it.
- A description of the current implementation → [`../system/`](../system/).
- A proposed rule → [`../working-notes/`](../working-notes/) until it is decided.
- A rule nobody intends to enforce. Every rule here is binding.

## Format

Imperative voice — **MUST / MUST NOT / SHOULD / SHOULD NOT**, never "we
recommend" or "ideally". Short, scannable, no prose explaining the rule. Each
rule names what it constrains, and each section cites its source:

```markdown
## Output

- aforth MUST write all output with `write` on file descriptor 1, through
  `write_stdout` in `src/machine.S`.
- aforth MUST NOT print through a stdio stream, `puts` and `printf` included,
  and MUST NOT hold an output buffer of its own.
- Source: [ADR 0007](../adr/0007-write-output-on-file-descriptor-1.md).
```

A rule with no nameable source is a smell: either it is not a rule, or the
reasoning needs writing up in `reference/` and citing from here.

## Conventions

- Rules here change when the rules change — distinct from `system/`, which
  changes when the code does, and from `adr/`, which does not change at all.
- If a rule needs three paragraphs of justification, the justification belongs
  upstream and the rule itself stays terse.
