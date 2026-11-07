// Streaming image output belongs to the host. Tests need no native image library.
///|
pub(all) struct PngWriter {
  add : (Bytes, Int) -> Bool
  finish : () -> Bytes?
  close : () -> Unit
}

///|
/// None while loading; Some(false) when unavailable. Readiness wakes the host frame.
pub fn png_ready() -> Bool? { current.val.png_ready() }

///|
pub fn png_writer(width : Int, height : Int) -> PngWriter? {
  current.val.png_writer(width, height)
}

///|
impl Host with png_ready(_) { Some(false) }

///|
impl Host with png_writer(_, _, _) { None }
