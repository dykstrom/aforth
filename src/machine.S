// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Start-up for aforth's machine: allocate the one region, carve it, fill the
// user area, and call the two routines in interpreter.S that build the dispatch
// table and the dictionary. The register convention and the region layout live
// in src/include/machine.h.
//
// The stack guards land in this file too: ds_underflow and its three siblings
// name the error and go through the vector in the user area. What the vector
// points at, and what each error number prints, is in src/outer.S.

#include "machine.h"

        SECTION_RODATA
        .p2align        3
msg_mmap:
        .asciz  "aforth: mmap"

// A run of spaces for write_spaces to write from.
//
// It lives here rather than in src/words/output.S because that file is
// included between DICT_BEGIN and DICT_END, where anything in SECTION_RODATA
// would be copied into the dictionary as if it were an entry.
        .p2align        3
spaces_run:
        .space  SPACES_RUN, 32

// readline's prompt. Nothing is printed in front of a line: aforth says " ok"
// after a line instead, which is where the older Forths put it.
str_empty:
        .asciz  ""

// The pieces the two cold-start paths are built from. The environment
// variables are ADR 0003's, and both file names carry the .f extension the
// design goals require of Forth source.
str_system_file:
        .asciz  "aforth.f"
str_xdg_config_home:
        .asciz  "XDG_CONFIG_HOME"
str_home:
        .asciz  "HOME"
str_dot_config:
        .asciz  "/.config"
str_init_file:
        .asciz  "/aforth/init.f"

        .text

// Allocate and carve the region, and set the machine registers.
//
// Returns the region base in x0, or 0 when the mapping failed, having already
// reported why. The dispatch table and the built-in dictionary are built here
// too, by the two routines in interpreter.S that know what goes in them.
        .p2align        2
        .globl  machine_init
        FUNC_TYPE(machine_init)
