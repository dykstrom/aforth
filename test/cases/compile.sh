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
raises "VALUE with no name"    '1 VALUE'    'aforth: name expected'
raises "DEFER with no name"    'DEFER'      'aforth: name expected'
raises "MARKER with no name"   'MARKER'     'aforth: name expected'
raises "BUFFER: with no name"  '1 BUFFER:'  'aforth: name expected'

# A name is counted in one byte, so 255 is the longest there is.
name255=$(printf '%255s' '' | tr ' ' x)
name256=$(printf '%256s' '' | tr ' ' x)
prints "a name of 255 bytes is kept whole" ": $name255 1 ;
$name255 ." ' ok
1  ok'
raises "a name of 256 bytes is refused" ": $name256 ;" 'aforth: name too long'

# The dictionary's end, reached from each of the three places that grow it
# while a definition is being compiled. A one-character name costs 32 bytes:
# link, flags, count and the name padded to 16, then the does-cell and the code
# field.
raises ": reports a full dictionary" 'UNUSED ALLOT
: Z ;' 'aforth: dictionary full'
raises "compiling a token reports a full dictionary" 'UNUSED 32 - ALLOT
: Z
DUP' 'aforth: dictionary full'
raises "compiling a literal reports a full dictionary" 'UNUSED 32 - ALLOT
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

# A string EVALUATE runs is not bound by the input buffer, so an interpreted
# S" there can be longer than a transient buffer. It raises rather than
# writing past the buffer's end, and a string that fills one exactly fits.
raises 'S" too long for a transient buffer raises' \
  'CREATE B 5000 ALLOT B 5000 CHAR x FILL
CHAR S B C! 34 B 1+ C! 32 B 2 + C!
B 5000 EVALUATE' 'aforth: input line too long'
prints 'S" that fills a transient buffer fits' \
  'CREATE B 4099 ALLOT B 4099 CHAR x FILL
CHAR S B C! 34 B 1+ C! 32 B 2 + C!
B 4099 EVALUATE NIP .' ' ok
 ok
4096  ok'

# The room for the whole string is tested before any of it is written, so a
# string that will not fit leaves the dictionary where it was.
raises 'compiling a string reports a full dictionary' 'UNUSED 32 - ALLOT
: Z
S" x"' 'aforth: dictionary full'

# ABORT" lays its message down the way S" does and compiles (ABORT") after it.
# A false flag lets the definition run on; a true one stops everything with the
# program's own message, in the same shape as aforth's.
prints 'ABORT" with a false flag runs on' ': T 0 ABORT" boom" 7 . ; T' '7  ok'
raises 'ABORT" with a false flag says nothing' ': T 0 ABORT" boom" ; T' ''
raises 'ABORT" prints its message' ': T 1 ABORT" disk full" ; T' \
  'aforth: disk full'
prints 'ABORT" prints nothing on stdout' ': T 1 ABORT" disk full" ; T' ''

# Any bit set is true, not only -1.
raises 'ABORT" takes -1 as true' ': T -1 ABORT" boom" ; T' 'aforth: boom'
raises 'ABORT" takes 2 as true' ': T 2 ABORT" boom" ; T' 'aforth: boom'

# What ABORT empties, ABORT" empties: the data stack, the rest of the line, and
# the rest of every definition it was called from. The next line still runs.
prints 'ABORT" empties the data stack' '1 2 : T 1 ABORT" x" ; T
.S' '<0>  ok'
prints 'ABORT" leaves the definitions that called it' ': A 1 ABORT" x" ;
: B A 99 . ;
B 1 .
2 .' ' ok
 ok
2  ok'

# Typed at the prompt it does the same work at once. Forth-2012 leaves that
# undefined, and aforth follows S" and ." in giving it a meaning.
raises 'ABORT" aborts while interpreting' '1 ABORT" boom"' 'aforth: boom'
prints 'ABORT" runs on while interpreting' '0 ABORT" boom" 5 .' '5  ok'

