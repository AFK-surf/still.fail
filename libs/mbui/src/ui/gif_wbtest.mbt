// A GIF that moves made a frame at a time as each is wanted (gif.mbt): each frame made the same bytes as all decoded at
// once, whenever and from wherever in its loop it is first shown; the decoder and png_of the same as those they replaced
// (kept here as they were, to compare with).

///|
/// `indices` LZW-coded as a GIF's image data (its sub-blocks, terminated) into `out`, codes from `min_code` + 1 bits.
fn lzw_coded(indices : Array[Int], min_code : Int, out : Array[Byte]) -> Unit {
  let clear = 1 << min_code
  let end = clear + 1
  let table : Map[Int, Int] = Map([])
  let mut size = min_code + 1
  let mut next = end + 1
  let mut acc = 0
  let mut bits = 0
  let bytes : Array[Byte] = []
  let emit = fn(code : Int) {
    acc = acc | (code << bits)
    bits = bits + size
    while bits >= 8 {
      bytes.push((acc & 0xFF).to_byte())
      acc = acc >> 8
      bits = bits - 8
    }
  }
  emit(clear)
  let mut cur = indices[0]
  for i in 1..<indices.length() {
    let k = indices[i]
    let key = cur * 256 + k
    match table.get(key) {
      Some(c) => cur = c
      None => {
        emit(cur)
        if next < 4096 {
          table[key] = next
          next = next + 1
          if next > (1 << size) && size < 12 {
            size = size + 1
          }
        } else {
          emit(clear)
          table.clear()
          size = min_code + 1
          next = end + 1
        }
        cur = k
      }
    }
  }
  emit(cur)
  emit(end)
  if bits > 0 {
    bytes.push((acc & 0xFF).to_byte())
  }
  let mut at = 0
  while at < bytes.length() {
    let n = imin(255, bytes.length() - at)
    out.push(n.to_byte())
    for i in at..<(at + n) {
      out.push(bytes[i])
    }
    at = at + n
  }
  out.push(b'\x00')
}

///|
/// A frame of a GIF made here: its rect, how it is left once shown, its transparent index (-1: none), how long it stays
/// (hundredths of a second), its own colour table's size (0: the global one's), whether it is interlaced, and its
/// indices (by `index`, at each of its pixels).
priv struct MadeFrame {
  x : Int
  y : Int
  w : Int
  h : Int
  disposal : Int
  transparent : Int
  delay : Int
  local_colors : Int
  interlaced : Bool
  index : (Int, Int) -> Int
}

///|
/// A GIF 8 by 6 of 4 colours whose frames are each of the ways a frame is drawn: whole; a rect inside the screen with
/// a transparent index, cleared once shown (2); a rect with its own colours, interlaced, the canvas put back once shown
/// (3); a strip interlaced with another transparent index, left (0); a rect past the screen's right edge put back (3),
/// saying under 20 ms (so 100); a rect of its own 2 colours, cleared (2). They end at 100, 150, 220, 250, 350 and 430 ms.
fn many_ways_gif() -> Bytes {
  let frames : Array[MadeFrame] = [
    { x: 0, y: 0, w: 8, h: 6, disposal: 1, transparent: -1, delay: 10, local_colors: 0, interlaced: false, index: fn(x, y) { (x + y) % 4 } },
    { x: 2, y: 1, w: 4, h: 3, disposal: 2, transparent: 0, delay: 5, local_colors: 0, interlaced: false, index: fn(x, y) { (x * y) % 4 } },
    { x: 1, y: 2, w: 5, h: 3, disposal: 3, transparent: -1, delay: 7, local_colors: 8, interlaced: true, index: fn(x, y) { (x + 2 * y) % 8 } },
    { x: 0, y: 0, w: 3, h: 6, disposal: 0, transparent: 1, delay: 3, local_colors: 0, interlaced: true, index: fn(x, y) { (x + 3 * y) % 4 } },
    { x: 6, y: 3, w: 4, h: 3, disposal: 3, transparent: -1, delay: 1, local_colors: 0, interlaced: false, index: fn(x, y) { (3 * x + y) % 4 } },
    { x: 3, y: 0, w: 2, h: 2, disposal: 2, transparent: -1, delay: 8, local_colors: 2, interlaced: false, index: fn(x, y) { (x + y) % 2 } },
  ]
  let out : Array[Byte] = []
  for b in [b'G', b'I', b'F', b'8', b'9', b'a'] {
    out.push(b)
  }
  let u16 = fn(v : Int) {
    out.push((v & 0xFF).to_byte())
    out.push((v >> 8).to_byte())
  }
  u16(8)
  u16(6)
  // (a global table of 4 colours)
  out.push(b'\x81')
  out.push(b'\x00')
  out.push(b'\x00')
  for c in [0x102030, 0xF04010, 0x20C040, 0x3050E0] {
    out.push((c >> 16).to_byte())
    out.push(((c >> 8) & 0xFF).to_byte())
    out.push((c & 0xFF).to_byte())
  }
  for f in frames {
    out.push(b'\x21')
    out.push(b'\xF9')
    out.push(b'\x04')
    out.push(((f.disposal << 2) | (if f.transparent >= 0 { 1 } else { 0 })).to_byte())
    u16(f.delay)
    out.push((if f.transparent >= 0 { f.transparent } else { 0 }).to_byte())
    out.push(b'\x00')
    out.push(b'\x2C')
    u16(f.x)
    u16(f.y)
    u16(f.w)
    u16(f.h)
    let bits = if f.local_colors == 8 { 3 } else if f.local_colors == 4 { 2 } else { 1 }
    let lf = (if f.local_colors > 0 { 0x80 | (bits - 1) } else { 0 }) | (if f.interlaced { 0x40 } else { 0 })
    out.push(lf.to_byte())
    for c in 0..<f.local_colors {
      out.push(((c * 37 + 11) & 0xFF).to_byte())
      out.push(((c * 91 + 5) & 0xFF).to_byte())
      out.push(((200 - c * 23) & 0xFF).to_byte())
    }
    let min_code = if f.local_colors == 8 { 3 } else { 2 }
    out.push(min_code.to_byte())
    let indices = []
    for y in interlace_rows(f.h, f.interlaced) {
      for x in 0..<f.w {
        indices.push((f.index)(x, y))
      }
    }
    lzw_coded(indices, min_code, out)
  }
  out.push(b'\x3B')
  Bytes::from_array(out)
}

