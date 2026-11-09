///|
/// A string `n` units long, for mbui's native shell to fill and give on (a callback's argument: mbui/wasmrt), as
/// src/stillfail's: the made-up chats run by the shell (scripts/latency.sh) are given words by their host too.
pub fn mbw_string(n : Int) -> String {
  @wasmrt.new_string(n)
}

///|
pub fn mbw_bytes(n : Int) -> Bytes {
  @wasmrt.new_bytes(n)
}
