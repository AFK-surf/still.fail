// Native host: the C/Objective-C side lives in apple_*.m and mac_app.m (and
// ios_app.m, built by scripts/ios.sh). Every call here is a plain C call.

#borrow(title)
extern "C" fn ffi_run(
  title : String,
  frame : FuncRef[(Double, Double, Double, Double) -> Unit],
  pointer : FuncRef[(Int, Double, Double, Int) -> Unit],
  wheel : FuncRef[(Double, Double, Double, Double, Int) -> Unit],
  key : FuncRef[(Int, Int) -> Unit],
  text : FuncRef[(Int, String, Int, Int) -> Unit],
) -> Unit = "mb_host_run"

extern "C" fn ffi_now() -> Double = "mb_host_now"

extern "C" fn ffi_request_frame() -> Unit = "mb_host_request_frame"

extern "C" fn ffi_wake_after(ms : Double) -> Unit = "mb_host_wake_after"

#borrow(out)
extern "C" fn ffi_font_metrics(
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Unit = "mb_host_font_metrics"

#borrow(text, out)
extern "C" fn ffi_shape(
  text : String,
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Int = "mb_host_shape"

#borrow(out)
extern "C" fn ffi_glyph(key : Int, out : FixedArray[Double]) -> Unit = "mb_host_glyph"

extern "C" fn ffi_atlas_generation() -> Int = "mb_host_atlas_generation"

#borrow(buf)
extern "C" fn ffi_present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit = "mb_host_present"

#borrow(text)
extern "C" fn ffi_set_ime(
  active : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  text : String,
  sel_start : Int,
  sel_end : Int,
) -> Unit = "mb_host_set_ime"

#borrow(s)
extern "C" fn ffi_clipboard_set(s : String) -> Unit = "mb_host_clipboard_set"

#borrow(s)
extern "C" fn ffi_log(s : String) -> Unit = "mb_host_log"

extern "C" fn ffi_bench_mode() -> Int = "mb_host_bench_mode"

extern "C" fn ffi_exit(code : Int) -> Unit = "mb_host_exit"

extern "C" fn ffi_mem_bytes() -> Double = "mb_host_mem_bytes"

///|
pub fn run(
  title : String,
  frame : FuncRef[(Double, Double, Double, Double) -> Unit],
  pointer : FuncRef[(Int, Double, Double, Int) -> Unit],
  wheel : FuncRef[(Double, Double, Double, Double, Int) -> Unit],
  key : FuncRef[(Int, Int) -> Unit],
  text : FuncRef[(Int, String, Int, Int) -> Unit],
) -> Unit {
  ffi_run(title, frame, pointer, wheel, key, text)
}

///|
pub fn now() -> Double {
  ffi_now()
}

///|
pub fn request_frame() -> Unit {
  ffi_request_frame()
}

///|
pub fn wake_after(ms : Double) -> Unit {
  ffi_wake_after(ms)
}

///|
pub fn font_metrics(size : Double, weight : Int, out : FixedArray[Double]) -> Unit {
  ffi_font_metrics(size, weight, out)
}

///|
pub fn shape(
  text : String,
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Int {
  ffi_shape(text, size, weight, out)
}

///|
pub fn glyph(key : Int, out : FixedArray[Double]) -> Unit {
  ffi_glyph(key, out)
}

///|
pub fn atlas_generation() -> Int {
  ffi_atlas_generation()
}

///|
pub fn present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  ffi_present(buf, count, r, g, b)
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
  ffi_set_ime(if active { 1 } else { 0 }, x, y, w, h, text, sel_start, sel_end)
}

///|
pub fn clipboard_set(s : String) -> Unit {
  ffi_clipboard_set(s)
}

///|
pub fn log(s : String) -> Unit {
  ffi_log(s)
}

///|
pub fn bench_mode() -> Int {
  ffi_bench_mode()
}

///|
pub fn exit(code : Int) -> Unit {
  ffi_exit(code)
}

///|
pub fn mem_bytes() -> Double {
  ffi_mem_bytes()
}

// Images: decoded off the UI thread to at most max_px on the long side,
// kept as textures the renderer draws (instances of kind 4 name theirs in
// slot 20). A decode that finishes requests a frame.

#borrow(src)
extern "C" fn ffi_image_load(src : String, max_px : Int) -> Int = "mb_host_image_load"

#borrow(data)
extern "C" fn ffi_image_load_bytes(data : Bytes, max_px : Int) -> Int = "mb_host_image_load_bytes"

#borrow(out)
extern "C" fn ffi_image_info(id : Int, out : FixedArray[Double]) -> Int = "mb_host_image_info"

extern "C" fn ffi_image_free(id : Int) -> Unit = "mb_host_image_free"

///|
/// Starts decoding the image at `src` (a file path or an http(s) URL);
/// returns its id.
pub fn image_load(src : String, max_px : Int) -> Int {
  ffi_image_load(src, max_px)
}

///|
/// Starts decoding an encoded image (JPEG, PNG, HEIC, WebP…) in memory.
pub fn image_load_bytes(data : Bytes, max_px : Int) -> Int {
  ffi_image_load_bytes(data, max_px)
}

///|
/// 0 while decoding, 1 when ready, -1 if it failed. Ready, `out` gets the
/// decoded width and height and the original's, in pixels.
pub fn image_info(id : Int, out : FixedArray[Double]) -> Int {
  ffi_image_info(id, out)
}

///|
pub fn image_free(id : Int) -> Unit {
  ffi_image_free(id)
}

// A sign-in in the browser that comes back here (browser_login.mbt; apple_browser_login.m).

///|
#borrow(path)
extern "C" fn bl_start(path : String) -> Int = "mb_host_browser_login_start"

///|
extern "C" fn bl_port(id : Int) -> Int = "mb_host_browser_login_port"

///|
#borrow(url)
extern "C" fn bl_open(id : Int, url : String) -> Int = "mb_host_browser_login_open"

///|
extern "C" fn bl_back(id : Int) -> String = "mb_host_browser_login_back"

///|
extern "C" fn bl_end(id : Int) -> Unit = "mb_host_browser_login_end"
