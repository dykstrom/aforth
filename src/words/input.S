// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The input words.
//
// A line comes from libedit through readline, called through its
// readline-compatible API and never through the native el_* one (ADR 0001).
// read_line and read_byte in src/machine.S are the two routines that reach the
// library and the terminal; the words here are what a Forth program sees. See
// docs/system/input.md.
//
// Four user variables describe the source being read now: UV_TIB is its
// address, UV_TIB_LEN how many bytes it holds, UV_TO_IN how far the parser has
// read, and UV_SOURCE_ID where it came from. Three more say where an error
// inside a file happened: UV_SRC_LINE, UV_SRC_NAME and UV_SRC_NAME_LEN. A
// source pushed on top of another saves all seven and installs its own, so
// every word that parses reads the same cells whatever is being read. src_push
// and src_pop below are the only things that touch the stack of saved ones.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

        DEFCODE "SOURCE", 6, source     // ( -- c-addr u )
        ROOM    2
        DPUSHM
        ldr     TOS, [UP, #UV_TIB]
        DPUSHM
        ldr     TOS, [UP, #UV_TIB_LEN]
        NEXT

        DEFCODE ">IN", 3, to_in         // ( -- a-addr )
        ROOM    1
        DPUSHM
        add     TOS, UP, #UV_TO_IN
        NEXT

// Fill the input buffer from the current source and put the parse offset back
// to the start.
//
// Returns the flag in x0 and an error number in x1, and raises nothing. The
// REFILL word turns that number into a raise. include_impl and ( call this
// routine instead, because a raise from inside either one would unwind past
// the frame holding the file's line buffer before the file is closed. That is
// the same reason interpret_source returns every error it meets.
//
// UV_SOURCE_ID says where the line comes from. 0 is the terminal, -1 is a
// string, and anything else is a fileid.
        .p2align        2
        .globl  refill_impl
        FUNC_TYPE(refill_impl)
refill_impl:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        ldr     x0, [UP, #UV_SOURCE_ID]
        cbz     x0, ri_terminal
        cmn     x0, #1
        b.eq    ri_string
        // fall through, so x0 is the fileid

// A file, read by the same file_read_line READ-LINE uses. x3 says whether a
// newline ended the line, which is what tells a whole line from the first
// 4096 bytes of one too long for the buffer.
//
// A read that fails ends the source rather than reporting. Forth-2012 makes an
// I/O exception while reading an included file an ambiguous condition, and an
// invalid fileid handed to INCLUDE-FILE is the way to reach this.
ri_file:
        ldr     x1, [UP, #UV_TIB]
        mov     x2, #TIB_SIZE
        bl      file_read_line
        cbnz    x2, ri_eof              // the read failed
        cbz     x1, ri_eof

// The line is counted before it is measured, so that a line too long for the
// buffer is reported against its own number rather than the one before it.
        ldr     x4, [UP, #UV_SRC_LINE]
        add     x4, x4, #1
        str     x4, [UP, #UV_SRC_LINE]

        cbnz    x3, 1f                  // a newline ended it, so it is whole
        mov     x2, #TIB_SIZE
        cmp     x0, x2
        b.hs    ri_too_long
1:      str     x0, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]
        b       ri_true

// The terminal, through libedit. Only its lines reach the history, which is
// what read_line's third argument says: a program reading data is not a
// command the user typed.
ri_terminal:
        ldr     x0, [UP, #UV_TIB]
        mov     x1, #TIB_SIZE
        mov     x2, #1                  // the user typed it, so keep it
        bl      read_line
        cmn     x0, #1                  // -1 is end of input
        b.eq    ri_eof
        mov     x1, #TIB_SIZE
        cmp     x0, x1
        b.hi    ri_too_long
        str     x0, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]

ri_true:
        mov     x0, #-1
        mov     x1, #0
        b       ri_done

// A string has no next line, so Forth-2012 asks REFILL to return false and do
// nothing else with one. Zeroing the length would destroy the string it is
// being asked to leave alone.
ri_string:
        mov     x0, #0
        mov     x1, #0
        b       ri_done

ri_eof:
        str     xzr, [UP, #UV_TIB_LEN]  // nothing to parse after the last line
        str     xzr, [UP, #UV_TO_IN]
        mov     x0, #0
        mov     x1, #0
        b       ri_done

// Half a line parses as valid Forth that is missing its tail, which is worse
// than an error, so neither source truncates.
ri_too_long:
        mov     x0, #0
        mov     x1, #ERR_LINE_TOO_LONG

ri_done:
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(refill_impl)

// REFILL is refill_impl and a raise. It is false at end of input, which is
// what ends a session, and false inside a string, which has no next line.
        DEFCODE "REFILL", 6, refill     // ( -- flag )
        ROOM    1
        bl      refill_impl
        mov     x27, x0                 // the flag, across the raise
        mov     x0, x1
        RAISE
        DPUSHM
        mov     TOS, x27
        NEXT

// ACCEPT reads into the caller's buffer and returns how much it took. It
// truncates instead of raising, because taking at most the count it was given
// is the word's own contract, and it adds nothing to the history: a program
// reading data is not a command the user typed.
//
// The count is kept in x27 across the call, which is what that register is for.
        DEFCODE "ACCEPT", 6, accept     // ( c-addr +n1 -- +n2 )
        NEED    2
        DPOP    x27                     // +n1
        mov     x0, TOS                 // c-addr, which the count replaces
        mov     x1, x27
        mov     x2, #0
        bl      read_line
        cmn     x0, #1
        b.ne    1f
        mov     x0, #0                  // end of input receives nothing
1:      cmp     x0, x27
        csel    TOS, x0, x27, lo        // at most what the caller asked for
        NEXT

// KEY reads one byte with the terminal in raw mode, so it returns on the
// keystroke and echoes nothing. It gives -1 at end of input, which is not a
// character: the standard leaves KEY no way to report one.
        DEFCODE "KEY", 3, key           // ( -- char )
        ROOM    1
        bl      read_byte
        DPUSHM
        mov     TOS, x0
        NEXT

// The input source stack.
//
// UV_TIB, UV_TIB_LEN, UV_TO_IN and UV_SOURCE_ID describe the source being read
// now, and UV_SRC_LINE, UV_SRC_NAME and UV_SRC_NAME_LEN say where an error in
// it should say it happened. A slot in the user area holds those seven cells
// for each source under the current one. See src/include/machine.h for the
// layout and docs/system/input.md for what nests.
//
// Only these four routines touch it, so a word that reads a line or parses a
// name never has to ask how deep it is.

// Where level x0's slot is.
        .p2align        2
src_slot:
        mov     x1, #SRC_SLOT
        madd    x0, x0, x1, UP
        add     x0, x0, #SRC_STACK_OFF
        ret

// Save the current source and install the one described by x0, x1 and x2: the
// address, the length and the SOURCE-ID. The parse offset starts at 0, and so
// do the line number and the name, which the caller fills in if it has them.
//
// Returns 0, or ERR_SOURCE_TOO_DEEP when every level is taken. It reports
// rather than raises because include_impl opens the file before it pushes, and
// a raise here would leave that file open with nothing holding its descriptor.
        .p2align        2
src_push:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]
        str     x2, [sp, #32]

        ldr     x0, [UP, #UV_SRC_DEPTH]
        cmp     x0, #SRC_LEVELS
        b.hs    sp_deep
        add     x1, x0, #1
        str     x1, [UP, #UV_SRC_DEPTH]
        bl      src_slot

        ldr     x3, [UP, #UV_TIB]
        str     x3, [x0, #SRC_TIB]
        ldr     x3, [UP, #UV_TIB_LEN]
        str     x3, [x0, #SRC_TIB_LEN]
        ldr     x3, [UP, #UV_TO_IN]
        str     x3, [x0, #SRC_TO_IN]
        ldr     x3, [UP, #UV_SOURCE_ID]
        str     x3, [x0, #SRC_ID]
        ldr     x3, [UP, #UV_SRC_LINE]
        str     x3, [x0, #SRC_LINE]
        ldr     x3, [UP, #UV_SRC_NAME]
        str     x3, [x0, #SRC_NAME]
        ldr     x3, [UP, #UV_SRC_NAME_LEN]
        str     x3, [x0, #SRC_NAME_LEN]

        ldp     x0, x1, [sp, #16]
        ldr     x2, [sp, #32]
        str     x0, [UP, #UV_TIB]
        str     x1, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]
        str     x2, [UP, #UV_SOURCE_ID]
        str     xzr, [UP, #UV_SRC_LINE]
        str     xzr, [UP, #UV_SRC_NAME]
        str     xzr, [UP, #UV_SRC_NAME_LEN]
        mov     x0, #0
        ldp     x29, x30, [sp], #48
        ret

sp_deep:
        mov     x0, #ERR_SOURCE_TOO_DEEP
        ldp     x29, x30, [sp], #48
        ret

// Put the source underneath back. Does nothing at the bottom, where the
// terminal is and there is nothing saved.
        .p2align        2
src_pop:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        ldr     x0, [UP, #UV_SRC_DEPTH]
        cbz     x0, 1f
        sub     x0, x0, #1
        str     x0, [UP, #UV_SRC_DEPTH]
        bl      src_slot
        bl      src_restore
1:      ldp     x29, x30, [sp], #16
        ret

// Put the seven cells of the slot at x0 back into the user variables.
        .p2align        2
src_restore:
        ldr     x1, [x0, #SRC_TIB]
        str     x1, [UP, #UV_TIB]
        ldr     x1, [x0, #SRC_TIB_LEN]
        str     x1, [UP, #UV_TIB_LEN]
        ldr     x1, [x0, #SRC_TO_IN]
        str     x1, [UP, #UV_TO_IN]
        ldr     x1, [x0, #SRC_ID]
        str     x1, [UP, #UV_SOURCE_ID]
        ldr     x1, [x0, #SRC_LINE]
        str     x1, [UP, #UV_SRC_LINE]
        ldr     x1, [x0, #SRC_NAME]
        str     x1, [UP, #UV_SRC_NAME]
        ldr     x1, [x0, #SRC_NAME_LEN]
        str     x1, [UP, #UV_SRC_NAME_LEN]
        ret

// Close x0 when it is a fileid, and do nothing when it is not. The terminal's
// 0 and a string's -1 are not descriptors, and neither is anything below 3:
// the process was given 0, 1 and 2 before aforth ran. The ior is nothing this
// caller can act on.
        .p2align        2
src_close_id:
        cmp     x0, #3
        b.lt    1f
        b       file_close              // a tail call, so its ret is ours
1:      ret

// Drop every source above the terminal and close every file among them, which
// is what an error, ABORT and QUIT all do. machine_quit calls it.
//
// The bottom slot holds whatever was current when the first source was pushed,
// so restoring that one is the whole of it however deep the stack went. The
// levels in between are still walked, because each may hold a descriptor.
//
// Nothing trips it today. An error inside a file or a string comes back to
// include_impl or EVALUATE as a number rather than unwinding past it, so every
// one of them in the chain pops its own source and closes its own file on the
// way out, and the stack is empty before machine_quit looks. This makes the
// invariant true at the one place that restarts the loop rather than true by
// the good behaviour of every source that will ever exist. Breaking it fails no
// case in the suite, which is worth knowing before trusting one.
        .p2align        2
        .globl  src_reset
        FUNC_TYPE(src_reset)
src_reset:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        ldr     x0, [UP, #UV_SRC_DEPTH]
        cbz     x0, 1f
        str     x0, [sp, #16]           // how many levels to walk

        ldr     x0, [UP, #UV_SOURCE_ID]
        bl      src_close_id
        mov     x0, #1
        str     x0, [sp, #24]           // slot 0 holds the terminal, so start at 1
2:      ldp     x0, x1, [sp, #16]
        cmp     x1, x0
        b.hs    3f
        mov     x0, x1
        bl      src_slot
        ldr     x0, [x0, #SRC_ID]
        bl      src_close_id
        ldr     x1, [sp, #24]
        add     x1, x1, #1
        str     x1, [sp, #24]
        b       2b

3:      str     xzr, [UP, #UV_SRC_DEPTH]
        mov     x0, #0
        bl      src_slot
        bl      src_restore
1:      ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(src_reset)

        DEFCODE "SOURCE-ID", 9, source_id       // ( -- 0 | -1 | fileid )
        ROOM    1
        DPUSHM
        ldr     TOS, [UP, #UV_SOURCE_ID]
        NEXT

// EVALUATE makes the string the source, interprets it, and puts the source
// back. It has to interpret and return, so that the word after it in a
// definition runs afterwards, which is why aforth_enter nests: interpret_source
// runs words through machine_execute while the entry that is running EVALUATE
// is still open.
//
// The string is the input buffer, not a copy of one. Forth-2012 says so, and it
// is what lets a level cost four cells and no buffer.
//
// An error inside the string pops the source first and raises afterwards, so
// that nothing is left stacked even though machine_quit would drop it anyway.
// That also keeps ABORT and QUIT working: both come back as a number here and
// go out as a raise, which is how they reach the loop.
        DEFCODE "EVALUATE", 8, evaluate // ( i*x c-addr u -- j*x )
        NEED    2
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        mov     x2, #-1                 // a string
        bl      src_push
        RAISE                           // no level free, and nothing pushed
        bl      interpret_source
        mov     x27, x0                 // across the pop, as x27 may be used
        bl      src_pop
        mov     x0, x27
        RAISE
        NEXT
