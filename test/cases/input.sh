# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The input words.
#
# These four read the line the case itself is written on, or the line after it,
# so a case here is written knowing what the suite pipes in. The old in-binary
# table could not hold a case for any of them: it ran before the outer
# interpreter, so a case that read input ate a line of the script.
# See docs/system/input.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

# SOURCE reports the line being interpreted, which is this case's own source.
prints "SOURCE gives the line"     'SOURCE TYPE'     'SOURCE TYPE ok'
prints "SOURCE gives its length"   'SOURCE NIP .'    '12  ok'

# >IN is how far the parser has gone. The name after it has been parsed by the
# time the word runs, so the offset is past that name as well.
prints ">IN is the parse offset"   '>IN @ .'         '6  ok'
prints ">IN advances along the line" '>IN @ . >IN @ .' '6 14  ok'

# REFILL replaces the line it was called from and puts >IN back to its start,
# so the rest of the line it ran on never runs and the next line runs instead.
prints "REFILL reads the next line" '1 REFILL
.S' '<2> 1 -1  ok'
prints "REFILL drops the rest of its own line" 'REFILL 99 .
42 .' '42  ok'

# At end of input REFILL has nothing to read and the session ends, so the false
# flag it leaves cannot be printed. That the word after it never runs is what
# says the flag was false.
prints "REFILL at end of input ends the session" 'REFILL 99 .' ' ok'

# ACCEPT reads a line into the caller's buffer and reports how many bytes it
# took. The count is printed beside the bytes, because a shell drops a NUL out
# of a captured line and bytes alone would not show a truncation.
prints "ACCEPT takes a line" \
  'BL WORD xxxxxxxxxx DUP DUP 10 ACCEPT DUP >R TYPE SPACE R> .
hello' 'hello 5  ok'
prints "ACCEPT truncates to its count" \
  'BL WORD xxxxxxxxxx DUP DUP 3 ACCEPT DUP >R TYPE SPACE R> .
hello' 'hel 3  ok'

# KEY takes one byte and leaves the rest of the line, so the empty remainder of
# that line is interpreted next and reports ok of its own.
prints "KEY takes one byte" 'KEY .
Z' '90  ok
 ok'

# The input source stack.
#
# A string installed by EVALUATE is the source these cases nest, so they are
# also what covers the stack itself: what SOURCE and REFILL say while a string
# is being read, and that the line underneath survives. A file source is
# covered in test/cases/file.sh. See docs/system/input.md.

prints "EVALUATE interprets a string" 'S" 1 2 +" EVALUATE .' '3  ok'

# The case the re-entrant aforth_enter exists for. EVALUATE has to interpret
# and return, so that the . after it in the definition still runs.
prints "EVALUATE runs inside a definition" ': F S" 1 2 +" EVALUATE . ;
F' ' ok
3  ok'

# A string being interpreted can interpret another. Two definitions rather than
# one line, because S" ends at the first quote and cannot hold another.
prints "EVALUATE nests" ': INNER S" 2 3 *" EVALUATE ;
: OUTER S" INNER" EVALUATE ;
OUTER .' ' ok
 ok
6  ok'

# The line EVALUATE was on carries on where it left off, which is what says the
# source was put back rather than abandoned.
prints "the line under EVALUATE survives" 'S" 1" EVALUATE . 99 .' '1 99  ok'

prints "SOURCE-ID is 0 at the terminal" 'SOURCE-ID .' '0  ok'
prints "SOURCE-ID is -1 in a string" 'S" SOURCE-ID ." EVALUATE' '-1  ok'

# SOURCE reports the string, not the line underneath it. The string is 12
# bytes and the line it is written on is longer, so the number says which.
prints "SOURCE reports the string" 'S" SOURCE NIP ." EVALUATE' '12  ok'

# Forth-2012 asks REFILL to return false for a string and do nothing else. The
# second number says it did nothing else: the string is still there to parse.
prints "REFILL is false in a string" 'S" REFILL ." EVALUATE' '0  ok'
prints "REFILL leaves a string alone" 'S" REFILL DROP 7 ." EVALUATE' '7  ok'

# An empty string has nothing to interpret and is not an error.
prints "EVALUATE takes the empty string" 'S" " EVALUATE 42 .' '42  ok'
