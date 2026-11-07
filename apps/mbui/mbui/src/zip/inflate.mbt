// Raw DEFLATE decoding uses the standard library; gzip preserves its first-member contract.

///|
/// Raw DEFLATE from `start`; trailing container bytes are left unread. `size` is an allocation hint, never an output limit.
pub fn inflate(data : Bytes, start? : Int = 0, size? : Int = 0) -> Bytes? {
  inflate_at(data, start, size).map(fn(r) { r.0 })
}

///|
fn inflate_at(data : Bytes, start : Int, size : Int) -> (Bytes, Int)? {
  if start < 0 || start >= data.length() { return None }
  // Container lengths are untrusted; large outputs grow only as the decoder produces them.
  if size > 0 && size <= 16 * 1024 * 1024 {
    let output = FixedArray::make(size, b'\x00')
    let decoded = try { Some(@flate.Decompressor().decompress_into(data[start:], output.mut_view(), mode=Prefix)) } catch { _ => None }
    if decoded is Some(result) {
      let bytes = Bytes::from_fixedarray(output)
      return Some((bytes[:result.produced].to_owned(), start + result.consumed))
    }
  }
  try {
    let decoded = @flate.inflate_prefix(data[start:])
    Some((decoded.data, start + decoded.consumed))
  } catch { _ => None }
}

///|
/// The file gzipped in `data` (RFC 1952: its first member), made whole; None where it is not gzip, is damaged, or its
/// size or CRC-32 is not what it says.
pub fn gunzip(data : Bytes) -> Bytes? {
  let n = data.length()
  if n < 18 || data[0] != b'\x1f' || data[1] != b'\x8b' || data[2] != b'\x08' {
    return None
  }
  let flags = data[3].to_int()
  let mut at = 10
  // FEXTRA: its length, then it
  if (flags & 4) != 0 {
    if at + 2 > n {
      return None
    }
    at += 2 + (data[at].to_int() | (data[at + 1].to_int() << 8))
  }
  // FNAME, FCOMMENT: each to its zero
  for flag in [8, 16] {
    if (flags & flag) != 0 {
      while at < n && data[at] != b'\x00' {
        at += 1
      }
      at += 1
    }
  }
  // FHCRC
  if (flags & 2) != 0 {
    at += 2
  }
  if at >= n {
    return None
  }
  let said = le32(data, n - 4)
  match inflate_at(data, at, said) {
    Some((out, end)) => {
      if end + 8 > n || le32(data, end + 4) != out.length() || crc32(out) != le32(data, end).reinterpret_as_uint() {
        return None
      }
      Some(out)
    }
    None => None
  }
}

///|
fn le32(data : Bytes, at : Int) -> Int {
  data[at].to_int() |
  (data[at + 1].to_int() << 8) |
  (data[at + 2].to_int() << 16) |
  (data[at + 3].to_int() << 24)
}

///|
let crc_table : FixedArray[UInt] = FixedArray::makei(256, fn(i) {
  let mut c = i.reinterpret_as_uint()
  for _ in 0..<8 {
    c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
  }
  c
})

///|
/// The CRC-32 of `data` (gzip's, zlib's crc32).
pub fn crc32(data : Bytes) -> UInt {
  let mut c = 0xFFFFFFFFU
  for i in 0..<data.length() {
    c = crc_table[((c ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}
