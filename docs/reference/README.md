# reference/

The long version of "why we think this". When a question has been worked through
far enough that the view has stopped shifting, the full argument goes here.

Different from `adr/`: an ADR is a short record of one decision. A reference doc
is the essay behind it, with the evidence in it.

## What is here

[`dispatch-performance.md`](dispatch-performance.md) — what aforth's inner
interpreter costs, how it was measured, what each variant build changed, and
what the numbers mean. It is the argument behind
[ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md) and the
guard rules in [`../architecture/machine-rules.md`](../architecture/machine-rules.md),
and it grew out of
[`../working-notes/dispatch-cost-of-index-code-fields.md`](../working-notes/dispatch-cost-of-index-code-fields.md).

## What goes here

- One markdown file per stabilized topic, kebab-case.
- A short intro saying which question the doc answers.
- The full argument: what was measured or considered, what was rejected, why the
  conclusion followed. Evidence, not assertion.
- Links back to the originating working note and to any ADR it supports.

## What does not go here

- Half-formed opinions → [`../working-notes/`](../working-notes/).
- One decision and its consequences → an ADR in [`../adr/`](../adr/).
- "Do X, then Y" → a system doc or the code. Reference docs explain *why*.
- A figure a future change has to beat: that belongs in `../system/`, where it
  will be kept current. This folder holds the working, not the target.

## Lifecycle

A reference doc is the **output** of a working note that stabilized. Promotion
is deliberate: the note's `Status:` reaches `Stabilizing` and stays there, the
substance is lifted here and restructured as an argument rather than as
chronological thinking, and the note flips to `Promoted` and is frozen.

Revised only when the underlying opinion changes, and a revision is itself a
deliberate act.
