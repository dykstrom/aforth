# 0001. Use libedit for input line editing

*2026-09-06*

## Context

The design goals require input line editing at the interactive prompt. GNU readline is the
obvious library for this and was the original candidate, but readline 6.0 and later are
GPLv3-or-later, so linking it forces aforth itself to be GPLv3-compatible. That collides with two
other goals: aforth is meant for anyone to use, and warm start means the system can save an image
containing its own kernel, so a user's turnkey binary would embed GPLv3 code and inherit the
license. libedit is the alternative, BSD-licensed, and it exposes a readline-compatible API with
the same symbol names alongside its own native API. A third force is the build goal of make and
clang only: readline on macOS comes from Homebrew as a keg-only formula, so its headers and
libraries are outside the default search paths and the Makefile would have to detect them, while
libedit is a system library on macOS and needs no flags beyond `-ledit`.

## Decision

We will link libedit and call it through its readline-compatible API — `readline`, `add_history`,
and the `rl_*` completion hooks — not through libedit's native `el_*` API. The library comes from a
Makefile variable, so a build can link GNU readline against the same symbols instead.

## Consequences

macOS needs nothing installed and the Makefile keeps to make and clang with no dependency-path
detection. The BSD license leaves aforth's own license open and keeps saved images and turnkey
binaries unconstrained, so the license question in `working-notes/open-design-questions.md` is now
independent of the line-editing choice rather than blocked by it. Because the symbol names match,
switching to GNU readline later is a Makefile change and not a rewrite.

We accept a smaller feature set: libedit's compatibility header exposes 69 functions against
readline's 288, and users configure it through `~/.editrc` rather than the `~/.inputrc` many already
have. Two constraints follow for future work. libedit's native `el_set` is variadic, and Apple's
ARM64 ABI passes variadic arguments on the stack where Linux passes them in registers, so the
native API must stay unused. On macOS `libreadline.tbd` is a symlink to `libedit.3.tbd`, so a
`-lreadline` build there links libedit and proves nothing about real readline behaviour. Linux
builds need `libedit-dev`, which must be added to `docker/Dockerfile` and
`.github/workflows/linux.yml` when line editing lands.
