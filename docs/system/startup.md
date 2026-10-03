# Start-up

What happens between the process starting and the first line being read. The
entry point is `main` in `src/aforth.S`, the region and the dictionary are
`machine_init` and `machine_load_dictionary` in `src/machine.S` and
`src/interpreter.S`, and the loop at the end is `machine_quit` in
`src/outer.S`.

## The order `main` runs in

1. Save `x19` to `x28`, and `argc` and `argv`, in a 112-byte frame. The C
   runtime expects those ten registers back, and `machine_init` hands eight of
   them to the Forth machine.
2. `setlocale(LC_CTYPE, "")`, before anything touches text and before libedit
   is first called. Without it the process runs in the C locale and editing
   treats each byte of a multi-byte character as a character (ADR 0004).
3. `machine_init`, which carves the region, fills the index-to-address table
   and copies the dictionary image into it.
4. `args_parse`, which reads the command line. `--help` is answered here and
   ends the run at step 4, exiting 0 without reaching the banner.
5. The banner, through `puts_stdout`.
6. `cold_start`, which reads the two init files.
7. `machine_quit`, which reads and runs Forth until `BYE` or end of input.

The banner comes before cold start rather than after it, so aforth has said
what it is before an init file prints or fails, and so that the banner is the
first line on file descriptor 1 whatever an init file does afterwards. The test
suite depends on the second half of that: `out` in `test/run-tests.sh` drops
line 1 and compares the rest.

Entry is `main` rather than `_start`, so the C runtime initialises libc first.
That follows from the design goal of calling libc rather than raw syscalls.

## The command line

Three flags. `--no-init` and `--init` are required by ADR 0003; `--help` is
what tells a user the other two are there.

| Argument | What it does |
|----------|--------------|
| `--help` | print the arguments on file descriptor 1 and exit 0 |
| `--no-init` | do not read the user's `init.f` |
| `--init <file>` | read `<file>` instead of the user's `init.f` |

`--no-init` drops the user's file only. The system file that ships with aforth
still loads, so the test suite exercises it on every run and a broken one
cannot ship unnoticed.

Nothing else is accepted. There is no `--version`, and no positional argument
that runs a script and exits. A file is read with `INCLUDE`. The version is not
missing: the banner prints it on every ordinary run.

`--init=<file>` as one argument is not accepted either. ADR 0003 writes the
two-argument form and that is the only one.

### `--help`

It prints the banner, then the flags, then where `init.f` is looked for. Both
init flags are described in terms of "the user's `init.f`", so the text says
what that is; the path it names is the one `user_init_path` builds, and the two
have to agree.

It goes out on file descriptor 1 through `puts_stdout`, the way the banner
does, because it is output the user asked for rather than an error (ADR 0007).
The version is the `banner` symbol itself, so an ordinary run and `--help`
cannot disagree about it. The rest is one `.asciz` with its line breaks in the
string, ending without one: `puts_stdout` appends exactly one newline.

`--help` is answered where the scan finds it, and the arguments after it are
never looked at.

| Command line | What happens |
|--------------|--------------|
| `--help` | the help, and exit 0 |
| `--help --wat` | the help, and exit 0 — the scan never reaches `--wat` |
| `--wat --help` | `aforth: unknown argument: --wat`, and exit 1 |
| `--init --help` | `--help` is the path, the argument after `--init` being a file name whatever it looks like |

So a line that also holds a mistake still prints the help. Someone asking what
the arguments are is the one person least helped by being told they got one
wrong.

Nothing is read: `--help` returns before the banner, before `cold_start` and
before `machine_quit`, so no init file runs and standard input is never
touched.

### What goes wrong, and what it says

| Command line | Message |
|--------------|---------|
| an argument that is neither flag | `aforth: unknown argument: ` and the argument |
| `--init` with nothing after it | `aforth: --init needs a file` |
| `--no-init` and `--init` together | `aforth: --no-init and --init cannot both be given` |

Each is written on file descriptor 2 and the process exits 1. `args_parse`
runs before the banner, so a command line that fails prints nothing at all on
file descriptor 1.

