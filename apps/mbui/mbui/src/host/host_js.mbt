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
  #|() => (globalThis.__mbhost && globalThis.__mbhost.now) ? globalThis.__mbhost.now() : performance.now()

extern "js" fn js_event_time() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.eventTime) ? globalThis.__mbhost.eventTime() : -1

// Without a host (the tests, run in node) a frame asked for is nobody's to draw.
extern "js" fn js_request_frame() -> Unit =
  #|() => globalThis.__mbhost && globalThis.__mbhost.requestFrame()

extern "js" fn js_wake_after(ms : Double) -> Unit =
  #|(ms) => globalThis.__mbhost && globalThis.__mbhost.wakeAfter(ms)

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

extern "js" fn js_text_key(text : String, size : Double, weight : Int, style : Int) -> Int =
  #|(t, s, w, st) => globalThis.__mbhost.textKey(t, s, w, st)

extern "js" fn js_glyph(key : Int, out : FixedArray[Double]) -> Unit =
  #|(k, o) => globalThis.__mbhost.glyph(k, o)

extern "js" fn js_glyph_put(key : Int, x : Int, y : Int) -> Unit =
  #|(k, x, y) => globalThis.__mbhost.glyphPut(k, x, y)

extern "js" fn js_atlas_size(colour : Bool) -> Int =
  #|(c) => globalThis.__mbhost.atlasSize(c)

extern "js" fn js_atlas_generation() -> Int =
  #|() => globalThis.__mbhost.atlasGeneration()

extern "js" fn js_face_add(face : Int, path : String, weight : Int) -> Bool =
  #|(f, p, w) => globalThis.__mbhost.faceAdd ? globalThis.__mbhost.faceAdd(f, p, w) : false

extern "js" fn js_face_add_bytes(face : Int, data : Bytes, weight : Int) -> Bool =
  #|(f, d, w) => globalThis.__mbhost.faceAddBytes ? globalThis.__mbhost.faceAddBytes(f, d, w) : false

extern "js" fn js_face_clear(face : Int) -> Unit =
  #|(f) => { if (globalThis.__mbhost.faceClear) globalThis.__mbhost.faceClear(f) }

extern "js" fn js_present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit =
  #|(buf, n, r, g, b) => globalThis.__mbhost.present(buf, n, r, g, b)

///|
extern "js" fn ffi_text_menu(shown : Int, x : Double, y : Double, w : Double, h : Double, can : Int) -> Unit =
  #|(s, x, y, w, h, c) => { if (globalThis.__mbhost && globalThis.__mbhost.textMenu) globalThis.__mbhost.textMenu(s, x, y, w, h, c) }

///|
/// (a browser's page has no menu bar of the app's)
extern "js" fn ffi_edit_can(can : Int) -> Unit =
  #|(c) => {}

///|
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
  #|(s) => globalThis.__mbhost ? globalThis.__mbhost.log(s) : console.log(s)

extern "js" fn js_bench_mode() -> Int =
  #|() => globalThis.__mbhost.benchMode()

extern "js" fn js_set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool =
  #|(f) => globalThis.__mbhost.setOutside ? (globalThis.__mbhost.setOutside(f), true) : false

extern "js" fn js_frame_awaiting(awaiting : Int, what : String) -> Unit =
  #|(n, w) => globalThis.__mbhost.frameAwaiting && globalThis.__mbhost.frameAwaiting(n, w)

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

extern "js" fn js_reduce_transparency() -> Bool =
  #|() => !!(globalThis.__mbhost && globalThis.__mbhost.reduceTransparency && globalThis.__mbhost.reduceTransparency())

extern "js" fn js_gpu_ms() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.gpuMs) ? globalThis.__mbhost.gpuMs() : -1

extern "js" fn js_system_dark() -> Bool =
  #|() => typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches

extern "js" fn js_env(name : String) -> String =
  #|(n) => (typeof location !== "undefined" && new URLSearchParams(location.search).get(n)) || ""