machine_init:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        mov     x0, #0                  // let the kernel choose the address
        // mov cannot take REGION_SIZE as one immediate, so build it from its
        // two 16-bit halves.
        movz    x1, #(REGION_SIZE & 0xffff)
        movk    x1, #((REGION_SIZE >> 16) & 0xffff), lsl #16
        mov     w2, #3                  // PROT_READ|PROT_WRITE
        mov     w3, #MMAP_FLAGS
        mov     w4, #-1                 // no file descriptor
        mov     x5, #0                  // no offset
        bl      CSYM(mmap)

        cmn     x0, #1                  // MAP_FAILED is -1
        b.eq    init_failed

        // x0 holds the region base from here to the return.
        mov     UP, x0

        add     x1, x0, #XTAB_OFF
        mov     XTAB, x1

        add     x1, x0, #DICT_OFF
        mov     DBASE, x1
        str     x1, [UP, #UV_DICT]
        str     x1, [UP, #UV_HERE]

        add     x1, x0, #DICT_END_OFF
        str     x1, [UP, #UV_DICT_END]

        add     x1, x0, #S0_OFF
        mov     DSP, x1
        str     x1, [UP, #UV_S0]

        add     x1, x0, #R0_OFF
        mov     RSP, x1
        str     x1, [UP, #UV_R0]

        add     x1, x0, #DSTACK_OFF
        str     x1, [UP, #UV_DS_LO]

        add     x1, x0, #RSTACK_OFF
        str     x1, [UP, #UV_RS_LO]

        add     x1, x0, #TIB_OFF
        str     x1, [UP, #UV_TIB]

        // Pictured output fills downward, so the pointer starts at the end and
        // the buffer's own base is the bound HOLDROOM tests against.
        add     x1, x0, #HOLD_END_OFF
        str     x1, [UP, #UV_HOLD]
        str     x1, [UP, #UV_HOLD_END]

        add     x1, x0, #HOLD_OFF
        str     x1, [UP, #UV_HOLD_LO]

        add     x1, x0, #PAD_OFF
        str     x1, [UP, #UV_PAD]

        // The transient string buffers start empty and the first interpreted
        // S" takes the first of them.
        add     x1, x0, #SBUF_OFF
        str     x1, [UP, #UV_SBUF]
        str     x1, [UP, #UV_SBUF_NEXT]

        // The only real code address aforth writes anywhere. It is allowed
        // because the user area is not the dictionary, which ADR 0005 requires
        // to hold none. When warm start lands it must rewrite this cell on
        // load rather than trust the saved value.
        adr_sym x1, quit_abort
        str     x1, [UP, #UV_ABORT]

        mov     x1, #10
        str     x1, [UP, #UV_BASE]

        str     xzr, [UP, #UV_LATEST]
        str     xzr, [UP, #UV_STATE]
        str     xzr, [UP, #UV_TIB_LEN]
        str     xzr, [UP, #UV_TO_IN]

        str     xzr, [UP, #UV_STOP_SP]

        str     xzr, [UP, #UV_ERR_ADDR]
        str     xzr, [UP, #UV_ERR_LEN]

        // The terminal is the source at the bottom, with nothing under it.
        str     xzr, [UP, #UV_SOURCE_ID]
        str     xzr, [UP, #UV_SRC_DEPTH]

        // Deterministic; the machine overwrites all three as soon as it runs.
        mov     IP, #0
        mov     TOS, #0
        mov     W, #0

        // Both are rebuilt on every start-up, which is what keeps a dictionary
        // of indices and offsets valid in a process that loaded elsewhere.
        bl      machine_build_xtab
        bl      machine_load_dictionary

        mov     x0, UP                  // the region base, for the caller
        ldp     x29, x30, [sp], #16
        ret

init_failed:
        adr_sym x0, msg_mmap
        bl      CSYM(perror)
        mov     x0, #0
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(machine_init)

// Where a word goes when it cannot do what it was asked. Each entry names the
// error, then goes through the vector in the user area, which holds quit_abort
// in src/outer.S: it carries the number out of the machine, and machine_quit
// reports it, empties the stacks and reads the next line.
        .p2align        2
        .globl  ds_underflow
        FUNC_TYPE(ds_underflow)
ds_underflow:
        mov     x0, #ERR_DS_UNDERFLOW
        b       machine_error
        FUNC_SIZE(ds_underflow)

        .globl  ds_overflow
        FUNC_TYPE(ds_overflow)
ds_overflow:
        mov     x0, #ERR_DS_OVERFLOW
        b       machine_error
        FUNC_SIZE(ds_overflow)

        .globl  rs_underflow
        FUNC_TYPE(rs_underflow)
rs_underflow:
        mov     x0, #ERR_RS_UNDERFLOW
        b       machine_error
        FUNC_SIZE(rs_underflow)

        .globl  rs_overflow
        FUNC_TYPE(rs_overflow)
rs_overflow:
        mov     x0, #ERR_RS_OVERFLOW
        b       machine_error
        FUNC_SIZE(rs_overflow)

        .globl  div_zero
        FUNC_TYPE(div_zero)
div_zero:
        mov     x0, #ERR_DIV_ZERO
        b       machine_error
        FUNC_SIZE(div_zero)

        .globl  hold_overflow
        FUNC_TYPE(hold_overflow)
hold_overflow:
        mov     x0, #ERR_HOLD_OVERFLOW
        b       machine_error
        FUNC_SIZE(hold_overflow)

// Remember the name an error names. It is at x0, x1 bytes long, and it goes in
// the user area for machine_quit to print after the message.
//
// The name points into the input buffer, which the next REFILL overwrites. The
// message is written before that happens, so the two never race.
        .globl  err_name
        FUNC_TYPE(err_name)
err_name:
        str     x0, [UP, #UV_ERR_ADDR]
        str     x1, [UP, #UV_ERR_LEN]
        ret
        FUNC_SIZE(err_name)

// Remember it and raise the undefined word on it. ' comes through here.
//
// interpret_source does not: it calls err_name and returns the number, because
// it runs outside aforth_enter when the loop calls it and inside one when
// EVALUATE does, and a raise is wrong in both. See docs/system/input.md.
//
// The bl clobbers x30, which costs nothing: this never returns.
        .globl  undefined_word
        FUNC_TYPE(undefined_word)
undefined_word:
        bl      err_name
        mov     x0, #ERR_UNDEFINED_WORD
        b       machine_error
        FUNC_SIZE(undefined_word)

        .globl  machine_error
        FUNC_TYPE(machine_error)
machine_error:
        ldr     x9, [UP, #UV_ABORT]
        br      x9
        FUNC_SIZE(machine_error)

// Reading a file.
//
// The four routines below are the ones that reach libc, as read_line and
// write_stdout are; the words that call them are in src/words/file.S and the
// whole picture is in docs/system/files.md.
//
// A fileid is the descriptor open returned and an ior is an errno, so none of
// these raises: a file word reports what went wrong on the stack and the
// program decides. Nothing here holds a buffer or a position of its own. The
// kernel's file position is the only one there is (ADR 0007).
//
// open, close and access return an int, so their result arrives in w0 and the
// top half of x0 is undefined. Each is sign-extended with sxtw before anything
// compares it against -1, because the two platforms leave different rubbish up
// there: macOS happened to sign-extend and Linux zeroed, which made a failed
// access read as 4294967295 rather than -1. read and lseek need none of this,
// returning ssize_t and off_t, which fill the register.

// The last errno. What a file word hands back as its ior.
        .p2align        2
        .globl  errno_value
        FUNC_TYPE(errno_value)
errno_value:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        bl      ERRNO_FN
        ldr     w0, [x0]
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(errno_value)

// Open the file named by the string at x0, x1 bytes long, with the flag word in
// x2. Returns the descriptor in x0 and an ior in x1, or -1 and the errno.
//
// The name is copied into this frame and terminated there, because open takes a
// C string and a Forth string has no terminator after it. A name too long for
// the frame is ENAMETOOLONG without asking the kernel.
//
// open is the first variadic libc function aforth calls, and it is safe to call
// because only its two named arguments are passed. Apple's ABI puts a variadic
// argument on the stack and the Linux AAPCS puts it in a register, so a call
// that passed one would need different code per platform; a call that passes
// none is the same instruction sequence on both. See docs/system/files.md.
        .p2align        2
        .globl  file_open
        FUNC_TYPE(file_open)
file_open:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        sub     sp, sp, #PATH_BUF
        str     x2, [x29, #16]          // the flag word, across the copy
        mov     x2, sp                  // the frame's own buffer
        bl      path_copy
        cbnz    x0, fo_name

        mov     x0, sp
        ldr     x1, [x29, #16]
        bl      CSYM(open)
        sxtw    x0, w0                  // an int, so only w0 is meaningful
        cmn     x0, #1
        b.eq    fo_failed
        mov     x1, #0
        b       fo_done

fo_failed:
        bl      errno_value
        mov     x1, x0
        mov     x0, #-1
        b       fo_done

fo_name:
        mov     x1, x0                  // ENAMETOOLONG
        mov     x0, #-1

fo_done:
        add     sp, sp, #PATH_BUF
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(file_open)

// Copy the string at x0, x1 bytes long, to the buffer at x2 and terminate it
// there. Returns 0, or ENAMETOOLONG when the name does not fit PATH_BUF.
//
// Both open and access take a C string, and a Forth string has no terminator
// after it. The caller carves the buffer in its own frame; this only fills it.
        .p2align        2
        .globl  path_copy
        FUNC_TYPE(path_copy)
path_copy:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        cmp     x1, #(PATH_BUF - 1)
        b.hi    pc_too_long

        str     x1, [sp, #16]           // the length, across the call
        mov     x3, x0                  // the name
        mov     x0, x2                  // where it goes
        mov     x2, x1                  // how many bytes
        mov     x1, x3
        bl      CSYM(memcpy)
        ldr     x1, [sp, #16]
        strb    wzr, [x0, x1]           // memcpy hands the destination back
        mov     x0, #0
        ldp     x29, x30, [sp], #32
        ret

pc_too_long:
        mov     x0, #ENAMETOOLONG
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(path_copy)

// Is the file named by the string at x0, x1 bytes long, there? Returns an ior
// in x0, which is 0 when it is.
//
// access asks the one question FILE-STATUS has to answer and needs no struct
// stat, whose layout differs between the platforms.
        .p2align        2
        .globl  file_status
        FUNC_TYPE(file_status)
file_status:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        sub     sp, sp, #PATH_BUF
        mov     x2, sp
        bl      path_copy
        cbnz    x0, fst_done            // ENAMETOOLONG is the ior

        mov     x0, sp
        mov     x1, #0                  // F_OK: is it there at all
        bl      CSYM(access)
        sxtw    x0, w0
        cmn     x0, #1
        b.ne    fst_done                // 0, and so the ior
        bl      errno_value

fst_done:
        add     sp, sp, #PATH_BUF
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(file_status)

// Read x2 bytes from descriptor x0 into x1. Returns how many in x0 and an ior
// in x1.
//
// read is called again until the buffer is full or it returns 0, so fewer bytes
// than asked for means the file ended rather than that one read came up short.
// READ-LINE depends on that: a short read with no newline in it would otherwise
// look like an unterminated last line.
        .p2align        2
        .globl  file_read
        FUNC_TYPE(file_read)
file_read:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]       // the descriptor and the buffer
        stp     x2, xzr, [sp, #32]      // how many are wanted, and how many so far

1:      ldp     x2, x3, [sp, #32]
        subs    x2, x2, x3              // how many are still wanted
        b.ls    fr_done
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #24]
        add     x1, x1, x3
        bl      CSYM(read)
        cmn     x0, #1
        b.eq    fr_failed
        cbz     x0, fr_done             // the file ended
        ldr     x3, [sp, #40]
        add     x3, x3, x0
        str     x3, [sp, #40]
        b       1b

fr_done:
        ldr     x0, [sp, #40]
        mov     x1, #0
        ldp     x29, x30, [sp], #48
        ret

fr_failed:
        bl      errno_value
        mov     x1, x0
        ldr     x0, [sp, #40]           // whatever arrived before the error
        ldp     x29, x30, [sp], #48
        ret
        FUNC_SIZE(file_read)

// Move descriptor x0 by the offset in x1, measured from x2. Returns the new
// position in x0 and an ior in x1.
        .p2align        2
        .globl  file_seek
        FUNC_TYPE(file_seek)
file_seek:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        bl      CSYM(lseek)
        cmn     x0, #1
        b.eq    fs_failed
        mov     x1, #0
        ldp     x29, x30, [sp], #16
        ret

fs_failed:
        bl      errno_value
        mov     x1, x0
        mov     x0, #-1
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(file_seek)

// Close descriptor x0. Returns an ior in x0.
        .p2align        2
        .globl  file_close
        FUNC_TYPE(file_close)
file_close:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        bl      CSYM(close)
        sxtw    x0, w0
        cmn     x0, #1
        b.eq    fc_failed
        mov     x0, #0
        ldp     x29, x30, [sp], #16
        ret

fc_failed:
        bl      errno_value
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(file_close)

// The two paths cold start reads.
//
// Neither is opened here: these only build a name, and cold_start in
// src/aforth.S decides what to do with it. Each fills a buffer the caller
// carves, PATH_BUF bytes long, the way path_copy does, and returns the length
// or -1. See docs/system/startup.md.
        exec_path_raw_def

// The path of the running executable, resolved. Returns its length in x0, or
// -1 when the platform would not say.
//
// realpath runs on both platforms although only macOS needs it: it is what
// makes ./build/aforth answer as an absolute path, and what makes an installed
// binary reached through a symlink look for its system file beside the real one
// rather than beside the link. Linux resolves /proc/self/exe already, so there
// it costs one call and changes nothing.
//
// realpath wants somewhere at least PATH_MAX bytes long, which PATH_BUF is on
// both platforms: 1024 on macOS and 4096 on Linux.
        .p2align        2
        .globl  exec_path
        FUNC_TYPE(exec_path)
exec_path:                              // x0 buffer -> x0 length, or -1
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        sub     sp, sp, #PATH_BUF
        str     x0, [x29, #16]          // where the answer goes

        mov     x0, sp                  // the path as the process was invoked
        mov     x1, #PATH_BUF
        bl      exec_path_raw
        cmn     x0, #1
        b.eq    ep_failed

        mov     x0, sp
        ldr     x1, [x29, #16]
        bl      CSYM(realpath)
        cbz     x0, ep_failed
        bl      CSYM(strlen)
        b       ep_done

ep_failed:
        mov     x0, #-1

ep_done:
        add     sp, sp, #PATH_BUF
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(exec_path)

// Append the NUL-terminated string at x1 to the buffer at x0, which holds x2
// bytes already, and terminate it. Returns the new length, or -1 when the
// result would not fit PATH_BUF.
//
// A path is built one piece at a time here rather than with strcat, which would
// walk what is already there again for every piece and would check nothing.
        .p2align        2
        .globl  path_append
        FUNC_TYPE(path_append)
path_append:                            // x0 buffer, x1 string, x2 length
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]       // the buffer and what goes on the end
        str     x2, [sp, #32]           // what is in the buffer now

        mov     x0, x1
        bl      CSYM(strlen)
        ldr     x2, [sp, #32]
        add     x3, x2, x0
        cmp     x3, #(PATH_BUF - 1)
        b.hi    pa_too_long
        str     x3, [sp, #40]           // what it will be

        add     x2, x0, #1              // the terminator goes with it
        ldp     x0, x1, [sp, #16]
        ldr     x3, [sp, #32]
        add     x0, x0, x3              // one past what is there
        bl      CSYM(memcpy)
        ldr     x0, [sp, #40]
        b       pa_done

pa_too_long:
        mov     x0, #-1

pa_done:
        ldp     x29, x30, [sp], #48
        ret
        FUNC_SIZE(path_append)

// The system file that ships with aforth: the directory the binary is in, and
// aforth.f. Returns its length in x0, or -1.
//
// Beside the binary rather than in the working directory, so that a session
// started anywhere has the same dictionary, and so that build/aforth finds
// build/aforth.f while an installed binary finds its own neighbour. It is never
// read from the current directory, which ADR 0003 forbids for the user's file
// and which would be no safer for this one.
        .p2align        2
        .globl  system_file_path
        FUNC_TYPE(system_file_path)
system_file_path:                       // x0 buffer -> x0 length, or -1
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]

        bl      exec_path
        cmn     x0, #1
        b.eq    sfp_failed

        // Back over the last component, keeping the slash. A path with no
        // slash in it at all leaves 0, and the name is then relative to the
        // working directory, which is the best that can be said about it.
        ldr     x1, [sp, #16]
        mov     x2, x0
1:      cbz     x2, 2f
        sub     x3, x2, #1
        ldrb    w4, [x1, x3]
        cmp     w4, #47                 // a slash
        b.eq    2f
        mov     x2, x3
        b       1b

        // x2 is the length of the directory part, which is what path_append
        // wants as the length already in the buffer.
2:      mov     x0, x1
        adr_sym x1, str_system_file
        bl      path_append
        b       sfp_done

sfp_failed:
        mov     x0, #-1

sfp_done:
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(system_file_path)

// The user's own init file: $XDG_CONFIG_HOME/aforth/init.f, or
// $HOME/.config/aforth/init.f when that variable is unset or empty. Returns its
// length in x0, or -1 when neither variable says where the user's files are.
//
// One path on both platforms, which is what ADR 0003 decided: a terminal
// program gains nothing from ~/Library/Application Support on macOS, and the
// XDG directory leaves room for the files that come later.
        .p2align        2
        .globl  user_init_path
        FUNC_TYPE(user_init_path)
user_init_path:                         // x0 buffer -> x0 length, or -1
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]

        adr_sym x0, str_xdg_config_home
        bl      CSYM(getenv)
        cbz     x0, uip_home
        ldrb    w1, [x0]
        cbz     w1, uip_home            // set to nothing is as good as unset

        mov     x1, x0
        ldr     x0, [sp, #16]
        mov     x2, #0
        bl      path_append
        b       uip_tail

uip_home:
        adr_sym x0, str_home
        bl      CSYM(getenv)
        cbz     x0, uip_failed
        ldrb    w1, [x0]
        cbz     w1, uip_failed

        mov     x1, x0
        ldr     x0, [sp, #16]
        mov     x2, #0
        bl      path_append
        cmn     x0, #1
        b.eq    uip_failed

        mov     x2, x0
        ldr     x0, [sp, #16]
        adr_sym x1, str_dot_config
        bl      path_append

uip_tail:
        cmn     x0, #1
        b.eq    uip_failed
        mov     x2, x0
        ldr     x0, [sp, #16]
        adr_sym x1, str_init_file
        bl      path_append
        b       uip_done

uip_failed:
        mov     x0, #-1

uip_done:
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(user_init_path)

// Write x1 bytes at x0 to file descriptor 1.
//
// Every byte aforth prints leaves through here, EMIT and TYPE and the banner
// alike. write is unbuffered, so there is no flushing rule and no question of
// what order a terminal and a pipe see things in: one call, one write, in the
// order the words made them. See docs/system/output.md.
        .p2align        2
        .globl  write_stdout
        FUNC_TYPE(write_stdout)
write_stdout:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x2, x1                  // length
        mov     x1, x0                  // buffer
        mov     x0, #1                  // fd
        bl      CSYM(write)
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(write_stdout)

// Write the NUL-terminated string at x0 to file descriptor 1, then a newline.
//
// What puts did, on aforth's own output path rather than through stdio: a
// buffered banner and an unbuffered number would reach a pipe in the wrong
// order. The newline byte is written from the stack, which is where the words
// that print one character build theirs too.
        .p2align        2
        .globl  puts_stdout
        FUNC_TYPE(puts_stdout)
puts_stdout:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]
        bl      CSYM(strlen)
        mov     x1, x0                  // length
        ldr     x0, [sp, #16]           // buffer
        bl      write_stdout
        mov     w1, #10
        strb    w1, [sp, #24]
        add     x0, sp, #24
        mov     x1, #1
        bl      write_stdout
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(puts_stdout)

// Write x0 spaces to file descriptor 1, and nothing at all when x0 is zero or
// less.
//
// A run per call rather than a byte per call, which is what SPACES needs: .R
// pads a number to its field width through it, and one write costs about 341 ns
// on macOS against 0.45 ns for a word dispatched. The bytes come from a
// constant run rather than a buffer, so aforth still holds no output of its own
// and ADR 0007 still stands. See docs/system/benchmark.md.
//
// The count crosses the write on the stack rather than in a register, as
// write_stderr's pointer does, so this clobbers nothing a caller might be
// keeping in x27 or x28.
        .p2align        2
        .globl  write_spaces
        FUNC_TYPE(write_spaces)
write_spaces:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]           // the count crosses the call here
1:      ldr     x2, [sp, #16]
        cmp     x2, #0
        b.le    2f
        mov     x1, #SPACES_RUN
        cmp     x2, x1
        csel    x1, x2, x1, lt          // the last run is the short one
        sub     x2, x2, x1
        str     x2, [sp, #16]
        adr_sym x0, spaces_run
        bl      write_stdout
        b       1b
2:      ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(write_spaces)

// Read one line into the caller's buffer.
//
// x0 the buffer, x1 how many bytes it holds, x2 nonzero to put the line in the
// history. Returns the line's length in x0, which may be more than the buffer
// took, or -1 at end of input.
//
// readline does the editing, the history and the terminal handling, and it
// returns lines unedited when stdin is not a terminal, so one routine serves
// the prompt and a piped script alike (ADR 0001). The line comes back malloc'd
// and is freed here, and it carries no newline.
//
// The untruncated length is what comes back, so that REFILL can tell a line
// longer than the input buffer from one that just fills it.
        .p2align        2
        .globl  read_line
        FUNC_TYPE(read_line)
read_line:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        str     x0, [sp, #16]           // the caller's buffer
        str     x1, [sp, #24]           // how much of it there is
        str     x2, [sp, #32]           // whether the user typed this

        adr_sym x0, str_empty
        bl      CSYM(readline)
        cbz     x0, rl_eof
        str     x0, [sp, #40]           // the line, to copy and to free

        bl      CSYM(strlen)
        str     x0, [sp, #48]           // its length, before any truncation

        ldr     x2, [sp, #24]
        cmp     x0, x2
        csel    x2, x0, x2, lo          // copy whichever is shorter
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #40]
        bl      CSYM(memcpy)

        ldr     x0, [sp, #32]
        cbz     x0, rl_no_history
        ldr     x0, [sp, #48]
        cbz     x0, rl_no_history       // an empty line is not worth recalling
        ldr     x0, [sp, #40]
        bl      CSYM(add_history)

rl_no_history:
        ldr     x0, [sp, #40]
        bl      CSYM(free)
        ldr     x0, [sp, #48]
        ldp     x29, x30, [sp], #64
        ret

rl_eof:
        mov     x0, #-1
        ldp     x29, x30, [sp], #64
        ret
        FUNC_SIZE(read_line)

// Read one byte, which is the character KEY returns. Returns it in x0, or -1
// at end of input.
//
// The terminal is put in raw mode for the read and put back afterwards, so the
// byte arrives on the keystroke and is not echoed. tcgetattr fails when stdin
// is not a terminal, and this is then one read of one byte, which is what a
// piped script wants.
//
// The frame holds the byte at 16, the saved settings at 32 and the raw ones at
// 112, which leaves room for the larger of the two platforms' structs.
        .p2align        2
        .globl  read_byte
        FUNC_TYPE(read_byte)
read_byte:
        stp     x29, x30, [sp, #-192]!
        mov     x29, sp

        mov     x0, #0                  // fd 0
        add     x1, sp, #32
        bl      CSYM(tcgetattr)
        cbnz    w0, rb_plain            // an int: only w0 is meaningful

        add     x0, sp, #112
        add     x1, sp, #32
        mov     x2, #TERMIOS_SIZE
        bl      CSYM(memcpy)

        // Four bytes of c_lflag, which is where both bits live on either
        // platform. See src/include/platform.h.
        ldr     w1, [sp, #(112 + TERMIOS_LFLAG_OFF)]
        mov     w2, #(T_ICANON | T_ECHO)
        bic     w1, w1, w2
        str     w1, [sp, #(112 + TERMIOS_LFLAG_OFF)]

        mov     x0, #0
        mov     x1, #0                  // TCSANOW
        add     x2, sp, #112
        bl      CSYM(tcsetattr)

        mov     x0, #0
        add     x1, sp, #16
        mov     x2, #1
        bl      CSYM(read)
        str     x0, [sp, #24]           // the result, across the restore

        mov     x0, #0
        mov     x1, #0
        add     x2, sp, #32             // the settings the terminal arrived in
        bl      CSYM(tcsetattr)

        ldr     x0, [sp, #24]
        b       rb_done

rb_plain:
        mov     x0, #0
        add     x1, sp, #16
        mov     x2, #1
        bl      CSYM(read)

rb_done:
        cmp     x0, #1
        b.ne    rb_eof
        ldrb    w0, [sp, #16]
        ldp     x29, x30, [sp], #192
        ret

rb_eof:
        mov     x0, #-1
        ldp     x29, x30, [sp], #192
        ret
        FUNC_SIZE(read_byte)

// Write a NUL-terminated message to file descriptor 2.
//
// fd 2 rather than fputs to stderr, because stderr is a libc variable whose
// symbol differs between the platforms: __stderrp on macOS, stderr on Linux.
//
// The pointer crosses the strlen call on the stack rather than in x27, so that
// this clobbers nothing a caller might be keeping. x27 and x28 are the two
// registers a word may use across a libc call, and a callee that took one of
// them would make that promise worthless.
        .p2align        2
        .globl  write_stderr
        FUNC_TYPE(write_stderr)
write_stderr:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]
        bl      CSYM(strlen)
        mov     x2, x0                  // length
        ldr     x1, [sp, #16]           // buffer
        mov     x0, #2                  // fd
        bl      CSYM(write)
        ldp     x29, x30, [sp], #32
        ret
        FUNC_SIZE(write_stderr)
