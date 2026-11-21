#!/bin/sh
# Install lua-polars into a temporary prefix and load it without
# POLARS_LUA_LIB, proving that the installed module finds its bridge.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lua-polars-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM
PREFIX="$TMP/prefix"

unset POLARS_LUA_LIB
"$ROOT/scripts/install.sh" "$PREFIX" >/dev/null

(
  cd "$TMP"
  LUA_PATH="$PREFIX/share/lua/5.1/?.lua;$PREFIX/share/lua/5.1/?/init.lua;;" \
    "${LUA:-luajit}" "$ROOT/tests/install_smoke.lua" \
      "$PREFIX" "$ROOT/tests/fixtures/sample.csv"
)
