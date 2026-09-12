// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The word test cases, walked by machine_test_words in src/selftest.S.
//
// Included by src/interpreter.S after DICT_END. It has to be in that
// assembler pass: a case names ENTOF_ and TOK_ symbols, which the entry
// macros define with .set and which cross no object file.

// One case is: the entry of the word under test, for the failure message; the
// error the case expects, 0 meaning it should run to the end; the cells to put
// on the stack, deepest first; the cells expected afterwards, deepest first;
// and the token list to run. Reading a case is reading its stack comment.
//
// Temporary. Ticket 009 replaces the whole table with Forth source, once there
// is an outer interpreter to feed it to.

// One case's first two cells. The rest of a case is plain data, read as the
// stack comment beside it reads.
.macro  TCASE entry, err=0
        .quad   \entry, \err
.endm

// A depth guard case, which is one line because every one of them is the same
// shape: run the word with too little on the stack and expect the error. The
// token list is inline, so the driver needs to know nothing about (STOP).
.macro  GCASE entry, tok, pushed, err=ERR_DS_UNDERFLOW
        .quad   \entry, \err, \pushed, \tok, TOK_stop
.endm

        .data
        .p2align        3
        .globl  word_tests
word_tests:
        TCASE   ENTOF_dup                       // ( 1 7 -- 1 7 7 )
        .quad   2, 1, 7
        .quad   3, 1, 7, 7
        .quad   2, TOK_dup, TOK_stop

        TCASE   ENTOF_drop                      // ( 1 7 -- 1 )
        .quad   2, 1, 7
        .quad   1, 1
        .quad   2, TOK_drop, TOK_stop

        TCASE   ENTOF_swap                      // ( 1 2 3 -- 1 3 2 )
        .quad   3, 1, 2, 3
        .quad   3, 1, 3, 2
        .quad   2, TOK_swap, TOK_stop

        TCASE   ENTOF_over                      // ( 1 2 3 -- 1 2 3 2 )
        .quad   3, 1, 2, 3
        .quad   4, 1, 2, 3, 2
        .quad   2, TOK_over, TOK_stop

        TCASE   ENTOF_rot                       // ( 9 1 2 3 -- 9 2 3 1 )
        .quad   4, 9, 1, 2, 3
        .quad   4, 9, 2, 3, 1
        .quad   2, TOK_rot, TOK_stop

        TCASE   ENTOF_q_dup                     // ( 1 7 -- 1 7 7 )
        .quad   2, 1, 7
        .quad   3, 1, 7, 7
        .quad   2, TOK_q_dup, TOK_stop

        TCASE   ENTOF_q_dup                     // ( 1 0 -- 1 0 )
        .quad   2, 1, 0
        .quad   2, 1, 0
        .quad   2, TOK_q_dup, TOK_stop

        TCASE   ENTOF_nip                       // ( 9 1 2 -- 9 2 )
        .quad   3, 9, 1, 2
        .quad   2, 9, 2
        .quad   2, TOK_nip, TOK_stop

        TCASE   ENTOF_tuck                      // ( 9 1 2 -- 9 2 1 2 )
        .quad   3, 9, 1, 2
        .quad   4, 9, 2, 1, 2
        .quad   2, TOK_tuck, TOK_stop

        TCASE   ENTOF_depth                     // ( 1 2 3 -- 1 2 3 3 )
        .quad   3, 1, 2, 3
        .quad   4, 1, 2, 3, 3
        .quad   2, TOK_depth, TOK_stop

        TCASE   ENTOF_depth                     // ( -- 0 ) on an empty stack
        .quad   0
        .quad   1, 0
        .quad   2, TOK_depth, TOK_stop

        TCASE   ENTOF_two_dup                   // ( 9 1 2 -- 9 1 2 1 2 )
        .quad   3, 9, 1, 2
        .quad   5, 9, 1, 2, 1, 2
        .quad   2, TOK_two_dup, TOK_stop

        TCASE   ENTOF_two_drop                  // ( 9 1 2 -- 9 )
        .quad   3, 9, 1, 2
        .quad   1, 9
        .quad   2, TOK_two_drop, TOK_stop

        TCASE   ENTOF_two_swap                  // ( 9 1 2 3 4 -- 9 3 4 1 2 )
        .quad   5, 9, 1, 2, 3, 4
        .quad   5, 9, 3, 4, 1, 2
        .quad   2, TOK_two_swap, TOK_stop

        TCASE   ENTOF_two_over                  // ( 1 2 3 4 -- 1 2 3 4 1 2 )
        .quad   4, 1, 2, 3, 4
        .quad   6, 1, 2, 3, 4, 1, 2
        .quad   2, TOK_two_over, TOK_stop

        TCASE   ENTOF_to_r                      // ( 9 7 -- 9 7 ) through R
        .quad   2, 9, 7
        .quad   2, 9, 7
        .quad   3, TOK_to_r, TOK_r_from, TOK_stop

        TCASE   ENTOF_r_fetch                   // ( 7 -- 7 7 )
        .quad   1, 7
        .quad   2, 7, 7
        .quad   4, TOK_to_r, TOK_r_fetch, TOK_r_from, TOK_stop

        TCASE   ENTOF_two_to_r                  // ( 1 2 -- 1 2 ) through R
        .quad   2, 1, 2
        .quad   2, 1, 2
        .quad   3, TOK_two_to_r, TOK_two_r_from, TOK_stop

        TCASE   ENTOF_two_r_fetch               // ( 1 2 -- 1 2 1 2 )
        .quad   2, 1, 2
        .quad   4, 1, 2, 1, 2
        .quad   4, TOK_two_to_r, TOK_two_r_fetch, TOK_two_r_from, TOK_stop

        TCASE   ENTOF_pick                      // ( 7 0 -- 7 7 ), 0 PICK is DUP
        .quad   2, 7, 0
        .quad   2, 7, 7
        .quad   2, TOK_pick, TOK_stop

        TCASE   ENTOF_pick                      // ( 1 2 3 2 -- 1 2 3 1 )
        .quad   4, 1, 2, 3, 2
        .quad   4, 1, 2, 3, 1
        .quad   2, TOK_pick, TOK_stop

        TCASE   ENTOF_roll                      // ( 7 0 -- 7 ), 0 ROLL does nothing
        .quad   2, 7, 0
        .quad   1, 7
        .quad   2, TOK_roll, TOK_stop

        TCASE   ENTOF_roll                      // ( 1 2 1 -- 2 1 ), 1 ROLL is SWAP
        .quad   3, 1, 2, 1
        .quad   2, 2, 1
        .quad   2, TOK_roll, TOK_stop

        TCASE   ENTOF_roll                      // ( 1 2 3 2 -- 2 3 1 ), 2 ROLL is ROT
        .quad   4, 1, 2, 3, 2
        .quad   3, 2, 3, 1
        .quad   2, TOK_roll, TOK_stop

        TCASE   ENTOF_plus                      // ( 20 22 -- 42 )
        .quad   2, 20, 22
        .quad   1, 42
        .quad   2, TOK_plus, TOK_stop

        TCASE   ENTOF_two_star                  // ( 21 -- 42 )
        .quad   1, 21
        .quad   1, 42
        .quad   2, TOK_two_star, TOK_stop

        TCASE   ENTOF_execute                   // ( 21 xt -- 42 )
        .quad   2, 21, TOK_two_star
        .quad   1, 42
        .quad   2, TOK_execute, TOK_stop

