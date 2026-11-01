// CFF and CFF2 outlines (read-fonts' ps module: INDEXes, DICTs, FDSelect, the Type 2 charstring evaluator; skrifa's
// unhinted, unscaled drawing through its TransformSink and NopFilterSink). Values are 16.16 fixed bits; the points
// given out are whole font units, as skrifa rounds them when it does not scale.

///|
/// An INDEX: where its count starts, how many items, and each item's range.
priv struct CffIndex {
  count : Int
  /// item i is data[starts[i], starts[i + 1])
  starts : Array[Int]
  /// the byte after the INDEX
  end : Int
}

///|
fn cff_index(b : Bytes, at : Int, cff2 : Bool) -> CffIndex {
  let (count, head) = if cff2 { (u32(b, at), 4) } else { (u16(b, at), 2) }
  if count == 0 {
    return { count: 0, starts: [], end: at + head }
  }
  let off_size = u8(b, at + head)
  let offs = at + head + 1
  let data = offs + (count + 1) * off_size - 1
  let read = fn(i : Int) {
    let mut v = 0
    for k in 0..<off_size {
      v = (v << 8) | u8(b, offs + i * off_size + k)
    }
    v
  }
  let starts = Array::makei(count + 1, fn(i) { data + read(i) })
  { count, starts, end: starts[count] }
}

///|
fn CffIndex::get(self : CffIndex, i : Int) -> (Int, Int)? {
  if i < 0 || i >= self.count {
    None
  } else {
    Some((self.starts[i], self.starts[i + 1]))
  }
}

///|
fn CffIndex::bias(self : CffIndex) -> Int {
  if self.count < 1240 {
    107
  } else if self.count < 33900 {
    1131
  } else {
    32768
  }
}

///|
/// A DICT's operators with their integer operands (reals are read as their integer part: none the outlines use
/// are real); escaped operators are 1200 + the second byte.
fn cff_dict(b : Bytes, start : Int, end : Int) -> Map[Int, Array[Int]] {
  let out : Map[Int, Array[Int]] = {}
  let operands = []
  let mut p = start
  while p < end {
    let b0 = u8(b, p)
    p += 1
    if b0 == 28 {
      operands.push(i16(b, p))
      p += 2
    } else if b0 == 29 {
      operands.push(u32(b, p))
      p += 4
    } else if b0 == 30 {
      // a real: skip its nibbles
      while p < end {
        let v = u8(b, p)
        p += 1
        if (v & 0xF) == 0xF || (v >> 4) == 0xF {
          break
        }
      }
      operands.push(0)
    } else if b0 >= 32 && b0 <= 246 {
      operands.push(b0 - 139)
    } else if b0 >= 247 && b0 <= 250 {
      operands.push((b0 - 247) * 256 + u8(b, p) + 108)
      p += 1
    } else if b0 >= 251 && b0 <= 254 {
      operands.push(-(b0 - 251) * 256 - u8(b, p) - 108)
      p += 1
    } else {
      let op = if b0 == 12 {
        let o = 1200 + u8(b, p)
        p += 1
        o
      } else {
        b0
      }
      out[op] = operands.copy()
      operands.clear()
    }
  }
  out
}

///|
/// A CFF or CFF2 font's outlines.
priv struct CffFont {
  b : Bytes
  cff2 : Bool
  charstrings : CffIndex
  global_subrs : CffIndex
  /// each font dict's private dict (start, end); one when the font has no FDArray
  privates : Array[(Int, Int)]
  fd_select : Int
  var_store : Int
}

