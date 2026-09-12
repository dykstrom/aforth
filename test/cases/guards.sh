# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The depth guards.
#
# Each line runs one word with one item too few and expects the error rather
# than a wild read. The number is what the case puts on the stack, so it reads
# as the word's requirement minus one, and this file is also the one place
# every word's arity is written down. Give every word that reads a stack a line
# here.
#
# test/run-tests.sh leaves this file out of the build without the guards, which
# has nothing to fire.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

RS_UNDERFLOW='aforth: return stack underflow'

guards "DUP"     'DUP'     0
guards "DROP"    'DROP'    0
guards "SWAP"    'SWAP'    1
guards "OVER"    'OVER'    1
guards "ROT"     'ROT'     2
guards "?DUP"    '?DUP'    0
guards "NIP"     'NIP'     1
guards "TUCK"    'TUCK'    1
guards "2DUP"    '2DUP'    1
guards "2DROP"   '2DROP'   1
guards "2SWAP"   '2SWAP'   3
guards "2OVER"   '2OVER'   3
guards "PICK"    'PICK'    0
guards "ROLL"    'ROLL'    0

# PICK and ROLL take their depth from the stack rather than from a fixed count,
# so NEEDX guards them against a count that reaches past the bottom as well.
raises "PICK past the bottom" '1 2 3 PICK' 'aforth: data stack underflow'
raises "ROLL past the bottom" '1 2 3 ROLL' 'aforth: data stack underflow'

guards "EXECUTE" 'EXECUTE' 0

guards ">R"      '>R'      0
guards "R>"      'R>'      0 "$RS_UNDERFLOW"
guards "R@"      'R@'      0 "$RS_UNDERFLOW"
guards "2>R"     '2>R'     1
guards "2R>"     '2R>'     0 "$RS_UNDERFLOW"
guards "2R@"     '2R@'     0 "$RS_UNDERFLOW"
guards "EXIT"    'EXIT'    0 "$RS_UNDERFLOW"

guards "+"       '+'       1
guards "-"       '-'       1
guards "*"       '*'       1
guards "/"       '/'       1
guards "MOD"     'MOD'     1
guards "/MOD"    '/MOD'    1
guards "ABS"     'ABS'     0
guards "NEGATE"  'NEGATE'  0
guards "MIN"     'MIN'     1
guards "MAX"     'MAX'     1
guards "1+"      '1+'      0
guards "1-"      '1-'      0
guards "2*"      '2*'      0
guards "2/"      '2/'      0
guards "UM*"     'UM*'     1
guards "M*"      'M*'      1
guards "UM/MOD"  'UM/MOD'  2
guards "SM/REM"  'SM/REM'  2
guards "FM/MOD"  'FM/MOD'  2
guards "*/"      '*/'      2
guards "*/MOD"   '*/MOD'   2

guards "AND"     'AND'     1
guards "OR"      'OR'      1
guards "XOR"     'XOR'     1
guards "INVERT"  'INVERT'  0
guards "LSHIFT"  'LSHIFT'  1
guards "RSHIFT"  'RSHIFT'  1

guards "="       '='       1
guards "<>"      '<>'      1
guards "<"       '<'       1
guards ">"       '>'       1
guards "U<"      'U<'      1
guards "U>"      'U>'      1
guards "0="      '0='      0
guards "0<>"     '0<>'     0
guards "0<"      '0<'      0
guards "0>"      '0>'      0

guards "@"       '@'       0
guards "!"       '!'       1
guards "C@"      'C@'      0
guards "C!"      'C!'      1
guards "+!"      '+!'      1
guards "CELL+"   'CELL+'   0
guards "CELLS"   'CELLS'   0
guards "CHAR+"   'CHAR+'   0
guards "CHARS"   'CHARS'   0
guards "ALIGNED" 'ALIGNED' 0
guards "MOVE"    'MOVE'    2
guards "FILL"    'FILL'    2
guards "ERASE"   'ERASE'   1

guards "EMIT"    'EMIT'    0
guards "TYPE"    'TYPE'    1
guards "SPACES"  'SPACES'  0
guards "#"       '#'       1
guards "#S"      '#S'      1
guards "HOLD"    'HOLD'    0
guards "SIGN"    'SIGN'    0
guards "#>"      '#>'      1

guards "ACCEPT"  'ACCEPT'  1

guards "PARSE"   'PARSE'   0
guards "WORD"    'WORD'    0
guards "COUNT"   'COUNT'   0
guards "FIND"    'FIND'    0
guards ">NUMBER" '>NUMBER' 3
guards "?NUMBER" '?NUMBER' 1