// The arithmetic. The 9 at the bottom of many of these is a sentinel: a word
// that disturbs the stack under its own operands fails the case.
        TCASE   ENTOF_minus                     // ( 9 30 8 -- 9 22 )
        .quad   3, 9, 30, 8
        .quad   2, 9, 22
        .quad   2, TOK_minus, TOK_stop

        TCASE   ENTOF_star                      // ( 9 6 7 -- 9 42 )
        .quad   3, 9, 6, 7
        .quad   2, 9, 42
        .quad   2, TOK_star, TOK_stop

        TCASE   ENTOF_slash                     // ( 22 7 -- 3 )
        .quad   2, 22, 7
        .quad   1, 3
        .quad   2, TOK_slash, TOK_stop

        TCASE   ENTOF_slash                     // ( -22 7 -- -3 ), toward zero
        .quad   2, -22, 7
        .quad   1, -3
        .quad   2, TOK_slash, TOK_stop

        TCASE   ENTOF_mod                       // ( 22 7 -- 1 )
        .quad   2, 22, 7
        .quad   1, 1
        .quad   2, TOK_mod, TOK_stop

        TCASE   ENTOF_mod                       // ( -22 7 -- -1 ), the dividend's sign
        .quad   2, -22, 7
        .quad   1, -1
        .quad   2, TOK_mod, TOK_stop

        TCASE   ENTOF_slash_mod                 // ( 22 7 -- 1 3 )
        .quad   2, 22, 7
        .quad   2, 1, 3
        .quad   2, TOK_slash_mod, TOK_stop

        TCASE   ENTOF_abs                       // ( -5 -- 5 )
        .quad   1, -5
        .quad   1, 5
        .quad   2, TOK_abs, TOK_stop

        TCASE   ENTOF_abs                       // ( 5 -- 5 )
        .quad   1, 5
        .quad   1, 5
        .quad   2, TOK_abs, TOK_stop

        TCASE   ENTOF_negate                    // ( 5 -- -5 )
        .quad   1, 5
        .quad   1, -5
        .quad   2, TOK_negate, TOK_stop

        TCASE   ENTOF_min                       // ( -1 -9 -- -9 ), signed
        .quad   2, -1, -9
        .quad   1, -9
        .quad   2, TOK_min, TOK_stop

        TCASE   ENTOF_max                       // ( 3 9 -- 9 )
        .quad   2, 3, 9
        .quad   1, 9
        .quad   2, TOK_max, TOK_stop

        TCASE   ENTOF_one_plus                  // ( 41 -- 42 )
        .quad   1, 41
        .quad   1, 42
        .quad   2, TOK_one_plus, TOK_stop

        TCASE   ENTOF_one_minus                 // ( 43 -- 42 )
        .quad   1, 43
        .quad   1, 42
        .quad   2, TOK_one_minus, TOK_stop

        TCASE   ENTOF_two_slash                 // ( 42 -- 21 )
        .quad   1, 42
        .quad   1, 21
        .quad   2, TOK_two_slash, TOK_stop

        TCASE   ENTOF_two_slash                 // ( -1 -- -1 ), a shift, so it floors
        .quad   1, -1
        .quad   1, -1
        .quad   2, TOK_two_slash, TOK_stop

