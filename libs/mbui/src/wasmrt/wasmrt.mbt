// What a program run in classic Wasm by mbui's native shell gives the native host of its
// values, and takes of the host's (tools/wasmhost writes the calls that use it): where a string, bytes or an array lies
// in the program's memory (laid out as the native program has it: [rc][length], then what it holds), and a string or
// bytes the host answered, copied into one made here. Empty on the other targets.

///|
#borrow(s)
pub fn string_addr(s : String) -> Int = "(func (param $s i32) (result i32) (local.get $s))"

///|
#borrow(b)
pub fn bytes_addr(b : Bytes) -> Int = "(func (param $b i32) (result i32) (local.get $b))"

///|
#borrow(a)
pub fn doubles_addr(a : FixedArray[Double]) -> Int = "(func (param $a i32) (result i32) (local.get $a))"

///|
#borrow(a)
pub fn byte_array_addr(a : FixedArray[Byte]) -> Int = "(func (param $a i32) (result i32) (local.get $a))"

///|
#borrow(a)
pub fn ints_addr(a : FixedArray[Int]) -> Int = "(func (param $a i32) (result i32) (local.get $a))"

///|
fn take_string_into(at : Int) = "mbhost" "mbw_take_string"

///|
fn take_bytes_into(at : Int) = "mbhost" "mbw_take_bytes"

///|
/// The string the host answered last, `n` units long (what the call answered): made here and copied in by the host.
pub fn take_string(n : Int) -> String {
  let s = String::make(n, '\u{0}')
  take_string_into(string_addr(s))
  s
}

///|
/// The bytes the host answered last, `n` long.
pub fn take_bytes(n : Int) -> Bytes {
  let b = Bytes::make(n, b'\x00')
  take_bytes_into(bytes_addr(b))
  b
}

///|
/// A string `n` units long the host fills and gives on (a callback's argument): its program's export mbw_string's.
pub fn new_string(n : Int) -> String {
  String::make(n, '\u{0}')
}

///|
pub fn new_bytes(n : Int) -> Bytes {
  Bytes::make(n, b'\x00')
}

///|
/// The string the shell made at `at` (its export mbw_string's, given on as a callback's argument): the program's
/// own from here, let go of as it is.
pub fn string_at(at : Int) -> String = "(func (param $a i32) (result i32) (local.get $a))"

///|
pub fn bytes_at(at : Int) -> Bytes = "(func (param $a i32) (result i32) (local.get $a))"
