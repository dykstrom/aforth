// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The outer interpreter: the QUIT loop, the one path an error takes, and the
// text each error prints.
//
// machine_quit reads a line, cuts a name out of it, and either runs the word
// the dictionary holds or pushes the number the name converts to. A name that
// is neither is an error, and so is anything a word raises. Every one of them
// comes out of the machine the same way, through the vector in UV_ABORT, and
// is reported here. See docs/system/outer-interpreter.md.
//
// The loop is assembly because a token list cannot branch until ticket 011.
// The words it reaches into the machine for are in src/interpreter.S:
// parse_name_impl, dict_find, number_impl, machine_refill and machine_execute.

#include "machine.h"

        SECTION_RODATA
        .p2align        3

// What a line that ran without error prints, and the newline that ends a
// message or a session. The older Forths put ok after the line rather than a
// prompt before it, and aforth does the same: readline is given an empty
// prompt, so nothing is printed in front of what the user types.
msg_ok:
        .ascii  " ok\n"
msg_newline:
        .ascii  "\n"
msg_colon:
        .asciz  ": "

// One message per error number. The name of the word that failed follows the
// last of them, when there is one.
msg_ds_underflow:
        .asciz  "aforth: data stack underflow"
msg_ds_overflow:
        .asciz  "aforth: data stack overflow"
msg_rs_underflow:
        .asciz  "aforth: return stack underflow"
msg_rs_overflow:
        .asciz  "aforth: return stack overflow"
msg_div_zero:
        .asciz  "aforth: divide by zero"
msg_hold_overflow:
        .asciz  "aforth: pictured output overflow"
msg_line_too_long:
        .asciz  "aforth: input line too long"
msg_undefined_word:
        .asciz  "aforth: undefined word"

        .text

// The QUIT loop. main calls it after the banner.
//
// It returns at end of input, and that is the only way it returns: BYE ends
// the process from inside the machine. The frame holds the name last parsed,
// because a word is free to clobber x27 and x28 and ACCEPT does, so nothing
// may be kept in a register across machine_execute.
        .p2align        2
        .globl  machine_quit
        FUNC_TYPE(machine_quit)
machine_quit:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp

// Where ABORT and every reported error go: both stacks emptied.
quit_reset:
        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        mov     TOS, #0
        // fall through