// The mixed precision words. A double has its high cell on top, so the pair
// below reads low first.
        TCASE   ENTOF_um_star                   // ( 2^32 2^32 -- 0 1 ), which is 2^64
        .quad   2, 4294967296, 4294967296
        .quad   2, 0, 1
        .quad   2, TOK_um_star, TOK_stop

        TCASE   ENTOF_um_star                   // ( -1 -1 -- 1 -2 ), where signed differs
        .quad   2, -1, -1
        .quad   2, 1, -2
        .quad   2, TOK_um_star, TOK_stop

        TCASE   ENTOF_m_star                    // ( -2 3 -- -6 -1 ), a signed double
        .quad   2, -2, 3
        .quad   2, -6, -1
        .quad   2, TOK_m_star, TOK_stop

        TCASE   ENTOF_um_slash_mod              // ( 100 0 7 -- 2 14 ), the short way
        .quad   3, 100, 0, 7
        .quad   2, 2, 14
        .quad   2, TOK_um_slash_mod, TOK_stop

        TCASE   ENTOF_um_slash_mod              // ( 0 1 3 -- 1 ... ), 2^64 / 3
        .quad   3, 0, 1, 3
        .quad   2, 1, 6148914691236517205
        .quad   2, TOK_um_slash_mod, TOK_stop

        TCASE   ENTOF_um_slash_mod              // the whole cell range, divided by 1
        .quad   3, -1, 0, 1
        .quad   2, 0, -1
        .quad   2, TOK_um_slash_mod, TOK_stop

// The largest quotient that still fits in a cell, all ones, from a dividend
// only just smaller than the divisor shifted up a cell. The running remainder
// passes 2^63 here, so the bit leaving the top of the dividend is the only
// thing that can tell the loop to subtract. No smaller case reaches that path.
        TCASE   ENTOF_um_slash_mod
        .quad   3, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000, 0x8000000000000001
        .quad   2, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF
        .quad   2, TOK_um_slash_mod, TOK_stop

// SM/REM and FM/MOD differ only when the signs differ, and then they differ
// exactly as Forth-2012's own examples say they do.
        TCASE   ENTOF_sm_slash_rem              // ( -7 2 -- -1 -3 ), toward zero
        .quad   3, -7, -1, 2
        .quad   2, -1, -3
        .quad   2, TOK_sm_slash_rem, TOK_stop

        TCASE   ENTOF_fm_slash_mod              // ( -7 2 -- 1 -4 ), floored
        .quad   3, -7, -1, 2
        .quad   2, 1, -4
        .quad   2, TOK_fm_slash_mod, TOK_stop

        TCASE   ENTOF_sm_slash_rem              // ( 7 -2 -- 1 -3 )
        .quad   3, 7, 0, -2
        .quad   2, 1, -3
        .quad   2, TOK_sm_slash_rem, TOK_stop

        TCASE   ENTOF_fm_slash_mod              // ( 7 -2 -- -1 -4 )
        .quad   3, 7, 0, -2
        .quad   2, -1, -4
        .quad   2, TOK_fm_slash_mod, TOK_stop

        TCASE   ENTOF_sm_slash_rem              // ( 7 2 -- 1 3 ), signs agreeing
        .quad   3, 7, 0, 2
        .quad   2, 1, 3
        .quad   2, TOK_sm_slash_rem, TOK_stop

        TCASE   ENTOF_fm_slash_mod              // ( -6 2 -- 0 -3 ), exact, so no fixup
        .quad   3, -6, -1, 2
        .quad   2, 0, -3
        .quad   2, TOK_fm_slash_mod, TOK_stop

// */ and */MOD, and the reason they multiply to a double first: 2^62 * 4 does
// not fit in a cell, but 2^62 4 8 */ is still exact.
        TCASE   ENTOF_star_slash                // ( 100 3 4 -- 75 )
        .quad   3, 100, 3, 4
        .quad   1, 75
        .quad   2, TOK_star_slash, TOK_stop

        TCASE   ENTOF_star_slash                // ( 2^62 4 8 -- 2^61 )
        .quad   3, 4611686018427387904, 4, 8
        .quad   1, 2305843009213693952
        .quad   2, TOK_star_slash, TOK_stop

        TCASE   ENTOF_star_slash_mod            // ( 100 3 7 -- 6 42 )
        .quad   3, 100, 3, 7
        .quad   2, 6, 42
        .quad   2, TOK_star_slash_mod, TOK_stop

