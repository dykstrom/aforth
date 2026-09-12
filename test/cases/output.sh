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
