# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# Linux/ARM64 build and test environment. Build from the repository root:
#   docker build --platform linux/arm64 -f docker/Dockerfile -t aforth-linux .
FROM debian:stable-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends clang make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /aforth
COPY Makefile ./
COPY src src
COPY test test

CMD ["make", "test"]