// A zero divisor is an error, not a trap: ARM64 division by zero yields zero
// and says nothing, so every dividing word tests for it.
        TCASE   ENTOF_slash, ERR_DIV_ZERO
        .quad   2, 1, 0
        .quad   0
        .quad   2, TOK_slash, TOK_stop

        TCASE   ENTOF_mod, ERR_DIV_ZERO
        .quad   2, 1, 0
        .quad   0
        .quad   2, TOK_mod, TOK_stop

        TCASE   ENTOF_slash_mod, ERR_DIV_ZERO
        .quad   2, 1, 0
        .quad   0
        .quad   2, TOK_slash_mod, TOK_stop

        TCASE   ENTOF_um_slash_mod, ERR_DIV_ZERO
        .quad   3, 1, 0, 0
        .quad   0
        .quad   2, TOK_um_slash_mod, TOK_stop

        TCASE   ENTOF_sm_slash_rem, ERR_DIV_ZERO
        .quad   3, 1, 0, 0
        .quad   0
        .quad   2, TOK_sm_slash_rem, TOK_stop

        TCASE   ENTOF_fm_slash_mod, ERR_DIV_ZERO
        .quad   3, 1, 0, 0
        .quad   0
        .quad   2, TOK_fm_slash_mod, TOK_stop

        TCASE   ENTOF_star_slash, ERR_DIV_ZERO
        .quad   3, 1, 1, 0
        .quad   0
        .quad   2, TOK_star_slash, TOK_stop

// The logic and the shifts.
        TCASE   ENTOF_and                       // ( 12 10 -- 8 )
        .quad   2, 12, 10
        .quad   1, 8
        .quad   2, TOK_and, TOK_stop

        TCASE   ENTOF_or                        // ( 12 10 -- 14 )
        .quad   2, 12, 10
        .quad   1, 14
        .quad   2, TOK_or, TOK_stop

        TCASE   ENTOF_xor                       // ( 12 10 -- 6 )
        .quad   2, 12, 10
        .quad   1, 6
        .quad   2, TOK_xor, TOK_stop

        TCASE   ENTOF_invert                    // ( 0 -- -1 )
        .quad   1, 0
        .quad   1, -1
        .quad   2, TOK_invert, TOK_stop

        TCASE   ENTOF_lshift                    // ( 1 4 -- 16 )
        .quad   2, 1, 4
        .quad   1, 16
        .quad   2, TOK_lshift, TOK_stop

        TCASE   ENTOF_rshift                    // ( -1 60 -- 15 ), logical, not signed
        .quad   2, -1, 60
        .quad   1, 15
        .quad   2, TOK_rshift, TOK_stop

// The comparisons. A true flag is every bit set, which is -1 as a cell.
        TCASE   ENTOF_equals                    // ( 5 5 -- true )
        .quad   2, 5, 5
        .quad   1, -1
        .quad   2, TOK_equals, TOK_stop

        TCASE   ENTOF_equals                    // ( 5 6 -- false )
        .quad   2, 5, 6
        .quad   1, 0
        .quad   2, TOK_equals, TOK_stop

        TCASE   ENTOF_not_equals                // ( 5 6 -- true )
        .quad   2, 5, 6
        .quad   1, -1
        .quad   2, TOK_not_equals, TOK_stop

        TCASE   ENTOF_less                      // ( -1 1 -- true ), signed
        .quad   2, -1, 1
        .quad   1, -1
        .quad   2, TOK_less, TOK_stop

        TCASE   ENTOF_less                      // ( 5 3 -- false )
        .quad   2, 5, 3
        .quad   1, 0
        .quad   2, TOK_less, TOK_stop

        TCASE   ENTOF_greater                   // ( 5 3 -- true )
        .quad   2, 5, 3
        .quad   1, -1
        .quad   2, TOK_greater, TOK_stop

        TCASE   ENTOF_u_less                    // ( -1 1 -- false ), unsigned
        .quad   2, -1, 1
        .quad   1, 0
        .quad   2, TOK_u_less, TOK_stop

        TCASE   ENTOF_u_greater                 // ( -1 1 -- true ), unsigned
        .quad   2, -1, 1
        .quad   1, -1
        .quad   2, TOK_u_greater, TOK_stop

        TCASE   ENTOF_zero_equals                // ( 0 -- true )
        .quad   1, 0
        .quad   1, -1
        .quad   2, TOK_zero_equals, TOK_stop

        TCASE   ENTOF_zero_not_equals            // ( 5 -- true )
        .quad   1, 5
        .quad   1, -1
        .quad   2, TOK_zero_not_equals, TOK_stop

        TCASE   ENTOF_zero_less                  // ( -5 -- true )
        .quad   1, -5
        .quad   1, -1
        .quad   2, TOK_zero_less, TOK_stop

        TCASE   ENTOF_zero_greater               // ( 5 -- true )
        .quad   1, 5
        .quad   1, -1
        .quad   2, TOK_zero_greater, TOK_stop

        TCASE   ENTOF_true                      // ( 9 -- 9 true )
        .quad   1, 9
        .quad   2, 9, -1
        .quad   2, TOK_true, TOK_stop

        TCASE   ENTOF_false                     // ( 9 -- 9 false )
        .quad   1, 9
        .quad   2, 9, 0
        .quad   2, TOK_false, TOK_stop

