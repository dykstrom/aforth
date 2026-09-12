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
// DOCOL, EXIT, EXECUTE and (STOP) stay here. They are the inner interpreter
// rather than words a program reaches for, and (STOP) belongs beside the
// aforth_enter it returns out of.
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

#include "words/stack.S"
#include "words/arithmetic.S"
#include "words/memory.S"
#include "words/output.S"
#include "words/input.S"
#include "words/parsing.S"
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
// One level only: the saved pointer is a single cell, so entering the machine
// again from inside it would lose the outer frame. Nothing does that yet.
//
// Returns 0 when the list ran to its end. A routine that unwinds the machine
// early goes through enter_return with its own value in x0, which is how
// machine_quit learns what failed and how ABORT and QUIT leave without
// returning to the word that ran them.
        .p2align        2
        .globl  aforth_enter
        FUNC_TYPE(aforth_enter)
aforth_enter:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x1, sp
        str     x1, [UP, #UV_STOP_SP]
        mov     IP, x0
        NEXT
        FUNC_SIZE(aforth_enter)

// Leave the machine, returning x0 as aforth_enter's result. The C stack
// pointer goes back to the frame aforth_enter built, whatever the words did
// with sp in between.
        .p2align        2
        .globl  enter_return
enter_return:
        ldr     x9, [UP, #UV_STOP_SP]
        mov     sp, x9
        ldp     x29, x30, [sp], #16
        ret

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

// Run REFILL, for the same reason: TOK_refill is a symbol of this file's.
// The flag it leaves is on the data stack, where the caller reads it.
        .p2align        2
        .globl  machine_refill
        FUNC_TYPE(machine_refill)
machine_refill:
        mov     x0, #TOK_refill
        b       machine_execute
        FUNC_SIZE(machine_refill)
