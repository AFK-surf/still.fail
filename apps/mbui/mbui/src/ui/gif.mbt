// GIFs that move: decoded here (not by a host, whose decoders give a still's first frame), each frame as the screen
// shows it then (its canvas after the frames before it, as their disposal leaves it), with how long it stays. An
// image handed over as a GIF of more than one frame (add_image) is shown as its frames in turn, a cycle of their
// lengths (Ctx::cycle: a frame of each length, the same at any frame rate); `still` holds its first.

///|
/// A GIF's frames as shown: each its pixels (RGBA, straight, the canvas's rows from the top) and how long it stays (ms).
pub(all) struct GifFrames {
  w : Int
  h : Int
  frames : Array[FixedArray[Byte]]
  delays : Array[Double]
}

///|
/// How long a frame that says none (or under 20 ms, as browsers do) stays.
let gif_least_ms : Double = 100.0

///|
/// Whether `data` is a GIF (its signature).
pub fn is_gif(data : Bytes) -> Bool {
  data.length() >= 6 &&
  data[0] == b'G' &&
  data[1] == b'I' &&
  data[2] == b'F' &&
  data[3] == b'8' &&
  (data[4] == b'7' || data[4] == b'9') &&
  data[5] == b'a'
}

///|
/// The frames of GIF `data`, or None where it is not one or is cut short before its first frame.
pub fn gif_frames(data : Bytes) -> GifFrames? {
  if !is_gif(data) || data.length() < 13 {
    return None
  }
  let n = data.length()
  let u8 = fn(i : Int) { if i < n { data[i].to_int() } else { 0 } }
  let u16 = fn(i : Int) { u8(i) | (u8(i + 1) << 8) }
  let w = u16(6)
  let h = u16(8)
  if w <= 0 || h <= 0 || w * h > 16_000_000 {
    return None
  }
  let flags = u8(10)
  let bg_index = u8(11)
  let mut p = 13
  let global : Array[Int] = []
  if (flags & 0x80) != 0 {
    let size = 1 << ((flags & 7) + 1)
    for k in 0..<size {
      global.push((u8(p + 3 * k) << 16) | (u8(p + 3 * k + 1) << 8) | u8(p + 3 * k + 2))
    }
    p = p + 3 * size
  }
  ignore(bg_index)
  let canvas = FixedArray::make(w * h * 4, b'\x00')
  let frames : Array[FixedArray[Byte]] = []
  let delays : Array[Double] = []
  // what the next frame's graphic control says
  let mut delay = 0.0
  let mut transparent = -1
  let mut disposal = 0
  while p < n {
    let b = u8(p)
    if b == 0x3B {
      break
    } else if b == 0x21 {
      // an extension: a graphic control's delay, transparency and disposal; the rest passed over
      let label = u8(p + 1)
      p = p + 2
      if label == 0xF9 && u8(p) >= 4 {
        let f = u8(p + 1)
        disposal = (f >> 2) & 7
        delay = u16(p + 2).to_double() * 10.0
        transparent = if (f & 1) != 0 { u8(p + 4) } else { -1 }
      }
      while p < n && u8(p) != 0 {
        p = p + u8(p) + 1
      }
      p = p + 1
    } else if b == 0x2C {
      let fx = u16(p + 1)
      let fy = u16(p + 3)
      let fw = u16(p + 5)
      let fh = u16(p + 7)
      let lf = u8(p + 9)
      p = p + 10
      let table = if (lf & 0x80) != 0 {
        let size = 1 << ((lf & 7) + 1)
        let t = []
        for k in 0..<size {
          t.push((u8(p + 3 * k) << 16) | (u8(p + 3 * k + 1) << 8) | u8(p + 3 * k + 2))
        }
        p = p + 3 * size
        t
      } else {
        global
      }
      let interlaced = (lf & 0x40) != 0
      let min_code = u8(p)
      p = p + 1
      // the image's data, its sub-blocks joined
      let lzw : Array[Byte] = []
      while p < n && u8(p) != 0 {
        let len = u8(p)
        for k in 0..<len {
          if p + 1 + k < n {
            lzw.push(data[p + 1 + k])
          }
        }
        p = p + len + 1
      }
      p = p + 1
      let indices = lzw_decode(lzw, min_code, fw * fh)
      // what the canvas goes back to once this frame has been shown (disposal 3)
      let before = if disposal == 3 { Some(canvas.copy()) } else { None }
      let rows = interlace_rows(fh, interlaced)
      for r in 0..<fh {
        let y = fy + rows[r]
        if y >= h {
          continue
        }
        for x in 0..<fw {
          let k = r * fw + x
          if k >= indices.length() {
            break
          }
          let ci = indices[k]
          if ci == transparent || ci >= table.length() || fx + x >= w {
            continue
          }
          let rgb = table[ci]
          let o = (y * w + fx + x) * 4
          canvas[o] = ((rgb >> 16) & 0xFF).to_byte()
          canvas[o + 1] = ((rgb >> 8) & 0xFF).to_byte()
          canvas[o + 2] = (rgb & 0xFF).to_byte()
          canvas[o + 3] = b'\xFF'
        }
      }
      frames.push(canvas.copy())
      delays.push(if delay < 20.0 { gif_least_ms } else { delay })
      // after it is shown: its rect cleared (2), the canvas as it was before it (3), or left (0, 1)
      if disposal == 2 {
        for y in fy..<imin(fy + fh, h) {
          for x in fx..<imin(fx + fw, w) {
            let o = (y * w + x) * 4
            for c in 0..<4 {
              canvas[o + c] = b'\x00'
            }
          }
        }
      } else if before is Some(was) {
        was.blit_to(canvas, len=canvas.length())
      }
      delay = 0.0
      transparent = -1
      disposal = 0
    } else {
      break
    }
  }
  if frames.length() == 0 {
    None
  } else {
    Some({ w, h, frames, delays })
  }
}

