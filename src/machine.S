// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Start-up for aforth's machine: allocate the one region, carve it, fill the
// user area, and call the two routines in interpreter.S that build the dispatch
// table and the dictionary. The register convention and the region layout live
// in src/include/machine.h.
//
// The stack guards land in this file too: ds_underflow and its three siblings
// name the error and go through the vector in the user area. What the vector
// points at, and what each error number prints, is in src/outer.S.

#include "machine.h"

        SECTION_RODATA
        .p2align        3
msg_mmap:
        .asciz  "aforth: mmap"

// readline's prompt. Nothing is printed in front of a line: aforth says " ok"
// after a line instead, which is where the older Forths put it.
str_empty:
        .asciz  ""

        .text

// Allocate and carve the region, and set the machine registers.
//
// Returns the region base in x0, or 0 when the mapping failed, having already
// reported why. The dispatch table and the built-in dictionary are built here
// too, by the two routines in interpreter.S that know what goes in them.
        .p2align        2
        .globl  machine_init
        FUNC_TYPE(machine_init)
machine_init:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        mov     x0, #0                  // let the kernel choose the address
        // mov cannot take REGION_SIZE as one immediate, so build it from its
        // two 16-bit halves.
        movz    x1, #(REGION_SIZE & 0xffff)
        movk    x1, #((REGION_SIZE >> 16) & 0xffff), lsl #16
        mov     w2, #3                  // PROT_READ|PROT_WRITE
        mov     w3, #MMAP_FLAGS
        mov     w4, #-1                 // no file descriptor
        mov     x5, #0                  // no offset
        bl      CSYM(mmap)

        cmn     x0, #1                  // MAP_FAILED is -1
        b.eq    init_failed

        // x0 holds the region base from here to the return.
        mov     UP, x0

        add     x1, x0, #XTAB_OFF
        mov     XTAB, x1

        add     x1, x0, #DICT_OFF
        mov     DBASE, x1
        str     x1, [UP, #UV_DICT]
        str     x1, [UP, #UV_HERE]

        add     x1, x0, #DICT_END_OFF
        str     x1, [UP, #UV_DICT_END]

        add     x1, x0, #S0_OFF
        mov     DSP, x1
        str     x1, [UP, #UV_S0]

        add     x1, x0, #R0_OFF
        mov     RSP, x1
        str     x1, [UP, #UV_R0]

        add     x1, x0, #DSTACK_OFF
        str     x1, [UP, #UV_DS_LO]

        add     x1, x0, #RSTACK_OFF
        str     x1, [UP, #UV_RS_LO]

        add     x1, x0, #TIB_OFF
        str     x1, [UP, #UV_TIB]

        // Pictured output fills downward, so the pointer starts at the end and
        // the buffer's own base is the bound HOLDROOM tests against.
        add     x1, x0, #HOLD_END_OFF
        str     x1, [UP, #UV_HOLD]
        str     x1, [UP, #UV_HOLD_END]

        add     x1, x0, #HOLD_OFF
        str     x1, [UP, #UV_HOLD_LO]

        add     x1, x0, #PAD_OFF
        str     x1, [UP, #UV_PAD]

        // The only real code address aforth writes anywhere. It is allowed
        // because the user area is not the dictionary, which ADR 0005 requires
        // to hold none. When warm start lands it must rewrite this cell on
        // load rather than trust the saved value.
        adr_sym x1, quit_abort
        str     x1, [UP, #UV_ABORT]

        mov     x1, #10
        str     x1, [UP, #UV_BASE]

        str     xzr, [UP, #UV_LATEST]
        str     xzr, [UP, #UV_STATE]
        str     xzr, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]

        str     xzr, [UP, #UV_STOP_SP]

        str     xzr, [UP, #UV_ERR_ADDR]
        str     xzr, [UP, #UV_ERR_LEN]

        // Deterministic; the machine overwrites all three as soon as it runs.
        mov     IP, #0
        mov     TOS, #0
        mov     W, #0

        // Both are rebuilt on every start-up, which is what keeps a dictionary
        // of indices and offsets valid in a process that loaded elsewhere.
        bl      machine_build_xtab
        bl      machine_load_dictionary

        mov     x0, UP                  // the region base, for the caller
        ldp     x29, x30, [sp], #16
        ret

init_failed:
        adr_sym x0, msg_mmap
        bl      CSYM(perror)
        mov     x0, #0
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(machine_init)

// Where a word goes when it cannot do what it was asked. Each entry names the
// error, then goes through the vector in the user area, which holds quit_abort
// in src/outer.S: it carries the number out of the machine, and machine_quit
// reports it, empties the stacks and reads the next line.
        .p2align        2
        .globl  ds_underflow
ds_underflow:
        mov     x0, #ERR_DS_UNDERFLOW
        b       machine_error

        .globl  ds_overflow
ds_overflow:
        mov     x0, #ERR_DS_OVERFLOW
        b       machine_error

        .globl  rs_underflow
rs_underflow:
        mov     x0, #ERR_RS_UNDERFLOW
        b       machine_error

        .globl  rs_overflow
rs_overflow:
        mov     x0, #ERR_RS_OVERFLOW
        b       machine_error

        .globl  div_zero
div_zero:
        mov     x0, #ERR_DIV_ZERO
        b       machine_error

        .globl  hold_overflow
hold_overflow:
        mov     x0, #ERR_HOLD_OVERFLOW
        b       machine_error

        .globl  line_too_long
line_too_long:
        mov     x0, #ERR_LINE_TOO_LONG
        b       machine_error

// The one error that names something. The name is at x0, x1 bytes long, and it
// goes in the user area for machine_quit to print after the message. Both the
// outer interpreter and ' come through here, so both say the same thing.
//
// The name points into the input buffer, which the next REFILL overwrites. The
// message is written before that happens, so the two never race.
        .globl  undefined_word
undefined_word:
        str     x0, [UP, #UV_ERR_ADDR]
        str     x1, [UP, #UV_ERR_LEN]
        mov     x0, #ERR_UNDEFINED_WORD
        b       machine_error

        .globl  machine_error
machine_error:
        ldr     x9, [UP, #UV_ABORT]
        br      x9

// Write x1 bytes at x0 to file descriptor 1.
//
// Every byte aforth prints leaves through here, EMIT and TYPE and the banner
// alike. write is unbuffered, so there is no flushing rule and no question of
// what order a terminal and a pipe see things in: one call, one write, in the
// order the words made them. See docs/system/output.md.
        .p2align        2
        .globl  write_stdout
write_stdout:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x2, x1                  // length
        mov     x1, x0                  // buffer
        mov     x0, #1                  // fd
        bl      CSYM(write)
        ldp     x29, x30, [sp], #16
        ret

// Write the NUL-terminated string at x0 to file descriptor 1, then a newline.
//
// What puts did, on aforth's own output path rather than through stdio: a
// buffered banner and an unbuffered number would reach a pipe in the wrong
// order. The newline byte is written from the stack, which is where the words
// that print one character build theirs too.
        .p2align        2
        .globl  puts_stdout
puts_stdout:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]
        bl      CSYM(strlen)
        mov     x1, x0                  // length
        ldr     x0, [sp, #16]           // buffer
        bl      write_stdout
        mov     w1, #10
        strb    w1, [sp, #24]
        add     x0, sp, #24
        mov     x1, #1
        bl      write_stdout
        ldp     x29, x30, [sp], #32
        ret

// Read one line into the caller's buffer.
//
// x0 the buffer, x1 how many bytes it holds, x2 nonzero to put the line in the
// history. Returns the line's length in x0, which may be more than the buffer
// took, or -1 at end of input.
//
// readline does the editing, the history and the terminal handling, and it
// returns lines unedited when stdin is not a terminal, so one routine serves
// the prompt and a piped script alike (ADR 0001). The line comes back malloc'd
// and is freed here, and it carries no newline.
//
// The untruncated length is what comes back, so that REFILL can tell a line
// longer than the input buffer from one that just fills it.
        .p2align        2
        .globl  read_line
read_line:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        str     x0, [sp, #16]           // the caller's buffer
        str     x1, [sp, #24]           // how much of it there is
        str     x2, [sp, #32]           // whether the user typed this

        adr_sym x0, str_empty
        bl      CSYM(readline)
        cbz     x0, rl_eof
        str     x0, [sp, #40]           // the line, to copy and to free

        bl      CSYM(strlen)
        str     x0, [sp, #48]           // its length, before any truncation

        ldr     x2, [sp, #24]
        cmp     x0, x2
        csel    x2, x0, x2, lo          // copy whichever is shorter
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #40]
        bl      CSYM(memcpy)

        ldr     x0, [sp, #32]
        cbz     x0, rl_no_history
        ldr     x0, [sp, #48]
        cbz     x0, rl_no_history       // an empty line is not worth recalling
        ldr     x0, [sp, #40]
        bl      CSYM(add_history)

rl_no_history:
        ldr     x0, [sp, #40]
        bl      CSYM(free)
        ldr     x0, [sp, #48]
        ldp     x29, x30, [sp], #64
        ret

rl_eof:
        mov     x0, #-1
        ldp     x29, x30, [sp], #64
        ret

// Read one byte, which is the character KEY returns. Returns it in x0, or -1
// at end of input.
//
// The terminal is put in raw mode for the read and put back afterwards, so the
// byte arrives on the keystroke and is not echoed. tcgetattr fails when stdin
// is not a terminal, and this is then one read of one byte, which is what a
// piped script wants.
//
// The frame holds the byte at 16, the saved settings at 32 and the raw ones at
// 112, which leaves room for the larger of the two platforms' structs.
        .p2align        2
        .globl  read_byte
read_byte:
        stp     x29, x30, [sp, #-192]!
        mov     x29, sp

        mov     x0, #0                  // fd 0
        add     x1, sp, #32
        bl      CSYM(tcgetattr)
        cbnz    x0, rb_plain

        add     x0, sp, #112
        add     x1, sp, #32
        mov     x2, #TERMIOS_SIZE
        bl      CSYM(memcpy)

        // Four bytes of c_lflag, which is where both bits live on either
        // platform. See src/include/platform.h.
        ldr     w1, [sp, #(112 + TERMIOS_LFLAG_OFF)]
        mov     w2, #(T_ICANON | T_ECHO)
        bic     w1, w1, w2
        str     w1, [sp, #(112 + TERMIOS_LFLAG_OFF)]

        mov     x0, #0
        mov     x1, #0                  // TCSANOW
        add     x2, sp, #112
        bl      CSYM(tcsetattr)

        mov     x0, #0
        add     x1, sp, #16
        mov     x2, #1
        bl      CSYM(read)
        str     x0, [sp, #24]           // the result, across the restore

        mov     x0, #0
        mov     x1, #0
        add     x2, sp, #32             // the settings the terminal arrived in
        bl      CSYM(tcsetattr)

        ldr     x0, [sp, #24]
        b       rb_done

rb_plain:
        mov     x0, #0
        add     x1, sp, #16
        mov     x2, #1
        bl      CSYM(read)

rb_done:
        cmp     x0, #1
        b.ne    rb_eof
        ldrb    w0, [sp, #16]
        ldp     x29, x30, [sp], #192
        ret

rb_eof:
        mov     x0, #-1
        ldp     x29, x30, [sp], #192
        ret

// Write a NUL-terminated message to file descriptor 2.
//
// fd 2 rather than fputs to stderr, because stderr is a libc variable whose
// symbol differs between the platforms: __stderrp on macOS, stderr on Linux.
//
// The pointer crosses the strlen call on the stack rather than in x27, so that
// this clobbers nothing a caller might be keeping. x27 and x28 are the two
// registers a word may use across a libc call, and a callee that took one of
// them would make that promise worthless.
        .p2align        2
        .globl  write_stderr
write_stderr:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]
        bl      CSYM(strlen)
        mov     x2, x0                  // length
        ldr     x1, [sp, #16]           // buffer
        mov     x0, #2                  // fd
        bl      CSYM(write)
        ldp     x29, x30, [sp], #32
        ret
