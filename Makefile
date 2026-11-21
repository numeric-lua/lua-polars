SHELL := /bin/sh
ROOT := $(CURDIR)

.PHONY: build test smoke rockspec install clean

PREFIX ?= /usr/local

install:
	@if [ ! -f target/release/libpolars_lua.so ] && [ ! -f target/release/libpolars_lua.dylib ]; then $(MAKE) build; fi
	./scripts/install.sh $(PREFIX)

build:
	./scripts/build.sh

test:
	./scripts/test.sh

smoke:
	./scripts/smoke.sh

rockspec:
	./scripts/rockspec.sh

clean:
	rm -rf target .cargo
