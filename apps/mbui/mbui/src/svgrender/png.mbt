// A streaming RGB PNG writer. Its input bands stay with the caller; close releases
// a cancelled writer, and finish consumes it. Missing rows are black, alpha ignored.
///|
pub struct PngEncoder {
  mut writer : PngDb?
}

///|
pub fn PngEncoder::new(width : Int, height : Int) -> PngEncoder? {
  if width <= 0 || height <= 0 || width > 0x1FFFFFFF { return None }
  let writer = png_new(width, height)
  if !png_valid(writer) { return None }
  Some({ writer: Some(writer) })
}

///|
pub fn PngEncoder::add(self : PngEncoder, rgba : Bytes, count : Int) -> Bool {
  if count < 0 { return false }
  match self.writer {
    Some(writer) => png_add(writer, rgba, count)
    None => false
  }
}

///|
pub fn PngEncoder::finish(self : PngEncoder) -> Bytes? {
  let writer = match self.writer { Some(writer) => writer; None => return None }
  self.writer = None
  let bytes = png_end(writer)
  if bytes.is_empty() { None } else { Some(bytes) }
}

///|
pub fn PngEncoder::close(self : PngEncoder) -> Unit {
  if self.writer is Some(writer) { png_free(writer) }
  self.writer = None
}
