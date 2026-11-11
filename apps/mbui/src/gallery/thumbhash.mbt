// ThumbHash pictures (mbui's @pixels.thumbhash: a photo's look in some 25 bytes) made once each and kept as images,
// shown while the photo itself comes.

///|
let hashed : Map[String, Bool] = Map([])

///|
/// Every Tester starts as the app does (mbui's on_reset): the pictures made here gone with its images.
fn init {
  @ui.on_reset(fn() {
    hashed.clear()
  })
}

///|
/// The image key of a hash's picture (base64), made the first time; with a `ground` (0xRRGGBBAA, none if clear) held
/// off `under` (what it lies on) by it (held_off).
pub fn thumbhash_image(hash : String, ground? : Int64 = 0L, under? : Int64 = 0L) -> String? {
  if hash == "" {
    return None
  }
  let key = "mem:thumbhash/" + hash + (if (ground & 0xFFL) == 0L { "" } else { "/\{ground}/\{under}" })
  let ok = match hashed.get(key) {
    Some(ok) => ok
    None => {
      let ok = match @pixels.thumbhash(@codec.from_base64(hash)) {
        Some((w, h, rgba)) => {
          held_off(rgba, ground, under)
          @ui.add_image(key, @pixels.png(w, h, rgba))
          true
        }
        None => false
      }
      hashed[key] = ok
      ok
    }
  }
  if ok {
    Some(key)
  } else {
    None
  }
}

///|
/// The picture `rgba` (unpremultiplied) held off `under` (0xRRGGBBAA: the ground it lies on) in place, for one
/// standing in for a picture still coming: its own colours as they are, and no channel of them nearer `under` than
/// `ground` (0xRRGGBBAA, translucent: the theme's neutral) over it comes to, on the ground's side. So a photograph's
/// likeness is the likeness itself (the user, 2026-11-11: the blurred picture a message has, not one ground for
/// all), and where its colours are the page's (a light screenshot's all over: 246,242,240 on 245,243,239; a white
/// margin) the neutral ground shows in their place, as for a picture with no ThumbHash. One-sided, each channel: white
/// on a light page is lighter than the page by less than the ground is darker, so anything between the two (the ground
/// laid over all of it, as this was at first) meets the page's colour on its way. What is clear of the picture is the
/// ground itself, translucent as it is.
pub fn held_off(rgba : FixedArray[Byte], ground : Int64, under : Int64) -> Unit {
  let ga = (ground & 0xFFL).to_double() / 255.0
  if ga <= 0.0 {
    return
  }
  let of = fn(colour : Int64, c : Int) { ((colour >> (24 - 8 * c)) & 0xFFL).to_double() }
  let gc = [of(ground, 0), of(ground, 1), of(ground, 2)]
  let uc = [of(under, 0), of(under, 1), of(under, 2)]
  // (the ground over what it lies on: what a picture with no likeness waits on)
  let plain = [0.0, 0.0, 0.0]
  for c in 0..<3 {
    plain[c] = gc[c] * ga + uc[c] * (1.0 - ga)
  }
  for i = 0; i + 3 < rgba.length(); i = i + 4 {
    let a = rgba[i + 3].to_int().to_double() / 255.0
    let out = a + ga * (1.0 - a)
    for c in 0..<3 {
      let own = rgba[i + c].to_int().to_double()
      let kept = if plain[c] <= uc[c] {
        if own < plain[c] { own } else { plain[c] }
      } else if own > plain[c] {
        own
      } else {
        plain[c]
      }
      let v = (kept * a + gc[c] * ga * (1.0 - a)) / out
      rgba[i + c] = (if v > 255.0 { 255.0 } else { v }).round().to_int().to_byte()
    }
    rgba[i + 3] = (out * 255.0).round().to_int().to_byte()
  }
}
