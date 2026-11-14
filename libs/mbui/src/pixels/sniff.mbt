// What a picture's bytes say of it before it is decoded: whether they are a PNG, and the width and height it is shown
// at as their header gives it (PNG, GIF, WebP, JPEG, HEIC/HEIF, AVIF: turned as its EXIF note or irot says, as hosts
// decode it).

///|
/// The width and height a picture's bytes say it is shown at (PNG, JPEG, GIF, WebP, HEIC/HEIF, AVIF), or None: a
/// JPEG's or HEIF's frame, its sides swapped where its EXIF orientation (5–8) or `irot` (1, 3) turns it a quarter.
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
  if n >= 16 && box_is(b, 4, b"ftyp") {
    return heif_size(b)
  }
  None
}

///|
fn box_is(b : Bytes, at : Int, tag : Bytes) -> Bool {
  at >= 0 &&
  at + 4 <= b.length() &&
  b[at] == tag[0] &&
  b[at + 1] == tag[1] &&
  b[at + 2] == tag[2] &&
  b[at + 3] == tag[3]
}

///|
fn next_box(b : Bytes, at : Int, end : Int) -> (Int, Int, Int)? {
  if at < 0 || at + 8 > end || end > b.length() {
    return None
  }
  let u8 = fn(i : Int) -> Int { b[i].to_int() }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let be32 = fn(i : Int) -> Int {
    if be16(i) >= 0x8000 {
      -1
    } else {
      (be16(i) << 16) | be16(i + 2)
    }
  }
  let sz = be32(at)
  if sz == 1 {
    if at + 16 > end || be32(at + 8) != 0 {
      return None
    }
    let big = be32(at + 12)
    if big < 16 || at + big > end {
      return None
    }
    Some((at + 4, at + 16, at + big))
  } else if sz == 0 {
    Some((at + 4, at + 8, end))
  } else if sz < 8 || at + sz > end {
    None
  } else {
    Some((at + 4, at + 8, at + sz))
  }
}

///|
fn heif_brand(b : Bytes, at : Int) -> Bool {
  for brand in [b"heic", b"heix", b"heim", b"heis", b"hevc", b"hevx", b"mif1", b"msf1", b"avif", b"avis", b"miaf"] {
    if box_is(b, at, brand) {
      return true
    }
  }
  false
}

///|
/// The width and height an ISOBMFF still image (`ftyp` with a HEIF/AVIF brand, then `meta`) says its primary item is
/// shown at (`pitm` → `iprp` `ipco`/`ipma`: `ispe`, turned a quarter where `irot` is 90° or 270°).
fn heif_size(b : Bytes) -> (Int, Int)? {
  let n = b.length()
  let u8 = fn(i : Int) -> Int { b[i].to_int() }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let be32 = fn(i : Int) -> Int {
    if be16(i) >= 0x8000 {
      -1
    } else {
      (be16(i) << 16) | be16(i + 2)
    }
  }
  guard next_box(b, 0, n) is Some((ft_tag, ft_body, ft_end)) &&
    box_is(b, ft_tag, b"ftyp") &&
    ft_body + 8 <= ft_end else {
    return None
  }
  let mut branded = heif_brand(b, ft_body)
  let mut p = ft_body + 8
  while !branded && p + 4 <= ft_end {
    branded = heif_brand(b, p)
    p += 4
  }
  if !branded {
    return None
  }
  let mut top = ft_end
  while next_box(b, top, n) is Some((tag, body, bend)) {
    top = bend
    if !box_is(b, tag, b"meta") || body + 4 > bend {
      continue
    }
    let mut primary = -1
    let props : Array[(Int, Int, Int)] = []
    let assocs : Array[(Int, Array[Int])] = []
    let mut c = body + 4
    while next_box(b, c, bend) is Some((ctag, cbody, cend)) {
      c = cend
      if box_is(b, ctag, b"pitm") && cbody + 4 <= cend {
        let ver = u8(cbody)
        if ver == 0 && cbody + 6 <= cend {
          primary = be16(cbody + 4)
        } else if ver >= 1 && cbody + 8 <= cend {
          primary = be32(cbody + 4)
        }
      } else if box_is(b, ctag, b"iprp") {
        let mut ip = cbody
        while next_box(b, ip, cend) is Some((ptag, pbody, pend)) {
          ip = pend
          if box_is(b, ptag, b"ipco") {
            let mut kp = pbody
            while next_box(b, kp, pend) is Some((ktag, kbody, kend)) {
              kp = kend
              if box_is(b, ktag, b"ispe") && kbody + 12 <= kend {
                props.push((be32(kbody + 4), be32(kbody + 8), -1))
              } else if box_is(b, ktag, b"irot") && kbody + 1 <= kend {
                props.push((0, 0, u8(kbody) & 3))
              } else {
                props.push((0, 0, -1))
              }
            }
          } else if box_is(b, ptag, b"ipma") && pbody + 8 <= pend {
            let ver = u8(pbody)
            let wide = (u8(pbody + 3) & 1) != 0
            let count = be32(pbody + 4)
            let mut q = pbody + 8
            if count > 0 {
              for _ in 0..<count {
                let id_len = if ver < 1 { 2 } else { 4 }
                if q + id_len + 1 > pend {
                  break
                }
                let item_id = if ver < 1 { be16(q) } else { be32(q) }
                let m = u8(q + id_len)
                q += id_len + 1
                let step = if wide { 2 } else { 1 }
                if q + m * step > pend {
                  break
                }
                let idxs : Array[Int] = []
                for _ in 0..<m {
                  let idx = if wide { be16(q) & 0x7FFF } else { u8(q) & 0x7F }
                  idxs.push(idx)
                  q += step
                }
                assocs.push((item_id, idxs))
              }
            }
          }
        }
      }
    }
    let mut w = 0
    let mut h = 0
    let mut rot = 0
    let mut matched = false
    if primary >= 0 {
      for entry in assocs {
        if entry.0 == primary {
          matched = true
          for idx in entry.1 {
            if idx >= 1 && idx <= props.length() {
              let (pw, ph, prot) = props[idx - 1]
              if pw > 0 && ph > 0 {
                w = pw
                h = ph
              }
              if prot >= 0 {
                rot = prot
              }
            }
          }
        }
      }
    }
    if !matched {
      for prop in props {
        let (pw, ph, prot) = prop
        if w == 0 && pw > 0 && ph > 0 {
          w = pw
          h = ph
        }
        if prot >= 0 {
          rot = prot
        }
      }
    }
    return if w > 0 && h > 0 {
      Some(if (rot & 1) == 1 { (h, w) } else { (w, h) })
    } else {
      None
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
