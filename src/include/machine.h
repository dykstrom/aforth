// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// aforth's machine model.
//
// Three things live here: the registers the Forth machine runs in, the layout
// of the one memory region it works out of, and the macros every primitive
// uses to touch the stacks. A primitive never names DSP or RSP directly, so a
// change to the stack invariant is a change to this file alone.
//
// See docs/adr/0005-indirect-threading-with-index-code-fields.md for why the
// dictionary base and the index-to-address table each get a register: a token
// compiled into a definition is an offset from the dictionary base, not an
// address, so dispatch reads both on every word.

#ifndef AFORTH_MACHINE_H
#define AFORTH_MACHINE_H

#include "platform.h"

// Registers.
//
// AArch64 gives ten callee-saved registers, x19 to x28. libc preserves them,
// so a value in one survives a call to puts or readline. Eight are the Forth
// machine:
//
//   IP     address of the next token in the list being run
//   DSP    data stack pointer; points at the second item, not the top
//   RSP    return stack pointer; points at the top item
//   TOS    top item of the data stack
//   W      word register; dispatch leaves the current entry here
//   DBASE  dictionary base; tokens and links are offsets from it
//   XTAB   base of the index-to-address table
//   UP     base of the user area
//
// Forth-2012 calls it the data stack, so the register is DSP and the macros
// that touch it are named with a leading D. The older Forth name for it, the
// parameter stack, is not used anywhere in aforth.
//
// Rules for a primitive, which is the part that is easy to get wrong:
//
//   x0-x15    free, clobber at will
//   x16, x17  never use; the Mach-O dynamic linker clobbers them at any call
//   x18       never use; reserved for the platform on both targets
//   x19-x26   machine state; change only as the word's own job requires
//   x27, x28  free, and preserved across a libc call
//   x29, x30  frame pointer and link register; a word that calls libc saves x30
//
// The guard macros below clobber x9, so a word puts its guard first, before x9
// holds anything live.
#define IP      x19
#define DSP     x20
#define RSP     x21
#define TOS     x22
#define W       x23
#define DBASE   x24
#define XTAB    x25
#define UP      x26

// TOS seen 32 bits wide, for the words that move one byte: C@ zero-extends into
// it, C! stores out of it.
#define TOSW    w22

// The region.
//
// One anonymous mapping, carved at start-up. The order is deliberate: each
// stack has an area of our own both above and below it, so an overrun of a few
// cells touches our own memory instead of faulting. That matters for the build
// with the guards compiled out.
//
//   0x000000  user area                4 KiB
//   0x001000  index-to-address table  16 KiB
//   0x005000  dictionary               1 MiB
//   0x105000  input buffer             4 KiB
//   0x106000  pictured output buffer   4 KiB
//   0x107000  return stack            64 KiB
//   0x117000  data stack              64 KiB
//   0x127000  PAD                      4 KiB   slack above the data stack
//   0x128000  end
//
// The index-to-address table is the one area whose contents are true only for
// the process that built them. It holds addresses, so a saved image must treat
// it as garbage and have start-up fill it again; see machine_build_xtab.
#define USER_AREA_SIZE  0x001000
#define XTAB_OFF        0x001000
#define XTAB_SIZE       0x004000
#define DICT_OFF        0x005000
#define DICT_SIZE       0x100000
#define TIB_OFF         0x105000
#define TIB_SIZE        0x001000
#define HOLD_OFF        0x106000
#define HOLD_SIZE       0x001000
#define RSTACK_OFF      0x107000
#define RSTACK_SIZE     0x010000
#define DSTACK_OFF      0x117000
#define DSTACK_SIZE     0x010000
#define PAD_OFF         0x127000
#define PAD_SIZE        0x001000
#define REGION_SIZE     0x128000

// How many routines the table holds, which is the ceiling on the number of
// primitives. One 16 KiB page is 2048 of them, far more than a Forth needs.
#define XTAB_MAX        (XTAB_SIZE / 8)

// Derived: the ends of the areas that are filled from the top downward.
#define DICT_END_OFF    (DICT_OFF + DICT_SIZE)
#define HOLD_END_OFF    (HOLD_OFF + HOLD_SIZE)
#define R0_OFF          (RSTACK_OFF + RSTACK_SIZE)
#define S0_OFF          (DSTACK_OFF + DSTACK_SIZE)

// The sizes must tile the region exactly, and the region must be whole pages.
// macOS/ARM64 uses 16 KiB pages, so a later save can write whole pages.
.if (USER_AREA_SIZE + XTAB_SIZE + DICT_SIZE + TIB_SIZE + HOLD_SIZE \
     + RSTACK_SIZE + DSTACK_SIZE + PAD_SIZE) != REGION_SIZE
