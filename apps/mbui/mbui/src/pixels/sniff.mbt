// What a picture's bytes say of it before it is decoded: whether they are a PNG, and the width and height it is shown
// at as their header gives it (PNG, GIF, WebP, JPEG: a JPEG turned as its EXIF note says, as hosts decode it).

///|
/// The width and height a picture's bytes say it is shown at (PNG, JPEG, GIF, WebP), or None: a JPEG's frame, its sides
/// swapped where its EXIF orientation turns it a quarter (5–8: a phone's photo kept on its side).
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
    let mut turned = false
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
      // an EXIF note (APP1): which way up it is shown
      if m == 0xE1 {
        match exif_turned(b, i + 4, i + 2 + be16(i + 2)) {
          Some(t) => turned = t
          None => ()
        }
      }
      // a start of frame (not DHT C4, JPG C8, DAC CC)
      if m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC {
        let (w, h) = (be16(i + 7), be16(i + 5))
        return Some(if turned { (h, w) } else { (w, h) })
      }
      i += 2 + be16(i + 2)
    }
  }
  None
}

///|
/// Whether the APP1 note in `b` from `at` to `end` (`Exif\0\0`, then a TIFF) says its picture is shown turned a quarter
/// (orientation 5–8); None for one that is not EXIF or says no orientation.
fn exif_turned(b : Bytes, at : Int, end : Int) -> Bool? {
  let end = if end < b.length() { end } else { b.length() }
  let u8 = fn(i : Int) -> Int { if i >= 0 && i < end { b[i].to_int() } else { -1 } }
  let exif = [0x45, 0x78, 0x69, 0x66, 0, 0]
  for k, v in exif {
    if u8(at + k) != v {
      return None
    }
  }
  // the TIFF: its byte order, 42, where its first directory is
  let t = at + 6
  let le = if u8(t) == 0x49 && u8(t + 1) == 0x49 {
    true
  } else if u8(t) == 0x4D && u8(t + 1) == 0x4D {
    false
  } else {
    return None
  }
  let u16 = fn(i : Int) -> Int {
    let (x, y) = (u8(t + i), u8(t + i + 1))
    if x < 0 || y < 0 {
      -1
    } else if le {
      x | (y << 8)
    } else {
      (x << 8) | y
    }
  }
  let u32 = fn(i : Int) -> Int {
    let (lo, hi) = if le { (u16(i), u16(i + 2)) } else { (u16(i + 2), u16(i)) }
    if lo < 0 || hi < 0 || hi >= 0x8000 {
      -1
    } else {
      (hi << 16) | lo
    }
  }
  if u16(2) != 42 {
    return None
  }
  let ifd = u32(4)
  let count = if ifd < 0 { -1 } else { u16(ifd) }
  if count < 0 {
    return None
  }
  for k in 0..<count {
    let e = ifd + 2 + k * 12
    if u16(e) == 0x0112 {
      let o = u16(e + 8)
      return if o < 0 { None } else { Some(o >= 5 && o <= 8) }
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
