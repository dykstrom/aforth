# 0014. Keep fixed system data outside the dictionary image

*2026-09-27*

## Context

`ENVIRONMENT?` answers queries such as `MAX-N` and `STACK-CELLS` from a table
of names and values. Every value is fixed when the binary is built, most of
them from constants in `src/include/machine.h`. The dictionary image is copied
into the writable region at start-up, and it is what warm start will save and
reload. `src/include/dict.h` allows nothing between `DICT_BEGIN` and `DICT_END`
that is not part of an entry. The alternative made the table the body of a
hidden entry, which keeps it in the image and within that rule. It costs
dictionary space and a start-up copy, needs a macro that keeps `dict_off` in
step with every row, and leaves the table in memory a program can write. A
saved image would also carry the table. A later binary with different sizes
that loaded it would then report the old binary's numbers.

## Decision

We will keep data that is fixed when the binary is built, and that no program
writes, outside the dictionary image. It goes in the read-only data of a
source file that is not included between `DICT_BEGIN` and `DICT_END`. The
`ENVIRONMENT?` table is `env_table` in `src/machine.S`.

## Consequences

The answers always describe the binary that is running, also after warm start
loads an image that another build wrote. The table takes no dictionary space,
start-up does not copy it, and a program cannot overwrite it. The cost is that
the data lives in a different file from the word that reads it, so a reader
has to look in two places. A program cannot add its own queries either. That
needs writable dictionary space and a new decision. Data that a program may
change, or that must travel with a saved dictionary, still belongs in the
image.
