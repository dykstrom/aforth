# aforth

[![macOS](https://github.com/dykstrom/aforth/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/macos.yml)
[![Linux](https://github.com/dykstrom/aforth/actions/workflows/linux.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/linux.yml)

A Forth system written in ARM64 assembly, targeting Forth-2012.

## Status

Early development. aforth reads Forth at a prompt and runs it until `BYE` or
end of input. The stack, arithmetic, logic, memory, output, input and parsing
words are in place. A user can define words with `:` and `;`, `CREATE`,
`CONSTANT` and `VARIABLE`, and branch inside them with `IF ELSE THEN`,
`BEGIN UNTIL WHILE REPEAT AGAIN` and `RECURSE`. A program can write a string
with `S"` or `."`, and interpret one with `EVALUATE`. It can open and read a
file with `OPEN-FILE` and `READ-LINE`, and load another program with
`INCLUDE`.

At start-up aforth reads two files: the system file `aforth.f` that ships
beside the binary, and the user's own `init.f` under
`$XDG_CONFIG_HOME/aforth/`. There is no counted loop and no way to write a
file.

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
- [Open design questions](docs/working-notes/open-design-questions.md) — what is still undecided
- [docs/](docs/) — how the documentation is organized
- [AGENTS.md](AGENTS.md) — project context for coding agents
