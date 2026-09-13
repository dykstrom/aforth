// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The memory words and dictionary allocation.
//
// A character is a byte, so CHARS is nothing at all and CHAR+ adds one. MOVE,
// FILL and ERASE hand the work to libc, which is what the portability goal
// asks for and gives us its tuned copies for free. libc keeps x19 to x28, so
// the machine survives the call, and a word has no use for x30.
//
// HERE, ALLOT, , and C, grow the dictionary, and dict_set_here and dict_comma
// below them are the only two routines that write the allocation pointer.
// src/words/compile.S builds headers on top of them. See
// docs/system/compiling.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

        DEFCODE "@", 1, fetch           // ( a-addr -- x )
        NEED    1
        ldr     TOS, [TOS]
        NEXT

        DEFCODE "!", 1, store           // ( x a-addr -- )
        NEED    2
        DPOPM   x0                      // x0 = x, and the stack loses it
        str     x0, [TOS]
        DPOPM                           // and then the address
        NEXT

        DEFCODE "C@", 2, c_fetch        // ( c-addr -- char )
        NEED    1
        ldrb    TOSW, [TOS]
        NEXT

        DEFCODE "C!", 2, c_store        // ( char c-addr -- )
        NEED    2
        DPOPM   x0
        strb    w0, [TOS]
        DPOPM
        NEXT

        DEFCODE "+!", 2, plus_store     // ( n a-addr -- )
        NEED    2
        DPOPM   x0
        ldr     x1, [TOS]
        add     x1, x1, x0
        str     x1, [TOS]
        DPOPM
        NEXT

        DEFCODE "CELL+", 5, cell_plus   // ( a-addr1 -- a-addr2 )
        NEED    1
        add     TOS, TOS, #8
        NEXT

        DEFCODE "CELLS", 5, cells       // ( n1 -- n2 )
        NEED    1
        lsl     TOS, TOS, #3
        NEXT

        DEFCODE "CHAR+", 5, char_plus   // ( c-addr1 -- c-addr2 )
        NEED    1
        add     TOS, TOS, #1
        NEXT

// CHARS is the identity, a character being a byte. It guards anyway, so that a
// stack effect of ( n1 -- n2 ) is honest about needing an item.
        DEFCODE "CHARS", 5, chars       // ( n1 -- n2 )
        NEED    1
        NEXT

// Dictionary allocation.
//
// HERE is a cell in the user area and every word below moves it. The two
// routines are the only things that write it, so the bound is tested in one
// place: the pointer must stay between the dictionary base and UV_DICT_END,
// and a move that would leave that range writes nothing and reports
// ERR_DICT_FULL.
//
// They report rather than raise, because the outer interpreter calls
// dict_comma too, to compile a token, and it runs outside aforth_enter where a
// raise would unwind to a frame that is already gone. A word turns the report
// into a raise with the RAISE macro.

// Move HERE to x0. Returns 0, or ERR_DICT_FULL with HERE left where it was.
// The comparison is unsigned, so a pointer that ran past either end of the
// dictionary — or wrapped, which a wild ALLOT does — fails it.
        .p2align        2
        .globl  dict_set_here
dict_set_here:
        ldr     x1, [UP, #UV_DICT_END]
        cmp     x0, x1
        b.hi    1f
        cmp     x0, DBASE
        b.lo    1f
        str     x0, [UP, #UV_HERE]
        mov     x0, #0
        ret
1:      mov     x0, #ERR_DICT_FULL
        ret

// Store the cell in x0 at HERE and move HERE one cell up. Returns 0, or
// ERR_DICT_FULL having written nothing.
//
// This is , and it is also how the outer interpreter compiles a token and how
// dict_compile_literal compiles a literal.
        .p2align        2
        .globl  dict_comma
dict_comma:
        ldr     x1, [UP, #UV_HERE]
        add     x2, x1, #8
        ldr     x3, [UP, #UV_DICT_END]
        cmp     x2, x3
        b.hi    1f
        str     x0, [x1]
        str     x2, [UP, #UV_HERE]
        mov     x0, #0
        ret
1:      mov     x0, #ERR_DICT_FULL
        ret

        DEFCODE "HERE", 4, here         // ( -- addr )
        ROOM    1
        ldr     x0, [UP, #UV_HERE]
        DPUSH   x0
        NEXT

// UNUSED is how far HERE may still move up, which is the one way a program can
// see the bound the two routines above test against.
        DEFCODE "UNUSED", 6, unused     // ( -- u )
        ROOM    1
        ldr     x0, [UP, #UV_DICT_END]
        ldr     x1, [UP, #UV_HERE]
        sub     x0, x0, x1
        DPUSH   x0
        NEXT

// ALLOT reserves n bytes when n is positive and releases |n| when it is
// negative, which is the one word that moves HERE back down.
        DEFCODE "ALLOT", 5, allot       // ( n -- )
        NEED    1
        ldr     x0, [UP, #UV_HERE]
        add     x0, x0, TOS
        bl      dict_set_here
        RAISE
        DPOPM
        NEXT

        DEFCODE ",", 1, comma           // ( x -- )
        NEED    1
        mov     x0, TOS
        bl      dict_comma
        RAISE
        DPOPM
        NEXT

// C, stores one byte, so it leaves HERE unaligned. Forth-2012 asks the program
// to say ALIGN before it stores a cell again.
        DEFCODE "C,", 2, c_comma        // ( char -- )
        NEED    1
        ldr     x27, [UP, #UV_HERE]     // kept across the call, as x27 may be
        add     x0, x27, #1
        bl      dict_set_here
        RAISE
        strb    TOSW, [x27]
        DPOPM
        NEXT

// ALIGN rounds the dictionary pointer up to a cell, which is what a program
// says after C, before it stores a cell again.
        DEFCODE "ALIGN", 5, align       // ( -- )
        ldr     x0, [UP, #UV_HERE]
        add     x0, x0, #7
        and     x0, x0, #-8
        bl      dict_set_here
        RAISE
        NEXT

        DEFCODE "ALIGNED", 7, aligned   // ( addr -- a-addr )
        NEED    1
        add     TOS, TOS, #7
        and     TOS, TOS, #-8
        NEXT

// MOVE copies u bytes and the two regions may overlap, which is memmove's
// contract exactly. Forth puts the source under the destination.
        DEFCODE "MOVE", 4, move         // ( addr1 addr2 u -- )
        NEED    3
        DPOP    x2                      // u
        DPOP    x0                      // addr2, the destination
        DPOP    x1                      // addr1, the source
        bl      CSYM(memmove)
        NEXT

        DEFCODE "FILL", 4, fill         // ( c-addr u char -- )
        NEED    3
        DPOP    x1                      // char
        DPOP    x2                      // u
        DPOP    x0                      // c-addr
        bl      CSYM(memset)
        NEXT

        DEFCODE "ERASE", 5, erase       // ( addr u -- )
        NEED    2
        DPOP    x2                      // u
        DPOP    x0                      // addr
        mov     x1, #0
        bl      CSYM(memset)
        NEXT
