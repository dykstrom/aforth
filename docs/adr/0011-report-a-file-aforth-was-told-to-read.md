# 0011. Report a file aforth was told to read, and pass over one it only looked for

*2026-09-16*

## Context

ADR 0003 requires aforth to read init files at cold start. It also forbids aforth from making a
directory or a file on the user's behalf. Cold start now reads three files. The system file
`aforth.f` ships beside the binary. The user's `init.f` sits under `$XDG_CONFIG_HOME/aforth/`. The
file `--init` names is whatever the user typed.

Each fails differently. A user on a fresh install has no `init.f`, and that is the ordinary case
rather than a fault. A binary with no `aforth.f` beside it starts with words missing, and the user
meets that later as an undefined word. A `--init` file that will not open means a typed command did
nothing.

Two other rules were weighed. The first stayed silent about both files aforth finds by itself and
reported only the `--init` file. A binary moved away from its system file then says nothing, and the
missing words surface as a puzzle. The second made a missing system file fatal. A single
`rm build/aforth.f` then stops the binary instead of leaving it usable.

## Decision

We will report every file aforth was told to read, and say nothing about the one it only looks for.
Cold start asks `file_status` about the user's `init.f` before opening it, and drops a path nothing
answers to without a word.

## Consequences

A user with no `init.f` sees nothing and gets nothing. No message, no error, no exit status, and no
directory or file made for them. ADR 0003's requirement is kept by the same rule that reports
everything else.

The rule classifies the files ADR 0003 foresees. A history file and a saved image are each either
told-to-read or looked-for, and that has to be settled before either is written.

Telling "there but will not open" from "not there" costs two calls rather than one. `file_status`
runs, then `file_open`, and the answer can change between them. A file made in that gap is read, and
one removed in it is reported as unopenable. The window is microseconds and neither outcome harms
the user.

None of this changes the exit status. Every one of these failures leaves the prompt to come up, and
the process still exits 0 at the end of input. A command line that will not parse stays the only
thing at start-up that exits 1.