///|
fn Face::cff_font(self : Face) -> CffFont? {
  let b = self.data
  let (cff2, t) = match self.tables.get("CFF2") {
    Some((t, _)) => (true, t)
    None =>
      match self.tables.get("CFF ") {
        Some((t, _)) => (false, t)
        None => return None
      }
  }
  let (top, global_subrs) = if cff2 {
    let hdr = u8(b, t + 2)
    let len = u16(b, t + 3)
    let top = cff_dict(b, t + hdr, t + hdr + len)
    (top, cff_index(b, t + hdr + len, true))
  } else {
    let names = cff_index(b, t + u8(b, t + 2), false)
    let tops = cff_index(b, names.end, false)
    let strings = cff_index(b, tops.end, false)
    guard tops.get(0) is Some((s, e)) else { return None }
    (cff_dict(b, s, e), cff_index(b, strings.end, false))
  }
  guard top.get(17) is Some(cs) && cs.length() > 0 else { return None }
  let charstrings = cff_index(b, t + cs[0], cff2)
  let privates = []
  match top.get(1236) {
    Some(fda) if fda.length() > 0 => {
      let fds = cff_index(b, t + fda[0], cff2)
      for i in 0..<fds.count {
        let (s, e) = (fds.starts[i], fds.starts[i + 1])
        let d = cff_dict(b, s, e)
        match d.get(18) {
          Some([size, off, ..]) => privates.push((t + off, t + off + size))
          _ => privates.push((0, 0))
        }
      }
    }
    _ =>
      match top.get(18) {
        Some([size, off, ..]) => privates.push((t + off, t + off + size))
        _ => privates.push((0, 0))
      }
  }
  let fd_select = match top.get(1237) {
    Some([o, ..]) => t + o
    _ => 0
  }
  let var_store = match top.get(24) {
    Some([o, ..]) if cff2 => t + o + 2
    _ => 0
  }
  Some({ b, cff2, charstrings, global_subrs, privates, fd_select, var_store })
}

///|
fn CffFont::font_index(self : CffFont, glyph : Int) -> Int {
  let b = self.b
  let s = self.fd_select
  if s == 0 {
    return 0
  }
  match u8(b, s) {
    0 => u8(b, s + 1 + glyph)
    3 | 4 => {
      let wide = u8(b, s) == 4
      let (count, recs, size) = if wide { (u32(b, s + 1), s + 5, 6) } else { (u16(b, s + 1), s + 3, 3) }
      let first = fn(i : Int) { if wide { u32(b, recs + i * size) } else { u16(b, recs + i * size) } }
      let fd = fn(i : Int) { if wide { u16(b, recs + i * size + 4) } else { u8(b, recs + i * size + 2) } }
      let sentinel = first(count)
      let mut ix = 0
      while ix + 1 < count && first(ix + 1) <= glyph {
        ix += 1
      }
      if count == 0 || glyph < first(ix) || glyph >= sentinel {
        0
      } else {
        fd(ix)
      }
    }
    _ => 0
  }
}

///|
/// The Type 2 charstring evaluator's state.
priv struct CffEval {
  font : CffFont
  subrs : CffIndex
  /// the blend's scalars (Fixed) for the active vsindex, per region
  mut scalars : Array[Int]
  coords : Array[Int]
  values : FixedArray[Int]
  is_fixed : FixedArray[Bool]
  mut top : Int
  mut stack_ix : Int
  mut x : Int
  mut y : Int
  mut is_open : Bool
  mut seen_width : Bool
  mut stem_count : Int
  mut ops : Int
  out : Array[(Int, Array[Int])]
}

///|
fn CffEval::push(self : CffEval, v : Int, fixed : Bool) -> Bool {
  if self.top == 513 {
    return false
  }
  self.values[self.top] = v
  self.is_fixed[self.top] = fixed
  self.top += 1
  true
}

///|
fn CffEval::get_fixed(self : CffEval, i : Int) -> Int {
  if i < 0 || i >= 513 {
    0
  } else if self.is_fixed[i] {
    self.values[i]
  } else {
    self.values[i] << 16
  }
}

///|
fn CffEval::pop_index(self : CffEval) -> Int {
  if self.top > 0 {
    self.top -= 1
  }
  self.top
}

///|
fn CffEval::pop_fixed(self : CffEval) -> Int {
  self.get_fixed(self.pop_index())
}

///|
/// The top as an integer; None when it is a fixed number.
fn CffEval::pop_int(self : CffEval) -> Int? {
  let i = self.pop_index()
  if self.is_fixed[i] {
    None
  } else {
    Some(self.values[i])
  }
}

///|
fn CffEval::reset(self : CffEval) -> Unit {
  self.top = 0
  self.stack_ix = 0
}

///|
fn CffEval::emit(self : CffEval, kind : Int, pts : Array[Int]) -> Unit {
  self.out.push((kind, pts))
}

///|
fn CffEval::ensure_open(self : CffEval) -> Unit {
  if !self.is_open {
    self.emit(0, [0, 0])
    self.is_open = true
  }
}

///|
fn CffEval::line(self : CffEval) -> Unit {
  self.ensure_open()
  self.emit(1, [self.x, self.y])
}

