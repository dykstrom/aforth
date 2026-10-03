# 0013. Give every dictionary entry a does-cell below its code field

*2026-09-26*

## Context

A word made by `CREATE` and given its behaviour by `DOES>` has to find two things when it runs: its body, and the token list after `DOES>`. A code field holds an index into a table filled at start-up (ADR 0005), and aforth generates no code at run time. So a `DOES>` word cannot have a routine of its own, and all of them share one routine, `DODOES`, which must read the token list's place from the entry. The first alternative put that place in the first cell of the body and started the body one cell later. Then `>BODY` would have to read the code field to know where the body starts, and `DOVAR` and `>BODY` would no longer agree for every word. The second alternative gave the extra cell only to entries that `CREATE` makes. Then the offset from the name to the code field would depend on the kind of entry, and every routine that finds a code field would have to read a flag as well as the name's length.

## Decision

We will give every dictionary entry one cell, the does-cell, between the name's pad and the code field. The does-cell holds the offset from `DBASE` of the token list a `DOES>` word runs, and 0 in every other entry.

## Consequences

The body starts one cell after the code field in every entry, so `DOVAR`, `>BODY` and dispatch do not read the does-cell and did not change. The offset from the name to the code field is still one sum of the name's length, which the `CFOFF` macro holds. The cost is eight bytes on every entry, including every built-in entry, which never uses the cell: an entry with a one-byte name now takes 32 bytes, not 24. The does-cell holds an offset, not an address, so a dictionary with `DOES>` words in it still loads at any address. Any future change to the entry layout must keep the cell directly below the code field, because `DODOES` and `(DOES>)` find it at a fixed distance from there.