These are usage errors rather than Forth errors. They happen before the machine
runs, so none goes through `machine_error`, none has an error number, and none
appears in `quit_report`. See [outer-interpreter.md](outer-interpreter.md) for
the errors that do.

The two flags contradict each other, so giving both is an error rather than a
guess about which was meant. `--init` given twice is not an error, and the last
one wins.

### Where the answer goes

`args_parse` returns one of three answers, because a flag that is answered in
full is neither a run nor a failure.

| Return | Means |
|--------|-------|
| `ARGS_RUN` | the command line was read; start the machine |
| `ARGS_FAIL` | it was wrong, and `args_parse` has said so; exit 1 |
| `ARGS_DONE` | it was answered, and there is nothing to run; exit 0 |

It returns rather than calling `exit` itself. `BYE` does call `exit`, because it
fires from inside the Forth machine with no way back to `main`; `args_parse` is
called by `main` and has one, so returning keeps the `x19`-`x28` restore in
`main_exit` honest and leaves the exit status in one place.

What the two init flags decided goes in three user variables, which cold start
reads.

| Cell | Holds |
|------|-------|
| `UV_INIT_ADDR` | the address of the path `--init` named |
| `UV_INIT_LEN` | how long it is, and 0 when there is no `--init` |
| `UV_NO_INIT` | -1 when `--no-init` was given, and 0 otherwise |

That is why `args_parse` runs after `machine_init` rather than before it. The
region is the only writable store aforth has, and nothing in `src/` keeps
writable static data. A command line that fails therefore costs one `mmap`
that the process gives back on exit.

The path is not copied. `argv` lives as long as the process does, so a pointer
into it stays valid for as long as anything could want it.

`args_parse` writes all three whatever the arguments say, so a default does not
depend on the region arriving zeroed.

`argc` is an `int`, so `main` reads `w0` and never the whole of `x0`. The top
half is unspecified, and the two platforms leave different bits there. See
`AGENTS.md`.

## Cold start

`cold_start` in `src/aforth.S` reads two files, in this order.

| File | Where it is | When it is read |
|------|-------------|-----------------|
| `aforth.f` | beside the binary | always |
| `init.f` | `$XDG_CONFIG_HOME/aforth/`, else `$HOME/.config/aforth/` | unless `--no-init` or `--init` said otherwise |

Each is attempted on its own. A failure in the first is reported and the second
is still tried: the point is to leave aforth usable at the prompt rather than to
stop half configured.

Both go through `included_impl` in `src/words/file.S`, the routine `INCLUDED`
and `INCLUDE` use, so an init file is an included file in every respect. What
that means is in [files.md](files.md).

`cold_start` runs outside `aforth_enter`, so it may not raise and may not use a
guard macro: `enter_return` would put `sp` back to a frame that is gone.
`included_impl` reports by returning a number instead, and `cold_report` hands
that number to `quit_report`. See the "Leaving the machine" rules in
[machine-rules.md](../architecture/machine-rules.md).

### The system file

`lib/aforth.f` in the source tree, copied to `build/aforth.f` by `make`. It
holds the part of aforth written in Forth rather than in ARM64 assembly:
`WITHIN`, `*/MOD`, `*/`, `.R`, `U.R`, `.(`, `CHAR`, `INCLUDE`, `VARIABLE`,
`BUFFER:`, `[']`, `DEFER@`, `DEFER!` and `ACTION-OF`.
A word belongs there when Forth says it more clearly than assembly would,
nothing on the dispatch path calls it, and no word written in assembly
compiles it.

`.`, `U.` and `SPACE` pass that rule and stay in assembly all the same. A
binary with no `aforth.f` beside it reports the missing file and still brings
up the prompt, and `.` is what lets that prompt print a number.
`test/cases/startup.sh` checks `1 .` in exactly that case.

It is found beside the binary, not in the working directory: `system_file_path`
in `src/machine.S` asks the platform for the running executable's own path, cuts
back to the last slash and appends `aforth.f`. So `build/aforth` finds
`build/aforth.f` and an installed binary finds its own neighbour, whatever
directory the session was started in. Reading it from the working directory
would run whatever a stranger left in the directory the user happened to be in,
which ADR 0003 forbids for `init.f` and which would be no safer here.

