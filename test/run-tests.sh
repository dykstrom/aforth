#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Runs the aforth binary and checks its observable behaviour.
# Usage: test/run-tests.sh ./build/aforth

set -eu

BIN="${1:-./build/aforth}"
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

output=$("$BIN")
status=$?

check "prints its banner" "aforth 0.0.0" "$output"
check "exits successfully" "0" "$status"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
