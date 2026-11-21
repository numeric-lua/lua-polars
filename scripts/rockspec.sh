#!/bin/sh
# Validate the LuaRocks source-rock build/install path from this checkout.
#
# The version gate runs first, then this reuses or incrementally rebuilds the
# release library, installs the checkout through the rockspec, and requires the
# module from the resulting tree without POLARS_LUA_LIB. Set
# POLARS_LUA_ROCK_TREE to reuse a tree across repeated checks; the default is a
# clean temporary tree.
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

luarocks make --tree="$TREE" --deps-mode=none "$ROCKSPEC"
eval "$(luarocks path --tree="$TREE")"
"${LUA:-luajit}" "$ROOT/tests/install_smoke.lua" "$TREE" \
  "$ROOT/tests/fixtures/sample.csv"

echo "rockspec check: ok"
