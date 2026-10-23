///|
#borrow(name)
extern "C" fn trace_bytes(name : Bytes) -> Bytes = "sfr_trace_read"

///|
extern "C" fn trace_found() -> Int = "sfr_trace_found"

///|
pub fn read_trace(name : String) -> String? {
  let b = trace_bytes(@utf8.encode(name))
  if trace_found() == 0 {
    None
  } else {
    Some(@utf8.decode_lossy(b[:]))
  }
}
