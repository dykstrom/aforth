// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The outer interpreter's own words. The loop itself is machine_quit in
// src/outer.S; see docs/system/outer-interpreter.md.
//
// Three of the four leave the machine rather than return to the word that ran
// them, and they do it the way an error does: through the vector in UV_ABORT,
// carrying a number machine_quit reads. One path out, so there is no second
// one to keep in step.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// STATE is a user variable like BASE: the word pushes the address of the cell
// and @ and ! do the rest. Only ticket 010 makes anything write it; the
// interpreter reads it from there on.
        DEFCODE "STATE", 5, state       // ( -- a-addr )
        ROOM    1
        add     x0, UP, #UV_STATE
        DPUSH   x0
        NEXT

// ABORT empties the data stack and starts over. machine_quit does the
// emptying, which is where the stacks are emptied for a reported error too.
        DEFCODE "ABORT", 5, abort       // ( i*x -- )
        mov     x0, #ERR_ABORT
        b       machine_error

// QUIT empties the return stack and reads the next line, leaving the data
// stack as it found it.
        DEFCODE "QUIT", 4, quit         // ( -- ) ( R: i*x -- )
        mov     x0, #ERR_QUIT
        b       machine_error

// BYE ends the process. exit flushes the stdio buffer libedit prints its own
// output through; aforth's has nothing in it, every byte having gone out
// through write already.
        DEFCODE "BYE", 3, bye           // ( -- )
        mov     w0, #0
        bl      CSYM(exit)
