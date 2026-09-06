# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Johan Dykström

# aforth build. make and clang only, per docs/architecture/design-goals.md.

BIN_NAME := aforth
SRC_DIR  := src
BUILD    := build
TEST_DIR := test

CC       := clang
# .S sources are preprocessed, so -I and -MMD apply as they do for C.
ASFLAGS  := -g -Wall -I$(SRC_DIR)/include -MMD -MP
LDFLAGS  :=

SRCS := $(wildcard $(SRC_DIR)/*.S)
OBJS := $(SRCS:$(SRC_DIR)/%.S=$(BUILD)/%.o)
DEPS := $(OBJS:.o=.d)
BIN  := $(BUILD)/$(BIN_NAME)

.PHONY: all run test clean docker-test

all: $(BIN)

$(BIN): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

$(BUILD)/%.o: $(SRC_DIR)/%.S | $(BUILD)
	$(CC) $(ASFLAGS) -c -o $@ $<

$(BUILD):
	mkdir -p $(BUILD)

run: $(BIN)
	./$(BIN)

test: $(BIN)
	$(TEST_DIR)/run-tests.sh ./$(BIN)

# Linux/ARM64 build and test, per the portability goal.
docker-test:
	docker build --platform linux/arm64 -f docker/Dockerfile -t aforth-linux .
	docker run --rm --platform linux/arm64 aforth-linux

clean:
	rm -rf $(BUILD)

-include $(DEPS)
