// ThumbHash (evanw/thumbhash, as still.fail's web/src/thumbhash.ts): a
// photo's look in some 25 bytes, drawn as a small blurred picture while the
// photo itself comes.

///|
fn b64_value(ch : Int) -> Int {
  if ch >= 65 && ch <= 90 {
    ch - 65
  } else if ch >= 97 && ch <= 122 {
    ch - 71
  } else if ch >= 48 && ch <= 57 {
    ch + 4
  } else if ch == 43 || ch == 45 {
    62
  } else if ch == 47 || ch == 95 {
    63
  } else {
    -1
  }
}

///|
/// Base64 (standard or URL-safe, padded or not).
fn b64_decode(s : String) -> Array[Int] {
  let out = []
  let mut acc = 0
  let mut bits = 0
  for ch in s {
    let v = b64_value(ch.to_int())
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      out.push((acc >> bits) & 0xFF)
    }
  }
  out
}

///|
/// The picture a hash stands for: its width, height and RGBA (straight).
fn thumbhash_rgba(hash : Array[Int]) -> (Int, Int, FixedArray[Byte])? {
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
        fx[cx] = @math.cos(pi / w.to_double() * (x.to_double() + 0.5) * cx.to_double())
      }
      for cy in 0..<nfy {
        fy[cy] = @math.cos(pi / h.to_double() * (y.to_double() + 0.5) * cy.to_double())
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
let hashed : Map[String, Bool] = {}

///|
/// The image key of a hash's picture (base64), made the first time.
pub fn thumbhash_image(hash : String) -> String? {
  if hash == "" {
    return None
  }
  let key = "mem:thumbhash/" + hash
  let ok = match hashed.get(key) {
    Some(ok) => ok
    None => {
      let ok = match thumbhash_rgba(b64_decode(hash)) {
        Some((w, h, rgba)) => {
          @ui.add_image(key, @sf.png(w, h, rgba))
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
