\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykström
\
\ Runs the Core and Core Extension files of the Forth-2012 test suite, in the
\ order the suite's own runtests.fth gives them, and prints the error report.
\
\ test/cases/forth2012.sh includes this from test/forth2012/, the directory
\ that holds the suite, so the names below have no path. aforth resolves a
\ relative name against the working directory, not against this file.
\
\ core.fr tests ACCEPT, which reads the line after the one that includes this
\ file. The case types that line.

S" prelimtest.fth" INCLUDED
S" tester.fr" INCLUDED
S" core.fr" INCLUDED
S" coreplustest.fth" INCLUDED
S" utilities.fth" INCLUDED
S" errorreport.fth" INCLUDED
S" coreexttest.fth" INCLUDED

REPORT-ERRORS
