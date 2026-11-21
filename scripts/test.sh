#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/scripts/ensure-bridge.sh"
SUFFIX=so
[ "$(uname -s)" = "Darwin" ] && SUFFIX=dylib
LIB=${POLARS_LUA_LIB:-"$ROOT/target/release/libpolars_lua.$SUFFIX"}
LUA_PATH="$ROOT/?.lua;$ROOT/?/init.lua;;" \
POLARS_LUA_LIB="$LIB" \
  "${LUA:-luajit}" "$ROOT/tests/run.lua"
