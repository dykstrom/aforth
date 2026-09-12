# Shipping a Linux binary

> **Working note — not authoritative.** Binding rules live in `architecture/` and `adr/`. Nothing
> here is a rule until it's promoted — however settled it reads.

Status: Research note

Ticket 006 linked libedit, and it linked it dynamically on both platforms. On macOS that settles
nothing to decide: libedit is a system library, at `/usr/lib/libedit.3.dylib`, present on every
machine. On Linux it is a package, and a person who downloads an aforth binary does not have it.
This note records what that costs and what the choices are, so the question is not rediscovered
when a release is cut. The epic has no distribution ticket; nothing here needs doing now.

## Resolved

### A downloaded binary does not start on a stock Debian

Measured on `debian:stable-slim` for arm64, with a binary built by `docker/Dockerfile`:

```
/tmp/aforth: error while loading shared libraries: libedit.so.2:
             cannot open shared object file: No such file or directory
exit status 127
```

The image carries `libtinfo.so.6`, `libbsd.so.0` and `libmd.so.0`, which are what libedit itself
pulls in, but not libedit. The failure is in the dynamic loader, before `main`, so aforth cannot
report it or fall back to reading lines without editing.

The user's fix is one package, and it is the runtime one rather than the one the build needs:
`apt-get install libedit2` on Debian and Ubuntu, `libedit` on Fedora. `libedit-dev` is a build
dependency only, which is why `docker/Dockerfile` and `.github/workflows/linux.yml` install that
one and a user does not need it. With `libedit2` installed, the same downloaded binary runs.

### Warm start does not change the picture

A saved image is data. The code still comes from the executable, and the executable is what names
libedit, so an image imposes no requirement of its own. A turnkey binary in
[ADR 0002](../adr/0002-license-under-apache-2-0.md)'s sense is aforth's executable plus an image,
which needs exactly what the executable needed.

### Four ways to state or remove the requirement

| Level | What it does | Cost |
|-------|--------------|------|
| The ELF's `DT_NEEDED` | Already there. States the need and lets the loader enforce it; cannot satisfy it | none |
| README or release notes | Tells a person to install `libedit2` before running | a sentence |
| A distro package | A `.deb` with `Depends: libedit2`, an `.rpm` with `Requires: libedit`. `dpkg-shlibdeps` derives it from the ELF, and the package manager installs it | packaging per distro |
| Link libedit into the binary | Removes the requirement | a Makefile variable |

### Linking libedit statically works today

No source change, and the transitive libraries have to be named by hand:

```
make LDLIBS="-Wl,-Bstatic -ledit -Wl,-Bdynamic -ltinfo -lbsd -lmd"
```

That binary runs on `debian:stable-slim` with no libedit present. It still needs `libtinfo`,
`libbsd`, `libmd` and glibc, all of which a stock Debian has. libedit is BSD-licensed, so linking
it in raises no licensing question, unlike the GNU readline build a person may make for themselves.

## Open questions

- Which of the four levels a release uses. A README sentence plus a static-libedit Linux build is
  the least work that leaves a working download; a `.deb` is what a distribution expects.
- Whether the static link belongs in the Makefile as a named target, or stays a command-line
  override that the release process spells out.
- Whether a release should ship a binary at all, rather than leaving people to build from source,
  where `libedit-dev` is the only requirement and the build is `make`.
- What a binary release implies for glibc versions. A binary built on Debian stable runs on a
  distribution with the same or newer glibc, and not on an older one. Nothing has been measured.
- macOS has the mirror-image question and a different answer: libedit is present everywhere, so a
  downloaded binary runs, but a Gatekeeper-signed and notarized binary is its own piece of work.
