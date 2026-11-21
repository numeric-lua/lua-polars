SHELL := /bin/sh
ROOT := $(CURDIR)

.PHONY: build test smoke clean

build:
	./scripts/build.sh

test:
	./scripts/test.sh

smoke:
	./scripts/smoke.sh

clean:
	rm -rf target .cargo
