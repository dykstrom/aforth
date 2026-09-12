# Parsing and name lookup

How a line becomes names, how a name becomes an execution token, and how one
that is not a word becomes a number. The words are in `src/interpreter.S`,
beside the two routines they share: `dict_find` and `digit_value`.

## Cutting a name out of the line

`PARSE-NAME` skips spaces, takes everything up to the next space, and leaves
`>IN` past it. It returns an address inside the input buffer and a length, and
copies nothing; the string is valid until the next `REFILL`. A length of 0
means the line is finished.

A space is the only delimiter `PARSE-NAME` skips. A tab in a line is part of
the name it lands in, so a name typed with a tab in it is not found.

`PARSE` skips nothing and takes its delimiter from the stack, which is what a
comment or a string literal needs. `WORD` skips leading delimiters and copies
what it parses to `HERE` as a counted string, the transient region Forth-2012
allows it — the next `WORD`, or the next thing that allocates, overwrites it. A
name longer than 255 bytes cannot be counted in one byte, so the copy stops at
255 while the parse runs on to the delimiter, leaving `>IN` where it belongs.

`COUNT` turns a counted string into the address and length every other word
takes. `CHAR` is `PARSE-NAME DROP C@`. `[CHAR]`, which compiles rather than
pushes, waits for ticket 010 and the literals it would have nothing to compile
without.

## The search

`dict_find` walks the chain from `LATEST`. Every link is an offset from `DBASE`
and 0 ends the chain, so the walk holds in a process that loaded the image at a
different address. An entry whose flags carry `F_HIDDEN` is stepped over rather
than matched, which is why `(STOP)` cannot be found by name.

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
there. `machine_quit` raises the same error through the same routine, so the
two print the same message.

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
`machine_quit` calls the same routine for every name the dictionary does not
hold, so the word and the interpreter cannot disagree about what a number is.

## Where the tests are

`test/cases/parsing.sh`. A case for one of these words is written on the line
the word parses, and a case for the search or the conversion builds its string
with `WORD` or `PARSE-NAME` rather than naming one in memory. See
[testing.md](testing.md).
