#!/bin/sh
# Validate the LuaRocks source-rock build/install path from this checkout.
#
# This is a one-shot check, not a loop: it builds or reuses the release
# library, installs the checkout through the rockspec into a temporary tree,
# and requires the module from that tree without POLARS_LUA_LIB.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lua-polars-rock.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM
TREE="$TMP/tree"

set -- "$ROOT"/lua-polars-*.rockspec
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "expected exactly one lua-polars-*.rockspec, found $#" >&2
  exit 2
fi
ROCKSPEC=$1

cd "$ROOT"
unset POLARS_LUA_LIB
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
"$ROOT/scripts/ensure-bridge.sh"

luarocks make --tree="$TREE" --deps-mode=none "$ROCKSPEC"
eval "$(luarocks path --tree="$TREE")"
"${LUA:-luajit}" "$ROOT/tests/install_smoke.lua" "$TREE" \
  "$ROOT/tests/fixtures/sample.csv"
