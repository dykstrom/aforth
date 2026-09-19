# 0010. Report a located error as the machine unwinds

*2026-09-16*

## Context

ADR 0008 sends every exit from the Forth machine through one vector. The handler carries an error
number and prints nothing. `machine_quit` reads the number afterwards and `quit_report` builds the
message. That holds as long as every message can be built from the number alone, and until ticket
005 every message could.

Ticket 005 added `INCLUDE-FILE`, `INCLUDED` and `INCLUDE`. An error inside an included file has to
name the file and the line, and neither is readable by the time `machine_quit` runs. `include_impl`
holds the file's line buffer and the copy of its name in its own C stack frame. The buffer is there
because reading into the shared input buffer would destroy the line that called the include. The
line number is in the user variables of the source level that `include_impl` puts back on its way
out. Every one of those frames has been popped before the loop sees the number.

Two other options were weighed. The first copied each name and line into a fixed arena in the user
area as each `include_impl` unwound, so that `quit_report` could print the whole traceback
afterwards. That costs an arena, a length limit on every entry, and a second routine that knows how
a message is shaped. The second reported the line number and no name, so that nothing needed
copying at all. A nested include then cannot say which of the files the line is in, which is most of
the value of reporting a line.

## Decision

We will let a failure whose context is about to be destroyed write its own message as it unwinds,
and then raise `ERR_REPORTED`, an error number with no message of its own. `quit_report` becomes
global, so that a routine reporting early asks it for the message text rather than building one.

## Consequences

The text of every message still lives in one place, and a routine that reports early gets it from
there. What moves is the moment of printing, not the place the words come from. The order comes out
right without any extra bookkeeping: the innermost frame prints the message first, and each frame
above it adds its own line as it unwinds.

`machine_quit` needs no branch for the new number. `quit_report` already returned without printing
for any number above the last one that has a message, so `ERR_REPORTED` joins `ERR_ABORT` and
`ERR_QUIT` above that line and the loop empties both stacks as it does for any failure.

The cost is that a reader can no longer find every message by reading `machine_quit`. A number that
reaches the loop may have printed already, and the only way to tell is that it is `ERR_REPORTED`.
Any routine that reports early therefore has to be sure it reports exactly once, and has to pass
`ERR_ABORT` and `ERR_QUIT` through untouched, because neither is a failure.

This is the shape any later word that installs an input source must follow if it wants to name a
location. Tickets 006 and 007 read an init file at cold start, and an error in one has to say so
the same way.
