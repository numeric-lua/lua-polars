# AGENTS.md — lua-polars

Local instructions for coding agents. The organization-wide rules in
`../AGENTS.md` still apply.

## Scope

`lua-polars` is a **thin binding** to the Rust Polars engine. It is not a
DataFrame implementation.

- Keep the Rust bridge small: opaque handles, `extern "C"`, `catch_unwind`, and
  a status/error path. A Rust panic must never unwind into Lua.
- Do not add a second query engine, a Lua CSV/Parquet parser, or a Python
  dependency.
- Keep the Lua surface eager-first for now. LazyFrame and Arrow C Data may be
  added later behind explicit APIs.
- JSON conversion is a deliberate MVP copy boundary. Do not claim zero-copy
  until the Arrow path is implemented and benchmarked.
- `polars` is the Lua module name; the repository is `lua-polars`. State
  clearly that this is an unofficial binding.

## Build

```sh
CARGO_BUILD_JOBS=1 ./scripts/build.sh
./scripts/test.sh
```

The laptop has 8 cores and about 7 GB of RAM. The Polars build has been
OOM-killed with four Cargo jobs; use one or two jobs. Do not run this build
while a promo-window agent is running.

## Rules

- Do not run `git commit`, `git push`, or release commands unless the
  coordinator asks.
- Do not modify sibling repositories.
- Every public behavior needs a test, including an error path.
- Keep generated `target/`, `.cargo/`, `.so`, and fixtures' scratch files out
  of commits.
- Keep the C ABI additive; never pass Rust references or `String` layouts
  across the boundary.
