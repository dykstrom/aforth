# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# aforth build. make and clang only, per docs/architecture/design-goals.md.

BIN_NAME := aforth
SRC_DIR  := src
LIB_DIR  := lib
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

# The system file, staged beside the binary. Cold start finds it by the
# executable's own path, so it has to be next to the binary rather than next to
# the source. See docs/system/startup.md.
SYSFILE := $(BUILD)/$(BIN_NAME).f

.PHONY: all run test bench clean docker-test docker-bench

all: $(BIN) $(SYSFILE)

# The library goes after the objects: a shared library named before the objects
# that need it satisfies nothing, and the Linux linker then drops it.
$(BIN): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

$(BUILD)/%.o: $(SRC_DIR)/%.S | $(BUILD)
	$(CC) $(ASFLAGS) -c -o $@ $<

$(SYSFILE): $(LIB_DIR)/$(BIN_NAME).f | $(BUILD)
	cp $< $@

$(BUILD):
	mkdir -p $(BUILD)

run: all
	./$(BIN)

# The flags go to the suite because it has to know what is in the binary: the
# build without the stack guards has no guard to fire, so the cases that expect
# a guard's message are skipped there rather than failing.
test: all
	AFORTH_ASFLAGS='$(ASFLAGS)' $(TEST_DIR)/run-tests.sh ./$(BIN)

# The benchmark. Not part of test, which has to stay fast: one run of bench is
# half a minute, and the point of it is a number rather than a pass or a fail.
# BENCH_FILE names one of the benchmarks in test/bench; BENCH_ITERS, BENCH_REPS
# and BENCH_POINTS are there for a slower machine, a quicker answer, or a
# figure worth trusting to the last per cent -- three points or more is what
# makes the drift column report anything.
#
# The count is large on purpose. run-bench.sh times from BENCH_ITERS/2 up to
# BENCH_ITERS, and a core coming out of idle takes about a second to reach its
# top clock, so the smaller point has to be long enough to be past that or the
# figure comes out several per cent high. See docs/system/benchmark.md.
#
# The suite times other Forths the same way, which is not something make can
# know about: test/bench/run-bench.sh takes a list of systems.
BENCH_FILE   := mix
BENCH_ITERS  := 200000000
BENCH_REPS   := 7
BENCH_POINTS := 2

# --no-init goes here rather than in run-bench.sh, which runs whatever command
# it is handed: the point of that harness is to time aforth against arm64th and
# SwiftForth, and neither of those understands the flag.
bench: all
	$(TEST_DIR)/bench/run-bench.sh -f $(BENCH_FILE) -n $(BENCH_ITERS) \
	  -r $(BENCH_REPS) -p $(BENCH_POINTS) './$(BIN) --no-init'

# Linux/ARM64 build and test, per the portability goal.
docker-test:
	docker build --platform linux/arm64 -f docker/Dockerfile -t aforth-linux .
	docker run --rm --platform linux/arm64 aforth-linux

# The Linux/ARM64 benchmark. On an Apple silicon host this runs in a virtual
# machine, so the figure carries that; see docs/system/benchmark.md.
docker-bench:
	docker build --platform linux/arm64 -f docker/Dockerfile -t aforth-linux .
	docker run --rm --platform linux/arm64 aforth-linux \
	  make BENCH_FILE=$(BENCH_FILE) BENCH_ITERS=$(BENCH_ITERS) \
	  BENCH_REPS=$(BENCH_REPS) BENCH_POINTS=$(BENCH_POINTS) bench

clean:
	rm -rf $(BUILD)

-include $(DEPS)
