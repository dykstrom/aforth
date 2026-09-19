# adr/

A short record of each significant choice about how aforth is built, and why.
One file per decision. When someone asks "why is it like this?" — including
future-you — this folder is the answer.

## What goes here

- Numbered files, strictly sequential: `0001-<short-kebab-name>.md`,
  `0002-<...>.md`. The title reads as a noun phrase, as
  `0005-indirect-threading-with-index-code-fields.md` does.
- One decision per file, in three sections: **Context** (the forces in tension,
  the alternatives considered), **Decision** (what we will do, active voice),
  **Consequences** (what becomes easier, what becomes harder).
- No `Status` field. A shipped ADR is accepted by definition. Supersession adds
  a `> Superseded by <NNNN>.` line under the title — the only edit a shipped ADR
  ever takes.
- `0000-record-architecture-decisions.md` declares that aforth uses ADRs and how.

## What does not go here

- Alternatives still being weighed → [`../working-notes/`](../working-notes/).
  An ADR captures a *resolved* decision, not the debate.
- The full argument → [`../reference/`](../reference/). ADRs are short minutes;
  reference docs are essays. If an ADR has grown past two screens, the substance
  belongs in a reference doc it links to — as
  [ADR 0005](0005-indirect-threading-with-index-code-fields.md) relates to
  [`../reference/dispatch-performance.md`](../reference/dispatch-performance.md).
- The rule the decision imposes → [`../architecture/`](../architecture/).
- Implementation detail or how-to → the codebase, or `../system/`.

## Lifecycle

ADRs are **immutable once shipped**:

- **Draft** — local, unpushed, nobody has acted on it. Edit freely. A tidy
  revised version beats a `0001 + 0002 (supersedes 0001)` pair one day old.
- **Shipped** — committed, pushed, or already acted on by other work. Immutable.
  A future reader needs the decision as it stood when it was made, and
  downstream commits and ADRs may quote its exact wording.

Rule of thumb: if anyone else has had reason to read it, treat it as shipped.

When superseding one, add the `> Superseded by <NNNN>.` line to the **old** ADR
and leave its body untouched. The new ADR explains what changed and references
the old one by number in its Context. Never renumber, never reuse a number.

## When to write one

Only for an *architecturally significant* decision — one whose implications are
scattered system-wide rather than localized to one feature. The test is not "is
this significant?" but "is this *architectural*?"

aforth's own are the shape of it: which threading model the inner interpreter
uses, which registers the machine owns, which line-editing library is linked,
which licence the project carries, where output goes, how a word leaves the
machine.

Not an ADR: a choice local to one word or one file, however durable; a gotcha to
respect; a naming or formatting convention; anything the code already captures.
Costly to reverse is not the same as architectural.
