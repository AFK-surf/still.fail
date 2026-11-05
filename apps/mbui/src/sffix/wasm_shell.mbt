///|
/// Allocate a callback argument for the native Wasm shell, as the full app does.
pub fn mbw_string(n : Int) -> String {
  @wasmrt.new_string(n)
}

///|
pub fn mbw_bytes(n : Int) -> Bytes {
  @wasmrt.new_bytes(n)
}
