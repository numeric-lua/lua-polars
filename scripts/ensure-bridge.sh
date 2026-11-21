#!/bin/sh
# Ensure the release native bridge exists and is newer than the Rust inputs.
#
# A fresh target/release/libpolars_lua.<ext> is reused, so repeated test and
# LuaRocks install validation does not trigger another Polars build. Missing or
# stale bridges are built incrementally with CARGO_BUILD_JOBS defaulting to 1.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SUFFIX=so
[ "$(uname -s)" = "Darwin" ] && SUFFIX=dylib

if [ -n "${POLARS_LUA_LIB:-}" ]; then
  if [ ! -f "$POLARS_LUA_LIB" ]; then
    echo "lua-polars: POLARS_LUA_LIB does not exist: $POLARS_LUA_LIB" >&2
    exit 1
  fi
  echo "using configured bridge: $POLARS_LUA_LIB"
  exit 0
fi

LIB="$ROOT/target/release/libpolars_lua.$SUFFIX"
if [ -f "$LIB" ]; then
  STALE=$(find "$ROOT/src" "$ROOT/Cargo.toml" "$ROOT/Cargo.lock" \
    -newer "$LIB" -print)
  if [ -z "$STALE" ]; then
    echo "reusing native bridge: $LIB"
    exit 0
  fi
  echo "native bridge is stale ($STALE); rebuilding incrementally" >&2
else
  echo "native bridge is missing; building" >&2
fi

CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-1} "$ROOT/scripts/build.sh"
# Cargo can treat a no-op invocation as finished without relinking. Touching
# the bridge records a successful check so the next call reuses it.
touch "$LIB"
