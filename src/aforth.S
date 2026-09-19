// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// aforth entry point.
//
// Entry is main, not _start: the C runtime initialises libc before calling it,
// and the design goals put libc ahead of raw syscalls for portability.
//
// Both lines below go out through puts_stdout rather than puts, because every
// byte aforth prints leaves by one unbuffered path: a banner held in a stdio
// buffer would reach a pipe after the output words had already written theirs.

#include "machine.h"

        SECTION_RODATA
        .p2align        3
banner:
        .asciz  "aforth 0.0.0"

// What --help prints, after the banner above: the version is written in one
// place and this carries the rest.
//
// The line breaks are in the string. puts_stdout appends exactly one newline
// after whatever it is given, which is the one this ends with, so the block
// ends without its own.
//
// It names the init path because both init flags are described in terms of
// "the user's init.f", which means nothing on its own. The path is the one
// user_init_path in src/machine.S builds, and the two have to agree.
//
// One source line per printed line, which is what makes the block readable as
// the thing the user sees. Only the last is .asciz: the rest are .ascii, so
// there is one terminator at the end rather than one per line.
help_text:
        .ascii  "\nUsage: aforth [OPTION]...\n\n"
        .ascii  "  --help         show this help and exit\n"
        .ascii  "  --init <file>  read <file> instead of the user's init.f\n"
        .ascii  "  --no-init      do not read the user's init.f\n\n"
        .ascii  "At start-up aforth reads aforth.f from beside the binary, then\n"
        .ascii  "$XDG_CONFIG_HOME/aforth/init.f, or ~/.config/aforth/init.f when\n"
        .asciz  "that variable is unset."

// The flags, and what goes wrong with them. ADR 0003 requires --no-init and
// --init; --help answers for the three.
//
// These are usage errors rather than Forth errors. They happen before the
// machine runs, so none of them goes through machine_error and none has a
// number: main writes the message and exits.
flag_help:
        .asciz  "--help"
flag_no_init:
        .asciz  "--no-init"
flag_init:
        .asciz  "--init"
msg_unknown_arg:
        .asciz  "aforth: unknown argument: "
msg_init_needs_file:
        .asciz  "aforth: --init needs a file\n"
msg_both_flags:
        .asciz  "aforth: --no-init and --init cannot both be given\n"
msg_arg_newline:
        .asciz  "\n"

// setlocale's second argument: the empty string, which means take the locale
// from the environment.
locale_from_env:
        .asciz  ""

        .text

// What args_parse tells main to do next. A flag that is answered in full is
// neither a run nor a failure, so there are three of these rather than two.
#define ARGS_RUN        0       // the command line was read; start the machine
#define ARGS_FAIL       1       // it was wrong, and args_parse has said so
#define ARGS_DONE       2       // it was answered, and there is nothing to run

// Read the command line: argc in w0, argv in x1.
//
// Returns one of the three above, having already written whatever the user
// sees. Nothing here reads a file or the environment — the flags only decide
// what cold start will do, and cold_start below is what does it.
//
// The answer goes in three user variables, so this runs after machine_init:
// the region is the only writable store aforth has. The --init path is not
// copied, because argv lives as long as the process does.
//
// All three are written whatever the arguments say, so a default does not
// depend on the region arriving zeroed.
        .p2align        2
