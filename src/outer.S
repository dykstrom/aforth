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
// When STATE says compiling, the same two answers are compiled instead: a
// word's token goes into the definition being built, and a number goes in as a
// literal. A word marked immediate runs whichever way STATE reads, which is how
// ; and [ get a chance to end the definition. See docs/system/compiling.md.
//
// The loop is assembly because it is what enters the machine and reads what
// unwound it. A definition can branch now, but a QUIT written in Forth would
// still need CATCH and THROW to tell an error from a word that finished, and
// aforth has neither. It runs the same parts the words do: parse_name_impl,
// dict_find and number_impl in src/words/parsing.S, and machine_refill and
// machine_execute in src/interpreter.S.
//
// dict.h rather than machine.h, for F_IMMEDIATE: the loop reads an entry's
// flags to decide whether a word runs while the loop is compiling. It defines
// no storage, so including it here builds nothing into this object file.

#include "dict.h"

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
msg_no_name:
        .asciz  "aforth: name expected"
msg_name_too_long:
        .asciz  "aforth: name too long"
msg_dict_full:
        .asciz  "aforth: dictionary full"
msg_control_flow:
        .asciz  "aforth: unstructured control flow"
msg_source_too_deep:
        .asciz  "aforth: input sources nested too deep"
msg_unterminated_comment:
        .asciz  "aforth: unterminated comment"
msg_open_failed:
        .asciz  "aforth: cannot open file"

// The lines under a message that say which file an error happened in, and
// which file included that one. include_impl writes them as it unwinds. A file
// opened by INCLUDE-FILE has no name, because the word is handed a descriptor.
msg_in:
        .asciz  "aforth:   in "
msg_included_from:
        .asciz  "aforth:   included from "
msg_a_file:
        .asciz  "a file"
msg_line:
        .asciz  ", line "

        .text

// Run the current source to the end of its parse area.
//
// Returns 0 when the parse area is empty, or the number of the error that
// stopped it. The frame holds the name last parsed, because a word is free to
// clobber x27 and x28 and ACCEPT does, so nothing may be kept in a register
// across machine_execute.
//
// It returns every error and raises none, which matters in both directions.
// machine_quit calls it from outside aforth_enter, where a raise would unwind
// sp to a frame that has already been popped — the trap the ROOM comment below
// describes. EVALUATE calls it from inside one, where a raise would unwind past
// EVALUATE and skip the source it has to pop. So the two callers decide what to
// do with a number, and this decides nothing.
//
// ERR_ABORT and ERR_QUIT come back the same way an error does. They are not
// failures, and telling them apart is the caller's job.
        .p2align        2
        .globl  interpret_source
        FUNC_TYPE(interpret_source)
interpret_source:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp

