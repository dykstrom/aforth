// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The arithmetic, the logic and the comparisons.
//
// Each uses the instruction that fits it rather than a sequence that would
// work anywhere: a Forth flag is csetm, which writes all ones, and division is
// sdiv with msub for the remainder.
//
// Division truncates toward zero, so / and MOD and /MOD are the symmetric
// pair, and */MOD divides with SM/REM to match them. Forth-2012 leaves that
// choice to the implementation and asks only that it be consistent.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// + : add the top two items.
        DEFCODE "+", 1, plus            // ( n1|u1 n2|u2 -- n3|u3 )
        NEED    2
        DPOPM   x0
        add     TOS, TOS, x0
        NEXT

        DEFCODE "-", 1, minus           // ( n1 n2 -- n3 )
        NEED    2
        DPOPM   x0
        sub     TOS, x0, TOS
        NEXT

        DEFCODE "*", 1, star            // ( n1 n2 -- n3 )
        NEED    2
        DPOPM   x0
        mul     TOS, x0, TOS
        NEXT

        DEFCODE "/", 1, slash           // ( n1 n2 -- n3 )
        NEED    2
        NONZERO TOS
        DPOPM   x0
        sdiv    TOS, x0, TOS
        NEXT

        DEFCODE "MOD", 3, mod           // ( n1 n2 -- n3 )
        NEED    2
        NONZERO TOS
        DPOPM   x0
        sdiv    x1, x0, TOS
        msub    TOS, x1, TOS, x0        // n1 - (n1 / n2) * n2
        NEXT

        DEFCODE "/MOD", 4, slash_mod    // ( n1 n2 -- n3 n4 )
        NEED    2
        NONZERO TOS
        DGETM   0, x0                   // x0 = n1
        sdiv    x1, x0, TOS             // x1 = the quotient
        msub    x2, x1, TOS, x0         // x2 = the remainder
        DSETM   0, x2
        mov     TOS, x1
        NEXT

        DEFCODE "ABS", 3, abs           // ( n -- u )
        NEED    1
        cmp     TOS, #0
        cneg    TOS, TOS, mi
        NEXT

        DEFCODE "NEGATE", 6, negate     // ( n1 -- n2 )
        NEED    1
        neg     TOS, TOS
        NEXT

        DEFCODE "MIN", 3, min           // ( n1 n2 -- n3 )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csel    TOS, x0, TOS, lt
        NEXT

        DEFCODE "MAX", 3, max           // ( n1 n2 -- n3 )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csel    TOS, x0, TOS, gt
        NEXT

        DEFCODE "1+", 2, one_plus       // ( n1 -- n2 )
        NEED    1
        add     TOS, TOS, #1
        NEXT

        DEFCODE "1-", 2, one_minus      // ( n1 -- n2 )
        NEED    1
        sub     TOS, TOS, #1
        NEXT

        DEFCODE "2*", 2, two_star       // ( x1 -- x2 )
        NEED    1
        lsl     TOS, TOS, #1
        NEXT

// 2/ is an arithmetic shift, so it floors rather than truncating: -1 2/ is -1.
// That is what Forth-2012 specifies, and it is not the same as 2 /.
        DEFCODE "2/", 2, two_slash      // ( x1 -- x2 )
        NEED    1
        asr     TOS, TOS, #1
        NEXT

// The mixed precision words. A double is two cells with the high one on top,
// so UM* and M* leave the high half in the cached top.
        DEFCODE "UM*", 3, um_star       // ( u1 u2 -- ud )
        NEED    2
        ROOM    1
        DGETM   0, x0                   // x0 = u1
        mul     x1, x0, TOS             // the low half
        umulh   x2, x0, TOS             // the high half
        DSETM   0, x1
        mov     TOS, x2
        NEXT

        DEFCODE "M*", 2, m_star         // ( n1 n2 -- d )
        NEED    2
        ROOM    1
        DGETM   0, x0
        mul     x1, x0, TOS
        smulh   x2, x0, TOS
        DSETM   0, x1
        mov     TOS, x2
        NEXT

