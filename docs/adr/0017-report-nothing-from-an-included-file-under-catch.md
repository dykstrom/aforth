# 0017. Report nothing from an included file under CATCH

*2026-11-21*

## Context

ADR 0010 lets `include_impl` print the message and the file and line as it
unwinds, then raise `ERR_REPORTED` so that nothing prints twice. Under `CATCH`
that prints a message for an error the program caught, and it hands the
program -259 instead of the code of what failed. One alternative always
reported, then raised the real code with a flag in the user area telling the
loop the message was out. `CATCH` would get the right code, but a caught error
would still write to stderr. The other alternative left `include_impl` as it
was, so that every failure inside an included file reached `CATCH` as -259.

## Decision

We will have `include_impl` print nothing while a `CATCH` is open and pass the
number up as it came. `UV_CATCH_DEPTH` counts the open `CATCH` frames.

## Consequences

`S" bad.f" ' INCLUDED CATCH` gives -13 for an undefined word and writes nothing
to stderr. With no `CATCH` open, ADR 0010 applies as before, traceback
included. The cost is that a program that catches an error from a file and
throws it again to the prompt gets the message without its file and line,
because the frames that knew them are gone. Any later word that reports early,
as ADR 0010 allows, must read `UV_CATCH_DEPTH` and stay silent the same way.
