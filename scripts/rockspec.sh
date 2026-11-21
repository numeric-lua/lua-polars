#!/bin/sh
# Validate the LuaRocks source-rock build/install path from this checkout.
#
# The version gate runs first, then this reuses or incrementally rebuilds the
# release library, installs the checkout through the rockspec, and requires the
# module from the resulting tree without POLARS_LUA_LIB. Set
# POLARS_LUA_ROCK_TREE to reuse a tree across repeated checks; the default is a
# clean temporary tree. A content stamp skips `luarocks make` when that tree
# already matches the rockspec, Lua modules, install script, and bridge;
# POLARS_LUA_ROCK_FORCE=1 forces a reinstall.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

if [ -n "${POLARS_LUA_ROCK_TREE:-}" ]; then
  TREE=$POLARS_LUA_ROCK_TREE
  mkdir -p "$TREE"
  echo "reusing LuaRocks tree: $TREE"
else
  TMP=$(mktemp -d "${TMPDIR:-/tmp}/lua-polars-rock.XXXXXX")
  trap 'rm -rf "$TMP"' EXIT
  trap 'exit 1' HUP INT TERM
  TREE="$TMP/tree"
fi

set -- "$ROOT"/lua-polars-*.rockspec
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "expected exactly one lua-polars-*.rockspec, found $#" >&2
  exit 2
fi
ROCKSPEC=$1

"$ROOT/scripts/check-version.sh"

cd "$ROOT"
unset POLARS_LUA_LIB
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
"$ROOT/scripts/ensure-bridge.sh"

SUFFIX=so
[ "$(uname -s)" = "Darwin" ] && SUFFIX=dylib
LIB=${POLARS_LUA_LIB:-"$ROOT/target/release/libpolars_lua.$SUFFIX"}
STAMP_FILE="$TREE/.lua-polars-install.stamp"

# Fingerprint everything that ends up in the installed tree. cksum streams the
# large native bridge, so a repeat check avoids reinstalling an unchanged tree.
fingerprint() {
  cksum "$ROCKSPEC" "$ROOT/polars.lua" "$ROOT/polars/json.lua" \
    "$ROOT/scripts/install-rock.sh" "$LIB" |
    cksum | awk '{ print $1 "-" $2 }'
}

installed_module=$(find "$TREE/share/lua" -name polars.lua -print -quit \
  2>/dev/null || true)
installed_bridge=$(find "$TREE/lib/lua" -name "libpolars_lua.$SUFFIX" \
  -print -quit 2>/dev/null || true)
wanted=$(fingerprint)
if [ "${POLARS_LUA_ROCK_FORCE:-0}" != "1" ] && [ -f "$STAMP_FILE" ] &&
  [ "$(cat "$STAMP_FILE")" = "$wanted" ] &&
  [ -n "$installed_module" ] && [ -n "$installed_bridge" ]; then
  echo "reusing installed LuaRocks tree: $TREE"
else
  rm -f "$STAMP_FILE"
  luarocks make --tree="$TREE" --deps-mode=none "$ROCKSPEC"
  printf '%s\n' "$wanted" >"$STAMP_FILE"
fi
eval "$(luarocks path --tree="$TREE")"
"${LUA:-luajit}" "$ROOT/tests/install_smoke.lua" "$TREE" \
  "$ROOT/tests/fixtures/sample.csv"

echo "rockspec check: ok"
