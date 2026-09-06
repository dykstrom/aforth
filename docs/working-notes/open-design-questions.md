# Open design questions

> **Working note — not authoritative.** Binding rules live in `architecture/` and `adr/`. Nothing
> here is a rule until it's promoted — however settled it reads.

Status: Research note

Goals that are settled live in
[architecture/design-goals.md](../architecture/design-goals.md). This note holds the parts of those
goals where the choice is still open.

## Resolved

### Which line-editing library

libedit, called through its readline-compatible API. Decided in
[ADR 0001](../adr/0001-use-libedit-for-line-editing.md), which records why: readline is GPLv3, and
libedit is BSD-licensed, a system library on macOS, and exposes the same symbol names.

### Which license aforth carries

Apache-2.0, copyright Johan Dykström. Decided in
[ADR 0002](../adr/0002-license-under-apache-2-0.md), which records why: permissive, so saved images
and turnkey binaries stay unconstrained, plus an explicit patent grant that MIT and BSD-2-Clause do
not give.

### Where configuration lives

`$XDG_CONFIG_HOME/aforth/`, falling back to `~/.config/aforth/`, with an `init.f` of Forth source
rather than a parsed configuration format. Decided in
[ADR 0003](../adr/0003-configuration-in-xdg-dir-as-forth-source.md), which records why: the
interpreter already exists, so executing Forth source needs no parser.

### How the source tree is laid out

One flat `src/` directory of `.S` files, with `src/include/` for headers. Every macOS/Linux
difference lives in `src/include/platform.h` rather than inline in a source file. Sources use the
`.S` extension so clang runs the C preprocessor on them, which is what makes that header work.
Split by subsystem later if the flat directory stops being readable.

## Open questions

None. Every question this note opened has been decided and recorded as an ADR.
