// The bench draws with Metal: on the JS target there is nothing to run.

///|
let supported = false

///|
fn init_offscreen(_w : Double, _h : Double, _scale : Double) -> Unit {
  ()
}

///|
fn draw_timed(_inst : FixedArray[Double], _count : Int, out : FixedArray[Double]) -> Unit {
  out[0] = 0.0
  out[1] = 0.0
}

///|
fn cpu_ms() -> Double {
  0.0
}

///|
fn unix_time() -> Double {
  0.0
}

///|
fn append_line(_path : String, _line : String) -> Bool {
  false
}

///|
fn status(_s : String) -> Unit {
  ()
}

///|
fn snapshot(_path : String) -> Unit {
  ()
}
