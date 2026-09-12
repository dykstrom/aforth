// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The memory words.
//
// A character is a byte, so CHARS is nothing at all and CHAR+ adds one. MOVE,
// FILL and ERASE hand the work to libc, which is what the portability goal
// asks for and gives us its tuned copies for free. libc keeps x19 to x28, so
// the machine survives the call, and a word has no use for x30.
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

// ALIGN rounds the dictionary pointer up to a cell. The word that reads that
// pointer, HERE, and the words that move it arrive with ticket 010; the pointer
// itself is already in the user area.
        DEFCODE "ALIGN", 5, align       // ( -- )
        ldr     x0, [UP, #UV_HERE]
        add     x0, x0, #7
        and     x0, x0, #-8
        str     x0, [UP, #UV_HERE]
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