///|
fn run(
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
fn now() -> Double {
  js_now()
}

///|
extern "js" fn js_wall_ms() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.wallMs) ? globalThis.__mbhost.wallMs() : Date.now()

///|
/// The time of day, in ms since 1970 (UTC), as the machine's clock has it: for what is shown of it only (@ui.wall_ms).
/// A run to a declared moment (a scripted shot) has its own: from a fixed day, on with its frames' clock.
fn wall_ms() -> Double {
  js_wall_ms()
}

///|
extern "js" fn js_utc_offset_min(at_ms : Double) -> Int =
  #|(ms) => (globalThis.__mbhost && globalThis.__mbhost.utcOffsetMin) ? globalThis.__mbhost.utcOffsetMin(ms) : -new Date(ms).getTimezoneOffset()

///|
/// How far local time is ahead of UTC at `at_ms`, in minutes (@hostapi.utc_offset_min).
fn utc_offset_min(at_ms : Double) -> Int {
  js_utc_offset_min(at_ms)
}

///|
/// When the input event being delivered happened, on now()'s clock (ms);
/// negative when the host doesn't say.
fn event_time() -> Double {
  js_event_time()
}

///|
/// What the pointer's event came from (@hostapi.event_finger): a page's host does not say.
fn event_finger() -> Int {
  -1
}

///|
/// How late the frame before reached the screen: a browser's are not told (@hostapi.frame_late).
fn frame_late() -> Double {
  0.0
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser.
fn platform() -> Int {
  4
}

///|
fn request_frame() -> Unit {
  js_request_frame()
}

///|
fn wake_after(ms : Double) -> Unit {
  js_wake_after(ms)
}

///|
/// As host_native's: ascent, descent, line height, the Han font's ascent and descent, whole-pixel lines.
fn font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  js_font_metrics(size, weight, style, out)
}

///|
fn shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  js_shape(text, size, weight, style, out)
}

///|
fn text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  js_text_key(text, size, weight, style)
}

///|
fn glyph(key : Int, out : FixedArray[Double]) -> Unit {
  js_glyph(key, out)
}

///|
fn glyph_put(key : Int, x : Int, y : Int) -> Unit {
  js_glyph_put(key, x, y)
}

///|
fn atlas_size(colour : Bool) -> Int {
  js_atlas_size(colour)
}

///|
/// (the page draws a glyph as it is first asked for: nothing ahead)
fn glyphs_ahead(keys : FixedArray[Int], n : Int) -> Unit {
  ignore(keys)
  ignore(n)
}

///|
/// A font file (at `path`: a URL the page can fetch) made part of face `face` (style.mbt), for `weight` (0: variable,
/// every weight). The page loads it as it can (FontFace): drawn in it once loaded (atlas_generation moves on then).
fn face_add(face : Int, path : String, weight : Int) -> Bool {
  js_face_add(face, path, weight)
}

///|
/// As face_add, the font's file being `data`.
fn face_add_bytes(face : Int, data : Bytes, weight : Int) -> Bool {
  js_face_add_bytes(face, data, weight)
}

///|
/// Face `face` given up.
fn face_clear(face : Int) -> Unit {
  js_face_clear(face)
}

///|
/// (a browser's faces are the files given: no family of the machine's)
fn face_add_family(face : Int, family : String) -> Bool {
  ignore(face)
  ignore(family)
  false
}

///|
fn local_font_families() -> String {
  ""
}

///|
fn atlas_generation() -> Int {
  js_atlas_generation()
}

///|
fn present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  js_present(buf, count, r, g, b)
}

