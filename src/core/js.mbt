// No engine on the web yet (the web app runs the core in a worker of its own): `start` answers false.

///|
fn ffi_start(_data_dir : String, _cloud : String, _beta : Int) -> Int {
  0
}

///|
fn ffi_send(_json : String) -> Unit {

}

///|
fn ffi_stop() -> Unit {

}

///|
fn ffi_next() -> String {
  ""
}

///|
fn ffi_set_wake(_f : FuncRef[() -> Unit]) -> Unit {

}

///|
fn ffi_web_auth(_token : Int, _url : String, _scheme : String) -> Int {
  0
}

///|
fn ffi_now() -> Double {
  0.0
}

///|
fn ffi_next_bytes() -> Bytes {
  b""
}

///|
extern "js" fn ffi_wall_ms() -> Double =
  #|() => Date.now()
