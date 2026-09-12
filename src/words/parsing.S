// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Parsing, name lookup and number conversion.
//
// Three answers the outer interpreter needs for every name on a line: where
// the name ends, whether the dictionary holds it, and what number it is if
// not. machine_quit in src/outer.S decides what to do with them; nothing here
// decides anything.
//
// See docs/system/parsing.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// Fold one ASCII letter to upper case, and leave every other byte alone. A
// byte of 0x80 and above is part of a multi-byte character and is compared as
// it stands, which is what ADR 0004 requires of name lookup.
.macro  FOLD reg, tmp1, tmp2
        sub     \tmp1, \reg, #97        // 'a'
        cmp     \tmp1, #26
        sub     \tmp2, \reg, #32        // to upper case
        csel    \reg, \tmp2, \reg, lo
.endm

// Search the dictionary for the name at x0, x1 bytes long.
//
// Returns the execution token in x0 and the entry's flags in x1, or 0 and 0
// when the name is not there. An xt is the offset of a code field from DBASE
// (ADR 0005), never an address, and 0 is free to mean "no such word" because
// the dictionary's first cell is reserved.
//
// The chain starts at LATEST and every link is an offset from DBASE, so the
// walk is valid in a process that loaded the image somewhere else. An entry
// marked F_HIDDEN is stepped over rather than matched.
        .p2align        2
        .globl  dict_find
