// A retained allocation is the positive control for the host's memory reading.
let held : Array[Array[Int]] = []

///|
pub fn run_round() -> Int {
  @kernel.memory_round()
}

///|
pub fn hold_control() -> Unit {
  held.push(Array::make(1048576, 0))
}

///|
pub fn release_control() -> Unit {
  held.clear()
}

///|
fn main { }