.error "aforth: the region areas do not sum to REGION_SIZE"
.endif
.if ((REGION_SIZE / 16384) * 16384) != REGION_SIZE
.error "aforth: REGION_SIZE is not a multiple of the 16 KiB page size"
.endif

// The user area: twenty-one cells at UP.
//
// Start-up sets all of them. Most exist here only so that their offset is
// fixed once; the ticket that reads each one is named.
#define UV_S0           0       // DSP when the data stack is empty
#define UV_R0           8       // RSP when the return stack is empty
#define UV_DS_LO        16      // lowest address the data stack may reach
#define UV_RS_LO        24      // lowest address the return stack may reach
#define UV_ABORT        32      // where a guard branches; quit_abort in 008
#define UV_DICT         40      // dictionary base, same as DBASE
#define UV_DICT_END     48      // one past the dictionary; 010
#define UV_HERE         56      // dictionary allocation pointer; 010
#define UV_LATEST       64      // newest entry, an offset from DBASE; 010
#define UV_BASE         72      // number base; 005 and 007
#define UV_STATE        80      // 0 interpreting, -1 compiling; 008 and 010
#define UV_TIB          88      // input buffer address; 006
#define UV_TIB_LEN      96      // bytes in the input buffer; 006
#define UV_TO_IN        104     // parse offset into the input buffer; 007
#define UV_HOLD         112     // pictured output pointer; 005
#define UV_PAD          120     // PAD address; 005
#define UV_STOP_SP      128     // C stack pointer aforth_enter returns on
#define UV_HOLD_END     136     // one past the pictured output buffer
#define UV_HOLD_LO      144     // lowest address the pictured output may reach
#define UV_ERR_ADDR     152     // the name an error names, when it names one
#define UV_ERR_LEN      160     // how long that name is; 0 for no name

// The data stack.
//
// TOS caches the top item, so the memory stack holds the items below it. Both
// stacks grow downward. S0 is the value DSP holds when the stack is empty.
//
//   depth 0   DSP = S0        TOS undefined
//   depth 1   DSP = S0 - 8    TOS is the item; the cell at [DSP] is dead
//   depth n   DSP = S0 - 8n   TOS is the top; [DSP] is the second item
//
// Depth is (S0 - DSP) >> 3 at every depth, zero included. The dead cell at
// depth 1 is why DROP is one instruction: DPOPM reloads a cell nobody reads,
// and the depth arithmetic stays right.

