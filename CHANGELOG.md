# Changelog

## Unreleased

- `df:columns()` returns column names in frame order;
- drop/rename/with_columns preserve column order, and dropping every column is
  an explicit error;
- dedicated CSV/Parquet writer round-trip and error-path tests;
- writer errors are freed instead of leaked;
- install and smoke scripts, plus a fix for the default library lookup when
  `POLARS_LUA_LIB` is unset.

## 0.4.0

- CSV and Parquet writers;
- drop/rename/with_columns helpers;
- 32 tests.

## 0.3.0

- eager full/outer, semi, anti, and cross joins;
- join-type tests;
- 31 tests.

## 0.2.0

- eager inner/left joins.
