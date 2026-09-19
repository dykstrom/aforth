# Machine rules

The rules that bind anyone writing aforth's machine: what may go in the dictionary, which
registers belong to whom, how a word leaves the machine early, where output goes, and what a
character is. They follow from the goals in [design-goals.md](design-goals.md) and from the ADRs
each section cites.

Read this before writing implementation code. Several rules forbid the obvious approach.

The descriptive side — what the code does today — is in
[system/inner-interpreter.md](../system/inner-interpreter.md) and
[system/outer-interpreter.md](../system/outer-interpreter.md).

## What the dictionary may hold

- The dictionary MUST NOT contain absolute code addresses. A code field MUST hold a primitive's
  index, and a link inside the dictionary MUST be an offset from the dictionary base. Executables
  load at a fresh address on every run, so a saved image holding an absolute address is invalid on
  reload.
- An execution token MUST be the offset of a code field from the dictionary base, never an address
  and never the offset of the entry that carries it. `EXECUTE` adds the base back, and 0 is not a
  token: the dictionary's first cell is reserved so that name lookup can return 0 for a name it did
  not find.
- aforth MUST NOT generate code at runtime. Generated code on macOS/ARM64 requires W^X handling and
  a JIT entitlement, and both platforms require instruction-cache maintenance.
- Source: [ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md).

## Machine model

- The Forth machine MUST live in the eight registers named in `src/include/machine.h`: x19 the
  instruction pointer, x20 the data stack pointer, x21 the return stack pointer, x22 the top data
  stack item, x23 the word register, x24 the dictionary base, x25 the index table base, and x26 the
  user area base.
- The top item of the data stack MUST be held in a register, not in memory.
- The top item MUST be treated as undefined when the stack is empty, so a word that reads the stack
  MUST check the depth first.
- A primitive MUST reach the stacks through the macros in `src/include/machine.h`, and MUST NOT name
  a stack pointer register directly.
- A routine that a word calls MUST NOT change x27 or x28. A primitive may keep values in those two
  registers across a libc call, and a callee that clobbers one takes that away. `write_stderr` in
  `src/machine.S` holds its argument on the stack for this reason.
- x16, x17 and x18 MUST NOT be used. The Mach-O dynamic linker clobbers x16 and x17 at any call,
  and x18 is reserved for the platform on both targets.
- Source: [ADR 0006](../adr/0006-assign-eight-registers-to-the-forth-machine.md).

## Leaving the machine

- Everything that leaves the Forth machine early MUST go through the vector in `UV_ABORT` and out
  of `aforth_enter`, carrying a number. That covers the stack guards, a word that raises, and
  `ABORT` and `QUIT`, which are not failures but must not return to the word that ran them either.
- The routine in the vector MUST NOT print. `machine_quit` reads the number, prints what it means,
  and empties what that number says to empty, unless the number says the message is already
  written.
- A word MUST NOT write its own error message, unless the message needs context the unwind
  destroys — a file name or a line number in a frame about to be popped. A word that does MUST
  take the text from `quit_report`, MUST raise `ERR_REPORTED` afterwards so that nothing prints
  twice, and MUST pass `ERR_ABORT` and `ERR_QUIT` on untouched, neither being a failure.
  Source: [ADR 0010](../adr/0010-report-a-located-error-as-the-machine-unwinds.md).
- A routine that a word calls while that word holds a resource MUST report an error by returning
  a number, not by raising one. A raise unwinds to the last `aforth_enter`, past the frame that
  would release the resource. `interpret_source`, `refill_impl` and `src_push` all report for
  that reason. Each is called by a word holding an open file or an installed input source.
- A guard macro — `NEED`, `ROOM`, `RNEED`, `RROOM` — MUST NOT be used by code running outside
  `aforth_enter`. `enter_return` puts `sp` back to the frame of the last `aforth_enter`, and that
  frame is gone. Such code MUST make the comparison itself, as `machine_quit` does before it pushes
  a number.
- Source: [ADR 0008](../adr/0008-leave-the-machine-through-one-vector.md).

## Output

- aforth MUST write all output with `write` on file descriptor 1, through `write_stdout` in
  `src/machine.S`.
- aforth MUST NOT print through a stdio stream, `puts` and `printf` included, and MUST NOT hold an
  output buffer of its own. libedit writes its prompt through stdio and flushes it, and a second
  buffer would leave the order of the prompt and the output to the two buffers.
- Source: [ADR 0007](../adr/0007-write-output-on-file-descriptor-1.md).

## Text and characters

- One character MUST be one byte. Text MUST be held as UTF-8-encoded byte sequences.
- `TYPE`, `S"`, the parser, and dictionary name lookup MUST stay byte-oriented.
- Case folding for name lookup MUST cover ASCII `A`-`Z` only. Bytes of 0x80 and above MUST be left
  unchanged.
- aforth MUST call `setlocale(LC_CTYPE, "")` at start-up, before initialising line editing.
- aforth MUST NOT normalize or collate text.
- The Forth-2012 Extended Characters word set is deferred. When implemented it MUST be an optional
  extension declared through `ENVIRONMENT?`.
- Source: [ADR 0004](../adr/0004-represent-text-as-utf-8-bytes.md).
