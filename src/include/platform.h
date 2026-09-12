// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Johan Dykström

// Platform differences between macOS/ARM64 and Linux/ARM64.
//
// Every .S file includes this header instead of writing platform-specific
// directives inline. The C preprocessor resolves the differences at build
// time, which is why sources use the .S extension: clang runs cpp on .S but
// not on .s.

#ifndef AFORTH_PLATFORM_H
#define AFORTH_PLATFORM_H

// C symbol names. The Mach-O toolchain prefixes C symbols with an underscore;
// ELF does not. Write bl CSYM(puts), never bl puts.
#if defined(__APPLE__)
#  define CSYM(name) _##name
#else
#  define CSYM(name) name
#endif

// Read-only data. Mach-O has no .rodata section.
#if defined(__APPLE__)
#  define SECTION_RODATA .section __TEXT,__const
#else
#  define SECTION_RODATA .section .rodata
#endif

// Symbol metadata. ELF only; the Mach-O assembler rejects these directives.
#if defined(__APPLE__)
#  define FUNC_TYPE(name)
#  define FUNC_SIZE(name)
#else
#  define FUNC_TYPE(name) .type name, %function
#  define FUNC_SIZE(name) .size name, . - name
#endif

// mmap flags for one private anonymous mapping. The two platforms number the
// anonymous flag differently: MAP_ANON is 0x1000 on macOS, MAP_ANONYMOUS is
// 0x20 on Linux, and MAP_PRIVATE is 0x2 on both. PROT_READ|PROT_WRITE is 3 on
// both, so it needs no macro here.
#if defined(__APPLE__)
#  define MMAP_FLAGS 0x1002
#else
#  define MMAP_FLAGS 0x22
#endif

// setlocale's category numbers differ: LC_CTYPE is the third constant on macOS
// and the first on Linux. aforth calls setlocale(LC_CTYPE, "") at start-up
// (ADR 0004), so it needs the right number for the platform it is built on.
#if defined(__APPLE__)
#  define LC_CTYPE 2
#else
#  define LC_CTYPE 0
#endif

// struct termios, which KEY puts in raw mode for one read.
//
// The struct differs in both size and layout. macOS gives each flag field 8
// bytes, so c_lflag sits at offset 24; Linux gives them 4, so it sits at 12.
// The two bits KEY clears are numbered differently as well: ICANON makes the
// terminal wait for a whole line and ECHO makes it print what was typed.
//
// TCSANOW is 0 on both platforms, so it is written as 0 at the call.
//
// c_lflag is read and written as four bytes on both platforms. On macOS that
// touches the low half of an eight-byte field, which is where both bits live,
// and ARM64 is little-endian on both targets.
#if defined(__APPLE__)
#  define TERMIOS_SIZE       72
#  define TERMIOS_LFLAG_OFF  24
#  define T_ICANON           0x100
#  define T_ECHO             0x8
#else
#  define TERMIOS_SIZE       60
#  define TERMIOS_LFLAG_OFF  12
#  define T_ICANON           0x2
#  define T_ECHO             0x8
#endif

// Load the address of a local symbol into a register, position-independent.
// The two toolchains spell the low-bits relocation differently.
.macro  adr_sym reg, sym
#if defined(__APPLE__)
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
#else
        adrp    \reg, \sym
        add     \reg, \reg, :lo12:\sym
#endif
.endm

// Mark the stack non-executable. ELF only.
#if !defined(__APPLE__)
        .section .note.GNU-stack,"",%progbits
#endif

#endif // AFORTH_PLATFORM_H
