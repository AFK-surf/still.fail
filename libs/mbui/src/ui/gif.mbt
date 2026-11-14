// GIFs that move: decoded here (not by a host, whose decoders give a still's first frame), each frame as the screen
// shows it then (its canvas after the frames before it, as their disposal leaves it), with how long it stays. An
// image handed over as a GIF of more than one frame (add_image) is shown as its frames in turn, a cycle of their
// lengths (Ctx::loop_at: a frame of each length, the same at any frame rate); `still` holds its first. Handed over, its
// blocks are walked once for how many frames it has and how long each stays, and only its first frame is decoded and
// made a picture (a PNG, png_of, which the host decodes as any picture): the rest are each decoded and made as they are
// first wanted (Ctx::moving_key: the frame its loop is at, and the one after it, so the host has that one decoded by its
// turn), by one decoder kept with it till all are made, then let go. When it is made decides only when the work is
// done: which frame shows at a moment is the loop's at that moment, as it was when all were made at once. One whose
// frames come to more pixels than gif_moving_most does not move: its frames are counted by its blocks, none decoded,
// and it is handed over as it is, a still (its first frame, as the host decodes it).

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
/// The most pixels a GIF that moves has in its frames together (frames × width × height): ≈64 MB as RGBA, which each
/// frame is held as twice once it is made, here (a PNG of it, png_of, stored, not compressed) and again by the host it
/// is handed to (its decode, and on Android the PNG's bytes, kept to decode again). 132 frames of 360 × 734 took a
/// phone's whole Java heap.
let gif_moving_most : Int = 16_000_000

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
/// Byte `i` of `data`, 0 past its end (a GIF cut short reads as zeros).
fn gif_u8(data : Bytes, i : Int) -> Int {
  if i < data.length() {
    data[i].to_int()
  } else {
    0
  }
}

///|
/// GIF `data`'s screen, its width and height, and where its blocks start (after its global colour table); None where it
/// is not one, is cut short before its blocks' start can be read, or its screen is empty or larger than a canvas is made
/// (16 M pixels).
fn gif_screen(data : Bytes) -> (Int, Int, Int)? {
  if !is_gif(data) || data.length() < 13 {
    return None
  }
  let w = gif_u8(data, 6) | (gif_u8(data, 7) << 8)
  let h = gif_u8(data, 8) | (gif_u8(data, 9) << 8)
  // (w > 16 M / h, not w × h > 16 M: 65535 × 65535 is past an Int)
  if w <= 0 || h <= 0 || w > 16_000_000 / h {
    return None
  }
  let flags = gif_u8(data, 10)
  let at = if (flags & 0x80) != 0 { 13 + 3 * (1 << ((flags & 7) + 1)) } else { 13 }
  Some((w, h, at))
}

///|
/// Where the sub-blocks of GIF `data` from `p` end (each its length's byte, then that many; one may run past the end of
/// `data`): where the block after them starts, past their terminator.
fn gif_sub_blocks(data : Bytes, p : Int) -> Int {
  let n = data.length()
  let mut p = p
  while p < n && data[p] != b'\x00' {
    p = p + data[p].to_int() + 1
  }
  p + 1
}

///|
/// Where the block of GIF `data` at `p` ends (the next one starts); -1 where `p` is past its end or what is there is not
/// a block it knows (its trailer, 0x3B, or what is no block).
fn gif_block_end(data : Bytes, p : Int) -> Int {
  if p >= data.length() {
    return -1
  }
  let b = data[p]
  if b == b'\x21' {
    gif_sub_blocks(data, p + 2)
  } else if b == b'\x2C' {
    let lf = gif_u8(data, p + 9)
    let mut q = p + 10
    if (lf & 0x80) != 0 {
      q = q + 3 * (1 << ((lf & 7) + 1))
    }
    // its LZW code size, then its data
    gif_sub_blocks(data, q + 1)
  } else {
    -1
  }
}

