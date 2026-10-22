///|
extern "C" fn emit_path_bytes() -> Bytes = "sfr_emit_path"

///|
#borrow(path, text)
extern "C" fn write_bytes(path : Bytes, text : Bytes) -> Int = "sfr_write_file"

///|
/// Where a flow's steps go as a scripted run's (FLOW_EMIT, scripts/rerecord.sh): "" when nothing asks for them.
fn emit_path() -> String {
  @utf8.decode_lossy(emit_path_bytes()[:])
}

///|
fn write_file(path : String, text : String) -> Unit {
  write_bytes(@utf8.encode(path), @utf8.encode(text)) |> ignore
}
