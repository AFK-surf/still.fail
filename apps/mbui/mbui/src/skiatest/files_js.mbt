///|
/// A file's bytes: none in a browser.
pub fn read_file(_path : String) -> Bytes {
  b""
}

///|
/// Writes a file: not in a browser.
pub fn write_file(_path : String, _data : Bytes) -> Bool {
  false
}