dict_find:
        ldr     x2, [UP, #UV_LATEST]    // the newest entry, an offset
1:      cbz     x2, df_none             // 0 ends the chain
        add     x3, DBASE, x2
        ldrb    w4, [x3, #ENT_FLAGS]
        tst     w4, #F_HIDDEN
        b.ne    df_next
        ldrb    w5, [x3, #ENT_COUNT]
        cmp     x5, x1
        b.ne    df_next

        add     x6, x3, #ENT_NAME       // the entry's name
        mov     x7, x0                  // the name being looked for
        mov     x8, x1
2:      cbz     x8, df_found
        ldrb    w9, [x6], #1
        ldrb    w10, [x7], #1
        FOLD    w9, w11, w12
        FOLD    w10, w11, w12
        cmp     w9, w10
        b.ne    df_next
        sub     x8, x8, #1
        b       2b

df_next:
        ldr     x2, [x3, #ENT_LINK]
        b       1b

df_found:
        // The code field follows the name, padded to a cell: the arithmetic
        // HEADER does at assembly time, done here at run time.
        ldrb    w5, [x3, #ENT_COUNT]
        add     x5, x5, #(ENT_NAME + 7)
        and     x5, x5, #-8
        add     x0, x2, x5
        ldrb    w1, [x3, #ENT_FLAGS]
        ret

df_none:
        mov     x0, #0
        mov     x1, #0
        ret

// The value of the digit in w0, or -1 when it is not a digit in BASE.
//
// The one place that knows the digit set, so >NUMBER and ?NUMBER cannot
// disagree about it, the way # is the one place for output. Letters fold, so
// ff and FF are the same number, and the characters between '9' and 'A' are
// rejected rather than read as digits above nine.
        .p2align        2
digit_value:
        sub     w1, w0, #48             // '0'
        cmp     w1, #10
        b.lo    1f

        FOLD    w0, w1, w2
        sub     w1, w0, #55             // 'A' - 10
        cmp     w1, #10                 // ':' to '@' land below ten here
        b.lo    dv_bad
        cmp     w1, #36
        b.hs    dv_bad

1:      ldr     x2, [UP, #UV_BASE]
        cmp     x1, x2
        b.hs    dv_bad
        mov     x0, x1
        ret

dv_bad:
        mov     x0, #-1
        ret

// Convert the whole name at x0, x1 bytes long, to one cell.
//
// Returns the value in x0 and a true flag in x1, or 0 and 0 when the name is
// not a number in BASE. A leading minus is allowed, and every other character
// must convert: a name that is half a number is not a number.
//
// ?NUMBER is this and nothing more, and the outer interpreter calls it for
// every name the dictionary does not hold, so the word and the interpreter
// cannot disagree about what a number is.
        .p2align        2
        .globl  number_impl
number_impl:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x3, x0                  // where the characters are
        mov     x4, x1                  // how many are left
        cbz     x4, ni_bad
        mov     x10, #0                 // was there a minus?
        ldrb    w0, [x3]
        cmp     w0, #45                 // '-'
        b.ne    1f
        mov     x10, #1
        add     x3, x3, #1
        sub     x4, x4, #1
        cbz     x4, ni_bad              // a minus on its own is not a number
1:      mov     x5, #0
2:      cbz     x4, 3f
        ldrb    w0, [x3]
        bl      digit_value
        cmn     x0, #1
        b.eq    ni_bad                  // one character that is not a digit
        ldr     x7, [UP, #UV_BASE]
        mul     x5, x5, x7
        add     x5, x5, x0
        add     x3, x3, #1
        sub     x4, x4, #1
        b       2b
3:      cbz     x10, 4f
        neg     x5, x5
4:      mov     x0, x5
        mov     x1, #-1
        ldp     x29, x30, [sp], #16
        ret

ni_bad:
        mov     x0, #0
        mov     x1, #0
        ldp     x29, x30, [sp], #16
        ret

// Cut the next name out of the input buffer: skip spaces, take everything to
// the next space, and leave >IN past it. Returns the address in x0 and the
// length in x1, which is 0 at the end of the line.
//
// PARSE-NAME is this, and ' is this followed by a search.
        .p2align        2
        .globl  parse_name_impl
parse_name_impl:
        ldr     x0, [UP, #UV_TIB]
        ldr     x1, [UP, #UV_TIB_LEN]
        ldr     x2, [UP, #UV_TO_IN]

1:      cmp     x2, x1
        b.hs    2f
        ldrb    w3, [x0, x2]
        cmp     w3, #32                 // a space
        b.ne    2f
        add     x2, x2, #1
        b       1b

2:      add     x4, x0, x2              // where the name starts
        mov     x5, x2
3:      cmp     x2, x1
        b.hs    4f
        ldrb    w3, [x0, x2]
        cmp     w3, #32
        b.eq    4f
        add     x2, x2, #1
        b       3b

4:      sub     x6, x2, x5              // how long it is
        cmp     x2, x1
        b.hs    5f
        add     x2, x2, #1              // step over the space that ended it
5:      str     x2, [UP, #UV_TO_IN]
        mov     x0, x4
        mov     x1, x6
        ret

        DEFCODE "PARSE-NAME", 10, parse_name    // ( "<spaces>name<space>" -- c-addr u )
        ROOM    2
        bl      parse_name_impl
        DPUSH   x0
        DPUSH   x1
        NEXT

// PARSE takes its delimiter from the stack and skips nothing: it starts where
// >IN stands, which is what makes it the word a comment or a string literal is
// parsed with.
        DEFCODE "PARSE", 5, parse       // ( char "ccc<char>" -- c-addr u )
        NEED    1
        ROOM    1
        mov     x7, TOS                 // the delimiter
        ldr     x0, [UP, #UV_TIB]
        ldr     x1, [UP, #UV_TIB_LEN]
        ldr     x2, [UP, #UV_TO_IN]
        add     x4, x0, x2
        mov     x5, x2
1:      cmp     x2, x1
        b.hs    2f
        ldrb    w3, [x0, x2]
        cmp     w3, w7
        b.eq    2f
        add     x2, x2, #1
        b       1b
2:      sub     x6, x2, x5
        cmp     x2, x1
        b.hs    3f
        add     x2, x2, #1              // step over the delimiter
3:      str     x2, [UP, #UV_TO_IN]
        mov     TOS, x4
        DPUSH   x6
        NEXT

// WORD skips leading delimiters and copies what it parses to HERE as a counted
// string, which is the transient region Forth-2012 allows it. The next WORD
// overwrites it, and so does the next thing that allocates.
//
// A name longer than 255 bytes cannot be counted in one byte, so the copy stops
// there while the parse runs on to the delimiter, leaving >IN where it belongs.
        DEFCODE "WORD", 4, word         // ( char "<chars>ccc<char>" -- c-addr )
        NEED    1
        mov     x7, TOS
        ldr     x0, [UP, #UV_TIB]
        ldr     x1, [UP, #UV_TIB_LEN]
        ldr     x2, [UP, #UV_TO_IN]

1:      cmp     x2, x1
        b.hs    2f
        ldrb    w3, [x0, x2]
        cmp     w3, w7
        b.ne    2f
        add     x2, x2, #1
        b       1b

2:      ldr     x8, [UP, #UV_HERE]
        add     x9, x8, #1              // the bytes follow the count
        mov     x6, #0
3:      cmp     x2, x1
        b.hs    4f
        ldrb    w3, [x0, x2]
        cmp     w3, w7
        b.eq    4f
        add     x2, x2, #1
        cmp     x6, #255
        b.hs    3b                      // parsed, but no room left to keep it
        strb    w3, [x9], #1
        add     x6, x6, #1
        b       3b

4:      cmp     x2, x1
        b.hs    5f
        add     x2, x2, #1
5:      str     x2, [UP, #UV_TO_IN]
        strb    w6, [x8]
        mov     TOS, x8
        NEXT

        DEFCODE "COUNT", 5, count       // ( c-addr1 -- c-addr2 u )
        NEED    1
        ROOM    1
        ldrb    w0, [TOS]
        add     TOS, TOS, #1
        DPUSH   x0
        NEXT

// FIND takes a counted string, which is what WORD leaves, and reports 1 for an
// immediate word and -1 for any other. A name it cannot find comes back
// unchanged under a 0.
        DEFCODE "FIND", 4, find         // ( c-addr -- c-addr 0 | xt 1 | xt -1 )
        NEED    1
        ROOM    1
        ldrb    w1, [TOS]               // the count
        add     x0, TOS, #1             // the bytes
        bl      dict_find
        cbz     x0, 1f
        tst     w1, #F_IMMEDIATE
        mov     x2, #-1
        mov     x3, #1
        csel    x2, x3, x2, ne
        mov     TOS, x0
        DPUSH   x2
        NEXT
1:      DPUSHM                          // the string stays, under a false flag
        mov     TOS, #0
        NEXT

// ' parses the next name and gives its execution token. A name that is not
// there raises, rather than handing back a token that would fault when it was
// executed, and the message names it.
//
// The name is kept in x27 and x28 across the search, because dict_find returns
// in x0 and x1 and undefined_word wants the name there. Those two registers
// exist for a word to keep something in.
        DEFCODE "'", 1, tick            // ( "<spaces>name" -- xt )
        ROOM    1
        bl      parse_name_impl
        mov     x27, x0
        mov     x28, x1
        cbz     x1, 1f                  // nothing left on the line
        bl      dict_find
        cbz     x0, 1f
        DPUSH   x0
        NEXT
1:      mov     x0, x27
        mov     x1, x28
        b       undefined_word

// >NUMBER converts while the characters convert and stops at the first one
// that does not, leaving the rest for the caller to look at. The accumulator is
// a double, so the multiply is a double one: the low half's high bits carry up.
        DEFCODE ">NUMBER", 7, to_number // ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
        NEED    4
        mov     x4, TOS                 // how many characters are left
        DGETM   0, x3                   // where they are
        DGETM   1, x6                   // the accumulator, high half
        DGETM   2, x5                   // and low
1:      cbz     x4, 2f
        ldrb    w0, [x3]
        bl      digit_value
        cmn     x0, #1
        b.eq    2f
        ldr     x7, [UP, #UV_BASE]
        umulh   x8, x5, x7
        mul     x5, x5, x7
        mul     x9, x6, x7
        add     x6, x8, x9
        adds    x5, x5, x0
        adc     x6, x6, xzr
        add     x3, x3, #1
        sub     x4, x4, #1
        b       1b
2:      DSETM   2, x5
        DSETM   1, x6
        DSETM   0, x3
        mov     TOS, x4
        NEXT

// ?NUMBER is the conversion the interpreter wants: the whole string or nothing,
// a leading minus allowed, and a flag saying which it was. Not a Forth-2012
// word; the name is the one FIG and F83 used. The conversion itself is
// number_impl above, which the outer interpreter calls as well.
        DEFCODE "?NUMBER", 7, q_number  // ( c-addr u -- n true | c-addr u false )
        NEED    2
        ROOM    1
        mov     x1, TOS                 // how many characters
        DGETM   0, x0                   // where they are
        bl      number_impl
        cbz     x1, 1f
        DSETM   0, x0                   // the number replaces the address
        mov     TOS, #-1
        NEXT
1:      DPUSHM                          // the string stays, under a false flag
        mov     TOS, #0
        NEXT

// CHAR is PARSE-NAME and the first byte of what it found. [CHAR], its compiling
// twin, waits for ticket 010 and the literals it has nothing to compile without.
        DEFWORD "CHAR", 4, char         // ( "<spaces>name" -- char )
        TOKEN   parse_name
        TOKEN   drop
        TOKEN   c_fetch
        ENDWORD