///|
fn set_ime(
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
fn clipboard_set(s : String) -> Unit {
  js_clipboard_set(s)
}

///|
/// A picture on the clipboard (@hostapi.clipboard_set_image): a page's runs put none.
fn clipboard_set_image(data : Bytes) -> Unit {
  ignore(data)
}

///|
/// A secret on the clipboard (see host_native.mbt): a page's as any words.
fn clipboard_set_secret(s : String, clear_ms~ : Double) -> Unit {
  ignore(clear_ms)
  js_clipboard_set(s)
}

///|
/// The secret copied taken off (see host_native.mbt): a page's clipboard is not read back to know it is still there.
fn clipboard_secret_off() -> Unit {
  ()
}

///|
fn log(s : String) -> Unit {
  js_log(s)
}

///|
fn bench_mode() -> Int {
  js_bench_mode()
}

///|
/// Who is told as what the host does for the app is done (`f(kind, id, state)`, as host_native.mbt's). False where
/// the host sends no such events.
fn set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool {
  js_set_outside(f)
}

///|
/// As the frame just built left it: how many of the app's asks the host has not answered yet and what they are (""
/// when none). A run to a declared moment keeps its clock still while any is awaited.
fn frame_awaiting(awaiting : Int, what : String) -> Unit {
  js_frame_awaiting(awaiting, what)
}

///|
extern "js" fn js_own_clock() -> Bool =
  #|() => !!(globalThis.__mbhost.ownClock && globalThis.__mbhost.ownClock())

///|
/// Whether the run is on a clock of its own (its frames', 1/60 s a frame from 0, still while the app awaits the host:
/// web/host.js shot_at), not the machine's.
fn own_clock() -> Bool {
  js_own_clock()
}

///|
/// Whether the system asks for less motion: the browser's prefers-reduced-motion.
extern "js" fn reduce_motion() -> Bool =
  #|() => typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches

///|
fn exit(code : Int) -> Unit {
  js_exit(code)
}

///|
fn mem_bytes() -> Double {
  js_mem_bytes()
}

///|
/// Where the system's back goes (host_native.mbt `set_back`); in a browser:
/// Alt+Left and a mouse's back button.
fn set_back(back : FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit {
  js_set_back(back)
}

///|
fn back_enabled(on : Bool) -> Unit {
  js_back_enabled(on)
}

///|
/// Whether the system asks for less transparency (glass drawn solid): the
/// browser's prefers-reduced-transparency.
fn reduce_transparency() -> Bool {
  js_reduce_transparency()
}

///|
/// The GPU's time for the last frame drawn, in ms (-1: not known here).
fn gpu_ms() -> Double {
  js_gpu_ms()
}

///|
/// A browser says not how much of a CPU its page has had (@hostapi.cpu_ms).
fn cpu_ms() -> Double {
  -1.0
}

///|
/// A browser's page keeps no performance record (@hostapi.perf_state).
fn perf_state() -> Int {
  -1
}

///|
fn set_perf(on : Bool) -> Unit {
  ignore(on)
}

///|
fn perf_line(line : String) -> Unit {
  ignore(line)
}

///|
fn perf_where() -> String {
  ""
}

///|
fn perf_size() -> Double {
  0.0
}

///|
fn perf_read() -> Bytes {
  b""
}

///|
/// The page's query parameter `name` ("" when there is none).
fn env(name : String) -> String {
  js_env(name)
}

///|
/// Who to tell when the app comes to the front or leaves it (host_native.mbt): the browser's page never tells (shown
/// and in front).
fn set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit {
  ignore(f)
}

///|
/// Whether the system is set to dark (see host_native.mbt): the browser's prefers-color-scheme.
fn system_dark() -> Bool {
  js_system_dark()
}

///|
fn font_scale() -> Double {
  1.0
}

///|
/// What the app was started to be used with (see host_native.mbt): the browser's primary pointer as the page loads, a
/// coarse one (a finger) touch, a fine one (a mouse, a touchpad) keyboard and mouse; 0 where it says neither.
extern "js" fn native_pointing() -> Int =
  #|() => (typeof matchMedia === "undefined" ? 0 : matchMedia("(pointer: coarse)").matches ? 1 : matchMedia("(pointer: fine)").matches ? 2 : 0)

///|
/// Whether a keyboard is at hand (see host_native.mbt): a browser cannot tell (-1: the platform's, @ui).
fn keyboard() -> Int {
  -1
}

///|
fn a11y_on() -> Bool {
  false
}

///|
fn a11y_tree(_s : String) -> Unit {
  ()
}

///|
/// The app is drawn dark from now on (host_native.mbt): the page has nothing of its own to follow it.
fn set_dark(dark : Bool) -> Unit {
  ignore(dark)
}

///|
/// Turned sideways for a film (see host_native.mbt): a browser's page does not turn.
fn set_sideways(on : Bool) -> Unit {
  ignore(on)
}

///|
/// A phone let turn as held (see host_native.mbt): a browser's page does not turn.
fn set_turnable(on : Bool) -> Bool {
  ignore(on)
  false
}


///|
/// Shared out (see host_native.mbt): the browser's page here has no share sheet of its own.
fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  ignore(text)
  ignore(name)
  ignore(mime)
  ignore(data)
  false
}

///|
fn shared_in() -> String {
  ""
}

///|
fn shared_in_file(i : Int) -> Bytes {
  ignore(i)
  b""
}

///|
/// This build's version code (see host_native.mbt): a page does not update itself.
fn app_version() -> Int {
  0
}

///|
fn update_fetch(url : String, sha256 : String, size : Double, name : String, now : Bool) -> Unit {
  ignore(url)
  ignore(sha256)
  ignore(size)
  ignore(name)
  ignore(now)
}

///|
fn update_apply(said : String) -> Unit {
  ignore(said)
}

///|
fn update_state() -> String {
  ""
}

///|
/// A package for the system's installer (see host_native.mbt): a page has none, said on the system channel as the
/// other hosts say it (the page's post queue: web/host.js H.post).
fn install_package(name : String, data : Bytes) -> Unit {
  ignore(data)
  let said : Json = { "install": { "name": Json::string(name), "error": "unsupported" } }
  js_post(@hostapi.system_channel, said.stringify())
}

///|
extern "js" fn js_post(channel : String, json : String) -> Unit =
  #|(c, j) => { const H = globalThis.__mbhost; if (H && H.post) H.post(c, j) }

///|
/// A scripted run's input given to the host (see host_native.mbt): the browser has none of these paths.
fn drive(kind : Int, text : String) -> Bool {
  ignore(kind)
  ignore(text)
  false
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
extern "js" fn js_image_pixels(id : Int, out : FixedArray[Byte]) -> Int =
  #|(i, o) => globalThis.__mbhost.imagePixels(i, o)

///|
fn image_load(src : String, max_px : Int) -> Int {
  js_image_load(src, max_px)
}

///|
fn image_load_bytes(data : Bytes, max_px : Int) -> Int {
  js_image_load_bytes(data, max_px)
}

///|
fn image_info(id : Int, out : FixedArray[Double]) -> Int {
  js_image_info(id, out)
}

///|
fn image_free(id : Int) -> Unit {
  js_image_free(id)
}

///|
/// A ready image's pixels (as host_native.mbt's).
fn image_pixels(id : Int, out : FixedArray[Byte]) -> Bool {
  js_image_pixels(id, out) == 1
}

///|
/// The last frame's pixels (as host_native.mbt's): a page's canvas is not read back here.
fn drawn_pixels(x : Int, y : Int, w : Int, h : Int, out : FixedArray[Byte]) -> Bool {
  ignore((x, y, w, h, out))
  false
}

///|
/// Instances drawn as a frame and read back (as host_native.mbt's): a page's canvas is not read back here.
fn drawn_pixels_of(
  inst : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
  scale : Double,
  w : Int,
  h : Int,
  out : FixedArray[Byte],
) -> Bool {
  ignore((inst, count, r, g, b, scale, w, h, out))
  false
}

// A sign-in in the browser that comes back here (browser_login.mbt): a page cannot listen.

///|
fn bl_start(_path : String, _done : String) -> Int {
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

// Files picked (pick.mbt): the page's file input (web/host.js H.pickStart), its answer told as outside kind 3.

///|
extern "js" fn pk_start(kind : Int) -> Int =
  #|(k) => { const H = globalThis.__mbhost; return H && H.pickStart ? H.pickStart(k) : 0 }

///|
extern "js" fn pk_state(id : Int) -> Int =
  #|(i) => { const H = globalThis.__mbhost; return H && H.pickState ? H.pickState(i) : -1 }

///|
extern "js" fn pk_count(id : Int) -> Int =
  #|(i) => globalThis.__mbhost.pickCount(i)

///|
extern "js" fn pk_name(id : Int, i : Int) -> String =
  #|(id, i) => globalThis.__mbhost.pickName(id, i)

///|
extern "js" fn pk_bytes(id : Int, i : Int) -> Bytes =
  #|(id, i) => globalThis.__mbhost.pickBytes(id, i)

///|
extern "js" fn pk_info(id : Int, i : Int) -> String =
  #|(id, i) => globalThis.__mbhost.pickInfo(id, i)

///|
extern "js" fn pk_end(id : Int) -> Unit =
  #|(i) => { const H = globalThis.__mbhost; if (H && H.pickEnd) H.pickEnd(i) }

// Files kept on the device (keep.mbt): a page keeps none.

///|
fn kp_begin(_name : String, _mime : String, _way : Int) -> Int {
  0
}

///|
fn kp_append(_id : Int, _data : Bytes) -> Int {
  0
}

///|
fn kp_finish(_id : Int) -> Unit {

}

///|
fn kp_state(_id : Int) -> Int {
  -1
}

///|
fn kp_where(_id : Int) -> String {
  ""
}

///|
fn kp_end(_id : Int) -> Unit {

}

// The gallery (gallery.mbt): a page has none.

///|
fn ga_access() -> Int {
  -1
}

///|
fn ga_ask() -> Unit {

}

///|
fn ga_answers() -> Int {
  0
}

///|
fn ga_read() -> Int {
  0
}

///|
fn ga_read_state(_id : Int) -> Int {
  -1
}

///|
fn ga_read_rows(_id : Int) -> String {
  ""
}

///|
fn ga_read_end(_id : Int) -> Unit {

}

///|
fn pk_photo(_src : String) -> Int {
  0
}

// Text in a legacy encoding (charset.mbt): the page's TextDecoder.

///|
extern "js" fn js_cs_known(charset : String) -> Bool =
  #|(l) => { try { new TextDecoder(l); return true } catch (e) { return false } }

///|
extern "js" fn js_cs_decode(data : Bytes, charset : String) -> String =
  #|(d, l) => new TextDecoder(l).decode(d)

///|
fn cs_known(charset : String) -> Int {
  if js_cs_known(charset) {
    1
  } else {
    0
  }
}

///|
fn cs_decode(data : Bytes, charset : String) -> String {
  js_cs_decode(data, charset)
}

// Marks drawn onto an image (marks.mbt): not by a page.

///|
fn mk_start(_image : Bytes, _marks : String) -> Int {
  0
}

///|
fn mk_state(_id : Int) -> Int {
  -1
}

///|
fn mk_png(_id : Int) -> Bytes {
  b""
}

// Notifications (notify.mbt): not shown by a page yet; what would be is said on the log.

///|
fn nt_show(channel : String, tag : String, title : String, body : String, opens : String) -> Unit {
  ignore(channel)
  ignore(opens)
  log("NOTICE " + tag + "\t" + title + "\t" + body)
}

///|
fn nt_cancel(tag : String) -> Unit {
  ignore(tag)
}

///|
/// The system's own bars (@hostapi.nav_bar): none in a browser, the app draws its own.
fn nv_bar(spec : String) -> Int {
  ignore(spec)
  0
}

///|
fn nv_able() -> Int {
  0
}

///|
fn nt_state(what : Int) -> Int {
  if what == 2 {
    -1
  } else {
    0
  }
}

///|
fn nt_text(what : Int) -> String {
  ignore(what)
  ""
}

// Native views over the canvas (see host_native.mbt): DOM elements under the canvas (web/host.js), shown through its
// holes; PDFs: none drawn here.

///|
extern "js" fn js_view_open(kind : Int, arg : String) -> Int =
  #|(k, a) => { const H = globalThis.__mbhost; return H && H.viewOpen ? H.viewOpen(k, a) : 0 }

///|
extern "js" fn js_view_place(
  id : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  cx0 : Double,
  cy0 : Double,
  cx1 : Double,
  cy1 : Double,
  r0 : Double,
  r1 : Double,
  r2 : Double,
  r3 : Double,
  shown : Bool,
) -> Unit =
  #|(i, x, y, w, h, a, b, c, d, r0, r1, r2, r3, s) => { const H = globalThis.__mbhost; if (H && H.viewPlace) H.viewPlace(i, x, y, w, h, a, b, c, d, s, r0, r1, r2, r3) }

///|
extern "js" fn js_view_close(id : Int) -> Unit =
  #|(i) => { const H = globalThis.__mbhost; if (H && H.viewClose) H.viewClose(i) }

///|
extern "js" fn js_view_control(id : Int, op : Int, value : Double) -> Unit =
  #|(i, o, v) => { const H = globalThis.__mbhost; if (H && H.viewControl) H.viewControl(i, o, v) }

///|
extern "js" fn js_view_info(id : Int, out : FixedArray[Double]) -> Int =
  #|(i, o) => { const H = globalThis.__mbhost; return H && H.viewInfo ? H.viewInfo(i, o) : -1 }

///|
extern "js" fn js_view_read_next(id : Int, out : FixedArray[Double]) -> Int =
  #|(i, o) => { const H = globalThis.__mbhost; return H && H.viewReadNext ? H.viewReadNext(i, o) : 0 }

///|
extern "js" fn js_view_read_answer(id : Int, req : Int, data : Bytes, total : Double, more : Bool) -> Unit =
  #|(i, r, d, t, m) => { const H = globalThis.__mbhost; if (H && H.viewReadAnswer) H.viewReadAnswer(i, r, d, t, m) }

///|
fn view_open(kind : Int, arg : String) -> Int {
  js_view_open(kind, arg)
}

///|
fn view_place(
  id : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  cx0 : Double,
  cy0 : Double,
  cx1 : Double,
  cy1 : Double,
  r0 : Double,
  r1 : Double,
  r2 : Double,
  r3 : Double,
  shown : Bool,
) -> Unit {
  js_view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, r0, r1, r2, r3, shown)
}

///|
fn view_close(id : Int) -> Unit {
  js_view_close(id)
}

///|
fn view_control(id : Int, op : Int, value : Double) -> Unit {
  js_view_control(id, op, value)
}

///|
fn view_info(id : Int, out : FixedArray[Double]) -> Int {
  js_view_info(id, out)
}

///|
fn view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  js_view_read_next(id, out)
}

///|
fn view_read_answer(id : Int, req : Int, data : Bytes, total : Double, more : Bool) -> Unit {
  js_view_read_answer(id, req, data, total, more)
}

///|
/// What a view has to say (see host_native.mbt): the browser opens no site (a page cannot answer another's requests
/// without a service worker of its own), so only what a page's frame posts its host (`{"said":…}`).
fn view_site_next(id : Int) -> String {
  js_view_site_next(id)
}

///|
extern "js" fn js_view_site_next(id : Int) -> String =
  #|(i) => { const H = globalThis.__mbhost; return (H && H.viewSiteNext ? H.viewSiteNext(i) : '') || '' }

///|
/// What the app tells a view beyond its controls (see host_native.mbt).
fn view_tell(id : Int, what : Int, text : String) -> Unit {
  js_view_tell(id, what, text)
}

///|
extern "js" fn js_view_tell(id : Int, what : Int, text : String) -> Unit =
  #|(i, w, t) => { const H = globalThis.__mbhost; if (H && H.viewTell) H.viewTell(i, w, t) }

///|
fn view_site_body(id : Int, req : Int) -> Bytes {
  ignore(id)
  ignore(req)
  Bytes::new(0)
}

///|
fn view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  ignore(id)
  ignore(req)
  ignore(status)
  ignore(headers)
}

