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
  #|(s) => globalThis.__mbhost ? globalThis.__mbhost.log(s) : console.log(s)

extern "js" fn js_bench_mode() -> Int =
  #|() => globalThis.__mbhost.benchMode()

extern "js" fn js_set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool =
  #|(f) => globalThis.__mbhost.setOutside ? (globalThis.__mbhost.setOutside(f), true) : false

extern "js" fn js_frame_awaiting(awaiting : Int, what : String, unrest : String) -> Unit =
  #|(n, w, r) => globalThis.__mbhost.frameAwaiting && globalThis.__mbhost.frameAwaiting(n, w, r)

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
extern "js" fn js_wall_ms() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.wallMs) ? globalThis.__mbhost.wallMs() : Date.now()

///|
/// The time of day, in ms since 1970 (UTC), as the machine's clock has it: for what is shown of it only (@ui.wall_ms).
/// A run to a declared moment (a scripted shot) has its own: from a fixed day, on with its frames' clock.
pub fn wall_ms() -> Double {
  js_wall_ms()
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
/// As host_native's: ascent, descent, line height, the Han font's ascent and descent, whole-pixel lines.
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
pub fn text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  js_text_key(text, size, weight, style)
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
/// A secret on the clipboard (see host_native.mbt): a page's as any words.
pub fn clipboard_set_secret(s : String, clear_ms~ : Double) -> Unit {
  ignore(clear_ms)
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
/// Who is told as what the host does for the app is done (`f(kind, id, state)`, as host_native.mbt's). False where
/// the host sends no such events.
pub fn set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool {
  js_set_outside(f)
}

///|
/// As the frame just built left it: how many of the app's asks the host has not answered yet and what they are (""
/// when none), and what keeps it from its rest (`unrest`, "" when nothing that ends is left to come: @ui's
/// Ctx::at_rest; "-" when not said, outside a run of its own clock; "never: …" at rest with a native view shown that
/// moves on its own, a video playing: a run to its rest fails there, saying it). A run to a declared moment keeps its
/// clock still while any is awaited; a run to its rest is pictured at the first frame at rest with none.
pub fn frame_awaiting(awaiting : Int, what : String, unrest : String) -> Unit {
  js_frame_awaiting(awaiting, what, unrest)
}

///|
extern "js" fn js_own_clock() -> Bool =
  #|() => !!(globalThis.__mbhost.ownClock && globalThis.__mbhost.ownClock())

///|
/// Whether the run is on a clock of its own (its frames', 1/60 s a frame from 0, still while the app awaits the host:
/// web/host.js shot_at), not the machine's.
pub fn own_clock() -> Bool {
  js_own_clock()
}

///|
/// Whether the system asks for less motion: the web host does not say.
pub fn reduce_motion() -> Bool {
  false
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
/// Whether the system asks for less transparency (glass drawn solid): the
/// browser's prefers-reduced-transparency.
pub fn reduce_transparency() -> Bool {
  js_reduce_transparency()
}

///|
/// The GPU's time for the last frame drawn, in ms (-1: not known here).
pub fn gpu_ms() -> Double {
  js_gpu_ms()
}

///|
/// The page's query parameter `name` ("" when there is none).
pub fn env(name : String) -> String {
  js_env(name)
}

///|
/// Who to tell when the app comes to the front or leaves it (host_native.mbt): the browser's page never tells (shown
/// and in front).
pub fn set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit {
  ignore(f)
}

///|
/// Whether the system is set to dark (see host_native.mbt): the browser's prefers-color-scheme.
pub fn system_dark() -> Bool {
  js_system_dark()
}

///|
/// The app is drawn dark from now on (host_native.mbt): the page has nothing of its own to follow it.
pub fn set_dark(dark : Bool) -> Unit {
  ignore(dark)
}

///|
/// Turned sideways for a film (see host_native.mbt): a browser's page does not turn.
pub fn set_sideways(on : Bool) -> Unit {
  ignore(on)
}


///|
/// Shared out (see host_native.mbt): the browser's page here has no share sheet of its own.
pub fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  ignore(text)
  ignore(name)
  ignore(mime)
  ignore(data)
  false
}

///|
pub fn shared_in() -> String {
  ""
}

///|
pub fn shared_in_file(i : Int) -> Bytes {
  ignore(i)
  b""
}

///|
/// This build's version code (see host_native.mbt): a page does not update itself.
pub fn app_version() -> Int {
  0
}

///|
pub fn update_install(url : String, sha256 : String, size : Double, name : String) -> Unit {
  ignore(url)
  ignore(sha256)
  ignore(size)
  ignore(name)
}

///|
pub fn update_state() -> String {
  ""
}

///|
/// A package for the system's installer (see host_native.mbt): a page has none, said on the system channel as the
/// other hosts say it (the page's post queue: web/host.js H.post).
pub fn install_package(name : String, data : Bytes) -> Unit {
  ignore(data)
  let said : Json = { "install": { "name": Json::string(name), "error": "unsupported" } }
  js_post(system_channel, said.stringify())
}

///|
extern "js" fn js_post(channel : String, json : String) -> Unit =
  #|(c, j) => { const H = globalThis.__mbhost; if (H && H.post) H.post(c, j) }

///|
/// A scripted run's input given to the host (see host_native.mbt): the browser has none of these paths.
pub fn drive(kind : Int, text : String) -> Bool {
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

// Files picked (pick.mbt): not from a page yet.

///|
fn pk_start(_kind : Int) -> Int {
  0
}

///|
fn pk_state(_id : Int) -> Int {
  -1
}

///|
fn pk_count(_id : Int) -> Int {
  0
}

///|
fn pk_name(_id : Int, _i : Int) -> String {
  ""
}

///|
fn pk_bytes(_id : Int, _i : Int) -> Bytes {
  b""
}

///|
fn pk_end(_id : Int) -> Unit {

}

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
  radius : Double,
  shown : Bool,
) -> Unit =
  #|(i, x, y, w, h, a, b, c, d, r, s) => { const H = globalThis.__mbhost; if (H && H.viewPlace) H.viewPlace(i, x, y, w, h, a, b, c, d, s, r) }

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
extern "js" fn js_view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit =
  #|(i, r, d, t) => { const H = globalThis.__mbhost; if (H && H.viewReadAnswer) H.viewReadAnswer(i, r, d, t) }

///|
pub fn view_open(kind : Int, arg : String) -> Int {
  js_view_open(kind, arg)
}

///|
pub fn view_place(
  id : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  cx0 : Double,
  cy0 : Double,
  cx1 : Double,
  cy1 : Double,
  radius : Double,
  shown : Bool,
) -> Unit {
  js_view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, radius, shown)
}

///|
pub fn view_close(id : Int) -> Unit {
  js_view_close(id)
}

///|
pub fn view_control(id : Int, op : Int, value : Double) -> Unit {
  js_view_control(id, op, value)
}

///|
pub fn view_info(id : Int, out : FixedArray[Double]) -> Int {
  js_view_info(id, out)
}

///|
pub fn view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  js_view_read_next(id, out)
}

