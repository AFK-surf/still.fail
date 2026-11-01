// No film in a browser: what is drawn there is the web's, not a host's.

///|
let supported = false

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  ignore((w, h, scale))
}

///|
fn set_offscreen_view(w : Double, h : Double, scale : Double) -> Unit {
  ignore((w, h, scale))
}

///|
fn draw_timed(
  inst : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
  parts : Array[(Double, Double, Double, Double)],
  out : FixedArray[Double],
) -> Unit {
  ignore((inst, count, r, g, b, parts))
  out[0] = 0.0
  out[1] = 0.0
}

///|
fn now_ms() -> Double {
  0.0
}

///|
fn open(path : String, w : Int, h : Int, fps : Int) -> Bool {
  ignore((path, w, h, fps))
  false
}

///|
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Bool {
  ignore((inst, count, r, g, b))
  false
}

///|
fn put_frame(k : Int) -> Bool {
  ignore(k)
  false
}

///|
fn close(frames : Int) -> Bool {
  ignore(frames)
  false
}

///|
fn finish(publish : Bool) -> Bool {
  ignore(publish)
  false
}

///|
fn snapshot(path : String) -> Bool {
  ignore(path)
  false
}

///|
fn spin(ms : Double) -> Unit {
  ignore(ms)
}

///|
fn ffi_arg(name : String) -> String {
  ignore(name)
  ""
}

///|
/// (for a film program too: a tool's output and its files)
pub fn say(s : String) -> Unit {
  println(s)
}

///|
/// (for a film program too: a tool's output and its files)
pub fn read_text(path : String) -> String {
  ignore(path)
  ""
}

///|
/// (for a film program too: a tool's output and its files)
pub fn write_text(path : String, text : String) -> Bool {
  ignore((path, text))
  false
}

///|
/// (for a film program too: a tool's output and its files)
pub fn exit(code : Int) -> Unit {
  ignore(code)
}
