// What a program run in Wasm GC by mbui's native shell (src/host/wasm_shell.c) gives the native host of its values,
// and takes of the host's: the same calls as wasmrt.mbt's on classic Wasm, over a linear memory the shell gives the
// program (the main's `import-memory`, env.memory), as the program's GC objects lie in no memory the shell reads.
// A value given is copied into that memory, laid out as a classic program's is ([length], then what it holds, its
// place what the call is given), for as long as the call (mark, settle); an array the host writes into is copied back
// as the call returns. A string or bytes the host answers is copied in where the program makes room for it (take_*),
// and one it gives a callback is laid where the program's mbw_string said (new_string_at), taken as it is read.

///|
fn load_i32(at : Int) -> Int = "(func (param i32) (result i32) (local.get 0) (i32.load))"

///|
fn load_u16(at : Int) -> Int = "(func (param i32) (result i32) (local.get 0) (i32.load16_u))"

///|
fn load_u8(at : Int) -> Int = "(func (param i32) (result i32) (local.get 0) (i32.load8_u))"

///|
fn load_f64(at : Int) -> Double = "(func (param i32) (result f64) (local.get 0) (f64.load))"

///|
fn store_i32(at : Int, v : Int) = "(func (param i32) (param i32) (local.get 0) (local.get 1) (i32.store))"

///|
fn store_u16(at : Int, v : Int) = "(func (param i32) (param i32) (local.get 0) (local.get 1) (i32.store16))"

///|
fn store_u8(at : Int, v : Int) = "(func (param i32) (param i32) (local.get 0) (local.get 1) (i32.store8))"

///|
fn store_f64(at : Int, v : Double) = "(func (param i32) (param f64) (local.get 0) (local.get 1) (f64.store))"

///|
fn memory_pages() -> Int = "(func (result i32) (memory.size))"

///|
fn memory_grow(pages : Int) -> Int = "(func (param i32) (result i32) (local.get 0) (memory.grow))"

///|
/// Where the program's room in the memory begins (what is below it the shell's own).
let room_base : Int = 1024 * 1024

///|
/// Where the room is taken up to.
// kept across runs: the program's one memory's
let room_top : Ref[Int] = Ref(room_base)

///|
/// What each call under way laid out: where the room stood as it began, and how many copies back it had.
// kept across runs: as deep as calls are nested
let marks : Array[(Int, Int)] = []

///|
/// What the host wrote into arrays given it, copied back into them as their call returns.
// kept across runs: emptied as each call settles
let backs : Array[() -> Unit] = []

///|
/// Strings and bytes laid out for a callback not taken yet.
// kept across runs: as many as the shell gave and the program has not read
let given : Ref[Int] = Ref(0)

///|
/// `bytes` of room, 8-aligned, the memory grown as it needs.
fn reserve(bytes : Int) -> Int {
  let at = (room_top.val + 7) & -8
  let end = at + bytes
  room_top.val = end
  let have = memory_pages() * 65536
  if end > have {
    if memory_grow((end - have + 65535) / 65536) < 0 {
      abort("wasmrt: no more memory for \{bytes} bytes")
    }
  }
  at
}

///|
/// The room let go of where nothing is under way or given out.
fn room_idle() -> Unit {
  if marks.is_empty() && given.val == 0 {
    room_top.val = room_base
  }
}

///|
/// A call begins that lays values out: what it lays out let go of at its settle.
pub fn mark() -> Int {
  marks.push((room_top.val, backs.length()))
  marks.length()
}

///|
/// The call begun at `m` returned: what the host wrote into arrays it was given copied back, its room let go of.
pub fn settle(m : Int) -> Unit {
  guard marks.length() == m else { abort("wasmrt: settle \{m} with \{marks.length()} calls under way") }
  let (top, b) = marks.unsafe_pop()
  for i in b..<backs.length() {
    (backs[i])()
  }
  backs.truncate(b)
  room_top.val = top
  room_idle()
}

