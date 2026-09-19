# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Colon definitions and the words that build them.
#
# A definition is written on its own line and run on the next, so most of these
# cases span two or three lines and the expected text holds one ok per line.
# See docs/system/compiling.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

# The whole of a definition in three lines: a name, a token list, and the word
# run afterwards.
prints ": and ; define a word" ': SQUARE DUP * ;
5 SQUARE .' ' ok
25  ok'

# STATE outlives a line, so the rest of a definition may be typed on as many
# lines as the programmer likes.
prints "a definition may span lines" ': SUM3
  + +
;
1 2 3 SUM3 .' ' ok
 ok
 ok
6  ok'

# A number typed while compiling is compiled as a literal, so it is pushed when
# the word runs rather than when it was typed. Running the word twice is what
# says so: a number pushed at compile time would be there once.
prints "a number compiles as a literal" ': TWO 2 ;
TWO TWO + .' ' ok
4  ok'

prints "a definition calls another" ': SQ DUP * ;
: QUAD SQ SQ ;
2 QUAD .' ' ok
 ok
16  ok'

# The name is hidden until ; , so the same name inside the definition is the
# word that was there before rather than the one being written.
prints "a definition sees the previous word of its name" ': X 1 ;
: X X 2 + ;
X .' ' ok
 ok
3  ok'

# STATE and the immediate flag. .STATE is immediate, so it runs whichever way
# the loop is reading, which is the only way to see STATE from inside a
# definition being compiled.
prints "STATE says which way the loop is reading" \
  ': .STATE STATE @ . ; IMMEDIATE
.STATE
: X .STATE ;' ' ok
0  ok
-1  ok'

prints "IMMEDIATE marks the definition just ended" ': SAY 65 EMIT ; IMMEDIATE
: USE SAY ;' ' ok
A ok'

# A word that is not immediate is compiled rather than run, which is the other
# half of the same decision: SAY prints nothing while USE is being written.
prints "a word that is not immediate is compiled" ': SAY 65 EMIT ;
: USE SAY ;
USE' ' ok
 ok
A ok'

