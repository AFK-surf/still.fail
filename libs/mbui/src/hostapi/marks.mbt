// Marks drawn onto an image at its own size, as a PNG (still.fail's Android app, chat/screens/ImageMarks.kt render,
// drawMarks, drawPins): boxes, arrows and lines drawn by hand as round-capped strokes, words with an edge of their
// halo colour, and the numbered marks' pins (a rounded tag of the halo, the mark's colour inside, its number). `marks`
// is JSON: {"w", "h": the size the marks' points are in (the picture as shown), "marks": [{"kind": "box" | "arrow" |
// "pen" | "words", "color", "halo": 0xRRGGBBAA as numbers, "w": the line's width (a text's size), "pts": [x, y, …]
// (a box's two corners, an arrow's tail and point, a line's points, words' top left), "text", "n": its pin's number,
// 0 none}]}. Drawn off the app's thread (Android's Canvas, Core Graphics); `made` once done. None where the host
// draws none (Windows, the web).

///|
/// Marks being drawn onto an image.
pub struct MarkedImage {
  priv id : Int
}

///|
/// Its id, as the host's event names it once drawn (set_outside: kind 5).
pub fn MarkedImage::id(self : MarkedImage) -> Int {
  self.id
}

///|
/// `image` (its bytes, any format the system decodes) with `marks` drawn on it: None where the host cannot.
pub fn draw_marks(image : Bytes, marks : String) -> MarkedImage? {
  match mk_start(image, marks) {
    0 => None
    id => Some({ id, })
  }
}

///|
/// The PNG once drawn (Some(empty): it could not be: the image not decoded, too big), None while it is drawn; taken
/// once.
pub fn MarkedImage::made(self : MarkedImage) -> Bytes? {
  match mk_state(self.id) {
    0 => None
    1 => Some(mk_png(self.id))
    _ => {
      mk_png(self.id) |> ignore
      Some(b"")
    }
  }
}

///|
/// Whether it is drawn (or could not be), its PNG not taken (MarkedImage::made takes it).
pub fn MarkedImage::drawn(self : MarkedImage) -> Bool {
  mk_state(self.id) != 0
}
