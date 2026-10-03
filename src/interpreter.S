// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The inner interpreter and the built-in dictionary.
//
// The dictionary is assembled here as an image and copied into the region at
// start-up, and the table that turns a code field's index into an address is
// filled at start-up too. The entry format and the macros used below are in
// src/include/dict.h.
//
// Every built-in word is in this one translation unit, because a link and a
// token are offsets into this one image and only the assembler building it can
// work them out. The words themselves are in src/words/, one file per kind,
// pulled in below with #include rather than assembled separately. Include order
// is definition order: a file may only use tokens from a file above it.
//
// DOCOL, EXIT, EXECUTE, (STOP), (LIT), (BRANCH), (0BRANCH), (DO), (LOOP),
// (+LOOP), (?DO), (S"), (ABORT"), (DOES>), (TO) and (DEFER) stay here, with
// the code fields DOCON, DOVAR, DODOES, DODEFER and DOMARKER. They are the
// inner interpreter rather than words a program reaches for, and (STOP)
// belongs beside the aforth_enter it returns out of. (STOP) and the twelve
// words after it are hidden: each of the twelve is the run-time half of a word
// the programmer writes, reading the list it is running or leaving a frame on
// the return stack for its other half, so a programmer who typed one would
// push, jump, print, store, strand a pair of cells or rewrite the newest word
// by whatever came next.
//
// machine_execute and machine_refill at the bottom are what the outer
// interpreter in src/outer.S calls to get into the machine. They live here
// because the tokens they need are symbols only this assembler pass has.

#include "dict.h"

        DICT_BEGIN


// DOCOL: run a list of tokens.
//
// The code field of every colon definition holds this routine's index, so
// dispatch arrives here with W on the code field and the token list starting
// one cell above it. Not a word, so it has no name and no entry.
        CODE    docol                   // ( -- ) ( R: -- nest-sys )
        RROOM   1
        RPUSH   IP                      // where to carry on afterwards
        add     IP, W, #8               // the parameter field
        NEXT

// EXIT: leave the definition being run and carry on in the caller.
        DEFCODE "EXIT", 4, exit         // ( -- ) ( R: nest-sys -- )
        RNEED   1
        RPOP    IP
        NEXT

