// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// The dictionary format and the inner interpreter.
//
// Three things live here: the shape of a dictionary entry, the dispatch macros
// every primitive ends with, and the macros that define a word. The register
// convention and the stacks are in machine.h.
//
// See docs/system/inner-interpreter.md for the whole picture and
// docs/adr/0005-indirect-threading-with-index-code-fields.md for why a code
// field holds an index instead of an address.

#ifndef AFORTH_DICT_H
#define AFORTH_DICT_H

#include "machine.h"

// A dictionary entry.
//
//   +0    cell   link: the previous entry as an offset from DBASE, 0 ends it
//   +8    byte   flag bits
//   +9    byte   name length in bytes, 0 to 255
//   +10   bytes  the name, UTF-8, stored as typed
//         pad    to the next cell
//   +N    cell   code field: the index of the routine that runs this word
//   +N+8  cells  parameter field: a colon definition's token list
//
// An execution token is the offset of the code field from DBASE, never an
// address. Dispatch adds DBASE back, so a token means the same thing in every
// process the image is loaded into.
//
// The dictionary's first cell is reserved, so no entry and no code field lies
// at offset 0. That leaves 0 free as the token for a word that was not found,
// which is what name lookup will return when it finds nothing.
//
// The name is not cell-aligned. Nothing reads it a cell at a time: comparison
// is byte by byte, because a character is a byte (ADR 0004).
#define ENT_LINK        0
#define ENT_FLAGS       8
#define ENT_COUNT       9
#define ENT_NAME        10

#define F_IMMEDIATE     0x01    // runs even while compiling; 010
#define F_HIDDEN        0x02    // name lookup walks past it; 007

// Every code-field routine, in index order.
//
// This list is the single source of truth. It assigns each routine its index
// and it drives machine_build_xtab, so a name here must exist as prim_<name>
// in some object file or the link fails.
//
// Append to it; do not insert. A code field in a saved dictionary holds an
// index, so renumbering changes the meaning of every image written before it.
//
// A label spells out the punctuation in the word's name, because a label has
// to be a symbol: plus for +, q_dup for ?DUP, to_r for >R, r_fetch for R@,
// two_star for 2*, less_num for <#, num_greater for #>, dot_s for .S.
#define AFORTH_PRIM_LIST docol, exit, execute, dup, plus, stop, \
        drop, swap, over, rot, q_dup, nip, tuck, depth, \
        two_dup, two_drop, two_swap, two_over, \
        to_r, r_from, r_fetch, two_to_r, two_r_from, two_r_fetch, \
        pick, roll, \
        minus, star, slash, mod, slash_mod, abs, negate, min, max, \
        one_plus, one_minus, two_star, two_slash, \
        um_star, um_slash_mod, m_star, sm_slash_rem, fm_slash_mod, \
        and, or, xor, invert, lshift, rshift, \
        equals, not_equals, less, greater, u_less, u_greater, \
        zero_equals, zero_not_equals, zero_less, zero_greater, true, false, \
        fetch, store, c_fetch, c_store, plus_store, \
        cell_plus, cells, char_plus, chars, align, aligned, \
        move, fill, erase, \
        emit, type, cr, spaces, bl, base, decimal, hex, \
        less_num, num, num_s, hold, sign, num_greater, dot_s, \
        source, to_in, refill, accept, key, \
        parse_name, parse, word, count, find, tick, to_number, q_number, \
        state, abort, quit, bye

        .set    aforth_prim_count, 0
        .irp    prim, AFORTH_PRIM_LIST
        .set    XT_\prim, aforth_prim_count
        .set    aforth_prim_count, aforth_prim_count + 1
        .endr

.if aforth_prim_count > XTAB_MAX
.error "aforth: more code-field routines than the index table holds"
.endif

