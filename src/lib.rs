//! C ABI bridge from LuaJIT to the Rust Polars engine.
//!
//! The exported surface is deliberately small and eager-first: read CSV or
//! Parquet, inspect the schema/shape, take a head, run a SQL query against a
//! DataFrame registered as `df`, join two DataFrames eagerly, and serialize
//! rows as JSON.  LazyFrame and Arrow C Data entry points can be added without
//! changing these handles.

use std::ffi::{CStr, CString};
use std::fs::File;
use std::num::NonZeroUsize;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use polars::polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};
use polars::prelude::*;
use polars::series::ops::NullBehavior;
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
    named_null_values: Option<Vec<(String, String)>>,
    rename_columns: Option<Vec<String>>,
    skip_rows: usize,
    skip_rows_after_header: usize,
    n_rows: Option<usize>,
    infer_schema_length: Option<usize>,
    encoding: CsvEncoding,
    try_parse_dates: bool,
    decimal_comma: bool,
    truncate_ragged_lines: bool,
    ignore_errors: bool,
    raise_if_empty: bool,
    low_memory: bool,
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
            named_null_values: None,
            rename_columns: None,
            skip_rows: 0,
            skip_rows_after_header: 0,
            n_rows: None,
            infer_schema_length: Some(100),
            encoding: CsvEncoding::Utf8,
            try_parse_dates: false,
            decimal_comma: false,
            truncate_ragged_lines: false,
            ignore_errors: false,
            raise_if_empty: true,
            low_memory: false,
        }
    }
}

#[derive(Clone)]
struct CsvWriteConfig {
    delimiter: u8,
    include_header: bool,
    null_value: Option<String>,
    line_terminator: String,
    quote_style: QuoteStyle,
    float_precision: Option<usize>,
    include_bom: bool,
    decimal_comma: bool,
}

impl Default for CsvWriteConfig {
    fn default() -> Self {
        Self {
            delimiter: DEFAULT_CSV_DELIMITER,
            include_header: true,
            null_value: None,
            line_terminator: "\n".to_string(),
            quote_style: QuoteStyle::Necessary,
            float_precision: None,
            include_bom: false,
            decimal_comma: false,
        }
    }
}

