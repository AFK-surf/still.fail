// No film in a browser: what is drawn there is the web's, not a host's.

///|
let supported = false

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  ignore((w, h, scale))
}

///|
fn open(path : String, w : Int, h : Int, fps : Int) -> Bool {
  ignore((path, w, h, fps))
  false
}

///|
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Unit {
  ignore((inst, count, r, g, b))
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
fn spin(ms : Double) -> Unit {
  ignore(ms)
}

///|
fn ffi_arg(name : String) -> String {
  ignore(name)
  ""
}

///|
fn say(s : String) -> Unit {
  println(s)
}

///|
fn read_text(path : String) -> String {
  ignore(path)
  ""
}

///|
fn write_text(path : String, text : String) -> Bool {
  ignore((path, text))
  false
}

///|
fn exit(code : Int) -> Unit {
  ignore(code)
}
