// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The defining words: how a word gets into the dictionary, and how the outer
// interpreter is told to compile rather than run.
//
// header_impl below is the one place an entry is built at run time, and it
// lays out exactly what the HEADER macro in src/include/dict.h lays out at
// assembly time. Everything it writes is an offset, an index or a name byte,
// so a dictionary grown here holds no more absolute addresses than the image
// it grew from (ADR 0005).
//
// The compiling half of the interpret loop is interpret_source in src/outer.S:
// it reads STATE and compiles a token instead of running it. The words that
// branch inside a definition are in src/words/control.S.
//
// See docs/system/compiling.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// Build a dictionary entry for the name at x0, x1 bytes long, whose code field
// holds the routine index in x2 and whose flags byte is x3.
//
// Leaves HERE on the cell after the code field, which is where a parameter
// field starts, and LATEST on the new entry. Nothing is pushed or popped.
//
// It raises rather than reporting, because every word that calls it runs
// inside aforth_enter. Three things stop it: no name left on the line, a name
// too long to count in one byte, and a dictionary with no room for the entry.
//
// The layout is HEADER's: link, flags, count, the name, pad to a cell, then the
// code field. The pad is zeroed so that the same source builds the same bytes.
        .p2align        2
header_impl:
        cbz     x1, hi_no_name
        cmp     x1, #255
        b.hi    hi_too_long

        ldr     x4, [UP, #UV_HERE]
        add     x4, x4, #7
        and     x4, x4, #-8             // an entry starts on a cell

        CFOFF   x5, x1                  // link, flags, count, name and pad
        add     x6, x4, x5
        add     x6, x6, #8              // one past the code field
        ldr     x7, [UP, #UV_DICT_END]
        cmp     x6, x7
        b.hi    hi_full

        ldr     x7, [UP, #UV_LATEST]
        str     x7, [x4, #ENT_LINK]     // the chain, as an offset from DBASE
        strb    w3, [x4, #ENT_FLAGS]
        strb    w1, [x4, #ENT_COUNT]

        add     x12, x4, x5             // where the code field goes
        add     x8, x4, #ENT_NAME
        mov     x9, x0
        mov     x10, x1
1:      cbz     x10, 2f
        ldrb    w11, [x9], #1
        strb    w11, [x8], #1
        sub     x10, x10, #1
        b       1b
2:      cmp     x8, x12
        b.hs    3f
        strb    wzr, [x8], #1
        b       2b

3:      str     x2, [x12]               // code field: a routine index
        str     x6, [UP, #UV_HERE]
        sub     x4, x4, DBASE
        str     x4, [UP, #UV_LATEST]    // the entry, as an offset from DBASE
        ret

hi_no_name:
        mov     x0, #ERR_NO_NAME
        b       machine_error
hi_too_long:
        mov     x0, #ERR_NAME_TOO_LONG
        b       machine_error
hi_full:
        mov     x0, #ERR_DICT_FULL
        b       machine_error

// CREATE builds an entry whose code field is DOVAR, so running the word pushes
// the address of the space that follows it. That space is whatever the program
// allots next; CREATE itself reserves none.
        DEFCODE "CREATE", 6, create     // ( "<spaces>name" -- )
        bl      parse_name_impl
        mov     x2, #XT_dovar
        mov     x3, #0
        bl      header_impl
        NEXT

// : builds an entry whose code field is DOCOL and sets STATE, so that the
// interpret loop compiles what follows instead of running it.
//
// The entry is hidden until ; unhides it, which is what makes the name inside
// the definition mean the previous word of that name rather than the one being
// written. Nothing else uses F_HIDDEN except (STOP) and (LIT), which are
// hidden for good.
//
// The name is parsed from the line : is on. STATE outlives the line, so the
// rest of a definition may be typed on as many lines as the programmer likes,
// but the name may not be one of them.
        DEFCODE ":", 1, colon           // ( C: "<spaces>name" -- colon-sys )
        bl      parse_name_impl
        mov     x2, #XT_docol
        mov     x3, #F_HIDDEN
        bl      header_impl
        mov     x0, #-1
        str     x0, [UP, #UV_STATE]
        NEXT

// ; ends the definition: EXIT's token, the name made findable, and STATE back
// to interpreting. Immediate, because the loop is compiling when it meets it.
        DEFCODE ";", 1, semicolon, F_IMMEDIATE  // ( C: colon-sys -- )
        mov     x0, #TOK_exit
        bl      dict_comma
        RAISE
        ldr     x1, [UP, #UV_LATEST]
        add     x1, DBASE, x1
        ldrb    w2, [x1, #ENT_FLAGS]
        bic     w2, w2, #F_HIDDEN
        strb    w2, [x1, #ENT_FLAGS]
        str     xzr, [UP, #UV_STATE]
        NEXT

// IMMEDIATE marks the newest entry, which is the definition ; has just ended.
        DEFCODE "IMMEDIATE", 9, immediate       // ( -- )
        ldr     x1, [UP, #UV_LATEST]
        add     x1, DBASE, x1
        ldrb    w2, [x1, #ENT_FLAGS]
        orr     w2, w2, #F_IMMEDIATE
        strb    w2, [x1, #ENT_FLAGS]
        NEXT

// [ and ] switch the loop between running and compiling. [ is immediate, so it
// runs while the loop is compiling; ] is not, because the loop is interpreting
// when it meets it.
        DEFCODE "[", 1, left_bracket, F_IMMEDIATE       // ( -- )
        str     xzr, [UP, #UV_STATE]
        NEXT

        DEFCODE "]", 1, right_bracket   // ( -- )
        mov     x0, #-1
        str     x0, [UP, #UV_STATE]
        NEXT

// LITERAL compiles the cell on the stack, so that the definition pushes it
// when it runs. That is the whole of what a number typed while compiling does,
// and the interpret loop compiles one through the same routine.
        DEFCODE "LITERAL", 7, literal, F_IMMEDIATE      // ( x -- )
        NEED    1
        mov     x0, TOS
        bl      dict_compile_literal
        RAISE
        DPOPM
        NEXT

// [CHAR] is CHAR and LITERAL: the first byte of the name it parses, compiled.
// A character is a byte (ADR 0004), so the first byte of a multi-byte
// character is what it gives, as CHAR does.
        DEFCODE "[CHAR]", 6, bracket_char, F_IMMEDIATE  // ( C: "<spaces>name" -- ) ( -- char )
        bl      parse_name_impl
        cbz     x1, 1f
        ldrb    w0, [x0]
        bl      dict_compile_literal
        RAISE
        NEXT
1:      mov     x0, #ERR_NO_NAME
        b       machine_error

// CONSTANT builds an entry whose code field is DOCON and stores the value in
// the parameter field, so running the word pushes it.
        DEFCODE "CONSTANT", 8, constant // ( x "<spaces>name" -- )
        NEED    1
        bl      parse_name_impl
        mov     x2, #XT_docon
        mov     x3, #0
        bl      header_impl
        mov     x0, TOS
        bl      dict_comma
        RAISE
        DPOPM
        NEXT

// VARIABLE is CREATE and one cell. Forth-2012 leaves the cell's initial value
// undefined; zeroing it costs nothing and is one less thing to be surprised by.
        DEFWORD "VARIABLE", 8, variable // ( "<spaces>name" -- )
        TOKEN   create
        TOKEN   false
        TOKEN   comma
        ENDWORD

// The two string literals.
//
// Both are immediate and both parse with a double quote as the delimiter,
// starting where >IN stands. parse_name_impl has already left it just past the
// one space that ended the word's own name, so S" ccc" takes ccc, and a
// delimiter that comes straight away gives the empty string.
//
// A string whose delimiter never comes takes the rest of the line and raises
// nothing. That is the choice ( makes, for the reason ( gives: the only line
// aforth could read a delimiter from is the terminal's, and waiting there for
// a quote the user does not know it wants is a trap.
//
// While compiling, each lays the bytes inside the definition through
// dict_compile_string below. While interpreting, S" copies them into a
// transient buffer and ." writes them straight out. Forth-2012 leaves the
// interpretation semantics of both undefined in Core and defines S" 's in the
// File-Access word set; what ." does while interpreting is aforth's own, and
// docs/system/output.md says so.

// Copy the string at x0, x1 bytes long, into the next transient buffer, and
// return where it went in x0 with the length still in x1.
//
// The buffers are taken in turn, so strings made one after another do not
// overwrite each other. Forth-2012 11.3.4 asks for at least two; aforth has
// SBUF_COUNT of them, and machine.h says why that is four.
//
// A buffer is as large as the input buffer and the string was parsed out of
// that, so the copy always fits. machine.h checks the two sizes against each
// other at assembly time, which is why nothing is tested here.
        .p2align        2
sbuf_take:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        ldr     x2, [UP, #UV_SBUF_NEXT]
        stp     x2, x1, [sp, #16]       // where it goes and how long, across
                                        // the call
        add     x3, x2, #SBUF_EACH      // the buffer after it
        ldr     x4, [UP, #UV_SBUF]
        add     x5, x4, #SBUF_SIZE      // one past the last one
        cmp     x3, x5
        csel    x3, x4, x3, hs          // round robin
        str     x3, [UP, #UV_SBUF_NEXT]

        mov     x2, x1                  // how many
        mov     x1, x0                  // from
        ldr     x0, [sp, #16]           // to
        bl      CSYM(memcpy)
        ldp     x0, x1, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// Compile the string at x0, x1 bytes long as inline data: (S")'s token, the
// count, the bytes, and zeroes up to the next cell.
//
// Returns 0, or ERR_DICT_FULL having written nothing. The room for all of it
// is tested once, before any of it is written, which is what a run of
// dict_comma calls could not do. It reports rather than raises for the reason
// dict_comma does, and the words below turn the report into a raise.
//
// The pad is zeroed rather than left as it was, so that the same source builds
// the same bytes, which is what header_impl does with a name's pad.
        .p2align        2
dict_compile_string:
        ldr     x2, [UP, #UV_HERE]
        add     x3, x1, #7
        and     x3, x3, #-8             // the bytes, padded to a cell
        add     x3, x3, #16             // the token and the count
        add     x3, x2, x3              // where HERE ends up
        ldr     x4, [UP, #UV_DICT_END]
        cmp     x3, x4
        b.hi    1f

        mov     x4, #TOK_s_quote_run
        str     x4, [x2], #8
        str     x1, [x2], #8
        mov     x5, x0                  // the bytes
        mov     x6, x1                  // how many
2:      cbz     x6, 3f
        ldrb    w7, [x5], #1
        strb    w7, [x2], #1
        sub     x6, x6, #1
        b       2b
3:      cmp     x2, x3
        b.hs    4f
        strb    wzr, [x2], #1
        b       3b
4:      str     x3, [UP, #UV_HERE]
        mov     x0, #0
        ret

1:      mov     x0, #ERR_DICT_FULL
        ret

        DEFCODE "S\"", 2, s_quote, F_IMMEDIATE  // ( "ccc<quote>" -- c-addr u )
        mov     x0, #34                 // a double quote
        bl      parse_impl
        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, 1f

        ROOM    2
        bl      sbuf_take
        DPUSH   x0
        DPUSH   x1
        NEXT

1:      bl      dict_compile_string
        RAISE
        NEXT

// ." is S" and TYPE, both while compiling and while interpreting: the same
// bytes in the same place, and the one write TYPE already makes of them.
        DEFCODE ".\"", 2, dot_quote, F_IMMEDIATE        // ( "ccc<quote>" -- )
        mov     x0, #34                 // a double quote
        bl      parse_impl
        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, 1f

        cbz     x1, 2f                  // nothing to write
        bl      write_stdout
2:      NEXT

1:      bl      dict_compile_string
        RAISE
        mov     x0, #TOK_type
        bl      dict_comma
        RAISE
        NEXT
