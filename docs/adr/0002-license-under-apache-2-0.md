# 0002. License aforth under Apache-2.0

*2026-09-06*

## Context

aforth is public and meant for anyone to use, and it had no LICENSE file, which means all rights
reserved: readers could see the code but not legally reuse it. The choice was open because
[ADR 0001](0001-use-libedit-for-line-editing.md) selected libedit, which is BSD-licensed and places
no requirement on aforth's own license. Warm start is a design goal, so the system will save images
containing its own kernel and users will build turnkey binaries from them; a copyleft license would
extend to those binaries and to the application code inside them. GPLv3 was considered and would
have needed a hand-written exception clause, modelled on the GCC Runtime Library Exception, to keep
saved images usable — and GPLv3 also rules out App Store distribution on the primary platform. MIT
and BSD-2-Clause were considered as shorter permissive alternatives with the same practical effect
as Apache-2.0 but without a patent grant.

## Decision

We will license aforth under Apache-2.0, with copyright held by Johan Dykström. Source files carry
an SPDX identifier (`SPDX-License-Identifier: Apache-2.0`) and a copyright line rather than the
full boilerplate header.

## Consequences

Anyone may use, modify, embed, and sell aforth, including inside a closed turnkey image, so the
warm-start goal and the license do not pull against each other. Contributors and users receive an
explicit patent grant, which MIT and BSD-2-Clause do not provide. A fork may be taken closed; that
is the trade-off accepted in exchange for unrestricted use.

Apache-2.0 code flows into GPLv3 projects but not the reverse, so aforth MUST NOT link a
GPL-licensed library — GNU readline included. This is a new constraint on future dependencies, and
it is the reason the Makefile's line-editing variable defaults to libedit. New source files need the
two SPDX header lines. No NOTICE file exists; if one is ever added, Apache-2.0 section 4(d) requires
redistributors to carry it, so adding one is a deliberate act rather than a formality.
