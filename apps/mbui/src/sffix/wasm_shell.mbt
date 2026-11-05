///|
/// A string `n` units long, for mbui's native shell to fill and give on (a callback's argument: mbui/wasmrt), as the
/// app's (stillfail/wasm_shell.mbt): the words typed, what the keyboard's field holds.
pub fn mbw_string(n : Int) -> String {
  @wasmrt.new_string(n)
}

///|
pub fn mbw_bytes(n : Int) -> Bytes {
  @wasmrt.new_bytes(n)
}