args_parse:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        mov     w2, w0                  // argc is an int, so only w0 is ours
        stp     x2, x1, [sp, #16]       // the count and the vector
        mov     x3, #1                  // argv[0] is the program name
        str     x3, [sp, #32]

        str     xzr, [UP, #UV_INIT_ADDR]
        str     xzr, [UP, #UV_INIT_LEN]
        str     xzr, [UP, #UV_NO_INIT]

ap_next:
        ldp     x2, x1, [sp, #16]
        ldr     x3, [sp, #32]
        cmp     x3, x2
        b.hs    ap_done
        ldr     x0, [x1, x3, lsl #3]    // argv[i]

        adr_sym x1, flag_help
        bl      CSYM(strcmp)
        cbz     w0, ap_help

        ldr     x1, [sp, #24]
        ldr     x3, [sp, #32]
        ldr     x0, [x1, x3, lsl #3]
        adr_sym x1, flag_no_init
        bl      CSYM(strcmp)
        cbz     w0, ap_no_init

        ldr     x1, [sp, #24]
        ldr     x3, [sp, #32]
        ldr     x0, [x1, x3, lsl #3]
        adr_sym x1, flag_init
        bl      CSYM(strcmp)
        cbz     w0, ap_init

        b       ap_unknown

// --help, which is answered where it is found: the arguments after it are
// never looked at, so a line that also holds a mistake still prints the help
// rather than the complaint. Someone asking what the arguments are is the one
// person least helped by being told they got one wrong.
//
// It goes out on file descriptor 1 through puts_stdout, not on 2: this is
// output the user asked for rather than an error, and every byte aforth prints
// leaves by that one path (ADR 0007). The banner is the first line, so the
// version is read from the same string an ordinary run prints.
ap_help:
        adr_sym x0, banner
        bl      puts_stdout
        adr_sym x0, help_text
        bl      puts_stdout
        mov     w0, #ARGS_DONE
        b       ap_return

// --no-init. Giving it with --init is an error rather than a guess about which
// was meant: a run that quietly ignored half of what was asked is how a bug
// report describes something that did not happen.
ap_no_init:
        ldr     x0, [UP, #UV_INIT_LEN]
        cbnz    x0, ap_both
        mov     x0, #-1
        str     x0, [UP, #UV_NO_INIT]
        b       ap_step

// --init, whose path is the argument after it. Given twice, the last one wins.
ap_init:
        ldr     x0, [UP, #UV_NO_INIT]
        cbnz    x0, ap_both
        ldp     x2, x1, [sp, #16]
        ldr     x3, [sp, #32]
        add     x3, x3, #1
        cmp     x3, x2
        b.hs    ap_no_file
        str     x3, [sp, #32]           // the path is taken, so step past it
        ldr     x0, [x1, x3, lsl #3]
        str     x0, [UP, #UV_INIT_ADDR]
        bl      CSYM(strlen)
        str     x0, [UP, #UV_INIT_LEN]

ap_step:
        ldr     x3, [sp, #32]
        add     x3, x3, #1
        str     x3, [sp, #32]
        b       ap_next

ap_done:
        mov     w0, #ARGS_RUN
        b       ap_return

ap_unknown:
        adr_sym x0, msg_unknown_arg
        bl      write_stderr
        ldr     x1, [sp, #24]
        ldr     x3, [sp, #32]
        ldr     x0, [x1, x3, lsl #3]
        bl      write_stderr
        adr_sym x0, msg_arg_newline
        bl      write_stderr
        b       ap_failed

ap_no_file:
        adr_sym x0, msg_init_needs_file
        bl      write_stderr
        b       ap_failed

ap_both:
        adr_sym x0, msg_both_flags
        bl      write_stderr

ap_failed:
        mov     w0, #ARGS_FAIL

ap_return:
        ldp     x29, x30, [sp], #48
        ret

// Report what an init file did, unless it needs no reporting.
//
// 0 is a file that ran to its end, and quit_report would read it as the first
// error number rather than as none. ERR_REPORTED has already printed itself
// with the file and the line the error happened on, and ABORT and QUIT are not
// failures; quit_report drops all three, so only the 0 is tested here.
        .p2align        2
cold_report:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        cbz     x0, 1f
        bl      quit_report
1:      ldp     x29, x30, [sp], #16
        ret

// Cold start: the two files aforth reads before the first prompt.
//
// First the system file that ships with aforth, found beside the binary, and
// then the user's, unless --no-init said not to or --init named another. Each
// is attempted on its own: a failure in the first is reported and the second is
// still tried, because the point is to leave aforth usable at the prompt rather
// than to stop half configured.
//
// The silence rule is one sentence. A file aforth was told to read reports when
// it fails; the one it merely looks for does not. So a user with no init.f sees
// nothing and gets nothing — no message, no exit status, and no directory or
// file made on their behalf, which ADR 0003 requires — while a missing
// aforth.f, an init.f that is there and will not open, and any --init file each
// print a line on file descriptor 2 and leave the prompt to come up anyway.
//
// This runs outside aforth_enter, so it may not raise and may not use a guard
// macro: enter_return would put sp back to a frame that is gone. included_impl
// reports by returning a number instead, which is what cold_report reads. See
// docs/architecture/machine-rules.md, "Leaving the machine".
//
// An error inside an init file leaves both stacks and STATE as they were when
// it unwound. Nothing is done about it here: machine_quit begins by emptying
// the stacks, clearing STATE and dropping every source above the terminal, so
// the first prompt is clean whatever happened.
        .p2align        2
cold_start:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        sub     sp, sp, #PATH_BUF

        mov     x0, sp
        bl      system_file_path
        cmn     x0, #1
        b.eq    cs_no_exec_path
        mov     x1, x0
        mov     x0, sp
        bl      included_impl
        bl      cold_report
        b       cs_user

// The platform would not say where the binary is, so there is no path to name
// in the message. It says that the file could not be opened and nothing more,
// which is all that is known.
cs_no_exec_path:
        mov     x0, #0
        mov     x1, #0
        bl      err_name
        mov     x0, #ERR_OPEN_FAILED
        bl      cold_report

cs_user:
        ldr     x0, [UP, #UV_NO_INIT]
        cbnz    x0, cs_done

        // --init names a file, so a file that will not open is reported: the
        // user asked for that one by name. The address is what says the flag
        // was given, not the length: --init with an empty string after it named
        // a file too, badly, and is better answered than quietly turned into
        // the config file.
        ldr     x0, [UP, #UV_INIT_ADDR]
        cbz     x0, cs_config
        ldr     x1, [UP, #UV_INIT_LEN]
        bl      included_impl
        bl      cold_report
        b       cs_done

// The user's own init.f, which aforth looks for rather than is told to read.
// Not finding one is the ordinary case and says nothing, so the path is asked
// about before it is opened. A file that is there and still will not open is a
// different thing, and included_impl reports it.
cs_config:
        mov     x0, sp
        bl      user_init_path
        cmn     x0, #1
        b.eq    cs_done                 // no XDG_CONFIG_HOME and no HOME
        str     x0, [x29, #16]

        mov     x1, x0
        mov     x0, sp
        bl      file_status
        cbnz    x0, cs_done             // nothing there, so nothing to say

        mov     x0, sp
        ldr     x1, [x29, #16]
        bl      included_impl
        bl      cold_report

cs_done:
        add     sp, sp, #PATH_BUF
        ldp     x29, x30, [sp], #32
        ret

        .p2align        2
        .globl  CSYM(main)
        FUNC_TYPE(CSYM(main))
CSYM(main):
        // Save the frame pointer, the return address, and x19 to x28. The C
        // runtime called us and expects those ten back; machine_init hands
        // eight of them to the Forth machine. Seven pairs is 112 bytes, so sp
        // stays 16-byte aligned, and the last pair holds argc and argv across
        // setlocale and machine_init.
        stp     x29, x30, [sp, #-112]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        stp     x0, x1, [sp, #96]       // argc and argv

        // Before anything touches text, and before libedit is first called:
        // without it the process runs in the C locale and line editing treats
        // each byte of a multi-byte character as one character (ADR 0004).
        mov     w0, #LC_CTYPE
        adr_sym x1, locale_from_env
        bl      CSYM(setlocale)

        bl      machine_init
        cbz     x0, main_failed         // it already reported why

        // After machine_init, because the three user variables it writes are
        // in the region, and the region is what machine_init carves.
        //
        // Three answers, not two: --help is neither a run nor a failure. It has
        // printed what it was asked for, so there is nothing left to do and
        // nothing wrong.
        ldp     x0, x1, [sp, #96]
        bl      args_parse
        cmp     w0, #ARGS_FAIL
        b.eq    main_failed             // it already reported why
        cmp     w0, #ARGS_DONE
        b.eq    main_ok                 // it already printed what was asked

        adr_sym x0, banner
        bl      puts_stdout

        // Before the first prompt and after the banner, so that aforth has
        // said what it is before an init file prints or fails, and so that the
        // banner is the first line on file descriptor 1 whatever an init file
        // does afterwards.
        bl      cold_start

        // The outer interpreter reads and runs Forth until end of input. BYE
        // ends the process from inside it, so this returns only when the input
        // runs out.
        bl      machine_quit

main_ok:
        mov     w0, #0                  // exit status
        b       main_exit

main_failed:
        mov     w0, #1                  // exit status

main_exit:
        ldp     x19, x20, [sp, #16]
        ldp     x21, x22, [sp, #32]
        ldp     x23, x24, [sp, #48]
        ldp     x25, x26, [sp, #64]
        ldp     x27, x28, [sp, #80]
        ldp     x29, x30, [sp], #112
        ret
        FUNC_SIZE(CSYM(main))
