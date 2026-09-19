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

// errno, which a file word reports as its ior.
//
// It is a macro over a function that hands back a pointer to the int, and the
// function differs: __error on macOS, __errno_location on Linux. The assembler
// symbol is spelled out here rather than written through CSYM, because CSYM
// pastes its argument and would not expand a macro handed to it.
#if defined(__APPLE__)
#  define ERRNO_FN ___error
#else
#  define ERRNO_FN __errno_location
#endif

// The two errno values aforth produces itself instead of reading one back from
// libc: a path too long to copy before open sees it, and a file position no
// off_t could hold.
//
// Only the first differs between the platforms, as ICANON above does. EINVAL is
// 22 on both, and so are the two the file cases assert as plain numbers, ENOENT
// at 2 and EBADF at 9. It is named here anyway, beside the one it is used with.
#if defined(__APPLE__)
#  define ENAMETOOLONG 63
#else
#  define ENAMETOOLONG 36
#endif
#define EINVAL 22

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

// The path of the running executable, which cold start needs to find the
// system file beside the binary rather than in the working directory.
//
// This is the one difference the init files add, and it is a whole routine
// rather than a constant, so the macro defines the routine and src/machine.S
// instantiates it once in its text section. A second instantiation would be a
// duplicate symbol, which is the right way to be told about it.
//
// exec_path_raw takes a buffer in x0 and its size in x1, terminates the path in
// it, and returns 0 or -1. The two platforms answer differently in both shape
// and quality: macOS hands back the path as the process was invoked, so it may
// be relative or run through a symlink, while Linux resolves /proc/self/exe
// already. exec_path in src/machine.S puts both through realpath so that the
// caller sees one kind of answer.
//
// _NSGetExecutablePath returns an int and takes its buffer size as a pointer to
// a uint32_t, which is why the size is stored as a word. readlink returns an
// ssize_t and writes no terminator, so this one adds it.
.macro  exec_path_raw_def
#if defined(__APPLE__)
        .p2align        2
exec_path_raw:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     w1, [sp, #16]           // the size, as the uint32_t it takes
        add     x1, sp, #16
        bl      CSYM(_NSGetExecutablePath)
        sxtw    x0, w0                  // an int, so only w0 is ours
        ldp     x29, x30, [sp], #32
        ret
#else
        SECTION_RODATA
        .p2align        3
exec_path_link:
        .asciz  "/proc/self/exe"

        .text
        .p2align        2
exec_path_raw:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x0, [sp, #16]           // the buffer, across the call
        sub     x2, x1, #1              // room for the terminator
        mov     x1, x0
        adr_sym x0, exec_path_link
        bl      CSYM(readlink)
        cmp     x0, #0
        b.le    1f                      // -1, or a link with nothing in it
        ldr     x1, [sp, #16]
        strb    wzr, [x1, x0]
        mov     x0, #0
        b       2f
1:      mov     x0, #-1
2:      ldp     x29, x30, [sp], #32
        ret
#endif
.endm

// Mark the stack non-executable. ELF only.
#if !defined(__APPLE__)
        .section .note.GNU-stack,"",%progbits
#endif

#endif // AFORTH_PLATFORM_H
