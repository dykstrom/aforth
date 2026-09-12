#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Runs the aforth binary and checks its observable behaviour.
# Usage: test/run-tests.sh ./build/aforth
#
# Every case pipes Forth source in and compares what comes out. The binary
# reads until end of input, so each case gets its own run with a whole script
# on stdin. The cases themselves are in test/cases/, one file per kind of word,
# mirroring src/words/. This file holds the helpers they are written with, the
# order they run in, and the coverage check at the end.
#
# See docs/system/testing.md for how to write a case.

set -eu

BIN="${1:-./build/aforth}"
HERE=$(dirname "$0")
failures=0

check() {
  name="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    echo "       expected: $expected"
    echo "       actual:   $actual"
    failures=$((failures + 1))
  fi
}

# Run the source in $1 and print what reaches stdout, the banner dropped.
# Errors go to file descriptor 2, so they are not in what this returns.
out() {
  printf '%s\n' "$1" | "$BIN" 2>/dev/null | sed 1d
}

# The same, but what reaches file descriptor 2.
err() {
  printf '%s\n' "$1" | "$BIN" 2>&1 >/dev/null
}

# The four helpers a case is written with. Each takes the case's name first,
# then the Forth source, then what that source should produce. A case needing
# more than one line puts a newline in the source.
#
#   prints "DUP copies the top"  '1 7 DUP .S'  '<3> 1 7 7  ok'
#   raises "/ by zero"           '1 0 /'       'aforth: divide by zero'
#   exits  "BYE exits"           '1 . BYE'     0
#   guards "ROT"                 'ROT'         2
#
# A stack effect is asserted by printing the stack with .S , which is what the
# expected string of a prints case usually holds.
prints() {
  check "$1" "$3" "$(out "$2")"
}

raises() {
  check "$1" "$3" "$(err "$2")"
}

exits() {
  status=0
  printf '%s\n' "$2" | "$BIN" >/dev/null 2>&1 || status=$?
  check "$1" "$3" "$status"
}

# One depth guard: run the word with the number of items it wants less one, and
# expect the error rather than a wild read. The count reads as the word's
# requirement minus one, so the guards file is also the one place every word's
# arity is written down.
guards() {
  guard_name="$1"
  guard_source="$2"
  guard_depth="$3"
  guard_message="${4:-aforth: data stack underflow}"
  guard_stack=""
  guard_i=0
  while [ "$guard_i" -lt "$guard_depth" ]; do
    guard_stack="$guard_stack 0"
    guard_i=$((guard_i + 1))
  done
  check "$guard_name guards its depth" "$guard_message" \
    "$(err "$guard_stack $guard_source")"
}

. "$HERE/cases/stack.sh"
. "$HERE/cases/arithmetic.sh"
. "$HERE/cases/memory.sh"
. "$HERE/cases/output.sh"
. "$HERE/cases/input.sh"
. "$HERE/cases/parsing.sh"
. "$HERE/cases/outer.sh"

# The guards have nothing to fire in the build that compiles them out, which is
# the point of that build, so the whole file is left out of it. make passes its
# assembler flags in AFORTH_ASFLAGS so that this can tell.
case "${AFORTH_ASFLAGS:-}" in
  *-DAFORTH_NO_STACK_CHECKS*)
    echo "skip - the depth guards (built without them)"
    ;;
  *)
    . "$HERE/cases/guards.sh"
    ;;
esac

# Every word needs a case.
#
# It takes the name out of every DEFCODE and DEFWORD in the sources and fails
# naming any word no case mentions. A hidden word is skipped: (STOP) cannot be
# reached by name.
#
# It is a search for the name, not proof that the case tests the word. A case
# still has to be written so that it fails when the word is broken.
#
# A case file is split on white space and each token stripped of one quote at
# either end, so that the word in '1 7 DUP .S' is found as DUP and the word in
# "' fnord" as ' .
case_tokens=$(cat "$HERE"/cases/*.sh |
  tr '\t' ' ' | tr ' ' '\n' |
  sed -e p -e "s/^[\"']//" -e "s/[\"']\$//" |
  sed '/^$/d' | sort -u)

uncovered=$(
  grep -hE '^[[:space:]]+DEF(CODE|WORD)' "$HERE"/../src/words/*.S \
      "$HERE"/../src/interpreter.S |
    grep -v F_HIDDEN |
    sed -e 's/^[^"]*"//' -e 's/".*$//' |
    sort -u |
    while read -r word; do
      printf '%s\n' "$case_tokens" | grep -qxF -- "$word" ||
        printf '%s ' "$word"
    done
)

check "every word has a case" "" "$uncovered"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
