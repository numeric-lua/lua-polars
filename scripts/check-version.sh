#!/bin/sh
# Check that every release version reference agrees.
#
# Cargo.toml is the source of truth. The Cargo.lock entry, the Lua module,
# the single source rockspec (name, version, and tag), README, API docs, and
# release notes must all carry the same version. `scripts/rockspec.sh` runs
# this before invoking LuaRocks so a version mismatch fails fast instead of
# producing a tree that looks valid.
#
# Set EXPECTED_VERSION=x.y.z to also assert the release being prepared.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
  echo "version check: $*" >&2
  exit 1
}

version=$(sed -n 's/^version = "\([0-9][0-9.]*\)"$/\1/p' "$ROOT/Cargo.toml" |
  head -n 1)
[ -n "$version" ] || fail "could not read the package version from Cargo.toml"
case $version in
  *[!0-9.]*) fail "Cargo.toml version '$version' is not numeric" ;;
esac
if [ -n "${EXPECTED_VERSION:-}" ] && [ "$version" != "$EXPECTED_VERSION" ]; then
  fail "Cargo.toml has $version, expected $EXPECTED_VERSION"
fi

check() {
  label=$1
  actual=$2
  expected=$3
  if [ "$actual" != "$expected" ]; then
    fail "$label is '$actual', expected '$expected'"
  fi
}

lock_version=$(grep -A2 '^name = "lua-polars"$' "$ROOT/Cargo.lock" |
  sed -n 's/^version = "\(.*\)"$/\1/p' | head -n 1)
check "Cargo.lock version" "$lock_version" "$version"

lua_version=$(sed -n 's/^  _VERSION = "\([^"]*\)",$/\1/p' "$ROOT/polars.lua" |
  head -n 1)
check "polars.lua _VERSION" "$lua_version" "$version"

set -- "$ROOT"/lua-polars-*.rockspec
if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  fail "expected exactly one lua-polars-*.rockspec, found $#"
fi
ROCKSPEC=$1
rock_name=$(basename "$ROCKSPEC" .rockspec)
check "rockspec filename" "$rock_name" "lua-polars-$version-1"

rock_version=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROCKSPEC" | head -n 1)
check "rockspec version" "$rock_version" "$version-1"

rock_tag=$(sed -n 's/^[[:space:]]*tag = "\(.*\)",$/\1/p' "$ROCKSPEC" | head -n 1)
check "rockspec source tag" "$rock_tag" "v$version"

readme_version=$(sed -n 's/^`\([0-9][0-9.]*\)` is an eager-first MVP:$/\1/p' \
  "$ROOT/README.md" | head -n 1)
check "README status version" "$readme_version" "$version"

api_version=$(sed -n '1s/^# lua-polars API[^0-9]*//p' "$ROOT/docs/api.md")
check "docs/api.md title version" "$api_version" "$version"

notes_version=$(sed -n '1s/^# lua-polars \([0-9][0-9.]*\)$/\1/p' \
  "$ROOT/RELEASE_NOTES.md")
check "RELEASE_NOTES.md title version" "$notes_version" "$version"

echo "version check: $version (rockspec $rock_version, tag $rock_tag) ok"
