/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Johan Dykström */

/*
 * aforth entry point.
 *
 * Entry is main, not _start: the C runtime initialises libc before calling it,
 * and the design goals put libc ahead of raw syscalls for portability.
 */

#include "platform.h"

        SECTION_RODATA
        .p2align        3
banner:
        .asciz  "aforth 0.0.0"

        .text
        .p2align        2
        .globl  CSYM(main)
        FUNC_TYPE(CSYM(main))
CSYM(main):
        /* Save the frame pointer and return address. sp stays 16-byte aligned. */
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp

        adr_sym x0, banner
        bl      CSYM(puts)

        mov     w0, #0                  /* exit status */
        ldp     x29, x30, [sp], #16
        ret
        FUNC_SIZE(CSYM(main))
