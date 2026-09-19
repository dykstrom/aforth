# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# The file words.
#
# Every case here needs a file with exact bytes to read, including one whose
# last line has no terminator, which an editor would quietly add. So the files
# are made here with printf rather than checked in, and removed at the end.
#
# A fileid is a descriptor and an ior is an errno. ENOENT is 2 and EBADF is 9 on
# both platforms, so a case asserts those as plain numbers. See
# docs/system/files.md.
#
# Sourced by test/run-tests.sh, which defines prints, raises, exits and guards.

FILE_DIR=$(mktemp -d)
printf 'one\ntwo\nthree\n'  > "$FILE_DIR/three"
printf 'alpha\nbeta'        > "$FILE_DIR/noeol"
printf 'a\r\nbb\r\n'        > "$FILE_DIR/crlf"

# The files the include cases read. A name inside one of them is resolved
# against the working directory rather than the including file's directory, so
# every name here is absolute.
printf ': SQ DUP * ;\n5 SQ .\n'                    > "$FILE_DIR/lib.f"
printf '\n'                                        > "$FILE_DIR/empty.f"
printf ': F\n  1 2 +\n  . ;\nF\n'                  > "$FILE_DIR/multi.f"
printf 'hello\n'                                   > "$FILE_DIR/bad.f"
printf 'SOURCE-ID .\n'                             > "$FILE_DIR/sid.f"
printf '1 2 ABORT 3\n'                             > "$FILE_DIR/ab.f"
printf '1 2 QUIT 3\n'                              > "$FILE_DIR/q.f"
printf '." a" CR\nINCLUDE %s/bad.f\n." b"\n' \
  "$FILE_DIR"                                     > "$FILE_DIR/outer.f"

prints "R/O is a fam"  'R/O .'  '0  ok'

# A descriptor above 2 is what SOURCE-ID needs of a fileid: it has to tell a
# file from the 0 that means the terminal.
prints "OPEN-FILE opens a file" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE . 2 > ." '0 -1  ok'
prints "OPEN-FILE reports a missing file" \
  "S\" $FILE_DIR/nothing-here\" R/O OPEN-FILE . DROP" '2  ok'

# Three lines in the order they are in the file. Each READ-LINE reads a whole
# buffer and seeks back over what came after the newline, so this is the case
# that says the seek left the file where the next line starts.
prints "READ-LINE reads the lines in order" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT F3
HERE 80 F3 READ-LINE . . HERE SWAP TYPE CR
HERE 80 F3 READ-LINE . . HERE SWAP TYPE CR
HERE 80 F3 READ-LINE . . HERE SWAP TYPE CR
F3 CLOSE-FILE ." ' ok
0 -1 one
 ok
0 -1 two
 ok
0 -1 three
 ok
0  ok'

# End of file is a false flag, a zero count and no error at all.
prints "READ-LINE reports the end of a file" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT F4
HERE 80 F4 READ-LINE 2DROP DROP
HERE 80 F4 READ-LINE 2DROP DROP
HERE 80 F4 READ-LINE 2DROP DROP
HERE 80 F4 READ-LINE . . . " ' ok
 ok
 ok
 ok
0 0 0  ok'

# A file whose last line has no newline. That line is a successful read, and
# the call after it is the one that reports the end.
prints "READ-LINE reads an unterminated last line" \
  "S\" $FILE_DIR/noeol\" R/O OPEN-FILE DROP CONSTANT FN
HERE 80 FN READ-LINE . . HERE SWAP TYPE CR
HERE 80 FN READ-LINE . . HERE SWAP TYPE CR
HERE 80 FN READ-LINE . . . " ' ok
0 -1 alpha
 ok
0 -1 beta
 ok
0 0 0  ok'

# A buffer too small for the line. Forth-2012 says the terminator has yet to be
# reached when u1 = u2, and the next call carries on inside the same line.
prints "READ-LINE stops when the buffer is full" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FB
HERE 2 FB READ-LINE . . HERE SWAP TYPE CR
HERE 2 FB READ-LINE . . HERE SWAP TYPE CR" ' ok
0 -1 on
 ok
0 -1 e
 ok'

# A carriage return in front of the newline goes with it, so a file edited on
# Windows gives the same lengths as one edited here.
prints "READ-LINE strips a carriage return" \
  "S\" $FILE_DIR/crlf\" R/O OPEN-FILE DROP CONSTANT FC
HERE 80 FC READ-LINE . . . CR
HERE 80 FC READ-LINE . . . " ' ok
0 -1 1 
 ok
0 -1 2  ok'

