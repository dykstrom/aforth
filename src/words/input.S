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
// The input buffer and the three user variables that describe it come from
// ticket 001: UV_TIB is its address, UV_TIB_LEN how many bytes the last line
// put there, and UV_TO_IN how far the parser has read. Ticket 007 is the first
// to move that offset.
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

// REFILL fills the input buffer and puts the parse offset back to the start.
// It is false at end of input, which is what ends a session, and it raises an
// error rather than truncating a line too long for the buffer: half a line
// parses as valid Forth that is missing its tail.
        DEFCODE "REFILL", 6, refill     // ( -- flag )
        ROOM    1
        ldr     x0, [UP, #UV_TIB]
        mov     x1, #TIB_SIZE
        mov     x2, #1                  // the user typed it, so keep it
        bl      read_line
        cmn     x0, #1                  // -1 is end of input
        b.eq    1f
        mov     x1, #TIB_SIZE
        cmp     x0, x1
        b.hi    2f
        str     x0, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]
        DPUSHM
        mov     TOS, #-1                // true
        NEXT
1:      str     xzr, [UP, #UV_TIB_LEN]  // nothing to parse after end of input
        str     xzr, [UP, #UV_TO_IN]
        DPUSHM
        mov     TOS, #0                 // false
        NEXT
2:      b       line_too_long

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