///|
fn view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  ignore(id)
  ignore(req)
  ignore(data)
}

///|
fn view_site_end(id : Int, req : Int, error : String) -> Unit {
  ignore(id)
  ignore(req)
  ignore(error)
}

///|
fn view_site_state(id : Int) -> String {
  ignore(id)
  ""
}

///|
fn view_site_load(id : Int, path : String) -> Unit {
  ignore(id)
  ignore(path)
}

///|
fn pdf_open(data : Bytes) -> Int {
  ignore(data)
  0
}

///|
fn pdf_pages(doc : Int) -> Int {
  ignore(doc)
  -1
}

///|
fn pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  ignore(doc)
  ignore(page)
  out[0] = 0.0
  out[1] = 0.0
}

///|
fn pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  ignore(doc)
  ignore(page)
  ignore(max_px)
  0
}

///|
fn pdf_close(doc : Int) -> Unit {
  ignore(doc)
}

///|
fn view_text(id : Int, what : Int) -> String? {
  match js_view_text(id, what) {
    "" => None
    s => Some(s)
  }
}

///|
/// What a view says (`what` 2: how its frame grab stands), "" none.
extern "js" fn js_view_text(id : Int, what : Int) -> String =
  #|(id, what) => (globalThis.__mbhost.viewText ? globalThis.__mbhost.viewText(id, what) : '') || ''

