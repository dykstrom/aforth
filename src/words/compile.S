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
// header_build is the same without the two checks on the name. :NONAME calls it
// with a length of 0, which is the one entry that has no name on purpose.
//
// The layout is HEADER's: link, flags, count, the name, pad to a cell, the
// does-cell, then the code field. The pad is zeroed so that the same source
// builds the same bytes. The loop that zeroes it runs up to the code field, so
// it zeroes the does-cell too, which is what every word but a DOES> word
// holds there.
        .p2align        2
header_impl:
        cbz     x1, hi_no_name
        cmp     x1, #255
        b.hi    hi_too_long
header_build:
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
//
// An entry with no name is one :NONAME made, and it stays hidden, so that
// neither FIND with an empty string nor WORDS ever reaches it.
        DEFCODE ";", 1, semicolon, F_IMMEDIATE  // ( C: colon-sys -- )
        mov     x0, #TOK_exit
        bl      dict_comma
        RAISE
        ldr     x1, [UP, #UV_LATEST]
        add     x1, DBASE, x1
        ldrb    w3, [x1, #ENT_COUNT]
        cbz     w3, 1f
        ldrb    w2, [x1, #ENT_FLAGS]
        bic     w2, w2, #F_HIDDEN
        strb    w2, [x1, #ENT_FLAGS]
1:      str     xzr, [UP, #UV_STATE]
        NEXT

// :NONAME is : without the name. It builds the same hidden entry with a name
// of no bytes, pushes the execution token, and sets STATE.
//
// The entry is in the chain like any other, so RECURSE finds it through LATEST
// as it finds a named definition, and an error part way through abandons it the
// same way. The token is pushed before anything is compiled, so it sits under
// whatever the control-flow words leave on the stack while the body is written.
        DEFCODE ":NONAME", 7, colon_noname      // ( C: -- colon-sys ) ( S: -- xt )
        ROOM    1
        mov     x1, #0                  // no name
        mov     x2, #XT_docol
        mov     x3, #F_HIDDEN
        bl      header_build
        ldr     x0, [UP, #UV_HERE]
        sub     x0, x0, DBASE
        sub     x0, x0, #8              // the code field, the cell below HERE
        DPUSH   x0
        mov     x0, #-1
        str     x0, [UP, #UV_STATE]
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
//
// CHAR is in lib/aforth.f, and [CHAR] could be CHAR POSTPONE LITERAL there. It
// is written here instead because it raises ERR_NO_NAME when the line holds no
// name, which a word written in Forth cannot do until aforth has THROW.
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

// VALUE is CONSTANT under a second name. A value pushes the cell in its body as
// a constant does, and TO is what tells the two apart: it stores into that
// cell. Forth-2012 makes TO on a constant an ambiguous condition, and aforth
// lets it happen.
        DEFALIAS "VALUE", 5, value, constant    // ( x "<spaces>name" -- )

// TO stores into the body of the word it names: at once while interpreting,
// and through (TO) when the definition being compiled runs.
//
// It compiles the word's token after (TO) rather than its body's address as a
// literal, because the address is absolute and the token is an offset (ADR
// 0005). Nothing checks that the word is a value, as >BODY does not check its
// token either.
//
// The parse and the search are ' in src/words/parsing.S, and a name that is not
// there raises as it does there.
        DEFCODE "TO", 2, to, F_IMMEDIATE        // ( x "<spaces>name" -- )
        bl      parse_name_impl
        mov     x27, x0
        mov     x28, x1
        cbz     x1, 2f                  // nothing left on the line
        bl      dict_find
        cbz     x0, 2f
        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, 1f

        NEED    1
        add     x0, DBASE, x0
        str     TOS, [x0, #8]           // the body
        DPOPM
        NEXT

1:      mov     x27, x0                 // the token, across the call
        mov     x0, #TOK_to_run
        bl      dict_comma
        RAISE
        mov     x0, x27
        bl      dict_comma
        RAISE
        NEXT
2:      mov     x0, x27
        mov     x1, x28
        b       undefined_word

// DEFER builds an entry whose code field is DODEFER and whose body is the token
// of the word it runs. That starts as (DEFER), which raises, so a deferred word
// run before IS has given it a word says so rather than running a stray cell.
        DEFCODE "DEFER", 5, defer       // ( "<spaces>name" -- )
        bl      parse_name_impl
        mov     x2, #XT_dodefer
        mov     x3, #0
        bl      header_impl
        mov     x0, #TOK_defer_unset
        bl      dict_comma
        RAISE
        NEXT

// IS is TO under a second name. A deferred word keeps the token it runs in its
// body, as a value keeps its value, so setting one is the same store.
// DEFER! and DEFER@, which reach the same cell from a token, are in
// lib/aforth.f.
        DEFALIAS "IS", 2, is, to, F_IMMEDIATE   // ( xt "<spaces>name" -- )

// MARKER builds a word that takes itself and everything defined after it back
// out of the dictionary, by putting HERE and LATEST back to what they were
// before MARKER ran.
//
// The body holds those two, both as offsets from DBASE, and DOMARKER in
// src/interpreter.S restores them. They are read before the entry is built, so
// the marker removes its own entry too, and they are kept in x27 and x28
// because header_impl uses everything below them.
//
// Nothing else is put back. The rest of what the dictionary holds is in the
// dictionary itself, and aforth has no search order to restore. A deferred word
// or a value older than the marker that holds a token of a word it removes is
// left pointing at space the next definition will reuse, which Forth-2012
// leaves ambiguous.
        DEFCODE "MARKER", 6, marker     // ( "<spaces>name" -- )
        ldr     x27, [UP, #UV_HERE]
        sub     x27, x27, DBASE
        ldr     x28, [UP, #UV_LATEST]
        bl      parse_name_impl
        mov     x2, #XT_domarker
        mov     x3, #0
        bl      header_impl
        mov     x0, x27
        bl      dict_comma
        RAISE
        mov     x0, x28
        bl      dict_comma
        RAISE
        NEXT

// The two string literals, and ABORT", which lays its message down the same
// way.
//
// All three are immediate and all three parse with a double quote as the
// delimiter, starting where >IN stands. parse_name_impl has already left it
// just past the one space that ended the word's own name, so S" ccc" takes ccc,
// and a delimiter that comes straight away gives the empty string.
//
// A string whose delimiter never comes takes the rest of the line and raises
// nothing. That is the choice ( makes, for the reason ( gives: the only line
// aforth could read a delimiter from is the terminal's, and waiting there for
// a quote the user does not know it wants is a trap.
//
// While compiling, each lays the bytes inside the definition through
// dict_compile_string below. While interpreting, S" copies them into a
// transient buffer, ." writes them straight out, and ABORT" leaves them where
// they were parsed. Forth-2012 leaves the interpretation semantics of all
// three undefined in Core and defines S" 's in the File-Access word set; what
// ." and ABORT" do while interpreting is aforth's own, and
// docs/system/output.md says so for .".

// Copy the string at x0, x1 bytes long, into the next transient buffer, and
// return where it went in x0 with the length still in x1.
//
// The buffers are taken in turn, so strings made one after another do not
// overwrite each other. Forth-2012 11.3.4 asks for at least two; aforth has
// SBUF_COUNT of them, and machine.h says why that is four.
//
// The caller has checked that the string fits. A buffer is as large as the
// input buffer, so one parsed from a line always does, but one parsed from a
// string EVALUATE runs need not.
        .p2align        2
sbuf_take:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        bl      sbuf_next
        stp     x2, x1, [sp, #16]       // where it goes and how long, across
                                        // the call
        mov     x2, x1                  // how many
        mov     x1, x0                  // from
        ldr     x0, [sp, #16]           // to
        bl      CSYM(memcpy)
        ldp     x0, x1, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// Take the next transient buffer, returning it in x2. Only x2 to x5 change, so
// a caller's x0 and x1 survive it.
        .p2align        2
sbuf_next:
        ldr     x2, [UP, #UV_SBUF_NEXT]
        add     x3, x2, #SBUF_EACH      // the buffer after it
        ldr     x4, [UP, #UV_SBUF]
        add     x5, x4, #SBUF_SIZE      // one past the last one
        cmp     x3, x5
        csel    x3, x4, x3, hs          // round robin
        str     x3, [UP, #UV_SBUF_NEXT]
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
        cmp     x1, #SBUF_EACH
        b.hi    2f                      // only EVALUATE's source is this long
        bl      sbuf_take
        DPUSH   x0
        DPUSH   x1
        NEXT
2:      mov     x0, #ERR_LINE_TOO_LONG
        b       machine_error

1:      bl      dict_compile_string
        RAISE
        NEXT

// S-backslash-quote, below, is S" with escapes: a backslash and the character
// after it stand for one byte, or two for \m, and a quote after a backslash
// does not end the string. The escapes are Forth-2012's:
//
//   \a 7   \b 8   \e 27   \f 12   \l 10   \m 13 10   \n 10   \q 34
//   \r 13  \t 9   \v 11   \z 0    \\ 92  \x and two hex digits
//
// and a backslash before a double quote, which gives 34. The word's own name
// is spelled out here rather than written, because an escaped quote in a
// comment leaves some editors reading the rest of the file as a string; see
// docs/system/assembler.md.
//
// \n is a line feed, which is the newline on both platforms. The letters are
// lower case only, as the standard spells them; the hex digits may be either.
// Anything else after a backslash, and \x without two hex digits after it,
// is the character after the backslash as it stands. Forth-2012 leaves those
// ambiguous. A backslash at the end of the line is dropped, and a string with
// no closing quote takes the rest of the line, as S" does.
//
// No escape stands for more bytes than it takes to write, so the bytes never
// outgrow the source they came from. While interpreting they go into a transient
// buffer; a string longer than one can come only from EVALUATE, and raises
// ERR_LINE_TOO_LONG. While compiling they are written above HERE, where
// dict_compile_string then finds them already in place.

// One escape letter and the byte it stands for, applied to w5.
//
// The selects run one after another, so this relies on no byte an escape gives
// being a letter another escape starts with. None is: they are all control
// characters or a quote.
.macro  ESCAPE letter, byte
        cmp     w5, #\letter
        mov     w6, #\byte
        csel    w5, w6, w5, eq
.endm

// The value of the hex digit in \reg, left in \reg, or a branch to \bad when
// it is not one.
.macro  HEXDIGIT reg, tmp, bad
        sub     \tmp, \reg, #48         // '0'
        cmp     \tmp, #10
        b.lo    .Lhex_ok\@
        orr     \tmp, \reg, #0x20       // fold a letter to lower case
        sub     \tmp, \tmp, #97         // 'a'
        cmp     \tmp, #6
        b.hs    \bad
        add     \tmp, \tmp, #10
.Lhex_ok\@:
        mov     \reg, \tmp
.endm

// Parse a string with escapes from where >IN stands, and write what it stands
// for at x0, stopping short of x1. Returns how many bytes were written in x0,
// or -1 when they would have reached x1, and leaves >IN past the closing
// quote. x0 on entry is where the bytes start, and it does not change until
// the return.
        .p2align        2
escape_parse:
        mov     x8, x0                  // where the next byte goes
        ldr     x2, [UP, #UV_TIB]
        ldr     x3, [UP, #UV_TIB_LEN]
        ldr     x4, [UP, #UV_TO_IN]
ep_next:
        cmp     x4, x3
        b.hs    ep_done                 // no closing quote: the rest of the line
        ldrb    w5, [x2, x4]
        add     x4, x4, #1
        cmp     w5, #34                 // a double quote ends it
        b.eq    ep_done
        cmp     w5, #92                 // a backslash starts an escape
        b.ne    ep_put
        cmp     x4, x3
        b.hs    ep_done                 // a backslash that ends the line
        ldrb    w5, [x2, x4]
        add     x4, x4, #1
        cmp     w5, #109                // m
        b.eq    ep_crlf
        cmp     w5, #120                // x
        b.eq    ep_hex
        ESCAPE  97, 7                   // a
        ESCAPE  98, 8                   // b
        ESCAPE  101, 27                 // e
        ESCAPE  102, 12                 // f
        ESCAPE  108, 10                 // l
        ESCAPE  110, 10                 // n
        ESCAPE  113, 34                 // q
        ESCAPE  114, 13                 // r
        ESCAPE  116, 9                  // t
        ESCAPE  118, 11                 // v
        ESCAPE  122, 0                  // z
ep_put:
        cmp     x8, x1
        b.hs    ep_full
        strb    w5, [x8], #1
        b       ep_next

ep_crlf:
        mov     w5, #13
        cmp     x8, x1
        b.hs    ep_full
        strb    w5, [x8], #1
        mov     w5, #10
        b       ep_put

// Two hex digits make one byte. Fewer than two left on the line, or a
// character that is not one, and the x stands for itself.
ep_hex:
        add     x6, x4, #1
        cmp     x6, x3
        b.hs    ep_put
        add     x7, x2, x4
        ldrb    w6, [x7]
        HEXDIGIT w6, w9, ep_put
        ldrb    w7, [x7, #1]
        HEXDIGIT w7, w9, ep_put
        add     w5, w7, w6, lsl #4
        add     x4, x4, #2
        b       ep_put

ep_done:
        str     x4, [UP, #UV_TO_IN]
        sub     x0, x8, x0
        ret
ep_full:
        mov     x0, #-1
        ret

        DEFCODE "S\\\"", 3, s_backslash_quote, F_IMMEDIATE      // ( "ccc<quote>" -- c-addr u )
        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, 1f

        ROOM    2
        bl      sbuf_next
        mov     x27, x2                 // the buffer, across the parse
        mov     x0, x2
        add     x1, x2, #SBUF_EACH
        bl      escape_parse
        cmn     x0, #1
        b.eq    2f
        DPUSH   x27
        DPUSH   x0
        NEXT
2:      mov     x0, #ERR_LINE_TOO_LONG
        b       machine_error

1:      ldr     x0, [UP, #UV_HERE]
        add     x0, x0, #16             // past the token and the count
        mov     x27, x0
        ldr     x1, [UP, #UV_DICT_END]
        bl      escape_parse
        cmn     x0, #1
        b.eq    3f
        mov     x1, x0
        mov     x0, x27
        bl      dict_compile_string     // the bytes are there already
        RAISE
        NEXT
3:      mov     x0, #ERR_DICT_FULL
        b       machine_error

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

// ABORT" is S" and (ABORT") while compiling. While interpreting it does the
// same work at once: it pops the flag and, when the flag is true, leaves the
// machine with the message it parsed. That message points into the input
// buffer, as an undefined word's name does, and quit_report prints it before
// anything refills the buffer.
        DEFCODE "ABORT\"", 6, abort_quote, F_IMMEDIATE  // ( i*x x "ccc<quote>" -- | i*x )
        mov     x0, #34                 // a double quote
        bl      parse_impl
        ldr     x2, [UP, #UV_STATE]
        cbnz    x2, 1f

        NEED    1
        DPOP    x2                      // x
        cbz     x2, 2f
        bl      err_name                // never returns, so x30 is free
        mov     x0, #ERR_ABORT_QUOTE
        b       machine_error
2:      NEXT

1:      bl      dict_compile_string
        RAISE
        mov     x0, #TOK_abort_quote_run
        bl      dict_comma
        RAISE
        NEXT

// COMPILE, appends an execution token to the definition being compiled. An
// execution token is a cell holding an offset from the dictionary base, and a
// token in a definition is that same cell, so appending one is what , does.
// COMPILE, is therefore , under a second name, and POSTPONE below compiles its
// token.
        DEFALIAS "COMPILE,", 8, compile_comma, comma    // ( xt -- )

// POSTPONE compiles the word it names into the definition being written, in
// whichever of the two ways that word needs.
//
// An immediate word is compiled as its own token, so it runs when the new word
// runs. Any other word cannot be: compiling its token would make the new word
// run it, where what the programmer asked for is a new word that compiles it.
// So the token is compiled as a literal with COMPILE, after it, and the new
// word appends it to whatever is being compiled when it runs. That is the
// code Forth-2012 describes POSTPONE appending.
//
// The parse, the search and the raise are ' in src/words/parsing.S, line for
// line: the name is kept in x27 and x28 because dict_find answers in x0 and x1
// and undefined_word wants the name back.
        DEFCODE "POSTPONE", 8, postpone, F_IMMEDIATE    // ( C: "<spaces>name" -- )
        bl      parse_name_impl
        mov     x27, x0
        mov     x28, x1
        cbz     x1, 1f                  // nothing left on the line
        bl      dict_find               // x0 the xt, x1 the flags
        cbz     x0, 1f
        tst     w1, #F_IMMEDIATE
        b.ne    2f
        bl      dict_compile_literal    // compile it when the new word runs
        RAISE
        mov     x0, #TOK_compile_comma
        bl      dict_comma
        RAISE
        NEXT
2:      bl      dict_comma              // run it when the new word runs
        RAISE
        NEXT
1:      mov     x0, x27
        mov     x1, x28
        b       undefined_word

// >BODY gives the address of the body of the word an execution token names.
//
// A token is an offset from the dictionary base and the body starts one cell
// after the code field, so this is the arithmetic DOVAR does, from a token
// rather than from the entry dispatch left in W.
//
// Nothing is checked but the depth. Forth-2012 makes a token that CREATE did
// not make an ambiguous condition, and @ does not check an address either.
        DEFCODE ">BODY", 5, to_body     // ( xt -- a-addr )
        NEED    1
        add     TOS, DBASE, TOS
        add     TOS, TOS, #8
        NEXT

// DOES> ends the part of a defining word that runs when the word defines, and
// starts the part the words it defines run.
//
// All it compiles is (DOES>)'s token. The rest of the definition compiles as
// it would anyway, up to ; and its EXIT, and that list is the does-part: when
// the defining word runs, (DOES>) in src/interpreter.S points the word CREATE
// has just made at it and leaves. See docs/system/compiling.md.
//
// Forth-2012 gives DOES> no interpretation semantics. Typed at the prompt it
// compiles the token at HERE all the same, as IF does.
        DEFCODE "DOES>", 5, does, F_IMMEDIATE   // ( C: colon-sys1 -- colon-sys2 )
        mov     x0, #TOK_does_run
        bl      dict_comma
        RAISE
        NEXT
