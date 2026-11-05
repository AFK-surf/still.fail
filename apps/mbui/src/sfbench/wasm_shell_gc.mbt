///|
/// Room for a string `n` units long in the memory mbui's native shell gave the program, for the shell to fill and give
/// on (mbui/wasmrt's wasmrt_gc.mbt): its place.
pub fn mbw_string(n : Int) -> Int {
  @wasmrt.new_string_at(n)
}

///|
pub fn mbw_bytes(n : Int) -> Int {
  @wasmrt.new_bytes_at(n)
}

///|
/// What mbui/film asks the shell next (its script's path, a line it says: film_wasm.mbt), as the shell reads it.
pub fn film_text_length() -> Int {
  @film.wasm_text_length()
}

///|
pub fn film_text_unit(i : Int) -> Int {
  @film.wasm_text_unit(i)
}