// The memory words, which need somewhere to write. test_scratch and
// test_source are in selftest.S.
        TCASE   ENTOF_store                     // 42 goes to scratch and comes back
        .quad   2, 42, test_scratch
        .quad   1, 42
        .quad   4, TOK_tuck, TOK_store, TOK_fetch, TOK_stop

        TCASE   ENTOF_c_store                   // 200 does not come back negative
        .quad   2, 200, test_scratch
        .quad   1, 200
        .quad   4, TOK_tuck, TOK_c_store, TOK_c_fetch, TOK_stop

        TCASE   ENTOF_plus_store                // 10 stored, 5 added, 15 read back
        .quad   5, test_scratch, 5, test_scratch, 10, test_scratch
        .quad   1, 15
        .quad   4, TOK_store, TOK_plus_store, TOK_fetch, TOK_stop

        TCASE   ENTOF_cell_plus                 // ( 100 -- 108 )
        .quad   1, 100
        .quad   1, 108
        .quad   2, TOK_cell_plus, TOK_stop

        TCASE   ENTOF_cells                     // ( 3 -- 24 )
        .quad   1, 3
        .quad   1, 24
        .quad   2, TOK_cells, TOK_stop

        TCASE   ENTOF_char_plus                 // ( 100 -- 101 )
        .quad   1, 100
        .quad   1, 101
        .quad   2, TOK_char_plus, TOK_stop

        TCASE   ENTOF_chars                     // ( 3 -- 3 ), a character being a byte
        .quad   1, 3
        .quad   1, 3
        .quad   2, TOK_chars, TOK_stop

        TCASE   ENTOF_aligned                   // ( 101 -- 104 )
        .quad   1, 101
        .quad   1, 104
        .quad   2, TOK_aligned, TOK_stop

        TCASE   ENTOF_aligned                   // ( 104 -- 104 ), already there
        .quad   1, 104
        .quad   1, 104
        .quad   2, TOK_aligned, TOK_stop

// ALIGN moves the dictionary pointer, and no word reads that pointer until
// HERE arrives in ticket 010, so all this can say is that it runs and leaves
// the stack alone.
        TCASE   ENTOF_align                     // ( 9 -- 9 )
        .quad   1, 9
        .quad   1, 9
        .quad   2, TOK_align, TOK_stop

        TCASE   ENTOF_move                      // eight known bytes, copied
        .quad   4, test_scratch, test_source, test_scratch, 8
        .quad   1, 0x1122334455667788
        .quad   3, TOK_move, TOK_fetch, TOK_stop

        TCASE   ENTOF_fill                      // filled with 65, read back as 65
        .quad   4, test_scratch, test_scratch, 8, 65
        .quad   1, 65
        .quad   3, TOK_fill, TOK_c_fetch, TOK_stop

        TCASE   ENTOF_erase                     // filled, then erased to zero
        .quad   6, test_scratch, test_scratch, 8, test_scratch, 8, 65
        .quad   1, 0
        .quad   4, TOK_fill, TOK_erase, TOK_c_fetch, TOK_stop

// The output words, in the part of them that shows on the stack. What they
// print is checked by test/run-tests.sh instead, because these cases run
// before aforth has said anything and a case that printed would land above the
// banner.
//
// #> hands back the address of the buffer, which is wherever the region landed,
// so a case reads the length it reports and drops the address with NIP.

        TCASE   ENTOF_base                      // ( -- 10 )
        .quad   0
        .quad   1, 10
        .quad   3, TOK_base, TOK_fetch, TOK_stop

        TCASE   ENTOF_hex                       // ( -- 16 ), and back to ten
        .quad   0
        .quad   1, 16
        .quad   5, TOK_hex, TOK_base, TOK_fetch, TOK_decimal, TOK_stop

        TCASE   ENTOF_decimal                   // ( -- 10 ) after HEX
        .quad   0
        .quad   1, 10
        .quad   5, TOK_hex, TOK_decimal, TOK_base, TOK_fetch, TOK_stop

        TCASE   ENTOF_num                       // two digits held, two reported
        .quad   2, 5, 0
        .quad   1, 2
        .quad   6, TOK_less_num, TOK_num, TOK_num, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_num_s                     // zero is one digit, not none
        .quad   2, 0, 0
        .quad   1, 1
        .quad   5, TOK_less_num, TOK_num_s, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_num_s                     // 255 is three digits in ten
        .quad   2, 255, 0
        .quad   1, 3
        .quad   5, TOK_less_num, TOK_num_s, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_num_s                     // and two in sixteen: FF
        .quad   2, 255, 0
        .quad   1, 2
        .quad   7, TOK_hex, TOK_less_num, TOK_num_s, TOK_num_greater, TOK_nip, TOK_decimal, TOK_stop

        TCASE   ENTOF_num_s                     // a double past a single cell
        .quad   2, 0, 1
        .quad   1, 20
        .quad   5, TOK_less_num, TOK_num_s, TOK_num_greater, TOK_nip, TOK_stop