# An empty message would end the line in the prefix, so it says aborted.
raises 'ABORT" with no message says aborted' ': T 1 ABORT" " ; T' \
  'aforth: aborted'

# EVALUATE hands the number on to the loop unchanged. S" has no escape for a
# quote, so the ABORT" is compiled outside the string and run from inside it.
raises 'ABORT" reaches the loop from inside EVALUATE' \
  ': T 1 ABORT" boom" ; S" T" EVALUATE' 'aforth: boom'

# Compiling a word from a word.
#
# POSTPONE takes one of two paths depending on whether the name it parses is
# immediate, and the two look the same at the prompt, so each case defines a
# word that uses POSTPONE and then a word that uses that.

# THEN is immediate, so ENDIF carries THEN's token and running ENDIF runs THEN.
# Without that, IF would never be resolved and 42 would not print.
prints "POSTPONE of an immediate word runs it later" ': ENDIF POSTPONE THEN ; IMMEDIATE
: T 1 IF 42 . ENDIF ;
T' ' ok
 ok
42  ok'

# DUP is not immediate, so MAKE-DUP carries the token as a literal and a comma.
# Running MAKE-DUP appends DUP to T, which is why T leaves two copies.
prints "POSTPONE of a plain word compiles it later" ': MAKE-DUP POSTPONE DUP ; IMMEDIATE
: T 5 MAKE-DUP ;
T . .' ' ok
 ok
5 5  ok'

# The same path as ' , down to the message: the name is reported rather than a
# token handed back that would fault when something ran it.
raises "POSTPONE reports a name that is not there" 'POSTPONE NOSUCHWORD' \
  'aforth: undefined word: NOSUCHWORD'
raises "POSTPONE with no name left on the line" 'POSTPONE' 'aforth: undefined word'

# ['] compiles the token, so the definition carries it and EXECUTE runs it.
prints "['] compiles an execution token" ": T ['] DUP EXECUTE ;
5 T . ." ' ok
5 5  ok'

# The token ['] compiles is the one ' gives. ['] has compilation semantics only,
# so it is asked inside a definition and compared outside one.
prints "['] and ' name the same token" ": T ['] DUP ;
T ' DUP = ." ' ok
-1  ok'

# >BODY reaches the cell CREATE's word pushes the address of, so the two agree
# and what was compiled into the body reads back.
prints ">BODY gives the address the word itself pushes" "CREATE X 7 ,
' X >BODY @ .
' X >BODY X = ." ' ok
7  ok
-1  ok'

# COMPILE, appends the token it is given, which is what POSTPONE does for a
# plain word by another route.
prints "COMPILE, appends the token it is given" ": MAKE-DUP ['] DUP COMPILE, ; IMMEDIATE
: T 5 MAKE-DUP ;
T . ." ' ok
 ok
5 5  ok'

# Defining words of the program's own.
#
# CONST is CONSTANT written with DOES>: the part before DOES> runs when CONST
# makes a word, and the part after it runs every time that word does, with the
# word's body on the stack.
DOES_CONST=': CONST CREATE , DOES> @ ;'
prints "DOES> gives a word the behaviour after it" "$DOES_CONST
42 CONST ANSWER ANSWER ." ' ok
42  ok'

# The does-part is shared and the body is not, so two words from one defining
# word run the same code on different cells.
prints "DOES> words keep their own bodies" "$DOES_CONST
1 CONST A 2 CONST B A . B ." ' ok
1 2  ok'

# What the does-part is handed is the body's address, so it can index into
# space the defining part allotted.
prints "the does-part gets the body's address" ': ARRAY CREATE CELLS ALLOT DOES> SWAP CELLS + ;
3 ARRAY V 7 1 V ! 1 V @ .' ' ok
7  ok'
prints ">BODY agrees with what the does-part gets" ": ADDR CREATE DOES> ;
ADDR X ' X >BODY X = ." ' ok
-1  ok'