///|
/// The blocks of GIF `data` from `p` (gif_screen's), in order until its trailer, a block it does not know or its end:
/// each extension given to `extension` (where its label is), each image to `image` (where its descriptor is). The one
/// walk frames are counted by (gif_frame_count, gif_delays) and decoded by (GifDecoder::next, block by block).
fn gif_blocks(data : Bytes, p : Int, extension : (Int) -> Unit, image : (Int) -> Unit) -> Unit {
  let mut p = p
  while p < data.length() {
    let end = gif_block_end(data, p)
    if end < 0 {
      break
    }
    if data[p] == b'\x21' {
      extension(p + 1)
    } else {
      image(p)
    }
    p = end
  }
}

///|
/// How many frames GIF `data` has, counted by its blocks with none decoded (gif_frames' walk): 0 where it is not one or
/// is cut short before its first.
pub fn gif_frame_count(data : Bytes) -> Int {
  guard gif_screen(data) is Some((_, _, p)) else { return 0 }
  let mut count = 0
  gif_blocks(data, p, fn(_) {  }, fn(_) { count = count + 1 })
  count
}

///|
/// How long each frame of GIF `data` stays (ms), its blocks from `start` walked with none decoded: as its graphic
/// control says, gif_least_ms where that says none or under 20 ms. As many as gif_frame_count.
fn gif_delays(data : Bytes, start : Int) -> Array[Double] {
  let delays = []
  let mut delay = 0.0
  gif_blocks(
    data,
    start,
    fn(at) {
      if gif_u8(data, at) == 0xF9 && gif_u8(data, at + 1) >= 4 {
        delay = (gif_u8(data, at + 3) | (gif_u8(data, at + 4) << 8)).to_double() * 10.0
      }
    },
    fn(_) {
      delays.push(if delay < 20.0 { gif_least_ms } else { delay })
      delay = 0.0
    },
  )
  delays
}

///|
/// A GIF's frames decoded one at a time, in order, onto its canvas: after `next`, the canvas is the frame it decoded as
/// the screen shows it (RGBA, straight, rows from the top). What a frame leaves once shown (its disposal) is done as the
/// next one is decoded. Its tables and buffers are made once and kept from frame to frame.
priv struct GifDecoder {
  data : Bytes
  w : Int
  h : Int
  /// where its blocks start (past its global colour table)
  start : Int
  /// its global colour table, each colour 0xRRGGBB
  global : FixedArray[Int]
  /// a frame's own colour table, read into this
  local_colors : FixedArray[Int]
  canvas : FixedArray[Byte]
  /// the canvas as it was before a frame of disposal 3 (made as the first such frame comes)
  mut was : FixedArray[Byte]
  /// where the next block starts
  mut at : Int
  /// how many frames it has decoded (the next one's index)
  mut decoded : Int
  /// what the next frame's graphic control says: its transparent index (-1: none), its disposal
  mut transparent : Int
  mut disposal : Int
  /// what the frame decoded last leaves once shown (2: its rect cleared, 3: the canvas as it was before it; else as it
  /// is), and its rect
  mut leaves : Int
  mut lx : Int
  mut ly : Int
  mut lw : Int
  mut lh : Int
  /// the LZW codes' strings: each one's last index, the code before it (-1: none) and its first index
  prefix : FixedArray[Int]
  suffix : FixedArray[Int]
  first : FixedArray[Int]
  /// a code's string, pushed last index first
  stack : FixedArray[Int]
}