/// Maps a Lua-facing CSV quote style to Polars' writer enum.
///
/// A null or empty name keeps the default `necessary`; `non_numeric` also
/// accepts the hyphenated spelling. Matching is case-insensitive.
fn parse_csv_quote_style(value: Option<&str>) -> Result<QuoteStyle, String> {
    let value = value.unwrap_or("necessary");
    match value.to_ascii_lowercase().as_str() {
        "" | "necessary" => Ok(QuoteStyle::Necessary),
        "always" => Ok(QuoteStyle::Always),
        "non_numeric" | "non-numeric" => Ok(QuoteStyle::NonNumeric),
        "never" => Ok(QuoteStyle::Never),
        other => Err(format!(
            "unsupported CSV quote_style '{other}'; expected necessary, always, non_numeric, or never"
        )),
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

/// Reads the optional CSV record terminator for the writer.
///
/// A null pointer or an empty string keeps the default `\n`. Only `\n` and
/// `\r\n` are accepted: arbitrary terminators would produce files the reader
/// cannot split into records, and the strict set keeps the writer and reader
/// round-trip honest. The terminator is written literally between records.
unsafe fn read_csv_line_terminator(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Ok("\n".to_string());
    }
    let text = read_utf8(ptr, "line_terminator")?;
    match text.as_str() {
        "" | "\n" => Ok("\n".to_string()),
        "\r\n" => Ok(text),
        _ => Err(format!(
            "CSV line_terminator must be \"\\n\" or \"\\r\\n\", got {text:?}"
        )),
    }
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

/// Maps a Lua-facing dtype name to a Polars dtype for `DataFrame:cast`.
///
/// The cast surface supports the same primitive dtypes as CSV overrides:
/// booleans, signed and unsigned 32/64-bit integers, 32/64-bit floats, and
/// strings. Date and datetime dtypes stay out because casting arbitrary
/// strings to them needs an explicit format policy. Names are matched
/// case-insensitively.
fn parse_cast_dtype(value: &str) -> Result<DataType, String> {
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
                "unsupported cast dtype '{value}'; expected bool, i32, i64, u32, u64, \
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

/// Reads optional per-column literal null markers from the C ABI.
///
/// `columns` and `values` are parallel arrays of `count` UTF-8 strings. A null
/// pointer or a zero count disables the policy and keeps Polars' default where
/// empty fields are null. Each named column gets exactly one marker; emptying
/// a marker or naming a column twice is rejected eagerly. Markers for columns
/// outside a projection are rejected by the reader config so a typo cannot be
/// silently ignored.
unsafe fn read_csv_named_null_values(
    columns: *const *const c_char,
    values: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<(String, String)>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if columns.is_null() || values.is_null() {
        return Err("CSV named null values are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "CSV named null value count is too large".to_string())?;
    let column_ptrs = std::slice::from_raw_parts(columns, count);
    let value_ptrs = std::slice::from_raw_parts(values, count);
    let mut seen = std::collections::HashSet::new();
    let mut pairs = Vec::with_capacity(count);
    for index in 0..count {
        let column = read_utf8(
            column_ptrs[index],
            &format!("CSV null value column at index {index}"),
        )?;
        if column.is_empty() {
            return Err(format!(
                "CSV null value column at index {index} must not be empty"
            ));
        }
        if !seen.insert(column.clone()) {
            return Err(format!("duplicate CSV null value column '{column}'"));
        }
        let value = read_utf8(value_ptrs[index], &format!("CSV null value for '{column}'"))?;
        if value.is_empty() {
            return Err(format!("CSV null value for '{column}' must not be empty"));
        }
        pairs.push((column, value));
    }
    Ok(Some(pairs))
}

/// Reads optional positional replacement names from the C ABI.
///
/// `ptr` points to `count` UTF-8 names that replace the leading column names
/// after the file is read. A null pointer or a zero count disables renaming.
/// Empty names and duplicates are rejected eagerly; the read frame width is
/// checked later because it is not known until the header is parsed.
unsafe fn read_csv_rename_columns(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<String>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("CSV rename columns are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "CSV rename column count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut names = Vec::with_capacity(count);
    for (index, &name_ptr) in raw.iter().enumerate() {
        let name = read_utf8(name_ptr, &format!("CSV rename column at index {index}"))?;
        if name.is_empty() {
            return Err(format!(
                "CSV rename column at index {index} must not be empty"
            ));
        }
        if !seen.insert(name.clone()) {
            return Err(format!("duplicate CSV rename column '{name}'"));
        }
        names.push(name);
    }
    Ok(Some(names))
}

/// Reads the optional CSV text encoding from the C ABI.
///
/// A null pointer or an empty string keeps strict UTF-8. `utf8-lossy` replaces
/// invalid UTF-8 bytes with the Unicode replacement character instead of
/// failing the read; other names are rejected. Matching is case-insensitive so
/// the Lua wrapper and direct ABI callers behave the same.
unsafe fn read_csv_encoding(ptr: *const c_char) -> Result<CsvEncoding, String> {
    if ptr.is_null() {
        return Ok(CsvEncoding::Utf8);
    }
    let value = read_utf8(ptr, "encoding")?;
    match value.to_ascii_lowercase().as_str() {
        "" | "utf8" => Ok(CsvEncoding::Utf8),
        "utf8-lossy" => Ok(CsvEncoding::LossyUtf8),
        _ => Err(format!(
            "unsupported CSV encoding '{value}'; expected utf8 or utf8-lossy"
        )),
    }
}

/// Applies positional column renames to a frame and rejects duplicate names.
///
/// Polars' eager CSV reader does not consume its `column_names_overwrite`
/// option, so the bridge renames the parsed frame instead. Renaming is applied
/// after projection, so the names replace the columns the caller receives.
fn rename_csv_frame(frame: DataFrame, names: &[String]) -> Result<DataFrame, String> {
    if names.is_empty() {
        return Ok(frame);
    }
    let width = frame.width();
    if names.len() > width {
        return Err(format!(
            "CSV rename_columns has {} names but the frame has {width} columns",
            names.len()
        ));
    }
    let mut final_names: Vec<String> = frame
        .get_column_names()
        .iter()
        .map(|name| name.to_string())
        .collect();
    for (index, name) in names.iter().enumerate() {
        final_names[index] = name.clone();
    }
    let mut seen = std::collections::HashSet::new();
    for name in &final_names {
        if !seen.insert(name.as_str()) {
            return Err(format!(
                "duplicate CSV column name '{name}' after rename_columns"
            ));
        }
    }
    let mut frame = frame;
    frame
        .set_column_names(&final_names)
        .map_err(|error| error.to_string())?;
    Ok(frame)
}

/// Builds the Polars null-marker policy for the reader.
///
/// Polars compares markers with the unquoted field bytes, so a marker that is
/// quoted in the file (for example `"NA"`) is supplied without its quotes.
/// Empty fields are already null without an explicit marker. Per-column
/// markers take precedence over the shared list; the Lua wrapper never sets
/// both, and the ABI validates each policy separately.
fn csv_null_values(config: &CsvReadConfig) -> Result<Option<NullValues>, String> {
    if let Some(named) = config.named_null_values.as_ref() {
        if !named.is_empty() {
            return Ok(Some(NullValues::Named(
                named
                    .iter()
                    .map(|(column, value)| {
                        (PlSmallStr::from_str(column), PlSmallStr::from_str(value))
                    })
                    .collect(),
            )));
        }
    }
    let Some(values) = config.null_values.as_ref() else {
        return Ok(None);
    };
    Ok(match values.as_slice() {
        [] => None,
        [single] => Some(NullValues::AllColumnsSingle(PlSmallStr::from_str(single))),
        multiple => Some(NullValues::AllColumns(
            multiple
                .iter()
                .map(|value| PlSmallStr::from_str(value))
                .collect(),
        )),
    })
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
    if config.named_null_values.is_some() && config.null_values.is_some() {
        return Err("CSV null_values cannot combine shared and per-column markers".to_string());
    }
    if let (Some(named), Some(columns)) = (&config.named_null_values, &config.columns) {
        for (column, _) in named {
            if !columns.iter().any(|name| name == column) {
                return Err(format!(
                    "CSV null value column '{column}' is not in the projection"
                ));
            }
        }
    }
    Ok(())
}

fn read_csv_frame(path: &str, config: CsvReadConfig) -> Result<DataFrame, String> {
    validate_csv_config(&config)?;
    let schema_overwrite = csv_schema_overwrite(&config)?;
    let null_values = csv_null_values(&config)?;
    let columns: Option<Arc<[PlSmallStr]>> = config.columns.as_ref().map(|columns| {
        columns
            .iter()
            .map(|name| PlSmallStr::from_str(name.as_str()))
            .collect()
    });
    let frame = CsvReadOptions::default()
        .with_has_header(config.has_header)
        .with_skip_rows(config.skip_rows)
        .with_skip_rows_after_header(config.skip_rows_after_header)
        .with_n_rows(config.n_rows)
        .with_infer_schema_length(config.infer_schema_length)
        .with_columns(columns)
        .with_schema_overwrite(schema_overwrite)
        .with_ignore_errors(config.ignore_errors)
        .with_raise_if_empty(config.raise_if_empty)
        .with_low_memory(config.low_memory)
        .map_parse_options(|options| {
            options
                .with_separator(config.delimiter)
                .with_quote_char(config.quote)
                .with_comment_prefix(config.comment.map(CommentPrefix::Single))
                .with_null_values(null_values.clone())
                .with_encoding(config.encoding)
                .with_try_parse_dates(config.try_parse_dates)
                .with_decimal_comma(config.decimal_comma)
                .with_truncate_ragged_lines(config.truncate_ragged_lines)
        })
        .try_into_reader_with_file_path(Some(PathBuf::from(path)))
        .map_err(|error| error.to_string())?
        .finish()
        .map_err(|error| error.to_string())?;
    // Polars keeps the file column order for a projection. Re-select with the
    // requested names so callers get the order they asked for, like `select`.
    let frame = match &config.columns {
        Some(columns) => frame
            .select(columns.iter().map(|name| name.as_str()))
            .map_err(|error| error.to_string())?,
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
            frame
        },
    };
    match &config.rename_columns {
        Some(names) => rename_csv_frame(frame, names),
        None => Ok(frame),
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

/// Reads a borrowed list of column names for a DataFrame operation.
///
/// A zero count is an empty list; the caller decides whether that means "all
/// columns" or is an error. A non-zero count with a null pointer, an empty
/// name, or a duplicate name is rejected before Polars sees the request.
unsafe fn read_name_list(
    ptr: *const *const c_char,
    count: u64,
    label: &str,
) -> Result<Vec<String>, String> {
    if count == 0 {
        return Ok(Vec::new());
    }
    if ptr.is_null() {
        return Err(format!("{label} are null"));
    }
    let count: usize = count
        .try_into()
        .map_err(|_| format!("{label} count is too large"))?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut names = Vec::with_capacity(count);
    for (index, &name_ptr) in raw.iter().enumerate() {
        let name = read_utf8(name_ptr, &format!("{label} at index {index}"))?;
        if name.is_empty() {
            return Err(format!("{label} at index {index} must not be empty"));
        }
        if !seen.insert(name.clone()) {
            return Err(format!("duplicate {label} '{name}'"));
        }
        names.push(name);
    }
    Ok(names)
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

/// Builds a CSV reader config from the row-window ABI arguments.
///
/// `n_rows` uses `-1` as the "read every remaining row" sentinel; other
/// negative values are errors. The conversion is shared by every reader entry
/// point that carries the window so they cannot drift.
unsafe fn csv_read_config_with_window(
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
) -> Result<CsvReadConfig, String> {
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
    Ok(CsvReadConfig {
        delimiter: read_delimiter(delimiter)?,
        has_header: has_header != 0,
        quote: read_csv_quote(quote)?,
        comment: read_csv_comment(comment)?,
        columns: read_csv_columns(columns, column_count)?,
        dtypes: read_csv_dtypes(dtypes, dtype_count)?,
        null_values: read_csv_null_values(null_values, null_value_count)?,
        skip_rows,
        n_rows,
        ..CsvReadConfig::default()
    })
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
        let config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus a text encoding.
///
/// This is the superset reader entry point. `encoding` is a UTF-8 string:
/// null or empty keeps strict UTF-8, `utf8` selects it explicitly, and
/// `utf8-lossy` replaces invalid bytes with the Unicode replacement character.
/// Other names are errors. See [`pl_dataframe_read_csv_row_window`] for the
/// shared reader arguments.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_encoded(
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
    encoding: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.encoding = read_csv_encoding(encoding)?;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option, a text encoding, and
/// positional replacement column names.
///
/// `rename_columns` points to `rename_column_count` UTF-8 names and is borrowed
/// for the duration of the call. The names replace the leading columns of the
/// frame that would otherwise be returned, so they compose with projection and
/// apply after dtype overrides and null markers. Supplying more names than the
/// frame has columns, empty names, and duplicate results are errors; supplying
/// fewer names renames only that prefix, matching Polars'
/// `column_names_overwrite` rule.
///
/// See [`pl_dataframe_read_csv_encoded`] for the encoding and shared reader
/// arguments. This entry point is additive; every earlier reader signature and
/// default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_renamed(
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
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option, a text encoding, a
/// positional rename list, and per-column literal null markers.
///
/// This is the superset reader entry point for per-column markers.
/// `null_columns` and `null_values` are parallel arrays of `null_value_count`
/// UTF-8 strings: each column gets exactly one marker, and columns without an
/// entry keep the default where only empty fields are null. Markers are
/// compared with the unquoted field bytes, so a marker quoted in the file is
/// supplied without its quotes. Empty column names or markers, duplicate
/// columns, and markers outside the projection are errors.
///
/// Markers are applied before `rename_columns`, so they name the file's
/// original columns, like `dtypes`. See [`pl_dataframe_read_csv_renamed`] for
/// the shared reader and rename arguments. This entry point is additive;
/// every earlier reader signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_named_nulls(
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    quote: *const c_char,
    comment: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    dtypes: *const *const c_char,
    dtype_count: u64,
    null_columns: *const *const c_char,
    null_values: *const *const c_char,
    null_value_count: u64,
    skip_rows: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            ptr::null(),
            0,
            skip_rows,
            n_rows,
        )?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, null_values, null_value_count)?;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus date inference.
///
/// This is the superset entry point for the parse-time options. All shared
/// columns, dtypes, null markers, renames, encoding, and row window arguments
/// have the same meaning as in the earlier readers. `null_values` and
/// `null_columns`/`named_null_values` are separate policies; supplying both is
/// an error, matching the Lua surface where a marker table is either a list or
/// a per-column map. `try_parse_dates` is non-zero to let Polars infer ISO date
/// and datetime columns instead of strings. This entry point is additive; every
/// earlier reader signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_parsed(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus lenient parsing.
///
/// This is the superset entry point for ragged lines and recoverable parse
/// errors. `truncate_ragged_lines` is non-zero to truncate rows that contain
/// more fields than the header instead of failing the read. `ignore_errors` is
/// non-zero to keep the rows Polars can parse and represent values it cannot
/// parse as nulls instead of failing the whole read. Both flags default to
/// false in every earlier reader entry point.
///
/// All shared arguments have the same meaning as in
/// [`pl_dataframe_read_csv_parsed`]. This entry point is additive; every
/// earlier reader signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_lenient(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    truncate_ragged_lines: i32,
    ignore_errors: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        config.truncate_ragged_lines = truncate_ragged_lines != 0;
        config.ignore_errors = ignore_errors != 0;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus post-header and
/// decimal-comma controls.
///
/// This is the superset reader entry point for the dialect controls.
/// `skip_rows_after_header` drops that many data rows after the header; when
/// `has_header` is zero there is no header, so it drops leading data rows.
/// The skip happens before `n_rows` is applied. It must fit this platform's
/// `usize`. `decimal_comma` is non-zero to parse a comma as the decimal
/// separator, which is useful with a semicolon or tab delimiter; delimiters and
/// quote/comment bytes keep their earlier rules.
///
/// All shared arguments have the same meaning as in
/// [`pl_dataframe_read_csv_lenient`]. This entry point is additive; every
/// earlier reader signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_extended(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    skip_rows_after_header: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    decimal_comma: i32,
    truncate_ragged_lines: i32,
    ignore_errors: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.skip_rows_after_header = usize::try_from(skip_rows_after_header)
            .map_err(|_| "CSV skip_rows_after_header is too large for this platform".to_string())?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        config.decimal_comma = decimal_comma != 0;
        config.truncate_ragged_lines = truncate_ragged_lines != 0;
        config.ignore_errors = ignore_errors != 0;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus empty-file handling.
///
/// The arguments match [`pl_dataframe_read_csv_extended`] and keep the same
/// meaning and defaults. `raise_if_empty` is non-zero to keep Polars' default
/// behavior where an empty file with no header is an error; zero allows that
/// read and returns an empty frame. A file with a header but no data rows is
/// not considered empty by Polars, so it keeps its header-derived schema in
/// either mode. This entry point is additive; every earlier reader signature
/// and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_empty_policy(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    skip_rows_after_header: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    decimal_comma: i32,
    truncate_ragged_lines: i32,
    ignore_errors: i32,
    raise_if_empty: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.skip_rows_after_header = usize::try_from(skip_rows_after_header)
            .map_err(|_| "CSV skip_rows_after_header is too large for this platform".to_string())?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        config.decimal_comma = decimal_comma != 0;
        config.truncate_ragged_lines = truncate_ragged_lines != 0;
        config.ignore_errors = ignore_errors != 0;
        config.raise_if_empty = raise_if_empty != 0;
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus schema inference
/// length.
///
/// The arguments match [`pl_dataframe_read_csv_empty_policy`] and keep the same
/// meaning and defaults. `infer_schema_length` is the number of data rows used
/// to infer dtypes; `-1` keeps Polars' default of 100 rows, `0` treats every
/// column as a string, and a positive value limits inference to that many rows.
/// The parser still reads the whole requested row window after inference. This
/// entry point is additive; every earlier reader signature and default is
/// unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_inferred(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    skip_rows_after_header: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    decimal_comma: i32,
    truncate_ragged_lines: i32,
    ignore_errors: i32,
    raise_if_empty: i32,
    infer_schema_length: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.skip_rows_after_header = usize::try_from(skip_rows_after_header)
            .map_err(|_| "CSV skip_rows_after_header is too large for this platform".to_string())?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        config.decimal_comma = decimal_comma != 0;
        config.truncate_ragged_lines = truncate_ragged_lines != 0;
        config.ignore_errors = ignore_errors != 0;
        config.raise_if_empty = raise_if_empty != 0;
        if infer_schema_length >= 0 {
            config.infer_schema_length = Some(usize::try_from(infer_schema_length).map_err(
                |_| "CSV infer_schema_length is too large for this platform".to_string(),
            )?);
        }
        read_csv_frame(&path, config)
    }));
    finish_frame(result, err)
}

/// Reads a CSV file with every earlier reader option plus a memory mode.
///
/// The arguments match [`pl_dataframe_read_csv_inferred`] and keep the same
/// meaning and defaults. `low_memory` is non-zero to select Polars' lower-memory
/// CSV reader path, which trades speed for a smaller peak footprint. The schema
/// and values are unchanged. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv_low_memory(
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
    null_columns: *const *const c_char,
    named_null_values: *const *const c_char,
    named_null_value_count: u64,
    skip_rows: u64,
    skip_rows_after_header: u64,
    n_rows: i64,
    rename_columns: *const *const c_char,
    rename_column_count: u64,
    encoding: *const c_char,
    try_parse_dates: i32,
    decimal_comma: i32,
    truncate_ragged_lines: i32,
    ignore_errors: i32,
    raise_if_empty: i32,
    infer_schema_length: i64,
    low_memory: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let mut config = csv_read_config_with_window(
            delimiter,
            has_header,
            quote,
            comment,
            columns,
            column_count,
            dtypes,
            dtype_count,
            null_values,
            null_value_count,
            skip_rows,
            n_rows,
        )?;
        config.skip_rows_after_header = usize::try_from(skip_rows_after_header)
            .map_err(|_| "CSV skip_rows_after_header is too large for this platform".to_string())?;
        config.encoding = read_csv_encoding(encoding)?;
        config.rename_columns = read_csv_rename_columns(rename_columns, rename_column_count)?;
        config.named_null_values =
            read_csv_named_null_values(null_columns, named_null_values, named_null_value_count)?;
        config.try_parse_dates = try_parse_dates != 0;
        config.decimal_comma = decimal_comma != 0;
        config.truncate_ragged_lines = truncate_ragged_lines != 0;
        config.ignore_errors = ignore_errors != 0;
        config.raise_if_empty = raise_if_empty != 0;
        config.low_memory = low_memory != 0;
        if infer_schema_length >= 0 {
            config.infer_schema_length = Some(usize::try_from(infer_schema_length).map_err(
                |_| "CSV infer_schema_length is too large for this platform".to_string(),
            )?);
        }
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

/// Reads an optional Parquet projection from the C ABI.
///
/// A null pointer or a zero count leaves the projection disabled. Column names
/// are borrowed for the duration of the call; empty and duplicate names are
/// rejected so the caller gets a precise error before Polars touches the file.
unsafe fn read_parquet_columns(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<String>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("Parquet columns are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "Parquet column count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut columns = Vec::with_capacity(count);
    for (index, &column_ptr) in raw.iter().enumerate() {
        let column = read_utf8(column_ptr, &format!("Parquet column at index {index}"))?;
        if column.is_empty() {
            return Err(format!("Parquet column at index {index} must not be empty"));
        }
        if !seen.insert(column.clone()) {
            return Err(format!("duplicate Parquet column '{column}'"));
        }
        columns.push(column);
    }
    Ok(Some(columns))
}

fn read_parquet_frame(
    path: &str,
    columns: Option<Vec<String>>,
    skip_rows: u64,
    n_rows: i64,
    low_memory: bool,
    rechunk: bool,
) -> Result<DataFrame, String> {
    let skip_rows: usize = skip_rows
        .try_into()
        .map_err(|_| "Parquet skip_rows is too large".to_string())?;
    let length = if n_rows < 0 {
        if n_rows != -1 {
            return Err(format!(
                "Parquet n_rows must be -1 or non-negative, got {n_rows}"
            ));
        }
        usize::MAX - skip_rows
    } else {
        usize::try_from(n_rows).map_err(|_| "Parquet n_rows is too large".to_string())?
    };
    let file = File::open(path).map_err(|error| error.to_string())?;
    let mut reader = ParquetReader::new(file)
        .with_slice(Some((skip_rows, length)))
        .set_low_memory(low_memory);
    if let Some(columns) = columns {
        reader = reader.with_columns(Some(columns));
    }
    let mut frame = reader.finish().map_err(|error| error.to_string())?;
    if rechunk {
        frame.rechunk_mut_par();
    }
    Ok(frame)
}

/// Reads a Parquet file with a column projection and a row window.
///
/// `columns` points to `column_count` UTF-8 names and is borrowed for the
/// duration of the call. A null array or a zero count reads every column.
/// `skip_rows` drops that many leading data rows. `n_rows` limits the data
/// rows read after the offset: `-1` reads every remaining row and any other
/// negative value is an error.
///
/// This entry point is additive; [`pl_dataframe_read_parquet`] keeps its
/// signature and reads every row and column.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_parquet_options(
    path: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    skip_rows: u64,
    n_rows: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_parquet_columns(columns, column_count)?;
        read_parquet_frame(&path, columns, skip_rows, n_rows, false, false)
    }));
    finish_frame(result, err)
}