///|
pub fn view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit {
  js_view_read_answer(id, req, data, total)
}

///|
/// What a view has to say (see host_native.mbt): the browser opens no site (a page cannot answer another's requests
/// without a service worker of its own), so only what a page's frame posts its host (`{"said":…}`).
pub fn view_site_next(id : Int) -> String {
  js_view_site_next(id)
}

///|
extern "js" fn js_view_site_next(id : Int) -> String =
  #|(i) => { const H = globalThis.__mbhost; return (H && H.viewSiteNext ? H.viewSiteNext(i) : '') || '' }

///|
/// What the app tells a view beyond its controls (see host_native.mbt).
pub fn view_tell(id : Int, what : Int, text : String) -> Unit {
  js_view_tell(id, what, text)
}

///|
extern "js" fn js_view_tell(id : Int, what : Int, text : String) -> Unit =
  #|(i, w, t) => { const H = globalThis.__mbhost; if (H && H.viewTell) H.viewTell(i, w, t) }

///|
pub fn view_site_body(id : Int, req : Int) -> Bytes {
  ignore(id)
  ignore(req)
  Bytes::new(0)
}

///|
pub fn view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  ignore(id)
  ignore(req)
  ignore(status)
  ignore(headers)
}

///|
pub fn view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  ignore(id)
  ignore(req)
  ignore(data)
}