///|
/// Which of `key`'s frames each picture drawn is (by the drawlist): its index, or -1 where it is `key` itself.
fn frames_drawn(t : Tester, key : String, n : Int) -> Array[Int] {
  let out = []
  for l in t.drawlist().split("\n") {
    if !l.has_prefix("image ") {
      continue
    }
    if l.contains("\"\{key}\"") {
      out.push(-1)
    }
    for k in 0..<n {
      if l.contains("\"\{key}#\{k}\"") {
        out.push(k)
      }
    }
  }
  out
}

///|
/// Which of moving image `m`'s frames are made.
fn made_of(m : GifCycle) -> Array[Bool] {
  Array::makei(m.made.length(), fn(i) { m.made[i] })
}

///|
/// A Tester showing GIF `key` while `shown` says so, twice: two pictures of it, of two sizes.
fn shown_twice(key : String, shown : Ref[Bool]) -> Tester {
  Tester::new(
    fn(c) {
      if shown.val {
        c.image(key, w=Px(16.0), h=Px(12.0), fade=false) |> ignore
        c.image(key, w=Px(40.0), h=Px(30.0), fade=false) |> ignore
      }
    },
    w=100.0,
    h=100.0,
  )
}

///|
/// The clock run on to the middle of frame `k`'s turn of moving image `m` (the next such moment), less `short`.
fn run_to_frame(t : Tester, m : GifCycle, k : Int, short : Double) -> Unit {
  let length = m.ends[m.ends.length() - 1]
  let from = if k == 0 { 0.0 } else { m.ends[k - 1] }
  let mid = (from + m.ends[k]) / 2.0 - short
  let at = t.time() - (t.time() / length).floor() * length
  let mut d = mid - at
  while d <= 0.0 {
    d = d + length
  }
  t.run_for(d)
}

///|
/// What GIF `key` shows now (both of its pictures), held to the frame its loop is at and to the bytes that frame has
/// decoded with all the others at once (`eager`).
fn holds_frame(t : Tester, key : String, eager : GifFrames, k : Int) -> Unit raise {
  let m = moving_images.get(key).unwrap()
  let length = m.ends[m.ends.length() - 1]
  let at = t.time() - (t.time() / length).floor() * length
  assert_eq(moving_frame(m, at / length), k)
  assert_eq(frames_drawn(t, key, m.keys.length()), [k, k])
  assert_eq(image_data.get(m.keys[k]), Some(png_of(eager.w, eager.h, eager.frames[k])))
}