# The four token lists, each of which reaches its underflow before it has
# written anything, which is what keeps this file silent.
guards "."       '.'       0
guards "U."      'U.'      0
guards ".R"      '.R'      1
guards "U.R"     'U.R'     1

# The other half of each guard: ROOM and RROOM, which report that a word has
# nowhere to put what it pushes. A depth case cannot reach either, so these
# fill the stack first.
#
# The data stack area holds 8192 cells, but 8191 is the deepest a line can
# leave it: REFILL needs a cell of its own for the flag it reports with, so a
# line that ended deeper would overflow in REFILL rather than in the word under
# test. So each line below starts at 8191 items and takes the last cell itself
# with a DUP when the word under test wants one cell. A word wanting two is
# already one short.
#
# The message alone would not say which guard fired: the interpreter raises the
# same one for a number it cannot push, and so does REFILL. So a room case
# reads both streams. A word whose guard is missing pushes, reports ok for its
# own line, and leaves REFILL to raise — five lines reporting ok instead of the
# fill's four.
#
# A filling line is built by doubling and then cut to length, because appending
# eight thousand numbers one at a time is slower than the tests they feed. " 1"
# is two bytes, so 2048 of them are the 4096-byte line the input buffer takes.

ds_unit=' 1'
while [ "${#ds_unit}" -lt 4096 ]; do ds_unit="$ds_unit$ds_unit"; done

rs_unit=' 1 >R'
while [ "${#rs_unit}" -lt 4095 ]; do rs_unit="$rs_unit$rs_unit"; done
rs_unit=$(printf '%.*s' 4095 "$rs_unit")        # 819 transfers, five bytes each

# A script leaving $1 items on the data stack, in $2-byte units per number.
fill_with() {
  fill_out=''
  fill_i=0
  while [ "$fill_i" -lt $(($1 / $3)) ]; do
    fill_out="$fill_out$2
"
    fill_i=$((fill_i + 1))
  done
  if [ $(($1 % $3)) -gt 0 ]; then
    fill_out="$fill_out$(printf '%.*s' $((($1 % $3) * ($4))) "$2")
"
  fi
  printf '%s' "$fill_out"
}

DS_FULL=$(fill_with 8191 "$ds_unit" 2048 2)     # four lines, all reporting ok
RS_FULL=$(fill_with 8192 "$rs_unit" 819 5)
RS_ALMOST=$(fill_with 8191 "$rs_unit" 819 5)

# One room case: $2 is the whole line, run on a data stack already 8191 deep.
room() {
  room_src="$DS_FULL
$2"
  check "$1 guards its room" "aforth: data stack overflow, 4 lines ok" \
    "$(err "$room_src"), $(out "$room_src" | grep -c ' ok') lines ok"
}

room "DUP"        'DUP DUP'
room "OVER"       'DUP OVER'
room "?DUP"       'DUP ?DUP'
room "TUCK"       'DUP TUCK'
room "DEPTH"      'DUP DEPTH'
room "2DUP"       '2DUP'
room "2OVER"      '2OVER'
room "TRUE"       'DUP TRUE'
room "FALSE"      'DUP FALSE'
room "BL"         'DUP BL'
room "BASE"       'DUP BASE'
room "SOURCE"     'SOURCE'
room ">IN"        'DUP >IN'
room "REFILL"     'DUP REFILL'
room "KEY"        'DUP KEY'
room "PARSE-NAME" 'PARSE-NAME'
room "PARSE"      'DUP BL PARSE'
room "COUNT"      'DUP COUNT'
room "FIND"       'DUP FIND'
room "'"          "DUP ' DUP"
room "?NUMBER"    'DUP ?NUMBER'
room "STATE"      'DUP STATE'

# The four that read the return stack check it before they check the data
# stack, so each line puts something there first and fills the gap that left.
room "R>"         '>R DUP DUP R>'
room "R@"         '>R DUP DUP R@'
room "2R>"        '2>R DUP DUP DUP 2R>'
room "2R@"        '2>R DUP DUP DUP 2R@'

# RROOM, the same for the return stack. Nothing else pushes there between
# lines, so the message on its own says which guard fired. DOCOL pushes the
# caller's instruction pointer, so any word defined as a token list reports it;
# SPACE is one.
raises ">R guards its room"    "$RS_FULL
1 >R"     'aforth: return stack overflow'
raises "2>R guards its room"   "$RS_ALMOST
1 2 2>R"  'aforth: return stack overflow'
raises "DOCOL guards its room" "$RS_FULL
SPACE"    'aforth: return stack overflow'
