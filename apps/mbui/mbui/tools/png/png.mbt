// A PNG's pixels, as the checks of pictures read them: an 8-bit RGB or RGBA picture, its rows unfiltered.

///|
pub struct Picture {
  w : Int
  h : Int
  /// bytes a pixel: 3 RGB, 4 RGBA
  bpp : Int
  rows : Array[Bytes]
}

///|
/// The pixel at (x, y): its red, green and blue
pub fn Picture::rgb(self : Picture, x : Int, y : Int) -> (Int, Int, Int) {
  let r = self.rows[y]
  let i = x * self.bpp
  (r[i].to_int(), r[i + 1].to_int(), r[i + 2].to_int())
}

///|
/// The PNG at `path`, or why not. Pixel decoding is shared with the application.
pub fn read(path : String) -> Result[Picture, String] {
  let d = match @sys.read_bytes(path) {
    Some(d) => d
    None => return Err("\{path}: cannot be read")
  }
  if d.length() < 29 || d[24] != b'\x08' || (d[25] != b'\x02' && d[25] != b'\x06') {
    return Err("\{path}: not an 8-bit RGB(A) PNG")
  }
  let (w, h, rgba) = match @pixels.decode_png(d) {
    Some(p) => p
    None => return Err("\{path}: its pixels cannot be decoded")
  }
  let bpp = if d[25] == b'\x06' { 4 } else { 3 }
  let rows = Array::makei(h, fn(y) {
    Bytes::from_fixedarray(FixedArray::makei(w * bpp, fn(i) {
      rgba[(y * w + i / bpp) * 4 + i % bpp]
    }))
  })
  Ok({ w, h, bpp, rows })
}
