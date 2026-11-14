// terminal.mbt's calls in a browser: none kept yet (libghostty-vt's Wasm is a step of its own), so the app shows no
// terminal there.

///|
fn tm_open(_cols : Int, _rows : Int) -> Int {
  0
}

///|
fn tm_write(_id : Int, _data : Bytes) -> Unit {
  ()
}

///|
fn tm_resize(_id : Int, _cols : Int, _rows : Int) -> Unit {
  ()
}

///|
fn tm_lines(_id : Int) -> String {
  ""
}

///|
fn tm_close(_id : Int) -> Unit {
  ()
}
