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
    static VERSION: &[u8] = b"0.4.0\0";
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_read_csv(
    path: *const c_char,
    err: *mut *mut c_char,
) -> *mut PlFrame {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<DataFrame, String> {
        let path = read_path(path)?;
        CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(PathBuf::from(path)))
            .map_err(|error| error.to_string())?
            .finish()
            .map_err(|error| error.to_string())
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

#[no_mangle]
pub unsafe extern "C" fn pl_dataframe_write_csv(
    ptr: *mut PlFrame,
    path: *const c_char,
    err: *mut *mut c_char,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<(), String> {
        let frame = frame_ref(ptr)?;
        let path = read_path(path)?;
        let file = File::create(&path).map_err(|error| error.to_string())?;
        let mut df = frame.df.clone();
        CsvWriter::new(file).finish(&mut df).map_err(|error| error.to_string())?;
        Ok(())
    }));
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(message)) => { set_error(err, message); 1 }
        Err(_) => { set_error(err, "write_csv panicked"); 1 }
    }
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
