# Testing

How aforth is tested. The suite is `test/run-tests.sh`, the cases are in
`test/cases/`, and `make test` runs both after it has built the binary.

## One suite, driven by Forth source

Every case pipes Forth source into the built binary and compares what comes
out. A case is its name, that source, and what the source should print. Each
case gets its own run of the binary, because the binary reads until end of
input. A run costs about four milliseconds, so the whole suite takes three
seconds and a case per word costs nothing.

Every run goes through `perl -e 'alarm shift; exec @ARGV'`, which kills a binary
that has not finished in ten seconds. A definition can branch, so a word can
loop forever, and one that does would hang the whole suite instead of failing
its own case. An alarm survives `exec`, so this costs one extra process per case
and leaves nothing running afterwards; perl is on both platforms, and `timeout`
is on neither by default on macOS. A case that is killed fails on what it did
not print, and an `exits` case sees 142.

`test/run-tests.sh` holds the helpers, the order the case files run in, and the
coverage check. It sources one file per kind of word from `test/cases/`, and
those names mirror `src/words/`, so a new word's case has one obvious home.

| File | What it covers |
|------|----------------|
| `stack.sh` | the stack shuffles, the return stack transfers, `PICK` and `ROLL` |
| `arithmetic.sh` | the arithmetic, the mixed precision, the logic, the comparisons |
| `memory.sh` | `@ ! C@ C!` and the rest that address memory, and dictionary allocation |
| `output.sh` | everything that prints, `BASE`, the pictured output, and `WORDS` |
| `input.sh` | `SOURCE >IN SOURCE-ID REFILL ACCEPT KEY EVALUATE` |
| `file.sh` | the file words, and the files they read |
| `parsing.sh` | the parsers, the search, and the number conversion |
| `compile.sh` | `:` and `;`, the defining words, and what `STATE` makes the loop do |
| `control.sh` | `IF ELSE THEN BEGIN UNTIL WHILE REPEAT AGAIN`, `EXIT` and `RECURSE` |
| `outer.sh` | the `QUIT` loop, its error messages, `ABORT`, `QUIT`, `BYE` |
| `startup.sh` | the command line, and the two files cold start reads |
| `system.sh` | the words `lib/aforth.f` defines rather than the assembly |
| `guards.sh` | the depth and room guard of every word that reads or fills a stack |

## Writing a case

Four helpers. Each takes the case's name first, then the Forth source, then
what that source should produce.

| Helper | Compares |
|--------|----------|
| `prints name source expected [args]` | stdout, the banner line dropped |
| `raises name source expected [args]` | stderr, stdout dropped |
| `exits name source status [args]` | the process's exit status |
| `guards name source depth [message]` | stderr, after pushing `depth` zeros |
| `room name line` | stderr and the count of lines reporting ok, on a full stack |

```sh
prints "ROT brings the third up" '9 1 2 3 ROT .S' '<4> 9 2 3 1  ok'
raises "/ by zero"               '1 0 /'          'aforth: divide by zero'
exits  "BYE exits successfully"  '1 . BYE'        0
guards "ROT"                     'ROT'            2
```

### Every case runs with `--no-init`

`DEFAULT_ARGS` in `test/run-tests.sh` is the command line a case gets when it
names none, and it is `--no-init`. Without it a developer's own `init.f` could
change a result, and a case would pass on one machine and fail on another. The
system file that ships with aforth still loads, so the suite exercises it on
every run. `make bench` passes the flag for the same reason.

The fourth argument of `prints`, `raises` and `exits` replaces that command
line. Leaving it off is not the same as passing an empty string: off means
`--no-init`, and empty means no arguments at all.

```sh
raises "an unknown argument" '' 'aforth: unknown argument: --wat' '--wat'
prints "no arguments at all" '1 .' '1  ok' ''
```

Only `test/cases/startup.sh` uses it.

### A case about an init file points `XDG_CONFIG_HOME` somewhere else

`test/cases/startup.sh` is the one file whose cases read the user's `init.f`,
and every one of them would otherwise read whatever the developer has in
`~/.config/aforth`. So it makes a `mktemp -d` directory and exports
`XDG_CONFIG_HOME` at the top, before its first case rather than beside the cases
that care: a case running with no arguments at all reads an init file too.
`HOME` is moved the same way for the one case about the fallback path, and put
back straight afterwards.

The two variables are the whole of what decides where aforth looks, which is
what makes this work at all. See [startup.md](startup.md).

A path that appears in an expected message needs the same treatment an address
does. The system file's path goes through `realpath`, so a case comparing
against it resolves its own temporary directory with `pwd -P` first: on macOS
`mktemp -d` hands back `/var/...`, which is a symlink to `/private/var/...`.

A case that turns a file unreadable with `chmod 000` shows nothing when the
suite runs as root, which it does in the Linux container. Such a case tests
`id -u` and prints `skip -` instead, the way the depth guards do in the build
that compiles them out.

