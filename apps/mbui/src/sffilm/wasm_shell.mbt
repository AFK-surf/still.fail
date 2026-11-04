///|
/// A string `n` units long, for mbui's native shell to fill and give on (mbui/wasmrt).
pub fn mbw_string(n : Int) -> String {
  @wasmrt.new_string(n)
}

///|
pub fn mbw_bytes(n : Int) -> Bytes {
  @wasmrt.new_bytes(n)
}

///|
/// What mbui/film asks the shell next (a name: film_wasm.mbt), as the shell reads it.
pub fn film_text_length() -> Int {
  @film.wasm_text_length()
}

///|
pub fn film_text_unit(i : Int) -> Int {
  @film.wasm_text_unit(i)
}
