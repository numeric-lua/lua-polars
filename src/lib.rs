//! C ABI bridge from LuaJIT to the Rust Polars engine.
//!
//! The exported surface is deliberately small and eager-first: read CSV or
//! Parquet, inspect the schema/shape, take a head, run a SQL query against a
//! DataFrame registered as `df`, join two DataFrames eagerly, and serialize
//! rows as JSON.  LazyFrame and Arrow C Data entry points can be added without
//! changing these handles.

use std::ffi::{CStr, CString};
use std::fs::File;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use polars::prelude::*;
use polars::sql::SQLContext;
use serde_json::{Map, Value};

#[repr(C)]
pub struct PlFrame {
    df: DataFrame,
}

unsafe fn read_utf8(ptr: *const c_char, label: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{label} is null"));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map(|value| value.to_string())
        .map_err(|_| format!("{label} is not valid UTF-8"))
}

unsafe fn read_path(ptr: *const c_char) -> Result<String, String> {
    read_utf8(ptr, "path")
}

const DEFAULT_CSV_DELIMITER: u8 = b',';
const DEFAULT_CSV_QUOTE: u8 = b'"';

#[derive(Clone)]
struct CsvReadConfig {
    delimiter: u8,
    has_header: bool,
    quote: Option<u8>,
    comment: Option<u8>,
    columns: Option<Vec<String>>,
    dtypes: Option<Vec<(String, DataType)>>,
    null_values: Option<Vec<String>>,
    skip_rows: usize,
    n_rows: Option<usize>,
}

impl Default for CsvReadConfig {
    fn default() -> Self {
        Self {
            delimiter: DEFAULT_CSV_DELIMITER,
            has_header: true,
            quote: Some(DEFAULT_CSV_QUOTE),
            comment: None,
            columns: None,
            dtypes: None,
            null_values: None,
            skip_rows: 0,
            n_rows: None,
        }
    }
}

#[derive(Clone)]
struct CsvWriteConfig {
    delimiter: u8,
    include_header: bool,
    null_value: Option<String>,
}

impl Default for CsvWriteConfig {
    fn default() -> Self {
        Self {
            delimiter: DEFAULT_CSV_DELIMITER,
            include_header: true,
            null_value: None,
        }
    }
}

/// Reads the optional one-byte CSV delimiter from the C ABI.
///
/// A null pointer keeps the Polars default. The delimiter has to fit in one
/// byte because Polars stores it as a `u8`; quote, newline, carriage-return,
/// and NUL bytes cannot be delimiters.
unsafe fn read_delimiter(ptr: *const c_char) -> Result<u8, String> {
    if ptr.is_null() {
        return Ok(DEFAULT_CSV_DELIMITER);
    }
    let delimiter = read_utf8(ptr, "delimiter")?;
    let bytes = delimiter.as_bytes();
    if bytes.len() != 1 {
        return Err(format!(
            "CSV delimiter must be exactly one byte, got {} bytes",
            bytes.len()
        ));
    }
    let byte = bytes[0];
    if matches!(byte, 0 | b'\n' | b'\r' | b'"') {
        return Err(format!("CSV delimiter byte 0x{byte:02x} is not allowed"));
    }
    Ok(byte)
}

/// Reads an optional one-byte CSV setting from the C ABI.
///
/// A null pointer or an empty string disables the setting. As with the
/// delimiter, the value has to fit in one byte; NUL, newline, and
/// carriage-return bytes are rejected.
unsafe fn read_optional_byte(ptr: *const c_char, label: &str) -> Result<Option<u8>, String> {
    if ptr.is_null() {
        return Ok(None);
    }
    let text = read_utf8(ptr, label)?;
    if text.is_empty() {
        return Ok(None);
    }
    let bytes = text.as_bytes();
    if bytes.len() != 1 {
        return Err(format!(
            "CSV {label} must be exactly one byte, got {} bytes",
            bytes.len()
        ));
    }
    let byte = bytes[0];
    if matches!(byte, 0 | b'\n' | b'\r') {
        return Err(format!("CSV {label} byte 0x{byte:02x} is not allowed"));
    }
    Ok(Some(byte))
}