/// Reads a Parquet file with a projection, row window, and memory mode.
///
/// The arguments match [`pl_dataframe_read_parquet_options`] and keep the same
/// projection and row-window rules. `low_memory` is non-zero to use Polars'
/// lower-memory reader path, which trades speed for a smaller peak footprint.
/// The returned frame has the same schema and values either way. This entry
/// point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_parquet_low_memory(
    path: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    skip_rows: u64,
    n_rows: i64,
    low_memory: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_parquet_columns(columns, column_count)?;
        read_parquet_frame(&path, columns, skip_rows, n_rows, low_memory != 0, false)
    }));
    finish_frame(result, err)
}

/// Reads a Parquet file with projection, row window, and memory controls.
///
/// The arguments match [`pl_dataframe_read_parquet_options`] plus
/// `low_memory` and `rechunk`. Non-zero `low_memory` selects Polars'
/// lower-memory path; non-zero `rechunk` consolidates the result into a single
/// chunk per column. Both preserve the schema and values. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_parquet_full(
    path: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    skip_rows: u64,
    n_rows: i64,
    low_memory: i32,
    rechunk: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_parquet_columns(columns, column_count)?;
        read_parquet_frame(
            &path,
            columns,
            skip_rows,
            n_rows,
            low_memory != 0,
            rechunk != 0,
        )
    }));
    finish_frame(result, err)
}

/// Reads an optional JSON projection from the C ABI.
///
/// A null pointer or a zero count leaves the projection disabled. Column names
/// are borrowed for the duration of the call; empty and duplicate names are
/// rejected before the file is parsed.
unsafe fn read_json_columns(
    ptr: *const *const c_char,
    count: u64,
) -> Result<Option<Vec<String>>, String> {
    if count == 0 {
        return Ok(None);
    }
    if ptr.is_null() {
        return Err("JSON columns are null".to_string());
    }
    let count: usize = count
        .try_into()
        .map_err(|_| "JSON column count is too large".to_string())?;
    let raw = std::slice::from_raw_parts(ptr, count);
    let mut seen = std::collections::HashSet::new();
    let mut columns = Vec::with_capacity(count);
    for (index, &column_ptr) in raw.iter().enumerate() {
        let column = read_utf8(column_ptr, &format!("JSON column at index {index}"))?;
        if column.is_empty() {
            return Err(format!("JSON column at index {index} must not be empty"));
        }
        if !seen.insert(column.clone()) {
            return Err(format!("duplicate JSON column '{column}'"));
        }
        columns.push(column);
    }
    Ok(Some(columns))
}

/// Reads a JSON array or JSON Lines file with an optional column projection.
///
/// `json_lines` is zero for a single JSON array and non-zero for one object per
/// line. `columns` points to `column_count` UTF-8 names; a null array or zero
/// count reads every column. The returned frame keeps the requested order.
/// This entry point is additive and leaves every earlier reader unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_json(
    path: *const c_char,
    json_lines: i32,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_json_columns(columns, column_count)?;
        let file = File::open(&path).map_err(|error| error.to_string())?;
        let mut reader = JsonReader::new(file).with_json_format(if json_lines != 0 {
            JsonFormat::JsonLines
        } else {
            JsonFormat::Json
        });
        if let Some(columns) = columns {
            reader = reader.with_projection(Some(
                columns
                    .iter()
                    .map(|name| PlSmallStr::from_str(name.as_str()))
                    .collect(),
            ));
        }
        reader.finish().map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Reads a JSON array or JSON Lines file with an optional inference window.
///
/// The arguments match [`pl_dataframe_read_json`] and keep the same meaning and
/// defaults. `infer_schema_length` applies to JSON Lines: `-1` keeps Polars'
/// default 100-record window, `0` scans the whole stream to infer the schema,
/// and a positive value limits inference to that many records. JSON arrays are
/// read as a whole by Polars, so the argument has no effect there. This entry
/// point is additive; every earlier reader signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_json_inferred(
    path: *const c_char,
    json_lines: i32,
    columns: *const *const c_char,
    column_count: u64,
    infer_schema_length: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_json_columns(columns, column_count)?;
        if infer_schema_length < -1 {
            return Err("JSON infer_schema_length must be -1 or a non-negative integer".to_string());
        }
        let file = File::open(&path).map_err(|error| error.to_string())?;
        let mut reader = JsonReader::new(file).with_json_format(if json_lines != 0 {
            JsonFormat::JsonLines
        } else {
            JsonFormat::Json
        });
        if json_lines != 0 {
            if infer_schema_length == 0 {
                reader = reader.infer_schema_len(None);
            } else if infer_schema_length > 0 {
                let records = usize::try_from(infer_schema_length).map_err(|_| {
                    "JSON infer_schema_length is too large for this platform".to_string()
                })?;
                let records = NonZeroUsize::new(records).ok_or_else(|| {
                    "JSON infer_schema_length must be positive or zero".to_string()
                })?;
                reader = reader.infer_schema_len(Some(records));
            }
        }
        if let Some(columns) = columns {
            reader = reader.with_projection(Some(
                columns
                    .iter()
                    .map(|name| PlSmallStr::from_str(name.as_str()))
                    .collect(),
            ));
        }
        reader.finish().map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Reads a JSON array or JSON Lines file with inference and error controls.
