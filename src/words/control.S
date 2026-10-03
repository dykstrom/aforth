// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Control flow inside a definition.
//
// Most words here are immediate and compile a branch. I, J and UNLOOP are the
// exceptions: they run inside the loop rather than build it, and read or drop
// the frame a counted loop keeps on the return stack. The branch primitives
// themselves, (BRANCH), (0BRANCH) and (LOOP), are in src/interpreter.S with
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

// End a piece of code with a branch over what comes after it, and point the
// branch that skipped this piece at what follows. The place to write on the
// control-flow stack is swapped for the new one.
//
// ELSE does this between the two halves of an IF, and ENDOF at the end of a
// CASE arm. Forth-2012 defines ENDOF as ELSE, and this routine is the whole of
// both of them.
//
// Named the way header_impl and include_impl are, and not cf_else: the HEADER
// macro spells a word's code field cf_<label>, so cf_else is ELSE's own entry.
        .p2align        2
else_impl:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x0, TOS
        bl      cf_check                // before anything is written
        mov     x0, #TOK_branch
        bl      cf_forward
        mov     x27, x0                 // the new place, across the resolve
        mov     x0, TOS
        bl      cf_resolve
        mov     TOS, x27
        ldp     x29, x30, [sp], #16
        ret

// ELSE ends the true half with a branch over the false half, and points IF's
// branch at what follows it.
        DEFCODE "ELSE", 4, else, F_IMMEDIATE    // ( C: orig1 -- orig2 )
        NEED    1
        bl      else_impl
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
// definition means the word that was there before. So it reads LATEST and works
// out that entry's code field itself.
        DEFCODE "RECURSE", 7, recurse, F_IMMEDIATE      // ( C: -- )
        ldr     x1, [UP, #UV_LATEST]
        add     x2, DBASE, x1
        ldrb    w3, [x2, #ENT_COUNT]
        CFOFF   x3, x3
        add     x0, x1, x3              // the code field's offset: the xt
        bl      dict_comma
        RAISE
        NEXT

// The counted loop.
//
// DO, ?DO, LOOP and +LOOP are the compiling halves of (DO), (?DO), (LOOP) and
// (+LOOP) in src/interpreter.S, and they are shaped like BEGIN and UNTIL: DO
// leaves the place a turn of the loop starts, and LOOP compiles a backward
// distance to it. I, J and UNLOOP read and drop the frame (DO) leaves on the
// return stack, the limit underneath and the index on top.
//
// I reads the top cell of that stack, so a word called from a loop body reads
// the address DOCOL saved for it instead of the index, and J reads two cells
// further down, so it finds the loop outside this one only while both are in
// the same definition. Forth-2012 makes both ambiguous conditions, and aforth
// leaves them as ones. See docs/system/control-flow.md.

// The branches a loop has still to resolve.
//
// LEAVE compiles a branch that only the closing LOOP can point anywhere, and it
// may stand anywhere in the body. Its place to write therefore cannot wait on
// the control-flow stack: that stack is the data stack, and an IF between the
// LEAVE and the LOOP would take the wrong item off it — THEN would resolve the
// LEAVE and nothing would ever resolve the IF.
//
// So the places to write are a list, threaded through the very cells the
// distances go in. Each cell holds the offset of the cell before it until the
// closing word writes the real distance over it, so the list costs no memory of
// its own and nothing absolute is written into the dictionary (ADR 0005).
//
// UV_LEAVE is the head: -1 when no loop is being compiled, 0 in a loop with
// nothing on its list, and otherwise the offset of the newest cell. The first
// of those is what lets LEAVE refuse a definition with no loop in it, and
// machine_quit puts it back when an error abandons a definition.

// Start a loop's list, leaving the enclosing loop's head on the control-flow
// stack for the closing word to put back. A loop inside a loop therefore keeps
// a list of its own, and the LEAVEs of the two do not mix.
        .p2align        2
cf_leave_begin:
        ldr     x0, [UP, #UV_LEAVE]
        DPUSH   x0
        str     xzr, [UP, #UV_LEAVE]
        ret

// Compile the cell a forward branch's distance goes in, holding the cell
// before it, and make it the head of the list. Shaped like cf_forward, which
// does the same for a branch whose place to write goes on the control-flow
// stack instead.
        .p2align        2
cf_leave_add:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        ldr     x0, [UP, #UV_HERE]
        sub     x0, x0, DBASE           // this cell, as an offset
        str     x0, [sp, #16]
        ldr     x0, [UP, #UV_LEAVE]     // the cell before it, or 0
        bl      dict_comma
        RAISE
        ldr     x0, [sp, #16]
        str     x0, [UP, #UV_LEAVE]
        ldp     x29, x30, [sp], #32
        ret

// Point every branch on the list at HERE. Each cell's link comes out before
// cf_resolve writes the distance over it. Clobbers x27, which survives the
// calls; no word that uses this keeps anything there.
        .p2align        2
cf_leave_resolve:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        ldr     x27, [UP, #UV_LEAVE]
1:      cbz     x27, 2f
        add     x0, DBASE, x27
        ldr     x27, [x0]               // the cell before this one
        bl      cf_resolve
        b       1b
2:      ldp     x29, x30, [sp], #16
        ret

// Raise unless x0 is a head DO could have left: -1 for no loop, 0 for a loop
// with an empty list, or a cell in the dictionary. The last one is checked for
// the reason cf_check exists — the closing word writes through the list, and a
// plain number on the control-flow stack looks exactly like a head.
        .p2align        2
cf_leave_check:
        cmn     x0, #1
        b.eq    1f
        cbz     x0, 1f
        add     x0, DBASE, x0
        b       cf_check                // returns, or raises
1:      ret

// Close a counted loop with the token in x0: compile it and a distance back to
// the dest, point every branch on the list at what follows, and put the
// enclosing loop's list back. What LOOP and +LOOP share.
        .p2align        2
cf_loop_end:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]           // the token, across the checks
        mov     x0, TOS
        bl      cf_check                // the dest
        DGETM   0, x0
        bl      cf_leave_check          // and the head, before anything is written
        ldr     x0, [sp, #16]
        mov     x1, TOS
        bl      cf_backward
        bl      cf_leave_resolve
        DGETM   0, x0
        str     x0, [UP, #UV_LEAVE]     // the list of the loop outside this one
        ldp     x29, x30, [sp], #32
        ret

        DEFCODE "DO", 2, do, F_IMMEDIATE        // ( C: -- leave-sys dest ) ( limit index -- )
        ROOM    2
        mov     x0, #TOK_do_run
        bl      dict_comma
        RAISE
        bl      cf_leave_begin
        ldr     x0, [UP, #UV_HERE]      // where each turn of the loop starts
        DPUSH   x0
        NEXT

// ?DO compiles a branch past the whole loop and puts it on the list, because it
// lands exactly where a LEAVE lands: after the closing word. So the word that
// closes the loop resolves one list and does not have to know which branches on
// it came from where.
        DEFCODE "?DO", 3, q_do, F_IMMEDIATE     // ( C: -- leave-sys dest ) ( limit index -- )
        ROOM    2
        mov     x0, #TOK_q_do_run
        bl      dict_comma
        RAISE
        bl      cf_leave_begin
        bl      cf_leave_add            // the branch over the loop
        ldr     x0, [UP, #UV_HERE]
        DPUSH   x0
        NEXT

        DEFCODE "LOOP", 4, loop, F_IMMEDIATE    // ( C: leave-sys dest -- )
        NEED    2
        mov     x0, #TOK_loop_run
        bl      cf_loop_end
        DPOPM
        DPOPM
        NEXT

        DEFCODE "+LOOP", 5, plus_loop, F_IMMEDIATE      // ( C: leave-sys dest -- ) ( n -- )
        NEED    2
        mov     x0, #TOK_plus_loop_run
        bl      cf_loop_end
        DPOPM
        DPOPM
        NEXT

// I and J each leave a copy of a loop index. Both check the return stack
// before the data stack, the way R@ and the three words beside it do.
        DEFCODE "I", 1, i               // ( -- n ) ( R: loop-sys -- loop-sys )
        RNEED   1
        ROOM    1
        RGET    0, x0
        DPUSH   x0
        NEXT

        DEFCODE "J", 1, j               // ( -- n ) ( R: loop-sys1 loop-sys2 -- loop-sys1 loop-sys2 )
        RNEED   3                       // the third cell down is what it reads
        ROOM    1
        RGET    2, x0
        DPUSH   x0
        NEXT

// UNLOOP drops one loop's parameters without ending the loop, which is what
// lets a definition leave from inside one: the address DOCOL saved is
// underneath them, and EXIT would otherwise return to the limit.
        DEFCODE "UNLOOP", 6, unloop     // ( -- ) ( R: loop-sys -- )
        RNEED   2
        RDROP   2
        NEXT

// LEAVE drops the parameters and branches past the closing word, which is why
// it compiles UNLOOP rather than a drop of its own: one word takes a loop's
// parameters off the return stack.
//
// A LEAVE with no loop open compiles nothing and raises instead. Forth-2012
// allows a system to do as it likes here, and what aforth would otherwise
// compile is dangerous: the UNLOOP would drop two cells that are not loop
// parameters, its guard would pass because two cells are there, and the EXIT
// at the end of the definition would return into a data cell.
        DEFCODE "LEAVE", 5, leave, F_IMMEDIATE  // ( C: -- ) ( R: loop-sys -- )
        ldr     x0, [UP, #UV_LEAVE]
        cmn     x0, #1
        b.ne    1f
        mov     x0, #ERR_CONTROL_FLOW   // there is no loop to leave
        b       machine_error
1:      mov     x0, #TOK_unloop
        bl      dict_comma
        RAISE
        mov     x0, #TOK_branch
        bl      dict_comma
        RAISE
        bl      cf_leave_add
        NEXT

// Dispatching on a value.
//
// CASE leaves a marker, each OF compiles a test that falls through to the next
// arm when it does not match, each ENDOF ends an arm with a branch to the end,
// and ENDCASE points every one of those branches at what follows it.
//
// The branches ENDCASE resolves wait on the control-flow stack, above the
// marker, which is where a LEAVE's branch cannot wait. The difference is that
// an ENDOF always closes at the depth the ENDOF before it closed at, so nothing
// belonging to the body can come between them, and ENDCASE walks them in one
// run. See docs/system/control-flow.md.

        DEFCODE "CASE", 4, case, F_IMMEDIATE    // ( C: -- case-sys )
        ROOM    1
        mov     x0, #0                  // the marker ENDCASE stops on
        DPUSH   x0
        NEXT

// OF compiles the standard's own definition of itself: OVER = IF DROP. The
// DROP goes after the branch's distance, so it runs on a match and not on a
// miss, and the value stays on the stack for the next arm to test.
        DEFCODE "OF", 2, of, F_IMMEDIATE        // ( C: -- of-sys ) ( x1 x2 -- | x1 )
        ROOM    1
        mov     x0, #TOK_over
        bl      dict_comma
        RAISE
        mov     x0, #TOK_equals
        bl      dict_comma
        RAISE
        mov     x0, #TOK_zero_branch
        bl      cf_forward
        mov     x27, x0                 // the place to write, across the call
        mov     x0, #TOK_drop
        bl      dict_comma
        RAISE
        DPUSH   x27
        NEXT

        DEFCODE "ENDOF", 5, endof, F_IMMEDIATE  // ( C: case-sys1 of-sys -- case-sys2 )
        NEED    1
        bl      else_impl
        NEXT

// ENDCASE drops the value no arm matched, and points every arm's ending branch
// at what follows that drop. An arm that did match dropped the value itself,
// which is why the branches land after the drop and not before it.
//
// This is the one word in the file that compiles before it checks. It has no
// choice: where the branches land depends on that drop being there, and how
// many of them there are is not known until the stack is walked. Each place is
// still checked before ENDCASE writes through that place, and the depth is
// checked on every turn, so a stack that runs out reports instead of reading
// past its end.
        DEFCODE "ENDCASE", 7, endcase, F_IMMEDIATE      // ( C: case-sys -- ) ( x -- )
        mov     x0, #TOK_drop
        bl      dict_comma
        RAISE
1:      NEED    1
        cbz     TOS, 2f                 // the marker: every arm is resolved
        mov     x0, TOS
        bl      cf_check
        mov     x0, TOS
        bl      cf_resolve
        DPOPM
        b       1b
2:      DPOPM                           // the marker
        NEXT