///|
/// A decoder of GIF `data`, whose screen is `w` by `h` and blocks start at `start` (gif_screen's), at its first frame.
fn GifDecoder::new(data : Bytes, w : Int, h : Int, start : Int) -> GifDecoder {
  let global = FixedArray::make((start - 13) / 3, 0)
  for k in 0..<global.length() {
    global[k] = (gif_u8(data, 13 + 3 * k) << 16) |
      (gif_u8(data, 13 + 3 * k + 1) << 8) |
      gif_u8(data, 13 + 3 * k + 2)
  }
  {
    data,
    w,
    h,
    start,
    global,
    local_colors: FixedArray::make(256, 0),
    canvas: FixedArray::make(w * h * 4, b'\x00'),
    was: FixedArray::make(0, b'\x00'),
    at: start,
    decoded: 0,
    transparent: -1,
    disposal: 0,
    leaves: 0,
    lx: 0,
    ly: 0,
    lw: 0,
    lh: 0,
    prefix: FixedArray::make(4096, -1),
    suffix: FixedArray::make(4096, 0),
    first: FixedArray::make(4096, 0),
    stack: FixedArray::make(4097, 0),
  }
}

///|
/// Back at the first frame, the canvas empty: to decode a frame before the one it is at.
fn GifDecoder::restart(self : GifDecoder) -> Unit {
  for i in 0..<self.canvas.length() {
    self.canvas[i] = b'\x00'
  }
  self.at = self.start
  self.decoded = 0
  self.transparent = -1
  self.disposal = 0
  self.leaves = 0
}

///|
/// The next frame decoded onto the canvas, after what the one before it leaves is done; false where there is none (its
/// trailer, a block it does not know, or its end: as many as gif_frame_count, by the same walk).
fn GifDecoder::next(self : GifDecoder) -> Bool {
  let w = self.w
  if self.leaves == 2 {
    for y in self.ly..<imin(self.ly + self.lh, self.h) {
      for x in self.lx..<imin(self.lx + self.lw, w) {
        let o = (y * w + x) * 4
        self.canvas[o] = b'\x00'
        self.canvas[o + 1] = b'\x00'
        self.canvas[o + 2] = b'\x00'
        self.canvas[o + 3] = b'\x00'
      }
    }
  } else if self.leaves == 3 {
    self.was.blit_to(self.canvas, len=self.canvas.length())
  }
  self.leaves = 0
  let data = self.data
  while self.at < data.length() {
    let p = self.at
    let end = gif_block_end(data, p)
    if end < 0 {
      break
    }
    self.at = end
    if data[p] == b'\x21' {
      // an extension: a graphic control's transparency and disposal (its delay is gif_delays'); the rest passed over
      if gif_u8(data, p + 1) == 0xF9 && gif_u8(data, p + 2) >= 4 {
        let f = gif_u8(data, p + 3)
        self.disposal = (f >> 2) & 7
        self.transparent = if (f & 1) != 0 { gif_u8(data, p + 6) } else { -1 }
      }
    } else {
      self.draw(p)
      self.decoded = self.decoded + 1
      self.transparent = -1
      self.disposal = 0
      return true
    }
  }
  false
}

