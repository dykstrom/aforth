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

// setlocale's second argument: the empty string, which means take the locale
// from the environment.
locale_from_env:
        .asciz  ""

        .text
        .p2align        2
        .globl  CSYM(main)
        FUNC_TYPE(CSYM(main))
CSYM(main):
        // Save the frame pointer, the return address, and x19 to x28. The C
        // runtime called us and expects those ten back; machine_init hands
        // eight of them to the Forth machine. Six pairs is 96 bytes, so sp
        // stays 16-byte aligned.
        stp     x29, x30, [sp, #-96]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]

        // Before anything touches text, and before libedit is first called:
        // without it the process runs in the C locale and line editing treats
        // each byte of a multi-byte character as one character (ADR 0004).
        mov     w0, #LC_CTYPE
        adr_sym x1, locale_from_env
        bl      CSYM(setlocale)

        bl      machine_init
        cbz     x0, main_failed         // it already reported why

        // Every word gets its cases run before aforth says anything at all.
        // A failure reports the word and exits, so silence here is a pass.
        adr_sym x0, word_tests
        bl      machine_test_words
#ifndef AFORTH_NO_STACK_CHECKS
        adr_sym x0, word_guards
        bl      machine_test_guards
#endif

        adr_sym x0, banner
        bl      puts_stdout

        // The outer interpreter reads and runs Forth until end of input. BYE
        // ends the process from inside it, so this returns only when the input
        // runs out.
        bl      machine_quit

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
        ldp     x29, x30, [sp], #96
        ret
        FUNC_SIZE(CSYM(main))