///
/// The arguments match [`pl_dataframe_read_json_inferred`] plus
/// `ignore_errors`. A non-zero `ignore_errors` keeps JSON Lines records whose
/// values cannot be parsed by inserting nulls, matching Polars' lenient mode;
/// JSON arrays reject the flag because Polars only supports it for lines.
/// `infer_schema_length` keeps its `-1` default, `0` full-scan, and positive
/// window meanings. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_json_full(
    path: *const c_char,
    json_lines: i32,
    columns: *const *const c_char,
    column_count: u64,
    infer_schema_length: i64,
    ignore_errors: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        let columns = read_json_columns(columns, column_count)?;
        if infer_schema_length < -1 {
            return Err("JSON infer_schema_length must be -1 or a non-negative integer".to_string());
        }
        let file = File::open(&path).map_err(|error| error.to_string())?;
        let mut reader = JsonReader::new(file)
            .with_json_format(if json_lines != 0 {
                JsonFormat::JsonLines
            } else {
                JsonFormat::Json
            })
            .with_ignore_errors(ignore_errors != 0);
        if json_lines != 0 {
            if infer_schema_length == 0 {
                reader = reader.infer_schema_len(None);
            } else if infer_schema_length > 0 {
                let records = usize::try_from(infer_schema_length).map_err(|_| {
                    "JSON infer_schema_length is too large for this platform".to_string()
                })?;
                let records = NonZeroUsize::new(records).ok_or_else(|| {
                    "JSON infer_schema_length must be positive or zero".to_string()
                })?;
                reader = reader.infer_schema_len(Some(records));
            }
        }
        if let Some(columns) = columns {
            reader = reader.with_projection(Some(
                columns
                    .iter()
                    .map(|name| PlSmallStr::from_str(name.as_str()))
                    .collect(),
            ));
        }
        reader.finish().map_err(|error| error.to_string())
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

/// Reports the approximate in-memory size of the frame in bytes.
///
/// The value is Polars' estimate and excludes allocator overhead beyond the
/// column buffers. It is written to `bytes` and the function returns zero on
/// success. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_estimated_size(
    ptr: *mut PlFrame,
    bytes: *mut u64,
    err: *mut *mut c_char,
) -> i32 {
    if bytes.is_null() {
        return 2;
    }
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<u64, String> {
        let frame = frame_ref(ptr)?;
        Ok(frame.df.estimated_size() as u64)
    }));
    match result {
        Ok(Ok(value)) => {
            *bytes = value;
            0
        },
        Ok(Err(message)) => {
            set_error(err, message);
            1
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            1
        },
    }
}

/// Reports the largest chunk count across the frame's columns.
///
/// The value is written to `out` and the function returns zero on success.
/// This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_max_chunks(
    ptr: *mut PlFrame,
    out: *mut u64,
    err: *mut *mut c_char,
) -> i32 {
    if out.is_null() {
        return 2;
    }
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<u64, String> {
        let frame = frame_ref(ptr)?;
        Ok(frame.df.max_n_chunks() as u64)
    }));
    match result {
        Ok(Ok(value)) => {
            *out = value;
            0
        },
        Ok(Err(message)) => {
            set_error(err, message);
            1
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            1
        },
    }
}

/// Checks whether rows are already sorted by one or more columns.
///
/// `columns` points to `column_count` names. `descending` points to the same
/// number of non-zero flags; `nulls_last` is applied to every key. The result
/// is written to `out` as zero or one. Empty key lists, mismatched flag arrays,
/// unknown columns, null output pointers, and closed frames are errors. This
/// entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_is_sorted(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    descending: *const i32,
    descending_count: u64,
    nulls_last: i32,
    out: *mut i32,
    err: *mut *mut c_char,
) -> i32 {
    if out.is_null() {
        return 2;
    }
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<bool, String> {
        let frame = frame_ref(ptr)?;
        let names = read_name_list(columns, column_count, "is_sorted columns")?;
        if names.is_empty() {
            return Err("is_sorted requires at least one column".to_string());
        }
        for name in &names {
            if frame.df.get_column_index(name.as_str()).is_none() {
                return Err(format!(
                    "is_sorted column '{name}' is not a column in the DataFrame"
                ));
            }
        }
        let descending_count: usize = descending_count
            .try_into()
            .map_err(|_| "is_sorted descending count is too large".to_string())?;
        if descending_count != names.len() {
            return Err(format!(
                "is_sorted descending count {} does not match column count {}",
                descending_count,
                names.len()
            ));
        }
        if descending.is_null() {
            return Err("is_sorted descending flags are null".to_string());
        }
        let raw = std::slice::from_raw_parts(descending, descending_count);
        let by: Vec<PlSmallStr> = names
            .iter()
            .map(|name| PlSmallStr::from_str(name.as_str()))
            .collect();
        let descending: Vec<bool> = raw.iter().map(|value| *value != 0).collect();
        let nulls_last = vec![nulls_last != 0; by.len()];
        DataFrameIsSorted::is_sorted(&frame.df, &by, &descending, &nulls_last)
            .map_err(|error| error.to_string())
    }));
    match result {
        Ok(Ok(value)) => {
            *out = if value { 1 } else { 0 };
            0
        },
        Ok(Err(message)) => {
            set_error(err, message);
            1
        },
        Err(payload) => {
            set_error(err, panic_message(payload));
            1
        },
    }
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

/// Returns the last `n` rows of a frame, or all rows when `n` exceeds the
/// height. A negative count is rejected. This entry point is additive; the
/// existing head behavior is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_tail(
    ptr: *mut PlFrame,
    n: i64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if n < 0 {
            return Err("tail count must be non-negative".to_string());
        }
        Ok(frame.df.tail(Some(n as usize)))
    }));
    finish_frame(result, err)
}

/// Returns `length` rows starting at `offset`. A negative offset counts from
/// the end of the frame, matching Polars' eager slice semantics; an offset
/// outside the frame returns an empty frame with the same schema. The length
/// is an unsigned row count and must fit this platform's `usize`.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_slice(
    ptr: *mut PlFrame,
    offset: i64,
    length: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let length = usize::try_from(length)
            .map_err(|_| "slice length is too large for this platform".to_string())?;
        Ok(frame.df.slice(offset, length))
    }));
    finish_frame(result, err)
}

/// Prepends a zero-based row-index column. `offset` shifts the first index
/// value, so an offset of 10 starts at 10. The name is borrowed for the call
/// and must be non-empty; Polars rejects names that collide with a column.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_with_row_index(
    ptr: *mut PlFrame,
    name: *const c_char,
    offset: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let name = read_utf8(name, "row index name")?;
        if name.is_empty() {
            return Err("row index name must not be empty".to_string());
        }
        let offset = IdxSize::try_from(offset)
            .map_err(|_| "row index offset is too large for this platform".to_string())?;
        frame
            .df
            .with_row_index(PlSmallStr::from_str(&name), Some(offset))
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Returns a frame with the row order reversed.
///
/// Column order, names, dtypes, and nulls are preserved; only the row order
/// changes. An empty frame stays empty. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_reverse(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        Ok(frame.df.reverse())
    }));
    finish_frame(result, err)
}

/// Returns a frame with a single chunk per column.
///
/// Polars may store each column in several chunks after a series of
/// operations. Rechunking consolidates them, which can simplify downstream
/// access and reduce overhead. The schema, values, and row order are unchanged,
/// and the input frame is left open. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_rechunk(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let mut output = frame.df.clone();
        output.rechunk_mut_par();
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Returns a copy with excess allocation capacity released.
///
/// The schema, values, and row order are unchanged, and the input frame stays
/// open. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_shrink_to_fit(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let mut output = frame.df.clone();
        output.shrink_to_fit();
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Expands struct columns into their field columns.
///
/// A null/zero `columns` count targets every `Struct` column; an explicit list
/// must name struct columns. `separator` is an optional non-empty prefix
/// separator: when set, output fields are named `column{separator}field`.
/// Column order otherwise follows Polars' struct expansion. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_unnest(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    separator: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let mut names = read_name_list(columns, column_count, "unnest columns")?;
        if names.is_empty() {
            names = frame
                .df
                .columns()
                .iter()
                .filter(|column| matches!(column.dtype(), DataType::Struct(_)))
                .map(|column| column.name().to_string())
                .collect();
        }
        if names.is_empty() {
            return Err("unnest requires at least one struct column".to_string());
        }
        for name in &names {
            let column = frame
                .df
                .column(name.as_str())
                .map_err(|_| format!("unnest column '{name}' is not a column in the DataFrame"))?;
            if !matches!(column.dtype(), DataType::Struct(_)) {
                return Err(format!(
                    "unnest column '{name}' has dtype {}; expected a struct",
                    column.dtype()
                ));
            }
        }
        let separator = if separator.is_null() {
            None
        } else {
            let value = read_utf8(separator, "unnest separator")?;
            if value.is_empty() {
                None
            } else {
                Some(value)
            }
        };
        let names: Vec<PlSmallStr> = names
            .iter()
            .map(|name| PlSmallStr::from_str(name.as_str()))
            .collect();
        frame
            .df
            .unnest(names, separator.as_deref())
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Transposes a frame so columns become rows and rows become columns.
///
/// `keep_names_as` is an optional non-empty column name that receives the
/// original column names; a null pointer omits it. Polars finds a common
/// supertype across all values, so mixed dtypes are cast to that type. Output
/// columns are named `column_0`, `column_1`, and so on unless a name column is
/// requested. Empty frames cannot be transposed. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_transpose(
    ptr: *mut PlFrame,
    keep_names_as: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let keep = if keep_names_as.is_null() {
            None
        } else {
            let name = read_utf8(keep_names_as, "transpose keep_names_as")?;
            if name.is_empty() {
                return Err("transpose keep_names_as must not be empty".to_string());
            }
            Some(name)
        };
        let mut output = frame.df.clone();
        output
            .transpose(keep.as_deref(), None)
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Shifts column values by a number of rows.
///
/// A null/zero `columns` count shifts every column; otherwise only the named
/// columns move and the other columns keep their values. Positive periods move
/// values toward higher row indexes and insert nulls at the start; negative
/// periods move them toward lower indexes and insert nulls at the end. The
/// result keeps the column order, names, and dtypes of the input. This entry
/// point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_shift(
    ptr: *mut PlFrame,
    periods: i64,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let names = read_name_list(columns, column_count, "shift columns")?;
        if names.is_empty() {
            return Ok(frame.df.shift(periods));
        }
        let mut output = frame.df.clone();
        for name in &names {
            let index = output.get_column_index(name.as_str()).ok_or_else(|| {
                format!("shift column '{name}' is not a column in the DataFrame")
            })?;
            let shifted = output.columns()[index].shift(periods);
            output
                .with_column(shifted)
                .map_err(|error| error.to_string())?;
        }
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Rejects a fractional clip bound for an integer column.
///
/// Polars would otherwise truncate the bound during its dtype cast, which can
/// move the effective range without telling the caller.
fn validate_clip_bound(
    dtype: &DataType,
    value: f64,
    label: &str,
    column: &str,
) -> Result<(), String> {
    if matches!(
        dtype,
        DataType::Int32 | DataType::Int64 | DataType::UInt32 | DataType::UInt64
    ) && value.fract() != 0.0
    {
        return Err(format!(
            "clip {label} for integer column '{column}' must be an integer, got {value}"
        ));
    }
    Ok(())
}

