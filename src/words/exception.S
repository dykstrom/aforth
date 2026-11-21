// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The Exception word set: CATCH and THROW.
//
// THROW raises its number the way every error is raised, through the vector in
// UV_ABORT and out of the nearest aforth_enter. CATCH runs its word through
// machine_execute, which is an aforth_enter of its own, so the raise stops
// there and CATCH reads the number as machine_execute's result. The error
// numbers are Forth-2012's THROW codes, so a stack underflow reaches CATCH as
// -4 and an undefined word as -13. See docs/system/outer-interpreter.md.
//
// ABORT and ABORT" are -1 and -2, as the Exception extensions say. They stay in
// quit.S and compile.S with the words they sit beside.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// CATCH: run xt, and push 0 if it finished or the code it threw if not.
//
// On a throw, the return stack and the data stack go back to where they were
// once xt was popped, and the code goes on top. Forth-2012 restores the depth,
// not the items: an item the thrown-from code changed in place keeps its new
// value. So the cached top stays when the depth already matches, and is
// reloaded from memory otherwise, from the cell DPUSHM would have spilled it to.
//
// The two stack pointers are kept on the C stack, because the word that runs
// may use x27 and x28. aforth_enter puts IP back, so CATCH carries on with the
// word after it.
//
// UV_CATCH_DEPTH counts the frames open, which tells include_impl to report
// nothing and pass the number up instead.
//
// QUIT is not caught. It empties the return stack, and Forth-2012 keeps a
// CATCH frame there, so it raises again to the loop. -56 THROW is QUIT's code
// and goes the same way.
        DEFCODE "CATCH", 5, catch       // ( i*x xt -- j*x 0 | i*x n )
        NEED    1
        DPOP    x0
        stp     DSP, RSP, [sp, #-16]!
        ldr     x1, [UP, #UV_CATCH_DEPTH]
        add     x1, x1, #1
        str     x1, [UP, #UV_CATCH_DEPTH]
        bl      machine_execute
        ldr     x1, [UP, #UV_CATCH_DEPTH]
        sub     x1, x1, #1
        str     x1, [UP, #UV_CATCH_DEPTH]
        ldp     x2, x3, [sp], #16
        cbz     x0, 2f
        cmp     x0, #ERR_QUIT
        b.eq    3f

        mov     RSP, x3
        cmp     DSP, x2
        b.eq    1f
        mov     DSP, x2
        ldr     TOS, [DSP, #-8]
1:      DPUSH   x0                      // the depth is below xt's, so it fits
        NEXT

2:      ROOM    1
        DPUSH   xzr
        NEXT

3:      b       machine_error

// THROW: do nothing for 0, and raise anything else.
//
// The name an earlier error named is cleared first. A program's -13 THROW
// would print it otherwise, and a -2 THROW would print an old ABORT" message.
        DEFCODE "THROW", 5, throw       // ( k*x n -- k*x | i*x n )
        NEED    1
        DPOP    x0
        cbnz    x0, 1f
        NEXT
1:      str     xzr, [UP, #UV_ERR_LEN]
        b       machine_error
