# Testing

How aforth is tested. The suite is `test/run-tests.sh`, the cases are in
`test/cases/`, and `make test` runs both after it has built the binary.

## One suite, driven by Forth source

Every case pipes Forth source into the built binary and compares what comes
out. A case is its name, that source, and what the source should print. Each
case gets its own run of the binary, because the binary reads until end of
input. A run costs about two milliseconds, so the whole suite takes a second and
a half and a case per word costs nothing.

`test/run-tests.sh` holds the helpers, the order the case files run in, and the
coverage check. It sources one file per kind of word from `test/cases/`, and
those names mirror `src/words/`, so a new word's case has one obvious home.

| File | What it covers |
|------|----------------|
| `stack.sh` | the stack shuffles, the return stack transfers, `PICK` and `ROLL` |
| `arithmetic.sh` | the arithmetic, the mixed precision, the logic, the comparisons |
| `memory.sh` | `@ ! C@ C!` and the rest that address memory |
| `output.sh` | everything that prints, `BASE`, and the pictured output |
| `input.sh` | `SOURCE >IN REFILL ACCEPT KEY` |
| `parsing.sh` | the parsers, the search, and the number conversion |
| `outer.sh` | the `QUIT` loop, its error messages, `ABORT`, `QUIT`, `BYE` |
| `guards.sh` | the depth and room guard of every word that reads or fills a stack |

## Writing a case

Four helpers. Each takes the case's name first, then the Forth source, then
what that source should produce.

| Helper | Compares |
|--------|----------|
| `prints name source expected` | stdout, the banner line dropped |
| `raises name source expected` | stderr, stdout dropped |
| `exits name source status` | the process's exit status |
| `guards name source depth [message]` | stderr, after pushing `depth` zeros |
| `room name line` | stderr and the count of lines reporting ok, on a full stack |

```sh
prints "ROT brings the third up" '9 1 2 3 ROT .S' '<4> 9 2 3 1  ok'
raises "/ by zero"               '1 0 /'          'aforth: divide by zero'
exits  "BYE exits successfully"  '1 . BYE'        0
guards "ROT"                     'ROT'            2
```

A stack effect is asserted by printing the stack with `.S`, so the expected
string reads as the word's stack comment does. A case needing more than one
line puts a newline in the source, which is how the `REFILL`, `ACCEPT` and `KEY`
cases feed the line they will read.

A word that writes needs somewhere to write. `BL WORD` copies the name it parses
to `HERE` and returns that address, which is cell-aligned and which nothing
reads again. That is the scratch the memory cases use.

## The depth guards

`test/cases/guards.sh` runs each word with one item too few and expects the
error rather than a wild read. The count is what the case puts on the stack, so
it reads as the word's requirement minus one, and the file is the one place
every word's arity is written down. Give every word that reads a stack a line
there.

The build without the guards has nothing to fire, so `run-tests.sh` leaves the
whole file out of it and says so. `make` passes its assembler flags to the suite
in `AFORTH_ASFLAGS` so that it can tell, which means the flag and the `test`
target must be on one command line:

```
make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS test
```

The same file covers the other half of each guard, `ROOM` and `RROOM`, which
report that a word has nowhere to put what it pushes. Those cases fill a stack
first. The data stack area holds 8192 cells, but 8191 is the deepest a line can
leave it, because `REFILL` needs a cell of its own for the flag it reports with;
so a room case starts at 8191 items and takes the last cell itself with a `DUP`
when the word under test wants one. The return stack holds 8192 and nothing else
pushes there between lines.

Two cases about the return stack live there as well. What `ABORT` and `QUIT`
empty can only be seen through `RNEED`: with the guards compiled out, `R>` on an
emptied return stack reads a cell nobody wrote instead of reporting anything.

## Every word needs a case

The last check takes the name out of every `DEFCODE` and `DEFWORD` in
`src/words/*.S` and `src/interpreter.S` and fails naming any word no case
mentions. A hidden word is skipped: `(STOP)` cannot be reached by name.

It is a search for the name, not proof that the case tests the word. A case
still has to be written so that it fails when the word is broken.

## Seven ways a case passes while testing nothing

Break the word on purpose before trusting a new case, and check that the case
names it. Each of these caught a case that was proving nothing:

- An operand that never reaches the code the case aims at. Two of the
  arithmetic cases passed against a deliberately broken `UM*` and a broken
  `udiv128`, because their operands had an empty high half.
- The same, one layer down: the case for `#` over a double passed against a `#`
  whose division of the high half was broken, because the double it was given
  had a high half smaller than `BASE`.
- A round operand. The `>NUMBER` case for 2^64 passed against a broken multiply,
  because at exactly 2^64 the high half comes from the last digit's carry and
  from neither multiply. Twenty-one nines reaches all three places.
- Anything else that would satisfy the case. The `STATE` case wrote -1 through
  `STATE` and read it back, and it passed against a `STATE` that handed out
  `BASE`'s address: any writable cell gives back what was put in it. A case for
  a word that hands out an address has to pin the address down, which is why
  that one also checks how far it lies from `BASE`'s.
- A NUL in what was printed. The shell drops NUL out of `$(...)`, so a line of
  `one` and a line of `one` followed by nine NULs compare equal. The `ACCEPT`
  case passed against an `ACCEPT` broken on purpose for that reason, the bytes
  past the truncation point being the zeros the buffer started with. Print a
  count beside the bytes when a word's job is how many there are, and read a
  zeroed buffer back byte at a time rather than typing it.
- An address in the expected string. The region lands wherever the process put
  it, so a case prints a difference or a flag instead: `STATE BASE - .`, or
  `BL WORD DUP FIND . ' DUP = .`.
- A message more than one guard can produce. Every `ROOM` case first passed
  against words whose `ROOM` had been left out, because a word that pushes one
  cell too many is caught by `REFILL` at the start of the next line, which says
  `aforth: data stack overflow` too. The case now counts the lines that reported
  ok as well: a word that raised never reported ok for its own line, and one
  whose guard is missing did. Ask which other code could produce the message a
  case expects.

Run that check with `make clean` each time. A file patched or restored in the
same second as the object built from it can leave `make` seeing the object as
current, so the binary under test is the one from the patch before: a break that
is caught looks uncaught, and one round's failure turns up in the next round's
output.

## Linux

`make docker-test` builds the Linux/ARM64 image in `docker/` and runs `make
test` inside it. The Dockerfile copies `src` and `test`, so a new case file is
picked up with no change to it. See [ci.md](ci.md).
