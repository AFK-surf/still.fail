///|
/// A file's bytes, empty when there is none (moonrun's: mbui/runfs).
pub fn read_file(path : String) -> Bytes {
  @runfs.read(path).unwrap_or(b"")
}

///|
/// Writes a file; whether it could.
pub fn write_file(path : String, data : Bytes) -> Bool {
  @runfs.write(path, data)
}
