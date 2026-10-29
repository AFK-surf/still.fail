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
  // (the bytes folded in as they come, no closure: what names a node is hashed for each node on every frame)
  let mut h = fnv_offset
  for ch in s {
    let c = ch.to_int()
    if c < 0x80 {
      h = (h ^ c.to_int64()) * fnv_prime
    } else if c < 0x800 {
      h = (h ^ (0xC0 | (c >> 6)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | (c & 0x3F)).to_int64()) * fnv_prime
    } else if c < 0x10000 {
      h = (h ^ (0xE0 | (c >> 12)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | ((c >> 6) & 0x3F)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | (c & 0x3F)).to_int64()) * fnv_prime
    } else {
      h = (h ^ (0xF0 | (c >> 18)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | ((c >> 12) & 0x3F)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | ((c >> 6) & 0x3F)).to_int64()) * fnv_prime
      h = (h ^ (0x80 | (c & 0x3F)).to_int64()) * fnv_prime
    }
  }
  h
}
