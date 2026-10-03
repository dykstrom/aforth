\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykström
\
\ aforth's system file, included at cold start before init.f; see
\ docs/system/startup.md. A word goes here when Forth says it more clearly than
\ assembly, nothing on the dispatch path calls it, and no assembly word compiles
\ it. Words are in the order of the src/words/ files they would otherwise sit in.

\ One unsigned compare after shifting the range to start at zero, so a range
\ that wraps works too.
: WITHIN ( test low high -- flag ) OVER - >R - R> U< ;

: */MOD ( n1 n2 n3 -- n4 n5 ) >R M* R> SM/REM ;
: */ ( n1 n2 n3 -- n4 ) */MOD NIP ;

\ A number wider than the field is printed in full: SPACES ignores a count
\ below one.
: .R ( n1 n2 -- ) >R DUP ABS 0 <# #S ROT SIGN #> R> OVER - SPACES TYPE ;
: U.R ( u n -- ) >R 0 <# #S #> R> OVER - SPACES TYPE ;

: .( ( "ccc<paren>" -- ) [CHAR] ) PARSE TYPE ; IMMEDIATE

\ With no name, CHAR reads the byte just past the parse area. [CHAR] raises
\ ERR_NO_NAME instead, which is why it stays in src/words/compile.S until there
\ is THROW. See docs/system/parsing.md.
: CHAR ( "<spaces>name" -- char ) PARSE-NAME DROP C@ ;

: INCLUDE ( i*x "<spaces>name" -- j*x ) PARSE-NAME INCLUDED ;

\ Forth-2012 leaves the cell undefined; aforth zeroes it.
: VARIABLE ( "<spaces>name" -- ) CREATE 0 , ;

: BUFFER: ( u "<spaces>name" -- ) CREATE ALLOT ;

: ['] ( C: "<spaces>name" -- ) ( -- xt ) ' POSTPONE LITERAL ; IMMEDIATE

\ A deferred word keeps the token it runs in its body.
: DEFER@ ( xt1 -- xt2 ) >BODY @ ;
: DEFER! ( xt2 xt1 -- ) >BODY ! ;
: ACTION-OF ( "<spaces>name" -- xt )
  ' STATE @ IF POSTPONE LITERAL POSTPONE DEFER@ ELSE DEFER@ THEN ; IMMEDIATE
