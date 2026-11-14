// What logwait asks of the system on Wasm: scripts/wasmrun.mjs's "chkev" imports, the same calls as events.c's
// (paths as tools/sys passes them: a byte a character).

///|
fn latin1(b : Bytes) -> String {
  let s = StringBuilder(size_hint=b.length())
  for x in b {
    s.write_char(x.to_int().unsafe_to_char())
  }
  s.to_string()
}

///|
fn h_ev_init() -> Int = "chkev" "init"

///|
fn h_ev_open(k : Int, path : String) -> Int = "chkev" "open"

///|
fn h_ev_read(k : Int) -> String = "chkev" "read"

///|
fn h_ev_file(k : Int) -> Int = "chkev" "file"

///|
fn h_ev_dir(path : String) -> Int = "chkev" "dir"

///|
fn h_ev_pid(pid : Int) -> Int = "chkev" "pid"

///|
fn h_ev_wait(ms : Int) -> Int = "chkev" "wait"

///|
fn ev_init() -> Int {
  h_ev_init()
}

///|
fn ev_open(k : Int, path : Bytes) -> Int {
  h_ev_open(k, latin1(path))
}

///|
fn ev_open_path(_k : Int, _path : Bytes) -> Int {
  1
}

///|
fn ev_read(k : Int) -> Bytes {
  let s = h_ev_read(k)
  Bytes::makei(s.length(), i => s[i].to_byte())
}

///|
fn ev_file(k : Int) -> Int {
  h_ev_file(k)
}

///|
fn ev_dir(path : Bytes) -> Int {
  h_ev_dir(latin1(path))
}

///|
fn ev_pid(pid : Int) -> Int {
  h_ev_pid(pid)
}

///|
fn ev_wait(ms : Int) -> Int {
  h_ev_wait(ms)
}
