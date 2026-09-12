// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The output words.
//
// Every byte aforth prints leaves through write_stdout in src/machine.S:
// write on file descriptor 1, unbuffered. There is no buffer, so there is no
// flushing rule and no question of what order a terminal sees things in and a
// pipe does not. The cost is a write per character out of EMIT, which ticket
// 012 is the place to price.
//
// A number is built in the pictured output buffer, right to left, by the words
// Forth-2012 gives for it, and . U. .R U.R are token lists over those words
// rather than code of their own. That is what keeps BASE honest: there is one
// place a digit is made, and every word that prints a number goes through it.
// .S is assembly, because it loops and there is no control flow until ticket
// 011, but it holds its digits through the same routine. See
// docs/system/output.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// Write one byte. It goes out of the C stack, there being nowhere else to
// point write at: the pictured output buffer holds a number being built, and a
// character written through here must not disturb it.
        .p2align        2
put_byte:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        strb    w0, [sp, #16]
        add     x0, sp, #16
        mov     x1, #1
        bl      write_stdout
        ldp     x29, x30, [sp], #32
        ret

// Start a number: the pointer goes back to the end of the buffer, which is
// what <# does.
        .p2align        2
hold_reset:
        ldr     x0, [UP, #UV_HOLD_END]
        str     x0, [UP, #UV_HOLD]
        ret

// Hold the byte in w0, which is what HOLD does. The buffer fills downward, so
// the guard tests the pointer before it moves.
        .p2align        2
hold_byte:
        ldr     x1, [UP, #UV_HOLD]
        HOLDROOM x1
        sub     x1, x1, #1
        strb    w0, [x1]
        str     x1, [UP, #UV_HOLD]
        ret

// Divide the double in x0, the low half, and x1, the high half, by BASE; hold
// the digit the division left; return the quotient the same way. This is # ,
// and #S and .S reach it too, so BASE is read in one place and a digit is made
// in one place.
//
// The division is in two steps because the quotient of a double is a double:
// the high half divides on its own, and its remainder rides above the low half
// into udiv128, where a divisor larger than that remainder keeps the second
// quotient inside a cell.
//
// A BASE of 0 or 1 is an ambiguous condition in Forth-2012, and each gets the
// answer the rest of aforth gives it: a zero divisor is the divide by zero
// every dividing word raises, and a BASE of 1 divides a number by itself
// forever and ends in the pictured output overflow. See
// docs/system/output.md.
        .p2align        2
hold_one:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        ldr     x2, [UP, #UV_BASE]
        NONZERO x2
        mov     x5, x0                  // the low half
        udiv    x6, x1, x2              // the quotient's high half
        msub    x0, x6, x2, x1          // what the high half left over
        mov     x1, x5
        bl      udiv128                 // x0 the digit, x1 the quotient's low
        mov     x5, x1                  // x6 and x5 now hold the quotient
        cmp     x0, #10
        add     x1, x0, #48             // '0'
        add     x2, x0, #55             // 'A' - 10
        csel    x0, x1, x2, lo
        bl      hold_byte
        mov     x0, x5
        mov     x1, x6
        ldp     x29, x30, [sp], #16
        ret

// Hold every digit of the double in x0 and x1, least significant first, and
// return the double reduced to zero. This is #S , which holds one digit even
// when the number is zero.
        .p2align        2
hold_all:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
1:      bl      hold_one
        orr     x2, x0, x1
        cbnz    x2, 1b
        ldp     x29, x30, [sp], #16
        ret

// Hold the cell in x0 as a signed number: its magnitude, then the minus sign
// if it had one. What . does, for the use of .S , which cannot call it.
        .p2align        2
hold_signed:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]
        cmp     x0, #0
        cneg    x0, x0, mi              // the magnitude
        mov     x1, #0                  // as a double
        bl      hold_all
        ldr     x0, [sp, #16]
        tbz     x0, #63, 1f
        mov     w0, #45                 // '-'
        bl      hold_byte
1:      ldp     x29, x30, [sp], #32
        ret

// Write what the buffer holds, which is what #> TYPE does.
        .p2align        2
hold_write:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        ldr     x0, [UP, #UV_HOLD]
        ldr     x1, [UP, #UV_HOLD_END]
        sub     x1, x1, x0
        bl      write_stdout
        ldp     x29, x30, [sp], #16
        ret

        DEFCODE "EMIT", 4, emit         // ( x -- )
        NEED    1
        mov     w0, TOSW
        DPOPM
        bl      put_byte
        NEXT

// TYPE is byte-oriented and stays that way: a character is a byte, so a
// counted string is bytes and this is one write of them (ADR 0004).
        DEFCODE "TYPE", 4, type         // ( c-addr u -- )
        NEED    2
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        cbz     x1, 1f
        bl      write_stdout
1:      NEXT

        DEFCODE "CR", 2, cr             // ( -- )
        mov     w0, #10
        bl      put_byte
        NEXT

// SPACES writes one space at a time rather than a run of them, because the
// buffer a run would be built in is the pictured output buffer, and .R calls
// SPACES while holding the string #> just handed it.
        DEFCODE "SPACES", 6, spaces     // ( n -- )
        NEED    1
        DPOP    x27                     // the count, kept across the writes
1:      cmp     x27, #0
        b.le    2f
        mov     w0, #32
        bl      put_byte
        sub     x27, x27, #1
        b       1b
2:      NEXT

// BL is a constant, and there is no CONSTANT until ticket 010, so it is shaped
// like TRUE and FALSE above.
        DEFCODE "BL", 2, bl             // ( -- char )
        ROOM    1
        DPUSHM
        mov     TOS, #32
        NEXT

// BASE is a user variable: the word pushes the address of the cell, and ! and
// @ do the rest. DECIMAL and HEX write it without a literal, which nothing can
// compile until ticket 010.
        DEFCODE "BASE", 4, base         // ( -- a-addr )
        ROOM    1
        DPUSHM
        add     TOS, UP, #UV_BASE
        NEXT

        DEFCODE "DECIMAL", 7, decimal   // ( -- )
        mov     x0, #10
        str     x0, [UP, #UV_BASE]
        NEXT

        DEFCODE "HEX", 3, hex           // ( -- )
        mov     x0, #16
        str     x0, [UP, #UV_BASE]
        NEXT

        DEFCODE "<#", 2, less_num       // ( -- )
        bl      hold_reset
        NEXT

        DEFCODE "#", 1, num             // ( ud1 -- ud2 )
        NEED    2
        mov     x1, TOS                 // the high half
        DGETM   0, x0                   // the low half
        bl      hold_one
        DSETM   0, x0
        mov     TOS, x1
        NEXT

        DEFCODE "#S", 2, num_s          // ( ud1 -- ud2 )
        NEED    2
        mov     x1, TOS
        DGETM   0, x0
        bl      hold_all
        DSETM   0, x0
        mov     TOS, x1
        NEXT

        DEFCODE "HOLD", 4, hold         // ( char -- )
        NEED    1
        mov     w0, TOSW
        DPOPM
        bl      hold_byte
        NEXT

        DEFCODE "SIGN", 4, sign         // ( n -- )
        NEED    1
        mov     x0, TOS
        DPOPM
        tbz     x0, #63, 1f
        mov     w0, #45                 // '-'
        bl      hold_byte
1:      NEXT

// #> drops the double it was handed and describes what the buffer holds. The
// address is the hold pointer itself, so the string must be typed before the
// next <# moves it.
        DEFCODE "#>", 2, num_greater    // ( xd -- c-addr u )
        NEED    2
        ldr     x0, [UP, #UV_HOLD]
        ldr     x1, [UP, #UV_HOLD_END]
        sub     x1, x1, x0
        DSETM   0, x0                   // the address goes under
        mov     TOS, x1                 // the length on top
        NEXT

// .S shows the stack without disturbing it, so it reads the items rather than
// popping them: the i-th from the bottom is at S0 - 8 * (i + 2) and the top is
// the cached one, which is the arithmetic machine_test_words does too. The
// depth and the items both go through the hold buffer, so .S follows BASE like
// every other printing word. An empty stack prints <0> and nothing else.
//
// The count and the index live in x27 and x28, the two registers a word may
// keep a value in across a call.
        DEFCODE ".S", 2, dot_s          // ( -- )
        sub     sp, sp, #16
        DDEPTH  x27
        bl      hold_reset
        mov     w0, #32                 // the space after the bracket
        bl      hold_byte
        mov     w0, #62                 // '>'
        bl      hold_byte
        mov     x0, x27
        mov     x1, #0
        bl      hold_all
        mov     w0, #60                 // '<'
        bl      hold_byte
        bl      hold_write

        mov     x28, #0                 // the item being printed, deepest first
1:      cmp     x28, x27
        b.ge    2f
        add     x0, x28, #1
        cmp     x0, x27
        b.eq    3f                      // the last one is the cached top
        ldr     x1, [UP, #UV_S0]
        add     x0, x28, #2
        sub     x0, x1, x0, lsl #3
        ldr     x0, [x0]
        b       4f
3:      mov     x0, TOS
4:      str     x0, [sp]                // across the calls that clobber x0
        bl      hold_reset
        mov     w0, #32
        bl      hold_byte
        ldr     x0, [sp]
        bl      hold_signed
        bl      hold_write
        add     x28, x28, #1
        b       1b
2:      add     sp, sp, #16
        NEXT

// The printing words, as token lists over the pictured output words above.
//
// This is what the standard's own definitions look like, and it is the reason
// none of them has a base of its own: every digit any of them prints is made
// by # , which reads BASE.
//
// FALSE stands in for the zero high half of a double. There is no literal yet
// and nothing parses a number until ticket 007, and FALSE is the cell with no
// bits set, which is the zero a double needs above a single.
        DEFWORD "SPACE", 5, space       // ( -- )
        TOKEN   bl
        TOKEN   emit
        ENDWORD

        DEFWORD ".", 1, dot             // ( n -- )
        TOKEN   dup
        TOKEN   abs
        TOKEN   false                   // the double's high half
        TOKEN   less_num
        TOKEN   num_s
        TOKEN   rot                     // bring the signed original back up
        TOKEN   sign
        TOKEN   num_greater
        TOKEN   type
        TOKEN   space
        ENDWORD

        DEFWORD "U.", 2, u_dot          // ( u -- )
        TOKEN   false
        TOKEN   less_num
        TOKEN   num_s
        TOKEN   num_greater
        TOKEN   type
        TOKEN   space
        ENDWORD

// .R and U.R pad on the left to the width they are given, and print nothing
// extra: a number already wider than the field is printed in full, because
// SPACES does nothing with a count of zero or less.
        DEFWORD ".R", 2, dot_r          // ( n1 n2 -- )
        TOKEN   to_r                    // hold the width
        TOKEN   dup
        TOKEN   abs
        TOKEN   false
        TOKEN   less_num
        TOKEN   num_s
        TOKEN   rot
        TOKEN   sign
        TOKEN   num_greater
        TOKEN   r_from
        TOKEN   over
        TOKEN   minus                   // the width less the length
        TOKEN   spaces
        TOKEN   type
        ENDWORD

        DEFWORD "U.R", 3, u_dot_r       // ( u n -- )
        TOKEN   to_r
        TOKEN   false
        TOKEN   less_num
        TOKEN   num_s
        TOKEN   num_greater
        TOKEN   r_from
        TOKEN   over
        TOKEN   minus
        TOKEN   spaces
        TOKEN   type
        ENDWORD
