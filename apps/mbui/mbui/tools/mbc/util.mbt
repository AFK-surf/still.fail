// Bytes as text (C source is bytes: what Python's str did with surrogateescape), sets, a stable sort, SHA-1, CRC-32.

///|
fn is_ident(c : Byte) -> Bool {
  (c >= b'a' && c <= b'z') ||
  (c >= b'A' && c <= b'Z') ||
  (c >= b'0' && c <= b'9') ||
  c == b'_' ||
  c == b'$'
}

///|
/// What an identifier starts with: [A-Za-z_$]
fn is_start(c : Byte) -> Bool {
  (c >= b'a' && c <= b'z') || (c >= b'A' && c <= b'Z') || c == b'_' || c == b'$'
}

///|
fn is_digit(c : Byte) -> Bool {
  c >= b'0' && c <= b'9'
}

///|
/// A regular expression's \w (a byte past ASCII: a letter's, mostly)
fn is_word(c : Byte) -> Bool {
  (c >= b'a' && c <= b'z') ||
  (c >= b'A' && c <= b'Z') ||
  (c >= b'0' && c <= b'9') ||
  c == b'_' ||
  c >= b'\x80'
}

///|
/// \s, str.strip()'s whitespace
fn is_space(c : Byte) -> Bool {
  c == b' ' || (c >= b'\t' && c <= b'\r') || (c >= b'\x1c' && c <= b'\x1f')
}