// UM/MOD divides a double by a single. ARM64 divides 64 bits by 64, not 128,
// so the work is in udiv128 below.
        DEFCODE "UM/MOD", 6, um_slash_mod       // ( ud u1 -- u2 u3 )
        NEED    3
        NONZERO TOS
        mov     x2, TOS                 // the divisor
        DPOPM                           // the high half of ud
        mov     x0, TOS
        DGETM   0, x1                   // the low half
        bl      udiv128
        DSETM   0, x0                   // the remainder goes under
        mov     TOS, x1                 // the quotient on top
        NEXT

// SM/REM divides toward zero and takes the remainder's sign from the dividend.
// It divides the magnitudes and then puts the signs back.
        DEFCODE "SM/REM", 6, sm_slash_rem       // ( d1 n1 -- n2 n3 )
        NEED    3
        NONZERO TOS
        mov     x2, TOS                 // the divisor
        DPOPM                           // the high half of d1
        mov     x0, TOS
        DGETM   0, x1                   // the low half
        eor     x7, x0, x2              // the quotient's sign
        mov     x8, x0                  // the dividend's sign, for the remainder
        tbz     x0, #63, 1f
        negs    x1, x1                  // negate the double
        ngc     x0, x0
1:      cmp     x2, #0
        cneg    x2, x2, mi              // and the divisor
        bl      udiv128
        tbz     x8, #63, 2f
        neg     x0, x0                  // the remainder follows the dividend
2:      tbz     x7, #63, 3f
        neg     x1, x1
3:      DSETM   0, x0
        mov     TOS, x1
        NEXT

// FM/MOD floors and takes the remainder's sign from the divisor. It is SM/REM
// with one correction: when the signs differ and the division was not exact,
// step the quotient down and pull the remainder up by the divisor.
        DEFCODE "FM/MOD", 6, fm_slash_mod       // ( d1 n1 -- n2 n3 )
        NEED    3
        NONZERO TOS
        mov     x2, TOS
        DPOPM
        mov     x0, TOS
        DGETM   0, x1
        mov     x6, x2                  // the divisor, kept for the correction
        eor     x7, x0, x2
        mov     x8, x0
        tbz     x0, #63, 1f
        negs    x1, x1
        ngc     x0, x0
1:      cmp     x2, #0
        cneg    x2, x2, mi
        bl      udiv128
        tbz     x8, #63, 2f
        neg     x0, x0
2:      tbz     x7, #63, 3f
        neg     x1, x1
        cbz     x0, 3f                  // an exact division needs no correction
        sub     x1, x1, #1
        add     x0, x0, x6
3:      DSETM   0, x0
        mov     TOS, x1
        NEXT

// */ and */MOD are the two words defined as token lists rather than in
// assembly, and it is not for want of an instruction. Both multiply to a
// double and divide that, which is the whole point of them: it is what keeps
// n1 n2 */ n3 exact when the product does not fit a cell. M* and SM/REM
// already do that work, so a primitive would only be a wrapper around this
// list. They also keep DOCOL and EXIT exercised until : arrives in ticket 010.
        DEFWORD "*/MOD", 5, star_slash_mod      // ( n1 n2 n3 -- n4 n5 )
        TOKEN   to_r                    // hold the divisor
        TOKEN   m_star                  // n1 n2 -> a double
        TOKEN   r_from
        TOKEN   sm_slash_rem
        ENDWORD

        DEFWORD "*/", 2, star_slash     // ( n1 n2 n3 -- n4 )
        TOKEN   star_slash_mod
        TOKEN   nip                     // drop the remainder
        ENDWORD

        DEFCODE "AND", 3, and           // ( x1 x2 -- x3 )
        NEED    2
        DPOPM   x0
        and     TOS, x0, TOS
        NEXT

        DEFCODE "OR", 2, or             // ( x1 x2 -- x3 )
        NEED    2
        DPOPM   x0
        orr     TOS, x0, TOS
        NEXT

        DEFCODE "XOR", 3, xor           // ( x1 x2 -- x3 )
        NEED    2
        DPOPM   x0
        eor     TOS, x0, TOS
        NEXT

        DEFCODE "INVERT", 6, invert     // ( x1 x2 -- x3 )
        NEED    1
        mvn     TOS, TOS
        NEXT

