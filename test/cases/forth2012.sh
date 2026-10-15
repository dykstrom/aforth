# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The Core and Core Extension files of the Forth-2012 test suite.
#
# The suite's files are in test/forth2012/, copied from upstream and never
# edited (ADR 0015). What aforth adds to run them is here in test/cases/: the
# driver forth2012.f, which includes them in order, and forth2012.out, the
# whole of stdout from a run that passed.
#
# The suite is one run of the binary, not a case per word, so it gets three
# checks of its own instead of the usual helpers. Each prints what it found
# beneath its FAIL line, because a whole run's output does not fit on the
# helpers' one line of expected and actual.
#
#   - Nothing reaches stderr. An undefined word, or anything else that stops a
#     file part way, is reported there with its file and line.
#   - prelimtest and the error report both count no error. The harness prints
#     each failing test as a line of its own, and those are what this shows.
#     A run that stopped part way never printed the report, so it fails here
#     too, with the count missing.
#   - stdout is byte for byte forth2012.out. The suite prints lines that only
#     a reader can judge, the ones beginning YOU SHOULD SEE, and this is what
#     checks them. A failure shows a diff.
#
# The second check is what keeps the third honest: forth2012.out regenerated
# from a run with errors in it still fails here.
#
# aforth resolves a relative name against the working directory, so the run
# happens in test/forth2012/, where the driver can name the files as the
# suite's own runtests.fth does. That needs the binary's absolute path.
#
# The second line on stdin is the one core.fr's ACCEPT test reads. It must be
# the same line as in the command in docs/system/testing.md that regenerates
# forth2012.out.
#
# Sourced by test/run-tests.sh, which defines check, aforth and DEFAULT_ARGS.

SUITE_RUN=$(mktemp -d)
SUITE_BIN=$(cd "$(dirname "$BIN")" && pwd -P)/$(basename "$BIN")

(
  cd "$HERE/forth2012"
  BIN="$SUITE_BIN"
  printf '%s\n' 'S" ../cases/forth2012.f" INCLUDED' 'typed for ACCEPT' |
    aforth $DEFAULT_ARGS 2>"$SUITE_RUN/stderr" | sed 1d >"$SUITE_RUN/stdout"
) || true

# Print what a failed check found, indented beneath its FAIL line.
suite_evidence() {
  sed 's/^/       /'
}

if [ -s "$SUITE_RUN/stderr" ]; then
  suite_stderr="some lines"
else
  suite_stderr="nothing"
fi
check "the Forth-2012 suite writes nothing to stderr" "nothing" "$suite_stderr"
suite_evidence <"$SUITE_RUN/stderr"

suite_prelim=$(sed -nE 's/^([0-9]+) tests? failed out of .*/\1/p' \
  "$SUITE_RUN/stdout")
suite_total=$(sed -nE 's/^Total +(-?[0-9]+).*/\1/p' "$SUITE_RUN/stdout")
suite_counts="prelimtest $suite_prelim, error report $suite_total"
check "the Forth-2012 suite counts no error" \
  "prelimtest 0, error report 0" "$suite_counts"
if [ "$suite_counts" != "prelimtest 0, error report 0" ]; then
  grep -E '^(Error #|INCORRECT RESULT|WRONG NUMBER OF RESULTS)' \
    "$SUITE_RUN/stdout" | suite_evidence || true
fi

if cmp -s "$HERE/cases/forth2012.out" "$SUITE_RUN/stdout"; then
  suite_same="the same bytes"
else
  suite_same="different bytes"
fi
check "the Forth-2012 suite prints what forth2012.out holds" \
  "the same bytes" "$suite_same"
if [ "$suite_same" != "the same bytes" ]; then
  diff -u "$HERE/cases/forth2012.out" "$SUITE_RUN/stdout" | suite_evidence ||
    true
fi

rm -rf "$SUITE_RUN"
