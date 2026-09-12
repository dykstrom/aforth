// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The stack words, the return stack transfers, and PICK and ROLL.
//
// Each is written for the cached top rather than translated from a Forth that
// keeps the whole stack in memory, so the shapes differ from the textbook
// ones: DROP is a load, DUP is a store, and a word that only rearranges the
// stack does it in place instead of popping and pushing its way through.
//
// Included by src/interpreter.S between DICT_BEGIN and DICT_END. Not a
// translation unit of its own: the entry macros track their place in the image
// with symbols only that one assembler pass has.

// DUP: copy the top item. The cached top already holds it, so spilling it is
// the whole word.
        DEFCODE "DUP", 3, dup           // ( x -- x x )
        NEED    1
        ROOM    1
        DPUSHM
        NEXT

        DEFCODE "DROP", 4, drop         // ( x -- )
        NEED    1
        DPOPM
        NEXT

        DEFCODE "SWAP", 4, swap         // ( x1 x2 -- x2 x1 )
        NEED    2
        DGETM   0, x0                   // x0 = x1
        DSETM   0, TOS                  // x2 goes under
        mov     TOS, x0
        NEXT

        DEFCODE "OVER", 4, over         // ( x1 x2 -- x1 x2 x1 )
        NEED    2
        ROOM    1
        DGETM   0, x0                   // x0 = x1
        DPUSH   x0
        NEXT

        DEFCODE "ROT", 3, rot           // ( x1 x2 x3 -- x2 x3 x1 )
        NEED    3
        DGETM   1, x0                   // x0 = x1
        DGETM   0, x1                   // x1 = x2
        DSETM   1, x1
        DSETM   0, TOS                  // x3 goes under
        mov     TOS, x0
        NEXT

// ?DUP: the guard comes first, because the test reads the top item.
        DEFCODE "?DUP", 4, q_dup        // ( x -- 0 | x x )
        NEED    1
        cbz     TOS, 1f
        ROOM    1
        DPUSHM
1:      NEXT

// NIP: drop the second item by popping it into nothing. The top is cached, so
// it is not disturbed.
        DEFCODE "NIP", 3, nip           // ( x1 x2 -- x2 )
        NEED    2
        DPOPM   xzr
        NEXT

        DEFCODE "TUCK", 4, tuck         // ( x1 x2 -- x2 x1 x2 )
        NEED    2
        ROOM    1
        DGETM   0, x0                   // x0 = x1
        DPUSHM                          // room for the copy
        DSETM   0, x0
        DSETM   1, TOS
        NEXT

        DEFCODE "DEPTH", 5, depth       // ( -- +n )
        ROOM    1
        DDEPTH  x0
        DPUSH   x0
        NEXT

        DEFCODE "2DUP", 4, two_dup      // ( x1 x2 -- x1 x2 x1 x2 )
        NEED    2
        ROOM    2
        DGETM   0, x0                   // x0 = x1
        DPUSHM
        DPUSHM
        DSETM   0, x0
        NEXT

        DEFCODE "2DROP", 5, two_drop    // ( x1 x2 -- )
        NEED    2
        DPOPM   xzr
        DPOPM
        NEXT

        DEFCODE "2SWAP", 5, two_swap    // ( x1 x2 x3 x4 -- x3 x4 x1 x2 )
        NEED    4
        DGETM   1, x0                   // x0 = x2
        DGETM   2, x1                   // x1 = x1
        DGETM   0, x2                   // x2 = x3
        DSETM   2, x2
        DSETM   1, TOS                  // x4
        DSETM   0, x1
        mov     TOS, x0
        NEXT

        DEFCODE "2OVER", 5, two_over    // ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )
        NEED    4
        ROOM    2
        DGETM   1, x0                   // x0 = x2
        DGETM   2, x1                   // x1 = x1
        DPUSHM
        DPUSHM
        DSETM   0, x1
        mov     TOS, x0
        NEXT

// The return stack transfers.
//
// The return stack keeps its top item in memory like every other item, so
// these words move a cell between a register and memory in one direction or
// the other. 2>R and 2R> keep the pair in the order the data stack had it,
// which is what the standard requires.
        DEFCODE ">R", 2, to_r           // ( x -- ) ( R: -- x )
        NEED    1
        RROOM   1
        RPUSH   TOS
        DPOPM
        NEXT

        DEFCODE "R>", 2, r_from         // ( -- x ) ( R: x -- )
        RNEED   1
        ROOM    1
        DPUSHM
        RPOP    TOS
        NEXT

        DEFCODE "R@", 2, r_fetch        // ( -- x ) ( R: x -- x )
        RNEED   1
        ROOM    1
        DPUSHM
        RGET    0, TOS
        NEXT

        DEFCODE "2>R", 3, two_to_r      // ( x1 x2 -- ) ( R: -- x1 x2 )
        NEED    2
        RROOM   2
        DGETM   0, x0                   // x0 = x1
        RPUSH   x0
        RPUSH   TOS                     // x2 ends on top, as it was
        DPOPM   xzr
        DPOPM
        NEXT

        DEFCODE "2R>", 3, two_r_from    // ( -- x1 x2 ) ( R: x1 x2 -- )
        RNEED   2
        ROOM    2
        RPOP    x0                      // x0 = x2
        RPOP    x1                      // x1 = x1
        DPUSH   x1
        DPUSH   x0
        NEXT

        DEFCODE "2R@", 3, two_r_fetch   // ( -- x1 x2 ) ( R: x1 x2 -- x1 x2 )
        RNEED   2
        ROOM    2
        RGET    1, x1                   // x1 = x1
        RGET    0, x0                   // x0 = x2
        DPUSH   x1
        DPUSH   x0
        NEXT


// PICK and ROLL, whose depth requirement is whatever the user asked for, so
// they guard with NEEDX rather than NEED. u itself is on the stack, so u + 2
// items must be there. A negative u passes that check and reads a cell of
// aforth's own memory: the standard calls u out of range an ambiguous
// condition, and this is what aforth does with it.
        DEFCODE "PICK", 4, pick         // ( xu ... x0 u -- xu ... x0 xu )
        NEED    1
        add     x0, TOS, #2
        NEEDX   x0
        DGETMX  TOS, x0                 // the u-th cell below the top
        mov     TOS, x0
        NEXT

// ROLL moves the u-th item to the top and closes the gap it left, so it walks
// the cells between. 0 ROLL does nothing, 1 ROLL is SWAP and 2 ROLL is ROT.
        DEFCODE "ROLL", 4, roll         // ( xu ... x0 u -- xu-1 ... x0 xu )
        NEED    1
        add     x0, TOS, #2
        NEEDX   x0
        DPOP    x0                      // x0 = u; the top is now x0
        cbz     x0, 2f
        mov     x1, TOS                 // x1 = the item that moves down
        sub     x2, x0, #1              // where xu sits now
        DGETMX  x2, x3
        mov     TOS, x3                 // xu becomes the top
1:      cbz     x2, 3f                  // shift the rest up one cell
        sub     x4, x2, #1
        DGETMX  x4, x3
        DSETMX  x2, x3
        mov     x2, x4
        b       1b
3:      DSETM   0, x1
2:      NEXT