///|
/// Which of the frame's rows each of its lines of data is: in order, or interlaced (every 8th from 0, every 8th from
/// 4, every 4th from 2, every 2nd from 1).
fn interlace_rows(h : Int, interlaced : Bool) -> Array[Int] {
  if !interlaced {
    return Array::makei(h, fn(i) { i })
  }
  let out = []
  for pass in [(0, 8), (4, 8), (2, 4), (1, 2)] {
    let mut y = pass.0
    while y < h {
      out.push(y)
      y = y + pass.1
    }
  }
  out
}

///|
/// A GIF image's LZW-coded colour indices, `most` at most.
fn lzw_decode(data : Array[Byte], min_code : Int, most : Int) -> Array[Int] {
  let out : Array[Int] = []
  if min_code < 2 || min_code > 11 {
    return out
  }
  let clear = 1 << min_code
  let end = clear + 1
  // each code's string: its last index and the code before it (-1: none), and its length
  let prefix = FixedArray::make(4096, -1)
  let suffix = FixedArray::make(4096, 0)
  let first = FixedArray::make(4096, 0)
  for k in 0..<clear {
    suffix[k] = k
    first[k] = k
  }
  let mut size = min_code + 1
  let mut next = end + 1
  let mut prev = -1
  let mut bits = 0
  let mut acc = 0
  let stack = FixedArray::make(4097, 0)
  let mut i = 0
  while i < data.length() && out.length() < most {
    acc = acc | (data[i].to_int() << bits)
    bits = bits + 8
    i = i + 1
    while bits >= size && out.length() < most {
      let code = acc & ((1 << size) - 1)
      acc = acc >> size
      bits = bits - size
      if code == clear {
        size = min_code + 1
        next = end + 1
        prev = -1
        continue
      }
      if code == end {
        return out
      }
      let known = code < next
      if !known && (code != next || prev < 0) {
        return out
      }
      // the code's string, pushed last index first, then given out in order
      let mut c = if known { code } else { prev }
      let mut top = 0
      if !known {
        stack[top] = first[prev]
        top = top + 1
      }
      while c >= 0 && top < 4097 {
        stack[top] = suffix[c]
        top = top + 1
        c = prefix[c]
      }
      let head = stack[top - 1]
      while top > 0 && out.length() < most {
        top = top - 1
        out.push(stack[top])
      }
      if prev >= 0 && next < 4096 {
        prefix[next] = prev
        suffix[next] = head
        first[next] = first[prev]
        next = next + 1
        if next == (1 << size) && size < 12 {
          size = size + 1
        }
      }
      prev = code
    }
  }
  out
}

