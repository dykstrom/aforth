# CI

`.github/workflows/macos.yml` and `.github/workflows/linux.yml` each run `make`
then `make test`. Both trigger on push to `main`, pull requests against `main`,
and manual dispatch.

Linux runs on `ubuntu-24.04-arm`, a native arm64 runner, rather than emulating
arm64 with QEMU on an x86 runner. GitHub gives these runners free minutes only
for public repositories; on a private repository the Linux workflow either finds
no runner or bills for it. Runner labels are pinned — `macos-15`, not
`macos-latest` — so a GitHub image rollover cannot change the build platform
without a commit.

macOS needs no install step: clang and make ship with the runner's Xcode command
line tools. Linux installs `clang` and `make` with apt. `docker/Dockerfile`
covers the same Linux build locally, from a macOS machine.
