// Owned renderer state. Call close when its owner is reset or disposed.
///|
pub struct Renderer {
  mut database : Db?
  mut fonts : Array[Bytes]
}

///|
pub fn Renderer::new() -> Renderer {
  { database: None, fonts: [] }
}

///|
pub fn rasterize(data : Bytes, side : Int) -> (Int, Int, FixedArray[Byte])? {
  let renderer = Renderer::new()
  let result = renderer.rasterize(data, side)
  renderer.close()
  result
}

///|
pub fn Renderer::close(self : Renderer) -> Unit {
  if self.database is Some(db) { db_free(db) }
  self.database = None
  self.fonts = []
}

///|
pub fn Renderer::rasterize(self : Renderer, data : Bytes, side : Int, fonts? : Array[Bytes] = []) -> (Int, Int, FixedArray[Byte])? {
  if side <= 0 { return None }
  let mut changed = self.database is None || self.fonts.length() != fonts.length()
  if !changed {
    for i in 0..<fonts.length() {
      if !physical_equal(self.fonts[i], fonts[i]) { changed = true; break }
    }
  }
  if changed {
    self.close()
    let db = db_new()
    for font in fonts { db_add(db, font) }
    self.database = Some(db)
    self.fonts = fonts.copy()
  }
  let bytes = db_draw(self.database.unwrap(), data, side)
  if bytes.length() < 8 { return None }
  let word = fn(at) {
    bytes[at].to_int() | (bytes[at + 1].to_int() << 8) |
    (bytes[at + 2].to_int() << 16) | (bytes[at + 3].to_int() << 24)
  }
  let width = word(0)
  let height = word(4)
  let rgba = FixedArray::make(bytes.length() - 8, b'\x00')
  for i in 0..<rgba.length() { rgba[i] = bytes[i + 8] }
  Some((width, height, rgba))
}