///|
pub fn view_site_end(id : Int, req : Int, error : String) -> Unit {
  ignore(id)
  ignore(req)
  ignore(error)
}

///|
pub fn view_site_state(id : Int) -> String {
  ignore(id)
  ""
}

///|
pub fn view_site_load(id : Int, path : String) -> Unit {
  ignore(id)
  ignore(path)
}

///|
pub fn pdf_open(data : Bytes) -> Int {
  ignore(data)
  0
}

///|
pub fn pdf_pages(doc : Int) -> Int {
  ignore(doc)
  -1
}

///|
pub fn pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  ignore(doc)
  ignore(page)
  out[0] = 0.0
  out[1] = 0.0
}

///|
pub fn pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  ignore(doc)
  ignore(page)
  ignore(max_px)
  0
}

///|
pub fn pdf_close(doc : Int) -> Unit {
  ignore(doc)
}

///|
pub fn view_text(id : Int, what : Int) -> String? {
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
pub fn view_still(id : Int) -> Bytes {
  ignore(id)
  b""
}

///|
pub fn save_file(name : String, data : Bytes) -> Bool {
  ignore(name)
  ignore(data)
  false
}

///|
extern "js" fn js_set_cursor(kind : Int) -> Unit =
  #|(k) => globalThis.__mbhost && globalThis.__mbhost.setCursor && globalThis.__mbhost.setCursor(k)

///|
/// The desktop's window as the app wants it (see host_native.mbt): a browser's page has no window to size.
pub fn window_setup(min_w : Double, min_h : Double, w : Double, h : Double, inset? : Bool = false) -> Unit {
  ignore((min_w, min_h, w, h, inset))
}

///|
/// Whether the window's buttons are in the app's top row (see host_native.mbt): never in a browser.
pub fn window_inset() -> Bool {
  false
}

///|
/// The window dragged by the app's top row (see host_native.mbt): a browser's page cannot move its window.
pub fn window_drag() -> Unit {
  ()
}

///|
/// The pointer's shape (see host_native.mbt): the canvas's CSS cursor.
pub fn set_cursor(kind : Int) -> Unit {
  js_set_cursor(kind)
}

///|
extern "js" fn js_word_at(text : String, off : Int) -> Double =
  #|(t, o) => globalThis.__mbhost && globalThis.__mbhost.wordAt ? globalThis.__mbhost.wordAt(t, o) : -1

///|
extern "js" fn js_open_url(url : String) -> Bool =
  #|(u) => !!(globalThis.__mbhost && globalThis.__mbhost.openUrl && globalThis.__mbhost.openUrl(u))

///|
/// The word around `off` (see host_native.mbt): the browser's Intl.Segmenter.
pub fn word_at(text : String, off : Int) -> (Int, Int) {
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
pub fn open_url(url : String) -> Bool {
  js_open_url(url)
}

///|
/// The app over another app done (see host_native.mbt): a page never is.
pub fn over_done(open_app~ : Bool) -> Unit {
  ignore(open_app)
}

///|
/// A page in a browser's tab (see host_native.mbt): a tab of its own, as open_url.
pub fn open_tab(url : String) -> Bool {
  js_open_url(url)
}

///|
/// What holds the app up while it listens for a browser (see host_native.mbt): a page keeps no notice.
pub fn hold_words(channel~ : String, title~ : String, body~ : String) -> Unit {
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
pub fn post_take() -> Int {
  js_post_take()
}

///|
/// The next message taken (`post_take`): its channel, its JSON and the bytes beside it (empty: none). None when all
/// taken are handed on.
pub fn post_next() -> (String, String, Bytes)? {
  let channel = js_post_next()
  if channel == "" {
    None
  } else {
    Some((channel, js_post_json(), js_post_bytes()))
  }
}
