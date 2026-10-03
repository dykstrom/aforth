// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The file words: the reading half of the optional File-Access word set.
//
// A fileid is the descriptor open returned, and a fam is the flag word open
// takes — R/O is O_RDONLY, which is 0. An ior is 0 or an errno, so nothing here
// raises: a file word reports what went wrong on the stack and the program
// decides what to do about it.
//
// The routines that reach libc are file_open, file_read, file_seek and
// file_close in src/machine.S, beside read_line and write_stdout. Nothing holds
// a buffer or a position of its own; the kernel's file position is the only one
// there is. See docs/system/files.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// Read one line from descriptor x0 into the buffer at x1, at most x2 bytes.
// Returns the length in x0, the flag in x1, an ior in x2, and in x3 whether a
// newline ended the line.
//
// READ-LINE ignores x3. refill_impl reads it, because a full buffer that no
// newline ended is how a file line too long for the buffer arrives.
//
// It reads a whole buffer's worth and then puts the file position back to just
// after the newline it found. Two system calls a line, and no state: the
// alternative that keeps a buffer would make FILE-POSITION subtract what was
// read but not yet given out.
//
// The four ways it can end are four sentences of Forth-2012. Nothing read at
// all is the end of the file, and the flag is false. A newline found is a line,
// and the position goes back to just past it. A full buffer with no newline in
// it is a line as well — "when u1 = u2 the line terminator has yet to be
// reached" — and the position is already right. And a short buffer with no
// newline is the last line of a file that does not end in one, which is a
// successful read; the call after it is the one that reports the end.
//
// A carriage return immediately before the newline goes with it. The standard
// allows up to two line-terminating characters and lets a program depend on
// neither, so a file edited on Windows runs instead of failing on a word with
// an invisible character stuck to it.
        .p2align        2
