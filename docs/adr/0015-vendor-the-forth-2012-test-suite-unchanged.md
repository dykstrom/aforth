# 0015. Vendor the Forth-2012 test suite unchanged

*2026-10-08*

## Context

`make test` runs the Core files of the Forth-2012 test suite, which other
people wrote and maintain upstream. ADR 0002 gives every source file an
Apache-2.0 SPDX line, but these files are under other terms. Hayes' files may
be distributed only with their notice, Jackson's are in the public domain, and
two carry no notice at all. An Apache-2.0 line on them would state a licence
they do not have. One alternative was a git submodule. The Docker build and
both CI workflows would then have to fetch it, and a plain copy of the
repository would lack it. Another alternative was to download the files when
the suite runs, which would make `make test` need the network. A third
alternative was to copy the files and adapt them, for example their paths or a
header. Then every update from upstream would be a merge.

## Decision

We will copy the suite's files into `test/forth2012/`, byte-identical to one
pinned upstream commit, and never edit them. They carry no SPDX line. A
README in that directory names the commit and each file's author and terms.
Everything aforth needs to run them, such as the order of the files, the
paths and the expected output, lives in aforth's own files in `test/cases/`.

## Consequences

The suite runs offline, everywhere the repository is copied, with no extra
step in Docker or CI. An update is a copy of new files followed by `cmp`, and
a diff against upstream is always empty. The trade-off is that a file in
`test/forth2012/` cannot be fixed in place. A bug in the suite itself has to be
worked around in the driver or reported upstream. The SPDX rule in AGENTS.md
now has an exception, and any later vendored file needs a decision of its own
about its terms.