///|
fn view_still(id : Int) -> Bytes {
  ignore(id)
  b""
}

///|
fn save_file(name : String, data : Bytes) -> Bool {
  ignore(name)
  ignore(data)
  false
}

///|
extern "js" fn js_set_cursor(kind : Int) -> Unit =
  #|(k) => globalThis.__mbhost && globalThis.__mbhost.setCursor && globalThis.__mbhost.setCursor(k)

///|
/// The desktop's window as the app wants it (see host_native.mbt): a browser's page has no window to size.
fn window_setup(min_w : Double, min_h : Double, w : Double, h : Double, inset? : Bool = false) -> Unit {
  ignore((min_w, min_h, w, h, inset))
}

///|
/// (a page's window is the browser's: shown as it is)
fn window_hold() -> Unit {
  ()
}

///|
fn window_show() -> Unit {
  ()
}

///|
/// Whether the window's buttons are in the app's top row (see host_native.mbt): never in a browser.
fn window_inset() -> Bool {
  false
}

///|
/// The window filling the screen (see host_native.mbt): a browser's page has none of its own.
fn full_screen() -> Bool {
  false
}

///|
fn set_full_screen(on : Bool) -> Unit {
  ignore(on)
}

///|
/// A browser's page: its corners square (@hostapi.window_corner).
fn window_corner() -> Double {
  0.0
}