# A DOES> word is a word like any other: it can be compiled into a definition
# and run by its token.
prints "a DOES> word runs compiled and through EXECUTE" "$DOES_CONST
42 CONST ANSWER
: T ANSWER 1+ ;
T . ' ANSWER EXECUTE ." ' ok
 ok
 ok
43 42  ok'

# (DOES>) leaves the defining word, so what follows DOES> runs only when the
# new word does, and the defining word's caller carries on after it.
prints "the does-part does not run while defining" ': D CREATE ." made " DOES> DROP ." ran " ;
D X X' ' ok
made ran  ok'
prints "a defining word returns to its caller" ': D CREATE DOES> DROP 1 ;
: USE D 2 ;
USE W . W .' ' ok
 ok
2 1  ok'

# Values.
#
# A value pushes its cell as a constant does, and TO is what changes it: at
# once at the prompt, and when the definition runs when it is compiled.
prints "VALUE pushes its value" '5 VALUE V V .' '5  ok'
prints "TO changes a value while interpreting" '5 VALUE V 7 TO V V .' '7  ok'
prints "TO changes a value from a definition" '5 VALUE V : SET TO V ;
9 SET V .' ' ok
9  ok'

# TO compiles the value's token rather than running, so the definition changes
# the value each time it runs, and nothing changes while it is being written.
prints "TO compiled runs each time" '0 VALUE N : BUMP N 1+ TO N ;
N . BUMP BUMP N .' ' ok
0 2  ok'
prints "TO is followed by the next word" '0 VALUE N : T 5 TO N 6 ;
T . N .' ' ok
6 5  ok'

raises "TO reports a name that is not there" '1 TO NOSUCH' \
  'aforth: undefined word: NOSUCH'
raises "TO with no name left on the line" '1 TO' 'aforth: undefined word'

# Deferred words.
#
# DEFER makes a word that runs whatever token IS last gave it, so setting it
# again changes what an older definition that calls it does.
prints "IS sets what a deferred word runs" "DEFER D ' DUP IS D 3 D .S" \
  '<2> 3 3  ok'
prints "a deferred word can be set again" "DEFER D : T D ; ' 1+ IS D 1 T .
' 1- IS D 1 T ." '2  ok
0  ok'
prints "IS compiled sets it when the definition runs" "DEFER D : SET IS D ;
' NEGATE SET 4 D ." ' ok
-4  ok'
raises "a deferred word that was never set says so" 'DEFER D D' \
  'aforth: deferred word not set'
raises "IS reports a name that is not there" "' DUP IS NOSUCH" \
  'aforth: undefined word: NOSUCH'

# DEFER@ and DEFER! reach the same cell from a token, and ACTION-OF from a
# name, while interpreting and from a definition.
prints "DEFER@ gives the token IS set" "DEFER D ' DUP IS D ' D DEFER@ ' DUP = ." \
  '-1  ok'
prints "DEFER! sets a deferred word from a token" "DEFER D ' 1+ ' D DEFER! 1 D ." \
  '2  ok'
prints "ACTION-OF gives the token while interpreting" \
  "DEFER D ' DUP IS D ACTION-OF D ' DUP = ." '-1  ok'
prints "ACTION-OF gives the token from a definition" \
  "DEFER D : A ACTION-OF D ; ' DUP IS D A ' DUP = .
' DROP IS D A ' DROP = ." '-1  ok
-1  ok'

# :NONAME is a definition with no name: it leaves the token, and the token is
# the only way to run it.
prints ":NONAME leaves a token that runs the definition" \
  ':NONAME 40 2 + ; EXECUTE .' '42  ok'
prints ":NONAME's token sits under what the body compiles" \
  ':NONAME 1 IF 7 THEN ; EXECUTE .' '7  ok'
prints "RECURSE works in :NONAME" \
  ':NONAME DUP 0> IF DUP 1- RECURSE + THEN ; 4 SWAP EXECUTE .' '10  ok'
prints ":NONAME and DEFER make a forward reference" "DEFER LATER : T LATER 1+ ;
:NONAME 41 ; IS LATER T ." ' ok
42  ok'

