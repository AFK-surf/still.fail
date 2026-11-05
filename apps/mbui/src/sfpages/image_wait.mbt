// A message's waiting picture: a smooth field of colours derived from the whole image's ThumbHash. Four broad
// regions contribute instead of each feature in the hash being blown up into a stripe. Pixels are averaged and
// interpolated premultiplied by alpha, so a transparent image keeps its clear parts without dark fringes.

///|
fn image_wait_colours(hash : String) -> String? {
  if hash == "" {
    return None
  }
  // The field is content in unit coordinates. Layout can stretch that field
  // into any box without regenerating it or reading a previous frame's size.
  let (pw, ph) = (32, 32)
  let key = "mem:wait-picture/\{hash}/field"
  if @ui.has_image(key) {
    return Some(key)
  }
  guard @pixels.thumbhash(@codec.from_base64(hash)) is Some((sw, sh, source)) else { return None }
  let sums = FixedArray::make(16, 0.0)
  let counts = FixedArray::make(4, 0.0)
  for y in 0..<sh {
    for x in 0..<sw {
      let q = (if x * 2 < sw { 0 } else { 1 }) + (if y * 2 < sh { 0 } else { 2 })
      let i = (y * sw + x) * 4
      let a = source[i + 3].to_int().to_double() / 255.0
      counts[q] = counts[q] + 1.0
      for c in 0..<3 {
        sums[q * 4 + c] = sums[q * 4 + c] + source[i + c].to_int().to_double() * a
      }
      sums[q * 4 + 3] = sums[q * 4 + 3] + source[i + 3].to_int().to_double()
    }
  }
  for q in 0..<4 {
    if counts[q] == 0.0 { return None }
    for c in 0..<4 { sums[q * 4 + c] = sums[q * 4 + c] / counts[q] }
  }
  let rgba = FixedArray::make(pw * ph * 4, b'\x00')
  for y in 0..<ph {
    let v = y.to_double() / (ph - 1).to_double()
    for x in 0..<pw {
      let u = x.to_double() / (pw - 1).to_double()
      let at = (y * pw + x) * 4
      let sample = fn(c : Int) {
        let top = sums[c] * (1.0 - u) + sums[4 + c] * u
        let bottom = sums[8 + c] * (1.0 - u) + sums[12 + c] * u
        top * (1.0 - v) + bottom * v
      }
      let a = sample(3)
      for c in 0..<3 {
        let value = if a <= 0.0 { 0.0 } else { sample(c) * 255.0 / a }
        rgba[at + c] = (if value > 255.0 { 255.0 } else if value < 0.0 { 0.0 } else { value }).round().to_int().to_byte()
      }
      rgba[at + 3] = a.round().to_int().to_byte()
    }
  }
  @ui.add_image(key, @pixels.png(pw, ph, rgba))
  Some(key)
}
