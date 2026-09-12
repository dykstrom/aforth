# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The stack words, the return stack transfers, and PICK and ROLL.
#
# Each case runs the word and prints the whole stack with .S , so the expected
# string reads as the word's stack comment does. The 9 at the bottom of several
# of them is a sentinel: a word that disturbs the stack under its own operands
# fails the case.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

prints "DUP copies the top"           '1 7 DUP .S'      '<3> 1 7 7  ok'
prints "DROP takes the top"           '1 7 DROP .S'     '<1> 1  ok'
prints "SWAP exchanges two"           '1 2 3 SWAP .S'   '<3> 1 3 2  ok'
prints "OVER copies the second"       '1 2 3 OVER .S'   '<4> 1 2 3 2  ok'
prints "ROT brings the third up"      '9 1 2 3 ROT .S'  '<4> 9 2 3 1  ok'
prints "?DUP copies a non-zero top"   '1 7 ?DUP .S'     '<3> 1 7 7  ok'
prints "?DUP leaves a zero alone"     '1 0 ?DUP .S'     '<2> 1 0  ok'
prints "NIP drops the second"         '9 1 2 NIP .S'    '<2> 9 2  ok'
prints "TUCK copies under the second" '9 1 2 TUCK .S'   '<4> 9 2 1 2  ok'

prints "DEPTH counts the items"       '1 2 3 DEPTH .S'  '<4> 1 2 3 3  ok'
prints "DEPTH counts none"            'DEPTH .S'        '<1> 0  ok'

prints "2DUP copies the top pair"     '9 1 2 2DUP .S'   '<5> 9 1 2 1 2  ok'
prints "2DROP takes the top pair"     '9 1 2 2DROP .S'  '<1> 9  ok'
prints "2SWAP exchanges two pairs"    '9 1 2 3 4 2SWAP .S' '<5> 9 3 4 1 2  ok'
prints "2OVER copies the second pair" '1 2 3 4 2OVER .S'   '<6> 1 2 3 4 1 2  ok'

# The return stack transfers, each put back before the line ends. A word runs
# on its own entry to the machine, so an item left on the return stack by one
# word is still there for the next word on the same line.
prints ">R and R> carry an item"      '9 7 >R R> .S'    '<2> 9 7  ok'
prints "R@ copies without taking"     '7 >R R@ R> .S'   '<2> 7 7  ok'
prints "2>R and 2R> carry a pair"     '1 2 2>R 2R> .S'  '<2> 1 2  ok'
prints "2R@ copies a pair"            '1 2 2>R 2R@ 2R> .S' '<4> 1 2 1 2  ok'
prints ">R keeps the order of a pair" '1 2 2>R R> R> .S'   '<2> 2 1  ok'

prints "0 PICK is DUP"                '7 0 PICK .S'     '<2> 7 7  ok'
prints "PICK reaches down"            '1 2 3 2 PICK .S' '<4> 1 2 3 1  ok'
prints "0 ROLL does nothing"          '7 0 ROLL .S'     '<1> 7  ok'
prints "1 ROLL is SWAP"               '1 2 1 ROLL .S'   '<2> 2 1  ok'
prints "2 ROLL is ROT"                '1 2 3 2 ROLL .S' '<3> 2 3 1  ok'
