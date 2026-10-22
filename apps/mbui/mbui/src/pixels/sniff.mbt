// What a picture's bytes say of it before it is decoded: whether they are a PNG, and the width and height their
// header gives (PNG, GIF, WebP, JPEG).

///|
/// The width and height a picture's bytes say (PNG, JPEG, GIF, WebP), or None.
pub fn image_size(b : Bytes) -> (Int, Int)? {
  let n = b.length()
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let le16 = fn(i : Int) -> Int { u8(i) | (u8(i + 1) << 8) }
  let be32 = fn(i : Int) -> Int { (be16(i) << 16) | be16(i + 2) }
  if n >= 24 && u8(0) == 0x89 && u8(1) == 0x50 && u8(2) == 0x4E && u8(3) == 0x47 {
    return Some((be32(16), be32(20)))
  }
  if n >= 10 && u8(0) == 0x47 && u8(1) == 0x49 && u8(2) == 0x46 {
    return Some((le16(6), le16(8)))
  }
  if n >= 30 && u8(0) == 0x52 && u8(1) == 0x49 && u8(8) == 0x57 && u8(9) == 0x45 {
    // RIFF….WEBP: VP8 , VP8L, VP8X
    let kind = u8(15)
    if kind == 0x20 {
      return Some((le16(26) & 0x3FFF, le16(28) & 0x3FFF))
    } else if kind == 0x4C {
      let bits = u8(21) | (u8(22) << 8) | (u8(23) << 16) | (u8(24) << 24)
      return Some(((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1))
    } else if kind == 0x58 {
      return Some(
        (
          (u8(24) | (u8(25) << 8) | (u8(26) << 16)) + 1,
          (u8(27) | (u8(28) << 8) | (u8(29) << 16)) + 1,
        ),
      )
    }
    return None
  }
  if n >= 4 && u8(0) == 0xFF && u8(1) == 0xD8 {
    let mut i = 2
    while i + 9 < n {
      if u8(i) != 0xFF {
        i += 1
        continue
      }
      let m = u8(i + 1)
      if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) || m == 0xFF {
        i += if m == 0xFF { 1 } else { 2 }
        continue
      }
      // a start of frame (not DHT C4, JPG C8, DAC CC)
      if m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC {
        return Some((be16(i + 7), be16(i + 5)))
      }
      i += 2 + be16(i + 2)
    }
  }
  None
}

///|
/// Whether `b` starts as a PNG does (its eight bytes' signature).
pub fn is_png(b : Bytes) -> Bool {
  let sig = [137, 80, 78, 71, 13, 10, 26, 10]
  if b.length() < sig.length() {
    return false
  }
  for i, v in sig {
    if b[i].to_int() != v {
      return false
    }
  }
  true
}
