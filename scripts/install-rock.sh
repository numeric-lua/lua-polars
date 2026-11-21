#!/bin/sh
# Install the Lua module and native bridge into a LuaRocks build tree.
#
# Usage: install-rock.sh LUADIR LIBDIR
#
# LuaRocks calls this from the rockspec with $(LUADIR) and $(LIBDIR), the
# versioned directories it deploys to the final tree.
set -eu
if [ "$#" -ne 2 ]; then
  echo "usage: $0 LUADIR LIBDIR" >&2
  exit 2
fi
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
LUADIR=$1
LIBDIR=$2
SUFFIX=so
[ "$(uname -s)" = "Darwin" ] && SUFFIX=dylib
LIB=${POLARS_LUA_LIB:-"$ROOT/target/release/libpolars_lua.$SUFFIX"}
if [ ! -f "$LIB" ]; then
  echo "lua-polars: missing native bridge at $LIB" >&2
  exit 1
fi
mkdir -p "$LUADIR/polars" "$LIBDIR"
cp "$ROOT/polars.lua" "$LUADIR/polars.lua"
cp "$ROOT/polars/json.lua" "$LUADIR/polars/json.lua"
cp "$LIB" "$LIBDIR/libpolars_lua.$SUFFIX"
printf 'staged lua-polars rock files in %s and %s\n' "$LUADIR" "$LIBDIR"