///|
/// The point modes of read-fonts' emit_curves: 0 DxDy, 1 XDy, 2 DxY, 3 DxInitialY, 4 DLargerCoordDist,
/// 5/6 DxMaybeDy without/with dy, 7/8 MaybeDxDy without/with dx.
fn CffEval::curves(self : CffEval, modes : Array[Int]) -> Unit {
  let ix0 = self.x
  let iy0 = self.y
  let pts = []
  self.ensure_open()
  for mode in modes {
    let at = self.stack_ix
    let used = match mode {
      0 => {
        self.x += self.get_fixed(at)
        self.y += self.get_fixed(at + 1)
        2
      }
      1 => {
        self.y += self.get_fixed(at)
        1
      }
      2 => {
        self.x += self.get_fixed(at)
        1
      }
      3 => {
        self.x += self.get_fixed(at)
        self.y = iy0
        1
      }
      4 => {
        let d = self.get_fixed(at)
        if (self.x - ix0).abs() > (self.y - iy0).abs() {
          self.x += d
          self.y = iy0
        } else {
          self.y += d
          self.x = ix0
        }
        1
      }
      5 | 6 => {
        self.x += self.get_fixed(at)
        if mode == 6 {
          self.y += self.get_fixed(at + 1)
          2
        } else {
          1
        }
      }
      _ => {
        self.y += self.get_fixed(at)
        if mode == 8 {
          self.x += self.get_fixed(at + 1)
          2
        } else {
          1
        }
      }
    }
    self.stack_ix += used
    if pts.length() == 4 {
      self.emit(2, [pts[0], pts[1], pts[2], pts[3], self.x, self.y])
      pts.clear()
    } else {
      pts.push(self.x)
      pts.push(self.y)
    }
  }
}

///|
fn CffEval::read_width(self : CffEval) -> Unit {
  self.seen_width = true
}

///|
/// Evaluates a charstring; false on a broken one (Err in read-fonts). The flag says whether it ended (endchar or
/// return).
fn CffEval::run(self : CffEval, start : Int, end : Int, depth : Int) -> (Bool, Bool) {
  if depth > 10 {
    return (false, false)
  }
  let b = self.font.b
  let mut p = start
  let mut seen_endchar = false
  while p < end {
    self.ops += 1
    if self.ops > 1000000 {
      return (false, false)
    }
    let b0 = u8(b, p)
    p += 1
    if b0 == 28 {
      if !self.push(i16(b, p), false) {
        return (false, false)
      }
      p += 2
      continue
    }
    if b0 >= 32 && b0 <= 246 {
      if !self.push(b0 - 139, false) {
        return (false, false)
      }
      continue
    }
    if b0 >= 247 && b0 <= 250 {
      if !self.push((b0 - 247) * 256 + u8(b, p) + 108, false) {
        return (false, false)
      }
      p += 1
      continue
    }
    if b0 >= 251 && b0 <= 254 {
      if !self.push(-(b0 - 251) * 256 - u8(b, p) - 108, false) {
        return (false, false)
      }
      p += 1
      continue
    }
    if b0 == 255 {
      if !self.push(u32(b, p), true) {
        return (false, false)
      }
      p += 4
      continue
    }
    let op = if b0 == 12 {
      let o = 1200 + u8(b, p)
      p += 1
      o
    } else {
      b0
    }
    if op == 14 {
      seen_endchar = true
    }
    match self.operator(op, p, depth) {
      Some((cont, next)) => {
        p = next
        if !cont {
          break
        }
      }
      None => return (false, false)
    }
  }
  (true, seen_endchar)
}