/// Resolves the numeric columns a `clip` operation should touch.
///
/// An empty request means every primitive numeric column in frame order.
/// Explicit names are checked against the frame and must themselves be
/// numeric; Boolean and string columns are not silently ignored.
fn numeric_target_columns(
    df: &DataFrame,
    requested: &[String],
    operation: &str,
) -> Result<Vec<String>, String> {
    let is_numeric = |column: &Column| column.dtype().to_physical().is_primitive_numeric();
    if requested.is_empty() {
        return Ok(df
            .columns()
            .iter()
            .filter(|column| is_numeric(column))
            .map(|column| column.name().to_string())
            .collect());
    }
    let mut names = Vec::with_capacity(requested.len());
    for name in requested {
        let column = df
            .column(name.as_str())
            .map_err(|_| format!("{operation} column '{name}' is not a column in the DataFrame"))?;
        if !is_numeric(column) {
            return Err(format!(
                "{operation} column '{name}' has dtype {}; expected a numeric column",
                column.dtype()
            ));
        }
        names.push(name.clone());
    }
    Ok(names)
}

/// Clamps numeric values to an inclusive `[minimum, maximum]` range.
///
/// A null/zero `columns` count clips every primitive numeric column; a name or
/// list limits the operation and rejects non-numeric columns. Nulls are
/// preserved, the input frame is unchanged, and column order is preserved.
/// Bounds must be finite and ordered; they are cast to each target dtype, so a
/// non-integral bound on an integer column is an error. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_clip(
    ptr: *mut PlFrame,
    minimum: f64,
    maximum: f64,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if !minimum.is_finite() {
            return Err("clip minimum must be finite".to_string());
        }
        if !maximum.is_finite() {
            return Err("clip maximum must be finite".to_string());
        }
        if minimum > maximum {
            return Err("clip minimum must not be greater than maximum".to_string());
        }
        let requested = read_name_list(columns, column_count, "clip columns")?;
        let names = numeric_target_columns(&frame.df, &requested, "clip")?;
        if names.is_empty() {
            return Ok(frame.df.clone());
        }
        let mut output = frame.df.clone();
        for name in &names {
            let index = output.get_column_index(name.as_str()).ok_or_else(|| {
                format!("clip column '{name}' is not a column in the DataFrame")
            })?;
            let current = output.columns()[index].clone();
            validate_clip_bound(current.dtype(), minimum, "minimum", name)?;
            validate_clip_bound(current.dtype(), maximum, "maximum", name)?;
            let min_series = Series::new(PlSmallStr::from_str("clip_min"), &[minimum]);
            let max_series = Series::new(PlSmallStr::from_str("clip_max"), &[maximum]);
            let clipped = clip(
                current.as_materialized_series(),
                &min_series,
                &max_series,
            )
            .map_err(|error| {
                format!("could not clip column '{name}' to [{minimum}, {maximum}]: {error}")
            })?;
            output
                .with_column(clipped.into_column())
                .map_err(|error| error.to_string())?;
        }
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Computes the difference between each value and the value `periods` rows
/// before it.
///
/// A null/zero `columns` count targets every primitive numeric column; an
/// explicit list must name numeric columns. The first `periods` rows are null
/// because no earlier value exists. Unsigned inputs widen to Int64 through
/// Polars' diff implementation, while nulls remain null. Column order and the
/// input frame are preserved. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_diff(
    ptr: *mut PlFrame,
    periods: i64,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if periods < 1 {
            return Err("diff periods must be a positive integer".to_string());
        }
        let requested = read_name_list(columns, column_count, "diff columns")?;
        let names = numeric_target_columns(&frame.df, &requested, "diff")?;
        if names.is_empty() {
            return Ok(frame.df.clone());
        }
        let expressions: Vec<Expr> = names
            .iter()
            .map(|name| {
                col(name.as_str())
                    .diff(lit(periods), NullBehavior::Ignore)
                    .alias(name.as_str())
            })
            .collect();
        frame
            .df
            .clone()
            .lazy()
            .with_columns(expressions)
            .collect()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Applies a forward cumulative numeric operation to selected columns.
///
/// `operation` is `sum`, `min`, `max`, `count`, or `prod`, matched
/// case-insensitively. A null/zero `columns` count targets every primitive
/// numeric column; an explicit list must name numeric columns. `count` is a
/// running count of non-null values. Column order and the input frame are
/// preserved. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_cumulative(
    ptr: *mut PlFrame,
    operation: *const c_char,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let operation = read_utf8(operation, "cumulative operation")?;
        let operation = operation.to_ascii_lowercase();
        if !matches!(
            operation.as_str(),
            "sum" | "min" | "max" | "count" | "prod"
        ) {
            return Err(format!(
                "unsupported cumulative operation '{operation}'; expected sum, min, max, count, or prod"
            ));
        }
        let requested = read_name_list(columns, column_count, "cumulative columns")?;
        let names = numeric_target_columns(&frame.df, &requested, "cumulative")?;
        if names.is_empty() {
            return Ok(frame.df.clone());
        }
        let mut expressions = Vec::with_capacity(names.len());
        for name in &names {
            let column = col(name.as_str());
            let expression = match operation.as_str() {
                "sum" => column.cum_sum(false),
                "min" => column.cum_min(false),
                "max" => column.cum_max(false),
                "count" => column.cum_count(false),
                "prod" => column.cum_prod(false),
                _ => unreachable!("operation was validated"),
            };
            expressions.push(expression.alias(name.as_str()));
        }
        frame
            .df
            .clone()
            .lazy()
            .with_columns(expressions)
            .collect()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Casts one or more columns to new dtypes.
///
/// `pairs` is a flat array of `column`, `dtype` string pairs and `pair_count`
/// is the number of pairs. Every named column must exist and every dtype must
/// be one of the primitive cast dtypes documented on [`parse_cast_dtype`].
/// Casting is strict: values that cannot be converted fail the whole operation
/// and leave the input frame unchanged. Column order and names are preserved.
/// This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_cast(
    ptr: *mut PlFrame,
    pairs: *const *const c_char,
    pair_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if pair_count == 0 {
            return Err("cast requires at least one column".to_string());
        }
        if pairs.is_null() {
            return Err("cast columns are null".to_string());
        }
        let pair_count: usize = pair_count
            .try_into()
            .map_err(|_| "cast column count is too large".to_string())?;
        let value_count = pair_count
            .checked_mul(2)
            .ok_or_else(|| "cast column count is too large".to_string())?;
        let raw = std::slice::from_raw_parts(pairs, value_count);
        let mut seen = std::collections::HashSet::new();
        let mut output = frame.df.clone();
        for index in 0..pair_count {
            let column = read_utf8(
                raw[index * 2],
                &format!("cast column at index {index}"),
            )?;
            if column.is_empty() {
                return Err(format!(
                    "cast column at index {index} must not be empty"
                ));
            }
            if !seen.insert(column.clone()) {
                return Err(format!("duplicate cast column '{column}'"));
            }
            let dtype_name = read_utf8(
                raw[index * 2 + 1],
                &format!("cast dtype for '{column}'"),
            )?;
            if dtype_name.is_empty() {
                return Err(format!("cast dtype for '{column}' must not be empty"));
            }
            let dtype = parse_cast_dtype(&dtype_name)?;
            let column_index = output.get_column_index(column.as_str()).ok_or_else(|| {
                format!("cast column '{column}' is not a column in the DataFrame")
            })?;
            let casted = output.columns()[column_index]
                .strict_cast(&dtype)
                .map_err(|error| format!("could not cast column '{column}' to {dtype}: {error}"))?;
            output
                .with_column(casted)
                .map_err(|error| error.to_string())?;
        }
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Fills nulls in place using a Polars fill-null strategy.
///
/// A null/zero request targets every column; otherwise each named column is
/// validated and filled independently so the frame keeps its column order and
/// the other columns keep their nulls. The input frame is unchanged.
fn fill_null_direction_frame(
    df: &DataFrame,
    requested: &[String],
    strategy: FillNullStrategy,
    operation: &str,
) -> Result<DataFrame, String> {
    let names: Vec<String> = if requested.is_empty() {
        df.get_column_names()
            .iter()
            .map(|name| name.to_string())
            .collect()
    } else {
        let mut names = Vec::with_capacity(requested.len());
        for name in requested {
            if df.get_column_index(name.as_str()).is_none() {
                return Err(format!(
                    "{operation} column '{name}' is not a column in the DataFrame"
                ));
            }
            names.push(name.clone());
        }
        names
    };
    let mut output = df.clone();
    for name in names {
        let index = output.get_column_index(name.as_str()).ok_or_else(|| {
            format!("{operation} column '{name}' is not a column in the DataFrame")
        })?;
        let filled = output.columns()[index]
            .fill_null(strategy)
            .map_err(|error| format!("could not fill nulls in column '{name}': {error}"))?;
        output
            .with_column(filled)
            .map_err(|error| error.to_string())?;
    }
    Ok(output)
}

/// Fills nulls with the previous non-null value in each targeted column.
///
/// A null/zero `columns` count targets every column; a name or contiguous list
/// limits the fill and leaves unselected columns untouched. Leading nulls stay
/// null because no previous value exists. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_fill_null_forward(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let requested = read_name_list(columns, column_count, "fill_null_forward columns")?;
        fill_null_direction_frame(
            &frame.df,
            &requested,
            FillNullStrategy::Forward(None),
            "fill_null_forward",
        )
    }));
    finish_frame(result, err)
}