A case runs the binary itself when no helper can give it what it needs. Every
such case is in `test/cases/outer.sh` or `test/cases/startup.sh`.

| What the case needs | Where |
|---------------------|-------|
| the banner line, which every helper drops | the banner case in `outer.sh` |
| output that begins with the banner, so line 1 must survive | the `--help` cases in `startup.sh` |
| an empty argument, which the helpers split away | `--init ''` in `startup.sh` |

Such a case must still name a command line. Outside `test/cases/startup.sh` it
passes `DEFAULT_ARGS` by hand. Otherwise it reads whatever `init.f` the
developer has, and it passes or fails by the machine it ran on. Every case in
`startup.sh` names its own command line already.

A stack effect is asserted by printing the stack with `.S`, so the expected
string reads as the word's stack comment does. A case needing more than one
line puts a newline in the source, which is how the `REFILL`, `ACCEPT` and `KEY`
cases feed the line they will read.

A word that writes needs somewhere to write. `BL WORD` copies the name it parses
to `HERE` and returns that address, which is cell-aligned and which nothing
reads again. That is the scratch the memory cases use.

An address is never in an expected string, the region landing wherever the
process put it. A case about the allocation pointer prints how far it moved —
`HERE 16 ALLOT HERE SWAP - .` — and one about the dictionary's end asks for one
byte more than `UNUSED` says is left, rather than for a number that depends on
how big the built-in dictionary happens to be.

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
`src/words/*.S` and `src/interpreter.S`, and out of every colon definition in
`lib/*.f`, and fails naming any word no case mentions. A hidden word is skipped:
`(STOP)` cannot be reached by name.

The system file is in there because a word written in Forth is as much a word of
aforth's as one written in assembly, and just as easy to add and forget. Its
cases go in `test/cases/system.sh`.

A name the source escapes is unescaped first — `\` and `S"` are two characters
in a `DEFCODE` and one byte each in the dictionary — and each case file is split
on white space and kept three ways: as it stands, without a leading quote, and
without a quote at either end. The middle form is what finds `S"`, because
stripping both ends of `'S"` would take the quote that is part of the name.

It is a search for the name, not proof that the case tests the word. A case
still has to be written so that it fails when the word is broken.

`."` is the one word the check cannot really see. A case file that ends a
double-quoted shell string with a full stop puts a full stop and a quote next to
each other, which is the same two characters as the word, and several cases do.
So `."` would pass this check with no case of its own, and the cases in
`test/cases/compile.sh` are what actually cover it.

A case that needs a file to read makes it rather than checking one in.
`test/cases/file.sh` writes its files with `printf` into a `mktemp -d`
directory when the file is sourced and removes them at the end, because one of
them has no terminator on its last line and an editor would quietly add one.

## Eight ways a case passes while testing nothing

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
  that one still checks how far it lies from `BASE`'s. Writing through `STATE`
  is no longer how its value is set in that case, the interpreter having started
  to read the cell.
- A NUL in what was printed. The shell drops NUL out of `$(...)`, so a line of
  `one` and a line of `one` followed by nine NULs compare equal. The `ACCEPT`
  case passed against an `ACCEPT` broken on purpose for that reason, the bytes
  past the truncation point being the zeros the buffer started with. Print a
  count beside the bytes when a word's job is how many there are, and read a
  zeroed buffer back byte at a time rather than typing it.
- An address in the expected string. The region lands wherever the process put
  it, so a case prints a difference or a flag instead: `STATE BASE - .`, or
  `BL WORD DUP FIND . ' DUP = .`.
- A word the interpreter compiled instead of running. The case for `WORDS`
  leaving out an unfinished definition wrote `WORDS` on the line after a `:`
  that had no `;` yet. `STATE` still said compiling, so the interpreter put
  `WORDS` into the definition and never ran it. The case passed against a
  `WORDS` that listed hidden entries. A case that needs a word to run while a
  definition is open brackets it — `[ WORDS ]` — because `[` is immediate.
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

## A routine with a mathematical contract gets a second check

The suite drives every word from Forth source, which reaches a routine only
through the operands a case can write. `udiv128` is the case in point. Its
corrections run on values that a case reaches only by luck, and that nobody
picks well by hand.

So check a routine like that outside the binary as well. Copy it into a file of
its own and assemble it with a C driver. Compare it against
`unsigned __int128` over millions of random inputs and every edge value.
Extract the routine from the source rather than retyping it, so the test cannot
drift from what ships. The current `udiv128` was run against 25 million cases
that way before it was believed, and the suite passed both before and after.

Nothing in the repository holds that driver. It is twenty lines, written when a
routine needs it and thrown away afterwards.

## Linux

`make docker-test` builds the Linux/ARM64 image in `docker/` and runs `make
test` inside it. The Dockerfile copies `src`, `lib` and `test`, so a new case
file is picked up with no change to it. It names each directory, and the build
inside the image sees nothing else. Add any new top-level directory the build
needs to `docker/Dockerfile`. See [ci.md](ci.md).
