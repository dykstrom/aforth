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
//   0x128000  transient strings       16 KiB   four buffers of 4 KiB
//   0x12c000  end
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
#define SBUF_OFF        0x128000
#define SBUF_SIZE       0x004000
#define REGION_SIZE     0x12c000

// The transient string buffers, taken round-robin by an interpreted S" .
//
// Forth-2012 11.3.4 asks for at least two of them, at least 80 characters
// each, so that two strings made one after the other are both still there.
// aforth has four, because REGION_SIZE must stay a whole number of 16 KiB
// pages and 16 KiB is the smallest step that keeps it one: the slack goes into
// the count rather than into a fifth area nothing would use.
//
// Each is as large as the input buffer, so a string parsed out of a line
// always fits and nothing has to be truncated or report an overflow. The check
// below is what keeps that true if either size ever moves.
#define SBUF_COUNT      4
#define SBUF_EACH       (SBUF_SIZE / SBUF_COUNT)

// How many spaces write_spaces writes per call to write. Wider than any field
// a program is likely to ask .R for, so padding a number costs one write.
#define SPACES_RUN      64

// How long a path file_open will copy, its terminator included. open takes a C
// string and a Forth string has no terminator after it, so the name is copied
// into file_open's own frame and terminated there. PATH_MAX is 1024 on macOS
// and 4096 on Linux, so a name this long fails in the kernel on both anyway;
// a longer one is ENAMETOOLONG without asking.
#define PATH_BUF        4096

// How much of a file name include_impl copies into its frame, for the message
// an error inside that file prints. The caller's bytes may sit in a transient
// string buffer, which five interpreted S" strings inside the file would take
// back, so the name has to be copied rather than pointed at. Only the message
// is cut short here. file_open copies the whole path itself, up to PATH_BUF.
#define INC_NAME_MAX    256

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
     + RSTACK_SIZE + DSTACK_SIZE + PAD_SIZE + SBUF_SIZE) != REGION_SIZE
.error "aforth: the region areas do not sum to REGION_SIZE"
.endif
.if ((REGION_SIZE / 16384) * 16384) != REGION_SIZE
.error "aforth: REGION_SIZE is not a multiple of the 16 KiB page size"
.endif

// A string parsed out of the input buffer must fit a transient buffer whole.
.if SBUF_EACH < TIB_SIZE
.error "aforth: a transient string buffer is smaller than the input buffer"
.endif

// The user area: thirty-one cells at UP, and the input source stack above
// them.
//
// machine_init sets every one of them before the machine runs, so no cell here
// depends on the region arriving zeroed.
#define UV_S0           0       // DSP when the data stack is empty
#define UV_R0           8       // RSP when the return stack is empty
#define UV_DS_LO        16      // lowest address the data stack may reach
#define UV_RS_LO        24      // lowest address the return stack may reach
#define UV_ABORT        32      // where a guard branches; quit_abort
#define UV_DICT         40      // dictionary base, same as DBASE
#define UV_DICT_END     48      // one past the dictionary
#define UV_HERE         56      // dictionary allocation pointer
#define UV_LATEST       64      // newest entry, an offset from DBASE
#define UV_BASE         72      // number base
#define UV_STATE        80      // 0 interpreting, -1 compiling
#define UV_TIB          88      // input buffer address
#define UV_TIB_LEN      96      // bytes in the input buffer
#define UV_TO_IN        104     // parse offset into the input buffer
#define UV_HOLD         112     // pictured output pointer
#define UV_PAD          120     // PAD address
#define UV_STOP_SP      128     // C stack pointer aforth_enter returns on
#define UV_HOLD_END     136     // one past the pictured output buffer
#define UV_HOLD_LO      144     // lowest address the pictured output may reach
#define UV_ERR_ADDR     152     // the name an error names, when it names one
#define UV_ERR_LEN      160     // how long that name is; 0 for no name
#define UV_SBUF         168     // base of the transient string buffers
#define UV_SBUF_NEXT    176     // the buffer the next interpreted S" takes
#define UV_SOURCE_ID    184     // 0 the terminal, -1 a string, or a fileid
#define UV_SRC_DEPTH    192     // how many sources are stacked under this one
#define UV_SRC_LINE     200     // which line of a file this source is on
#define UV_SRC_NAME     208     // the name of the file, for a message
#define UV_SRC_NAME_LEN 216     // how long that name is; 0 for no name
#define UV_INIT_ADDR    224     // the path --init named, pointing into argv
#define UV_INIT_LEN     232     // how long that path is; 0 for no --init
#define UV_NO_INIT      240     // -1 when --no-init was given, 0 otherwise