unsafe fn read_csv_quote(ptr: *const c_char) -> Result<Option<u8>, String> {
    if ptr.is_null() {
        return Ok(Some(DEFAULT_CSV_QUOTE));
    }
    read_optional_byte(ptr, "quote")
}

unsafe fn read_csv_comment(ptr: *const c_char) -> Result<Option<u8>, String> {
    read_optional_byte(ptr, "comment")
}

/// Reads the optional CSV null-value placeholder for the writer.
///
/// A null pointer or an empty string keeps the default empty field. Polars
/// writes the placeholder literally, so bytes that would change the CSV
/// structure (the delimiter, the `"` quote, line breaks, and NUL) are rejected
/// instead of producing a file that cannot be read back unambiguously.
unsafe fn read_csv_null_value(ptr: *const c_char, delimiter: u8) -> Result<Option<String>, String> {
    if ptr.is_null() {
        return Ok(None);
    }
    let text = read_utf8(ptr, "null_value")?;
    if text.is_empty() {
        return Ok(None);
    }
    for byte in text.bytes() {
        let reason = match byte {
            0 => Some("NUL"),
            b'\n' => Some("newline"),
            b'\r' => Some("carriage return"),
            b'"' => Some("quote"),
            byte if byte == delimiter => Some("delimiter"),
            _ => None,
        };
        if let Some(reason) = reason {
            return Err(format!(
                "CSV null_value must not contain a {reason} byte (0x{byte:02x})"
            ));
        }
    }
    Ok(Some(text))
}