///|
/// A browser's page: its corners square, each (@hostapi.window_corner_at).
fn window_corner_at(k : Int) -> Double {
  ignore(k)
  0.0
}

///|
/// The window dragged by the app's top row (see host_native.mbt): a browser's page cannot move its window.
fn window_drag() -> Unit {
  ()
}

///|
/// The window's own buttons (see host_native.mbt): a browser's page has none to draw.
fn window_act(what : Int) -> Unit {
  ignore(what)
}

///|
fn window_zoomed() -> Bool {
  false
}

///|
fn window_snap(x : Double, y : Double, w : Double, h : Double) -> Unit {
  ignore((x, y, w, h))
}

///|
fn window_snap_state() -> Int {
  0
}

///|
/// A window of the app's own (see host_native.mbt): a browser's page opens none.
fn window_opens() -> Bool {
  false
}

///|
fn window_open(what : String) -> Bool {
  ignore(what)
  false
}

///|
/// The pointer's shape (see host_native.mbt): the canvas's CSS cursor.
fn set_cursor(kind : Int) -> Unit {
  js_set_cursor(kind)
}

///|
/// (no icon of the app's in a browser to put a number on)
fn set_badge(n : Int) -> Unit {
  ignore(n)
}

///|
/// (no menu bar of the system's in a browser)
fn menu_setup(json : String) -> Unit {
  ignore(json)
}