///|
/// \b between t[i - 1] and t[i]
fn boundary(t : BytesView, i : Int) -> Bool {
  let a = i > 0 && is_word(t[i - 1])
  let b = i < t.length() && is_word(t[i])
  a != b
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Bytes in the order of their bytes (Python's str order for UTF-8), not Bytes::compare's (length first)
fn bcmp(a : BytesView, b : BytesView) -> Int {
  let n = imin(a.length(), b.length())
  for i in 0..<n {
    let x = a[i]
    let y = b[i]
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  a.length() - b.length()
}

///|
fn sub(t : Bytes, i : Int, j : Int) -> Bytes {
  t[i:j].to_bytes()
}

///|
fn cat(parts : Array[Bytes]) -> Bytes {
  let buf = @buffer.new()
  for p in parts {
    buf.write_bytes(p)
  }
  buf.to_bytes()
}

///|
fn starts_at(t : BytesView, i : Int, s : Bytes) -> Bool {
  if i < 0 || i + s.length() > t.length() {
    return false
  }
  for k in 0..<s.length() {
    if t[i + k] != s[k] {
      return false
    }
  }
  true
}

///|
fn starts(t : BytesView, s : Bytes) -> Bool {
  starts_at(t, 0, s)
}

///|
fn ends(t : BytesView, s : Bytes) -> Bool {
  starts_at(t, t.length() - s.length(), s)
}

///|
/// str.find(s, from)
fn find(t : BytesView, s : Bytes, from : Int) -> Int {
  let n = t.length()
  let m = s.length()
  if m == 0 {
    return if from <= n { from } else { -1 }
  }
  let c0 = s[0]
  let mut i = imax(from, 0)
  while i + m <= n {
    if t[i] == c0 && starts_at(t, i, s) {
      return i
    }
    i += 1
  }
  -1
}

///|
fn find_byte(t : BytesView, c : Byte, from : Int) -> Int {
  for i in imax(from, 0)..<t.length() {
    if t[i] == c {
      return i
    }
  }
  -1
}

///|
fn rfind_byte(t : BytesView, c : Byte) -> Int {
  let mut i = t.length() - 1
  while i >= 0 {
    if t[i] == c {
      return i
    }
    i -= 1
  }
  -1
}

///|
fn contains(t : BytesView, s : Bytes) -> Bool {
  find(t, s, 0) >= 0
}

///|
fn has_byte(t : BytesView, c : Byte) -> Bool {
  find_byte(t, c, 0) >= 0
}

///|
fn count(t : BytesView, s : Bytes) -> Int {
  let mut n = 0
  let mut i = 0
  while true {
    let k = find(t, s, i)
    if k < 0 {
      break
    }
    n += 1
    i = k + s.length()
  }
  n
}

///|
fn lskip(t : BytesView, i : Int) -> Int {
  let mut k = i
  while k < t.length() && is_space(t[k]) {
    k += 1
  }
  k
}

///|
fn rskip(t : BytesView, j : Int) -> Int {
  let mut k = j
  while k > 0 && is_space(t[k - 1]) {
    k -= 1
  }
  k
}

///|
fn strip(t : Bytes) -> Bytes {
  let a = lskip(t, 0)
  let b = rskip(t, t.length())
  if a >= b {
    b""
  } else {
    sub(t, a, b)
  }
}

///|
fn lstrip(t : Bytes) -> Bytes {
  sub(t, lskip(t, 0), t.length())
}

///|
fn rstrip(t : Bytes) -> Bytes {
  sub(t, 0, rskip(t, t.length()))
}

///|
/// Python's text[i:j] (a negative bound from the end, clamped)
fn pyslice(t : Bytes, i : Int, j : Int) -> Bytes {
  let n = t.length()
  let a = imin(n, imax(0, if i < 0 { n + i } else { i }))
  let b = imin(n, imax(0, if j < 0 { n + j } else { j }))
  if a >= b {
    b""
  } else {
    sub(t, a, b)
  }
}

///|
fn replace_all(t : Bytes, from : Bytes, to : Bytes) -> Bytes {
  if from.length() == 0 {
    return t
  }
  let buf = @buffer.new()
  let mut i = 0
  while true {
    let k = find(t, from, i)
    if k < 0 {
      break
    }
    buf.write_bytesview(t[i:k])
    buf.write_bytes(to)
    i = k + from.length()
  }
  buf.write_bytesview(t[i:])
  buf.to_bytes()
}

///|
/// len() of the text Python decoded (characters: bytes that do not continue one)
fn clen(t : BytesView) -> Int {
  let mut n = 0
  for i in 0..<t.length() {
    if (t[i].to_int() & 0xC0) != 0x80 {
      n += 1
    }
  }
  n
}

///|
fn b(s : String) -> Bytes {
  utf8(s)
}

///|
fn bint(n : Int) -> Bytes {
  utf8(n.to_string())
}

///|
/// FNV-1a of t[s:e]
fn hash_range(t : BytesView, s : Int, e : Int) -> Int {
  let mut h = 0x811c9dc5
  for i in s..<e {
    h = (h ^ t[i].to_int()) * 0x01000193
  }
  h ^ (h >> 15)
}

///|
fn same_range(k : Bytes, t : BytesView, s : Int, e : Int) -> Bool {
  if k.length() != e - s {
    return false
  }
  for i in 0..<k.length() {
    if k[i] != t[s + i] {
      return false
    }
  }
  true
}

///|
/// A table keyed by byte strings, in the order keys came in, that a range of a text can be looked up in without
/// copying it (an identifier in a function's text: most are looked up, few added)
struct BTab[V] {
  keys : Array[Bytes]
  vals : Array[V]
  mut slots : FixedArray[Int] // index + 1 into keys; 0 empty
}

///|
fn[V] BTab::new() -> BTab[V] {
  { keys: [], vals: [], slots: FixedArray::make(16, 0) }
}

///|
fn[V] BTab::find_range(self : BTab[V], t : BytesView, s : Int, e : Int) -> Int {
  let mask = self.slots.length() - 1
  let mut i = hash_range(t, s, e) & mask
  while true {
    let k = self.slots[i]
    if k == 0 {
      return -1
    }
    if same_range(self.keys[k - 1], t, s, e) {
      return k - 1
    }
    i = (i + 1) & mask
  }
  -1
}

///|
fn[V] BTab::find(self : BTab[V], k : BytesView) -> Int {
  self.find_range(k, 0, k.length())
}

///|
fn[V] BTab::grow(self : BTab[V]) -> Unit {
  let n = self.slots.length() * 2
  let slots = FixedArray::make(n, 0)
  let mask = n - 1
  for idx, k in self.keys {
    let mut i = hash_range(k, 0, k.length()) & mask
    while slots[i] != 0 {
      i = (i + 1) & mask
    }
    slots[i] = idx + 1
  }
  self.slots = slots
}

///|
/// Adds k (as given: not copied) with v, or sets its value
fn[V] BTab::set(self : BTab[V], k : Bytes, v : V) -> Unit {
  let at = self.find(k)
  if at >= 0 {
    self.vals[at] = v
    return
  }
  if (self.keys.length() + 1) * 2 > self.slots.length() {
    self.grow()
  }
  self.keys.push(k)
  self.vals.push(v)
  let mask = self.slots.length() - 1
  let mut i = hash_range(k, 0, k.length()) & mask
  while self.slots[i] != 0 {
    i = (i + 1) & mask
  }
  self.slots[i] = self.keys.length()
}

///|
fn[V] BTab::get(self : BTab[V], k : BytesView) -> V? {
  let at = self.find(k)
  if at < 0 {
    None
  } else {
    Some(self.vals[at])
  }
}

///|
fn[V] BTab::length(self : BTab[V]) -> Int {
  self.keys.length()
}

///|
/// A set of byte strings, in the order they came in
struct BSet {
  t : BTab[Unit]
}

///|
fn BSet::new() -> BSet {
  { t: BTab::new() }
}

///|
fn BSet::of(xs : Array[Bytes]) -> BSet {
  let s = BSet::new()
  for x in xs {
    s.add(x)
  }
  s
}

///|
fn BSet::add(self : BSet, x : Bytes) -> Unit {
  if self.t.find(x) < 0 {
    self.t.set(x, ())
  }
}

///|
/// Adds t[s:e] (copied only when it is not there yet)
fn BSet::add_range(self : BSet, t : BytesView, s : Int, e : Int) -> Unit {
  if self.t.find_range(t, s, e) < 0 {
    self.t.set(t[s:e].to_bytes(), ())
  }
}

///|
fn BSet::has(self : BSet, x : BytesView) -> Bool {
  self.t.find(x) >= 0
}

///|
fn BSet::has_range(self : BSet, t : BytesView, s : Int, e : Int) -> Bool {
  self.t.find_range(t, s, e) >= 0
}

///|
fn BSet::size(self : BSet) -> Int {
  self.t.length()
}

///|
fn BSet::items(self : BSet) -> Array[Bytes] {
  self.t.keys.copy()
}

///|
fn BSet::add_all(self : BSet, o : BSet) -> Unit {
  for k in o.t.keys {
    self.add(k)
  }
}

///|
fn BSet::copy(self : BSet) -> BSet {
  let s = BSet::new()
  s.add_all(self)
  s
}

///|
fn BSet::minus(self : BSet, o : BSet) -> BSet {
  let s = BSet::new()
  for k in self.t.keys {
    if !o.has(k) {
      s.add(k)
    }
  }
  s
}

///|
fn BSet::inter(self : BSet, o : BSet) -> BSet {
  let s = BSet::new()
  for k in self.t.keys {
    if o.has(k) {
      s.add(k)
    }
  }
  s
}

///|
fn BSet::sorted(self : BSet) -> Array[Bytes] {
  sort_bytes(self.items())
}

///|
fn sort_bytes(a : Array[Bytes]) -> Array[Bytes] {
  stable_sort(a, fn(x, y) { bcmp(x, y) })
}

///|
/// Sorted as Python's sorted: stable
fn[T] stable_sort(a : Array[T], cmp : (T, T) -> Int) -> Array[T] {
  let n = a.length()
  let mut src = a.copy()
  let mut dst = a.copy()
  let mut width = 1
  while width < n {
    let mut lo = 0
    while lo < n {
      let mid = imin(lo + width, n)
      let hi = imin(lo + 2 * width, n)
      let mut i = lo
      let mut j = mid
      let mut k = lo
      while k < hi {
        if i < mid && (j >= hi || cmp(src[i], src[j]) <= 0) {
          dst[k] = src[i]
          i += 1
        } else {
          dst[k] = src[j]
          j += 1
        }
        k += 1
      }
      lo += 2 * width
    }
    let t = src
    src = dst
    dst = t
    width *= 2
  }
  src
}

///|
fn sorted_ints(a : Array[Int]) -> Array[Int] {
  stable_sort(a, fn(x, y) { x - y })
}

///|
/// SHA-1 of `data`, 20 bytes
fn sha1(data : BytesView) -> FixedArray[UInt] {
  let ml = data.length()
  let total = (ml + 8) / 64 * 64 + 64
  let msg = FixedArray::make(total, b'\x00')
  for i in 0..<ml {
    msg[i] = data[i]
  }
  msg[ml] = b'\x80'
  let bits = ml.to_int64() * 8L
  for k in 0..<8 {
    msg[total - 1 - k] = (bits >> (8 * k)).to_byte()
  }
  let h = FixedArray::from_array([
    0x67452301U, 0xEFCDAB89U, 0x98BADCFEU, 0x10325476U, 0xC3D2E1F0U,
  ])
  let w = FixedArray::make(80, 0U)
  let mut off = 0
  while off < total {
    for t in 0..<16 {
      let p = off + t * 4
      w[t] = (msg[p].to_uint() << 24) |
        (msg[p + 1].to_uint() << 16) |
        (msg[p + 2].to_uint() << 8) |
        msg[p + 3].to_uint()
    }
    for t in 16..<80 {
      let x = w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16]
      w[t] = (x << 1) | (x >> 31)
    }
    let mut a = h[0]
    let mut bb = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    for t in 0..<80 {
      let (f, k) = if t < 20 {
        ((bb & c) | (bb.lnot() & d), 0x5A827999U)
      } else if t < 40 {
        (bb ^ c ^ d, 0x6ED9EBA1U)
      } else if t < 60 {
        ((bb & c) | (bb & d) | (c & d), 0x8F1BBCDCU)
      } else {
        (bb ^ c ^ d, 0xCA62C1D6U)
      }
      let tmp = ((a << 5) | (a >> 27)) + f + e + k + w[t]
      e = d
      d = c
      c = (bb << 30) | (bb >> 2)
      bb = a
      a = tmp
    }
    h[0] = h[0] + a
    h[1] = h[1] + bb
    h[2] = h[2] + c
    h[3] = h[3] + d
    h[4] = h[4] + e
    off += 64
  }
  h
}

///|
/// The first `n` hex digits of `data`'s SHA-1
fn sha1_hex(data : BytesView, n : Int) -> Bytes {
  let h = sha1(data)
  let hex = b"0123456789abcdef"
  let buf = @buffer.new()
  for i in 0..<n {
    let word = h[i / 8]
    let nib = (word >> (28 - 4 * (i % 8))) & 0xFU
    buf.write_byte(hex[nib.reinterpret_as_int()])
  }
  buf.to_bytes()
}

///|
let crc_table : FixedArray[UInt] = {
  let t = FixedArray::make(256, 0U)
  for i in 0..<256 {
    let mut c = i.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    t[i] = c
  }
  t
}

///|
/// zlib.crc32
fn crc32(data : BytesView) -> UInt {
  let mut c = 0xFFFFFFFFU
  for i in 0..<data.length() {
    c = crc_table[((c ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^
      (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}
