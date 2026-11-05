///|
/// A string `n` units long, for mbui's native shell to fill and give on (a callback's argument, words typed among them:
/// mbui/wasmrt), as still.fail's own (src/stillfail/wasm_shell.mbt).
pub fn mbw_string(n : Int) -> String {
  @wasmrt.new_string(n)
}

///|
pub fn mbw_bytes(n : Int) -> Bytes {
  @wasmrt.new_bytes(n)
}