# READ-FILE takes a count and does not care where the lines fall. Asking for
# more than is left gives what was left and no error.
prints "READ-FILE reads a count of characters" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FR
HERE 4 FR READ-FILE . HERE SWAP TYPE
HERE 100 FR READ-FILE . . " ' ok
0 one
 ok
0 10  ok'

# Closing twice is EBADF, and so is reading a fileid that was closed. Both say
# the descriptor really went away.
prints "CLOSE-FILE closes once" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FX
FX CLOSE-FILE .
FX CLOSE-FILE ." ' ok
0  ok
9  ok'
prints "reading a closed file reports EBADF" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FY
FY CLOSE-FILE DROP
HERE 80 FY READ-LINE . . . " ' ok
 ok
9 0 0  ok'

# Asking a file about itself.
#
# A size and a position are doubles, so each of these leaves three cells and
# the . . . prints them ior first. The high half is always 0: a cell is 64 bits
# and no file position needs more.

prints "FILE-POSITION starts at the start" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FP
FP FILE-POSITION . . . " ' ok
0 0 0  ok'
prints "FILE-POSITION moves with the reading" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FQ
HERE 80 FQ READ-LINE 2DROP DROP
FQ FILE-POSITION . . . " ' ok
 ok
0 0 4  ok'

prints "FILE-SIZE is the size of the file" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FS
FS FILE-SIZE . . . " ' ok
0 0 14  ok'

# The one the three seeks exist for. Forth-2012 says FILE-SIZE must not affect
# the file position, so the position after it has to be the position before.
prints "FILE-SIZE leaves the file where it was" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FT
HERE 80 FT READ-LINE 2DROP DROP
FT FILE-POSITION . . .
FT FILE-SIZE 2DROP DROP
FT FILE-POSITION . . . " ' ok
 ok
0 0 4  ok
 ok
0 0 4  ok'

# Three cells and no more: the third DROP would underflow if the double were
# one cell, and the stack is empty afterwards.
prints "FILE-SIZE leaves a double and an ior" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FU
FU FILE-SIZE DROP DROP DROP DEPTH ." ' ok
0  ok'

prints "REPOSITION-FILE moves the file" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FV
HERE 80 FV READ-LINE 2DROP DROP
0 0 FV REPOSITION-FILE .
HERE 80 FV READ-LINE . . HERE SWAP TYPE" ' ok
 ok
0  ok
0 -1 one ok'

# A high half that is not 0 names a position no off_t holds. EINVAL is 22 on
# both platforms, and the file does not move.
prints "REPOSITION-FILE refuses a position too large" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FW
HERE 80 FW READ-LINE 2DROP DROP
0 1 FW REPOSITION-FILE .
FW FILE-POSITION . . . " ' ok
 ok
22  ok
0 0 4  ok'

# FILE-STATUS answers one question and opens nothing. x is 0 and says nothing.
prints "FILE-STATUS finds a file" \
  "S\" $FILE_DIR/three\" FILE-STATUS . ." '0 0  ok'
prints "FILE-STATUS reports a missing file" \
  "S\" $FILE_DIR/nothing-here\" FILE-STATUS . ." '2 0  ok'

prints "FILE-SIZE on a closed file reports EBADF" \
  "S\" $FILE_DIR/three\" R/O OPEN-FILE DROP CONSTANT FZ
FZ CLOSE-FILE DROP
FZ FILE-SIZE . 2DROP
FZ FILE-POSITION . 2DROP" ' ok
 ok
9  ok
9  ok'

# Including a file.
#
# Forth-2012 makes all three words close the file at the end, and aforth closes
# it on the path an error takes as well. See docs/system/files.md.

prints "INCLUDE runs the file" \
  "INCLUDE $FILE_DIR/lib.f" '25  ok'

# The rest of the calling line has to survive the include, which is what the
# file's own line buffer is for: reading into the shared one would overwrite it.
prints "INCLUDE leaves the rest of the line to run" \
  "INCLUDE $FILE_DIR/lib.f 7 SQ ." '25 49  ok'

prints "INCLUDED takes the name from the stack" \
  "S\" $FILE_DIR/lib.f\" INCLUDED" '25  ok'

prints "INCLUDE-FILE takes an open file" \
  "S\" $FILE_DIR/lib.f\" R/O OPEN-FILE DROP INCLUDE-FILE" '25  ok'

prints "a definition may span the lines of a file" \
  "INCLUDE $FILE_DIR/multi.f" '3  ok'

# A descriptor is never 0, 1 or 2, so a fileid tells a file from the terminal.
prints "SOURCE-ID is the fileid inside a file and 0 after it" \
  "INCLUDE $FILE_DIR/sid.f SOURCE-ID ." '3 0  ok'

