// mbui-render draws with Metal: on the JS target there is nothing to run.

///|
let supported = false

///|
fn arg(_name : String) -> String {
  ""
}

///|
fn init_offscreen(_w : Double, _h : Double, _scale : Double) -> Unit {
  ()
}

///|
fn draw(_inst : FixedArray[Double], _count : Int, _r : Double, _g : Double, _b : Double) -> Unit {
  ()
}

///|
fn read_text(_path : String) -> String {
  ""
}

///|
fn read_bytes(_path : String) -> Bytes {
  b""
}

///|
fn say(_s : String) -> Unit {
  ()
}

///|
fn spin(_ms : Double) -> Unit {
  ()
}

///|
fn snapshot(_path : String) -> Bool {
  false
}
