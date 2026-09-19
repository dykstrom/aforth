#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykstrom

# Times one or more Forth systems on a benchmark and prints a table.
# Usage: run-bench.sh [-f FILE] [-n ITERS] [-r REPS] [-p POINTS] [COMMAND ...]
#
# Each COMMAND is a Forth that reads a program on standard input and stops at
# BYE, which is aforth, arm64th and SwiftForth alike. With none given it times
# ./build/aforth.  Prefix one with LABEL= to name it in the table, which is how
# two builds of the same binary are told apart.
#
# Every system is timed at POINTS iteration counts, evenly spaced from ITERS/2
# up to ITERS, and the per-iteration figure is the slope of the least-squares
# line through them. The intercept absorbs everything that does not scale with
# the loop -- process start-up, building the dictionary, reading the file, the
# core clocking up from idle -- so none of it has to be measured, and only the
# slope is reported. Two points make that the plain difference between them;
# more points cost more time and buy a figure that one unlucky run cannot move.
#
# The points start at half of ITERS rather than at a small count on purpose. A
# core coming out of idle takes something like a second to reach its top clock,
# so a short run is slower per iteration than a long one and a line fitted
# through both is bent. Every point being long puts them all past that, at the
# cost of a shorter lever arm. Choose ITERS so that ITERS/2 takes about a
# second in the slowest system being timed.
#
# The drift column is the worst residual as a percentage of the point it
# belongs to, and is the number to look at before believing a small difference
# between two rows: a run on a quiet machine holds it under a percent.
#
# The benchmark prints a line beginning with # holding the values it ended on.
# It is a checksum: every system and every build must print the same line, and
# a row whose line differs is marked rather than compared.
#
# Not part of make test, which has to stay fast. make bench runs this.

set -eu

# Number formatting only: a locale whose decimal separator is a comma would
# otherwise print the table's nanoseconds as 0,522.
LC_NUMERIC=C
export LC_NUMERIC

HERE=$(dirname "$0")
BENCH="$HERE/mix.f"
ITERS=50000000
REPS=7
POINTS=2

while [ $# -gt 0 ]; do
  case "$1" in
    -f) BENCH="$2"; shift 2 ;;
    -n) ITERS="$2"; shift 2 ;;
    -r) REPS="$2"; shift 2 ;;
    -p) POINTS="$2"; shift 2 ;;
    -h|--help) sed -n '5,30p' "$0"; exit 0 ;;
    --) shift; break ;;
    -*) echo "run-bench.sh: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

# A bare name is taken as one of the benchmarks next to this script.
ASKED=$BENCH
[ -f "$BENCH" ] || BENCH="$HERE/$BENCH.f"
[ -f "$BENCH" ] || { echo "run-bench.sh: no such benchmark: $ASKED" >&2; exit 2; }

[ $# -gt 0 ] || set -- ./build/aforth

# How many Forth words one iteration of this benchmark runs, declared by the
# benchmark itself. It is aforth's count: a system that compiles UNTIL to a
# machine branch rather than to a word runs one word fewer.
WPI=$(sed -n 's/^\\ words-per-iteration: *//p' "$BENCH")
[ -n "$WPI" ] || { echo "run-bench.sh: $BENCH declares no words-per-iteration" >&2; exit 2; }

[ "$POINTS" -ge 2 ] || { echo "run-bench.sh: need at least two points" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# The benchmark, with the count it is missing written ahead of it.
script() {  # script COUNT
  printf '%s CONSTANT ITERS\n' "$1"
  cat "$BENCH"
  printf 'BYE\n'
}

counts=
i=1
while [ "$i" -le "$POINTS" ]; do
  n=$((ITERS / 2 + (ITERS / 2) * (i - 1) / (POINTS - 1)))
  script "$n" > "$TMP/$n.f"
  counts="$counts $n"
  i=$((i + 1))
done

# One job per line: the input file, a tab, the command. Every system's points
# go in the one list, so that a single pass of timeit.pl runs all of them and
# interleaves them.
: > "$TMP/jobs"
labels=
for spec in "$@"; do
  case "$spec" in
    *=*) label=${spec%%=*}; cmd=${spec#*=} ;;
    *)   label=$spec;       cmd=$spec ;;
  esac
  for n in $counts; do
    printf '%s\t%s\n' "$TMP/$n.f" "$cmd" >> "$TMP/jobs"
  done
  labels="$labels$label	$cmd
"
done

perl "$HERE/timeit.pl" "$REPS" "$TMP/jobs" > "$TMP/times"

printf '%s, %s to %s iterations over %s points, best of %s, interleaved\n\n' \
  "$BENCH" "$((ITERS / 2))" "$ITERS" "$POINTS" "$REPS"
printf '%-22s %11s %12s %10s %7s  %s\n' \
  system "$ITERS" 'per iter' 'per word' drift result
printf -- '%s\n' \
  '--------------------------------------------------------------------------------'

n=0
echo "$labels" | while IFS='	' read -r label cmd; do
  [ -n "$label" ] || continue
  n=$((n + 1))
  first=$(((n - 1) * POINTS + 1))
  times=$(sed -n "${first},$((first + POINTS - 1))p" "$TMP/times" | tr '\n' ' ')

  # One untimed run for the checksum. Every system and every build must print
  # the same line; one that does not is marked rather than compared.
  got=$($cmd < "$TMP/$ITERS.f" 2>/dev/null | sed -n 's/^#//p' | sed 's/ *$//') || true
  [ -s "$TMP/expect" ] || printf '%s' "$got" > "$TMP/expect"
  if [ "$got" = "$(cat "$TMP/expect")" ]; then mark=ok; else mark="MISMATCH: $got"; fi

  echo "$label|$counts|$times|$WPI|$mark" | awk -F'|' '{
    label = $1; wpi = $4; mark = $5
    np = split($2, xs, " ")
    split($3, ys, " ")
    for (i = 1; i <= np; i++) { sx += xs[i]; sy += ys[i] }
    mx = sx / np; my = sy / np
    for (i = 1; i <= np; i++) {
      num += (xs[i] - mx) * (ys[i] - my)
      den += (xs[i] - mx) * (xs[i] - mx)
    }
    slope = num / den; icept = my - slope * mx
    for (i = 1; i <= np; i++) {
      r = (ys[i] - (icept + slope * xs[i])) / ys[i]
      if (r < 0) r = -r
      if (r > worst) worst = r
    }
    per = slope * 1e6
    # A line through two points fits them exactly, so there is no residual to
    # report and a figure of 0.00% would say more than it knows.
    drift = np > 2 ? sprintf("%6.2f%%", worst * 100) : "     -"
    printf "%-22s %8.1f ms %9.2f ns %7.3f ns %s  %s\n",
           label, ys[np], per, per / wpi, drift, mark
  }'
done