// A high half larger than BASE, which is the case that needs # to divide the
// halves in turn: 255 * 2^64 is 22 digits, and a # that divided the low half
// alone would overflow the quotient instead. The digits themselves are checked
// by the line out_list_double prints.
        TCASE   ENTOF_num_s                     // ( 0 255 -- ) 22 digits
        .quad   2, 0, 255
        .quad   1, 22
        .quad   5, TOK_less_num, TOK_num_s, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_hold                      // one character, one byte
        .quad   3, 0, 0, 65
        .quad   1, 1
        .quad   5, TOK_less_num, TOK_hold, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_sign                      // a negative holds the minus
        .quad   3, 0, 0, -1
        .quad   1, 1
        .quad   5, TOK_less_num, TOK_sign, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_sign                      // a positive holds nothing
        .quad   3, 0, 0, 1
        .quad   1, 0
        .quad   5, TOK_less_num, TOK_sign, TOK_num_greater, TOK_nip, TOK_stop

        TCASE   ENTOF_bl                        // ( -- 32 )
        .quad   0
        .quad   1, 32
        .quad   2, TOK_bl, TOK_stop

// The input words, in the part of them that reads nothing. No case here may
// call REFILL, ACCEPT or KEY: this table runs before the scaffolding does, so
// a case that read input would eat a line of the piped script and leave the
// suite's checks depending on the order the cases are in.

        TCASE   ENTOF_source                    // nothing read yet, so no line
        .quad   0
        .quad   1, 0
        .quad   3, TOK_source, TOK_nip, TOK_stop

        TCASE   ENTOF_to_in                     // ( -- 0 ), the parse offset
        .quad   0
        .quad   1, 0
        .quad   3, TOK_to_in, TOK_fetch, TOK_stop

// The search and the number conversion, over strings in writable data. The
// words that parse cannot be tested here — they read SOURCE, nothing can point
// SOURCE at a test buffer, and a case that refilled would eat a line of the
// piped script — so PARSE-NAME, PARSE, WORD, CHAR and ' are checked by
// test/run-tests.sh, which feeds the binary Forth source.

        TCASE   ENTOF_find                      // the word, and -1 for not immediate
        .quad   1, test_cs_dup
        .quad   2, TOK_dup, -1
        .quad   2, TOK_find, TOK_stop

        TCASE   ENTOF_find                      // the same word typed in lower case
        .quad   1, test_cs_dup_lower
        .quad   2, TOK_dup, -1
        .quad   2, TOK_find, TOK_stop

        TCASE   ENTOF_find                      // a name no entry carries
        .quad   1, test_cs_missing
        .quad   2, test_cs_missing, 0
        .quad   2, TOK_find, TOK_stop

        TCASE   ENTOF_find                      // hidden, so the search walks past
        .quad   1, test_cs_hidden
        .quad   2, test_cs_hidden, 0
        .quad   2, TOK_find, TOK_stop

        TCASE   ENTOF_count                     // ( c-addr -- c-addr+1 3 )
        .quad   1, test_cs_dup
        .quad   2, test_cs_dup + 1, 3
        .quad   2, TOK_count, TOK_stop

        TCASE   ENTOF_to_number                 // all three digits convert
        .quad   4, 0, 0, test_s_123, 3
        .quad   4, 123, 0, test_s_123 + 3, 0
        .quad   2, TOK_to_number, TOK_stop

        TCASE   ENTOF_to_number                 // stops at the x, one left
        .quad   4, 0, 0, test_s_12x, 3
        .quad   4, 12, 0, test_s_12x + 2, 1
        .quad   2, TOK_to_number, TOK_stop

        TCASE   ENTOF_to_number                 // FF is 255 in base sixteen
        .quad   4, 0, 0, test_s_ff, 2
        .quad   4, 255, 0, test_s_ff + 2, 0
        .quad   4, TOK_hex, TOK_to_number, TOK_decimal, TOK_stop

        TCASE   ENTOF_q_number                  // a signed number, and a flag
        .quad   2, test_s_minus42, 3
        .quad   2, -42, -1
        .quad   2, TOK_q_number, TOK_stop

        TCASE   ENTOF_q_number                  // not a number: the string comes back
        .quad   2, test_s_wat, 3
        .quad   3, test_s_wat, 3, 0
        .quad   2, TOK_q_number, TOK_stop

