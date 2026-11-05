///|
/// Room for a string `n` units long in the memory mbui's native shell gave the program, for the shell to fill and give
/// on (a callback's argument: mbui/wasmrt, wasmrt_gc.mbt): its place.
pub fn mbw_string(n : Int) -> Int {
  @wasmrt.new_string_at(n)
}

///|
pub fn mbw_bytes(n : Int) -> Int {
  @wasmrt.new_bytes_at(n)
}