// Spill the cached top into memory. TOS is then free to overwrite.
.macro  DPUSHM
        str     TOS, [DSP, #-8]!
.endm

// Take a cell off the memory stack. With no argument it refills the cached
// top, which is DROP. With a register it loads the second item and leaves the
// cached top alone, which is what a binary operator wants: + is then two
// instructions and still names no stack pointer.
.macro  DPOPM dst=TOS
        ldr     \dst, [DSP], #8
.endm

// Push src, which becomes the new top.
.macro  DPUSH src
        DPUSHM
        mov     TOS, \src
.endm

// Pop the top into dst.
.macro  DPOP dst
        mov     \dst, TOS
        DPOPM
.endm

// Reaching into a stack without moving its pointer.
//
// DGETM and DSETM read and write one cell of the memory stack. Index 0 is the
// second item on the data stack, 1 the third, and so on: the top item is in
// TOS and not in memory at all. DGETMX and DSETMX take that index in a
// register instead, which is what PICK and ROLL need.
//
// RGET and RSET are the same for the return stack, where index 0 is the top
// item, because the whole of that stack is in memory.
//
// These exist so that a word like SWAP or ROT can rearrange the stack in place
// rather than popping and pushing its way through it, and still name no stack
// pointer of its own.
.macro  DGETM i, dst
        ldr     \dst, [DSP, #((\i) * 8)]
.endm

.macro  DSETM i, src
        str     \src, [DSP, #((\i) * 8)]
.endm

.macro  DGETMX idx, dst
        ldr     \dst, [DSP, \idx, lsl #3]
.endm

.macro  DSETMX idx, src
        str     \src, [DSP, \idx, lsl #3]
.endm

.macro  RGET i, dst
        ldr     \dst, [RSP, #((\i) * 8)]
.endm

.macro  RSET i, src
        str     \src, [RSP, #((\i) * 8)]
.endm

// How many items the data stack holds, the cached top included. This is the
// arithmetic DEPTH does, and the guards below do it too.
.macro  DDEPTH dst
        ldr     \dst, [UP, #UV_S0]
        sub     \dst, \dst, DSP
        asr     \dst, \dst, #3
.endm

.macro  RPUSH src
        str     \src, [RSP, #-8]!
.endm

.macro  RPOP dst
        ldr     \dst, [RSP], #8
.endm

// The guards.
//
// NEED n errors unless the data stack holds n items; ROOM n errors unless n
// more cells fit. RNEED and RROOM are the same for the return stack. The
// comparison is signed, so a stack pointer that has already run past its end
// still reports an error rather than wrapping to a large unsigned value.
//
// Each one tests the good case and jumps over a branch to its handler, rather
// than branching to the handler on the bad case. A conditional branch on
// Mach-O cannot name a symbol in another file, and the handlers are in
// machine.S, so the direct form only assembles inside that one file. The
// instruction count on the path a word actually takes is the same either way.
//
// Ticket 012 builds with -DAFORTH_NO_STACK_CHECKS to price these. Whether
// hoisting S0 into x27 pays back the load is for that ticket to measure.
#ifndef AFORTH_NO_STACK_CHECKS

.macro  NEED n
        ldr     x9, [UP, #UV_S0]
        sub     x9, x9, DSP
        cmp     x9, #((\n) * 8)
        b.ge    .Lneed_ok\@
        b       ds_underflow
.Lneed_ok\@:
.endm

.macro  ROOM n
        ldr     x9, [UP, #UV_DS_LO]
        sub     x9, DSP, x9
        cmp     x9, #((\n) * 8)
        b.ge    .Lroom_ok\@
        b       ds_overflow
.Lroom_ok\@:
.endm

.macro  RNEED n
        ldr     x9, [UP, #UV_R0]
        sub     x9, x9, RSP
        cmp     x9, #((\n) * 8)
        b.ge    .Lrneed_ok\@
        b       rs_underflow
.Lrneed_ok\@:
.endm

.macro  RROOM n
        ldr     x9, [UP, #UV_RS_LO]
        sub     x9, RSP, x9
        cmp     x9, #((\n) * 8)
        b.ge    .Lrroom_ok\@
        b       rs_overflow
.Lrroom_ok\@:
.endm

// NEED with the count in a register, for PICK and ROLL, whose depth
// requirement is whatever number the user put on the stack.
.macro  NEEDX reg
        DDEPTH  x9
        cmp     x9, \reg
        b.ge    .Lneedx_ok\@
        b       ds_underflow
.Lneedx_ok\@:
.endm

#else

.macro  NEED n
.endm
.macro  ROOM n
.endm
.macro  RNEED n
.endm
.macro  RROOM n
.endm
.macro  NEEDX reg
.endm

#endif // AFORTH_NO_STACK_CHECKS

// Raise a pictured output overflow unless reg, the hold pointer about to be
// decremented, is still above the bottom of the buffer. Not a stack guard
// either, for the same reason NONZERO is not: a number built past the end of
// the buffer would write over the input buffer below it, and Forth-2012 leaves
// what happens to the system rather than to the program.
//
// It is also what stops a BASE of 1, which divides a number by itself forever
// and holds a digit every time round.
.macro  HOLDROOM reg
        ldr     x9, [UP, #UV_HOLD_LO]
        cmp     \reg, x9
        b.hi    .Lholdroom_ok\@
        b       hold_overflow
.Lholdroom_ok\@:
.endm

// Raise a divide by zero unless reg holds something else. Not a stack guard:
// it stays in the build that compiles those out, because a zero divisor is a
// real error and not a check on aforth's own bookkeeping. Shaped like the
// guards for the same reason they are, a conditional branch being unable to
// name div_zero in another file.
.macro  NONZERO reg
        cbnz    \reg, .Lnonzero_ok\@
        b       div_zero
.Lnonzero_ok\@:
.endm

// Error numbers a word hands to the routine in UV_ABORT. The guards raise the
// first four; the next four are raised by the words that meet them — a divide
// by zero, a pictured output overflow, an input line too long for the buffer,
// and a name the dictionary does not hold.
//
// The last two are not failures. ABORT and QUIT leave the machine the same way
// an error does, because they must not return to the word that ran them, and
// machine_quit tells them apart by the number: it prints nothing for either,
// and empties the data stack for ABORT but not for QUIT.
#define ERR_DS_UNDERFLOW        1
#define ERR_DS_OVERFLOW         2
#define ERR_RS_UNDERFLOW        3
#define ERR_RS_OVERFLOW         4
#define ERR_DIV_ZERO            5
#define ERR_HOLD_OVERFLOW       6
#define ERR_LINE_TOO_LONG       7
#define ERR_UNDEFINED_WORD      8
#define ERR_ABORT               9
#define ERR_QUIT                10

#endif // AFORTH_MACHINE_H
