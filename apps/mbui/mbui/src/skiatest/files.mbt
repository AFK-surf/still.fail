///|
#borrow(path)
extern "C" fn read_file_bytes(path : Bytes) -> Bytes = "mbui_skiatest_read_file"

///|
/// A file's bytes, empty when there is none.
pub fn read_file(path : String) -> Bytes {
  read_file_bytes(@utf8.encode(path + "\u{0}"))
}