///|
/// (no station of this machine's to manage from a browser)
fn local_station() -> String {
  ""
}

///|
fn local_station_act(a : String) -> Unit {
  ignore(a)
}

///|
/// (the keys held are not read here)
fn mods_held() -> Int {
  0
}

///|
extern "js" fn js_word_at(text : String, off : Int) -> Double =
  #|(t, o) => globalThis.__mbhost && globalThis.__mbhost.wordAt ? globalThis.__mbhost.wordAt(t, o) : -1

///|
extern "js" fn js_open_url(url : String) -> Bool =
  #|(u) => !!(globalThis.__mbhost && globalThis.__mbhost.openUrl && globalThis.__mbhost.openUrl(u))

///|
/// The word around `off` (see host_native.mbt): the browser's Intl.Segmenter.
fn word_at(text : String, off : Int) -> (Int, Int) {
  let v = js_word_at(text, off)
  if v < 0.0 {
    return (-1, -1)
  }
  let k = 4294967296.0
  let s = (v / k).floor()
  (s.to_int(), (v - s * k).to_int())
}

///|
/// `url` handed to the browser (see host_native.mbt): window.open, in a tab of its own.
fn open_url(url : String) -> Bool {
  js_open_url(url)
}

///|
/// The app over another app done (see host_native.mbt): a page never is.
fn over_done(open_app~ : Bool) -> Unit {
  ignore(open_app)
}

