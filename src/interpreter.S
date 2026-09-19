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
// DOCOL, EXIT, EXECUTE, (STOP), (LIT), (BRANCH), (0BRANCH) and (S") stay here.
// They are the inner interpreter rather than words a program reaches for, and
// (STOP) belongs beside the aforth_enter it returns out of. The last four are
// hidden: each reads something out of the list it is running, so a programmer
// who typed one would push, jump or print by whatever came next.
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
