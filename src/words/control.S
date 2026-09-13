// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Control flow inside a definition.
//
// Every word here is immediate and compiles a branch. The two branch
// primitives themselves, (BRANCH) and (0BRANCH), are in src/interpreter.S with
// the rest of the inner interpreter; each takes a distance in cells from the
// list it is running, never an address, so a definition that branches is as
// relocatable as one that does not (ADR 0005).
//
// The control-flow stack is the data stack, which Forth-2012 allows. An item
// on it is the address of a cell in the dictionary: where a forward branch's
// distance has still to be written, or where a backward branch is to land.
// That is an address rather than an offset because it never leaves the data
// stack and never reaches the dictionary.
//
// Sharing the data stack means a plain number looks exactly like a place to
// branch to, so cf_check tests every one before anything writes through it.
// Without it `2 THEN` would store through address 2 and kill the process.
//
// See docs/system/control-flow.md.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// Raise unless x0 is a place in the dictionary a branch could name: a cell
// boundary, at or after the dictionary base and no further than HERE. Leaves
// x0 alone, so a caller may check and then use it.
        .p2align        2
cf_check:
        ldr     x1, [UP, #UV_HERE]
        cmp     x0, x1
        b.hi    1f
        cmp     x0, DBASE
        b.lo    1f
        tst     x0, #7
        b.ne    1f
        ret
1:      mov     x0, #ERR_CONTROL_FLOW
        b       machine_error

// Compile the branch whose token is in x0, and a distance of 0 after it for
// cf_resolve to fill in later. Returns the address of that cell.
        .p2align        2
cf_forward:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        bl      dict_comma
        RAISE
        ldr     x0, [UP, #UV_HERE]      // where the distance goes
        str     x0, [sp, #16]
        mov     x0, #0
        bl      dict_comma
        RAISE
        ldr     x0, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// Compile the branch whose token is in x0, landing on the address in x1.
        .p2align        2
cf_backward:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x1, [sp, #16]           // where it lands, across the call
        bl      dict_comma
        RAISE
        ldr     x1, [sp, #16]
        ldr     x2, [UP, #UV_HERE]      // where the distance goes
        sub     x0, x1, x2
        sub     x0, x0, #8              // counted from the token after it
        asr     x0, x0, #3              // in cells
        bl      dict_comma
        RAISE
        ldp     x29, x30, [sp], #32
        ret

// Fill in the distance at x0 so that the branch lands on HERE.
        .p2align        2
cf_resolve:
        ldr     x1, [UP, #UV_HERE]
        sub     x2, x1, x0
        sub     x2, x2, #8
        asr     x2, x2, #3
        str     x2, [x0]
        ret

// IF compiles a branch taken when the flag is false, and leaves the place its
// distance has to be written. THEN writes it, so that a false flag lands on
// the token after THEN.
        DEFCODE "IF", 2, if, F_IMMEDIATE        // ( C: -- orig ) ( x -- )
        ROOM    1
        mov     x0, #TOK_zero_branch
        bl      cf_forward
        DPUSH   x0
        NEXT

        DEFCODE "THEN", 4, then, F_IMMEDIATE    // ( C: orig -- )
        NEED    1
        mov     x0, TOS
        bl      cf_check
        bl      cf_resolve
        DPOPM
        NEXT

// ELSE ends the true half with a branch over the false half, and points IF's
// branch at what follows it. The place to write is swapped for the new one.
        DEFCODE "ELSE", 4, else, F_IMMEDIATE    // ( C: orig1 -- orig2 )
        NEED    1
        mov     x0, TOS
        bl      cf_check                // before anything is written
        mov     x0, #TOK_branch
        bl      cf_forward
        mov     x27, x0                 // the new place, across the resolve
        mov     x0, TOS
        bl      cf_resolve
        mov     TOS, x27
        NEXT

// BEGIN marks where a backward branch lands. Nothing is compiled.
        DEFCODE "BEGIN", 5, begin, F_IMMEDIATE  // ( C: -- dest )
        ROOM    1
        ldr     x0, [UP, #UV_HERE]
        DPUSH   x0
        NEXT

        DEFCODE "UNTIL", 5, until, F_IMMEDIATE  // ( C: dest -- ) ( x -- )
        NEED    1
        mov     x0, TOS
        bl      cf_check
        mov     x1, TOS
        mov     x0, #TOK_zero_branch
        bl      cf_backward
        DPOPM
        NEXT

        DEFCODE "AGAIN", 5, again, F_IMMEDIATE  // ( C: dest -- )
        NEED    1
        mov     x0, TOS
        bl      cf_check
        mov     x1, TOS
        mov     x0, #TOK_branch
        bl      cf_backward
        DPOPM
        NEXT

// WHILE compiles the test's branch out of the loop and tucks the place to
// write it under BEGIN's, so that REPEAT finds them in the order it wants.
        DEFCODE "WHILE", 5, while, F_IMMEDIATE  // ( C: dest -- orig dest )
        NEED    1
        ROOM    1
        mov     x0, #TOK_zero_branch
        bl      cf_forward
        DPUSH   x0
        DGETM   0, x1                   // dest, under the new place
        DSETM   0, TOS
        mov     TOS, x1
        NEXT

// REPEAT closes the loop and then points WHILE's branch past it.
        DEFCODE "REPEAT", 6, repeat, F_IMMEDIATE        // ( C: orig dest -- )
        NEED    2
        mov     x0, TOS
        bl      cf_check
        DGETM   0, x0
        bl      cf_check                // both, before anything is written
        mov     x1, TOS
        mov     x0, #TOK_branch
        bl      cf_backward
        DGETM   0, x0
        bl      cf_resolve
        DPOPM
        DPOPM
        NEXT

// RECURSE compiles the definition being written, which its own name cannot
// reach: : hides the entry until ; unhides it, so that a name inside a
// definition means the word that was there before.
//
// The code field follows the name, padded to a cell. That is the arithmetic
// the HEADER macro does at assembly time and dict_find does at df_found, done
// here a third time on the entry LATEST names.
        DEFCODE "RECURSE", 7, recurse, F_IMMEDIATE      // ( C: -- )
        ldr     x1, [UP, #UV_LATEST]
        add     x2, DBASE, x1
        ldrb    w3, [x2, #ENT_COUNT]
        add     x3, x3, #(ENT_NAME + 7)
        and     x3, x3, #-8
        add     x0, x1, x3              // the code field's offset: the xt
        bl      dict_comma
        RAISE
        NEXT
