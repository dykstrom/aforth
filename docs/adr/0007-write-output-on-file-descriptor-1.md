# 0007. Write output with write on file descriptor 1

*2026-09-11*

## Context

Ticket 005 added the words that print: `EMIT`, `TYPE`, `CR`, `.` and the rest. They need one way
to reach the terminal, and the C library offers two. Writing through a stdio stream means naming
`stdout`, which is a libc variable rather than a function, and its symbol differs between the
platforms — `__stdoutp` on macOS, `stdout` on Linux — so reaching it from assembly needs a GOT
load and a new macro in `src/include/platform.h`. aforth already avoided that for errors:
`write_stderr` writes to file descriptor 2 instead of naming `stderr`. A second alternative kept
stdio but named no stream, calling `putchar`, which is a function and takes no `FILE *`, with
`fflush(NULL)` as the flushing rule. Two forces pull against stdio buffering. Line editing uses
libedit (ADR 0001), which writes its prompt through stdio and flushes it, so a second buffer of
aforth's own would make the order of the prompt and the output depend on both buffers. And the
test suite reads captured output, so the order in a pipe has to equal the order at a terminal.

## Decision

We will write every byte of aforth's output with `write` on file descriptor 1, through one routine,
`write_stdout` in `src/machine.S`, and keep no output buffer of our own. Nothing prints through
stdio: `main` writes its banner with `puts_stdout` rather than `puts`.

## Consequences

There is no flushing rule, so there is none to get wrong, and a terminal and a pipe receive the
same bytes in the same order. Output costs no platform difference, which leaves
`src/include/platform.h` covering the same five differences it covered before. When libedit
arrives, its prompt cannot be overtaken by output aforth is still holding.

`EMIT`, `CR` and `SPACES` each cost one `write` call per character, so a program that prints
character by character pays a syscall for each one. Ticket 012 prices that. Removing the cost means
giving aforth a buffer of its own, and then something has to flush it before every line read and
before the process exits — the rule this decision exists to avoid. Until then, a new call to
`puts`, `printf` or any other stdio function for output breaks the ordering this relies on.
