#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SUFFIX=so
[ "$(uname -s)" = "Darwin" ] && SUFFIX=dylib
if [ "$#" -gt 1 ]; then
  echo "usage: $0 PREFIX  (or PREFIX=... $0)" >&2
  exit 2
fi
PREFIX=${1:-${PREFIX:-}}
if [ -z "$PREFIX" ]; then
  echo "usage: $0 PREFIX  (or PREFIX=... $0)" >&2
  exit 2
fi

LIB=${POLARS_LUA_LIB:-"$ROOT/target/release/libpolars_lua.$SUFFIX"}
if [ ! -f "$LIB" ]; then
  "$ROOT/scripts/build.sh"
fi
DEST="$PREFIX/share/lua/5.1"
mkdir -p "$DEST/polars"
cp "$ROOT/polars.lua" "$DEST/polars.lua"
cp "$ROOT/polars/json.lua" "$DEST/polars/json.lua"
cp "$LIB" "$DEST/libpolars_lua.$SUFFIX"
printf 'installed lua-polars into %s\n' "$DEST"
