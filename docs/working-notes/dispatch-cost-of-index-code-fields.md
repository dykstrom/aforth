# Dispatch cost of index code fields

> **Working note — not authoritative.** Binding rules live in `architecture/` and `adr/`. Nothing
> here is a rule until it's promoted — however settled it reads.

Status: Research note

[ADR 0005](../adr/0005-indirect-threading-with-index-code-fields.md) is shipped and stands: a code
field holds a primitive's index, a token is an offset from `DBASE`. This note records the question
that came up afterwards — *could the dictionary hold real addresses and rewrite them at warm start
instead?* — so the alternative and its caveats are not lost between now and the first benchmark.

## Resolved

### A general relocation pass at warm start cannot work

Rewriting addresses on load requires knowing which cells hold addresses. In a Forth image you
cannot know that. A definition body is untyped cells: tokens, literals, branch offsets, inline
strings, `,`-compiled data. And an xt is a first-class value in Forth-2012 — `'`, `FIND`,
`EXECUTE`, `DEFER`/`IS`, a jump table built with `' FOO ,`, an xt stored in a `VARIABLE` or a
buffer. User code can put an xt in any cell of the image, including cells the compiler never wrote.

So the two ways to find them both fail:

- a relocation table the compiler maintains — incomplete the moment a user program stores an xt
  itself, which is ordinary Forth practice;
- a conservative scan ("is this cell inside the old text range?") — unsound, a literal can alias.

An index or an offset is inherently position-independent, so it does not matter where the value is
stored. That is the real strength of ADR 0005, and it is a stronger argument than the one the ADR
makes: 0005 stops at "an absolute address is invalid on reload" without adding "and you cannot
enumerate them".

### There is a middle ground: relocate only the code fields

Code fields *are* enumerable. Each sits at a known offset in a dictionary entry, reachable by
walking the link chain from `UV_LATEST`. So relocate exactly those and leave every other cell an
offset:

```
; today
ldr   W, [IP], #8              ; token = offset from DBASE
add   W, DBASE, W              ; entry address
ldr   w9, [W]                  ; code field = primitive index
ldr   x9, [XTAB, x9, lsl #3]   ; index -> address
br    x9

; code field holds a real address, rebuilt at warm start
ldr   W, [IP], #8
add   W, DBASE, W
ldr   x9, [W]                  ; code field = address
br    x9
```

The entry must then say what kind of code field it wants — primitive N, `DOCOL`, `DOVAR`, `DOCON`,
`DODOES` — which is a few flag bits in the header plus, for a primitive, the index that exists
anyway. Warm start walks the chain once and writes each code field: O(entries), microseconds.
`XTAB` stays, as the table the walk reads from; it just leaves the dispatch path.

This keeps everything ADR 0005 bought — no runtime code generation, no W^X, no JIT entitlement, no
instruction-cache maintenance — because the values written are addresses of primitives assembled
ahead of time, not instructions.

Two caveats:

- `:NONAME` produces an xt with no header and so is not in the link chain. Nameless entries would
  have to be linked too; giving them a zero-length name is the tidy fix.