/// Reads an optional CSV projection from the C ABI.
///
/// A null pointer or a zero count leaves the projection disabled. Column names
/// are borrowed for the duration of the call; empty and duplicate names are
/// rejected so the caller gets a precise error instead of a parser surprise.
unsafe fn read_csv_columns(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<String>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("CSV columns are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "CSV column count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut columns = Vec::with_capacity(count);
    for (index, &column_ptr) in raw.iter().enumerate() {
        let column = read_utf8(column_ptr, &format!("CSV column at index {index}"))?;
        if column.is_empty() {
            return Err(format!("CSV column at index {index} must not be empty"));
        }
        if !seen.insert(column.clone()) {
            return Err(format!("duplicate CSV column '{column}'"));
        }
        columns.push(column);
    }
    Ok(Some(columns))
}

/// Maps a Lua-facing dtype name to a Polars dtype for CSV overrides.
///
/// Only dtypes the pinned CSV reader can build directly are accepted: the
/// `dtype-i8`/`dtype-i16`/`dtype-u8`/`dtype-u16`/`dtype-date` Polars features
/// are not enabled. Names are matched case-insensitively so `"F64"` and
/// `"f64"` are the same override.
fn parse_csv_dtype(value: &str) -> Result<DataType, String> {
    let dtype = match value.to_ascii_lowercase().as_str() {
        "bool" | "boolean" => DataType::Boolean,
        "i32" | "int32" => DataType::Int32,
        "i64" | "int64" => DataType::Int64,
        "u32" | "uint32" => DataType::UInt32,
        "u64" | "uint64" => DataType::UInt64,
        "f32" | "float32" => DataType::Float32,
        "f64" | "float64" => DataType::Float64,
        "str" | "string" | "utf8" => DataType::String,
        _ => {
            return Err(format!(
                "unsupported CSV dtype '{value}'; expected bool, i32, i64, u32, u64, \
                 f32, f64, or str"
            ))
        },
    };
    Ok(dtype)
}

/// Reads optional CSV dtype overrides from the C ABI.
///
/// `dtypes` is a flat array of `column`, `dtype` string pairs; `dtype_count`
/// is the number of pairs. A null pointer or a zero count leaves inference
/// unchanged. Entries are validated eagerly so the caller gets a precise error
/// before Polars touches the file.
unsafe fn read_csv_dtypes(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<(String, DataType)>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("CSV dtypes are null".to_string());
    }
    let pairs: usize = count
        .try_into()
        .map_err(|_| "CSV dtype count is too large".to_string())?;
    let value_count = pairs
        .checked_mul(2)
        .ok_or_else(|| "CSV dtype count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, value_count);
    let mut seen = std::collections::HashSet::new();
    let mut dtypes = Vec::with_capacity(pairs);
    for index in 0..pairs {
        let column = read_utf8(
            raw[index * 2],
            &format!("CSV dtype column at index {index}"),
        )?;
        if column.is_empty() {
            return Err(format!(
                "CSV dtype column at index {index} must not be empty"
            ));
        }
        if !seen.insert(column.clone()) {
            return Err(format!("duplicate CSV dtype column '{column}'"));
        }
        let value = read_utf8(raw[index * 2 + 1], &format!("CSV dtype for '{column}'"))?;
        if value.is_empty() {
            return Err(format!("CSV dtype for '{column}' must not be empty"));
        }
        dtypes.push((column, parse_csv_dtype(&value)?));
    }
    Ok(Some(dtypes))
}

/// Reads optional literal CSV null markers from the C ABI.
///
/// `values` points to `count` UTF-8 strings. A null pointer or a zero count
/// keeps Polars' default (empty fields are null). One marker selects the
/// single-value fast path; several markers are all treated as null. Empty
/// markers and duplicates are rejected eagerly.
unsafe fn read_csv_null_values(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<String>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("CSV null values are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "CSV null value count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut values = Vec::with_capacity(count);
    for (index, &value_ptr) in raw.iter().enumerate() {
        let value = read_utf8(value_ptr, &format!("CSV null value at index {index}"))?;
        if value.is_empty() {
            return Err(format!(
                "CSV null value at index {index} must not be empty"
            ));
        }
        if !seen.insert(value.clone()) {
            return Err(format!("duplicate CSV null value '{value}'"));
        }
        values.push(value);
    }
    Ok(Some(values))
}

/// Builds the Polars null-marker policy for the reader.
///
/// Polars compares markers with the unquoted field bytes, so a marker that is
/// quoted in the file (for example `"NA"`) is supplied without its quotes.
/// Empty fields are already null without an explicit marker.
fn csv_null_values(config: &CsvReadConfig) -> Option<NullValues> {
    let values = config.null_values.as_ref()?;
    match values.as_slice() {
        [] => None,
        [single] => Some(NullValues::AllColumnsSingle(PlSmallStr::from_str(single))),
        multiple => Some(NullValues::AllColumns(
            multiple
                .iter()
                .map(|value| PlSmallStr::from_str(value))
                .collect(),
        )),
    }
}

/// Builds the Polars schema overwrite for the requested dtype overrides.
///
/// A projection limits which columns are read, so an override for a column
/// outside it is rejected instead of being silently ignored.
fn csv_schema_overwrite(config: &CsvReadConfig) -> Result<Option<SchemaRef>, String> {
    let Some(dtypes) = config.dtypes.as_ref() else {
        return Ok(None);
    };
    if let Some(columns) = &config.columns {
        for (column, _) in dtypes {
            if !columns.iter().any(|name| name == column) {
                return Err(format!(
                    "CSV dtype column '{column}' is not in the projection"
                ));
            }
        }
    }
    let schema = dtypes
        .iter()
        .map(|(column, dtype)| (PlSmallStr::from_str(column), dtype.clone()))
        .collect::<Schema>();
    Ok(Some(Arc::new(schema)))
}

fn validate_csv_config(config: &CsvReadConfig) -> Result<(), String> {
    if config.quote == Some(config.delimiter) {
        return Err("CSV quote character must differ from the delimiter".to_string());
    }
    if config.comment == Some(config.delimiter) {
        return Err("CSV comment prefix must differ from the delimiter".to_string());
    }
    if config.quote.is_some() && config.quote == config.comment {
        return Err("CSV quote character and comment prefix must differ".to_string());
    }
    Ok(())
}

fn read_csv_frame(path: &str, config: CsvReadConfig) -> Result<DataFrame, String> {
    validate_csv_config(&config)?;
    let schema_overwrite = csv_schema_overwrite(&config)?;
    let columns: Option<Arc<[PlSmallStr]>> = config.columns.as_ref().map(|columns| {
        columns
            .iter()
            .map(|name| PlSmallStr::from_str(name.as_str()))
            .collect()
    });
    let frame = CsvReadOptions::default()
        .with_has_header(config.has_header)
        .with_skip_rows(config.skip_rows)
        .with_n_rows(config.n_rows)
        .with_columns(columns)
        .with_schema_overwrite(schema_overwrite)
        .map_parse_options(|options| {
            options
                .with_separator(config.delimiter)
                .with_quote_char(config.quote)
                .with_comment_prefix(config.comment.map(CommentPrefix::Single))
                .with_null_values(csv_null_values(&config))
        })
        .try_into_reader_with_file_path(Some(PathBuf::from(path)))
        .map_err(|error| error.to_string())?
        .finish()
        .map_err(|error| error.to_string())?;
    // Polars keeps the file column order for a projection. Re-select with the
    // requested names so callers get the order they asked for, like `select`.
    match &config.columns {
        Some(columns) => frame
            .select(columns.iter().map(|name| name.as_str()))
            .map_err(|error| error.to_string()),
        None => {
            // Schema overwrites are applied by name. Polars ignores names that
            // are not in the file, so reject typos after the headers are known.
            if let Some(dtypes) = &config.dtypes {
                for (column, _) in dtypes {
                    if frame.get_column_index(column.as_str()).is_none() {
                        return Err(format!(
                            "CSV dtype column '{column}' is not a column in the file"
                        ));
                    }
                }
            }
            Ok(frame)
        },
    }
}

unsafe fn read_key_list(
    ptr: *const *const c_char,
    count: u64,
    side: &str,
) -> Result<Vec<String>, String> {
    if count == 0 {
        return Err(format!("{side} join keys must not be empty"));
    }
    if ptr.is_null() {
        return Err(format!("{side} join keys are null"));
    }
    let count: usize = count
        .try_into()
        .map_err(|_| format!("{side} join key count is too large"))?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut keys = Vec::with_capacity(count);
    for (index, &key_ptr) in raw.iter().enumerate() {
        let key = read_utf8(key_ptr, &format!("{side} join key at index {index}"))?;
        if key.is_empty() {
            return Err(format!("{side} join key at index {index} must not be empty"));
        }
        keys.push(key);
    }
    Ok(keys)
}

fn validate_keys(df: &DataFrame, keys: &[String], side: &str) -> Result<(), String> {
    let mut seen = std::collections::HashSet::new();
    for key in keys {
        if !seen.insert(key.as_str()) {
            return Err(format!("duplicate {side} join key '{key}'"));
        }
        if df.get_column_index(key.as_str()).is_none() {
            return Err(format!(
                "{side} join key '{key}' is not a column in the {side} DataFrame"
            ));
        }
    }
    Ok(())
}

fn c_string(value: &str) -> *mut c_char {
    let cleaned = value.replace('\0', " ");
    CString::new(cleaned)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

unsafe fn set_error(err: *mut *mut c_char, message: impl AsRef<str>) {
    if !err.is_null() {
        *err = c_string(message.as_ref());
    }
}

unsafe fn frame_ref<'a>(ptr: *mut PlFrame) -> Result<&'a PlFrame, String> {
    ptr.as_ref().ok_or_else(|| "DataFrame handle is null or closed".to_string())
}

fn boxed(df: DataFrame) -> *mut PlFrame {
    Box::into_raw(Box::new(PlFrame { df }))
}

fn panic_message(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        format!("polars bridge panicked: {message}")
    } else if let Some(message) = payload.downcast_ref::<String>() {
        format!("polars bridge panicked: {message}")
    } else {
        "polars bridge panicked".to_string()
    }
}

unsafe fn finish_frame(
    result: std::thread::Result<Result<DataFrame, String>>,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    match result {
        Ok(Ok(df)) => boxed(df),
        Ok(Err(message)) => {
            set_error(err, message);
            ptr::null_mut()
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            ptr::null_mut()
        },
    }
}

#[no_mangle]
pub extern "C" fn pl_version() -> *const c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv(
    path: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        read_csv_frame(&path, CsvReadConfig::default())
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with an explicit delimiter and header policy.
///
/// `delimiter` may be null to keep the default comma. `has_header` is zero for
/// a headerless file and non-zero to parse the first row as column names.
///
/// This entry point is kept for ABI compatibility; new callers can use
/// [`pl_dataframe_read_csv_ex`] for quote and comment control.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_options(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            ..CsvReadConfig::default()
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with delimiter, header, quote, and comment controls.
///
/// A null `quote` keeps the `"` default; an empty `quote` disables quote
/// parsing. A null or empty `comment` disables comment lines; otherwise the
/// first byte of each line is compared with the comment prefix. Quote and
/// comment values are borrowed for the duration of the call.
///
/// [`pl_dataframe_read_csv_projected`] adds a column projection to this
/// signature.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_ex(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            quote: read_csv_quote(quote)?,
            comment: read_csv_comment(comment)?,
            columns: None,
            dtypes: None,
            null_values: None,
            ..CsvReadConfig::default()
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with delimiter, header, quote, comment, and projection
/// controls.
///
/// `columns` points to `column_count` UTF-8 column names and is borrowed for
/// the duration of the call. A null pointer or a zero count reads every
/// column. The returned frame keeps the requested order; duplicate or unknown
/// names are errors. This entry point is additive; the earlier reader
/// signatures keep their defaults.
///
/// [`pl_dataframe_read_csv_typed`] combines this projection with dtype
/// overrides.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_projected(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            quote: read_csv_quote(quote)?,
            comment: read_csv_comment(comment)?,
            columns: read_csv_columns(columns, column_count)?,
            dtypes: None,
            null_values: None,
            ..CsvReadConfig::default()
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with delimiter, header, quote, comment, projection, and
/// dtype override controls.
///
/// `columns` and its `column_count` have the same meaning as in
/// [`pl_dataframe_read_csv_projected`]. `dtypes` points to `dtype_count`
/// `column`, `dtype` string pairs (a flat array of `2 * dtype_count` UTF-8
/// strings). Overrides are applied by column name after the header is known;
/// duplicates and unsupported dtype names are errors, as is an override for a
/// column outside the projection or absent from the file. A null pointer or a
/// zero count keeps Polars inference.
///
/// Supported dtype aliases are `bool`/`boolean`, `i32`/`i64`, `u32`/`u64`,
/// `f32`/`f64`, and `str`/`string`/`utf8`; these are the dtypes the pinned
/// CSV reader can build directly. Matching is case-insensitive. This entry
/// point is additive.
///
/// [`pl_dataframe_read_csv_null_values`] adds literal null markers to this
/// signature.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_typed(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    dtypes: *const *const c_char,
    dtype_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            quote: read_csv_quote(quote)?,
            comment: read_csv_comment(comment)?,
            columns: read_csv_columns(columns, column_count)?,
            dtypes: read_csv_dtypes(dtypes, dtype_count)?,
            null_values: None,
            ..CsvReadConfig::default()
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with delimiter, header, quote, comment, projection, dtype
/// override, and literal null-marker controls.
///
/// This is the superset reader entry point. `columns`, `column_count`,
/// `dtypes`, and `dtype_count` have the same meaning as in
/// [`pl_dataframe_read_csv_typed`]; see that function for the supported dtype
/// names. `null_values` points to `null_value_count` UTF-8 strings and is
/// borrowed for the duration of the call. A null pointer or a zero count keeps
/// the default where only empty fields are null; one marker uses Polars'
/// single-value policy and several markers are all interpreted as null.
///
/// Markers are compared with the unquoted field bytes, so a marker that is
/// quoted in the file (for example `"NA"`) is supplied without its quotes.
/// Empty and duplicate markers are errors. This entry point is additive; the
/// earlier reader signatures and defaults are unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_null_values(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    dtypes: *const *const c_char,
    dtype_count: u64,
    null_values: *const *const c_char,
    null_value_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            quote: read_csv_quote(quote)?,
            comment: read_csv_comment(comment)?,
            columns: read_csv_columns(columns, column_count)?,
            dtypes: read_csv_dtypes(dtypes, dtype_count)?,
            null_values: read_csv_null_values(null_values, null_value_count)?,
            ..CsvReadConfig::default()
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus a row window.
///
/// `skip_rows` is the number of CSV rows skipped before the header is parsed
/// (Polars' `skip_rows`; comments and quoting are respected while skipping).
/// `n_rows` limits the number of data rows read after the header; `-1` reads
/// every remaining row and other negative values are errors. A window of
/// `skip_rows = 0`, `n_rows = -1` matches the earlier defaults.
///
/// `columns`, `dtypes`, and `null_values` have the same meaning as in
/// [`pl_dataframe_read_csv_null_values`]. This entry point is additive; the
/// earlier reader signatures and defaults are unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_row_window(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    dtypes: *const *const c_char,
    dtype_count: u64,
    null_values: *const *const c_char,
    null_value_count: u64,
    skip_rows: u64,
    n_rows: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let skip_rows = usize::try_from(skip_rows)
            .map_err(|_| "CSV skip_rows is too large for this platform".to_string())?;
        let n_rows = if n_rows == -1 {
            None
        } else if n_rows < 0 {
            return Err(format!(
                "CSV n_rows must be -1 to read all rows or a non-negative count, got {n_rows}"
            ));
        } else {
            Some(
                usize::try_from(n_rows)
                    .map_err(|_| "CSV n_rows is too large for this platform".to_string())?,
            )
        };
        let config = CsvReadConfig {
            delimiter: read_delimiter(delimiter)?,
            has_header: has_header != 0,
            quote: read_csv_quote(quote)?,
            comment: read_csv_comment(comment)?,
            columns: read_csv_columns(columns, column_count)?,
            dtypes: read_csv_dtypes(dtypes, dtype_count)?,
            null_values: read_csv_null_values(null_values, null_value_count)?,
            skip_rows,
            n_rows,
        };
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_parquet(
    path: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let file = File::open(&path).map_err(|error| error.to_string())?;
        ParquetReader::new(file)
            .finish()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_free(ptr: *mut PlFrame) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr));
    }
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_shape(
    ptr: *mut PlFrame,
    rows: *mut u64,
    cols: *mut u64,
) -> i32 {
    let frame = match frame_ref(ptr) {
        Ok(frame) => frame,
        Err(_) => return 1,
    };
    if rows.is_null() || cols.is_null() {
        return 2;
    }
    *rows = frame.df.height() as u64;
    *cols = frame.df.width() as u64;
    0
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_schema_json(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        let mut fields = Map::new();
        for column in frame.df.columns() {
            fields.insert(
                column.name().to_string(),
                Value::String(column.dtype().to_string()),
            );
        }
        serde_json::to_string(&Value::Object(fields)).map_err(|error| error.to_string())
    }));
    match result {
        Ok(Ok(json)) => c_string(&json),
        Ok(Err(message)) => {
            set_error(err, message);
            ptr::null_mut()
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            ptr::null_mut()
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_columns_json(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        let names: Vec<String> = frame
            .df
            .columns()
            .iter()
            .map(|column| column.name().to_string())
            .collect();
        serde_json::to_string(&names).map_err(|error| error.to_string())
    }));
    match result {
        Ok(Ok(json)) => c_string(&json),
        Ok(Err(message)) => {
            set_error(err, message);
            ptr::null_mut()
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            ptr::null_mut()
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_head(
    ptr: *mut PlFrame,
    n: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if n < 0 {
            return Err("head count must be non-negative".to_string());
        }
        Ok(frame.df.head(Some(n as usize)))
    }));
    finish_frame(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_join(
    left_ptr: *mut PlFrame,
    right_ptr: *mut PlFrame,
    how: *const c_char,
    left_on: *const *const c_char,
    left_count: u64,
    right_on: *const *const c_char,
    right_count: u64,
    nulls_equal: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let left = frame_ref(left_ptr)?;
        let right = frame_ref(right_ptr)?;
        let how = read_utf8(how, "join type")?;
        let join_type = match how.to_ascii_lowercase().as_str() {
            "inner" => JoinType::Inner,
            "left" => JoinType::Left,
            "full" | "outer" => JoinType::Full,
            "semi" => JoinType::Semi,
            "anti" => JoinType::Anti,
            "cross" => JoinType::Cross,
            other => return Err(format!(
                "invalid join type '{other}'; expected inner, left, full, semi, anti, or cross")),
        };
        if join_type == JoinType::Cross {
            let mut args = JoinArgs::new(join_type);
            args.nulls_equal = nulls_equal != 0;
            return left.df.join(&right.df, Vec::<String>::new().iter(),
                Vec::<String>::new().iter(), args, None)
                .map_err(|error| error.to_string());
        }
        let left_keys = read_key_list(left_on, left_count, "left")?;
        let right_keys = read_key_list(right_on, right_count, "right")?;
        if left_keys.len() != right_keys.len() {
            return Err(format!(
                "join key count mismatch: left has {}, right has {}",
                left_keys.len(),
                right_keys.len()
            ));
        }
        validate_keys(&left.df, &left_keys, "left")?;
        validate_keys(&right.df, &right_keys, "right")?;
        let mut args = JoinArgs::new(join_type);
        args.nulls_equal = nulls_equal != 0;
        left.df
            .join(&right.df, left_keys.iter(), right_keys.iter(), args, None)
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_sql(
    ptr: *mut PlFrame,
    query: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if query.is_null() {
            return Err("SQL query is null".to_string());
        }
        let query = CStr::from_ptr(query)
            .to_str()
            .map_err(|_| "SQL query is not valid UTF-8".to_string())?;
        let mut context = SQLContext::new();
        context.register("df", frame.df.clone().lazy());
        context
            .execute(query)
            .map_err(|error| error.to_string())?
            .collect()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_to_json(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        let mut df = frame.df.clone();
        let mut buffer = Vec::new();
        JsonWriter::new(&mut buffer)
            .with_json_format(JsonFormat::Json)
            .finish(&mut df)
            .map_err(|error| error.to_string())?;
        String::from_utf8(buffer).map_err(|error| error.to_string())
    }));
    match result {
        Ok(Ok(json)) => c_string(&json),
        Ok(Err(message)) => {
            set_error(err, message);
            ptr::null_mut()
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            ptr::null_mut()
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn pl_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

fn write_csv_frame(df: &DataFrame, path: &str, config: CsvWriteConfig) -> Result<(), String> {
    let file = File::create(path).map_err(|error| error.to_string())?;
    let mut df = df.clone();
    let mut writer = CsvWriter::new(file)
        .include_header(config.include_header)
        .with_separator(config.delimiter);
    if let Some(null_value) = config.null_value {
        writer = writer.with_null_value(PlSmallStr::from_str(&null_value));
    }
    writer.finish(&mut df).map_err(|error| error.to_string())
}

unsafe fn finish_write(
    result: std::thread::Result<Result<(), String>>,
    err: *mut *mut c_char,
) -> i32 {
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => {
            set_error(err, message);
            1
        },
        Err(_) => {
            set_error(err, "write_csv panicked");
            1
        },
    }
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv(
    ptr: *mut PlFrame,
    path: *const c_char,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        write_csv_frame(&frame.df, &path, CsvWriteConfig::default())
    }));
    finish_write(result, err)
}

/// Writes a CSV file with delimiter, header, and null-value controls.
///
/// `delimiter` may be null to keep the default comma; it has the same one-byte
/// and quote/newline restrictions as the reader. `has_header` is zero to omit
/// the header row. A null or empty `null_value` writes empty fields for nulls;
/// otherwise the placeholder is written literally and may not contain the
/// delimiter, `"`, NUL, newline, or carriage-return bytes.
///
/// This entry point is additive; [`pl_dataframe_write_csv`] keeps its
/// signature and comma/header/empty-null defaults.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv_options(
    ptr: *mut PlFrame,
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let delimiter = read_delimiter(delimiter)?;
        let config = CsvWriteConfig {
            delimiter,
            include_header: has_header != 0,
            null_value: read_csv_null_value(null_value, delimiter)?,
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_parquet(
    ptr: *mut PlFrame,
    path: *const c_char,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let file = File::create(&path).map_err(|error| error.to_string())?;
        let mut df = frame.df.clone();
        ParquetWriter::new(file).finish(&mut df).map_err(|error| error.to_string())?;
        Ok(())
    }));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => { set_error(err, message); 1 }
        Err(_) => { set_error(err, "write_parquet panicked"); 1 }
    }
}
