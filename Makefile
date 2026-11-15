SHELL := /bin/sh
ROOT := $(CURDIR)

.PHONY: build test clean

build:
	./scripts/build.sh

test:
	./scripts/test.sh

clean:
	rm -rf target .cargo
