// A remote screen's pointer, as still.fail's Android viewer draws it over the frame (app/remote/ScreenViewer.kt
// Pointer): an arrow, white with a dark edge (1.2 wide), its tip where it points, at its own size however the frame is
// zoomed. Its image keeps a unit round the outline for the edge's outer half: the tip is `pointer_tip` in from its top
// left.

///|
/// The arrow's outline (dp from its tip), and the square it is drawn in.
let pointer_outline : Array[Double] = [
  0.0, 0.0, 0.0, 16.0, 4.0, 12.5, 7.0, 18.5, 9.5, 17.5, 6.5, 11.5, 11.5, 11.5,
].map(fn(v) { v + pointer_tip })

///|
/// Where the tip is in the image, from its top and its left.
pub let pointer_tip : Double = 1.0

///|
pub let pointer_size : Double = 20.0

///|
/// The edge's colour (ScreenViewer.kt Pointer: 0xFF1B1C1F).
let pointer_edge : Int64 = 0x1B1C1FFFL

///|
/// The pointer's image (its key for Ctx::image), `pointer_size` square, its tip `pointer_tip` in from the top left,
/// rasterised at the screen's pixels once.
pub fn pointer_image(c : @ui.Ctx) -> String {
  let px = px_of(c, pointer_size)
  let key = "mem:sf/pointer/\{px}"
  if !made.contains(key) {
    made[key] = true
    // the edge drawn half inside and half outside the outline, over the white inside it
    let inside = Art::new(pointer_size)
    inside.fills.push([pointer_outline])
    let edge = Art::new(pointer_size)
    edge.stroke(pointer_outline, 1.2, true)
    let fill = inside.cover(px)
    let line = edge.cover(px)
    let rgba = FixedArray::make(px * px * 4, b'\x00')
    let er = ((pointer_edge >> 24) & 0xFFL).to_double()
    let eg = ((pointer_edge >> 16) & 0xFFL).to_double()
    let eb = ((pointer_edge >> 8) & 0xFFL).to_double()
    for i in 0..<(px * px) {
      let a_line = line[i]
      let a_fill = fill[i]
      // the edge over the white: straight alpha
      let a = a_line + a_fill * (1.0 - a_line)
      if a > 0.0 {
        let mix = fn(v : Double) {
          let c = (v * a_line + 255.0 * a_fill * (1.0 - a_line)) / a
          (c + 0.5).to_int().to_byte()
        }
        rgba[i * 4] = mix(er)
        rgba[i * 4 + 1] = mix(eg)
        rgba[i * 4 + 2] = mix(eb)
        rgba[i * 4 + 3] = (a * 255.0 + 0.5).to_int().to_byte()
      }
    }
    @ui.add_image(key, png(px, px, rgba))
  }
  key
}
