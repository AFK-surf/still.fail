///|
test "thumbhash decodes as the reference does" {
  // the size, the first two pixels and the one at (11, 16), as the npm
  // package thumbhash's thumbHashToRGBA gives them for this hash
  let hash = b64_decode("1QcSHQRnh493V4dIh4eXh1h4kJUI")
  guard thumbhash_rgba(hash) is Some((w, h, rgba)) else { fail("no picture") }
  let first = []
  for i in 0..<8 {
    first.push(rgba[i].to_int())
  }
  let mid = []
  for i in 0..<4 {
    mid.push(rgba[(w * 16 + 11) * 4 + i].to_int())
  }
  inspect(
    "\{w}x\{h} \{first} \{mid}",
    content="23x32 [64, 77, 113, 255, 66, 79, 114, 255] [140, 109, 88, 255]",
  )
}