// DOCON: push the cell in the parameter field. The code field of a word made
// by CONSTANT, and not a word itself, so it has no entry either.
        CODE    docon                   // ( -- x )
        ROOM    1
        ldr     x0, [W, #8]
        DPUSH   x0
        NEXT

// DOVAR: push the address of the parameter field. The code field of a word
// made by CREATE, and so of one made by VARIABLE, which is CREATE and a cell.
        CODE    dovar                   // ( -- a-addr )
        ROOM    1
        add     x0, W, #8
        DPUSH   x0
        NEXT

// DODOES: push the address of the parameter field, as DOVAR does, then run the
// token list the does-cell names, as DOCOL runs the one in the parameter
// field. The code field of a word made by CREATE and given its behaviour by
// DOES>; (DOES>) below is what points an entry here.
//
// The does-cell holds an offset from DBASE rather than an address, so a word
// made this way is as relocatable as the rest of the dictionary (ADR 0005).
        CODE    dodoes                  // ( -- a-addr ) ( R: -- nest-sys )
        ROOM    1
        RROOM   1
        add     x0, W, #8
        DPUSH   x0
        RPUSH   IP                      // where to carry on afterwards
        ldr     x0, [W, #CF_DOES]
        add     IP, DBASE, x0           // the does-part
        NEXT

// DODEFER: run the word whose token is in the parameter field. The code field
// of a word made by DEFER. It is EXECUTE with the token read from the body
// instead of the stack, so a deferred word costs one dispatch more than the
// word it runs and no stack or return stack at all.
        CODE    dodefer                 // ( i*x -- j*x )
        ldr     x0, [W, #8]
        add     W, DBASE, x0
        DISPATCH

// DOMARKER: put HERE and LATEST back to what the parameter field says they
// were, which takes the word and every word after it out of the dictionary.
// The code field of a word made by MARKER. Both cells are offsets from DBASE,
// so a marker is as relocatable as the rest of the dictionary (ADR 0005).
        CODE    domarker                // ( -- )
        ldr     x0, [W, #8]
        add     x0, DBASE, x0
        str     x0, [UP, #UV_HERE]
        ldr     x0, [W, #16]
        str     x0, [UP, #UV_LATEST]
        NEXT

// EXECUTE: run the word whose token is on the data stack.
//
// A token is an offset, so it needs DBASE added before it names anything. That
// is the whole difference between this and NEXT, which reads its token from
// the list instead of the stack.
        DEFCODE "EXECUTE", 7, execute   // ( i*x xt -- j*x )
        NEED    1
        DPOP    W
        add     W, DBASE, W
        DISPATCH

// (STOP): leave the Forth machine and return to whoever called aforth_enter.
//
// Hidden, so name lookup will not find it: a programmer who compiled it into a
// definition would unwind the outer interpreter from under it. Ends by
// returning rather than with NEXT, which is what makes it the end of a token
// list. Every list the outer interpreter runs ends with this token.
        DEFCODE "(STOP)", 6, stop, F_HIDDEN     // ( -- )
        mov     x0, #0                  // the machine ran to the end
        b       enter_return

// (LIT): push the cell that follows this token in the list, and step over it.
//
// What LITERAL compiles, and what the outer interpreter compiles for a number
// typed while compiling. Hidden, so name lookup will not find it: run on its
// own it would push whatever token came next and then skip that word.
        DEFCODE "(LIT)", 5, lit, F_HIDDEN       // ( -- x )
        ROOM    1
        ldr     x0, [IP], #8
        DPUSH   x0
        NEXT

// (BRANCH): jump by the distance that follows this token in the list.
//
// The distance is a count of cells, not an address, so a definition holding
// one is still valid wherever the dictionary lands (ADR 0005). It is counted
// from the token after the distance itself, so 0 means carry straight on and a
// negative number jumps back.
//
// Hidden, as (LIT) is. The words that compile it are in src/words/control.S.
        DEFCODE "(BRANCH)", 8, branch, F_HIDDEN         // ( -- )
        ldr     x0, [IP], #8
        add     IP, IP, x0, lsl #3
        NEXT

// (0BRANCH): the same jump, but only when the flag on the stack is false.
        DEFCODE "(0BRANCH)", 9, zero_branch, F_HIDDEN   // ( x -- )
        NEED    1
        mov     x1, TOS
        DPOPM
        ldr     x0, [IP], #8
        cbnz    x1, 1f
        add     IP, IP, x0, lsl #3
1:      NEXT

// (DO): take a loop's limit and starting index off the data stack and put them
// on the return stack, where I, J and (LOOP) read them.
//
// The index goes on top, because I and (LOOP) read it far more often than
// anything reads the limit. The frame is two cells and no more, which is what
// UNLOOP drops and what a definition leaving from inside a loop has to put
// back before EXIT finds the address DOCOL saved.
//
// Sharing the return stack is what makes a loop cost no area of its own, and
// it is also why J reaches the frame below this one only while both loops are
// in the same definition: a call puts DOCOL's saved address between them. See
// docs/system/control-flow.md.
//
// Hidden, as (LIT) is. Run on its own it would park two cells on the return
// stack that nothing would ever drop.
        DEFCODE "(DO)", 4, do_run, F_HIDDEN     // ( limit index -- ) ( R: -- limit index )
        NEED    2
        RROOM   2
        DGETM   0, x0                   // the limit, under the index
        RPUSH   x0
        RPUSH   TOS                     // the index, on top
        DPOPM
        DPOPM
        NEXT

// (LOOP): add one to the index, and go back to the start of the loop unless
// the index has reached the limit.
//
// The distance follows this token in the list and is applied the way (BRANCH)
// applies its own: a count of cells rather than an address, so a definition
// holding a loop is as relocatable as one without (ADR 0005).
//
// The test is for equality, which is what Forth-2012 asks for. A loop whose
// limit is its starting index therefore does not run no times: 0 0 DO LOOP
// counts the whole cell range before the index meets 0 again. ?DO is the
// standard's word for the other reading, and aforth has not got it yet.
//
// The turn that ends the loop drops both parameters, so a loop that runs out
// needs no UNLOOP after it. That turn leaves the index unstored, because
// nothing reads it again.
        DEFCODE "(LOOP)", 6, loop_run, F_HIDDEN // ( -- ) ( R: limit index -- limit index | )
        RNEED   2
        ldr     x0, [IP], #8            // the distance
        RGET    0, x1                   // the index
        add     x1, x1, #1
        RGET    1, x2                   // the limit
        cmp     x1, x2
        b.eq    1f
        RSET    0, x1
        add     IP, IP, x0, lsl #3      // round again
        NEXT
1:      RDROP   2                       // the loop is done with its parameters
        NEXT

// (+LOOP): add the step on the data stack to the index, and go back to the
// start of the loop unless the index crossed the limit.
//
// Forth-2012 puts the end of the loop at the boundary between the limit minus
// one and the limit, and asks whether the step carried the index over it. The
// test below asks the same question the other way round: it subtracts the
// limit from the index before and after the step, and ends the loop when those
// two differ in sign. That is what makes a negative step count down to the
// limit and stop on it, where the equality (LOOP) tests for would run past it.
//
// A step of one behaves as (LOOP) does, so LOOP could have compiled this word
// and does not: (LOOP) reaches its own answer in two instructions fewer.
        DEFCODE "(+LOOP)", 7, plus_loop_run, F_HIDDEN   // ( n -- ) ( R: limit index -- limit index | )
        NEED    1
        RNEED   2
        ldr     x0, [IP], #8            // the distance
        RGET    0, x1                   // the index
        RGET    1, x2                   // the limit
        sub     x3, x1, x2              // index - limit, before the step
        add     x1, x1, TOS             // the new index
        DPOPM
        sub     x4, x1, x2              // index - limit, after it
        eor     x3, x3, x4              // the sign bit differs iff it crossed
        tbnz    x3, #63, 1f
        RSET    0, x1
        add     IP, IP, x0, lsl #3      // round again
        NEXT
1:      RDROP   2                       // the loop is done with its parameters
        NEXT

// (?DO): start a counted loop, unless the range is empty.
//
// (DO) counts from its starting index until the index meets the limit, so a
// range of no width counts the whole cell range instead of nothing. This word
// is the standard's answer to that: equal limit and index means the loop runs
// no times, and the distance that follows the token carries it past the whole
// loop.
//
// That distance is written by the LOOP or +LOOP that closes the loop, and not
// by ?DO itself, because where the loop ends is not known until then. ?DO
// leaves the cell on the same list of unresolved branches LEAVE uses, since
// both land in the same place. See docs/system/control-flow.md.
        DEFCODE "(?DO)", 5, q_do_run, F_HIDDEN  // ( limit index -- ) ( R: -- limit index | )
        NEED    2
        RROOM   2
        ldr     x0, [IP], #8            // the distance past the loop
        DGETM   0, x1                   // the limit
        cmp     TOS, x1
        b.eq    1f
        RPUSH   x1
        RPUSH   TOS                     // the index, on top, as (DO) leaves it
        DPOPM
        DPOPM
        NEXT
1:      DPOPM
        DPOPM
        add     IP, IP, x0, lsl #3      // the range is empty: skip the loop
        NEXT

// (S"): push the string that follows this token in the list, and step over it.
//
// The third shape of inline data and the first that is not one cell: a count,
// then that many bytes, then padding to the next cell. The count is read the
// way (LIT) reads its cell, and the padding is what keeps a definition holding
// a string one unbroken run of cells — so a branch measured over one is still
// a whole number of cells, and nothing in src/words/control.S changes.
//
// What both S" and ." compile; ." compiles TYPE's token after it. Hidden, as
// (LIT) is, and for the same reason: run on its own it would push whatever
// token came next as an address and a length.
        DEFCODE "(S\")", 4, s_quote_run, F_HIDDEN      // ( -- c-addr u )
        ROOM    2
        ldr     x0, [IP], #8            // the count
        mov     x1, IP                  // the bytes, where the list stands
        add     x2, x0, #7
        and     x2, x2, #-8
        add     IP, IP, x2              // past them, on the next cell
        DPUSH   x1
        DPUSH   x0
        NEXT

// (ABORT"): abort with the message under it when the flag under that is true.
//
// What ABORT" compiles, after the (S") that pushes the message. A false flag
// drops all three and the definition carries on. A true one leaves the machine
// the way ABORT does, and the message goes in the user area for quit_report to
// print. It lies inside the definition, which the unwind leaves alone, so it
// needs no reporting early.
//
// Hidden, as (S") is. Run on its own it would read a string nobody laid down.
        DEFCODE "(ABORT\")", 8, abort_quote_run, F_HIDDEN     // ( x c-addr u -- )
        NEED    3
        DPOP    x1                      // u
        DPOP    x0                      // c-addr
        DPOP    x2                      // x
        cbz     x2, 1f
        bl      err_name                // never returns, so x30 is free
        mov     x0, #ERR_ABORT_QUOTE
        b       machine_error
1:      NEXT

// (DOES>): give the newest word the behaviour that follows this token, and
// leave the definition that is running.
//
// What DOES> compiles. The tokens after it are the does-part: they do not run
// now, but every time the newest word runs. So this word writes where they
// start into that word's does-cell, as an offset from DBASE, and points its
// code field at DODOES. Then it does what EXIT does, because the rest of the
// list belongs to the word it just changed and not to the one running it.
//
// The newest word is whatever LATEST names, which is the word CREATE made in
// the usual defining word. Forth-2012 makes any other entry an ambiguous
// condition, and nothing here checks, as >BODY does not check its token.
//
// Hidden, as (LIT) is. Run on its own it would rewrite the newest word to run
// whatever list it was reached from.
        DEFCODE "(DOES>)", 7, does_run, F_HIDDEN        // ( -- ) ( R: nest-sys -- )
        RNEED   1
        ldr     x1, [UP, #UV_LATEST]
        add     x1, DBASE, x1
        ldrb    w2, [x1, #ENT_COUNT]
        CFOFF   x2, x2
        add     x1, x1, x2              // the newest word's code field
        sub     x0, IP, DBASE
        str     x0, [x1, #CF_DOES]      // the does-part, as an offset
        mov     x0, #XT_dodoes
        str     x0, [x1]
        RPOP    IP
        NEXT

// (TO): store the top of the stack in the body of the word whose token follows
// this one in the list, and step over it.
//
// What TO and IS compile. The token is an offset like any other, so a
// definition holding one is as relocatable as the rest (ADR 0005), where the
// body's address compiled as a literal would not be.
//
// Hidden, as (LIT) is. Run on its own it would store into the body of whatever
// token came next.
        DEFCODE "(TO)", 4, to_run, F_HIDDEN     // ( x -- )
        NEED    1
        ldr     x0, [IP], #8            // the word's token
        add     x0, DBASE, x0
        str     TOS, [x0, #8]           // its body
        DPOPM
        NEXT

// (DEFER): what a deferred word runs until IS gives it a word to run.
//
// DEFER stores this token in every word it makes, so running one early raises
// rather than running whatever its body happened to hold. The message cannot
// name the word: dispatch has already replaced its code field in W with this
// one's.
//
// Hidden, because nothing should run it by name. DEFER@ can still hand its
// token back.
        DEFCODE "(DEFER)", 7, defer_unset, F_HIDDEN     // ( -- )
        mov     x0, #ERR_DEFER_UNSET
        b       machine_error

#include "words/stack.S"
#include "words/arithmetic.S"
#include "words/memory.S"
#include "words/output.S"
#include "words/input.S"
#include "words/parsing.S"
#include "words/file.S"
#include "words/compile.S"
#include "words/control.S"
#include "words/quit.S"

        DICT_END

        .text

// Fill the index-to-address table.
//
// The only place in aforth where a real code address is written, and it is
// written again on every start-up. That is what lets a dictionary hold indices
// and stay valid in a process that loaded at a different address (ADR 0005).
//
// XTAB must already point at the table, so machine_init calls this after it
// has carved the region.
        .p2align        2
        .globl  machine_build_xtab
        FUNC_TYPE(machine_build_xtab)
machine_build_xtab:
        .irp    prim, AFORTH_PRIM_LIST
        adr_sym x1, prim_\prim
        str     x1, [XTAB, #(XT_\prim * 8)]
        .endr
        ret
        FUNC_SIZE(machine_build_xtab)

// Copy the built-in dictionary into the region, and point HERE past it and
// LATEST at its newest entry.
//
// A plain memcpy is the whole of it. The image holds offsets, indices and name
// bytes and nothing else, so there is nothing in it to fix up.
        .p2align        2
        .globl  machine_load_dictionary
        FUNC_TYPE(machine_load_dictionary)
machine_load_dictionary:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        mov     x0, DBASE
        adr_sym x1, dict_image
        mov     x2, #dict_image_size
        bl      CSYM(memcpy)

        mov     x1, #dict_image_size
        add     x1, DBASE, x1
        str     x1, [UP, #UV_HERE]

        mov     x1, #dict_latest
        str     x1, [UP, #UV_LATEST]

        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(machine_load_dictionary)

// Enter the Forth machine on the token list at x0, and return when a word runs
// (STOP).
//
// There is no ret at the end: NEXT branches into the first word and control
// stays inside the machine until (STOP) unwinds to this frame. The C stack
// pointer is saved because a word is free to leave sp wherever it likes as
// long as it is balanced, and (STOP) should not have to trust that.
//
// It nests. Each entry saves two things in its own frame: the pointer the entry
// below it left in UV_STOP_SP, so that one cell is really the top of a stack,
// and IP, because the entry below it is part of the way through a token list
// and this one is about to point IP at another. EVALUATE is what needs both: it
// interprets from inside a word, so it runs words through machine_execute while
// an aforth_enter of its caller's is still open, and the word after it in the
// definition has to run when it finishes. See docs/system/input.md.
//
// Nothing else is saved. The stacks are shared on purpose — EVALUATE's stack
// effect is i*x to j*x, so what the string does to the data stack is the point
// — and W is scratch that dispatch fills before anything reads it.
//
// Returns 0 when the list ran to its end. A routine that unwinds the machine
// early goes through enter_return with its own value in x0, which is how
// machine_quit learns what failed and how ABORT and QUIT leave without
// returning to the word that ran them. An error inside a nested entry unwinds
// to that entry and no further, and whoever called it decides whether to pass
// it on.
        .p2align        2
        .globl  aforth_enter
        FUNC_TYPE(aforth_enter)
aforth_enter:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        ldr     x1, [UP, #UV_STOP_SP]
        stp     x1, IP, [sp, #16]       // the entry below this one, and its IP
        mov     x1, sp
        str     x1, [UP, #UV_STOP_SP]
        mov     IP, x0
        NEXT
        FUNC_SIZE(aforth_enter)

// Leave the machine, returning x0 as aforth_enter's result. The C stack
// pointer goes back to the frame aforth_enter built, whatever the words did
// with sp in between, and UV_STOP_SP and IP go back to the entry below it.
        .p2align        2
        .globl  enter_return
        FUNC_TYPE(enter_return)
enter_return:
        ldr     x9, [UP, #UV_STOP_SP]
        mov     sp, x9
        ldp     x9, IP, [sp, #16]
        str     x9, [UP, #UV_STOP_SP]
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(enter_return)

// Run the word whose token is in x0, and return what aforth_enter returned: 0
// when the word finished, or the number of the error that unwound it.
//
// The list is built in this frame, because the token is only known at run
// time. A token list is cells of offsets and nothing else, so it may sit on
// the C stack as readily as in read-only memory, and it stays valid while the
// word runs: aforth_enter and everything it calls work below this frame.
//
// This lives here rather than in outer.S because TOK_stop is a symbol only the
// assembler building this file has.
        .p2align        2
        .globl  machine_execute
        FUNC_TYPE(machine_execute)
machine_execute:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        mov     x1, #TOK_stop
        stp     x0, x1, [sp, #16]
        add     x0, sp, #16
        bl      aforth_enter
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(machine_execute)

// Compile the cell in x0 as a literal: (LIT)'s token, then the cell itself.
//
// Returns 0, or ERR_DICT_FULL when the dictionary had no room, in which case
// the token may already be there and the cell is not. A half-written literal
// does not matter: the error unwinds to machine_quit, which abandons the
// definition being compiled along with the rest of the line.
//
// Here rather than in src/outer.S because TOK_lit is a symbol only the
// assembler building this file has, which is why machine_execute is here too.
        .p2align        2
        .globl  dict_compile_literal
        FUNC_TYPE(dict_compile_literal)
dict_compile_literal:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]           // the value, across the first call
        mov     x0, #TOK_lit
        bl      dict_comma
        cbnz    x0, 1f
        ldr     x0, [sp, #16]
        bl      dict_comma
1:      ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(dict_compile_literal)

// Run REFILL, for the same reason: TOK_refill is a symbol of this file's.
// The flag it leaves is on the data stack, where the caller reads it.
        .p2align        2
        .globl  machine_refill
        FUNC_TYPE(machine_refill)
machine_refill:
        mov     x0, #TOK_refill
        b       machine_execute
        FUNC_SIZE(machine_refill)