// A colon is the character after '9' in ASCII, so subtracting 'A' - 10 from it
// gives 3. It is not a digit in any base, and this is the case that says so.
        TCASE   ENTOF_to_number                 // ( 0 0 c-addr 1 -- 0 0 c-addr 1 )
        .quad   4, 0, 0, test_s_colon, 1
        .quad   4, 0, 0, test_s_colon, 1
        .quad   4, TOK_hex, TOK_to_number, TOK_decimal, TOK_stop

// 2^64 in twenty digits: the accumulator leaves one cell, so a carry has to
// reach the high half of the double. This one reaches it from the addition of
// the last digit and from nowhere else.
        TCASE   ENTOF_to_number                 // ( 0 0 c-addr 20 -- 0 1 c-addr+20 0 )
        .quad   4, 0, 0, test_s_2p64, 20
        .quad   4, 0, 1, test_s_2p64 + 20, 0
        .quad   2, TOK_to_number, TOK_stop

// Twenty-one nines, which is 54 times 2^64 and change. Here the high half has
// to come from both of the other two places: the top bits of the low half's
// multiply, and the high half's own multiply once it is no longer zero.
        TCASE   ENTOF_to_number                 // ( 0 0 c-addr 21 -- lo 54 c-addr+21 0 )
        .quad   4, 0, 0, test_s_nines, 21
        .quad   4, 3875820019684212735, 54, test_s_nines + 21, 0
        .quad   2, TOK_to_number, TOK_stop

// The outer interpreter's words.
//
// STATE is written and read back, and how far its address lies from BASE's is
// checked as well. Writing and reading alone is not enough: this case passed
// against a STATE that handed out BASE's address, because any writable cell
// gives back what was put in it. The distance is the one machine.h sets,
// UV_STATE minus UV_BASE.
//
// STATE is left holding -1, which costs nothing: machine_quit zeroes it before
// it reads a line.
        TCASE   ENTOF_state                     // ( -- 8 -1 )
        .quad   0
        .quad   2, 8, -1
        .quad   9, TOK_state, TOK_base, TOK_minus, TOK_true, TOK_state, \
                TOK_store, TOK_state, TOK_fetch, TOK_stop

// ABORT and QUIT leave the machine the way an error does, so the driver
// catches them the way it catches a divide by zero. What each one empties is
// machine_quit's job and is checked by test/run-tests.sh instead.
        TCASE   ENTOF_abort, ERR_ABORT
        .quad   2, 1, 2
        .quad   0
        .quad   2, TOK_abort, TOK_stop

        TCASE   ENTOF_quit, ERR_QUIT
        .quad   0
        .quad   0
        .quad   2, TOK_quit, TOK_stop

        .quad   0                       // no more cases

#ifndef AFORTH_NO_STACK_CHECKS
// The depth guards.
//
// Each line runs one word with one item too few and expects the error rather
// than a wild read. The number is what the case puts on the stack, so it reads
// as the word's requirement minus one, and the table is also the one place
// every word's arity is written down.
//
// The build without the guards has nothing to fire, which is the point of that
// build, so the whole table is left out of it.
        SECTION_RODATA
        .p2align        3
        .globl  word_guards