///|
/// A page in a browser's tab (see host_native.mbt): a tab of its own, as open_url.
fn open_tab(url : String) -> Bool {
  js_open_url(url)
}

///|
/// What holds the app up while it listens for a browser (see host_native.mbt): a page keeps no notice.
fn hold_words(channel~ : String, title~ : String, body~ : String) -> Unit {
  ignore(channel)
  ignore(title)
  ignore(body)
}

///|
extern "js" fn js_post_take() -> Int =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.postTake) ? globalThis.__mbhost.postTake() : 0

///|
extern "js" fn js_post_next() -> String =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.postNext) ? globalThis.__mbhost.postNext() : ""

///|
extern "js" fn js_post_json() -> String =
  #|() => globalThis.__mbhost.postJson()

///|
extern "js" fn js_post_bytes() -> Bytes =
  #|() => globalThis.__mbhost.postBytes()

///|
/// What was posted from outside the frames since the last take (`__mbhost.post(channel, json, bytes)`: web/host.js),
/// taken now as a frame begins: how many. They are handed on one at a time (`post_next`), in the order posted.
fn post_take() -> Int {
  js_post_take()
}

///|
/// The next message taken (`post_take`): its channel, its JSON and the bytes beside it (empty: none). None when all
/// taken are handed on.
fn post_next() -> (String, String, Bytes)? {
  let channel = js_post_next()
  if channel == "" {
    None
  } else {
    Some((channel, js_post_json(), js_post_bytes()))
  }
}

///|
/// The part of the next frame that differs from the one before (@hostapi.render_dirty): web/host.js draws only that
/// part of its canvas again.
extern "js" fn rn_dirty(x : Double, y : Double, w : Double, h : Double) -> Unit =
  #|(x, y, w, h) => { if (globalThis.__mbhost.renderDirty) globalThis.__mbhost.renderDirty(x, y, w, h) }
