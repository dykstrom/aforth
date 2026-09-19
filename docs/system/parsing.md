# Parsing and name lookup

How a line becomes names, how a name becomes an execution token, and how one
that is not a word becomes a number. The words are in `src/words/parsing.S`,
beside the two routines they share: `dict_find` and `digit_value`.

## Cutting a name out of the line

`PARSE-NAME` skips spaces, takes everything up to the next space, and leaves
`>IN` past it. It returns an address inside the input buffer and a length, and
copies nothing; the string is valid until the next `REFILL`. A length of 0
means the line is finished.

A space is the only delimiter `PARSE-NAME` skips. A tab in a line is part of
the name it lands in, so a name typed with a tab in it is not found.

`PARSE` skips nothing and takes its delimiter from the stack, which is what a
comment or a string literal needs. The scan itself is `parse_impl`, which takes
the delimiter in a register: `S"` and `."` call it with a double quote rather
than carrying a second copy of the loop, so there is one place that decides
what a delimiter does and what happens when it never comes. See
[compiling.md](compiling.md). `WORD` skips leading delimiters and copies
what it parses to `HERE` as a counted string, the transient region Forth-2012
allows it — the next `WORD`, or the next thing that allocates, overwrites it, and
`,` and `:` both do. A
name longer than 255 bytes cannot be counted in one byte, so the copy stops at
255 while the parse runs on to the delimiter, leaving `>IN` where it belongs.

## The comment words

`(` and `\` are both immediate, so a comment reads the same way inside a
definition as outside one. Neither parses into a string: each moves `>IN` and
leaves nothing behind.

`(` ends at the first `)`. It does not nest, so `( a ( b )` is one comment and
what follows the `)` is code again.

What it does when the line runs out first depends on where the line came from.
At the terminal and inside a string the comment ends with the line. Waiting at
the terminal for a `)` the user does not know it wants is a trap, and a string
has no next line to read.

From a file it reads on. That is Forth-2012's File-Access word set: "if the end
of the parse area is reached before a right parenthesis is found, refill the
input buffer from the next line of the file, set `>IN` to zero, and resume
parsing, repeating this process until either a right parenthesis is found or
the end of the file is reached." A file cannot trap anyone the way the terminal
can, so the reason for the old behaviour does not hold there.

The standard says nothing about a file that ends before the `)`. aforth raises
`ERR_UNTERMINATED_COMMENT`, which prints `aforth: unterminated comment` and
gets the traceback of the file and the line under it. A missing `)` is almost
always a mistake. `(` refills through `refill_impl` rather than the `REFILL`
word, which is the same routine `include_impl` uses. See
[input.md](input.md).

`\` gives the rest of the line to the comment. It is Forth-2012 Core
Extensions rather than Core, so a program that has to run on a system without
it cannot use it.

Both are written in `src/words/parsing.S`. `\` was the first word whose name
the source escapes — `DEFCODE "\\"` is two characters in the file and one byte
in the dictionary — and `S"`, `."` and `(S")` escape a double quote the same
way. `test/run-tests.sh` unescapes both before it checks that every word has a
case; see [testing.md](testing.md) for the one name that check cannot really
see.

`COUNT` turns a counted string into the address and length every other word
takes. `CHAR` is `PARSE-NAME DROP C@`, and `[CHAR]`, which compiles that byte
rather than pushing it, is in `src/words/compile.S` with the other words that
compile; see [compiling.md](compiling.md).

## The search

`dict_find` walks the chain from `LATEST`. Every link is an offset from `DBASE`
and 0 ends the chain, so the walk holds in a process that loaded the image at a
different address. An entry whose flags carry `F_HIDDEN` is stepped over rather
than matched, which is why `(STOP)` and `(LIT)` cannot be found by name and why
a definition cannot find itself between `:` and `;`.

Folding is ASCII `A`-`Z` against `a`-`z` and nothing else. A byte of 0x80 and
above is compared as it stands, per ADR 0004, so a name in another script
matches byte for byte and never half-folds.

What the search returns is an execution token: the offset of the word's **code
field** from `DBASE`, which is what `EXECUTE` adds `DBASE` to. It is not an
address and not the entry's offset. A name that is not there gives 0, which is
free to mean that because the dictionary's first cell is reserved.

`FIND` is that search over a counted string, reporting 1 for an immediate word
and -1 for any other, and giving the string back under a 0 when there is no
such word. `'` parses the next name and gives its token, and raises
`ERR_UNDEFINED_WORD` when the dictionary does not hold it — `aforth: undefined
word: ` and the name. It keeps the name in x27 and x28 across the search,
because `dict_find` returns in x0 and x1 and `undefined_word` wants the name
there. `interpret_source` reports the same error through the same routine, so
the two print the same message; see
[outer-interpreter.md](outer-interpreter.md) for why one raises and one
returns.

## Numbers

`digit_value` is the one place that knows the digit set and reads `BASE`, the
way `#` is for output. `0` to `9` are themselves and a letter is 10 upward,
folded, so `ff` and `FF` are one number. The characters between `9` and `A` in
ASCII are rejected rather than read as digits above nine, which matters most in
base 16, where `:` would otherwise convert as 3.

`>NUMBER` is the standard word: it accumulates into a double while the
characters convert and stops at the first one that does not, leaving the rest
for the caller. The accumulator is a double, so each step is a double multiply
— the top bits of the low half's product and the high half's own product both
carry up, and the digit's addition carries too.

`?NUMBER ( c-addr u -- n true | c-addr u false )` is not a Forth-2012 word. The
name is the one FIG and F83 used, and it is the conversion the interpreter
wants: a leading minus is allowed, the whole string must convert, and the flag
says which way it went. The number prefixes Forth-2012 allows a text
interpreter — `#`, `$`, `%` and `'c'` — are not implemented.

The conversion itself is `number_impl`, and the word is a call to it.
`interpret_source` calls the same routine for every name the dictionary does
not hold, so the word and the interpreter cannot disagree about what a number
is.

## Where the tests are

`test/cases/parsing.sh`. A case for one of these words is written on the line
the word parses, and a case for the search or the conversion builds its string
with `WORD` or `PARSE-NAME` rather than naming one in memory. See
[testing.md](testing.md).