file_read_line:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]       // the descriptor and the buffer
        str     x2, [sp, #32]           // how much of it there is

        bl      file_read
        cbnz    x1, frl_failed
        cbz     x0, frl_eof
        str     x0, [sp, #40]           // how many bytes arrived

        ldr     x3, [sp, #24]           // the buffer
        mov     x4, #0
1:      cmp     x4, x0
        b.hs    frl_no_newline
        ldrb    w5, [x3, x4]
        cmp     w5, #10                 // a newline
        b.eq    frl_newline
        add     x4, x4, #1
        b       1b

// A newline, so the file position goes back over everything after it.
frl_newline:
        str     x4, [sp, #48]
        ldr     x0, [sp, #16]
        ldr     x5, [sp, #40]
        add     x1, x4, #1
        sub     x1, x1, x5              // never positive: a step backwards
        mov     x2, #1                  // from where the file stands
        bl      file_seek
        cbnz    x1, frl_failed

        ldr     x4, [sp, #48]
        cbz     x4, 2f                  // nothing in front of it
        ldr     x3, [sp, #24]
        sub     x5, x4, #1
        ldrb    w6, [x3, x5]
        cmp     w6, #13                 // a carriage return
        b.ne    2f
        mov     x4, x5
2:      mov     x0, x4
        mov     x1, #-1
        mov     x2, #0
        mov     x3, #-1                 // a newline ended it
        b       frl_done

// No newline in what arrived. Either the buffer filled first and the line runs
// on, or the file ended without one; both are a line, and the position is
// already where the next call should start.
frl_no_newline:
        ldr     x0, [sp, #40]
        mov     x1, #-1
        mov     x2, #0
        mov     x3, #0                  // no newline, so it may run on
        b       frl_done

frl_eof:
        mov     x0, #0
        mov     x1, #0
        mov     x2, #0
        mov     x3, #0
        b       frl_done

frl_failed:
        mov     x2, x1
        mov     x0, #0
        mov     x1, #0
        mov     x3, #0

frl_done:
        ldp     x29, x30, [sp], #64
        ret

// R/O is the only access method implemented, and it is O_RDONLY, which is 0 on
// both platforms. A fam being open's own flag word is what will make W/O and
// R/W one constant each when writing lands.
        DEFCODE "R/O", 3, r_o           // ( -- fam )
        ROOM    1
        DPUSHM
        mov     TOS, #0
        NEXT

// OPEN-FILE hands back what open returned. A descriptor is never 0, 1 or 2 as
// long as the process was given its three standard ones, which is what
// SOURCE-ID needs of a fileid: it has to be telling a file from the 0 that
// means the terminal.
        DEFCODE "OPEN-FILE", 9, open_file       // ( c-addr u fam -- fileid ior )
        NEED    3
        DPOP    x2                      // fam
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        bl      file_open
        DPUSH   x0
        DPUSH   x1
        NEXT

        DEFCODE "CLOSE-FILE", 10, close_file    // ( fileid -- ior )
        NEED    1
        mov     x0, TOS
        bl      file_close
        mov     TOS, x0
        NEXT

        DEFCODE "READ-FILE", 9, read_file       // ( c-addr u1 fileid -- u2 ior )
        NEED    3
        DPOP    x0                      // fileid
        DPOP    x2                      // u1
        DPOP    x1                      // c-addr
        bl      file_read
        DPUSH   x0
        DPUSH   x1
        NEXT

        DEFCODE "READ-LINE", 9, read_line       // ( c-addr u1 fileid -- u2 flag ior )
        NEED    3
        DPOP    x0                      // fileid
        DPOP    x2                      // u1
        DPOP    x1                      // c-addr
        bl      file_read_line
        DPUSH   x0
        DPUSH   x1
        DPUSH   x2
        NEXT

// Asking a file about itself.
//
// Forth-2012 makes a size and a position doubles. A cell is 64 bits here, so
// every position a file can have fits the low half and the high half is always
// 0 coming out. Both are pushed anyway, because the stack effect is the
// contract, and a double is ( lo hi ) with the high half on top, as M* leaves
// one.

// The size of the file on descriptor x0, in x0, with an ior in x1.
//
// Three seeks: remember where the file stands, go to the end, and put it back.
// Forth-2012 says FILE-SIZE must not affect the file position, and that is the
// whole of how it keeps the promise. fstat would be one call instead of three,
// at the price of struct stat, whose size and field offsets differ between the
// platforms the way struct termios already does.
        .p2align        2
file_size_impl:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        str     x0, [sp, #16]           // the descriptor

        mov     x1, #0
        mov     x2, #1                  // from where the file stands
        bl      file_seek
        cbnz    x1, fsi_done
        str     x0, [sp, #24]           // where that was

        ldr     x0, [sp, #16]
        mov     x1, #0
        mov     x2, #2                  // from the end
        bl      file_seek
        cbnz    x1, fsi_done
        str     x0, [sp, #32]           // the size

        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        mov     x2, #0                  // from the start
        bl      file_seek
        cbnz    x1, fsi_done
        ldr     x0, [sp, #32]
        mov     x1, #0

fsi_done:
        ldp     x29, x30, [sp], #48
        ret

        DEFCODE "FILE-SIZE", 9, file_size       // ( fileid -- ud ior )
        NEED    1
        ROOM    2
        mov     x0, TOS
        bl      file_size_impl
        mov     TOS, x0                 // the low half replaces the fileid
        DPUSH   xzr                     // and the high half is always 0
        DPUSH   x1
        NEXT

        DEFCODE "FILE-POSITION", 13, file_position      // ( fileid -- ud ior )
        NEED    1
        ROOM    2
        mov     x0, TOS
        mov     x1, #0
        mov     x2, #1                  // from where the file stands
        bl      file_seek
        mov     TOS, x0
        DPUSH   xzr
        DPUSH   x1
        NEXT

// A high half that is not 0 names a position no off_t holds. Reporting EINVAL
// is better than truncating the number and seeking somewhere surprising.
        DEFCODE "REPOSITION-FILE", 15, reposition_file  // ( ud fileid -- ior )
        NEED    3
        DPOP    x0                      // fileid
        DPOP    x3                      // the high half
        DPOP    x1                      // the low half
        cbnz    x3, 1f
        mov     x2, #0                  // from the start
        bl      file_seek
        DPUSH   x1
        NEXT
1:      mov     x1, #EINVAL
        DPUSH   x1
        NEXT

// FILE-STATUS answers one question: is the file there. x is 0 and carries
// nothing — Forth-2012 makes it implementation-defined, and a meaning invented
// now is one a program can come to depend on.
        DEFCODE "FILE-STATUS", 11, file_status_word     // ( c-addr u -- x ior )
        NEED    2
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        bl      file_status
        DPUSH   xzr                     // x, which says nothing
        DPUSH   x0
        NEXT

// Including a file.
//
// INCLUDE-FILE, INCLUDED and INCLUDE all end in include_impl, which makes the
// file the input source, interprets it line by line, and closes it. See
// docs/system/files.md.
//
// A file source cannot read into the shared input buffer. The line that called
// the include is still in there, and the saved >IN of the level below points
// into it, so overwriting it would lose the rest of that line and INCLUDE
// lib.f MAIN would never run MAIN. include_impl therefore carves the line
// buffer out of its own frame, which lives exactly as long as the source level
// does. EVALUATE already points UV_TIB at bytes it does not own.

// include_impl's frame. The name copy is for the message an error prints, and
// the buffer is the file's input buffer.
#define INC_FILEID      16
#define INC_NAMELEN     24
#define INC_ERR         32
#define INC_NAME        48
#define INC_BUF         (INC_NAME + INC_NAME_MAX)
#define INC_FRAME       (INC_BUF + TIB_SIZE)

// Interpret the file open on x0 to its end and close it. x1 and x2 are the
// name it was opened by, for a message, and a length of 0 means there is none.
//
// Returns 0, or the number of the error that stopped it. It closes the file on
// every path out, including the one an error takes. Forth-2012 makes
// INCLUDE-FILE close the file at the end and leaves the status of a file being
// interpreted implementation-defined when an error stops it, so one rule covers
// both.
//
// It reports rather than raises, because a raise would unwind past this frame
// before the close, and the frame holds the buffer the source is still reading.
// interpret_source and refill_impl both report for the same reason.
        .p2align        2
include_impl:
        sub     sp, sp, #TIB_SIZE
        sub     sp, sp, #INC_BUF
        stp     x29, x30, [sp]
        mov     x29, sp
        str     x0, [sp, #INC_FILEID]

// The name is copied because the caller's bytes may sit in a transient string
// buffer, which five interpreted S" strings inside this file would take back.
        mov     x3, #INC_NAME_MAX
        cmp     x2, x3
        csel    x2, x2, x3, lo
        str     x2, [sp, #INC_NAMELEN]
        add     x0, sp, #INC_NAME
        mov     x4, #0
1:      cmp     x4, x2
        b.hs    2f
        ldrb    w5, [x1, x4]
        strb    w5, [x0, x4]
        add     x4, x4, #1
        b       1b

2:      add     x0, sp, #INC_BUF
        mov     x1, #0                  // nothing read into it yet
        ldr     x2, [sp, #INC_FILEID]
        bl      src_push
        cbnz    x0, ii_no_level

        add     x0, sp, #INC_NAME
        str     x0, [UP, #UV_SRC_NAME]
        ldr     x0, [sp, #INC_NAMELEN]
        str     x0, [UP, #UV_SRC_NAME_LEN]

// The loop Forth-2012 describes: refill, interpret, and repeat until a refill
// finds no next line.
ii_loop:
        bl      refill_impl
        cbnz    x1, ii_refill_failed
        cbz     x0, ii_eof
        bl      interpret_source
        cbz     x0, ii_loop
        b       ii_error

ii_eof:
        mov     x0, #0
        b       ii_pop

ii_refill_failed:
        mov     x0, x1

// An error stopped it. ABORT and QUIT are not failures and say nothing.
// Anything else prints here rather than in machine_quit, because the name and
// the line number are in this frame and in the user variables this level is
// about to give up, and both are gone by the time the loop reads the number.
ii_error:
        str     x0, [sp, #INC_ERR]      // across quit_report and err_location
        cmp     x0, #ERR_ABORT
        b.hs    ii_pop                  // ABORT and QUIT are not failures
        cmp     x0, #ERR_REPORTED
        b.eq    1f
        bl      quit_report             // the message itself, written once
        mov     x0, #0                  // the file the error happened in
        b       2f
1:      mov     x0, #1                  // a file that included it
2:      bl      err_location
        mov     x0, #ERR_REPORTED

// Every path here arrives with the number to return in x0.
ii_pop:
        str     x0, [sp, #INC_ERR]
        bl      src_pop

ii_close:
        ldr     x0, [sp, #INC_FILEID]
        bl      file_close
        ldr     x0, [sp, #INC_ERR]
        b       ii_return

// No level was free, so nothing was pushed and there is nothing to pop. The
// file is closed all the same: this routine was handed it, and the caller has
// no way to reach it once this returns.
ii_no_level:
        str     x0, [sp, #INC_ERR]
        ldr     x0, [sp, #INC_FILEID]
        bl      file_close
        ldr     x0, [sp, #INC_ERR]

ii_return:
        ldp     x29, x30, [sp]
        add     sp, sp, #TIB_SIZE
        add     sp, sp, #INC_BUF
        ret

// Open the file named by x0, x1 and include it. Returns 0 or an error number.
//
// INCLUDED and INCLUDE have no ior in their stack effects, so a file that will
// not open is an error rather than a number a program reads. The message names
// the file, the way the undefined-word message names a word.
        .p2align        2
        .globl  included_impl
        FUNC_TYPE(included_impl)
included_impl:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]
        cbz     x1, inc_no_name

        mov     x2, #0                  // R/O
        bl      file_open
        cbnz    x1, inc_no_file
        ldp     x1, x2, [sp, #16]
        bl      include_impl
        b       inc_return

inc_no_name:
        mov     x0, #ERR_NO_NAME
        b       inc_return

inc_no_file:
        ldp     x0, x1, [sp, #16]
        bl      err_name
        mov     x0, #ERR_OPEN_FAILED

inc_return:
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(included_impl)

// INCLUDE-FILE names no file, so an error inside it says "a file" where the
// other two name one.
        DEFCODE "INCLUDE-FILE", 12, include_file        // ( i*x fileid -- j*x )
        NEED    1
        DPOP    x0                      // fileid
        mov     x1, #0                  // no name to report
        mov     x2, #0
        bl      include_impl
        RAISE
        NEXT

        DEFCODE "INCLUDED", 8, included // ( i*x c-addr u -- j*x )
        NEED    2
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        bl      included_impl
        RAISE
        NEXT
