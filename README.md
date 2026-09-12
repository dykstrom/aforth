# aforth

[![macOS](https://github.com/dykstrom/aforth/actions/workflows/macos.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/macos.yml)
[![Linux](https://github.com/dykstrom/aforth/actions/workflows/linux.yml/badge.svg?branch=main)](https://github.com/dykstrom/aforth/actions/workflows/linux.yml)

A Forth system written in ARM64 assembly, targeting Forth-2012.

## Status

Early development. aforth reads Forth at a prompt and runs it until `BYE` or
end of input. The stack, arithmetic, logic, memory, output, input and parsing
words are in place. There is no way to define a word yet.

## Platforms

macOS/ARM64 (primary) and Linux/ARM64.

## Building

Requires make, clang and libedit (a system library on macOS; `libedit-dev` on Linux).

    make        # build build/aforth
    make run    # build and run
    make test   # build and run the test suite

## License

Apache-2.0. See [LICENSE](LICENSE).

## Documentation

- [Design goals](docs/architecture/design-goals.md) — what aforth must do
- [Open design questions](docs/working-notes/open-design-questions.md) — what is still undecided
- [docs/](docs/) — how the documentation is organized
- [AGENTS.md](AGENTS.md) — project context for coding agents
