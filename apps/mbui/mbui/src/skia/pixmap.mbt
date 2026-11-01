// tiny-skia's pixmaps and masks (src/pixmap.rs, src/mask.rs): premultiplied RGBA bytes, rows from the top; a mask
// is a byte a pixel.

///|
pub(all) struct Pixmap {
  data : FixedArray[Byte]
  width : Int
  height : Int
}

///|
pub fn Pixmap::new(width : Int, height : Int) -> Pixmap? {
  if width <= 0 || height <= 0 || width.to_int64() * 4L > 2147483647L {
    return None
  }
  let len = width.to_int64() * height.to_int64() * 4L
  if len > 2147483647L {
    return None
  }
  Some({ data: FixedArray::make(len.to_int(), b'\x00'), width, height })
}

///|
/// A pixmap of `data` (premultiplied RGBA, width × height × 4 bytes).
pub fn Pixmap::from_data(data : FixedArray[Byte], width : Int, height : Int) -> Pixmap? {
  if width <= 0 || height <= 0 || data.length() != width * height * 4 {
    None
  } else {
    Some({ data, width, height })
  }
}

///|
pub fn Pixmap::size(self : Pixmap) -> IntSize {
  { width: self.width, height: self.height }
}

///|
pub fn Pixmap::fill(self : Pixmap, color : Color) -> Unit {
  let c = color.premultiply().to_color_u8()
  let n = self.width * self.height
  for i in 0..<n {
    self.data[i * 4] = c.r.to_byte()
    self.data[i * 4 + 1] = c.g.to_byte()
    self.data[i * 4 + 2] = c.b.to_byte()
    self.data[i * 4 + 3] = c.a.to_byte()
  }
}

///|
pub fn Pixmap::pixel(self : Pixmap, x : Int, y : Int) -> PremultipliedColorU8? {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return None
  }
  let i = (y * self.width + x) * 4
  Some({
    r: self.data[i].to_int(),
    g: self.data[i + 1].to_int(),
    b: self.data[i + 2].to_int(),
    a: self.data[i + 3].to_int(),
  })
}

///|
pub fn Pixmap::copy(self : Pixmap) -> Pixmap {
  let data = FixedArray::make(self.data.length(), b'\x00')
  self.data.blit_to(data, len=self.data.length())
  { data, width: self.width, height: self.height }
}

///|
/// The pixmap's pixels with their colour divided back out of alpha (take_demultiplied).
pub fn Pixmap::demultiplied(self : Pixmap) -> FixedArray[Byte] {
  let out = FixedArray::make(self.data.length(), b'\x00')
  for i in 0..<(self.width * self.height) {
    let p : PremultipliedColorU8 = {
      r: self.data[i * 4].to_int(),
      g: self.data[i * 4 + 1].to_int(),
      b: self.data[i * 4 + 2].to_int(),
      a: self.data[i * 4 + 3].to_int(),
    }
    let c = p.demultiply()
    out[i * 4] = c.r.to_byte()
    out[i * 4 + 1] = c.g.to_byte()
    out[i * 4 + 2] = c.b.to_byte()
    out[i * 4 + 3] = c.a.to_byte()
  }
  out
}

///|
pub fn Pixmap::clone_rect(self : Pixmap, rect : IntRect) -> Pixmap? {
  let rect = match IntRect::from_xywh(0, 0, self.width, self.height).unwrap().intersect(rect) {
    Some(r) => r
    None => return None
  }
  let new = match Pixmap::new(rect.width, rect.height) {
    Some(p) => p
    None => return None
  }
  for y in 0..<rect.height {
    for x in 0..<rect.width {
      let o = ((y + rect.y) * self.width + x + rect.x) * 4
      let n = (y * rect.width + x) * 4
      for k in 0..<4 {
        new.data[n + k] = self.data[o + k]
      }
    }
  }
  Some(new)
}

///|
fn Pixmap::as_subpixmap(self : Pixmap) -> SubPixmap {
  { data: self.data, offset: 0, width: self.width, height: self.height, real_width: self.width }
}

///|
fn Pixmap::subpixmap(self : Pixmap, rect : IntRect) -> SubPixmap? {
  match IntRect::from_xywh(0, 0, self.width, self.height).unwrap().intersect(rect) {
    Some(r) =>
      Some({
        data: self.data,
        offset: r.y * self.width + r.x,
        width: r.width,
        height: r.height,
        real_width: self.width,
      })
    None => None
  }
}

///|
/// A part of a pixmap or mask drawn into (SubPixmapMut): `offset` and `real_width` in pixels (4 bytes each in a
/// pixmap, 1 in a mask).
priv struct SubPixmap {
  data : FixedArray[Byte]
  offset : Int
  width : Int
  height : Int
  real_width : Int
}

///|
fn SubPixmap::offset_at(self : SubPixmap, dx : Int, dy : Int) -> Int {
  self.offset + self.real_width * dy + dx
}

///|
pub(all) enum MaskType {
  Alpha
  Luminance
} derive(Eq, Show, Debug)

///|
pub(all) struct Mask {
  data : FixedArray[Byte]
  width : Int
  height : Int
}

