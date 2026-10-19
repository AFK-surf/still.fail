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

extern "C" fn ffi_event_time() -> Double = "mb_host_event_time"

extern "C" fn ffi_platform() -> Int = "mb_host_platform"

extern "C" fn ffi_request_frame() -> Unit = "mb_host_request_frame"

extern "C" fn ffi_wake_after(ms : Double) -> Unit = "mb_host_wake_after"

#borrow(out)
extern "C" fn ffi_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit = "mb_host_font_metrics"

#borrow(text, out)
extern "C" fn ffi_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int = "mb_host_shape"

#borrow(text)
extern "C" fn ffi_text_key(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
) -> Int = "mb_host_text_key"

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

extern "C" fn ffi_reduce_transparency() -> Int = "mb_host_reduce_transparency"

extern "C" fn ffi_gpu_ms() -> Double = "mb_host_gpu_ms"

extern "C" fn ffi_set_back(
  back : FuncRef[(Int, Double, Double, Int) -> Unit],
) -> Unit = "mb_host_set_back"

extern "C" fn ffi_back_enabled(on : Int) -> Unit = "mb_host_back_enabled"

#borrow(name)
extern "C" fn ffi_env(name : String) -> String = "mb_host_env"

#borrow(text)
extern "C" fn ffi_drive(kind : Int, text : String) -> Int = "mb_host_drive"

extern "C" fn ffi_set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit = "mb_host_set_app_state"

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
/// When the input event being delivered happened, on now()'s clock (ms):
/// a touch's own time, which comes before it is handled (a frame's touches
/// are handled together); negative when the host doesn't say.
pub fn event_time() -> Double {
  ffi_event_time()
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser.
pub fn platform() -> Int {
  ffi_platform()
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
/// Ascent, descent and line height of the system font (or its code face,
/// `style` & style_mono; slanted with style_italic) at this size and weight.
pub fn font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  ffi_font_metrics(size, weight, style, out)
}

///|
/// `text` shaped in that font into grapheme clusters: four numbers each
/// (start, length, advance, glyph key; -1 for none) in `out`; returns how
/// many.
pub fn shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  ffi_shape(text, size, weight, style, out)
}

///|
/// The glyph key of `text` drawn whole as one piece (the way the platform draws it in a line: a word whose letters
/// join), for `glyph`.
pub fn text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  ffi_text_key(text, size, weight, style)
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

///|
/// Where the system's back goes (Android's back gesture, predictive or not,
/// and its back button; a mouse's back button): `back(kind, x, progress,
/// edge)`, kind 0 a back gesture started at x (logical pixels), 1 it moved
/// (to x, `progress` 0-1 as the system has it), 2 let go to go back (or a
/// back with no gesture), 3 called off; edge 0 the left, 1 the right.
/// Called before `run`.
pub fn set_back(back : FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit {
  ffi_set_back(back)
}

///|
/// Whether the app takes back now (a page to go back to): when not, the
/// system does what it does (Android leaves the app).
pub fn back_enabled(on : Bool) -> Unit {
  ffi_back_enabled(if on { 1 } else { 0 })
}

///|
/// Whether the system asks for less transparency (glass drawn solid):
/// macOS's and iOS's Reduce Transparency, Windows' transparency effects
/// turned off; Android has no such setting (never).
pub fn reduce_transparency() -> Bool {
  ffi_reduce_transparency() != 0
}

///|
/// The GPU's time for the last frame it finished, in ms (-1: not known on
/// this host).
pub fn gpu_ms() -> Double {
  ffi_gpu_ms()
}

///|
/// An environment variable ("" when unset; in a browser, the page's query
/// parameter of that name).
pub fn env(name : String) -> String {
  ffi_env(name)
}

///|
/// Who to tell when the app comes to the front or leaves it: `f` gets 1 while its window is shown, | 2 while it is
/// also in front (the key window of the active app; Android: the activity resumed with the window's focus). Told on
/// each change, on the app's thread (Android: before the GL thread pauses). Hosts that never tell leave the app as
/// shown and in front.
pub fn set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit {
  ffi_set_app_state(f)
}

///|
/// A scripted run's input given to the host to send as its own (src/ui/drive.mbt): `drive_insert` words committed and
/// `drive_mark` composed by the input method (macOS: NSTextInputClient's insertText and setMarkedText; Android: the
/// view's InputConnection), `drive_newline` its Enter, `drive_paste` the system's paste of the clipboard (Cmd+V,
/// KEYCODE_PASTE), `drive_backspace`, `drive_shot` the window's picture saved at `text` (a path). False where the host
/// has no such path (the caller sends it to the app itself).
pub fn drive(kind : Int, text : String) -> Bool {
  ffi_drive(kind, text) != 0
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

// A sign-in in the browser that comes back here (browser_login.mbt; apple_browser_login.m, and on Android
// android_host.c on android/…/BrowserLogin.java).

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

// Files picked (pick.mbt; mac_app.m's open panel, android_host.c on MainActivity's pickers).

///|
extern "C" fn pk_start(kind : Int) -> Int = "mb_host_pick_start"

///|
extern "C" fn pk_state(id : Int) -> Int = "mb_host_pick_state"

///|
extern "C" fn pk_count(id : Int) -> Int = "mb_host_pick_count"

///|
extern "C" fn pk_name(id : Int, i : Int) -> String = "mb_host_pick_name"

///|
extern "C" fn pk_bytes(id : Int, i : Int) -> Bytes = "mb_host_pick_bytes"

///|
extern "C" fn pk_end(id : Int) -> Unit = "mb_host_pick_end"