// Dispatch.
//
// DISPATCH runs the word whose code field W points at. NEXT reads the next
// token from the list IP walks and dispatches on that.
//
// NEXT is a macro rather than one shared routine on purpose: every primitive
// carries its own copy, so the indirect branch gets a branch-predictor entry
// per word instead of one entry for the whole system. ADR 0005 expects that to
// matter more than the extra indexed load the index code field costs.
//
// Both clobber x9 and W, the same x9 the stack guards use. A primitive must be
// finished with both before its NEXT.
.macro  DISPATCH
        ldr     x9, [W]                 // code field: a routine index
        ldr     x9, [XTAB, x9, lsl #3]  // index -> address
        br      x9
.endm

.macro  NEXT
        ldr     W, [IP], #8             // token: an offset from DBASE
        add     W, DBASE, W             // the code field it names
        DISPATCH
.endm

// Defining words.
//
// The built-in dictionary is assembled as an image and copied into the region
// at start-up. The image holds nothing but offsets, indices and name bytes, so
// it is valid at whatever address the region landed on, and the copy needs no
// fixing up.
//
// Every built-in entry must be assembled in one pass. The macros track where
// they are in the image with one running offset, and that offset only exists
// inside the assembler that is building it. A second object file would build a
// second image, and its links would not reach this one.
//
// One pass is not one file. The entries live in src/words/, one file per kind
// of word, and src/interpreter.S pulls them in with #include between
// DICT_BEGIN and DICT_END. Include order is definition order, so a file may
// only use tokens from a file above it. The fragments cannot be assembled on
// their own, and the Makefile does not try: its glob is src/*.S, which does not
// reach into src/words/.
//
// Nothing else may go into SECTION_RODATA between DICT_BEGIN and DICT_END: the
// image is whatever lies between those two labels, so a stray string would be
// copied into the dictionary as if it were an entry.
//
// Every offset below is plain arithmetic on the name lengths, never the
// difference between two labels. clang's assembler refuses to reassign a
// symbol whose value is a label difference, because it cannot fold one until
// it lays the section out, and it refuses on Linux while accepting it on
// macOS. So a name's length is declared rather than measured, and two checks
// per entry catch a declaration that does not match the bytes emitted.

// Open the image, reserving the first cell so offset 0 names nothing.
.macro  DICT_BEGIN
        SECTION_RODATA
        .p2align        3
dict_image:
        .quad   0
        .set    dict_prev, 0            // newest entry, an offset from here
        .set    dict_off, 8             // where the next entry goes
.endm

// Close it, and record what start-up needs: how much to copy and where the
// newest entry sits. dict_off is left invalid, so an entry emitted after the
// image has been closed trips the size check in HEADER.
.macro  DICT_END
        SECTION_RODATA
dict_image_end:
        .set    dict_image_size, dict_off
        .set    dict_latest, dict_prev
        .set    dict_off, -1
        .text
.endm

// One entry header, up to and including the code field. Leaves the image
// section open so a caller can append a parameter field.
//
// The name is passed as a quoted string, and its length follows it. The quotes
// are what let a word be named with a comma, which would otherwise separate
// this macro's own arguments; a name holding a double quote or a backslash
// escapes it as any string would.
//
// The four awkward spellings are in docs/system/inner-interpreter.md rather
// than here. An escaped quote inside a comment leaves some editors
// highlighting the rest of the file as one long string.
.macro  HEADER name, len, label, code, flags=0
        SECTION_RODATA
ent_\label:
        .quad   dict_prev               // link
        .set    dict_prev, dict_off
        .set    ENTOF_\label, dict_off  // the entry itself, for a test table
        .byte   \flags
        .byte   \len
1:      .ascii  "\name"
2:
.if (2b - 1b) != \len
.error "aforth: a name's declared length does not match the name"
.endif
        // Pad the name out to the cell the code field starts on.
        .set    dict_hlen, ((10 + \len + 7) / 8) * 8
        .space  dict_hlen - (10 + \len)
        .set    TOK_\label, dict_off + dict_hlen
cf_\label:
        .quad   \code                   // code field
        .set    dict_off, TOK_\label + 8
.if (. - dict_image) != dict_off
.error "aforth: an entry emitted more or fewer bytes than its offsets claim"
.endif
.endm

// A code-field routine with no name of its own: DOCOL, and the other DO...
// routines a defining word will point an entry at. Not a word, so it gets no
// entry; only an index and a body.
.macro  CODE label
        .text
        .p2align        2
        .globl  prim_\label
prim_\label:
.endm

// A word written in assembly: an entry whose code field is the code's own
// index, then the code. The caller writes the body and ends it with NEXT.
//
// Give every word its stack effect as a comment on the defining line, in the
// notation Forth-2012 uses for it: DEFCODE "DUP", 3, dup  // ( x -- x x )
.macro  DEFCODE name, len, label, flags=0
        HEADER  "\name", \len, \label, XT_\label, \flags
        CODE    \label
.endm

// A word defined as a list of tokens: an entry whose code field is DOCOL's
// index. The caller writes the list with TOKEN and ends it with ENDWORD.
.macro  DEFWORD name, len, label, flags=0
        HEADER  "\name", \len, \label, XT_docol, \flags
.endm

// One token in a list. The word must already be defined: a token is a backward
// reference, exactly as it is when Forth compiles one.
//
// A token is an offset into the image, so a list of them is valid outside the
// dictionary as well as inside it. Advancing dict_off is harmless there,
// because DICT_END has already taken the size it needed.
.macro  TOKEN label
        .quad   TOK_\label
        .set    dict_off, dict_off + 8
.endm

.macro  ENDWORD
        TOKEN   exit
        .text
.endm

#endif // AFORTH_DICT_H
