# The Forth-2012 test suite

The files in this directory are copies from the Forth-2012 test suite. `make
test` runs them through `test/cases/forth2012.sh`. They are not aforth's own
files.

## Source

- Repository: <https://github.com/gerryjackson/forth2012-test-suite>
- Commit: `4c87e5659c5b79bd7a6664daa56603df080c6f9b`, from 5 September 2026
- Directory: `src/`

Gerry Jackson started the suite and maintained it. At this commit, the
upstream README says that the Forth standard committee now maintains it.

## Files and terms

| File | Author | Terms |
|------|--------|-------|
| `tester.fr` | John Hayes, 1995 | "(C) 1995 Johns Hopkins University / Applied Physics Laboratory. May be distributed freely as long as this copyright notice remains." |
| `core.fr` | John Hayes, 1995 | The same notice as `tester.fr`. |
| `coreplustest.fth` | Gerry Jackson, 2007 | Public domain. The notice asks that it is kept. |
| `coreexttest.fth` | Gerry Jackson, 2006, with contributions the file names | Public domain. The notice asks that it is kept. |
| `exceptiontest.fth` | Gerry Jackson, 2006, with contributions the file names | Public domain. The notice asks that it is kept. |
| `errorreport.fth` | Gerry Jackson, 2015 | Public domain. The notice asks that it is kept. |
| `prelimtest.fth` | Gerry Jackson, as the upstream history shows | The file carries no notice, and the upstream repository has no licence file. |
| `utilities.fth` | Gerry Jackson, as the upstream history shows | The file carries no notice, and the upstream repository has no licence file. |

## Rules

- Every file is byte-identical to the commit above. Nobody edits a copy, not
  even to add a licence header. See ADR 0015.
- Anything aforth needs to run the files is in `test/cases/`: the driver
  `forth2012.f`, the case `forth2012.sh`, and the expected output
  `forth2012.out`.
- To update the copies from upstream, follow `docs/system/testing.md`.