///|
/// `n` units and their length laid out: where the units begin.
fn laid(n : Int, unit : Int) -> Int {
  let at = reserve(4 + n * unit) + 4
  store_i32(at - 4, n)
  at
}

///|
pub fn string_addr(s : String) -> Int {
  let n = s.length()
  let at = laid(n, 2)
  for i in 0..<n {
    store_u16(at + i * 2, s.unsafe_charcode_at(i))
  }
  at
}

///|
pub fn bytes_addr(b : Bytes) -> Int {
  let n = b.length()
  let at = laid(n, 1)
  for i in 0..<n {
    store_u8(at + i, b[i].to_int())
  }
  at
}

///|
pub fn doubles_addr(a : FixedArray[Double]) -> Int {
  let n = a.length()
  let at = laid(n, 8)
  for i in 0..<n {
    store_f64(at + i * 8, a[i])
  }
  backs.push(fn() { for i in 0..<n { a[i] = load_f64(at + i * 8) } })
  at
}

///|
pub fn byte_array_addr(a : FixedArray[Byte]) -> Int {
  let n = a.length()
  let at = laid(n, 1)
  for i in 0..<n {
    store_u8(at + i, a[i].to_int())
  }
  backs.push(fn() { for i in 0..<n { a[i] = load_u8(at + i).to_byte() } })
  at
}

///|
pub fn ints_addr(a : FixedArray[Int]) -> Int {
  let n = a.length()
  let at = laid(n, 4)
  for i in 0..<n {
    store_i32(at + i * 4, a[i])
  }
  backs.push(fn() { for i in 0..<n { a[i] = load_i32(at + i * 4) } })
  at
}

///|
fn take_string_into(at : Int) = "mbhost" "mbw_take_string"

///|
fn take_bytes_into(at : Int) = "mbhost" "mbw_take_bytes"

///|
/// The units at `at`, `n` of them, as a string of the program's.
fn string_of(at : Int, n : Int) -> String {
  let b = StringBuilder::new(size_hint=n)
  for i in 0..<n {
    b.write_char(Int::unsafe_to_char(load_u16(at + i * 2)))
  }
  b.to_string()
}

///|
fn bytes_of(at : Int, n : Int) -> Bytes {
  Bytes::makei(n, fn(i) { load_u8(at + i).to_byte() })
}

///|
/// The string the host answered last, `n` units long (what the call answered): copied in where room was made for it.
pub fn take_string(n : Int) -> String {
  let top = room_top.val
  let at = reserve(n * 2)
  take_string_into(at)
  let s = string_of(at, n)
  room_top.val = top
  room_idle()
  s
}

///|
pub fn take_bytes(n : Int) -> Bytes {
  let top = room_top.val
  let at = reserve(n)
  take_bytes_into(at)
  let b = bytes_of(at, n)
  room_top.val = top
  room_idle()
  b
}

///|
/// Room for a string `n` units long the shell fills and gives on (a callback's argument): the program's export
/// mbw_string's place, read by string_at.
pub fn new_string_at(n : Int) -> Int {
  given.val += 1
  laid(n, 2)
}

///|
pub fn new_bytes_at(n : Int) -> Int {
  given.val += 1
  laid(n, 1)
}

///|
/// The string the shell laid at `at` (new_string_at's), the program's own from here.
pub fn string_at(at : Int) -> String {
  let n = load_i32(at - 4)
  let s = string_of(at, n)
  taken(at, n * 2)
  s
}

///|
/// What was laid at `at`, `bytes` long, for a callback, read: its room let go of where it is the last taken (a
/// callback's arguments are read as it is called, the shell's run under way the whole time: nothing settles).
fn taken(at : Int, bytes : Int) -> Unit {
  given.val -= 1
  if room_top.val == at + bytes {
    room_top.val = at - 4
  }
  room_idle()
}

///|
pub fn bytes_at(at : Int) -> Bytes {
  let n = load_i32(at - 4)
  let b = bytes_of(at, n)
  taken(at, n)
  b
}