/// Fills nulls with the next non-null value in each targeted column.
///
/// A null/zero `columns` count targets every column; a name or contiguous list
/// limits the fill and leaves unselected columns untouched. Trailing nulls stay
/// null because no following value exists. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_fill_null_backward(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let requested = read_name_list(columns, column_count, "fill_null_backward columns")?;
        fill_null_direction_frame(
            &frame.df,
            &requested,
            FillNullStrategy::Backward(None),
            "fill_null_backward",
        )
    }));
    finish_frame(result, err)
}

/// Returns every `n`th row starting at `offset`.
///
/// `n` must be positive; `offset` is a zero-based row index and may be past the
/// end, which returns an empty frame with the same schema. The result is a
/// newly owned frame and the input frame is unchanged. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_gather_every(
    ptr: *mut PlFrame,
    n: u64,
    offset: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let step = usize::try_from(n)
            .map_err(|_| "gather_every n is too large for this platform".to_string())?;
        if step == 0 {
            return Err("gather_every n must be positive".to_string());
        }
        let offset = usize::try_from(offset)
            .map_err(|_| "gather_every offset is too large for this platform".to_string())?;
        let height = frame.df.height();
        let indices: Vec<IdxSize> = (offset..height)
            .step_by(step)
            .map(|index| index as IdxSize)
            .collect();
        let indices = IdxCa::from_vec(PlSmallStr::EMPTY, indices);
        frame
            .df
            .take(&indices)
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Returns rows by zero-based or negative index.
///
/// `indices` points to `count` signed row indexes. A negative index counts
/// from the end (`-1` is the last row); every resolved index must be inside the
/// frame. Order and duplicates are preserved. A zero count returns an empty
/// frame with the input schema. The input frame is unchanged. This entry point
/// is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_take(
    ptr: *mut PlFrame,
    indices: *const i64,
    count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let count: usize = count
            .try_into()
            .map_err(|_| "take index count is too large".to_string())?;
        if count == 0 {
            return Ok(frame.df.head(Some(0)));
        }
        if indices.is_null() {
            return Err("take indices are null".to_string());
        }
        let height = i64::try_from(frame.df.height())
            .map_err(|_| "DataFrame is too tall for take".to_string())?;
        let raw = std::slice::from_raw_parts(indices, count);
        let mut resolved = Vec::with_capacity(count);
        for (position, &index) in raw.iter().enumerate() {
            let row = if index < 0 {
                index.checked_add(height)
            } else {
                Some(index)
            };
            let row = row.filter(|row| *row >= 0 && *row < height).ok_or_else(|| {
                format!(
                    "take index at position {} is out of bounds for {} rows: {index}",
                    position + 1,
                    height
                )
            })?;
            resolved.push(row as IdxSize);
        }
        let resolved = IdxCa::from_vec(PlSmallStr::EMPTY, resolved);
        frame
            .df
            .take(&resolved)
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Appends a Boolean row mask that is true when any column is null.
///
/// `name` is the appended column name; a null pointer keeps the default
/// `has_nulls`. The name must be non-empty and must not collide with an
/// existing column. A zero-column frame has no rows that can be tested, so it
/// is an error. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_null_mask(
    ptr: *mut PlFrame,
    name: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let name = if name.is_null() {
            "has_nulls".to_string()
        } else {
            read_utf8(name, "null mask name")?
        };
        if name.is_empty() {
            return Err("null mask name must not be empty".to_string());
        }
        if frame.df.get_column_index(name.as_str()).is_some() {
            return Err(format!(
                "null mask column '{name}' already exists in the DataFrame"
            ));
        }
        let columns = frame.df.columns();
        let Some(first) = columns.first() else {
            return Err("null_mask requires at least one column".to_string());
        };
        let mut mask = first.is_null();
        for column in &columns[1..] {
            mask = mask | column.is_null();
        }
        let mut output = frame.df.clone();
        let mut marker = mask.into_column();
        marker.rename(PlSmallStr::from_str(&name));
        output
            .with_column(marker)
            .map_err(|error| error.to_string())?;
        Ok(output)
    }));
    finish_frame(result, err)
}

/// Resolves the float columns a NaN operation should touch.
///
/// A requested list is validated against the frame; entries that are not
/// Float32/Float64 are ignored because only float columns can contain NaN.
/// An empty request means every float column. The returned names keep frame
/// order for the all-column case and request order for an explicit subset.
fn nan_target_columns(
    df: &DataFrame,
    requested: &[String],
    operation: &str,
) -> Result<Vec<String>, String> {
    let is_float = |column: &Column| {
        matches!(column.dtype(), DataType::Float32 | DataType::Float64)
    };
    if requested.is_empty() {
        return Ok(df
            .columns()
            .iter()
            .filter(|column| is_float(column))
            .map(|column| column.name().to_string())
            .collect());
    }
    let mut names = Vec::new();
    for name in requested {
        let column = df.column(name.as_str()).map_err(|_| {
            format!("{operation} column '{name}' is not a column in the DataFrame")
        })?;
        if is_float(column) {
            names.push(name.clone());
        }
    }
    Ok(names)
}

/// Replaces NaN values in float columns with a finite scalar.
///
/// A null/zero `columns` count targets every Float32/Float64 column; otherwise
/// the named columns are checked against the frame and non-float columns are
/// left unchanged. Nulls are preserved because only NaN values match the
/// replacement predicate. `value` must be finite. The input frame is unchanged
/// and the result keeps its column order. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_fill_nan(
    ptr: *mut PlFrame,
    value: f64,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        if !value.is_finite() {
            return Err("fill_nan value must be finite".to_string());
        }
        let requested = read_name_list(columns, column_count, "fill_nan columns")?;
        let names = nan_target_columns(&frame.df, &requested, "fill_nan")?;
        if names.is_empty() {
            return Ok(frame.df.clone());
        }
        let mut expressions = Vec::with_capacity(names.len());
        for name in &names {
            let dtype = frame
                .df
                .column(name.as_str())
                .map_err(|error| error.to_string())?
                .dtype()
                .clone();
            expressions.push(
                when(col(name.as_str()).is_nan())
                    .then(lit(value).cast(dtype))
                    .otherwise(col(name.as_str()))
                    .alias(name.as_str()),
            );
        }
        frame
            .df
            .clone()
            .lazy()
            .with_columns(expressions)
            .collect()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Drops rows containing a NaN in any targeted float column.
///
/// A null/zero `columns` count targets every Float32/Float64 column; otherwise
/// the named columns are checked against the frame and non-float columns are
/// ignored. Null values are kept: a row is removed only for a NaN, not for a
/// null. The input frame is unchanged and the result keeps its column order.
/// This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_drop_nans(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let requested = read_name_list(columns, column_count, "drop_nans columns")?;
        let names = nan_target_columns(&frame.df, &requested, "drop_nans")?;
        if names.is_empty() {
            return Ok(frame.df.clone());
        }
        let mut predicate: Option<Expr> = None;
        for name in &names {
            let column = col(name.as_str());
            let not_nan = column.clone().is_not_nan().or(column.is_null());
            predicate = Some(match predicate {
                Some(current) => current.and(not_nan),
                None => not_nan,
            });
        }
        frame
            .df
            .clone()
            .lazy()
            .filter(predicate.expect("at least one NaN column"))
            .collect()
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Appends a Boolean duplicate marker to a frame.
///
/// `name` is the marker column name; a null pointer keeps the supplied default.
/// The name must be non-empty and must not collide with an existing column.
/// `unique` selects the inverse mask: true marks rows that occur exactly once,
/// false marks rows whose full row value repeats. The input frame is unchanged
/// and the marker is appended after the existing columns.
unsafe fn duplicate_marker_frame(
    frame: &DataFrame,
    name: *const c_char,
    default_name: &str,
    unique: bool,
) -> Result<DataFrame, String> {
    let name = if name.is_null() {
        default_name.to_string()
    } else {
        read_utf8(name, "duplicate marker name")?
    };
    if name.is_empty() {
        return Err("duplicate marker name must not be empty".to_string());
    }
    if frame.get_column_index(name.as_str()).is_some() {
        return Err(format!(
            "duplicate marker column '{name}' already exists in the DataFrame"
        ));
    }
    let mask = if unique {
        frame.is_unique()
    } else {
        frame.is_duplicated()
    }
    .map_err(|error| error.to_string())?;
    let mut output = frame.clone();
    let mut marker = mask.into_column();
    // The mask arrives named `is_unique`/`is_duplicated`; rename it before
    // appending so an existing column with that name is never replaced.
    marker.rename(PlSmallStr::from_str(&name));
    output
        .with_column(marker)
        .map_err(|error| error.to_string())?;
    Ok(output)
}

/// Appends a Boolean column marking duplicated rows.
///
/// The marker is true for every row whose full row value occurs more than
/// once. A null `name` keeps the default `duplicated`; an explicit name must be
/// non-empty and must not collide with an existing column. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_is_duplicated(
    ptr: *mut PlFrame,
    name: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        duplicate_marker_frame(&frame.df, name, "duplicated", false)
    }));
    finish_frame(result, err)
}

/// Appends a Boolean column marking unique rows.
///
/// The marker is true for rows whose full row value occurs exactly once. A null
/// `name` keeps the default `unique`; an explicit name must be non-empty and
/// must not collide with an existing column. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_is_unique(
    ptr: *mut PlFrame,
    name: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        duplicate_marker_frame(&frame.df, name, "unique", true)
    }));
    finish_frame(result, err)
}

/// Parses a `unique` keep strategy from the C ABI.
fn parse_unique_keep(value: Option<&str>) -> Result<UniqueKeepStrategy, String> {
    match value.unwrap_or("first").to_ascii_lowercase().as_str() {
        "" | "first" => Ok(UniqueKeepStrategy::First),
        "last" => Ok(UniqueKeepStrategy::Last),
        "none" => Ok(UniqueKeepStrategy::None),
        "any" => Ok(UniqueKeepStrategy::Any),
        other => Err(format!(
            "unsupported unique keep '{other}'; expected first, last, none, or any"
        )),
    }
}