// The shifts take their count from a register, and ARM64 reads only its low
// six bits. Forth-2012 calls a count of a cell's width or more an ambiguous
// condition, so 1 64 LSHIFT is 1 here rather than 0.
        DEFCODE "LSHIFT", 6, lshift     // ( x1 u -- x2 )
        NEED    2
        DPOPM   x0
        lsl     TOS, x0, TOS
        NEXT

        DEFCODE "RSHIFT", 6, rshift     // ( x1 u -- x2 )
        NEED    2
        DPOPM   x0
        lsr     TOS, x0, TOS
        NEXT

// The comparisons. A Forth true is all bits set, which is what csetm writes.
        DEFCODE "=", 1, equals          // ( x1 x2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, eq
        NEXT

        DEFCODE "<>", 2, not_equals     // ( x1 x2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, ne
        NEXT

        DEFCODE "<", 1, less            // ( n1 n2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, lt
        NEXT

        DEFCODE ">", 1, greater         // ( n1 n2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, gt
        NEXT

        DEFCODE "U<", 2, u_less         // ( u1 u2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, lo
        NEXT

        DEFCODE "U>", 2, u_greater      // ( u1 u2 -- flag )
        NEED    2
        DPOPM   x0
        cmp     x0, TOS
        csetm   TOS, hi
        NEXT

        DEFCODE "0=", 2, zero_equals    // ( x -- flag )
        NEED    1
        cmp     TOS, #0
        csetm   TOS, eq
        NEXT

        DEFCODE "0<>", 3, zero_not_equals       // ( x -- flag )
        NEED    1
        cmp     TOS, #0
        csetm   TOS, ne
        NEXT

        DEFCODE "0<", 2, zero_less      // ( n -- flag )
        NEED    1
        cmp     TOS, #0
        csetm   TOS, lt
        NEXT

        DEFCODE "0>", 2, zero_greater   // ( n -- flag )
        NEED    1
        cmp     TOS, #0
        csetm   TOS, gt
        NEXT

        DEFCODE "TRUE", 4, true         // ( -- true )
        ROOM    1
        DPUSHM
        mov     TOS, #-1
        NEXT

        DEFCODE "FALSE", 5, false       // ( -- false )
        ROOM    1
        DPUSHM
        mov     TOS, #0
        NEXT


        .text

// Divide a 128-bit dividend by a 64-bit divisor.
//
// x0 the high half, x1 the low half, x2 the divisor. Returns the remainder in
// x0 and the quotient in x1, and leaves x2 and x6 to x8 alone, because the
// signed words keep the signs they have to put back in those.
//
// ARM64 divides 64 bits by 64, so a wider dividend is shift and subtract, one
// bit at a time. The quotient shifts in at the bottom of the low half as the
// dividend shifts out of the top of it, which is why one register serves as
// both. A quotient too big for a cell is an ambiguous condition in
// Forth-2012, and what comes out here is whatever the loop makes of it.
//
// Ticket 013 replaces the loop: udiv on 32-bit halves would do the same work in
// a handful of instructions. It is measured at about 35 ns, which is the
// largest single cost in aforth so far, though a single-cell number printed
// arrives here with an empty high half and takes the fast path above instead.
        .p2align        2
udiv128:
        cbnz    x0, 1f
        udiv    x3, x1, x2              // nothing in the high half: one divide
        msub    x0, x3, x2, x1
        mov     x1, x3
        ret

1:      mov     x4, #64
2:      lsr     x3, x0, #63             // the bit about to leave the dividend
        lsl     x0, x0, #1
        orr     x0, x0, x1, lsr #63
        lsl     x1, x1, #1
        cmp     x0, x2
        cset    x5, hs
        orr     x5, x5, x3              // that bit means 2^64, so subtract
        cbz     x5, 3f
        sub     x0, x0, x2
        orr     x1, x1, #1              // and record a quotient bit
3:      subs    x4, x4, #1
        b.ne    2b
        ret
