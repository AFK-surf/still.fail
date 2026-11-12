// A classic Wasm module's bytes read and written: LEB128 numbers, names, sections.

///|
fn[T] fail(why : String) -> T {
  @sys.eprintln("wasmgas: " + why)
  @sys.exit(2)
  panic()
}

///|
priv struct Reader {
  data : Bytes
  mut p : Int
}

///|
fn Reader::new(data : Bytes, p : Int) -> Reader {
  { data, p }
}

///|
fn Reader::byte(self : Reader) -> Int {
  if self.p >= self.data.length() {
    fail("the module ends early")
  }
  let b = self.data[self.p].to_int()
  self.p += 1
  b
}

///|
/// An unsigned LEB128 (a u32's, or a u64's in limits)
fn Reader::uint64(self : Reader) -> Int64 {
  let mut v = 0L
  let mut shift = 0
  while true {
    let b = self.byte()
    v = v | ((b & 0x7f).to_int64() << shift)
    if (b & 0x80) == 0 {
      break
    }
    shift += 7
    if shift > 63 {
      fail("a number too long at \{self.p}")
    }
  }
  v
}

///|
fn Reader::uint(self : Reader) -> Int {
  let v = self.uint64()
  if v > 0x7fffffffL {
    fail("a number too large at \{self.p}")
  }
  v.to_int()
}

///|
/// A signed LEB128 passed over (a constant, a block's type)
fn Reader::skip_signed(self : Reader) -> Unit {
  while (self.byte() & 0x80) != 0 {
    ()
  }
}

///|
/// A name: its bytes, as a String of their code units (the names counted by are ASCII)
fn Reader::name(self : Reader) -> String {
  let n = self.uint()
  if self.p + n > self.data.length() {
    fail("a name past the module's end")
  }
  let sb = StringBuilder()
  for i in 0..<n {
    sb.write_char(Int::unsafe_to_char(self.data[self.p + i].to_int()))
  }
  self.p += n
  sb.to_string()
}

///|
/// A table's or a memory's limits passed over
fn Reader::limits(self : Reader) -> Unit {
  let flags = self.uint()
  ignore(self.uint64())
  if (flags & 1) != 0 {
    ignore(self.uint64())
  }
}

///|
fn leb_u(out : @buffer.Buffer, v : Int64) -> Unit {
  let mut v = v
  while true {
    let b = (v & 0x7fL).to_int()
    v = v >> 7
    if v == 0L {
      out.write_byte(b.to_byte())
      break
    }
    out.write_byte((b | 0x80).to_byte())
  }
}

///|
fn leb_s(out : @buffer.Buffer, v : Int64) -> Unit {
  let mut v = v
  while true {
    let b = (v & 0x7fL).to_int()
    v = v >> 7
    if (v == 0L && (b & 0x40) == 0) || (v == -1L && (b & 0x40) != 0) {
      out.write_byte(b.to_byte())
      break
    }
    out.write_byte((b | 0x80).to_byte())
  }
}

///|
fn put(out : @buffer.Buffer, bytes : Array[Int]) -> Unit {
  for b in bytes {
    out.write_byte(b.to_byte())
  }
}

///|
fn section(out : @buffer.Buffer, id : Int, body : @buffer.Buffer) -> Unit {
  out.write_byte(id.to_byte())
  leb_u(out, body.length().to_int64())
  out.write_bytes(body.to_bytes())
}

///|
/// A function's name by its index (the name section's), the module's whole when it has none
fn function_names(data : Bytes) -> Map[Int, String] {
  let names = Map([])
  check_magic(data)
  let r = Reader::new(data, 8)
  while r.p < data.length() {
    let id = r.byte()
    let size = r.uint()
    let end = r.p + size
    if id == 0 {
      if r.name() == "name" {
        while r.p < end {
          let sub = r.byte()
          let n = r.uint()
          let sub_end = r.p + n
          if sub == 1 {
            let count = r.uint()
            for _ in 0..<count {
              let index = r.uint()
              names[index] = r.name()
            }
          }
          r.p = sub_end
        }
      }
    }
    r.p = end
  }
  names
}

///|
fn check_magic(data : Bytes) -> Unit {
  if data.length() < 8 ||
    data[0] != b'\x00' ||
    data[1] != b'a' ||
    data[2] != b's' ||
    data[3] != b'm' ||
    data[4] != b'\x01' {
    fail("not a classic Wasm module")
  }
}
