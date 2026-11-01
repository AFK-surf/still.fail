// The reference images the skia tests compare with, decoded by @pixels.decode_png.

///|
/// The image's width, height and RGBA bytes (straight), None where it is not a PNG.
pub fn decode_png(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  @pixels.decode_png(b)
}

///|
/// A PNG as a pixmap: its colours premultiplied (Pixmap::decode_png).
pub fn load_pixmap(path : String) -> @skia.Pixmap? {
  match decode_png(read_file(path)) {
    Some((w, h, rgba)) => {
      for i in 0..<(w * h) {
        let a = rgba[i * 4 + 3].to_int()
        for k in 0..<3 {
          rgba[i * 4 + k] = @skia.premultiply_u8(rgba[i * 4 + k].to_int(), a).to_byte()
        }
      }
      @skia.Pixmap::from_data(rgba, w, h)
    }
    None => None
  }
}

///|
/// Whether two pixmaps are the same, byte for byte.
pub fn same_pixmap(a : @skia.Pixmap, b : @skia.Pixmap) -> Bool {
  if a.width != b.width || a.height != b.height {
    return false
  }
  for i in 0..<a.data.length() {
    if a.data[i] != b.data[i] {
      return false
    }
  }
  true
}

///|
/// How many pixels differ (for a failure's message).
pub fn diff_count(a : @skia.Pixmap, b : @skia.Pixmap) -> Int {
  if a.width != b.width || a.height != b.height {
    return -1
  }
  let mut n = 0
  for i in 0..<(a.width * a.height) {
    for k in 0..<4 {
      if a.data[i * 4 + k] != b.data[i * 4 + k] {
        n += 1
        break
      }
    }
  }
  n
}

///|
/// A PNG of one channel (or its alpha) as a mask (Mask::load_png: its first byte a pixel for gray, its alpha else).
pub fn load_mask(path : String) -> @skia.Mask? {
  match decode_png(read_file(path)) {
    Some((w, h, rgba)) => {
      let data = FixedArray::makei(w * h, fn(i) { rgba[i * 4 + 3] })
      // (a gray image's value; an alpha image's alpha)
      let gray = rgba.length() > 0 && (0).until(w * h).all(fn(i) { rgba[i * 4 + 3] == b'\xff' })
      if gray {
        for i in 0..<(w * h) {
          data[i] = rgba[i * 4]
        }
      }
      Some({ data, width: w, height: h })
    }
    None => None
  }
}
