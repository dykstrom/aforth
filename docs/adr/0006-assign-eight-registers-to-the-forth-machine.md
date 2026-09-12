# 0006. Assign eight callee-saved registers to the Forth machine

*2026-09-08*

## Context

ADR 0005 settled indirect threading with index code fields, and two consequences of it reach into
register allocation. A token compiled into a definition cannot hold an absolute address, so it
holds an offset from the dictionary base, which means dispatch adds that base to every token and
then reads a second table, the one mapping a primitive's index to its address. ADR 0005 also named
two optimisations it expected to matter more than the threading model: inlining `NEXT` at the end
of each primitive, and keeping the top of the data stack in a register. AArch64 offers ten
callee-saved registers, x19 to x28, and libc preserves them, so a value in one survives a call to
`puts` or `readline`; x16 and x17 are clobbered by the Mach-O dynamic linker at any call and x18 is
reserved for the platform, so none of those three is available. Two narrower allocations were
weighed. Six registers, with no pointer to the system variables, reaches that table and those
variables through the dictionary base instead, costing one more instruction inside a `NEXT` that is
repeated at every primitive. Five registers, with the top of the data stack left in memory, makes
`+` four instructions instead of two and `DROP` three instead of one. No primitive existed yet, so
the choice was still cheap.

## Decision

We will give the Forth machine eight of the ten callee-saved registers: x19 the instruction
pointer, x20 the data stack pointer, x21 the return stack pointer, x22 the top item of the data
stack, x23 the word register, x24 the dictionary base, x25 the base of the index table, and x26 the
base of the user area. x27 and x28 stay free for primitives. The top item of the data stack lives
in x22 and the memory stack holds the items below it, so an empty stack is a data stack pointer
equal to its start value with x22 undefined, and depth is that difference shifted right by three.

## Consequences

Dispatch costs five instructions, none of them spent forming an address; `+` costs two and `DROP`
one. Every primitive is written against one convention, held as macros in `src/include/machine.h`,
so a change to the stack invariant is a change to one file rather than to every word.

Three constraints follow. A primitive gets x0 to x15 freely, and x27 and x28 across a libc call,
and must spill anything beyond that. The top of the stack is undefined when the stack is empty, so
a word that reads the stack needs a guard or a wrong depth passes unnoticed; each guard costs a
load and a compare, and they compile out under `-DAFORTH_NO_STACK_CHECKS`. x16, x17 and x18 must
stay unused, and nothing in the build enforces that.

The instruction counts above are read from the source, not measured. Reversing this allocation once
the primitives exist means rewriting all of them, so the measurement is planned while their number
is still small.
