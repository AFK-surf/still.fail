// A file's bytes read and written by a test run on Wasm (`moon test --target wasm-gc`, in moonrun): moonrun's
// "__moonbit_fs_unstable", as moonbitlang/x's fs asks it. What a test reads and writes on native through a C stub of
// its own (skiatest's, the gallery's read_file.c) on Wasm, where no C is compiled. Empty on the other targets.

///|
#external
priv type XStringCreateHandle

///|
#external
priv type XExternString

///|
#external
priv type XByteArrayCreateHandle

///|
#external
priv type XByteArrayReadHandle

///|
#external
priv type XExternByteArray

///|
fn begin_create_string() -> XStringCreateHandle = "__moonbit_fs_unstable" "begin_create_string"

///|
fn string_append_char(handle : XStringCreateHandle, ch : Char) = "__moonbit_fs_unstable" "string_append_char"

///|
fn finish_create_string(handle : XStringCreateHandle) -> XExternString = "__moonbit_fs_unstable" "finish_create_string"

///|
fn begin_read_byte_array(s : XExternByteArray) -> XByteArrayReadHandle = "__moonbit_fs_unstable" "begin_read_byte_array"

///|
fn byte_array_read_byte(handle : XByteArrayReadHandle) -> Int = "__moonbit_fs_unstable" "byte_array_read_byte"

///|
fn finish_read_byte_array(handle : XByteArrayReadHandle) = "__moonbit_fs_unstable" "finish_read_byte_array"

///|
fn begin_create_byte_array() -> XByteArrayCreateHandle = "__moonbit_fs_unstable" "begin_create_byte_array"

///|
fn byte_array_append_byte(handle : XByteArrayCreateHandle, b : Int) = "__moonbit_fs_unstable" "byte_array_append_byte"

///|
fn finish_create_byte_array(handle : XByteArrayCreateHandle) -> XExternByteArray = "__moonbit_fs_unstable" "finish_create_byte_array"

///|
fn get_file_content() -> XExternByteArray = "__moonbit_fs_unstable" "get_file_content"

///|
fn read_file_to_bytes(path : XExternString) -> Int = "__moonbit_fs_unstable" "read_file_to_bytes_new"

///|
fn write_bytes_to_file(path : XExternString, content : XExternByteArray) -> Int = "__moonbit_fs_unstable" "write_bytes_to_file_new"

///|
fn extern_string(s : String) -> XExternString {
  let h = begin_create_string()
  for c in s.code_units() {
    string_append_char(h, c.unsafe_to_char())
  }
  finish_create_string(h)
}

///|
/// A file's bytes, None when it cannot be read.
pub fn read(path : String) -> Bytes? {
  if read_file_to_bytes(extern_string(path)) == -1 {
    return None
  }
  let out : Array[Byte] = []
  let h = begin_read_byte_array(get_file_content())
  while true {
    let b = byte_array_read_byte(h)
    if b == -1 {
      break
    }
    out.push(b.to_byte())
  }
  finish_read_byte_array(h)
  Some(Bytes::from_array(out[:]))
}

///|
/// Writes a file; whether it could.
pub fn write(path : String, data : Bytes) -> Bool {
  let h = begin_create_byte_array()
  for b in data {
    byte_array_append_byte(h, b.to_int())
  }
  write_bytes_to_file(extern_string(path), finish_create_byte_array(h)) != -1
}
