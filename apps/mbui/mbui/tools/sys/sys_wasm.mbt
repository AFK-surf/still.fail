// What sys.mbt asks of the system on Wasm: scripts/wasmrun.mjs's "tsys" imports, the same calls as sys.c's. Bytes
// cross as JavaScript strings of one character a byte (Latin-1), which JavaScript's string builtins pass whole.

///|
fn bytes_text(b : Bytes) -> String {
  let s = StringBuilder(size_hint=b.length())
  for x in b {
    s.write_char(x.to_int().unsafe_to_char())
  }
  s.to_string()
}

///|
fn text_bytes(s : String) -> Bytes {
  Bytes::makei(s.length(), i => s[i].to_byte())
}

///|
fn h_ok() -> Int = "tsys" "ok"

///|
fn h_read(path : String) -> String = "tsys" "read"

///|
fn h_write(path : String, data : String) -> Int = "tsys" "write"

///|
fn h_kind(path : String) -> Int = "tsys" "kind"

///|
fn h_mkdir(path : String) -> Int = "tsys" "mkdir"

///|
fn h_remove(path : String) -> Int = "tsys" "remove"

///|
fn h_list(path : String) -> String = "tsys" "list"

///|
fn h_getenv(name : String) -> String = "tsys" "getenv"

///|
fn h_getcwd() -> String = "tsys" "getcwd"

///|
fn h_out(s : String, err : Int) -> Unit = "tsys" "out"

///|
fn h_exit(code : Int) -> Unit = "tsys" "exit"

///|
fn h_is_link(path : String) -> Int = "tsys" "isLink"

///|
fn h_read_stdin() -> String = "tsys" "readStdin"

///|
fn h_run_out(cmd : String) -> String = "tsys" "runOut"

///|
fn c_ok() -> Int {
  h_ok()
}

///|
fn c_read(path : Bytes) -> Bytes {
  text_bytes(h_read(bytes_text(path)))
}

///|
fn c_write(path : Bytes, data : Bytes) -> Int {
  h_write(bytes_text(path), bytes_text(data))
}

///|
fn c_kind(path : Bytes) -> Int {
  h_kind(bytes_text(path))
}

///|
fn c_mkdir(path : Bytes) -> Int {
  h_mkdir(bytes_text(path))
}

///|
fn c_remove(path : Bytes) -> Int {
  h_remove(bytes_text(path))
}

///|
fn c_list(path : Bytes) -> Bytes {
  text_bytes(h_list(bytes_text(path)))
}

///|
fn c_getenv(name : Bytes) -> Bytes {
  text_bytes(h_getenv(bytes_text(name)))
}

///|
fn c_getcwd() -> Bytes {
  text_bytes(h_getcwd())
}

///|
fn c_out(s : Bytes, err : Int) -> Unit {
  h_out(bytes_text(s), err)
}

///|
fn c_exit(code : Int) -> Unit {
  h_exit(code)
}

///|
fn c_is_link(path : Bytes) -> Int {
  h_is_link(bytes_text(path))
}

///|
fn c_read_stdin() -> Bytes {
  text_bytes(h_read_stdin())
}

///|
fn c_run_out(cmd : Bytes) -> Bytes {
  text_bytes(h_run_out(bytes_text(cmd)))
}