/// Returns distinct rows, optionally using a column subset and keep strategy.
///
/// A null/zero `columns` count compares every column. `keep` is `first`
/// (default), `last`, `none`, or `any`, matched case-insensitively.
/// `maintain_order` is non-zero to keep the first-seen row order, matching
/// Polars' stable distinct. Names are borrowed for the call. This entry point
/// is additive; the earlier `unique()` Lua helper keeps its all-column result.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_unique(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    keep: *const c_char,
    maintain_order: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let names = read_name_list(columns, column_count, "unique columns")?;
        for name in &names {
            if frame.df.get_column_index(name.as_str()).is_none() {
                return Err(format!(
                    "unique column '{name}' is not a column in the DataFrame"
                ));
            }
        }
        let keep = if keep.is_null() {
            UniqueKeepStrategy::First
        } else {
            let value = read_utf8(keep, "unique keep")?;
            parse_unique_keep(Some(value.as_str()))?
        };
        let subset = if names.is_empty() {
            None
        } else {
            Some(
                names
                    .iter()
                    .map(|name| PlSmallStr::from_str(name.as_str()))
                    .collect(),
            )
        };
        frame
            .df
            .unique_impl(maintain_order != 0, subset, keep, None)
            .map_err(|error| error.to_string())
    }));
    finish_frame(result, err)
}

/// Explodes one or more list columns into long form.
///
/// `columns` points to a non-empty list of list-typed column names.
/// `keep_nulls` is non-zero to keep one null row for a null list, and
/// `empty_as_null` is non-zero to keep one null row for an empty list. Both
/// default to true in the Lua surface. At least one list column is required;
/// non-list columns are rejected with a precise error. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_explode(
    ptr: *mut PlFrame,
    columns: *const *const c_char,
    column_count: u64,
    keep_nulls: i32,
    empty_as_null: i32,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let frame = frame_ref(ptr)?;
        let names = read_name_list(columns, column_count, "explode columns")?;
        if names.is_empty() {
            return Err("explode requires at least one column".to_string());
        }
        for name in &names {
            let column = frame.df.column(name.as_str()).map_err(|_| {
                format!("explode column '{name}' is not a column in the DataFrame")
            })?;
            if !matches!(column.dtype(), DataType::List(_)) {
                return Err(format!(
                    "explode column '{name}' has dtype {}; expected a list",
                    column.dtype()
                ));
            }
        }
        frame
            .df
            .explode(
                names.iter().map(|name| name.as_str()),
                ExplodeOptions {
                    keep_nulls: keep_nulls != 0,
                    empty_as_null: empty_as_null != 0,
                },
            )
            .map_err(|error| error.to_string())
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

fn to_json_string(df: &DataFrame, format: JsonFormat) -> Result<String, String> {
    let mut df = df.clone();
    let mut buffer = Vec::new();
    JsonWriter::new(&mut buffer)
        .with_json_format(format)
        .finish(&mut df)
        .map_err(|error| error.to_string())?;
    String::from_utf8(buffer).map_err(|error| error.to_string())
}

fn to_json_pretty_string(df: &DataFrame) -> Result<String, String> {
    let json = to_json_string(df, JsonFormat::Json)?;
    let value: Value = serde_json::from_str(&json).map_err(|error| error.to_string())?;
    serde_json::to_string_pretty(&value).map_err(|error| error.to_string())
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_to_json(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        to_json_string(&frame.df, JsonFormat::Json)
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

/// Serializes a frame as a JSON array or JSON Lines string.
///
/// `json_lines` is zero for the default array form and non-zero for one object
/// per line. The returned string uses the same `polars` JSON conventions as
/// [`pl_dataframe_to_json`] and must be freed with [`pl_string_free`]. This
/// entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_to_json_format(
    ptr: *mut PlFrame,
    json_lines: i32,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        let format = if json_lines != 0 {
            JsonFormat::JsonLines
        } else {
            JsonFormat::Json
        };
        to_json_string(&frame.df, format)
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

/// Serializes a frame as a pretty-printed JSON array string.
///
/// The output has the same values as [`pl_dataframe_to_json`] with indentation
/// and line breaks. It is always an array; JSON Lines is not supported because
/// pretty-printing would break the one-object-per-line contract. The returned
/// string must be freed with [`pl_string_free`]. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_to_json_pretty(
    ptr: *mut PlFrame,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        to_json_pretty_string(&frame.df)
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
        .include_bom(config.include_bom)
        .with_separator(config.delimiter)
        .with_line_terminator(PlSmallStr::from_str(&config.line_terminator))
        .with_quote_style(config.quote_style)
        .with_float_precision(config.float_precision)
        .with_decimal_comma(config.decimal_comma);
    if let Some(null_value) = config.null_value {
        writer = writer.with_null_value(PlSmallStr::from_str(&null_value));
    }
    writer.finish(&mut df).map_err(|error| error.to_string())
}

unsafe fn finish_write_with(
    result: std::thread::Result<Result<(), String>>,
    err: *mut *mut c_char,
    operation: &str,
) -> i32 {
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => {
            set_error(err, message);
            1
        },
        Err(_) => {
            set_error(err, &format!("{operation} panicked"));
            1
        },
    }
}

unsafe fn finish_write(
    result: std::thread::Result<Result<(), String>>,
    err: *mut *mut c_char,
) -> i32 {
    finish_write_with(result, err, "write_csv")
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
            ..CsvWriteConfig::default()
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

/// Writes a CSV file with delimiter, header, null-value, and line-terminator
/// controls.
///
/// This is the superset writer entry point. `delimiter`, `has_header`, and
/// `null_value` have the same meaning as in
/// [`pl_dataframe_write_csv_options`]. A null or empty `line_terminator` keeps
/// the default `\n`; `\r\n` writes CRLF records, and any other value is an
/// error. The terminator is written literally after the header and every data
/// row. This entry point is additive; every earlier writer signature and
/// default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv_full(
    ptr: *mut PlFrame,
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    line_terminator: *const c_char,
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
            line_terminator: read_csv_line_terminator(line_terminator)?,
            quote_style: QuoteStyle::Necessary,
            float_precision: None,
            include_bom: false,
            decimal_comma: false,
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

/// Writes a CSV file with delimiter, header, null-value, line-terminator, and
/// quote-style controls.
///
/// The first five arguments have the same meaning as in
/// [`pl_dataframe_write_csv_full`]. `quote_style` accepts `necessary` (the
/// default when null or empty), `always`, `non_numeric`/`non-numeric`, and
/// `never`, matched case-insensitively. `never` intentionally permits invalid
/// CSV when a field contains the delimiter, quote, or a line break, matching
/// Polars. This entry point is additive; earlier writer signatures and defaults
/// are unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv_configured(
    ptr: *mut PlFrame,
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    line_terminator: *const c_char,
    quote_style: *const c_char,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let delimiter = read_delimiter(delimiter)?;
        let quote_style_name = if quote_style.is_null() {
            None
        } else {
            Some(read_utf8(quote_style, "quote_style")?)
        };
        let config = CsvWriteConfig {
            delimiter,
            include_header: has_header != 0,
            null_value: read_csv_null_value(null_value, delimiter)?,
            line_terminator: read_csv_line_terminator(line_terminator)?,
            quote_style: parse_csv_quote_style(quote_style_name.as_deref())?,
            float_precision: None,
            include_bom: false,
            decimal_comma: false,
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

/// Converts the writer's `float_precision` ABI value.
///
/// `-1` keeps Polars' default shortest representation; other negative values
/// are errors, and non-negative values are the digits after the decimal point.
fn parse_csv_float_precision(value: i64) -> Result<Option<usize>, String> {
    if value == -1 {
        return Ok(None);
    }
    if value < 0 {
        return Err(format!(
            "CSV float_precision must be -1 for the default or a non-negative count, got {value}"
        ));
    }
    usize::try_from(value)
        .map(Some)
        .map_err(|_| "CSV float_precision is too large for this platform".to_string())
}

/// Writes a CSV file with every earlier writer option plus float precision.
///
/// The delimiter, header, null-value, line-terminator, and quote-style
/// arguments have the same meaning as in
/// [`pl_dataframe_write_csv_configured`]. `float_precision` is a non-negative
/// number of digits after the decimal point for float columns; `-1` keeps
/// Polars' default shortest representation. This entry point is additive;
/// every earlier writer signature and default is unchanged.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv_precise(
    ptr: *mut PlFrame,
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    line_terminator: *const c_char,
    quote_style: *const c_char,
    float_precision: i64,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let delimiter = read_delimiter(delimiter)?;
        let quote_style_name = if quote_style.is_null() {
            None
        } else {
            Some(read_utf8(quote_style, "quote_style")?)
        };
        let config = CsvWriteConfig {
            delimiter,
            include_header: has_header != 0,
            null_value: read_csv_null_value(null_value, delimiter)?,
            line_terminator: read_csv_line_terminator(line_terminator)?,
            quote_style: parse_csv_quote_style(quote_style_name.as_deref())?,
            float_precision: parse_csv_float_precision(float_precision)?,
            include_bom: false,
            decimal_comma: false,
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

/// Writes a CSV file with every earlier writer option plus BOM and decimal
/// controls.
///
/// The delimiter, header, null-value, line-terminator, quote-style, and
/// float-precision arguments have the same meaning as in
/// [`pl_dataframe_write_csv_precise`]. `include_bom` is non-zero to prepend a
/// UTF-8 byte-order mark (`EF BB BF`) to the file. `decimal_comma` is non-zero
/// to serialize float fields with a comma decimal separator, which is intended
/// with a semicolon or tab delimiter. Both default to zero in every earlier
/// writer entry point. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv_complete(
    ptr: *mut PlFrame,
    path: *const c_char,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    line_terminator: *const c_char,
    quote_style: *const c_char,
    float_precision: i64,
    include_bom: i32,
    decimal_comma: i32,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let delimiter = read_delimiter(delimiter)?;
        let quote_style_name = if quote_style.is_null() {
            None
        } else {
            Some(read_utf8(quote_style, "quote_style")?)
        };
        let config = CsvWriteConfig {
            delimiter,
            include_header: has_header != 0,
            null_value: read_csv_null_value(null_value, delimiter)?,
            line_terminator: read_csv_line_terminator(line_terminator)?,
            quote_style: parse_csv_quote_style(quote_style_name.as_deref())?,
            float_precision: parse_csv_float_precision(float_precision)?,
            include_bom: include_bom != 0,
            decimal_comma: decimal_comma != 0,
        };
        write_csv_frame(&frame.df, &path, config)
    }));
    finish_write(result, err)
}

