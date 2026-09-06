# 0005. Use indirect threading with index code fields

*2026-09-06*

## Context

Warm start is a design goal, so aforth saves a dictionary image and reloads it in a later process.
Both platforms load position-independent executables at a fresh address on every run, which was
measured: the same binary reported `main` at three different addresses across three runs. Any cell
in a saved image holding an absolute code address is therefore invalid on reload, in every run and
not only when the image lands at a new base. The threading model decides how many such addresses
exist. Direct threading writes a branch instruction into each colon definition's code field, and
subroutine threading compiles a `bl` per word, so both turn defining a word into generating code.
Generated code on macOS/ARM64 cannot live in a page that is writable and executable at once: it
needs either `mprotect` between RW and RX plus `sys_icache_invalidate`, or `MAP_JIT` with
`pthread_jit_write_protect_np`, which under the hardened runtime requires a JIT entitlement and
pulls codesigning into the build. Both platforms also require explicit instruction-cache
maintenance after writing instructions. Indirect and token threading generate no code and avoid all
of it. The design goals rank performance below portability and warm-start ability.

## Decision

We will use indirect threaded code in which a code field holds a primitive's index, not its
address, and every link inside the dictionary is an offset from the dictionary base. This is a
hybrid of indirect and token threading. Primitives are assembled ahead of time into the text
segment, and a table built at start-up maps index to address; that table is the only place a real
code address appears. aforth will not generate code at runtime in its first version.

## Consequences

The dictionary contains no absolute addresses, so saving is writing one `mmap`ed region to a file
and loading is mapping it at any address with no relocation pass. Warm start is unaffected by
address space layout randomization. aforth needs no `MAP_JIT`, no JIT entitlement, no codesigning
or notarization step, and no instruction-cache maintenance, so `platform.h` carries no W^X
difference between macOS and Linux.

Dispatch costs one indexed load more than textbook indirect threading, from a table small enough to
stay in cache. Direct and subroutine threading are rejected despite being faster: they make
defining a word an act of code generation, which is the cost this decision avoids. Two
optimisations remain available and are expected to matter more than the threading model — inlining
`NEXT` at the end of each primitive so dispatch is not a single branch-prediction site, and keeping
the top of the data stack in a register.

The code field stays an indirection, so a future version may point a hot word at generated native
code and take on the W^X work then. This decision defers native code generation rather than ruling
it out; reversing it would be a new ADR.
