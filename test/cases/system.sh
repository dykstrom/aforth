# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The system file, lib/aforth.f, which cold start includes before the prompt.
#
# A word defined in Forth rather than in assembly is still a word of aforth's,
# so it needs a case, and run-tests.sh's coverage check reads the definitions out
# of lib/aforth.f to make sure it gets one. The case goes in the file for its
# kind of word, as it would if the word were in src/words/: */ in arithmetic.sh,
# ['] in compile.sh. This file holds the check that the system file loads at
# all, and the cases for WITHIN.
#
# Every case runs with --no-init, which drops the user's init.f and leaves the
# system file loading: that is what makes the suite exercise it on every run.
# See docs/system/startup.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

# The system file was read at all. WITHIN is defined nowhere in src/, so a
# binary that did not find its aforth.f fails here rather than somewhere subtler
# later on.
prints "the system file is included at cold start" \
  "' WITHIN DROP 1 ." '1  ok'

# WITHIN is the half-open range low..high-1, so the low end is in and the high
# end is out.
prints "WITHIN inside the range"    '5 1 9 WITHIN .' '-1  ok'
prints "WITHIN at the low end"      '1 1 9 WITHIN .' '-1  ok'
prints "WITHIN at the high end"     '9 1 9 WITHIN .' '0  ok'
prints "WITHIN below the range"     '0 1 9 WITHIN .' '0  ok'
prints "WITHIN above the range"     '11 1 9 WITHIN .' '0  ok'

# An empty range holds nothing, whatever is asked of it.
prints "WITHIN in an empty range"   '5 5 5 WITHIN .' '0  ok'

# The one unsigned comparison is what makes a range that crosses the largest
# number work: -2 -1 0 1 is a run of four, and WITHIN reads it as one.
prints "WITHIN in a range that wraps"     '0 -2 2 WITHIN .' '-1  ok'
prints "WITHIN outside a range that wraps" '5 -2 2 WITHIN .' '0  ok'