// The input source stack.
//
// UV_TIB, UV_TIB_LEN, UV_TO_IN and UV_SOURCE_ID describe the source being read
// now. A source pushed on top of another saves those cells into a slot here and
// installs its own, and popping puts them back. So every word that parses reads
// the same cells it always did, and >IN hands out one fixed address however
// deep the nesting goes — which it must, because a program may store through
// it.
//
// Three more cells ride along so that an error inside an included file can say
// where it happened. REFILL counts the lines of a file into UV_SRC_LINE, and
// include_impl puts the name it opened in UV_SRC_NAME. A terminal or a string
// level leaves all three at 0.
//
// Eight levels of seven cells is 448 bytes, which the user area holds without
// the region changing. A source pushed on a full stack raises
// ERR_SOURCE_TOO_DEEP.
//
// A string source points straight at the caller's bytes: Forth-2012 makes
// EVALUATE's string both the input source and the input buffer, so nothing is
// copied and no line buffer is needed. A file source cannot do that, and
// include_impl carves its line buffer out of its own C stack frame.
// The stack starts at 512 rather than just above the cells, so that adding a
// user variable does not move it. The cells reach 248 now.
#define SRC_STACK_OFF   512
#define SRC_LEVELS      8
#define SRC_SLOT        56

#define SRC_TIB         0
#define SRC_TIB_LEN     8
#define SRC_TO_IN       16
#define SRC_ID          24
#define SRC_LINE        32
#define SRC_NAME        40
#define SRC_NAME_LEN    48

.if (SRC_STACK_OFF + SRC_LEVELS * SRC_SLOT) > USER_AREA_SIZE
.error "aforth: the input source stack does not fit the user area"
.endif

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
// These have been priced; docs/reference/dispatch-performance.md has the working.
// The
// guards are two-fifths of every instruction aforth executes and 8% of its
// time, 17% on a loop of PICK and ROLL, which pay NEED and then NEEDX. The load
// at the top of each one is worth about twice what the subtract, compare and
// branch behind it are worth, but not more than that: hoisting S0 into x27
// buys 3.5% and hoisting UV_DS_LO into x28 as well buys 6%, against the 13%
// that compiling the guards out buys. Each costs a register a word may keep a
// value in across a call, so acting on it would supersede part of ADR 0006 and
// has not been done.
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

// Raise the error in x0, if it holds one, and carry on when it holds 0. This is
// what a word does with the status a dictionary routine returns: dict_comma and
// the rest report rather than raise, because machine_quit calls them too and
// cannot be unwound. Shaped like the guards for the same reason they are, a
// conditional branch on Mach-O being unable to name machine_error in another
// file.
//
// Only for code running inside aforth_enter, as the guards are.
.macro  RAISE
        cbz     x0, .Lraise_ok\@
        b       machine_error
.Lraise_ok\@:
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
// first four; the ten after them are raised by the words that meet them — a
// divide by zero, a pictured output overflow, an input line too long for the
// buffer, a name the dictionary does not hold, a defining word with no name
// left on the line, a name too long to count in one byte, a dictionary with no
// room left, a control-flow word given something that is not a place in the
// dictionary, a source stack with no level free, a file that ends inside a
// comment, and a file INCLUDED could not open.
//
// The last three are not failures to report. ABORT and QUIT leave the machine
// the same way an error does, because they must not return to the word that ran
// them, and machine_quit tells them apart by the number: it prints nothing for
// either, and empties the data stack for ABORT but not for QUIT.
//
// ERR_REPORTED is a failure that has already printed. include_impl writes the
// message and its own traceback line as it unwinds, because the file name and
// the line number live in a frame that dies before machine_quit sees the
// number. It then raises this instead, and machine_quit clears up without
// printing a second message.
//
// These three stay the highest numbers, because quit_report tells a message
// from a silent exit by comparing against the last one that has a message.
//
// The numbers are runtime only. Nothing writes one to disk, so unlike a code
// field's index they may be renumbered when an error is added in the middle.
#define ERR_DS_UNDERFLOW        1
#define ERR_DS_OVERFLOW         2
#define ERR_RS_UNDERFLOW        3
#define ERR_RS_OVERFLOW         4
#define ERR_DIV_ZERO            5
#define ERR_HOLD_OVERFLOW       6
#define ERR_LINE_TOO_LONG       7
#define ERR_UNDEFINED_WORD      8
#define ERR_NO_NAME             9
#define ERR_NAME_TOO_LONG       10
#define ERR_DICT_FULL           11
#define ERR_CONTROL_FLOW        12
#define ERR_SOURCE_TOO_DEEP     13
#define ERR_UNTERMINATED_COMMENT 14
#define ERR_OPEN_FAILED         15
#define ERR_REPORTED            16
#define ERR_ABORT               17
#define ERR_QUIT                18

#endif // AFORTH_MACHINE_H
