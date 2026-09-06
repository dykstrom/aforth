# aforth

A Forth system written in ARM64 assembly, targeting Forth-2012.

## Status

Early development. The build skeleton prints a banner and exits; no Forth is
implemented yet.

## Platforms

macOS/ARM64 (primary) and Linux/ARM64.

## Building

Requires make and clang.

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