word_guards:
        GCASE   ENTOF_dup, TOK_dup, 0
        GCASE   ENTOF_drop, TOK_drop, 0
        GCASE   ENTOF_swap, TOK_swap, 1
        GCASE   ENTOF_over, TOK_over, 1
        GCASE   ENTOF_rot, TOK_rot, 2
        GCASE   ENTOF_q_dup, TOK_q_dup, 0
        GCASE   ENTOF_nip, TOK_nip, 1
        GCASE   ENTOF_tuck, TOK_tuck, 1
        GCASE   ENTOF_two_dup, TOK_two_dup, 1
        GCASE   ENTOF_two_drop, TOK_two_drop, 1
        GCASE   ENTOF_two_swap, TOK_two_swap, 3
        GCASE   ENTOF_two_over, TOK_two_over, 3
        GCASE   ENTOF_pick, TOK_pick, 0
        GCASE   ENTOF_roll, TOK_roll, 0
        GCASE   ENTOF_execute, TOK_execute, 0

        GCASE   ENTOF_to_r, TOK_to_r, 0
        GCASE   ENTOF_r_from, TOK_r_from, 0, ERR_RS_UNDERFLOW
        GCASE   ENTOF_r_fetch, TOK_r_fetch, 0, ERR_RS_UNDERFLOW
        GCASE   ENTOF_two_to_r, TOK_two_to_r, 1
        GCASE   ENTOF_two_r_from, TOK_two_r_from, 0, ERR_RS_UNDERFLOW
        GCASE   ENTOF_two_r_fetch, TOK_two_r_fetch, 0, ERR_RS_UNDERFLOW
        GCASE   ENTOF_exit, TOK_exit, 0, ERR_RS_UNDERFLOW

        GCASE   ENTOF_plus, TOK_plus, 1
        GCASE   ENTOF_minus, TOK_minus, 1
        GCASE   ENTOF_star, TOK_star, 1
        GCASE   ENTOF_slash, TOK_slash, 1
        GCASE   ENTOF_mod, TOK_mod, 1
        GCASE   ENTOF_slash_mod, TOK_slash_mod, 1
        GCASE   ENTOF_abs, TOK_abs, 0
        GCASE   ENTOF_negate, TOK_negate, 0
        GCASE   ENTOF_min, TOK_min, 1
        GCASE   ENTOF_max, TOK_max, 1
        GCASE   ENTOF_one_plus, TOK_one_plus, 0
        GCASE   ENTOF_one_minus, TOK_one_minus, 0
        GCASE   ENTOF_two_star, TOK_two_star, 0
        GCASE   ENTOF_two_slash, TOK_two_slash, 0
        GCASE   ENTOF_um_star, TOK_um_star, 1
        GCASE   ENTOF_m_star, TOK_m_star, 1
        GCASE   ENTOF_um_slash_mod, TOK_um_slash_mod, 2
        GCASE   ENTOF_sm_slash_rem, TOK_sm_slash_rem, 2
        GCASE   ENTOF_fm_slash_mod, TOK_fm_slash_mod, 2
        GCASE   ENTOF_star_slash, TOK_star_slash, 2
        GCASE   ENTOF_star_slash_mod, TOK_star_slash_mod, 2

        GCASE   ENTOF_and, TOK_and, 1
        GCASE   ENTOF_or, TOK_or, 1
        GCASE   ENTOF_xor, TOK_xor, 1
        GCASE   ENTOF_invert, TOK_invert, 0
        GCASE   ENTOF_lshift, TOK_lshift, 1
        GCASE   ENTOF_rshift, TOK_rshift, 1

        GCASE   ENTOF_equals, TOK_equals, 1
        GCASE   ENTOF_not_equals, TOK_not_equals, 1
        GCASE   ENTOF_less, TOK_less, 1
        GCASE   ENTOF_greater, TOK_greater, 1
        GCASE   ENTOF_u_less, TOK_u_less, 1
        GCASE   ENTOF_u_greater, TOK_u_greater, 1
        GCASE   ENTOF_zero_equals, TOK_zero_equals, 0
        GCASE   ENTOF_zero_not_equals, TOK_zero_not_equals, 0
        GCASE   ENTOF_zero_less, TOK_zero_less, 0
        GCASE   ENTOF_zero_greater, TOK_zero_greater, 0

        GCASE   ENTOF_fetch, TOK_fetch, 0
        GCASE   ENTOF_store, TOK_store, 1
        GCASE   ENTOF_c_fetch, TOK_c_fetch, 0
        GCASE   ENTOF_c_store, TOK_c_store, 1
        GCASE   ENTOF_plus_store, TOK_plus_store, 1
        GCASE   ENTOF_cell_plus, TOK_cell_plus, 0
        GCASE   ENTOF_cells, TOK_cells, 0
        GCASE   ENTOF_char_plus, TOK_char_plus, 0
        GCASE   ENTOF_chars, TOK_chars, 0
        GCASE   ENTOF_aligned, TOK_aligned, 0
        GCASE   ENTOF_move, TOK_move, 2
        GCASE   ENTOF_fill, TOK_fill, 2
        GCASE   ENTOF_erase, TOK_erase, 1

        GCASE   ENTOF_emit, TOK_emit, 0
        GCASE   ENTOF_type, TOK_type, 1
        GCASE   ENTOF_spaces, TOK_spaces, 0
        GCASE   ENTOF_num, TOK_num, 1
        GCASE   ENTOF_num_s, TOK_num_s, 1
        GCASE   ENTOF_hold, TOK_hold, 0
        GCASE   ENTOF_sign, TOK_sign, 0
        GCASE   ENTOF_num_greater, TOK_num_greater, 1

        GCASE   ENTOF_accept, TOK_accept, 1

        GCASE   ENTOF_parse, TOK_parse, 0
        GCASE   ENTOF_word, TOK_word, 0
        GCASE   ENTOF_count, TOK_count, 0
        GCASE   ENTOF_find, TOK_find, 0
        GCASE   ENTOF_to_number, TOK_to_number, 3
        GCASE   ENTOF_q_number, TOK_q_number, 1

        // The four token lists, each of which reaches its underflow before it
        // has written anything, which is what keeps this table silent.
        GCASE   ENTOF_dot, TOK_dot, 0
        GCASE   ENTOF_u_dot, TOK_u_dot, 0
        GCASE   ENTOF_dot_r, TOK_dot_r, 1
        GCASE   ENTOF_u_dot_r, TOK_u_dot_r, 1

        .quad   0                       // no more cases
#endif // AFORTH_NO_STACK_CHECKS