# [ and ] switch the loop, which is how a value is worked out while a
# definition is being written and then compiled with LITERAL.
prints "] and [ switch the loop" ': .STATE STATE @ . ; IMMEDIATE
.STATE ] .STATE [ .STATE' ' ok
0 -1 0  ok'

prints "LITERAL compiles the value on the stack" ': FIVE [ 2 3 + ] LITERAL ;
FIVE .' ' ok
5  ok'

prints "[CHAR] compiles a character" ': A-CHAR [CHAR] A ;
A-CHAR .' ' ok
65  ok'
prints "[CHAR] takes only the first byte" ': FIRST [CHAR] abc ;
FIRST .' ' ok
97  ok'

# CREATE names the space that follows it, which is whatever is allotted next.
prints "CREATE names the space at HERE" 'CREATE BUF BUF HERE = .' '-1  ok'
prints "CREATE names the space ALLOT reserves" \
  'CREATE BUF 2 CELLS ALLOT 7 BUF ! BUF @ .' '7  ok'
prints "CREATE gives every name its own space" \
  'CREATE ONE 8 ALLOT CREATE TWO ONE TWO = .' '0  ok'

prints "VARIABLE makes a cell"    'VARIABLE V 9 V ! V @ .' '9  ok'
prints "VARIABLE starts at zero"  'VARIABLE V V @ .'       '0  ok'
prints "two VARIABLEs are two cells" 'VARIABLE A VARIABLE B A B = .' '0  ok'

prints "CONSTANT pushes its value" '42 CONSTANT ANSWER ANSWER .' '42  ok'
prints "CONSTANT is a word like any other" \
  '7 CONSTANT SEVEN : NEXT-ONE SEVEN 1 + ; NEXT-ONE .' '8  ok'

# A defining word with nothing left on the line says so rather than building an
# entry with no name.
raises ": with no name"        ':'          'aforth: name expected'
raises "CREATE with no name"   'CREATE'     'aforth: name expected'
raises "CONSTANT with no name" '1 CONSTANT' 'aforth: name expected'
raises "VARIABLE with no name" 'VARIABLE'   'aforth: name expected'
raises "[CHAR] with no name"   '[CHAR]'     'aforth: name expected'

# A name is counted in one byte, so 255 is the longest there is.
name255=$(printf '%255s' '' | tr ' ' x)
name256=$(printf '%256s' '' | tr ' ' x)
prints "a name of 255 bytes is kept whole" ": $name255 1 ;
$name255 ." ' ok
1  ok'
raises "a name of 256 bytes is refused" ": $name256 ;" 'aforth: name too long'

# The dictionary's end, reached from each of the three places that grow it
# while a definition is being compiled. A one-character name costs 24 bytes:
# link, flags, count and the name padded to 16, then the code field.
raises ": reports a full dictionary" 'UNUSED ALLOT
: Z ;' 'aforth: dictionary full'
raises "compiling a token reports a full dictionary" 'UNUSED 24 - ALLOT
: Z
DUP' 'aforth: dictionary full'
raises "compiling a literal reports a full dictionary" 'UNUSED 24 - ALLOT
: Z
1' 'aforth: dictionary full'

# An error inside a definition abandons it: the loop is interpreting again on
# the next line, and the half-written name was never unhidden, so nothing can
# reach it.
raises "an error names the word that failed" ': BAD fnord ;' \
  'aforth: undefined word: fnord'
prints "an error leaves the loop interpreting" ': BAD fnord ;
1 .' '1  ok'
prints "an abandoned definition cannot be found" ': BAD fnord ;
BL WORD BAD DUP FIND . = .' '0 -1  ok'

# The two string literals.
#
# S" and ." are immediate, so each has two behaviours to test: what it compiles
# into a definition and what it does typed at the prompt. See
# docs/system/compiling.md for the inline shape and docs/system/output.md for
# what ." does while interpreting.

prints 'S" leaves a string while interpreting' 'S" hello" TYPE' 'hello ok'
prints 'S" leaves an address and a length' 'S" hello" NIP .' '5  ok'

# A delimiter that comes straight away gives the empty string, which is the
# shortest thing S" can parse rather than a case it refuses.
prints 'S" parses the empty string' 'S" " NIP .' '0  ok'

# Forth-2012 11.3.4 wants two strings made one after the other to be there at
# once, so the transient buffers are taken in turn rather than reused. Printing
# them in the order they were not made is what says so.
prints 'two interpreted strings are both live' 'S" one" S" two" TYPE TYPE' \
  'twoone ok'

# A definition carries its own bytes, so two definitions do not share a buffer
# and neither loses its string to the other.
prints 'a definition carries its string' ': F S" abc" ;
F TYPE' ' ok
abc ok'
prints "two definitions keep their own strings" ': F S" abc" ;
: G S" xyz" ;
F TYPE G TYPE' ' ok
 ok
abcxyz ok'

# The bytes are padded to a cell, so the token after the string is where the
# list expects it. A length one under, one over and exactly a cell is what
# catches the arithmetic being off by one either way.
prints "a definition steps over seven bytes" ': F S" 1234567" 2DROP 42 ;
F .' ' ok
42  ok'
prints "a definition steps over eight bytes" ': F S" 12345678" 2DROP 42 ;
F .' ' ok
42  ok'
prints "a definition steps over nine bytes" ': F S" 123456789" 2DROP 42 ;
F .' ' ok
42  ok'

# A branch distance is counted in cells, and the padding is what keeps a string
# a whole number of them. A branch measured over one lands right or the word
# runs into the string as if it were tokens.
prints "a branch over a string lands right" ': F 0= IF S" yes" ELSE S" no" THEN TYPE ;
0 F
1 F' ' ok
yes ok
no ok'

prints '." prints while interpreting' '." hello"' 'hello ok'
prints '." prints from a definition' ': F ." hello" ;
F' ' ok
hello ok'

# ." compiles TYPE after the string, so what follows it in the definition still
# runs. Nine bytes puts the next token on the far side of a pad.
prints '." leaves the list where the next token is' ': F ." 123456789" CR 42 . ;
F' ' ok
123456789
42  ok'

# A string whose delimiter never comes takes the rest of the line, which is
# what ( does with a comment and for the same reason. The next line still runs.
prints 'S" with no closing quote takes the line' 'S" abc
NIP .' ' ok
3  ok'

# The room for the whole string is tested before any of it is written, so a
# string that will not fit leaves the dictionary where it was.
raises 'compiling a string reports a full dictionary' 'UNUSED 24 - ALLOT
: Z
S" x"' 'aforth: dictionary full'
