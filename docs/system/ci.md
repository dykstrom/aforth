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
line tools, and libedit is a system library there. Linux installs `clang`,
`make` and `libedit-dev` with apt. `docker/Dockerfile` installs the same three
and covers the Linux build locally, from a macOS machine.

`libedit-dev` is the package to install, not `libedit`. Ubuntu and Debian ship
`libedit.so.2` in the base image, which is enough to run a binary and not enough
to link one: `-ledit` wants the `libedit.so` symlink, and only the dev package
has it.

## Building the same tree from both platforms

`docker/Dockerfile` copies the source into the image rather than mounting it, so
a build there cannot reach the working tree. A container that mounts the tree
instead — a persistent one kept for testing on Linux — shares `build/` with the
macOS build, and whichever ran last leaves objects the other cannot link:

```
ld: unknown file type in 'build/interpreter.o'
```

Give such a container a directory of its own. `BUILD` is a make variable for
that, and the path must be relative, because the `test` target runs `./$(BIN)`
and an absolute path would make that `.//tmp/...`:

```
make BUILD=build-linux test
```

`.gitignore` matches `build*/`, so a per-platform directory needs no line of its
own. `make clean` on the host is the whole fix when the objects do get mixed.