// One name, and then the next, until the parse area is used up.
is_name:
        bl      parse_name_impl
        str     x0, [sp, #16]           // the name, for the number and the
        str     x1, [sp, #24]           // message that may need it
        cbz     x1, is_done             // nothing left to parse

        bl      dict_find
        cbz     x0, is_number

        // Compiling, and the word is not immediate: its token goes into the
        // definition being built instead of being run. dict_comma reports
        // rather than raises, which is exactly the shape this routine wants.
        ldr     x2, [UP, #UV_STATE]
        cbz     x2, is_run
        tst     w1, #F_IMMEDIATE
        b.ne    is_run
        bl      dict_comma
        cbz     x0, is_name
        b       is_return

is_run:
        bl      machine_execute
        cbz     x0, is_name             // the word ran to its end
        b       is_return

// Not a word, so it has to be a number.
is_number:
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        bl      number_impl
        cbz     x1, is_undefined

        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, is_literal

        // ROOM cannot be used here. It branches through the vector to
        // enter_return, which puts sp back to the frame of the last
        // aforth_enter, and that frame was popped when the word before this
        // number finished. So the same comparison is made here, and the number
        // is returned like any other.
        ldr     x1, [UP, #UV_DS_LO]
        sub     x1, DSP, x1
        cmp     x1, #8
        b.lt    is_overflow
        DPUSH   x0
        b       is_name

// Compiling, so the number is compiled as a literal rather than pushed. The
// routine is in src/interpreter.S, because (LIT)'s token is a symbol only the
// assembler building that file has.
is_literal:
        bl      dict_compile_literal
        cbz     x0, is_name
        b       is_return

is_undefined:
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        bl      err_name                // remembered, not raised
        mov     x0, #ERR_UNDEFINED_WORD
        b       is_return

is_overflow:
        mov     x0, #ERR_DS_OVERFLOW
        b       is_return

is_done:
        mov     x0, #0

is_return:
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(interpret_source)

// The QUIT loop. main calls it after the banner.
//
// It reads a line, hands it to interpret_source, and decides what the number
// that comes back means. It returns at end of input, and that is the only way
// it returns: BYE ends the process from inside the machine.
        .p2align        2
        .globl  machine_quit
        FUNC_TYPE(machine_quit)
machine_quit:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

// Where ABORT and every reported error go: both stacks emptied.
quit_reset:
        ldr     x0, [UP, #UV_S0]
        mov     DSP, x0
        mov     TOS, #0
        // fall through

// Where QUIT goes: the return stack only, and the data stack left alone.
//
// Every input source above the terminal goes in both cases. Forth-2012 says
// QUIT returns control to the terminal, and an error inside an included file
// must not leave the loop reading a file nobody is watching. src_reset closes
// every file it drops.
quit_restart:
        ldr     x0, [UP, #UV_R0]
        mov     RSP, x0
        str     xzr, [UP, #UV_STATE]
        bl      src_reset

quit_line:
        bl      machine_refill
        cbnz    x0, quit_failed         // the line did not fit the buffer
        DPOP    x0
        cbz     x0, quit_eof

        bl      interpret_source
        cbz     x0, quit_ok
        cmp     x0, #ERR_QUIT
        b.eq    quit_restart
        cmp     x0, #ERR_ABORT
        b.eq    quit_reset
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
        ldp     x29, x30, [sp], #16
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
        FUNC_TYPE(quit_abort)
quit_abort:
        b       enter_return
        FUNC_SIZE(quit_abort)

// Print the error in x0 on file descriptor 2. ABORT and QUIT print nothing:
// they are how a program leaves what it was doing, not failures.
//
// The message, then a colon and the name when the error names one, then a
// newline. Three writes rather than one formatted string, because aforth holds
// no output buffer to format into and printf is variadic, which the two
// platforms pass differently.
        .p2align        2
        .globl  quit_report
        FUNC_TYPE(quit_report)
quit_report:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        cmp     x0, #ERR_OPEN_FAILED
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
        cmp     x0, #ERR_NO_NAME
        b.eq    qr_no_name
        cmp     x0, #ERR_NAME_TOO_LONG
        b.eq    qr_name_too_long
        cmp     x0, #ERR_DICT_FULL
        b.eq    qr_dict_full
        cmp     x0, #ERR_CONTROL_FLOW
        b.eq    qr_control_flow
        cmp     x0, #ERR_SOURCE_TOO_DEEP
        b.eq    qr_source_too_deep
        cmp     x0, #ERR_UNTERMINATED_COMMENT
        b.eq    qr_unterminated_comment
        cmp     x0, #ERR_OPEN_FAILED
        b.eq    qr_open_failed
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
qr_no_name:
        adr_sym x0, msg_no_name
        b       qr_write
qr_name_too_long:
        adr_sym x0, msg_name_too_long
        b       qr_write
qr_dict_full:
        adr_sym x0, msg_dict_full
        b       qr_write
qr_control_flow:
        adr_sym x0, msg_control_flow
        b       qr_write
qr_source_too_deep:
        adr_sym x0, msg_source_too_deep
        b       qr_write
qr_unterminated_comment:
        adr_sym x0, msg_unterminated_comment
        b       qr_write

// The two errors that name something. The name is in the user area, put there
// by err_name, and it points into the input buffer, which nothing has refilled
// yet.
qr_undefined_word:
        adr_sym x0, msg_undefined_word
        b       qr_named

qr_open_failed:
        adr_sym x0, msg_open_failed

qr_named:
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
        FUNC_SIZE(quit_report)

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

// Write one line of the traceback that goes under a message. x0 is 0 for the
// file the error happened in and anything else for a file that included it.
//
// It reads the current source level, so include_impl calls it before it pops.
// Only a file level has a name and a line to report, which is why an EVALUATE
// between two files adds no line.
        .p2align        2
        .globl  err_location
        FUNC_TYPE(err_location)
err_location:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        cbz     x0, 1f
        adr_sym x0, msg_included_from
        b       2f
1:      adr_sym x0, msg_in
2:      bl      write_stderr

        ldr     x1, [UP, #UV_SRC_NAME_LEN]
        cbz     x1, 3f
        ldr     x0, [UP, #UV_SRC_NAME]
        bl      err_write
        b       4f
3:      adr_sym x0, msg_a_file
        bl      write_stderr

4:      adr_sym x0, msg_line
        bl      write_stderr
        ldr     x0, [UP, #UV_SRC_LINE]
        bl      err_number
        adr_sym x0, msg_newline
        mov     x1, #1
        bl      err_write
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(err_location)

// Write x0 on file descriptor 2 in decimal. A line number is never negative,
// and twenty digits hold any unsigned 64-bit number, so the digits are built
// backwards into the frame and written in one call.
//
// The pictured output words would do this, but they build into the buffer a
// program may be part way through using, and an error must not disturb it.
        .p2align        2
err_number:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        add     x3, sp, #40             // one past the last digit
        mov     x4, #10
1:      udiv    x5, x0, x4
        msub    x6, x5, x4, x0          // the remainder
        add     x6, x6, #48             // '0'
        sub     x3, x3, #1
        strb    w6, [x3]
        mov     x0, x5
        cbnz    x0, 1b
        add     x1, sp, #40
        sub     x1, x1, x3
        mov     x0, x3
        bl      err_write
        ldp     x29, x30, [sp], #48
        ret