# The same descriptor comes back, which is how the suite sees that the include
# closed the file. A fresh open takes the lowest one free.
prints "INCLUDE closes the file" \
  "S\" $FILE_DIR/empty.f\" R/O OPEN-FILE DROP DUP . CLOSE-FILE DROP
INCLUDE $FILE_DIR/empty.f
S\" $FILE_DIR/empty.f\" R/O OPEN-FILE DROP ." '3  ok
 ok
3  ok'

prints "an error inside a file still closes it" \
  "S\" $FILE_DIR/empty.f\" R/O OPEN-FILE DROP DUP . CLOSE-FILE DROP
INCLUDE $FILE_DIR/bad.f
S\" $FILE_DIR/empty.f\" R/O OPEN-FILE DROP ." '3  ok
3  ok'

# The message, then one line per file, innermost first. include_impl writes
# each line as it unwinds, because the name and the line number live in a frame
# that is gone by the time machine_quit reads the number.
raises "an error in a file names the file and the line" \
  "INCLUDE $FILE_DIR/bad.f" "aforth: undefined word: hello
aforth:   in $FILE_DIR/bad.f, line 1"

raises "a file that included one is named too" \
  "INCLUDE $FILE_DIR/outer.f" "aforth: undefined word: hello
aforth:   in $FILE_DIR/bad.f, line 1
aforth:   included from $FILE_DIR/outer.f, line 2"

# INCLUDE-FILE is handed a descriptor and never sees a name.
raises "INCLUDE-FILE has no name to give" \
  "S\" $FILE_DIR/bad.f\" R/O OPEN-FILE DROP INCLUDE-FILE" \
  "aforth: undefined word: hello
aforth:   in a file, line 1"

# The error ends the file and the rest of the calling line, and the next line
# typed still runs. That is what ABORT means, and an error is one.
prints "an error in a file drops the rest of the calling line" \
  "INCLUDE $FILE_DIR/bad.f 1 .
2 ." '2  ok'

# INCLUDED and INCLUDE have no ior in their stack effects, so a file that will
# not open is an error that names it.
raises "INCLUDE reports a file it cannot open" \
  "INCLUDE $FILE_DIR/nothing-here" \
  "aforth: cannot open file: $FILE_DIR/nothing-here"
raises "INCLUDED reports a file it cannot open" \
  "S\" $FILE_DIR/nothing-here\" INCLUDED" \
  "aforth: cannot open file: $FILE_DIR/nothing-here"
raises "INCLUDE with no name left on the line" 'INCLUDE' 'aforth: name expected'

# ABORT and QUIT are not failures. Both return to the terminal and say nothing,
# and they differ in what they empty.
prints "ABORT inside a file says nothing and empties the data stack" \
  "9 INCLUDE $FILE_DIR/ab.f
DEPTH ." '0  ok'
prints "QUIT inside a file leaves the data stack alone" \
  "9 INCLUDE $FILE_DIR/q.f
DEPTH ." '3  ok'

# Eight levels of source, so the ninth has nowhere to go. The terminal holds
# the first, which is why d8.f is the file that fails rather than d9.f.
i=1
while [ "$i" -le 9 ]; do
  printf 'INCLUDE %s/d%s.f\n' "$FILE_DIR" "$((i + 1))" > "$FILE_DIR/d$i.f"
  i=$((i + 1))
done
printf '." bottom"\n' > "$FILE_DIR/d10.f"

raises "a ninth input source is too deep" \
  "INCLUDE $FILE_DIR/d1.f" \
  "aforth: input sources nested too deep
aforth:   in $FILE_DIR/d8.f, line 1
aforth:   included from $FILE_DIR/d7.f, line 1
aforth:   included from $FILE_DIR/d6.f, line 1
aforth:   included from $FILE_DIR/d5.f, line 1
aforth:   included from $FILE_DIR/d4.f, line 1
aforth:   included from $FILE_DIR/d3.f, line 1
aforth:   included from $FILE_DIR/d2.f, line 1
aforth:   included from $FILE_DIR/d1.f, line 1"

# A file line that fills the buffer with no terminator after it is a line
# missing its tail, which is what the terminal raises for too. The file arm
# cannot see the newline one byte past the buffer, so a file line of exactly
# 4096 bytes raises where a typed one of exactly 4096 bytes is accepted. See
# docs/system/input.md.
awk 'BEGIN { while (n++ < 2048) printf "1 " }' > "$FILE_DIR/long.f"
raises "a file line too long for the buffer" \
  "INCLUDE $FILE_DIR/long.f" \
  "aforth: input line too long
aforth:   in $FILE_DIR/long.f, line 1"

rm -rf "$FILE_DIR"
