// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The word tests: run each case in a table of them through the machine and
// check what it left on the stack.
//
// This is aforth testing itself from inside, because there is no prompt yet to
// feed Forth source to. The driver is here; the cases are the table in
// interpreter.S, which is where the tokens they name are known. Ticket 009
// deletes both, once the outer interpreter can read a test in Forth.
//
// Nothing is printed when every case passes, so a failure shows up in the test
// suite's exit status as well as in its output.

#include "dict.h"

        SECTION_RODATA
        .p2align        3
msg_test_pre:
        .asciz  "aforth: "
msg_test_post:
        .asciz  " failed its stack test\n"
msg_guard_post:
        .asciz  " failed its depth guard\n"
msg_test_empty:
        .asciz  "aforth: the word test table is empty\n"
msg_guard_empty:
        .asciz  "aforth: the depth guard table is empty\n"

// Scratch for the cases that need somewhere to write, and a known eight bytes
// for MOVE to copy. A case names these by address, which is why the case table
// is in writable data: a pointer there is fixed up when the binary loads.
        .data
        .p2align        3
        .globl  test_scratch
test_scratch:
        .space  64
        .globl  test_source
test_source:
        .quad   0x1122334455667788

// Strings the parsing and lookup cases name. A counted string carries its
// length in the first byte, which is what WORD leaves and what FIND takes; the
// plain ones are for the words that take an address and a length.
        .globl  test_cs_dup
test_cs_dup:
        .byte   3
        .ascii  "DUP"
        .globl  test_cs_dup_lower
test_cs_dup_lower:
        .byte   3
        .ascii  "dup"
        .globl  test_cs_missing
test_cs_missing:
        .byte   3
        .ascii  "ZZZ"
        .globl  test_cs_hidden
test_cs_hidden:
        .byte   6
        .ascii  "(STOP)"
        .globl  test_s_123
test_s_123:
        .ascii  "123"
        .globl  test_s_12x
test_s_12x:
        .ascii  "12x"
        .globl  test_s_ff
test_s_ff:
        .ascii  "FF"
        .globl  test_s_minus42
test_s_minus42:
        .ascii  "-42"
        .globl  test_s_wat
test_s_wat:
        .ascii  "wat"
        .globl  test_s_colon
test_s_colon:
        .ascii  ":"
        .globl  test_s_2p64
test_s_2p64:
        .ascii  "18446744073709551616"
        .globl  test_s_nines
test_s_nines:
        .ascii  "999999999999999999999"

        .text

// Run the table at x0. Returns nothing: a case that fails names the word it
// was testing and exits 1.
//
// The driver keeps its place in the table on the C stack, not in a register.
// A word may use x27 and x28 as it likes, so nothing of ours survives a call
// into the machine.
        .p2align        2
        .globl  machine_test_words
        FUNC_TYPE(machine_test_words)
