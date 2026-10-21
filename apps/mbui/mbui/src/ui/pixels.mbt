// An image's pixels, to make another picture from (an icon drawn from a picture, say): decoded by the host as Ctx::image
// has it (by its source, at most so many pixels on its long side) and read back from it once, kept while the run lasts.
// Not on a host that cannot read its images back (false from @hostapi.image_pixels): failed.

///|
/// What an image's pixels are so far.
pub(all) enum ImagePixels {
  /// being decoded
  PixelsComing
  /// read: its width and height and its pixels (RGBA, premultiplied, rows from the top)
  PixelsRead(Int, Int, FixedArray[Byte])
  /// it did not decode, or cannot be read back here
  PixelsFailed
} derive(Eq)

///|
/// Read back, by the long side asked for and the source ("BUCKET SRC").
let pixels_read : Map[String, ImagePixels] = {}

///|
/// The pixels of the image at `src` (a path, an http(s) URL, a key given to image_bytes) decoded to at most `px` on its
/// long side (a larger original made smaller; a smaller one as it is): coming until it is decoded, a frame asked for
/// as it is.
pub fn Ctx::image_pixels(self : Ctx, src : String, px : Int) -> ImagePixels {
  let want = bucket(px.to_double())
  let key = "\{want} \{src}"
  match pixels_read.get(key) {
    Some(p) => return p
    None => ()
  }
  let p = match self.image_for(src, px.to_double()) {
    Some(e) if e.state == 1 && e.px >= want => {
      let w = e.w.to_int()
      let h = e.h.to_int()
      let out = FixedArray::make(w * h * 4, b'\x00')
      if h_image_pixels(e.id, out) {
        PixelsRead(w, h, out)
      } else {
        PixelsFailed
      }
    }
    _ =>
      match image_cache.get(src) {
        Some(list) if list.iter().any(fn(e) { e.state == -1 && e.px >= want }) => PixelsFailed
        _ => PixelsComing
      }
  }
  if p != PixelsComing {
    pixels_read[key] = p
  }
  p
}
