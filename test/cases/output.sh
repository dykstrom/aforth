# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The output words, BASE, and the pictured numeric output.
#
# These cases check the bytes the words write, which is the half the old
# in-binary table could not reach: it ran before the banner, so a case that
# printed landed above it. See docs/system/output.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

prints "EMIT writes one byte"      '65 EMIT'         'A ok'
prints "BL is a space"             'BL .'            '32  ok'
prints "SPACE writes one space"    '65 EMIT SPACE 66 EMIT' 'A B ok'
prints "SPACES writes a run"       '3 SPACES 65 EMIT' '   A ok'
prints "SPACES writes none for zero" '0 SPACES 65 EMIT' 'A ok'
prints "SPACES writes none for a negative" '-3 SPACES 65 EMIT' 'A ok'
prints "TYPE writes the bytes"     'BL WORD hello COUNT TYPE' 'hello ok'
prints "CR starts a new line"      '65 EMIT CR 66 EMIT' 'A
B ok'

# .( is immediate, so it prints while a definition is being written and
# compiles nothing into it.
prints ".( prints up to the parenthesis" '.( hello) 1 .' 'hello1  ok'
prints ".( prints while compiling" ': T .( made) 1 ;
T .' 'made ok
1  ok'
prints ".( parses the empty string" '.( ) 1 .' '1  ok'

prints "BASE starts at ten"        'BASE @ .'        '10  ok'
prints "HEX sets sixteen"          'HEX BASE @ DECIMAL .' '16  ok'
prints "DECIMAL sets ten again"    'HEX DECIMAL BASE @ .' '10  ok'
prints "a number prints in BASE"   '255 HEX . DECIMAL' 'FF  ok'

# The pictured numeric output words, over a double: the low half first, the
# high half on top. The buffer fills downward, so two # of 5 give 05.
prints "# holds one digit at a time" '5 0 <# # # #> TYPE' '05 ok'
prints "#S holds a zero as one digit" '0 0 <# #S #> TYPE' '0 ok'
prints "#S holds every digit"      '255 0 <# #S #> TYPE' '255 ok'
prints "#S follows BASE"           '255 0 HEX <# #S #> TYPE DECIMAL' 'FF ok'
prints "#S holds a double past a cell" '0 1 <# #S #> TYPE' '18446744073709551616 ok'

# A high half larger than BASE, which is the case that needs # to divide the
# halves in turn: a # that divided the low half alone would overflow the
# quotient the moment the high half reached BASE.
prints "#S holds a high half larger than BASE" \
  '0 255 <# #S #> TYPE' '4703919738795935662080 ok'

prints "HOLD puts a character in"  '0 0 <# 65 HOLD #> TYPE' 'A ok'
prints "SIGN holds a minus for a negative" '255 0 <# #S -1 SIGN #> TYPE' '-255 ok'
prints "SIGN holds nothing for a positive" '255 0 <# #S 1 SIGN #> TYPE' '255 ok'
prints "#> reports the length"     '255 0 <# #S #> NIP .' '3  ok'

# BASE outside 2 to 36 is an ambiguous condition. Neither of the two that would
# misbehave gets away with it: # divides by BASE, so 0 is the divide by zero
# every dividing word raises, and 1 divides a number by itself forever and
# fills the buffer instead of hanging.
raises "a BASE of zero"  '5 0 0 BASE ! <# #S #> TYPE' 'aforth: divide by zero'
raises "a BASE of one"   '5 0 1 BASE ! <# #S #> TYPE' 'aforth: pictured output overflow'

prints ". prints a signed number"  '42 .'            '42  ok'
prints ". prints a negative"       '-42 .'           '-42  ok'
prints "U. prints unsigned"        '-1 U.'           '18446744073709551615  ok'
prints ".R pads on the left"       '42 5 .R'         '   42 ok'
prints ".R prints a wide number in full" '12345 3 .R' '12345 ok'
prints ".R pads a negative"        '-42 5 .R'        '  -42 ok'
prints "U.R pads on the left"      '-1 25 U.R'       '     18446744073709551615 ok'

prints ".S prints an empty stack"  '.S'              '<0>  ok'
prints ".S prints the items deepest first" '1 2 3 .S' '<3> 1 2 3  ok'
prints ".S prints a negative item" '-1 .S'           '<1> -1  ok'
prints ".S leaves the stack alone" '1 2 .S .S'       '<2> 1 2 <2> 1 2  ok'
prints ".S follows BASE"           '255 HEX .S DECIMAL' '<1> FF  ok'

# WORDS prints the whole dictionary, which grows whenever a word is added, so
# these cases ask whether one name is in the list rather than comparing the
# list.
# The list is split to one name per line, with the interpreter's ok dropped.
words_has() {
  if out "$1" | sed '$d' | tr ' ' '\n' | grep -qxF "$2"; then
    echo yes
  else
    echo no
  fi
}

check "WORDS lists a built-in word" "yes" "$(words_has 'WORDS' 'DUP')"
check "WORDS lists a word just defined" "yes" "$(words_has ': ZZFOO ;
WORDS' 'ZZFOO')"

# The chain runs newest first, so a word defined on the line before heads it.
check "WORDS lists the newest word first" "ZZFOO" \
  "$(out ': ZZFOO ;
WORDS' | sed -n 2p | cut -d' ' -f1)"

# The two an F_HIDDEN entry covers: a word that may never be typed, and a
# definition that has not reached its ; yet.
check "WORDS leaves out a hidden word" "no" "$(words_has 'WORDS' '(LIT)')"
#
# WORDS has to run while the definition is still open, and a word that is not
# immediate would be compiled into it instead. [ and ] are what let it run: on
# the next line it would be compiled, and the case would pass against a WORDS
# that listed everything.
check "WORDS leaves out an unfinished definition" "no" \
  "$(words_has ': ZZFOO [ WORDS ]' 'ZZFOO')"

# The width is fixed, aforth never asking the terminal how wide it is. Both
# cases name the lines that broke the rule rather than reporting a count, so a
# failure says which one.
check "WORDS wraps at 64 columns" "" \
  "$(out 'WORDS' | sed '$d' | awk 'length > 64 { printf "%s ", FNR }')"
check "WORDS leaves no line ending in a space" "" \
  "$(out 'WORDS' | sed '$d' | awk '/ $/ { printf "%s ", FNR }')"