### The user's file

`user_init_path` in `src/machine.S` builds `$XDG_CONFIG_HOME/aforth/init.f`, or
`$HOME/.config/aforth/init.f` when that variable is unset or set to nothing. One
path on both platforms, which is what ADR 0003 decided. With neither variable
set there is no user file and nothing is read.

`--no-init` skips it. `--init <file>` reads that file in its place, wherever it
is.

An init file runs with the working directory the session started in, because
aforth never changes it. A relative name in an `INCLUDE` there resolves against
that directory rather than against the config directory. So an init file that
loads a second file must name it absolutely.

A relative name is worse than broken. In a directory where someone left a file
of that name, aforth runs that file. That is what ADR 0003 forbids for `init.f`
itself. Nothing in the dictionary reads an environment variable, so Forth code
cannot build the config path for itself. See [files.md](files.md).

### What is silent and what is reported

A file aforth was **told** to read reports when it fails; the one it merely
**looks for** does not.

| What happened | What it does |
|---------------|--------------|
| no `init.f` at the config path | nothing at all |
| `init.f` there and it will not open | `aforth: cannot open file: ` and the path |
| the file `--init` named will not open | `aforth: cannot open file: ` and the path |
| no `aforth.f` beside the binary | `aforth: cannot open file: ` and the path |
| an error inside any of them | the error, then `aforth:   in <file>, line <n>` |

So a user with no `init.f` sees nothing and gets nothing: no message, no error,
no exit status, and no directory or file made on their behalf, which ADR 0003
requires. `cold_start` asks `file_status` about the path before opening it, and
a path nothing answers to is dropped without a word. A file that is there and
still will not open is a different thing, and `included_impl` reports it.

None of this changes the exit status. Every one of these leaves the prompt to
come up, and the process exits 0 at the end of input as it always did. A command
line that will not parse is the only thing at start-up that exits 1.

An error inside an init file leaves both stacks and `STATE` as they were when it
unwound, and `cold_start` does nothing about it: `machine_quit` begins by
emptying the stacks, clearing `STATE` and dropping every input source above the
terminal, so the first prompt is clean whatever happened.

### Finding the executable

The one platform difference the init files add, and it is in
`src/include/platform.h` with the rest. `exec_path_raw_def` defines a routine
that fills a buffer with the running executable's path:

| Platform | How |
|----------|-----|
| macOS | `_NSGetExecutablePath`, whose second argument is a pointer to a `uint32_t` holding the buffer size |
| Linux | `readlink` on `/proc/self/exe`, which returns a length and writes no terminator |

The macro is instantiated once, in `src/machine.S`. A second instantiation would
be a duplicate symbol, which is the right way to be told about it.

`exec_path` puts the answer through `realpath` on both platforms. Only macOS
needs it — it hands back the path as the process was invoked, so `./build/aforth`
comes back relative and a symlinked install comes back as the symlink — but
running it everywhere means the two platforms answer the same way, and it is one
call on Linux, which resolves `/proc/self/exe` already. `realpath` wants a buffer
of at least `PATH_MAX`, which `PATH_BUF` is on both: 1024 on macOS and 4096 on
Linux.

## Where the tests are

`test/cases/startup.sh` for the command line and the two init files, and
`test/cases/system.sh` for the words `lib/aforth.f` defines.

Every case in `startup.sh` names its own command line as the fourth argument of
`prints`, `raises` or `exits`, which is what stops the suite adding `--no-init`
to it. The cases about the config file name `''` instead, which is no arguments
at all.

That file also exports `XDG_CONFIG_HOME` into a `mktemp -d` directory before its
first case, so that no case reads the developer's own `~/.config/aforth`, and
moves `HOME` for the one case about the fallback path.

Every other case in the suite runs with `--no-init`, so that a developer's own
`init.f` cannot change a result. `make bench` passes it too. The system file
loads on all of them, which is what keeps a broken one from shipping unnoticed.
See [testing.md](testing.md).
