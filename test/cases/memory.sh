# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The memory words and the address arithmetic.
#
# The words that write need somewhere to write. BL WORD copies the name it
# parses to HERE as a counted string, and the address it returns is HERE
# itself, which is cell-aligned and which nothing reads again. That address is
# the scratch these cases use, and the name parsed is only there to give the
# scratch a size.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

prints "! stores and @ reads back" \
  'BL WORD scratch DUP 42 SWAP ! @ .' '42  ok'

# 200 has its top bit set as a byte. C@ zero-extends, so it must not come back
# negative.
prints "C! stores a byte and C@ reads it" \
  'BL WORD scratch DUP 200 SWAP C! C@ .' '200  ok'

prints "+! adds to the cell" \
  'BL WORD scratch DUP 10 SWAP ! DUP 5 SWAP +! @ .' '15  ok'

prints "CELL+ steps one cell"     '100 CELL+ .S'    '<1> 108  ok'
prints "CELLS scales to cells"    '3 CELLS .S'      '<1> 24  ok'
prints "CHAR+ steps one character" '100 CHAR+ .S'   '<1> 101  ok'
prints "CHARS is the identity"    '3 CHARS .S'      '<1> 3  ok'
prints "ALIGNED rounds up"        '101 ALIGNED .S'  '<1> 104  ok'
prints "ALIGNED leaves an aligned address" '104 ALIGNED .S' '<1> 104  ok'

# ALIGN moves the dictionary pointer, and no word hands that pointer out until
# HERE arrives in ticket 010. What WORD returns is that pointer, so the second
# WORD reports whether ALIGN moved an already aligned one.
prints "ALIGN leaves the stack alone" '9 ALIGN .S'  '<1> 9  ok'
prints "ALIGN moves an aligned pointer nowhere" \
  'BL WORD one ALIGN BL WORD two = .' '-1  ok'

# Eight known bytes, copied eight bytes along and typed back. A MOVE that
# copied nothing would leave the zeros the dictionary starts with, and the
# expected text would not match them.
prints "MOVE copies the bytes" \
  'BL WORD abcdefgh DUP CHAR+ OVER 9 CHARS + 8 MOVE 9 CHARS + 8 TYPE' \
  'abcdefgh ok'

prints "FILL writes the character" \
  'BL WORD abcdefgh DUP CHAR+ 8 65 FILL CHAR+ 8 TYPE' 'AAAAAAAA ok'

# ERASE writes zeros, which the shell drops out of a captured line, so the
# bytes are read back one at a time instead of typed. The first and the last
# say the whole run was reached.
prints "ERASE zeroes the bytes" \
  'BL WORD abcdefgh DUP CHAR+ 8 65 FILL DUP CHAR+ 8 ERASE DUP CHAR+ C@ . CHAR+ 7 + C@ .' \
  '0 0  ok'
