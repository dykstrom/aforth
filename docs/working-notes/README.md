# working-notes/

Thinking while it is still in motion. Rough notes, half-formed opinions,
questions not yet answered. When one settles, its substance moves into
`reference/` or an ADR and the note stays here, frozen.

**Nothing in this folder is authoritative**, however settled it reads. Binding
rules live in [`../architecture/`](../architecture/) and [`../adr/`](../adr/).

## What a note looks like

Every note opens with the non-authority banner, right under the title:

> **Working note — not authoritative.** Binding rules live in `architecture/` and `adr/`. Nothing
> here is a rule until it's promoted — however settled it reads.

Then a `Status:` line, a `Resolved` section that grows as questions get answered
within the note, and an `Open questions` section even when it is empty. One file
per topic, kebab-case, no date prefix — git history is the date.

| Status | Means |
|---|---|
| `Research note` | Active thinking. Opinions may flip. |
| `Stabilizing` | Most questions resolved; the take looks right but is not promoted. |
| `Promoted` | Substance lifted into `reference/` or an ADR. Frozen. |

## What does not go here

- Settled rationale you intend to cite → [`../reference/`](../reference/).
- "We chose A over B" → an ADR in [`../adr/`](../adr/).
- New content added to a note that has already been promoted. The note stays
  frozen as a record of how the thinking went.

Promotion is never automatic. Don't promote without explicit go-ahead. The full
funnel is in [`../README.md`](../README.md).