///|
/// The image whose descriptor is at `at` drawn onto the canvas, as its graphic control said.
fn GifDecoder::draw(self : GifDecoder, at : Int) -> Unit {
  let data = self.data
  let u16 = fn(i : Int) { gif_u8(data, i) | (gif_u8(data, i + 1) << 8) }
  let fx = u16(at + 1)
  let fy = u16(at + 3)
  let fw = u16(at + 5)
  let fh = u16(at + 7)
  let lf = gif_u8(data, at + 9)
  let mut p = at + 10
  let (table, colours) = if (lf & 0x80) != 0 {
    let size = 1 << ((lf & 7) + 1)
    for k in 0..<size {
      self.local_colors[k] = (gif_u8(data, p + 3 * k) << 16) |
        (gif_u8(data, p + 3 * k + 1) << 8) |
        gif_u8(data, p + 3 * k + 2)
    }
    p = p + 3 * size
    (self.local_colors, size)
  } else {
    (self.global, self.global.length())
  }
  // what the canvas goes back to once this frame has been shown (disposal 3)
  if self.disposal == 3 {
    if self.was.length() != self.canvas.length() {
      self.was = FixedArray::make(self.canvas.length(), b'\x00')
    }
    self.canvas.blit_to(self.was, len=self.canvas.length())
  }
  self.leaves = self.disposal
  self.lx = fx
  self.ly = fy
  self.lw = fw
  self.lh = fh
  self.lzw_draw(p, fx, fy, fw, fh, interlace_rows(fh, (lf & 0x40) != 0), table, colours)
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
/// An image's LZW-coded colour indices (its code size at `p`, its sub-blocks after it, read where they lie in the GIF)
/// drawn as they come onto the canvas, its rect `fx`, `fy`, `fw` by `fh` (`rows`: which row each line of its data is),
/// in `table`'s first `colours` colours: an index past them, the transparent one, or a pixel off the canvas left as it
/// is. `fw` × `fh` indices at most; where its data ends or is not LZW, the rest of the rect left as it is.
fn GifDecoder::lzw_draw(
  self : GifDecoder,
  p : Int,
  fx : Int,
  fy : Int,
  fw : Int,
  fh : Int,
  rows : Array[Int],
  table : FixedArray[Int],
  colours : Int,
) -> Unit {
  let data = self.data
  let n = data.length()
  let min_code = gif_u8(data, p)
  if min_code < 2 || min_code > 11 || fw <= 0 || fh <= 0 {
    return
  }
  let (w, h, canvas, transparent) = (self.w, self.h, self.canvas, self.transparent)
  let (prefix, suffix, first, stack) = (self.prefix, self.suffix, self.first, self.stack)
  let clear = 1 << min_code
  let end = clear + 1
  for k in 0..<clear {
    prefix[k] = -1
    suffix[k] = k
    first[k] = k
  }
  let mut size = min_code + 1
  let mut next = end + 1
  let mut prev = -1
  let mut bits = 0
  let mut acc = 0
  // where its data is read: the next byte, and how many are left of the sub-block it is in
  let mut q = p + 1
  let mut left = 0
  // where the next index goes: its line of data `r`, `x` along it; its row's first pixel on the canvas (-1: below it)
  // and how many of its pixels are on the canvas
  let mut r = 0
  let mut x = 0
  let row_at = fn(r : Int) {
    let y = fy + rows[r]
    if y < h {
      (y * w + fx) * 4
    } else {
      -1
    }
  }
  let mut o = row_at(0)
  let across = imin(fw, w - fx)
  while r < fh {
    if left == 0 {
      if q >= n || data[q] == b'\x00' {
        return
      }
      left = data[q].to_int()
      q = q + 1
    }
    if q >= n {
      return
    }
    acc = acc | (data[q].to_int() << bits)
    q = q + 1
    left = left - 1
    bits = bits + 8
    while bits >= size && r < fh {
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
        return
      }
      let known = code < next
      if !known && (code != next || prev < 0) {
        return
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
      while top > 0 && r < fh {
        top = top - 1
        let ci = stack[top]
        if o >= 0 && x < across && ci != transparent && ci < colours {
          let rgb = table[ci]
          let k = o + x * 4
          canvas[k] = ((rgb >> 16) & 0xFF).to_byte()
          canvas[k + 1] = ((rgb >> 8) & 0xFF).to_byte()
          canvas[k + 2] = (rgb & 0xFF).to_byte()
          canvas[k + 3] = b'\xFF'
        }
        x = x + 1
        if x == fw {
          x = 0
          r = r + 1
          if r < fh {
            o = row_at(r)
          }
        }
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
}

///|
/// The frames of GIF `data`, all decoded, or None where it is not one, is cut short before its first frame, or its
/// frames come to more pixels than gif_moving_most (counted first: then none is decoded).
pub fn gif_frames(data : Bytes) -> GifFrames? {
  guard gif_screen(data) is Some((w, h, start)) else { return None }
  let delays = gif_delays(data, start)
  let count = delays.length()
  // (count × w × h > gif_moving_most, said so that it is never past an Int)
  if count == 0 || count > gif_moving_most / (w * h) {
    return None
  }
  let d = GifDecoder::new(data, w, h, start)
  let frames : Array[FixedArray[Byte]] = []
  while d.next() {
    frames.push(d.canvas.copy())
  }
  Some({ w, h, frames, delays })
}

///|
/// A GIF that moves, handed over (add_image): each frame's key (`key#<n>`, its pixels as a PNG the host decodes as any
/// picture) and when in its cycle it ends (ms, the frames' lengths summed); which frames are made (their bytes in
/// image_data), and the decoder that makes the rest, let go once none is left.
priv struct GifCycle {
  keys : Array[String]
  ends : Array[Double]
  made : FixedArray[Bool]
  mut unmade : Int
  mut decoder : GifDecoder?
}

///|
/// The GIFs that move, by the key they were handed over as.
let moving_images : Map[String, GifCycle] = Map([])

///|
/// `data` handed over as `key` when it is a GIF of more than one frame: its frames each a picture of its own, its first
/// made now and under `key` too (what a still shows), the rest as each is first wanted (GifCycle::make); false when it
/// is not one, or its frames are more than gif_moving_most (none decoded), handed over as it is.
fn add_gif(key : String, data : Bytes) -> Bool {
  guard gif_screen(data) is Some((w, h, start)) else { return false }
  let delays = gif_delays(data, start)
  let count = delays.length()
  // (count × w × h > gif_moving_most, said so that it is never past an Int)
  if count < 2 || count > gif_moving_most / (w * h) {
    return false
  }
  let keys = []
  let ends = []
  let mut t = 0.0
  for k, d in delays {
    keys.push(key + "#" + k.to_string())
    t = t + d
    ends.push(t)
  }
  let m : GifCycle = {
    keys,
    ends,
    made: FixedArray::make(count, false),
    unmade: count,
    decoder: Some(GifDecoder::new(data, w, h, start)),
  }
  moving_images[key] = m
  m.make(0)
  image_data[key] = image_data[keys[0]]
  true
}

///|
/// Frame `k` made, where it is not yet: its decoder taken on to it (the frames on the way decoded onto its canvas, not
/// made; begun again from the first where it is past it), its pixels made a PNG in image_data, said to be here. The
/// decoder let go once every frame is made.
fn GifCycle::make(self : GifCycle, k : Int) -> Unit {
  if self.made[k] {
    return
  }
  guard self.decoder is Some(d) else { return }
  if d.decoded > k + 1 {
    d.restart()
  }
  while d.decoded < k + 1 && d.next() {
    ()
  }
  image_data[self.keys[k]] = png_of(d.w, d.h, d.canvas)
  self.made[k] = true
  self.unmade = self.unmade - 1
  if self.unmade == 0 {
    self.decoder = None
  }
  image_bytes_here(self.keys[k])
}

///|
/// Which frame of a moving image is shown at `phase` (0 … 1) of its cycle.
fn moving_frame(m : GifCycle, phase : Double) -> Int {
  let t = phase * m.ends[m.ends.length() - 1]
  for k, e in m.ends {
    if t < e {
      return k
    }
  }
  m.ends.length() - 1
}

///|
// kept across runs: a table, never written
/// CRC-32's remainder of each byte (PNG's: its polynomial 0xEDB88320, reflected).
let png_crc_table : FixedArray[UInt] = {
  let t = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c = n.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    t[n] = c
  }
  t
}

///|
/// `v` written big-endian into `out` at `at`.
fn png_u32(out : FixedArray[Byte], at : Int, v : Int) -> Unit {
  out[at] = ((v >> 24) & 0xFF).to_byte()
  out[at + 1] = ((v >> 16) & 0xFF).to_byte()
  out[at + 2] = ((v >> 8) & 0xFF).to_byte()
  out[at + 3] = (v & 0xFF).to_byte()
}

///|
/// A chunk's CRC written after its kind and body (`out` from `from` to `until`).
fn png_crc(out : FixedArray[Byte], from : Int, until : Int) -> Unit {
  let mut c = 0xFFFFFFFFU
  for i in from..<until {
    c = png_crc_table[((c ^ out[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  png_u32(out, until, (c ^ 0xFFFFFFFFU).reinterpret_as_int())
}

///|
/// A chunk's length and kind (its four letters as one number, big-endian) written into `out` at `at`.
fn png_chunk_head(out : FixedArray[Byte], at : Int, length : Int, kind : Int) -> Unit {
  png_u32(out, at, length)
  png_u32(out, at + 4, kind)
}

///|
/// RGBA pixels (straight) as a PNG, stored, not compressed: what a host decodes as any picture. Written into one buffer
/// of the size it comes to, each row copied whole; its checks (CRC-32 by a table, Adler-32 with the remainder taken
/// every 5552 bytes, as zlib does, the most before its sums can pass 32 bits) worked out over it.
fn png_of(w : Int, h : Int, rgba : FixedArray[Byte]) -> Bytes {
  let stride = w * 4
  // the rows, each after its filter byte (none), in stored deflate blocks of 65535 bytes at most (one, empty, for none)
  let raw = h * (stride + 1)
  let blocks = if raw == 0 { 1 } else { (raw + 65534) / 65535 }
  let zlen = 2 + 5 * blocks + raw + 4
  let out = FixedArray::make(8 + 25 + (12 + zlen) + 12, b'\x00')
  for i, b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    out[i] = b.to_byte()
  }
  // (IHDR)
  png_chunk_head(out, 8, 13, 0x49484452)
  png_u32(out, 16, w)
  png_u32(out, 20, h)
  out[24] = b'\x08'
  out[25] = b'\x06'
  png_crc(out, 12, 29)
  // (IDAT)
  png_chunk_head(out, 33, zlen, 0x49444154)
  out[41] = b'\x78'
  out[42] = b'\x01'
  let mut o = 43
  // raw bytes written, and left in the block being written
  let mut done = 0
  let mut left = 0
  let block = fn() {
    let n = imin(raw - done, 65535)
    out[o] = (if done + n >= raw { 1 } else { 0 }).to_byte()
    out[o + 1] = (n & 0xFF).to_byte()
    out[o + 2] = (n >> 8).to_byte()
    out[o + 3] = (n.lnot() & 0xFF).to_byte()
    out[o + 4] = ((n.lnot() >> 8) & 0xFF).to_byte()
    o = o + 5
    left = n
  }
  if raw == 0 {
    block()
  }
  // Adler-32's sums, and how many bytes were added since their remainder was last taken
  let mut a = 1U
  let mut b = 0U
  let mut summed = 0
  for y in 0..<h {
    if left == 0 {
      block()
    }
    // (its filter byte, 0, as the buffer was made)
    o = o + 1
    left = left - 1
    done = done + 1
    b = b + a
    summed = summed + 1
    if summed == 5552 {
      a = a % 65521U
      b = b % 65521U
      summed = 0
    }
    let mut s = y * stride
    let mut rest = stride
    while rest > 0 {
      if left == 0 {
        block()
      }
      let c = imin(rest, left)
      rgba.blit_to(out, len=c, src_offset=s, dst_offset=o)
      // (summed in runs up to the next remainder)
      let mut i = s
      while i < s + c {
        let run = imin(s + c - i, 5552 - summed)
        for j in i..<(i + run) {
          a = a + rgba[j].to_uint()
          b = b + a
        }
        i = i + run
        summed = summed + run
        if summed == 5552 {
          a = a % 65521U
          b = b % 65521U
          summed = 0
        }
      }
      o = o + c
      s = s + c
      rest = rest - c
      left = left - c
      done = done + c
    }
  }
  a = a % 65521U
  b = b % 65521U
  png_u32(out, o, ((b << 16) | a).reinterpret_as_int())
  o = o + 4
  png_crc(out, 37, o)
  o = o + 4
  // (IEND)
  png_chunk_head(out, o, 0, 0x49454E44)
  png_crc(out, o + 4, o + 8)
  Bytes::from_array(out[:])
}
