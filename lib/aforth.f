\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykström
\
\ aforth's system file: the part of the system written in Forth rather than in
\ ARM64 assembly.
\
\ Cold start includes this file before the user's own init.f, finding it beside
\ the binary rather than in the working directory, so a word defined here is in
\ the dictionary of every session whatever --no-init says. See
\ docs/system/startup.md.
\
\ A word belongs here when Forth says it more clearly than assembly would and
\ nothing on the dispatch path calls it. One that a benchmark or the inner
\ interpreter reaches stays in src/words/, where it costs one code field
\ instead of a threaded definition.

\ Is test in the half-open range low..high-1?
\
\ One unsigned comparison rather than two signed ones, which is what makes the
\ range wrap correctly and what Forth-2012 describes: both subtractions move
\ the range down to start at zero, and U< then asks the only question left.
: WITHIN ( test low high -- flag ) OVER - >R - R> U< ;
