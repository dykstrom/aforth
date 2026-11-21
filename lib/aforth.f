\ SPDX-License-Identifier: Apache-2.0
\ Copyright 2026 Johan Dykström
\
\ aforth's system file, included at cold start before init.f; see
\ docs/system/startup.md. A word goes here when Forth says it more clearly than
\ assembly, nothing on the dispatch path calls it, and no assembly word compiles
\ it. Words are in the order of the src/words/ files they would otherwise sit in,
\ unless a word uses one that file order would put after it.

\ One unsigned compare after shifting the range to start at zero, so a range
\ that wraps works too.
: WITHIN ( test low high -- flag ) OVER - >R - R> U< ;

: */MOD ( n1 n2 n3 -- n4 n5 ) >R M* R> SM/REM ;
: */ ( n1 n2 n3 -- n4 ) */MOD NIP ;

\ A number wider than the field is printed in full: SPACES ignores a count
\ below one.
: .R ( n1 n2 -- ) >R DUP ABS 0 <# #S ROT SIGN #> R> OVER - SPACES TYPE ;
: U.R ( u n -- ) >R 0 <# #S #> R> OVER - SPACES TYPE ;

\ The buffer fills downward, so the last byte goes in first and the string
\ reads forwards in the result.
: HOLDS ( c-addr u -- ) BEGIN DUP WHILE 1- 2DUP + C@ HOLD REPEAT 2DROP ;

\ A character is a byte (ADR 0004), so a name's first byte is the character,
\ even when it starts a multi-byte one. A line with no name left on it is
\ -16, the code for a missing name, which prints aforth: name expected. See
\ docs/system/parsing.md.
: CHAR ( "<spaces>name" -- char ) PARSE-NAME 0= IF -16 THROW THEN C@ ;
: [CHAR] ( C: "<spaces>name" -- ) ( -- char ) CHAR POSTPONE LITERAL ; IMMEDIATE

\ After [CHAR], which it uses, though the file order would put it first.
: .( ( "ccc<paren>" -- ) [CHAR] ) PARSE TYPE ; IMMEDIATE

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
