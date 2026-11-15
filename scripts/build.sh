#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-"$ROOT/target"}
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-4}
exec cargo build --release --manifest-path "$ROOT/Cargo.toml" "$@"
