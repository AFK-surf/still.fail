///|
#borrow(path)
extern "C" fn read_file_bytes(path : Bytes) -> Bytes = "mbui_skiatest_read_file"

///|
/// A file's bytes, empty when there is none.
pub fn read_file(path : String) -> Bytes {
  read_file_bytes(@utf8.encode(path + "\u{0}"))
}

///|
#borrow(path, data)
extern "C" fn write_file_bytes(path : Bytes, data : Bytes) -> Int = "mbui_skiatest_write_file"

///|
/// Writes a file; whether it could.
pub fn write_file(path : String, data : Bytes) -> Bool {
  write_file_bytes(@utf8.encode(path + "\u{0}"), data) != 0
}
