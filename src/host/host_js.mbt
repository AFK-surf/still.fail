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

extern "js" fn js_event_time() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.eventTime) ? globalThis.__mbhost.eventTime() : -1

extern "js" fn js_request_frame() -> Unit =
  #|() => globalThis.__mbhost.requestFrame()

extern "js" fn js_wake_after(ms : Double) -> Unit =
  #|(ms) => globalThis.__mbhost.wakeAfter(ms)

extern "js" fn js_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit =
  #|(s, w, st, o) => globalThis.__mbhost.fontMetrics(s, w, st, o)

extern "js" fn js_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int =
  #|(t, s, w, st, o) => globalThis.__mbhost.shape(t, s, w, st, o)

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

extern "js" fn js_set_back(
  back : FuncRef[(Int, Double, Double, Int) -> Unit],
) -> Unit =
  #|(b) => globalThis.__mbhost && globalThis.__mbhost.setBack && globalThis.__mbhost.setBack(b)

extern "js" fn js_back_enabled(on : Bool) -> Unit =
  #|(on) => globalThis.__mbhost && globalThis.__mbhost.backEnabled && globalThis.__mbhost.backEnabled(on)

extern "js" fn js_env(name : String) -> String =
  #|(n) => (typeof location !== "undefined" && new URLSearchParams(location.search).get(n)) || ""

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
/// When the input event being delivered happened, on now()'s clock (ms);
/// negative when the host doesn't say.
pub fn event_time() -> Double {
  js_event_time()
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser.
pub fn platform() -> Int {
  4
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
pub fn font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  js_font_metrics(size, weight, style, out)
}

///|
pub fn shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  js_shape(text, size, weight, style, out)
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

///|
/// Where the system's back goes (host_native.mbt `set_back`); in a browser:
/// Alt+Left and a mouse's back button.
pub fn set_back(back : FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit {
  js_set_back(back)
}

///|
pub fn back_enabled(on : Bool) -> Unit {
  js_back_enabled(on)
}

///|
/// The page's query parameter `name` ("" when there is none).
pub fn env(name : String) -> String {
  js_env(name)
}

///|
extern "js" fn js_image_load(src : String, max_px : Int) -> Int =
  #|(s, m) => globalThis.__mbhost.imageLoad(s, m)

///|
extern "js" fn js_image_load_bytes(data : Bytes, max_px : Int) -> Int =
  #|(d, m) => globalThis.__mbhost.imageLoadBytes(d, m)

///|
extern "js" fn js_image_info(id : Int, out : FixedArray[Double]) -> Int =
  #|(i, o) => globalThis.__mbhost.imageInfo(i, o)

///|
extern "js" fn js_image_free(id : Int) -> Unit =
  #|(i) => globalThis.__mbhost.imageFree(i)

///|
pub fn image_load(src : String, max_px : Int) -> Int {
  js_image_load(src, max_px)
}

///|
pub fn image_load_bytes(data : Bytes, max_px : Int) -> Int {
  js_image_load_bytes(data, max_px)
}

///|
pub fn image_info(id : Int, out : FixedArray[Double]) -> Int {
  js_image_info(id, out)
}

///|
pub fn image_free(id : Int) -> Unit {
  js_image_free(id)
}

// A sign-in in the browser that comes back here (browser_login.mbt): a page cannot listen.

///|
fn bl_start(_path : String) -> Int {
  0
}

///|
fn bl_port(_id : Int) -> Int {
  0
}

///|
fn bl_open(_id : Int, _url : String) -> Int {
  0
}

///|
fn bl_back(_id : Int) -> String {
  ""
}

///|
fn bl_end(_id : Int) -> Unit {

}