///|
/// Applies an operator at `p` (after it); Some((go on, where to read next)) or None when it fails.
fn CffEval::operator(self : CffEval, op : Int, p : Int, depth : Int) -> (Bool, Int)? {
  let mut p = p
  match op {
    // flex
    1235 => {
      self.curves([0, 0, 0, 0, 0, 0])
      self.reset()
    }
    1234 => {
      self.curves([2, 0, 2, 2, 3, 2])
      self.reset()
    }
    1236 => {
      self.curves([0, 0, 2, 2, 0, 3])
      self.reset()
    }
    1237 => {
      self.curves([0, 0, 0, 0, 0, 4])
      self.reset()
    }
    15 =>
      // vsindex
      if self.font.cff2 {
        guard self.pop_int() is Some(i) else { return None }
        self.set_vsindex(i)
      }
    16 =>
      // blend
      if self.font.cff2 {
        if !self.blend() {
          return None
        }
      }
    11 => return Some((false, p))
    14 => {
      if (self.top == 1 || self.top == 5) && !self.seen_width {
        self.read_width()
      }
      self.seen_width = true
      // seac (an accented glyph by standard encoding codes) is not drawn
      return Some((false, p))
    }
    1 | 3 | 18 | 23 => {
      let mut len = self.top
      if (self.top & 1) != 0 && !self.seen_width {
        self.read_width()
        len = self.top - 1
      }
      self.seen_width = true
      self.stem_count += len / 2
      self.reset()
    }
    19 | 20 => {
      let mut len = self.top
      if (self.top & 1) != 0 && !self.seen_width {
        self.read_width()
        len = self.top - 1
      }
      self.seen_width = true
      self.stem_count += len / 2
      p += (self.stem_count + 7) / 8
      self.reset()
    }
    21 => {
      if self.top > 2 && !self.seen_width {
        self.read_width()
      }
      self.seen_width = true
      let dy = self.pop_fixed()
      let dx = self.pop_fixed()
      self.x += dx
      self.y += dy
      if !self.is_open {
        self.is_open = true
      } else {
        self.emit(3, [])
      }
      self.emit(0, [self.x, self.y])
      self.reset()
    }
    22 | 4 => {
      if self.top > 1 && !self.seen_width {
        self.read_width()
      }
      self.seen_width = true
      let d = self.pop_fixed()
      if op == 22 {
        self.x += d
      } else {
        self.y += d
      }
      if !self.is_open {
        self.is_open = true
      } else {
        self.emit(3, [])
      }
      self.emit(0, [self.x, self.y])
      self.reset()
    }
    5 => {
      let mut i = 0
      while i < self.top {
        self.x += self.get_fixed(i)
        self.y += self.get_fixed(i + 1)
        self.line()
        i += 2
      }
      self.reset()
    }
    6 | 7 => {
      let mut is_x = op == 6
      for i in 0..<self.top {
        let d = self.get_fixed(i)
        if is_x {
          self.x += d
        } else {
          self.y += d
        }
        is_x = !is_x
        self.line()
      }
      self.reset()
    }
    27 => {
      let count1 = self.top
      let count = count1 & (2 ^ -1)
      self.stack_ix = count1 - count
      while self.stack_ix < count {
        if ((count - self.stack_ix) & 1) != 0 {
          self.y += self.get_fixed(self.stack_ix)
          self.stack_ix += 1
        }
        self.curves([2, 0, 2])
      }
      self.reset()
    }
    26 => {
      let count1 = self.top
      let count = count1 & (2 ^ -1)
      self.stack_ix = count1 - count
      while self.stack_ix < count {
        if ((count - self.stack_ix) & 1) != 0 {
          self.x += self.get_fixed(self.stack_ix)
          self.stack_ix += 1
        }
        self.curves([1, 0, 1])
      }
      self.reset()
    }
    31 | 30 => {
      let count1 = self.top
      let count = count1 & (2 ^ -1)
      let mut horizontal = op == 31
      self.stack_ix = count1 - count
      while self.stack_ix < count {
        let last = count - self.stack_ix == 5
        if horizontal {
          self.curves([2, 0, if last { 8 } else { 7 }])
        } else {
          self.curves([1, 0, if last { 6 } else { 5 }])
        }
        horizontal = !horizontal
      }
      self.reset()
    }
    8 | 24 => {
      while self.top - self.stack_ix >= 6 {
        self.curves([0, 0, 0])
      }
      if op == 24 {
        self.x += self.get_fixed(self.stack_ix)
        self.y += self.get_fixed(self.stack_ix + 1)
        self.line()
      }
      self.reset()
    }
    25 => {
      while self.top - self.stack_ix > 6 {
        self.x += self.get_fixed(self.stack_ix)
        self.y += self.get_fixed(self.stack_ix + 1)
        self.line()
        self.stack_ix += 2
      }
      while self.top - self.stack_ix >= 6 {
        self.curves([0, 0, 0])
      }
      self.reset()
    }
    10 | 29 => {
      guard self.pop_int() is Some(index) else { return None }
      let subrs = if op == 10 { self.subrs } else { self.font.global_subrs }
      guard subrs.get(index + subrs.bias()) is Some((s, e)) else { return None }
      let (ok, _) = self.run(s, e, depth + 1)
      if !ok {
        return None
      }
    }
    1200 => ()
    1203 | 1204 | 1215 => {
      let b2 = self.pop_fixed()
      let a = self.pop_fixed()
      let r = match op {
        1203 => a != 0 && b2 != 0
        1204 => a != 0 || b2 != 0
        _ => a == b2
      }
      ignore(self.push(if r { 1 } else { 0 }, false))
    }
    1205 => {
      let a = self.pop_fixed()
      ignore(self.push(if a == 0 { 1 } else { 0 }, false))
    }
    1209 | 1214 => {
      let a = self.pop_fixed()
      let r = if a < -0x7FFFFFFF {
        0x7FFFFFFF
      } else if op == 1209 {
        a.abs()
      } else {
        -a
      }
      ignore(self.push(r, true))
    }
    1210 | 1211 => {
      let b2 = self.pop_fixed()
      let a = self.pop_fixed()
      ignore(self.push(if op == 1210 { a + b2 } else { a - b2 }, true))
    }
    1212 => {
      let bi = self.pop_index()
      let ai = self.pop_index()
      let a = self.get_fixed(ai)
      let b2 = self.get_fixed(bi)
      ignore(self.push(fx_div(a, b2), true))
    }
    1224 => {
      let b2 = self.pop_fixed()
      let a = self.pop_fixed()
      ignore(self.push(fx_mul(a, b2), true))
    }
    1226 => {
      let a = self.pop_fixed()
      ignore(self.push(fixed_sqrt(a), true))
    }
    1218 => ignore(self.pop_fixed())
    1227 => {
      let i = self.pop_index()
      let (v, f) = (self.values[i], self.is_fixed[i])
      ignore(self.push(v, f))
      ignore(self.push(v, f))
    }
    1228 => {
      if self.top < 2 {
        return None
      }
      let a = self.top - 1
      let (v, f) = (self.values[a], self.is_fixed[a])
      self.values[a] = self.values[a - 1]
      self.is_fixed[a] = self.is_fixed[a - 1]
      self.values[a - 1] = v
      self.is_fixed[a - 1] = f
    }
    1229 => {
      guard self.pop_int() is Some(index) else { return None }
      let len = self.top
      if len > 0 {
        let from = if index < 0 { len - 1 } else if index >= len { 0 } else { len - 1 - index }
        let v = self.get_fixed(from)
        ignore(self.push(v, true))
      }
    }
    1230 => {
      guard self.pop_int() is Some(shift) else { return None }
      guard self.pop_int() is Some(count) else { return None }
      if count >= 2 {
        if count > self.top {
          return None
        }
        let offset = self.top - count
        let s = if shift < 0 { -(-shift % count) } else { shift % count }
        if s != 0 {
          let vs = Array::makei(count, fn(i) { (self.values[offset + i], self.is_fixed[offset + i]) })
          for i in 0..<count {
            let j = ((i + s) % count + count) % count
            self.values[offset + j] = vs[i].0
            self.is_fixed[offset + j] = vs[i].1
          }
        }
      }
    }
    1220 | 1221 => {
      // put and get: a transient array the outlines here do not use
      if op == 1220 {
        ignore(self.pop_fixed())
        ignore(self.pop_fixed())
      } else {
        ignore(self.pop_fixed())
      }
    }
    1222 => {
      let c2 = self.pop_fixed()
      let c1 = self.pop_fixed()
      let a2 = self.pop_fixed()
      let a1 = self.pop_fixed()
      ignore(self.push(if c1 <= c2 { a1 } else { a2 }, true))
    }
    1201 | 1202 => self.reset()
    _ => self.reset()
  }
  Some((true, p))
}

