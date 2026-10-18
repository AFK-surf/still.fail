// Browser host: web/host.js defines globalThis.__mbhost (canvas, WebGL2,
// canvas-2D text, a hidden textarea for input methods).

extern "js" fn js_run(
  title : String,
  frame : FuncRef[(Double, Double, Double, Double) -> Unit],
  pointer : FuncRef[(Int, Double, Double, Int) -> Unit],
  wheel : FuncRef[(Double, Double, Double, Double, Int) -> Unit],
  key : FuncRef[(Int, Int) -> Unit],
  text : FuncRef[(Int, String, Int, Int) -> Unit],
) -> Unit =
  #|(t, f, p, w, k, x) => globalThis.__mbhost.run(t, f, p, w, k, x)

extern "js" fn js_now() -> Double =
  #|() => performance.now()

extern "js" fn js_request_frame() -> Unit =
  #|() => globalThis.__mbhost.requestFrame()

extern "js" fn js_wake_after(ms : Double) -> Unit =
  #|(ms) => globalThis.__mbhost.wakeAfter(ms)

extern "js" fn js_font_metrics(
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Unit =
  #|(s, w, o) => globalThis.__mbhost.fontMetrics(s, w, o)

extern "js" fn js_shape(
  text : String,
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Int =
  #|(t, s, w, o) => globalThis.__mbhost.shape(t, s, w, o)

extern "js" fn js_glyph(key : Int, out : FixedArray[Double]) -> Unit =
  #|(k, o) => globalThis.__mbhost.glyph(k, o)

extern "js" fn js_atlas_generation() -> Int =
  #|() => globalThis.__mbhost.atlasGeneration()

extern "js" fn js_present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit =
  #|(buf, n, r, g, b) => globalThis.__mbhost.present(buf, n, r, g, b)

extern "js" fn js_set_ime(
  active : Bool,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  text : String,
  sel_start : Int,
  sel_end : Int,
) -> Unit =
  #|(a, x, y, w, h, t, s, e) => globalThis.__mbhost.setIme(a, x, y, w, h, t, s, e)

extern "js" fn js_clipboard_set(s : String) -> Unit =
  #|(s) => globalThis.__mbhost.clipboardSet(s)

extern "js" fn js_log(s : String) -> Unit =
  #|(s) => globalThis.__mbhost.log(s)

extern "js" fn js_bench_mode() -> Int =
  #|() => globalThis.__mbhost.benchMode()

extern "js" fn js_exit(code : Int) -> Unit =
  #|(c) => globalThis.__mbhost.exit(c)

extern "js" fn js_mem_bytes() -> Double =
  #|() => globalThis.__mbhost.memBytes()

///|
pub fn run(
  title : String,
  frame : FuncRef[(Double, Double, Double, Double) -> Unit],
  pointer : FuncRef[(Int, Double, Double, Int) -> Unit],
  wheel : FuncRef[(Double, Double, Double, Double, Int) -> Unit],
  key : FuncRef[(Int, Int) -> Unit],
  text : FuncRef[(Int, String, Int, Int) -> Unit],
) -> Unit {
  js_run(title, frame, pointer, wheel, key, text)
}

///|
pub fn now() -> Double {
  js_now()
}

///|
pub fn request_frame() -> Unit {
  js_request_frame()
}

///|
pub fn wake_after(ms : Double) -> Unit {
  js_wake_after(ms)
}

///|
pub fn font_metrics(size : Double, weight : Int, out : FixedArray[Double]) -> Unit {
  js_font_metrics(size, weight, out)
}

///|
pub fn shape(
  text : String,
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Int {
  js_shape(text, size, weight, out)
}

///|
pub fn glyph(key : Int, out : FixedArray[Double]) -> Unit {
  js_glyph(key, out)
}

///|
pub fn atlas_generation() -> Int {
  js_atlas_generation()
}

///|
pub fn present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  js_present(buf, count, r, g, b)
}

///|
pub fn set_ime(
  active : Bool,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  text : String,
  sel_start : Int,
  sel_end : Int,
) -> Unit {
  js_set_ime(active, x, y, w, h, text, sel_start, sel_end)
}

///|
pub fn clipboard_set(s : String) -> Unit {
  js_clipboard_set(s)
}

///|
pub fn log(s : String) -> Unit {
  js_log(s)
}

///|
pub fn bench_mode() -> Int {
  js_bench_mode()
}

///|
pub fn exit(code : Int) -> Unit {
  js_exit(code)
}

///|
pub fn mem_bytes() -> Double {
  js_mem_bytes()
}
