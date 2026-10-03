# aforth

[![macOS](https://github.com/dykstrom/aforth/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/macos.yml)
[![Linux](https://github.com/dykstrom/aforth/actions/workflows/linux.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/linux.yml)

A Forth system written in ARM64 assembly, targeting Forth-2012.

## Status

Early development. aforth reads Forth at a prompt and runs it until `BYE` or
end of input. In the terms Forth-2012 uses to label a system, aforth is:

- Providing the Core word set
- Providing name(s) from the Core Extensions word set: all but `C"`, `HOLDS`,
  `RESTORE-INPUT`, `SAVE-INPUT` and `[COMPILE]`
- Providing name(s) from the File-Access word set: all but `BIN`,
  `CREATE-FILE`, `DELETE-FILE`, `R/W`, `RESIZE-FILE`, `W/O`, `WRITE-FILE` and
  `WRITE-LINE`
- Providing name(s) from the File-Access Extensions word set: `FILE-STATUS` and
  `INCLUDE`
- Providing name(s) from the Programming-Tools word set: `.S` and `WORDS`
- Providing name(s) from the Programming-Tools Extensions word set: `BYE`

At start-up aforth reads two files: the system file `aforth.f` that ships
beside the binary, and the user's own `init.f` under
`$XDG_CONFIG_HOME/aforth/`.

## AI assistance

aforth is built with AI assistance. Claude Code wrote much of the assembly, the
tests and the documentation, working from specifications written for it.

A person designs the system and decides what goes into it, but has not read
every line of every commit.

## Platforms

macOS/ARM64 (primary) and Linux/ARM64.

## Building

Requires make, clang and libedit (a system library on macOS; `libedit-dev` on Linux).

    make        # build build/aforth
    make run    # build and run
    make test   # build and run the test suite
    make bench  # build and time the inner interpreter

## License

Apache-2.0. See [LICENSE](LICENSE).

## Documentation

- [Design goals](docs/architecture/design-goals.md) — what aforth must be
- [Machine rules](docs/architecture/machine-rules.md) — the rules for writing it
- [docs/](docs/) — how the documentation is organized
- [AGENTS.md](AGENTS.md) — project context for coding agents