///|
test "a GIF's frames made as each is wanted: the same bytes as all decoded at once, first shown mid-loop, on into the next" {
  let data = many_ways_gif()
  let eager = gif_frames(data).unwrap()
  assert_eq(eager.frames.length(), 6)
  assert_eq(eager.delays, [100.0, 50.0, 70.0, 30.0, 100.0, 80.0])
  let shown = Ref(false)
  let t = shown_twice("mem:ways", shown)
  add_image("mem:ways", data)
  t.draw()
  let m = moving_images.get("mem:ways").unwrap()
  // (handed over: its first frame alone)
  assert_eq(made_of(m), [true, false, false, false, false, false])
  assert_eq(image_data.get("mem:ways"), Some(png_of(eager.w, eager.h, eager.frames[0])))
  // first shown in frame 2's turn: it and the next made, the frames on the way to it decoded only
  run_to_frame(t, m, 2, a_moment_short)
  shown.val = true
  t.draw()
  assert_eq(made_of(m), [true, false, true, true, false, false])
  assert_true(!image_data.contains("mem:ways#1"))
  t.run_for(a_moment_on)
  holds_frame(t, "mem:ways", eager, 2)
  // each turn after it, past its end into the next lap
  for k in [3, 4, 5, 0, 1, 2, 3] {
    run_to_frame(t, m, k, 0.0)
    holds_frame(t, "mem:ways", eager, k)
  }
  // a whole loop shown: every frame made, its decoder let go
  assert_eq(made_of(m), [true, true, true, true, true, true])
  assert_eq(m.unmade, 0)
  assert_true(m.decoder is None)
}

///|
test "a GIF first shown at its last frame: the decoder past all the others, begun again for the next lap" {
  let data = many_ways_gif()
  let eager = gif_frames(data).unwrap()
  let shown = Ref(false)
  let t = shown_twice("mem:last", shown)
  add_image("mem:last", data)
  t.draw()
  let m = moving_images.get("mem:last").unwrap()
  run_to_frame(t, m, 5, a_moment_short)
  shown.val = true
  t.draw()
  assert_eq(made_of(m), [true, false, false, false, false, true])
  assert_eq(m.decoder.unwrap().decoded, 6)
  t.run_for(a_moment_on)
  holds_frame(t, "mem:last", eager, 5)
  for k in [0, 1, 2, 3, 4, 5, 0] {
    run_to_frame(t, m, k, 0.0)
    holds_frame(t, "mem:last", eager, k)
  }
  assert_true(m.decoder is None)
}

///|
/// GIF `key` shown by `t` from the middle of frame `k`'s turn, a moment short of it, held to that frame a moment on, and
/// put away again.
fn shown_once(t : Tester, shown : Ref[Bool], key : String, eager : GifFrames, k : Int) -> Unit raise {
  run_to_frame(t, moving_images.get(key).unwrap(), k, a_moment_short)
  shown.val = true
  t.draw()
  t.run_for(a_moment_on)
  holds_frame(t, key, eager, k)
  shown.val = false
  t.draw()
}

///|
test "a GIF scrolled away and shown again later, behind and ahead of where its decoder is: each time the frame of then" {
  let data = many_ways_gif()
  let eager = gif_frames(data).unwrap()
  let shown = Ref(false)
  let t = shown_twice("mem:back", shown)
  add_image("mem:back", data)
  t.draw()
  let m = moving_images.get("mem:back").unwrap()
  // shown at 3 (3 and 4 made: its decoder at 5), then away for laps
  shown_once(t, shown, "mem:back", eager, 3)
  assert_eq(m.decoder.unwrap().decoded, 5)
  t.run_for(away)
  // shown again at 1, behind it: begun again (1 and 2 made)
  shown_once(t, shown, "mem:back", eager, 1)
  assert_eq(made_of(m), [true, true, true, true, true, false])
  assert_eq(m.decoder.unwrap().decoded, 3)
  t.run_for(away * 2.0)
  // and at 5, ahead of it: the last made, its decoder let go
  shown_once(t, shown, "mem:back", eager, 5)
  assert_true(m.decoder is None)
  // (all made now: shown anywhere, the same)
  shown_once(t, shown, "mem:back", eager, 2)
}

