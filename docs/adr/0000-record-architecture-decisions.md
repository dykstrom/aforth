# 0000. Record architecture decisions

*2026-09-06*

## Context

aforth is a public project with a single author so far. Decisions about the system are being made
before any Forth code exists — which standard to implement, which platforms to support, which
external libraries to depend on — and the reasoning behind them lives only in conversations. A
future contributor, or the author a year from now, would read the code and not know which
constraints are deliberate and which are accidental. The alternative is to keep the reasoning in
commit messages and prose documentation, which records what changed but not the alternatives that
were rejected.

## Decision

We will record architecturally significant decisions as ADRs in `docs/adr/`, in the format
described by Michael Nygard: Context, Decision, Consequences, one decision per numbered file. An
ADR is immutable once shipped; a later change of course is a new ADR that supersedes the old one by
number.

## Consequences

The reasoning behind a structural choice, a foundational dependency, or an accepted system-wide
constraint stays readable after the conversation that produced it. Numbers are permanent and
sequential, so a decision can be cited by number from `architecture/` rules, working notes, and
later ADRs.

The bar is architectural significance, not importance: a choice localized to one feature or module
does not become an ADR however consequential it feels. Decisions below that bar belong in the other
`docs/` folders. Because a shipped ADR is never edited, a reversal costs a new record rather than a
correction, and the old one stays in place as history.
