// A hash that is the same in every run, on every target (FNV-1a, 64 bits, over a string's UTF-8 bytes): what a value
// made from a hash is made by (an id, a file's name, a seed), where MoonBit's own `hash()` is seeded anew in each
// process and differs between js and native (detlint's builtin-hash).

///|
let fnv_offset : Int64 = -3750763034362895579L

///|
let fnv_prime : Int64 = 1099511628211L

///|
/// `data`'s FNV-1a (64 bits): the same for the same bytes in every run and on every target.
pub fn stable_hash_bytes(data : Bytes) -> Int64 {
  let mut h = fnv_offset
  for b in data {
    h = (h ^ b.to_int64()) * fnv_prime
  }
  h
}

///|
/// `s`'s FNV-1a (64 bits) over its UTF-8 bytes: the same for the same words in every run and on every target.
pub fn stable_hash(s : String) -> Int64 {
  let mut h = fnv_offset
  let byte = fn(b : Int) { h = (h ^ b.to_int64()) * fnv_prime }
  for ch in s {
    let c = ch.to_int()
    if c < 0x80 {
      byte(c)
    } else if c < 0x800 {
      byte(0xC0 | (c >> 6))
      byte(0x80 | (c & 0x3F))
    } else if c < 0x10000 {
      byte(0xE0 | (c >> 12))
      byte(0x80 | ((c >> 6) & 0x3F))
      byte(0x80 | (c & 0x3F))
    } else {
      byte(0xF0 | (c >> 18))
      byte(0x80 | ((c >> 12) & 0x3F))
      byte(0x80 | ((c >> 6) & 0x3F))
      byte(0x80 | (c & 0x3F))
    }
  }
  h
}
