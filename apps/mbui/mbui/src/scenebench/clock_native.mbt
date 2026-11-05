///|
extern "C" fn ffi_now_ms() -> Double = "msb_now_ms"

///|
/// The wall clock (ms): what the bench times the frames by.
fn now_ms() -> Double {
  ffi_now_ms()
}