- The failure mode is worse. A code field that is missed is a branch to a stale address; an index
  cannot go stale. Loading stops being a pure `mmap` and gains an invariant ("code fields are
  garbage until the fixup pass has run") that every path into the image has to respect.

### What the extra indirection costs

The dispatch dependency chain today is `ldr` → `add` → `ldr` → `ldr` → indirect branch. The `XTAB`
load adds one instruction and roughly four cycles of latency; the `lsl #3` is free in the
addressing mode. Against a primitive like `+` that does one cycle of real work, that is not noise —
perhaps 20-30% on primitive-dense code if nothing hides it.

Most of it should hide, though. Once `NEXT` is inlined at the end of each primitive, the token load
and the `XTAB` load can be hoisted above the primitive's own work and overlap with it, and an
M-series core has ample window for that. What cannot be hidden is the indirect branch, and that
cost is the same in all three schemes. Expectation: single-digit percent with inlined `NEXT`, much
worse without it. That is an expectation, not a measurement. The measurements below price dispatch
in absolute terms but do not isolate the increment, which is still unmeasured.

Clarity is close to a wash. Tokens stay offsets either way, so `EXECUTE`, `'`, `>BODY` and `DEFER`
need the same `add DBASE` conversion in both schemes. The index version is one line longer in
`NEXT` and one table build at start-up; the fixup version is shorter in `NEXT` and carries a
relocation pass and its invariant.

### Why the decision stays as it is for now

Cheapest to change later. Dispatch lives in one macro in `src/include/machine.h`, the code field's
meaning is documented in one place, and the save format is the simplest one available. When there
are real words and a benchmark — ticket 012, which already prices the stack guards — the fixup
variant is a contained experiment. ADR 0005's closing paragraph already anticipates the code
field's meaning changing; switching it from an index to a fixed-up address would be a new ADR
superseding it.

## First measurements

*2026-09-09.* Taken while ticket 004 landed, on an Apple M4 Max under macOS 26.5.2 with Apple clang
21.0.0, default build so the stack guards are compiled in. These came out of a question about `*/`
and `*/MOD`, which ticket 004 defines as token lists rather than primitives, so they measure a
word's threading cost rather than the code field's.

### Method

A temporary definition holding a hundred copies of the body, called a hundred thousand times from
the word test driver, so ten million iterations cost ten thousand tokens of table. Each variant
was a separate build; the figure is the best of seven runs of the whole binary, less 2.2 ms for
start-up and the test cases. A throwaway primitive `*/` was written for the comparison and then
reverted. Wall clock on a whole process, not cycle counts: there is no profiler in this yet.

### What came out

Ten million iterations, each `DUP DUP` followed by the body under test:

| body | total | per iteration |
|------|-------|---------------|
| `DUP DROP`, for scale | 11.5 ms | 1.15 ns |
| `*/` as a token list | 70.1 ms | 7.01 ns |
| `>R M* R> SM/REM NIP` inline, no colon wrapper | 54.3 ms | 5.43 ns |
| `*/` as a primitive | 41.5 ms | 4.15 ns |

Taking the `DUP DUP` off each, `*/` itself costs 5.9 ns as a token list against 3.0 ns as a
primitive, so about twice as much. The same run with operands whose product overflows a cell, which
is what `*/` is for, gives 41.3 ns against 37.4 ns: the same absolute overhead, now a tenth of the
total, because the software division dominates.

Three numbers fall out of that, and they are the reusable part:

- **A word dispatched costs 0.4 to 0.6 ns**, body included, for a one-instruction word with its
  guard. Ten instructions in something between two and three cycles, so the core is issuing about
  four per cycle and predicting the indirect branch well.
- **A colon nesting level costs about 0.8 ns**, a `DOCOL` and its `EXIT`. That is the number to
  weigh when deciding whether a word is worth writing in assembly: `*/` pays it twice, once for
  itself and once for the `*/MOD` it calls.
- **`udiv128`'s long path costs about 35 ns**, sixty-four iterations at roughly 2.4 cycles each.
  That is twelve times the whole threading overhead of `*/`, and the only figure here big enough to
  be worth chasing. Dividing on 32-bit halves with `udiv` would replace the loop with a handful of
  instructions.

### What this does not settle

Not the question this note opened. These figures price dispatch as it stands; they say nothing
about what the `XTAB` load adds, because there is nothing to compare against until the fixup
variant exists. The absolute cost being small is consistent with the expectation above — an
M-series core hiding the load behind the primitive's own work — but consistent is not the same as
measured.

Isolating it means building the middle ground described earlier: walk the link chain at start-up,
write each code field as a real address, and drop the `XTAB` load from `NEXT`. That is a contained
experiment on top of what exists now, and ticket 012 is where it belongs.

Two more caveats. The per-word figures subtract an estimated `DUP DUP` cost taken from the
`DUP DROP` row rather than measuring it in place. And the guards are compiled in, which is four
instructions on every word that reads a stack, so every figure here carries them; ticket 012 prices
those separately.

## Open questions

### Does the region need a fixed address?

The same argument that sinks a general relocation pass applies to *data* addresses. `HERE`, a
`VARIABLE`'s address, the address of a buffer — a user can store any of them in any cell, and they
are equally unenumerable at load. So ADR 0005's "mapping it at any address with no relocation pass"
holds for links and tokens, but not for a cell a user program filled with an address.

That points at mapping the region at a fixed address (`MAP_FIXED` at some chosen high address) when
save and restore are built, and failing warm start loudly if the address is unavailable. Undecided;
belongs to whichever ticket implements the image format.
