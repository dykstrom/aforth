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

# Every case runs the binary through this rather than calling it directly.
#
# A definition can branch, so a word can loop forever, and one that does would
# hang the whole suite instead of failing its own case. perl's alarm kills the
# run after CASE_TIMEOUT seconds: the timer survives exec, so this costs one
# extra process per case and leaves no wrapper running afterwards. perl is on
# both platforms, and timeout is on neither by default on macOS.
#
# A case that is killed fails on what it did not print, and an exits case sees
# 142, which is what a shell reports for a process killed by SIGALRM.
CASE_TIMEOUT=10

if command -v perl >/dev/null 2>&1; then
  aforth() {
    perl -e 'alarm shift; exec @ARGV' "$CASE_TIMEOUT" "$BIN" "$@"
  }
else
  echo "warn - no perl, so a word that loops forever will hang the suite"
  aforth() {
    "$BIN" "$@"
  }
fi

# What a case runs the binary with when it names no command line itself.
#
# --no-init keeps a developer's own init.f out of every result, so that a case
# cannot pass on one machine and fail on another. The system file that ships
# with aforth still loads, so the suite exercises it on every run.
DEFAULT_ARGS='--no-init'

# Run the source in $1 and print what reaches stdout, the banner dropped.
# Errors go to file descriptor 2, so they are not in what this returns.
#
# $2 is the command line, left unquoted so that the shell splits it into
# arguments. Leaving it off is not the same as passing an empty string: off
# means DEFAULT_ARGS, and empty means no arguments at all. That is what
# ${2-...} buys over ${2:-...}.
out() {
  printf '%s\n' "$1" | aforth ${2-$DEFAULT_ARGS} 2>/dev/null | sed 1d
}

# The same, but what reaches file descriptor 2.
err() {
  printf '%s\n' "$1" | aforth ${2-$DEFAULT_ARGS} 2>&1 >/dev/null
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
# prints, raises and exits take a fourth argument, the command line to run the
# binary with. A case that leaves it off gets DEFAULT_ARGS, which is every case
# but the ones in cases/startup.sh.
#
#   raises "an unknown argument" '' 'aforth: unknown argument: --wat' '--wat'
#   prints "no arguments at all" '1 .' '1  ok' ''
#
# A stack effect is asserted by printing the stack with .S , which is what the
# expected string of a prints case usually holds.
prints() {
  if [ $# -gt 3 ]; then check "$1" "$3" "$(out "$2" "$4")"
  else check "$1" "$3" "$(out "$2")"; fi
}

raises() {
  if [ $# -gt 3 ]; then check "$1" "$3" "$(err "$2" "$4")"
  else check "$1" "$3" "$(err "$2")"; fi
}

exits() {
  status=0
  printf '%s\n' "$2" | aforth ${4-$DEFAULT_ARGS} >/dev/null 2>&1 || status=$?
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
. "$HERE/cases/file.sh"
. "$HERE/cases/parsing.sh"
. "$HERE/cases/compile.sh"
. "$HERE/cases/control.sh"
. "$HERE/cases/outer.sh"
. "$HERE/cases/startup.sh"
. "$HERE/cases/system.sh"

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
# It takes the name out of every DEFCODE and DEFWORD in the assembly sources,
# and out of every colon definition in the system file lib/aforth.f, and fails
# naming any word no case mentions. A word written in Forth is as much a word
# of aforth's as one written in assembly, and just as easy to add and forget.
# A hidden word is skipped: (STOP) cannot be reached by name.
#
# It is a search for the name, not proof that the case tests the word. A case
# still has to be written so that it fails when the word is broken.
#
# A case file is split on white space, and each token is kept three ways: as it
# stands, without a leading quote, and without a quote at either end. So the
# word in '1 7 DUP .S' is found as DUP, the word in "'" as ' , and the word in
# 'S" hi" TYPE' as S" — that one needs the middle form, because stripping both
# ends of 'S" would take the quote that is part of the name.
#
# A name the source escapes is unescaped first. Both \\ and \" are two
# characters in DEFCODE and one in the dictionary, and a case that uses one
# writes the one.
#
# A name that a case file could spell by accident is not really checked. ." is
# one: a shell string ending in a full stop puts a full stop and a closing
# quote next to each other, which is the same two characters. The check cannot
# tell them apart, so ." would pass this even with no case of its own.
case_tokens=$(cat "$HERE"/cases/*.sh |
  tr '\t' ' ' | tr ' ' '\n' |
  sed -e p -e "s/^[\"']//" -e p -e "s/[\"']\$//" |
  sed '/^$/d' | sort -u)

defined_words=$(
  grep -hE '^[[:space:]]+DEF(CODE|WORD)' "$HERE"/../src/words/*.S \
      "$HERE"/../src/interpreter.S |
    grep -v F_HIDDEN |
    sed -E -e 's/^[^"]*"((\\.|[^"\\])*)".*$/\1/' \
           -e 's/\\"/"/g' -e 's/\\\\/\\/g'
  sed -nE 's/^: +([^ ]+).*$/\1/p' "$HERE"/../lib/*.f
)

uncovered=$(
  printf '%s\n' "$defined_words" |
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