// Where QUIT goes: the return stack only, and the data stack left alone.
quit_restart:
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        str     xzr, [UP, #UV_STATE]

quit_line:
        bl      machine_refill
        cbnz    x0, quit_failed         // the line did not fit the buffer
        DPOP    x0
        cbz     x0, quit_eof

// One name, and then the next, until the line is used up.
quit_name:
        bl      parse_name_impl
        str     x0, [sp, #16]           // the name, for the number and the
        str     x1, [sp, #24]           // message that may need it
        cbz     x1, quit_ok             // nothing left on the line

        bl      dict_find
        cbz     x0, quit_number

        bl      machine_execute
        cbz     x0, quit_name           // the word ran to its end
        cmp     x0, #ERR_QUIT
        b.eq    quit_restart
        cmp     x0, #ERR_ABORT
        b.eq    quit_reset
        b       quit_failed

// Not a word, so it has to be a number.
quit_number:
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        bl      number_impl
        cbz     x1, quit_undefined

        // ROOM cannot be used here. It branches through the vector to
        // enter_return, which puts sp back to the frame of the last
        // aforth_enter, and that frame was popped when the word before this
        // number finished. So the same comparison is made here, and it
        // branches to this file's own reporting.
        ldr     x1, [UP, #UV_DS_LO]
        sub     x1, DSP, x1
        cmp     x1, #8
        b.lt    quit_overflow
        DPUSH   x0
        b       quit_name

quit_undefined:
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        b       undefined_word          // stores the name and raises

quit_overflow:
        mov     x0, #ERR_DS_OVERFLOW
        // fall through

// Report what failed and start the next line. The rest of the line the error
// happened on is dropped with it, which is what ABORT means.
quit_failed:
        bl      quit_report
        b       quit_reset

quit_ok:
        adr_sym x0, msg_ok
        mov     x1, #4
        bl      write_stdout
        b       quit_line

// End of input. The newline puts the shell's prompt on a line of its own after
// the user types Ctrl-D.
quit_eof:
        adr_sym x0, msg_newline
        mov     x1, #1
        bl      write_stdout
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(machine_quit)

// The routine in UV_ABORT. Every guard, every word that raises, and both of
// ABORT and QUIT arrive here through machine_error with a number in x0, and
// leave the machine carrying it as aforth_enter's result.
//
// It reports nothing itself. machine_quit does that, so a word test that
// expects an error stays silent, and so that the message is built in one place.
        .p2align        2
        .globl  quit_abort
quit_abort:
        b       enter_return

// Print the error in x0 on file descriptor 2. ABORT and QUIT print nothing:
// they are how a program leaves what it was doing, not failures.
//
// The message, then a colon and the name when the error names one, then a
// newline. Three writes rather than one formatted string, because aforth holds
// no output buffer to format into and printf is variadic, which the two
// platforms pass differently.
        .p2align        2
quit_report:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        cmp     x0, #ERR_UNDEFINED_WORD
        b.hi    qr_done

        cmp     x0, #ERR_DS_OVERFLOW
        b.eq    qr_ds_overflow
        cmp     x0, #ERR_RS_UNDERFLOW
        b.eq    qr_rs_underflow
        cmp     x0, #ERR_RS_OVERFLOW
        b.eq    qr_rs_overflow
        cmp     x0, #ERR_DIV_ZERO
        b.eq    qr_div_zero
        cmp     x0, #ERR_HOLD_OVERFLOW
        b.eq    qr_hold_overflow
        cmp     x0, #ERR_LINE_TOO_LONG
        b.eq    qr_line_too_long
        cmp     x0, #ERR_UNDEFINED_WORD
        b.eq    qr_undefined_word
        adr_sym x0, msg_ds_underflow
        b       qr_write
qr_ds_overflow:
        adr_sym x0, msg_ds_overflow
        b       qr_write
qr_rs_underflow:
        adr_sym x0, msg_rs_underflow
        b       qr_write
qr_rs_overflow:
        adr_sym x0, msg_rs_overflow
        b       qr_write
qr_div_zero:
        adr_sym x0, msg_div_zero
        b       qr_write
qr_hold_overflow:
        adr_sym x0, msg_hold_overflow
        b       qr_write
qr_line_too_long:
        adr_sym x0, msg_line_too_long
        b       qr_write

// The one error that names a word. The name is in the user area, put there by
// undefined_word, and it points into the input buffer, which nothing has
// refilled yet.
qr_undefined_word:
        adr_sym x0, msg_undefined_word
        bl      write_stderr
        ldr     x1, [UP, #UV_ERR_LEN]
        cbz     x1, qr_newline          // ' at the end of a line names nothing
        adr_sym x0, msg_colon
        bl      write_stderr
        ldr     x0, [UP, #UV_ERR_ADDR]
        ldr     x1, [UP, #UV_ERR_LEN]
        bl      err_write
        b       qr_newline

qr_write:
        bl      write_stderr

qr_newline:
        adr_sym x0, msg_newline
        mov     x1, #1
        bl      err_write

qr_done:
        ldp     x29, x30, [sp], #16
        ret

// Write x1 bytes at x0 to file descriptor 2, for the parts of a message whose
// length is known. write_stderr in src/machine.S sizes a NUL-terminated string
// with strlen instead; a name cut out of the input buffer has no NUL after it.
        .p2align        2
err_write:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x2, x1                  // length
        mov     x1, x0                  // buffer
        mov     x0, #2                  // fd
        bl      CSYM(write)
        ldp     x29, x30, [sp], #16
        ret
