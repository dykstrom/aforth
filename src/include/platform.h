/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Johan Dykström */

/*
 * Platform differences between macOS/ARM64 and Linux/ARM64.
 *
 * Every .S file includes this header instead of writing platform-specific
 * directives inline. The C preprocessor resolves the differences at build
 * time, which is why sources use the .S extension: clang runs cpp on .S but
 * not on .s.
 */

#ifndef AFORTH_PLATFORM_H
#define AFORTH_PLATFORM_H

/*
 * C symbol names. The Mach-O toolchain prefixes C symbols with an underscore;
 * ELF does not. Write bl CSYM(puts), never bl puts.
 */
#if defined(__APPLE__)
#  define CSYM(name) _##name
#else
#  define CSYM(name) name
#endif

/* Read-only data. Mach-O has no .rodata section. */
#if defined(__APPLE__)
#  define SECTION_RODATA .section __TEXT,__const
#else
#  define SECTION_RODATA .section .rodata
#endif

/* Symbol metadata. ELF only; the Mach-O assembler rejects these directives. */
#if defined(__APPLE__)
#  define FUNC_TYPE(name)
#  define FUNC_SIZE(name)
#else
#  define FUNC_TYPE(name) .type name, %function
#  define FUNC_SIZE(name) .size name, . - name
#endif

/*
 * Load the address of a local symbol into a register, position-independent.
 * The two toolchains spell the low-bits relocation differently.
 */
.macro  adr_sym reg, sym
#if defined(__APPLE__)
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
#else
        adrp    \reg, \sym
        add     \reg, \reg, :lo12:\sym
#endif
.endm

/* Mark the stack non-executable. ELF only. */
#if !defined(__APPLE__)
        .section .note.GNU-stack,"",%progbits
#endif

#endif /* AFORTH_PLATFORM_H */