machine_test_words:
        stp     x29, x30, [sp, #-80]!
        mov     x29, sp
        str     x0, [sp, #16]           // where we are in the table
        str     xzr, [sp, #56]          // cases run

        // An abort has to come back to us rather than exit, so that a case
        // expecting one can say whether it got it.
        adr_sym x0, test_abort
        str     x0, [UP, #UV_ABORT]

tw_case:
        ldr     x2, [sp, #16]
        ldr     x3, [x2], #8            // the word's entry; 0 ends the table
        cbz     x3, tw_done
        str     x3, [sp, #40]
        ldr     x3, [x2], #8            // the error this case expects
        str     x3, [sp, #48]

        // Both stacks empty, whatever the case before left behind.
        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        mov     TOS, #0

        ldr     x4, [x2], #8            // cells to put on, deepest first
1:      cbz     x4, 2f
        ldr     x5, [x2], #8
        DPUSH   x5
        sub     x4, x4, #1
        b       1b

2:      ldr     x4, [x2], #8            // cells expected afterwards
        str     x4, [sp, #32]
        str     x2, [sp, #24]
        add     x2, x2, x4, lsl #3

        ldr     x4, [x2], #8            // the token list's length
        mov     x0, x2                  // the list itself
        add     x2, x2, x4, lsl #3
        str     x2, [sp, #16]           // the case after this one

        bl      aforth_enter

        ldr     x1, [sp, #48]
        cmp     x0, x1                  // did it stop the way it should?
        b.ne    tw_failed
        cbnz    x1, tw_ok               // an abort leaves no stack worth reading

        DDEPTH  x0
        ldr     x4, [sp, #32]
        cmp     x0, x4
        b.ne    tw_failed

        // Compare deepest first. The top item is the cached one; the rest are
        // in memory, and the i-th from the bottom is at S0 - 8 * (i + 2)
        // whatever the depth. The two cells that offset accounts for are the
        // top item, which is not in memory at all, and the cell the first push
        // spilled the undefined top into, which nothing reads.
        ldr     x6, [sp, #24]
        ldr     x7, [UP, #UV_S0]
        mov     x5, #0
3:      cmp     x5, x4
        b.ge    tw_ok
        ldr     x10, [x6, x5, lsl #3]   // what the case expects
        add     x11, x5, #1
        cmp     x11, x4                 // the last one is the cached top
        b.eq    4f
        add     x11, x5, #2
        sub     x12, x7, x11, lsl #3
        ldr     x13, [x12]
        cmp     x13, x10
        b.ne    tw_failed
        add     x5, x5, #1
        b       3b
4:      cmp     TOS, x10
        b.ne    tw_failed

tw_ok:
        ldr     x1, [sp, #56]
        add     x1, x1, #1
        str     x1, [sp, #56]
        b       tw_case

tw_done:
        ldr     x1, [sp, #56]
        cbz     x1, tw_empty            // a table that ran nothing passed nothing

        // Put the machine back the way machine_init left it.
        adr_sym x0, quit_abort
        str     x0, [UP, #UV_ABORT]
        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        mov     TOS, #0

        ldp     x29, x30, [sp], #80
        ret

tw_failed:
        ldr     x0, [sp, #40]
        adr_sym x1, msg_test_post
        b       test_report

tw_empty:
        adr_sym x0, msg_test_empty
        b       test_report_plain
        FUNC_SIZE(machine_test_words)

// Run the guard table at x0. Each case runs one word with too little on a
// stack and must get the error the case names.
//
// The cases are all the same shape, so the table is one line each and the
// token list sits inside the case, at a fixed offset the driver knows.
        .p2align        2
        .globl  machine_test_guards
        FUNC_TYPE(machine_test_guards)
machine_test_guards:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        str     x0, [sp, #16]
        str     xzr, [sp, #48]          // cases run

        adr_sym x0, test_abort
        str     x0, [UP, #UV_ABORT]

tg_case:
        ldr     x2, [sp, #16]
        ldr     x3, [x2]                // the word's entry; 0 ends the table
        cbz     x3, tg_done
        str     x3, [sp, #24]
        ldr     x3, [x2, #8]            // the error this case expects
        str     x3, [sp, #32]
        ldr     x4, [x2, #16]           // how many items to put on

        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        mov     TOS, #0

        mov     x5, #0                  // one item short of enough, and
1:      cmp     x5, x4                  // distinguishable if one is read
        b.ge    2f
        add     x5, x5, #1
        DPUSH   x5
        b       1b

2:      add     x0, x2, #24             // the case's own token list
        add     x2, x2, #40
        str     x2, [sp, #16]           // the case after this one

        bl      aforth_enter

        ldr     x1, [sp, #32]
        cmp     x0, x1
        b.ne    tg_failed

        ldr     x1, [sp, #48]
        add     x1, x1, #1
        str     x1, [sp, #48]
        b       tg_case

tg_done:
        ldr     x1, [sp, #48]
        cbz     x1, tg_empty

        adr_sym x0, quit_abort
        str     x0, [UP, #UV_ABORT]
        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        mov     TOS, #0

        ldp     x29, x30, [sp], #64
        ret

tg_failed:
        ldr     x0, [sp, #24]
        adr_sym x1, msg_guard_post
        b       test_report

tg_empty:
        adr_sym x0, msg_guard_empty
        b       test_report_plain
        FUNC_SIZE(machine_test_guards)

// Report a failed case and exit. x0 is the word's entry as an offset from
// DBASE, x1 the message to follow its name with. The name comes out of the
// dictionary entry itself, so it is the word's own name and not a copy kept
// beside the case. Never returns.
        .p2align        2
test_report:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]           // the word's entry
        str     x1, [sp, #24]           // what to say about it
        adr_sym x0, msg_test_pre
        bl      write_stderr
        ldr     x1, [sp, #16]
        add     x1, DBASE, x1
        ldrb    w2, [x1, #ENT_COUNT]
        add     x1, x1, #ENT_NAME
        mov     x0, #2                  // fd 2; the name is counted, not NUL-ended
        bl      CSYM(write)
        ldr     x0, [sp, #24]
        // fall through

// Write the NUL-terminated message at x0 and exit 1. Never returns.
        .p2align        2
test_report_plain:
        bl      write_stderr
        mov     w0, #1
        bl      CSYM(exit)

// Where an abort lands while the tests run: out of aforth_enter, carrying the
// error number as its result.
        .p2align        2
test_abort:
        b       enter_return