///|
test "GIF frames decoded as before: a frame of each way drawn, and cut short anywhere" {
  let data = many_ways_gif()
  let now = gif_frames(data).unwrap()
  let before = gif_frames_before(data).unwrap()
  assert_eq((now.w, now.h, now.delays), (before.w, before.h, before.delays))
  assert_true(now.frames == before.frames)
  for l in 0..=data.length() {
    let cut = Bytes::from_array(Array::makei(l, fn(i) { data[i] }))
    let a = gif_frames(cut).map(fn(g) { (g.w, g.h, g.delays, g.frames) })
    let b = gif_frames_before(cut).map(fn(g) { (g.w, g.h, g.delays, g.frames) })
    assert_true(a == b, msg="cut at \{l}")
  }
}

///|
test "png_of: the same bytes as the one it replaced, one pixel, a few, none, and rows of more than one deflate block" {
  let mut seed = 7
  for size in [(1, 1), (3, 2), (5, 0), (200, 100), (300, 300)] {
    let (w, h) = size
    let rgba = FixedArray::make(w * h * 4, b'\x00')
    for i in 0..<rgba.length() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
      rgba[i] = ((seed >> 16) & 0xFF).to_byte()
    }
    assert_true(png_of(w, h, rgba) == png_of_before(w, h, rgba), msg="\{w} by \{h}")
  }
  // (all 255: Adler-32's sums at their largest between remainders)
  let full = FixedArray::make(300 * 300 * 4, b'\xFF')
  assert_true(png_of(300, 300, full) == png_of_before(300, 300, full))
}

///|
/// png_of as it was (till 2026-11-11), to compare with: byte by byte into arrays, CRC-32 a bit at a time.
fn png_of_before(w : Int, h : Int, rgba : FixedArray[Byte]) -> Bytes {
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

///|
/// gif_frames as it was (till 2026-11-11), to compare with: its sub-blocks joined into an array, its indices pushed
/// into another, the canvas copied whole for each frame.
fn gif_frames_before(data : Bytes) -> GifFrames? {
  guard gif_screen(data) is Some((w, h, start)) else { return None }
  let count = gif_frame_count(data)
  if count == 0 || count > gif_moving_most / (w * h) {
    return None
  }
  let n = data.length()
  let u8 = fn(i : Int) { gif_u8(data, i) }
  let u16 = fn(i : Int) { u8(i) | (u8(i + 1) << 8) }
  let global : Array[Int] = []
  if (u8(10) & 0x80) != 0 {
    for k in 0..<((start - 13) / 3) {
      global.push((u8(13 + 3 * k) << 16) | (u8(13 + 3 * k + 1) << 8) | u8(13 + 3 * k + 2))
    }
  }
  let canvas = FixedArray::make(w * h * 4, b'\x00')
  let frames : Array[FixedArray[Byte]] = []
  let delays : Array[Double] = []
  let mut delay = 0.0
  let mut transparent = -1
  let mut disposal = 0
  let sub_blocks = fn(p : Int, each : (Int, Int) -> Unit) -> Int {
    let mut p = p
    while p < n && data[p] != b'\x00' {
      let len = data[p].to_int()
      each(p + 1, len)
      p = p + len + 1
    }
    p + 1
  }
  let extension = fn(at : Int) {
    let p = at + 1
    if u8(at) == 0xF9 && u8(p) >= 4 {
      let f = u8(p + 1)
      disposal = (f >> 2) & 7
      delay = u16(p + 2).to_double() * 10.0
      transparent = if (f & 1) != 0 { u8(p + 4) } else { -1 }
    }
  }
  let image = fn(at : Int) {
    let fx = u16(at + 1)
    let fy = u16(at + 3)
    let fw = u16(at + 5)
    let fh = u16(at + 7)
    let lf = u8(at + 9)
    let mut p = at + 10
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
    let lzw : Array[Byte] = []
    sub_blocks(p + 1, fn(s, len) {
      for k in 0..<len {
        if s + k < n {
          lzw.push(data[s + k])
        }
      }
    })
    |> ignore
    let indices = lzw_decode_before(lzw, min_code, fw * fh)
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
  }
  gif_blocks(data, start, extension, image)
  Some({ w, h, frames, delays })
}

///|
/// lzw_decode as it was (gif_frames_before's).
fn lzw_decode_before(data : Array[Byte], min_code : Int, most : Int) -> Array[Int] {
  let out : Array[Int] = []
  if min_code < 2 || min_code > 11 {
    return out
  }
  let clear = 1 << min_code
  let end = clear + 1
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
/// A moment into a frame's turn after it is first shown, and how far short of the middle of its turn it is shown from.
let a_moment_on : Double = 10.0

///|
let a_moment_short : Double = 5.0

///|
/// How long a GIF is put away before it is shown again: more than two of its loops.
let away : Double = 1000.0