///|
fn fixed_sqrt(v : Int) -> Int {
  if v <= 0 {
    return 0
  }
  let mut root = if v < 10 { v } else { v >> 1 }
  while true {
    let next = (root + fx_div(v, root) + 1) >> 1
    if next == root {
      return next
    }
    root = next
  }
  root
}

///|
fn CffEval::set_vsindex(self : CffEval, index : Int) -> Unit {
  let b = self.font.b
  let store = self.font.var_store
  self.scalars = []
  if store == 0 || index >= u16(b, store + 6) {
    return
  }
  let regions = store + u32(b, store + 2)
  let axis_count = u16(b, regions)
  let data = store + u32(b, store + 8 + index * 4)
  let n = u16(b, data + 4)
  self.scalars = Array::makei(n, fn(k) {
    let ri = u16(b, data + 6 + k * 2)
    if self.coords.length() == 0 {
      0
    } else {
      region_scalar(b, regions + 4 + ri * axis_count * 6, axis_count, self.coords)
    }
  })
}

///|
/// The blend operator: values plus their deltas times each region's scalar.
fn CffEval::blend(self : CffEval) -> Bool {
  guard self.pop_int() is Some(n) else { return false }
  if n > self.top {
    return false
  }
  let regions = self.scalars.length()
  let operands = n * (regions + 1)
  if self.top < operands {
    return false
  }
  let start = self.top - operands
  for i in start..<self.top {
    if !self.is_fixed[i] {
      self.values[i] = self.values[i] << 16
      self.is_fixed[i] = true
    }
  }
  for r in 0..<regions {
    let scalar = self.scalars[r]
    if scalar == 0 {
      continue
    }
    for v in 0..<n {
      let delta = self.values[start + n + regions * v + r]
      self.values[start + v] = self.values[start + v] + fx_mul(delta, scalar)
    }
  }
  self.top = start + n
  true
}

