# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The arithmetic, the logic, the shifts and the comparisons.
#
# The 9 at the bottom of several cases is a sentinel: a word that disturbs the
# stack under its own operands fails the case. See docs/system/arithmetic.md
# for the choices Forth-2012 leaves open, which is what the division cases pin.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

prints "+ adds"                    '20 22 + .S'      '<1> 42  ok'
prints "- subtracts"               '9 30 8 - .S'     '<2> 9 22  ok'
prints "* multiplies"              '9 6 7 * .S'      '<2> 9 42  ok'
prints "1+ adds one"               '41 1+ .S'        '<1> 42  ok'
prints "1- takes one"              '43 1- .S'        '<1> 42  ok'
prints "2* doubles"                '21 2* .S'        '<1> 42  ok'
prints "ABS of a negative"         '-5 ABS .S'       '<1> 5  ok'
prints "ABS of a positive"         '5 ABS .S'        '<1> 5  ok'
prints "NEGATE flips the sign"     '5 NEGATE .S'     '<1> -5  ok'
prints "MIN compares signed"       '-1 -9 MIN .S'    '<1> -9  ok'
prints "MAX takes the larger"      '3 9 MAX .S'      '<1> 9  ok'

# / and MOD round toward zero and the remainder carries the dividend's sign,
# which is the pair of choices SM/REM makes and / is defined over.
prints "/ divides"                 '22 7 / .S'       '<1> 3  ok'
prints "/ rounds toward zero"      '-22 7 / .S'      '<1> -3  ok'
prints "MOD leaves the remainder"  '22 7 MOD .S'     '<1> 1  ok'
prints "MOD takes the dividend sign" '-22 7 MOD .S'  '<1> -1  ok'
prints "/MOD leaves both"          '22 7 /MOD .S'    '<2> 1 3  ok'

# 2/ is an arithmetic shift, so it floors instead of rounding toward zero.
prints "2/ halves"                 '42 2/ .S'        '<1> 21  ok'
prints "2/ of -1 is -1"            '-1 2/ .S'        '<1> -1  ok'

# The mixed precision words. A double has its high cell on top, so a pair
# written out reads low first.
prints "UM* makes a double"        '4294967296 4294967296 UM* .S' '<2> 0 1  ok'
prints "UM* is unsigned"           '-1 -1 UM* .S'    '<2> 1 -2  ok'
prints "M* keeps the sign"         '-2 3 M* .S'      '<2> -6 -1  ok'

prints "UM/MOD divides a short double" '100 0 7 UM/MOD .S' '<2> 2 14  ok'
prints "UM/MOD divides 2^64 by 3"  '0 1 3 UM/MOD .S' '<2> 1 6148914691236517205  ok'
prints "UM/MOD by one"             '-1 0 1 UM/MOD .S' '<2> 0 -1  ok'

# The largest quotient that still fits in a cell, from a dividend only just
# smaller than the divisor shifted up a cell. The running remainder passes 2^63
# here, so the bit leaving the top of the dividend is the only thing that can
# tell udiv128 to subtract, and no smaller case reaches that path. Printed with
# U. , because .S prints an item signed and both halves have their top bit set.
prints "UM/MOD at the top of the range" \
  'HEX FFFFFFFFFFFFFFFF 8000000000000000 8000000000000001 UM/MOD U. U. DECIMAL' \
  'FFFFFFFFFFFFFFFF 8000000000000000  ok'

# SM/REM and FM/MOD differ only when the signs differ, and then they differ
# exactly as Forth-2012's own examples say they do.
prints "SM/REM rounds toward zero" '-7 -1 2 SM/REM .S' '<2> -1 -3  ok'
prints "FM/MOD floors"             '-7 -1 2 FM/MOD .S' '<2> 1 -4  ok'
prints "SM/REM with a negative divisor" '7 0 -2 SM/REM .S' '<2> 1 -3  ok'
prints "FM/MOD with a negative divisor" '7 0 -2 FM/MOD .S' '<2> -1 -4  ok'
prints "SM/REM with signs agreeing" '7 0 2 SM/REM .S'  '<2> 1 3  ok'
prints "FM/MOD needs no fixup when exact" '-6 -1 2 FM/MOD .S' '<2> 0 -3  ok'

# */ and */MOD multiply to a double before they divide, which is what keeps
# them exact when the product overflows a cell: 2^62 * 4 does not fit.
prints "*/ scales"                 '100 3 4 */ .S'   '<1> 75  ok'
prints "*/ stays exact past a cell" '4611686018427387904 4 8 */ .S' \
  '<1> 2305843009213693952  ok'
prints "*/MOD leaves both"         '100 3 7 */MOD .S' '<2> 6 42  ok'

# A zero divisor is an error, not a trap: ARM64 division by zero yields zero
# and says nothing, so every dividing word tests for it.
raises "/ by zero"                 '1 0 /'           'aforth: divide by zero'
raises "MOD by zero"               '1 0 MOD'         'aforth: divide by zero'
raises "/MOD by zero"              '1 0 /MOD'        'aforth: divide by zero'
raises "UM/MOD by zero"            '1 0 0 UM/MOD'    'aforth: divide by zero'
raises "SM/REM by zero"            '1 0 0 SM/REM'    'aforth: divide by zero'
raises "FM/MOD by zero"            '1 0 0 FM/MOD'    'aforth: divide by zero'
raises "*/ by zero"                '1 1 0 */'        'aforth: divide by zero'

prints "AND masks"                 '12 10 AND .S'    '<1> 8  ok'
prints "OR sets"                   '12 10 OR .S'     '<1> 14  ok'
prints "XOR differs"               '12 10 XOR .S'    '<1> 6  ok'
prints "INVERT flips every bit"    '0 INVERT .S'     '<1> -1  ok'
prints "LSHIFT shifts up"          '1 4 LSHIFT .S'   '<1> 16  ok'
prints "RSHIFT is logical"         '-1 60 RSHIFT .S' '<1> 15  ok'

# A shift count of a cell's width is an ambiguous condition in Forth-2012. The
# instruction reads the low six bits of the count, so aforth shifts by none.
prints "LSHIFT by 64 shifts by none" '1 64 LSHIFT .S' '<1> 1  ok'

# A true flag is every bit set, which is -1 as a cell.
prints "= on equal cells"          '5 5 = .S'        '<1> -1  ok'
prints "= on different cells"      '5 6 = .S'        '<1> 0  ok'
prints "<> on different cells"     '5 6 <> .S'       '<1> -1  ok'
prints "< is signed"               '-1 1 < .S'       '<1> -1  ok'
prints "< on a larger left"        '5 3 < .S'        '<1> 0  ok'
prints "> on a larger left"        '5 3 > .S'        '<1> -1  ok'
prints "U< is unsigned"            '-1 1 U< .S'      '<1> 0  ok'
prints "U> is unsigned"            '-1 1 U> .S'      '<1> -1  ok'
prints "0= on zero"                '0 0= .S'         '<1> -1  ok'
prints "0<> on a non-zero"         '5 0<> .S'        '<1> -1  ok'
prints "0< on a negative"          '-5 0< .S'        '<1> -1  ok'
prints "0> on a positive"          '5 0> .S'         '<1> -1  ok'
prints "TRUE pushes every bit"     '9 TRUE .S'       '<2> 9 -1  ok'
prints "FALSE pushes none"         '9 FALSE .S'      '<2> 9 0  ok'