/// Serializes a frame as CSV text.
///
/// The arguments match [`pl_dataframe_write_csv_complete`] but return the bytes
/// as a NUL-terminated string instead of writing a file. The returned string
/// must be freed with [`pl_string_free`]. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_to_csv(
    ptr: *mut PlFrame,
    delimiter: *const c_char,
    has_header: i32,
    null_value: *const c_char,
    line_terminator: *const c_char,
    quote_style: *const c_char,
    float_precision: i64,
    include_bom: i32,
    decimal_comma: i32,
    err: *mut *mut c_char,
) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<String, String> {
        let frame = frame_ref(ptr)?;
        let delimiter = read_delimiter(delimiter)?;
        let quote_style_name = if quote_style.is_null() {
            None
        } else {
            Some(read_utf8(quote_style, "quote_style")?)
        };
        let config = CsvWriteConfig {
            delimiter,
            include_header: has_header != 0,
            null_value: read_csv_null_value(null_value, delimiter)?,
            line_terminator: read_csv_line_terminator(line_terminator)?,
            quote_style: parse_csv_quote_style(quote_style_name.as_deref())?,
            float_precision: parse_csv_float_precision(float_precision)?,
            include_bom: include_bom != 0,
            decimal_comma: decimal_comma != 0,
        };
        let mut df = frame.df.clone();
        let mut buffer = Vec::new();
        let mut writer = CsvWriter::new(&mut buffer)
            .include_header(config.include_header)
            .include_bom(config.include_bom)
            .with_separator(config.delimiter)
            .with_line_terminator(PlSmallStr::from_str(&config.line_terminator))
            .with_quote_style(config.quote_style)
            .with_float_precision(config.float_precision)
            .with_decimal_comma(config.decimal_comma);
        if let Some(null_value) = config.null_value {
            writer = writer.with_null_value(PlSmallStr::from_str(&null_value));
        }
        writer
            .finish(&mut df)
            .map_err(|error| error.to_string())?;
        String::from_utf8(buffer).map_err(|error| error.to_string())
    }));
    match result {
        Ok(Ok(csv)) => c_string(&csv),
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

/// Parses the optional Parquet compression codec name.
///
/// A null or empty name keeps Polars' default of Zstd. Names are matched
/// case-insensitively; `none` is an alias for `uncompressed` and `lz4-raw` is
/// an alias for `lz4`. The pinned Polars writer always uses the codec's
/// default compression level, so no level is exposed yet.
fn parse_parquet_compression(value: Option<&str>) -> Result<ParquetCompression, String> {
    let value = value.unwrap_or("zstd");
    match value.to_ascii_lowercase().as_str() {
        "" | "zstd" => Ok(ParquetCompression::Zstd(None)),
        "snappy" => Ok(ParquetCompression::Snappy),
        "gzip" => Ok(ParquetCompression::Gzip(None)),
        "brotli" => Ok(ParquetCompression::Brotli(None)),
        "lz4" | "lz4-raw" => Ok(ParquetCompression::Lz4Raw),
        "uncompressed" | "none" => Ok(ParquetCompression::Uncompressed),
        other => Err(format!(
            "unsupported Parquet compression '{other}'; expected zstd, snappy, gzip, brotli, lz4, or uncompressed"
        )),
    }
}

/// Parses a codec name plus an optional compression level.
///
/// A negative level keeps the codec default. Levels apply to zstd (1..=22),
/// gzip (0..=9), and brotli (0..=11); other codecs reject an explicit level.
fn parse_parquet_compression_level(
    value: Option<&str>,
    level: i64,
) -> Result<ParquetCompression, String> {
    let value = value.unwrap_or("zstd");
    if level < 0 {
        return parse_parquet_compression(Some(value));
    }
    match value.to_ascii_lowercase().as_str() {
        "" | "zstd" => {
            let level = i32::try_from(level)
                .map_err(|_| "Parquet zstd compression_level is too large".to_string())?;
            let level = ZstdLevel::try_new(level).map_err(|error| error.to_string())?;
            Ok(ParquetCompression::Zstd(Some(level)))
        },
        "gzip" => {
            let level = u8::try_from(level)
                .map_err(|_| "Parquet gzip compression_level is too large".to_string())?;
            let level = GzipLevel::try_new(level).map_err(|error| error.to_string())?;
            Ok(ParquetCompression::Gzip(Some(level)))
        },
        "brotli" => {
            let level = u32::try_from(level)
                .map_err(|_| "Parquet brotli compression_level is too large".to_string())?;
            let level = BrotliLevel::try_new(level).map_err(|error| error.to_string())?;
            Ok(ParquetCompression::Brotli(Some(level)))
        },
        "snappy" | "lz4" | "lz4-raw" | "uncompressed" | "none" => Err(format!(
            "compression_level is not supported for Parquet codec '{value}'"
        )),
        other => Err(format!(
            "unsupported Parquet compression '{other}'; expected zstd, snappy, gzip, brotli, lz4, or uncompressed"
        )),
    }
}

/// Converts an optional positive ABI size into `Option<usize>`.
///
/// Zero means "use the Polars default". Any non-zero value must fit in
/// `usize`; the caller validates that it is a positive integer in Lua terms.
fn optional_parquet_size(value: u64, label: &str) -> Result<Option<usize>, String> {
    if value == 0 {
        return Ok(None);
    }
    usize::try_from(value)
        .map(Some)
        .map_err(|_| format!("{label} is too large"))
}

#[derive(Clone)]
struct ParquetWriteConfig {
    compression: ParquetCompression,
    statistics: StatisticsOptions,
    row_group_size: Option<usize>,
    data_page_size: Option<usize>,
}

impl Default for ParquetWriteConfig {
    fn default() -> Self {
        Self {
            compression: ParquetCompression::default(),
            statistics: StatisticsOptions::default(),
            row_group_size: None,
            data_page_size: None,
        }
    }
}

fn write_parquet_frame(
    df: &DataFrame,
    path: &str,
    config: ParquetWriteConfig,
) -> Result<(), String> {
    let file = File::create(path).map_err(|error| error.to_string())?;
    let mut df = df.clone();
    let mut writer = ParquetWriter::new(file)
        .with_compression(config.compression)
        .with_statistics(config.statistics);
    if let Some(row_group_size) = config.row_group_size {
        writer = writer.with_row_group_size(Some(row_group_size));
    }
    if let Some(data_page_size) = config.data_page_size {
        writer = writer.with_data_page_size(Some(data_page_size));
    }
    writer
        .finish(&mut df)
        .map(|_| ())
        .map_err(|error| error.to_string())
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
        write_parquet_frame(&frame.df, &path, ParquetWriteConfig::default())
    }));
    finish_write_with(result, err, "write_parquet")
}

/// Writes a Parquet file with compression, statistics, and chunk-size controls.
///
/// A null or empty `compression` keeps the default Zstd; the accepted names
/// are `zstd`, `snappy`, `gzip`, `brotli`, `lz4`/`lz4-raw`, and
/// `uncompressed`/`none`, matched case-insensitively. `statistics` is zero to
/// skip column statistics and non-zero for the Polars defaults. A zero
/// `row_group_size` or `data_page_size` keeps the Polars default; non-zero
/// values are row and byte counts respectively.
///
/// This entry point is additive; [`pl_dataframe_write_parquet`] keeps its
/// signature and default Zstd/statistics/chunking behavior.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_parquet_options(
    ptr: *mut PlFrame,
    path: *const c_char,
    compression: *const c_char,
    statistics: i32,
    row_group_size: u64,
    data_page_size: u64,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let compression_name = if compression.is_null() {
            None
        } else {
            Some(read_utf8(compression, "compression")?)
        };
        let config = ParquetWriteConfig {
            compression: parse_parquet_compression(compression_name.as_deref())?,
            statistics: if statistics == 0 {
                StatisticsOptions::empty()
            } else {
                StatisticsOptions::default()
            },
            row_group_size: optional_parquet_size(row_group_size, "Parquet row_group_size")?,
            data_page_size: optional_parquet_size(data_page_size, "Parquet data_page_size")?,
        };
        write_parquet_frame(&frame.df, &path, config)
    }));
    finish_write_with(result, err, "write_parquet")
}

/// Writes a Parquet file with an explicit compression level.
///
/// The arguments match [`pl_dataframe_write_parquet_options`] plus
/// `compression_level`. A negative level keeps the codec default; zstd, gzip,
/// and brotli accept their codec-specific ranges, while other codecs reject an
/// explicit level. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_parquet_leveled(
    ptr: *mut PlFrame,
    path: *const c_char,
    compression: *const c_char,
    statistics: i32,
    row_group_size: u64,
    data_page_size: u64,
    compression_level: i64,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let compression_name = if compression.is_null() {
            None
        } else {
            Some(read_utf8(compression, "compression")?)
        };
        let config = ParquetWriteConfig {
            compression: parse_parquet_compression_level(
                compression_name.as_deref(),
                compression_level,
            )?,
            statistics: if statistics == 0 {
                StatisticsOptions::empty()
            } else {
                StatisticsOptions::default()
            },
            row_group_size: optional_parquet_size(row_group_size, "Parquet row_group_size")?,
            data_page_size: optional_parquet_size(data_page_size, "Parquet data_page_size")?,
        };
        write_parquet_frame(&frame.df, &path, config)
    }));
    finish_write_with(result, err, "write_parquet")
}

/// Writes a frame as a JSON array or JSON Lines file.
///
/// `json_lines` is zero for a single JSON array and non-zero for one object per
/// line. The file is created or truncated. Non-primitive Polars values are
/// formatted by the Arrow JSON writer, matching `to_json`. This entry point is
/// additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_json(
    ptr: *mut PlFrame,
    path: *const c_char,
    json_lines: i32,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let file = File::create(path).map_err(|error| error.to_string())?;
        let mut df = frame.df.clone();
        JsonWriter::new(file)
            .with_json_format(if json_lines != 0 {
                JsonFormat::JsonLines
            } else {
                JsonFormat::Json
            })
            .finish(&mut df)
            .map_err(|error| error.to_string())
    }));
    finish_write_with(result, err, "write_json")
}

/// Writes a pretty-printed JSON array.
///
/// JSON Lines is not supported by this entry point because pretty-printing a
/// stream would break the one-object-per-line format; a non-zero `json_lines`
/// is an error. Array output is parsed and re-serialized with indentation, so
/// it is valid JSON with the same values as [`pl_dataframe_write_json`]. The
/// function returns zero on success. This entry point is additive.
#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_json_pretty(
    ptr: *mut PlFrame,
    path: *const c_char,
    json_lines: i32,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        if json_lines != 0 {
            return Err("pretty write_json supports only the array format".to_string());
        }
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let pretty = to_json_pretty_string(&frame.df)?;
        std::fs::write(path, pretty).map_err(|error| error.to_string())
    }));
    finish_write_with(result, err, "write_json")
}