# The entry has no name and stays hidden after ; , so nothing finds it by the
# empty name and the word defined before it keeps its own place.
prints ":NONAME cannot be found by the empty name" \
  ':NONAME ; DROP BL WORD X DUP 0 SWAP C! FIND NIP .' '0  ok'
prints ":NONAME leaves the word before it alone" ': A 1 ;
:NONAME 2 ; DROP A .' ' ok
1  ok'

# BUFFER: names space of its own, of the size asked for.
prints "BUFFER: reserves the space asked for" '10 BUFFER: B HERE B - .' '10  ok'
prints "BUFFER: names space a program can use" \
  '10 BUFFER: B B 10 65 FILL B 10 TYPE' 'AAAAAAAAAA ok'

# MARKER takes itself and everything after it back out, and HERE with them.
prints "MARKER forgets the words after it" 'MARKER M : FOO 1 ; M
BL WORD FOO FIND NIP .' ' ok
0  ok'
prints "MARKER forgets itself" 'MARKER M M BL WORD M FIND NIP .' '0  ok'
prints "MARKER puts HERE back" 'HERE MARKER M 100 ALLOT M HERE = .' '-1  ok'

# A word of the same name defined before the marker is found again once the
# marker has taken the newer one away.
prints "MARKER uncovers an older word of the same name" ': FOO 1 ;
MARKER M : FOO 2 ; M FOO .' ' ok
1  ok'

# The string literal with escapes, one byte printed at a time so that a
# control character shows as its number. \m is two bytes.
BYTES=': BYTES 0 ?DO DUP I + C@ . LOOP DROP ;'
prints 'S\" translates every escape' "$BYTES
S\\\" \\a\\b\\e\\f\\l\\m\\n\\q\\r\\t\\v\\z\\\"\\\\\" BYTES" ' ok
7 8 27 12 10 13 10 10 34 13 9 11 0 34 92  ok'
prints 'S\" takes two hex digits after \x' "$BYTES
S\\\" \\x41\\x7e\\xFF\" BYTES" ' ok
65 126 255  ok'

# What Forth-2012 leaves ambiguous: an escape it does not define, and \x
# without two hex digits, are the character after the backslash.
prints 'S\" keeps an unknown escape as its character' 'S\" a\kb" TYPE' 'akb ok'
prints 'S\" keeps \x without two hex digits as x' 'S\" \x4g" TYPE' 'x4g ok'
prints 'S\" leaves plain text alone' 'S\" hello" TYPE' 'hello ok'
prints 'S\" parses the empty string' 'S\" " NIP .' '0  ok'

# A backslash before the quote keeps the string going, so the next quote ends
# it and the words after that still run.
prints 'S\" does not end on an escaped quote' 'S\" a\"b" TYPE 1 .' 'a"b1  ok'

# Compiled, the translated bytes are the definition's, padded to a cell like
# any string's, so the token after them is where the list expects it.
prints 'S\" compiles into a definition' ': F S\" 1\t234567" 42 ;
F . TYPE' ' ok
42 1	234567 ok'
prints 'S\" compiled steps over nine bytes' ': F S\" 12345678\n" 2DROP 42 ;
F .' ' ok
42  ok'
raises 'compiling S\" reports a full dictionary' 'UNUSED 32 - ALLOT
: Z
S\" x"' 'aforth: dictionary full'

prints 'S\" with no closing quote takes the line' 'S\" abc
NIP .' ' ok
3  ok'

# A string EVALUATE runs is not bound by the input buffer, so an interpreted
# S\" there can be longer than a transient buffer. It raises rather than
# writing past the buffer's end.
raises 'S\" too long for a transient buffer raises' \
  'CREATE B 5000 ALLOT B 5000 CHAR x FILL
CHAR S B C! 92 B 1+ C! 34 B 2 + C! 32 B 3 + C!
B 5000 EVALUATE' 'aforth: input line too long'