///|
pub fn Mask::new(width : Int, height : Int) -> Mask? {
  if width <= 0 || height <= 0 || width.to_int64() * height.to_int64() > 2147483647L {
    None
  } else {
    Some({ data: FixedArray::make(width * height, b'\x00'), width, height })
  }
}

///|
pub fn Mask::from_pixmap(pixmap : Pixmap, mask_type : MaskType) -> Mask {
  let n = pixmap.width * pixmap.height
  let data = FixedArray::make(n, b'\x00')
  match mask_type {
    Alpha => for i in 0..<n { data[i] = pixmap.data[i * 4 + 3] }
    Luminance =>
      for i in 0..<n {
        let pa = pixmap.data[i * 4 + 3].to_int()
        let mut r = fi(pixmap.data[i * 4].to_int()) / 255.0
        let mut g = fi(pixmap.data[i * 4 + 1].to_int()) / 255.0
        let mut b = fi(pixmap.data[i * 4 + 2].to_int()) / 255.0
        let a = fi(pa) / 255.0
        if pa != 0 {
          r = r / a
          g = g / a
          b = b / a
        }
        let luma = r * 0.2126 + g * 0.7152 + b * 0.0722
        let v = luma * a * 255.0
        let v : Float = if v < 0.0 { 0.0 } else if v > 255.0 { 255.0 } else { v }
        data[i] = f2u8(v.ceil()).to_byte()
      }
  }
  { data, width: pixmap.width, height: pixmap.height }
}

///|
fn Mask::as_subpixmap(self : Mask) -> SubPixmap {
  { data: self.data, offset: 0, width: self.width, height: self.height, real_width: self.width }
}

///|
fn Mask::subpixmap(self : Mask, rect : IntRect) -> SubPixmap? {
  match IntRect::from_xywh(0, 0, self.width, self.height).unwrap().intersect(rect) {
    Some(r) =>
      Some({ data: self.data, offset: r.y * self.width + r.x, width: r.width, height: r.height, real_width: self.width })
    None => None
  }
}

///|
fn Mask::mask_ctx(self : Mask) -> MaskCtx {
  { data: self.data, offset: 0, real_width: self.width }
}

///|
fn Mask::submask_ctx(self : Mask, rect : IntRect) -> MaskCtx? {
  match IntRect::from_xywh(0, 0, self.width, self.height).unwrap().intersect(rect) {
    Some(r) => Some({ data: self.data, offset: r.y * self.width + r.x, real_width: self.width })
    None => None
  }
}

///|
/// Fills `path` into the mask, opaque where it covers.
pub fn Mask::fill_path(self : Mask, path : Path, fill_rule : FillRule, anti_alias : Bool, transform : Transform) -> Unit {
  if !transform.is_identity() {
    match path.transform(transform) {
      Some(p) => self.fill_path(p, fill_rule, anti_alias, Transform::identity())
      None => ()
    }
    return
  }
  let b = path.bounds
  if is_nearly_zero(b.width()) || is_nearly_zero(b.height()) {
    return
  }
  if is_too_big_for_math(path) {
    return
  }
  match draw_tiles(self.width, self.height) {
    Some(tiles) => {
      let mut path = path
      for tile in tiles {
        path = match path.transform(Transform::from_translate(-fi(tile.x), -fi(tile.y))) {
          Some(p) => p
          None => return
        }
        let clip_rect = tile.size().to_screen_int_rect(0, 0)
        match self.subpixmap(tile.to_int_rect()) {
          Some(sub) => {
            let blitter = RasterPipelineBlitter::new_mask(sub)
            if anti_alias {
              fill_path_aa(path, fill_rule, clip_rect, blitter)
            } else {
              fill_path_nonaa(path, fill_rule, clip_rect, blitter)
            }
          }
          None => ()
        }
        path = match path.transform(Transform::from_translate(fi(tile.x), fi(tile.y))) {
          Some(p) => p
          None => return
        }
      }
    }
    None => {
      let clip_rect = self.size().to_screen_int_rect(0, 0)
      let blitter = RasterPipelineBlitter::new_mask(self.as_subpixmap())
      if anti_alias {
        fill_path_aa(path, fill_rule, clip_rect, blitter)
      } else {
        fill_path_nonaa(path, fill_rule, clip_rect, blitter)
      }
    }
  }
}

///|
pub fn Mask::size(self : Mask) -> IntSize {
  { width: self.width, height: self.height }
}

///|
/// The mask times `path` filled (Mask::intersect_path).
pub fn Mask::intersect_path(self : Mask, path : Path, fill_rule : FillRule, anti_alias : Bool, transform : Transform) -> Unit {
  let submask = Mask::new(self.width, self.height).unwrap()
  submask.fill_path(path, fill_rule, anti_alias, transform)
  for i in 0..<self.data.length() {
    self.data[i] = premultiply_u8(self.data[i].to_int(), submask.data[i].to_int()).to_byte()
  }
}

///|
pub fn Mask::invert(self : Mask) -> Unit {
  for i in 0..<self.data.length() {
    self.data[i] = (255 - self.data[i].to_int()).to_byte()
  }
}

///|
pub fn Mask::clear(self : Mask) -> Unit {
  for i in 0..<self.data.length() {
    self.data[i] = b'\x00'
  }
}
