//! Generate the test Parquet fixture from the CSV fixture.
use std::fs::File;
use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let mut df = CsvReadOptions::default()
        .with_has_header(true)
        .try_into_reader_with_file_path(Some("tests/fixtures/sample.csv".into()))?
        .finish()?;
    let file = File::create("tests/fixtures/sample.parquet")?;
    ParquetWriter::new(file).finish(&mut df)?;
    Ok(())
}
