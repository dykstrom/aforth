# 0003. Read configuration from an XDG directory as Forth source

*2026-09-06*

## Context

The design goals require that the user can configure which editor aforth opens and that aforth
reads init files on cold start. Neither the location nor the form was settled. For location, the
alternatives were a single `~/.aforthrc` dotfile, which leaves no natural home for later files, and
each platform's own directory — `~/Library/Application Support/aforth` on macOS against
`~/.config/aforth` on Linux — which adds a platform difference for no benefit to a terminal
program. For form, the alternative was a parsed key-value file, which needs a parser written in
ARM64 assembly and can express only the settings built into it. A Forth system already has an
interpreter, so an init file of Forth source costs no new code and can express anything the
language can; GNU gforth takes the same approach with `~/.gforth-init`.

## Decision

We will read configuration from `$XDG_CONFIG_HOME/aforth/`, falling back to `~/.config/aforth/`
when that variable is unset, on both platforms. Forth source files use the `.f` extension, so the
cold-start init file is `init.f`; it holds Forth source that the interpreter executes, and there is
no configuration format and no parser. The editor comes from `$VISUAL`, then `$EDITOR`, then a
built-in default of `vi`; `init.f` may override it.

## Consequences

One lookup path serves both platforms, so configuration adds nothing to `platform.h`. The init file
gains the full power of the language, and every configurable setting is a Forth word rather than a
key the parser has to know about. The XDG directory gives later files — a history file, saved
images — a place to live without a second convention.

Because `init.f` is executed as code, it is a trust boundary. aforth MUST NOT read an init file
from the current directory: doing so would run arbitrary code when a user starts aforth inside a
directory someone else wrote. Only the XDG path and an explicit `--init <file>` argument are read.
A `--no-init` flag MUST exist so tests and bug reports can run without user configuration; the test
suite will need it as soon as init files are implemented.

The `.f` extension is also Fortran's, so editors and language-detection tools may read `.f` files as
Fortran. A `*.f linguist-language=Forth` line in `.gitattributes` corrects GitHub's detection if it
guesses wrong once files exist.

Saved images are data rather than configuration, and XDG puts data under `$XDG_DATA_HOME`
(`~/.local/share`). That path is not decided here.
