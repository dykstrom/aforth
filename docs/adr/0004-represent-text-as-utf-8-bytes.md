# 0004. Represent text as UTF-8 bytes

*2026-09-06*

## Context

Users expect a modern language system to accept UTF-8: pasted text, string literals, and definition
names outside ASCII. Forth-2012 separates a primitive character, which is one address unit and what
`C@`, `C!`, and `CHARS` operate on, from an extended character, which is one code point and may
occupy several primitive characters. It also defines an optional Extended Characters word set
(`XC@+`, `XC-SIZE`, `XC-WIDTH`, `XEMIT`, `XKEY` and others) for variable-width encodings. The
alternative was to make one character a fixed-width code point, storing text as UTF-32 internally.
That would break `C@` over file and network bytes, multiply storage for mostly-ASCII source, and
diverge from the byte-oriented words the standard already defines. UTF-8 is self-synchronizing —
no byte of a multi-byte sequence is ever an ASCII byte — so a byte-oriented parser and dictionary
lookup stay correct with no change.

## Decision

We will treat one character as one byte and hold all text as UTF-8-encoded byte sequences. `TYPE`,
`S"`, the parser, and dictionary name lookup stay byte-oriented and carry no UTF-8 knowledge. Case
folding for name lookup covers ASCII `A`-`Z` only; bytes of 0x80 and above are left alone. aforth
calls `setlocale(LC_CTYPE, "")` at start-up, before initialising line editing. The Extended
Characters word set is deferred; when it is implemented it will be an optional extension declared
through `ENVIRONMENT?`.

## Consequences

UTF-8 text passes through `EMIT`, `TYPE`, and `S"` unchanged, non-ASCII definition names work by
byte comparison, and none of this costs code in the parser. aforth is a conforming Forth-2012
system without the Extended Characters word set, so deferring it is not a standards gap.

Display width stops matching byte count, and it does not match code-point count either: East Asian
characters occupy two terminal cells and combining marks occupy none. Any output alignment that
counts bytes is wrong for non-ASCII text, and correcting it needs `XC-WIDTH` and Unicode tables.
This is the one part of UTF-8 support that is real work, and it is deferred with the rest of the
word set. Until then, `KEY` returns a single byte, so a multi-byte character arrives over several
calls, and `CHAR` and `[CHAR]` yield one byte rather than one code point.

The `setlocale` call is required, not optional: without it the process runs in the C locale, libedit
treats each byte as a character, and backspace over a multi-byte character deletes one byte and
leaves an invalid sequence. libedit's handling of multi-byte input is less proven than GNU
readline's, though Apple's build exports the wide-character API, and this can only be confirmed on a
real terminal once line editing exists. aforth will not normalize or collate text: `é` written as
one code point and as `e` plus a combining accent stay different strings.