///|
/// A GIF's frames handed over (add_image): each frame's key (`key#<n>`, its pixels as a PNG the host decodes as any
/// picture) and when in its cycle it ends (ms, the frames' lengths summed).
priv struct GifCycle {
  keys : Array[String]
  ends : Array[Double]
}

///|
/// The GIFs that move, by the key they were handed over as.
let moving_images : Map[String, GifCycle] = {}

///|
/// `data` handed over as `key` when it is a GIF of more than one frame: its frames each as a picture of its own, the
/// first under `key` too (what a still shows); false when it is not one (handed over as it is).
fn add_gif(key : String, data : Bytes) -> Bool {
  if !is_gif(data) {
    return false
  }
  match gif_frames(data) {
    Some(g) if g.frames.length() > 1 => {
      let keys = []
      let ends = []
      let mut t = 0.0
      for k, f in g.frames {
        let fk = key + "#" + k.to_string()
        image_data[fk] = png_of(g.w, g.h, f)
        keys.push(fk)
        t = t + g.delays[k]
        ends.push(t)
      }
      image_data[key] = image_data[keys[0]]
      moving_images[key] = { keys, ends }
      true
    }
    _ => false
  }
}

///|
/// Which frame of a moving image is shown at `phase` (0 … 1) of its cycle.
fn moving_frame(m : GifCycle, phase : Double) -> String {
  let t = phase * m.ends[m.ends.length() - 1]
  for k, e in m.ends {
    if t < e {
      return m.keys[k]
    }
  }
  m.keys[m.keys.length() - 1]
}

///|
/// RGBA pixels (straight) as a PNG, stored, not compressed: what a host decodes as any picture.
fn png_of(w : Int, h : Int, rgba : FixedArray[Byte]) -> Bytes {
  let out : Array[Byte] = []
  let u32 = fn(a : Array[Byte], v : Int) {
    a.push(((v >> 24) & 0xFF).to_byte())
    a.push(((v >> 16) & 0xFF).to_byte())
    a.push(((v >> 8) & 0xFF).to_byte())
    a.push((v & 0xFF).to_byte())
  }
  let chunk = fn(kind : String, body : Array[Byte]) {
    u32(out, body.length())
    let start = out.length()
    for ch in kind {
      out.push(ch.to_int().to_byte())
    }
    out.append(body)
    let mut crc = 0xFFFFFFFFU
    for i in start..<out.length() {
      crc = crc ^ out[i].to_uint()
      for _ in 0..<8 {
        crc = if (crc & 1U) != 0U { 0xEDB88320U ^ (crc >> 1) } else { crc >> 1 }
      }
    }
    u32(out, (crc ^ 0xFFFFFFFFU).reinterpret_as_int())
  }
  for b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    out.push(b.to_byte())
  }
  let head : Array[Byte] = []
  u32(head, w)
  u32(head, h)
  for b in [8, 6, 0, 0, 0] {
    head.push(b.to_byte())
  }
  chunk("IHDR", head)
  // the rows, each after its filter byte (none), in stored deflate blocks
  let raw : Array[Byte] = []
  for y in 0..<h {
    raw.push(b'\x00')
    for x in 0..<(w * 4) {
      raw.push(rgba[y * w * 4 + x])
    }
  }
  let z : Array[Byte] = [b'\x78', b'\x01']
  let mut at = 0
  while at < raw.length() || at == 0 {
    let n = imin(raw.length() - at, 65535)
    z.push((if at + n >= raw.length() { 1 } else { 0 }).to_byte())
    z.push((n & 0xFF).to_byte())
    z.push((n >> 8).to_byte())
    z.push((n.lnot() & 0xFF).to_byte())
    z.push(((n.lnot() >> 8) & 0xFF).to_byte())
    for i in at..<(at + n) {
      z.push(raw[i])
    }
    at = at + n
    if n == 0 {
      break
    }
  }
  let mut a = 1
  let mut b = 0
  for v in raw {
    a = (a + v.to_int()) % 65521
    b = (b + a) % 65521
  }
  u32(z, (b << 16) | a)
  chunk("IDAT", z)
  chunk("IEND", [])
  Bytes::from_array(out)
}