///|
/// A glyph's CFF outline in font units, as skrifa draws it unhinted and unscaled.
fn Face::cff_glyph_outline(self : Face, glyph : Int, coords : Array[Int]) -> Array[PathCmd]? {
  guard self.cff_font() is Some(font) else { return None }
  guard font.charstrings.get(glyph) is Some((s, e)) else { return None }
  let b = self.data
  let fd = font.font_index(glyph)
  let (ps, pe) = if fd < font.privates.length() { font.privates[fd] } else { (0, 0) }
  let private = cff_dict(b, ps, pe)
  let subrs = match private.get(19) {
    Some([o, ..]) => cff_index(b, ps + o, font.cff2)
    _ => { count: 0, starts: [], end: 0 }
  }
  let ev : CffEval = {
    font,
    subrs,
    scalars: [],
    coords,
    values: FixedArray::make(513, 0),
    is_fixed: FixedArray::make(513, false),
    top: 0,
    stack_ix: 0,
    x: 0,
    y: 0,
    is_open: false,
    seen_width: false,
    stem_count: 0,
    ops: 0,
    out: [],
  }
  if font.cff2 {
    let vs = match private.get(22) {
      Some([i, ..]) => i
      _ => 0
    }
    ev.set_vsindex(vs)
  }
  let (ok, ended) = ev.run(s, e, 0)
  if !ok {
    return None
  }
  if !font.cff2 && !ended {
    ignore(ev.operator(14, 0, 0))
  }
  if ev.is_open {
    ev.emit(3, [])
  }
  // TransformSink without a scale: each coordinate to whole units ((x × 1/64) >> 10, then << 16)
  let unit = fn(v : Int) { fx_mul(v, 0x400) >> 10 }
  // NopFilterSink: drops lines to where the pen already is, and the closing line back to the start
  let out : Array[PathCmd] = []
  let mut pending : (Int, Array[Int])? = None
  let mut start : (Int, Int)? = None
  let mut open = false
  let flush = fn(for_close : Bool) {
    match pending {
      Some((0, p)) =>
        if !for_close {
          open = true
          out.push(MoveTo(Float::from_int(p[0]), Float::from_int(p[1])))
          start = Some((p[0], p[1]))
        }
      Some((1, p)) =>
        if !for_close || start != Some((p[0], p[1])) {
          out.push(LineTo(Float::from_int(p[0]), Float::from_int(p[1])))
        }
      Some((_, p)) =>
        out.push(
          CubicTo(
            Float::from_int(p[0]),
            Float::from_int(p[1]),
            Float::from_int(p[2]),
            Float::from_int(p[3]),
            Float::from_int(p[4]),
            Float::from_int(p[5]),
          ),
        )
      None => ()
    }
    pending = None
  }
  for cmd in ev.out {
    let (kind, pts) = cmd
    let pts = pts.map(unit)
    match kind {
      0 => pending = Some((0, pts))
      1 => {
        let same = match pending {
          Some((k, p)) =>
            if k == 2 {
              p[4] == pts[0] && p[5] == pts[1]
            } else {
              p[0] == pts[0] && p[1] == pts[1]
            }
          None => false
        }
        if !same {
          flush(false)
          pending = Some((1, pts))
        }
      }
      2 => {
        flush(false)
        pending = Some((2, pts))
      }
      _ => {
        flush(true)
        if open {
          out.push(Close)
          open = false
        }
      }
    }
  }
  flush(true)
  if open {
    out.push(Close)
  }
  Some(out)
}
