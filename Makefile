# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# aforth build. make and clang only, per docs/architecture/design-goals.md.

BIN_NAME := aforth
SRC_DIR  := src
BUILD    := build
TEST_DIR := test

CC       := clang
# .S sources are preprocessed, so -I and -MMD apply as they do for C.
# EXTRA_ASFLAGS is for the command line: a variable set there replaces the
# assignment here rather than adding to it, so ASFLAGS itself cannot be
# extended from outside. Use it as make EXTRA_ASFLAGS=-DAFORTH_NO_STACK_CHECKS.
EXTRA_ASFLAGS :=
ASFLAGS  := -g -Wall -I$(SRC_DIR)/include -MMD -MP $(EXTRA_ASFLAGS)
LDFLAGS  :=
# The line-editing library. aforth links libedit: it needs nothing installed on
# macOS and the libedit-dev package on Linux. Someone building aforth for
# themselves can link GNU readline instead, which exposes the same symbols, by
# overriding this on the command line.
LDLIBS   := -ledit

SRCS := $(wildcard $(SRC_DIR)/*.S)
OBJS := $(SRCS:$(SRC_DIR)/%.S=$(BUILD)/%.o)
DEPS := $(OBJS:.o=.d)
BIN  := $(BUILD)/$(BIN_NAME)

.PHONY: all run test clean docker-test

all: $(BIN)

# The library goes after the objects: a shared library named before the objects
# that need it satisfies nothing, and the Linux linker then drops it.
$(BIN): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

$(BUILD)/%.o: $(SRC_DIR)/%.S | $(BUILD)
	$(CC) $(ASFLAGS) -c -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

run: $(BIN)
	./$(BIN)

# The flags go to the suite because it has to know what is in the binary: the
# build without the stack guards has no guard to fire, so the cases that expect
# a guard's message are skipped there rather than failing.
test: $(BIN)
	AFORTH_ASFLAGS='$(ASFLAGS)' $(TEST_DIR)/run-tests.sh ./$(BIN)

# Linux/ARM64 build and test, per the portability goal.
docker-test:
	docker build --platform linux/arm64 -f docker/Dockerfile -t aforth-linux .
	docker run --rm --platform linux/arm64 aforth-linux

clean:
	rm -rf $(BUILD)

-include $(DEPS)
