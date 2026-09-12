# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Parsing, name lookup and number conversion.
#
# A case for one of these words is written on the line the word parses, which
# is what the old in-binary table could not do: it ran before the outer
# interpreter and nothing could point SOURCE at a buffer of its own.
# See docs/system/parsing.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

prints "PARSE-NAME cuts a name out" 'PARSE-NAME abc TYPE'  'abc ok'
prints "PARSE-NAME skips leading spaces" 'PARSE-NAME     abc TYPE' 'abc ok'

# At the end of a line there is no name, and the length says so. The length is
# read on the next line, because a length of zero cannot be printed from the
# line that has already been used up.
prints "PARSE-NAME finds nothing at the end of a line" 'PARSE-NAME
NIP .' ' ok
0  ok'

# PARSE takes its delimiter from the stack and skips nothing, which is what
# makes it the word a comment or a string literal is parsed with.
prints "PARSE cuts to the delimiter" 'CHAR ) PARSE this is a comment) TYPE' \
  'this is a comment ok'
prints "PARSE skips no leading delimiter" 'CHAR ) PARSE ) TYPE 65 EMIT' 'A ok'

# WORD copies what it parses to HERE as a counted string, so two calls report
# the same address and the second overwrites the first.
prints "WORD copies a counted string" 'BL WORD hello COUNT TYPE' 'hello ok'
prints "WORD skips leading delimiters" 'BL WORD     hello COUNT TYPE' 'hello ok'
prints "WORD copies to the same place twice" 'BL WORD one BL WORD two = .' '-1  ok'

# COUNT steps past the count byte and reports it: the length, then how far the
# address moved.
prints "COUNT reports the length and steps past it" \
  'BL WORD abc DUP COUNT . SWAP - .' '3 1  ok'

# FIND reports -1 for a word that is not immediate, and the token it reports is
# the one ' gives for the same name.
prints "FIND finds a word"           "BL WORD DUP FIND . ' DUP = ." '-1 -1  ok'
prints "FIND folds case"             "BL WORD dup FIND . ' DUP = ." '-1 -1  ok'
prints "FIND leaves a missing name under a false flag" \
  'BL WORD ZZZ DUP FIND . = .' '0 -1  ok'
prints "FIND walks past a hidden word" \
  'BL WORD (STOP) DUP FIND . = .' '0 -1  ok'

# ' gives the same token every time, and raises rather than handing back a
# token that would fault when it was executed. At the end of a line it has no
# name to give, so its message stops after the word "word".
prints "' gives a token"              "' DUP ' DUP = ."  '-1  ok'
raises "' with no name"               "'"  'aforth: undefined word'

# >NUMBER converts while the characters convert and stops at the first one that
# does not. Each case prints how far the address moved, how many characters are
# left, and the double it accumulated, high half first.
prints ">NUMBER converts every digit" \
  '0 0 PARSE-NAME 123 OVER >R >NUMBER SWAP R> - . . . .' '3 0 0 123  ok'
prints ">NUMBER stops at the first character that is not a digit" \
  '0 0 PARSE-NAME 12x OVER >R >NUMBER SWAP R> - . . . .' '2 1 0 12  ok'
prints ">NUMBER follows BASE" \
  'HEX 0 0 PARSE-NAME FF OVER >R >NUMBER SWAP R> - . . . . DECIMAL' \
  '2 0 0 FF  ok'

# A colon is the character after 9 in ASCII, so subtracting the offset for the
# letters from it gives 3. It is a digit in no base, and this says so.
prints ">NUMBER rejects a colon" \
  'HEX 0 0 PARSE-NAME : OVER >R >NUMBER SWAP R> - . . . . DECIMAL' \
  '0 1 0 0  ok'

# 2^64 in twenty digits: the accumulator leaves one cell, and here the carry
# reaches the high half from the addition of the last digit and nowhere else.
prints ">NUMBER carries into the high half" \
  '0 0 PARSE-NAME 18446744073709551616 OVER >R >NUMBER SWAP R> - . . . .' \
  '20 0 1 0  ok'

# Twenty-one nines, which is 54 times 2^64 and change. Here the high half has
# to come from both of the other two places: the top bits of the low half's
# multiply, and the high half's own multiply once it is no longer zero.
prints ">NUMBER carries from both multiplies" \
  '0 0 PARSE-NAME 999999999999999999999 OVER >R >NUMBER SWAP R> - . . . .' \
  '21 0 54 3875820019684212735  ok'

# ?NUMBER is the whole string or nothing, with a flag saying which.
prints "?NUMBER converts a signed number" 'PARSE-NAME -42 ?NUMBER .S' \
  '<2> -42 -1  ok'
prints "?NUMBER leaves a name it cannot convert" \
  'PARSE-NAME wat OVER >R ?NUMBER . . R> - .' '0 3 0  ok'

prints "CHAR takes the first byte of a name" 'CHAR A .'    '65  ok'
prints "CHAR takes only the first"           'CHAR abc .'  '97  ok'
