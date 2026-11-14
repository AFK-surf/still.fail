// What the reader of an event stream (sse.mbt) does to many bytes at once, where MoonBit is compiled (native): its
// own loops and its copy.

///|
/// `chunk` put in `to` from `at` on, without its CRs: where it then ends.
fn put(to : FixedArray[Byte], at : Int, chunk : Bytes) -> Int {
  let mut end = at
  for b in chunk {
    if b != b'\r' {
      to[end] = b
      end = end + 1
    }
  }
  end
}

///|
/// `from`'s bytes `start` to `end` at the front of `to`, which may be `from`.
fn moved(to : FixedArray[Byte], from : FixedArray[Byte], start : Int, end : Int) -> Unit {
  to.unsafe_blit(0, from, start, end - start)
}

///|
/// Where the first newline of `held` is from `from` on and before `end`, -1 where none is.
fn newline(held : FixedArray[Byte], from : Int, end : Int) -> Int {
  for i = from; i < end; i = i + 1 {
    if held[i] == b'\n' {
      return i
    }
  }
  -1
}
