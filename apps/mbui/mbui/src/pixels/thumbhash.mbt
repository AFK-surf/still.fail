// ThumbHash (evanw/thumbhash, as still.fail's web/src/thumbhash.ts has it): a photo's look in some 25 bytes, drawn
// back as a small blurred picture to show while the photo itself comes.

///|
/// The picture a ThumbHash's bytes stand for (its proportions, about 32 on its longer side): its width, height and
/// RGBA (straight, rows from the top); None for what is too short to be one.
pub fn thumbhash(bytes : Bytes) -> (Int, Int, FixedArray[Byte])? {
  let hash = Array::makei(bytes.length(), fn(i) { bytes[i].to_int() })
  if hash.length() < 5 {
    return None
  }
  let pi = 3.141592653589793
  let header24 = hash[0] | (hash[1] << 8) | (hash[2] << 16)
  let header16 = hash[3] | (hash[4] << 8)
  let l_dc = (header24 & 63).to_double() / 63.0
  let p_dc = ((header24 >> 6) & 63).to_double() / 31.5 - 1.0
  let q_dc = ((header24 >> 12) & 63).to_double() / 31.5 - 1.0
  let l_scale = ((header24 >> 18) & 31).to_double() / 31.0
  let has_alpha = (header24 >> 23) != 0
  let p_scale = ((header16 >> 3) & 63).to_double() / 63.0
  let q_scale = ((header16 >> 9) & 63).to_double() / 63.0
  let landscape = (header16 >> 15) != 0
  let imax = fn(a : Int, b : Int) { if a > b { a } else { b } }
  let lx = imax(3, if landscape { if has_alpha { 5 } else { 7 } } else { header16 & 7 })
  let ly = imax(3, if landscape { header16 & 7 } else if has_alpha { 5 } else { 7 })
  let at = fn(i : Int) { if i < hash.length() { hash[i] } else { 0 } }
  let a_dc = if has_alpha { (at(5) & 15).to_double() / 15.0 } else { 1.0 }
  let a_scale = (at(5) >> 4).to_double() / 15.0
  let ac_start = if has_alpha { 6 } else { 5 }
  let mut ac_index = 0
  let channel = fn(nx : Int, ny : Int, scale : Double) -> Array[Double] {
    let ac = []
    for cy in 0..<ny {
      let mut cx = if cy > 0 { 0 } else { 1 }
      while cx * ny < nx * (ny - cy) {
        let byte = at(ac_start + (ac_index >> 1))
        let v = (byte >> ((ac_index & 1) << 2)) & 15
        ac_index = ac_index + 1
        ac.push((v.to_double() / 7.5 - 1.0) * scale)
        cx = cx + 1
      }
    }
    ac
  }
  let l_ac = channel(lx, ly, l_scale)
  let p_ac = channel(3, 3, p_scale * 1.25)
  let q_ac = channel(3, 3, q_scale * 1.25)
  let a_ac = if has_alpha { channel(5, 5, a_scale) } else { [] }
  // its proportions, from the header
  let ratio = {
    let rh = at(3)
    let ra = (at(2) & 0x80) != 0
    let rl = (at(4) & 0x80) != 0
    let rx = if rl { if ra { 5 } else { 7 } } else { rh & 7 }
    let ry = if rl { rh & 7 } else if ra { 5 } else { 7 }
    if ry == 0 { 1.0 } else { rx.to_double() / ry.to_double() }
  }
  let w = (if ratio > 1.0 { 32.0 } else { 32.0 * ratio }).round().to_int()
  let h = (if ratio > 1.0 { 32.0 / ratio } else { 32.0 }).round().to_int()
  if w <= 0 || h <= 0 {
    return None
  }
  let rgba = FixedArray::make(w * h * 4, b'\x00')
  let nfx = imax(lx, if has_alpha { 5 } else { 3 })
  let nfy = imax(ly, if has_alpha { 5 } else { 3 })
  let fx = Array::make(nfx, 0.0)
  let fy = Array::make(nfy, 0.0)
  let byte = fn(v : Double) -> Byte {
    let c = 255.0 * (if v > 1.0 { 1.0 } else { v })
    (if c < 0.0 { 0.0 } else { c }).to_int().to_byte()
  }
  for y in 0..<h {
    for x in 0..<w {
      let i = (y * w + x) * 4
      let mut l = l_dc
      let mut p = p_dc
      let mut q = q_dc
      let mut a = a_dc
      for cx in 0..<nfx {
        fx[cx] = @dmath.cos(pi / w.to_double() * (x.to_double() + 0.5) * cx.to_double())
      }
      for cy in 0..<nfy {
        fy[cy] = @dmath.cos(pi / h.to_double() * (y.to_double() + 0.5) * cy.to_double())
      }
      let mut j = 0
      for cy in 0..<ly {
        let fy2 = fy[cy] * 2.0
        let mut cx = if cy > 0 { 0 } else { 1 }
        while cx * ly < lx * (ly - cy) {
          l = l + l_ac[j] * fx[cx] * fy2
          j = j + 1
          cx = cx + 1
        }
      }
      j = 0
      for cy in 0..<3 {
        let fy2 = fy[cy] * 2.0
        let mut cx = if cy > 0 { 0 } else { 1 }
        while cx < 3 - cy {
          let f = fx[cx] * fy2
          p = p + p_ac[j] * f
          q = q + q_ac[j] * f
          j = j + 1
          cx = cx + 1
        }
      }
      if has_alpha {
        j = 0
        for cy in 0..<5 {
          let fy2 = fy[cy] * 2.0
          let mut cx = if cy > 0 { 0 } else { 1 }
          while cx < 5 - cy {
            a = a + a_ac[j] * fx[cx] * fy2
            j = j + 1
            cx = cx + 1
          }
        }
      }
      let b = l - 2.0 / 3.0 * p
      let r = (3.0 * l - b + q) / 2.0
      let g = r - q
      rgba[i] = byte(r)
      rgba[i + 1] = byte(g)
      rgba[i + 2] = byte(b)
      rgba[i + 3] = byte(a)
    }
  }
  Some((w, h, rgba))
}


///|
/// The width over the height of the picture a ThumbHash's bytes stand for, from its header alone (thumbhash.js
/// thumbHashToApproximateAspectRatio); None for what is too short to be one.
pub fn thumbhash_ratio(bytes : Bytes) -> Double? {
  if bytes.length() < 5 {
    return None
  }
  let header = bytes[3].to_int()
  let has_alpha = (bytes[2].to_int() & 0x80) != 0
  let is_landscape = (bytes[4].to_int() & 0x80) != 0
  let lx = if is_landscape { if has_alpha { 5 } else { 7 } } else { header & 7 }
  let ly = if is_landscape { header & 7 } else if has_alpha { 5 } else { 7 }
  if ly == 0 {
    None
  } else {
    Some(lx.to_double() / ly.to_double())
  }
}
