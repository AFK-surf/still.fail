// The host's side, for every package that is not an app's main: the window, the text and pictures the system draws, what the
// device does. Everything mbui and an app ask of their host goes through `Host`; which host answers is set as the
// program starts: an app's main imports mbui/host, whose `init` gives the platform's (macOS, iOS, Android, Windows, a
// browser); a test's Tester gives its fake (@ui's FakeHost). A test's program links no host's code (Objective-C, C++,
// JNI): it builds and runs on any machine.
//
// A method answers as a host with nothing for it does (nothing done, 0, false, empty, None) unless the host says
// otherwise: mbui/host's Native says every one (its native_host.mbt), as a new method must there too.
//
// The methods without docs here are what this package's own wrappers ask (pick.mbt's pk_*, keep.mbt's kp_*…).

///|
pub(open) trait Host {
  window_setup(Self, Double, Double, Double, Double, Bool) -> Unit = _
  window_inset(Self) -> Bool = _
  window_drag(Self) -> Unit = _
  set_cursor(Self, Int) -> Unit = _
  run(Self, String, FuncRef[(Double, Double, Double, Double) -> Unit], FuncRef[(Int, Double, Double, Int) -> Unit], FuncRef[(Double, Double, Double, Double, Int) -> Unit], FuncRef[(Int, Int) -> Unit], FuncRef[(Int, String, Int, Int) -> Unit]) -> Unit = _
  now(Self) -> Double = _
  wall_ms(Self) -> Double = _
  event_time(Self) -> Double = _
  platform(Self) -> Int = _
  request_frame(Self) -> Unit = _
  wake_after(Self, Double) -> Unit = _
  font_metrics(Self, Double, Int, Int, FixedArray[Double]) -> Unit = _
  shape(Self, String, Double, Int, Int, FixedArray[Double]) -> Int = _
  text_key(Self, String, Double, Int, Int) -> Int = _
  glyph(Self, Int, FixedArray[Double]) -> Unit = _
  face_add(Self, Int, String, Int) -> Bool = _
  face_add_bytes(Self, Int, Bytes, Int) -> Bool = _
  face_clear(Self, Int) -> Unit = _
  atlas_generation(Self) -> Int = _
  present(Self, FixedArray[Double], Int, Double, Double, Double) -> Unit = _
  set_ime(Self, Bool, Double, Double, Double, Double, String, Int, Int) -> Unit = _
  clipboard_set(Self, String) -> Unit = _
  clipboard_set_secret(Self, String, Double) -> Unit = _
  log(Self, String) -> Unit = _
  bench_mode(Self) -> Int = _
  set_outside(Self, FuncRef[(Int, Int, Int) -> Unit]) -> Bool = _
  frame_awaiting(Self, Int, String) -> Unit = _
  own_clock(Self) -> Bool = _
  reduce_motion(Self) -> Bool = _
  exit(Self, Int) -> Unit = _
  mem_bytes(Self) -> Double = _
  set_back(Self, FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit = _
  back_enabled(Self, Bool) -> Unit = _
  reduce_transparency(Self) -> Bool = _
  gpu_ms(Self) -> Double = _
  env(Self, String) -> String = _
  set_app_state(Self, FuncRef[(Int) -> Unit]) -> Unit = _
  system_dark(Self) -> Bool = _
  set_dark(Self, Bool) -> Unit = _
  set_sideways(Self, Bool) -> Unit = _
  share(Self, String, String, String, Bytes) -> Bool = _
  shared_in(Self) -> String = _
  shared_in_file(Self, Int) -> Bytes = _
  app_version(Self) -> Int = _
  update_install(Self, String, String, Double, String) -> Unit = _
  update_state(Self) -> String = _
  install_package(Self, String, Bytes) -> Unit = _
  drive(Self, Int, String) -> Bool = _
  image_load(Self, String, Int) -> Int = _
  image_load_bytes(Self, Bytes, Int) -> Int = _
  image_info(Self, Int, FixedArray[Double]) -> Int = _
  image_free(Self, Int) -> Unit = _
  image_pixels(Self, Int, FixedArray[Byte]) -> Bool = _
  view_site_next(Self, Int) -> String = _
  view_site_body(Self, Int, Int) -> Bytes = _
  view_site_head(Self, Int, Int, Int, String) -> Unit = _
  view_site_chunk(Self, Int, Int, Bytes) -> Unit = _
  view_site_end(Self, Int, Int, String) -> Unit = _
  view_site_state(Self, Int) -> String = _
  view_site_load(Self, Int, String) -> Unit = _
  view_tell(Self, Int, Int, String) -> Unit = _
  view_open(Self, Int, String) -> Int = _
  view_place(Self, Int, Double, Double, Double, Double, Double, Double, Double, Double, Double, Bool) -> Unit = _
  view_close(Self, Int) -> Unit = _
  view_control(Self, Int, Int, Double) -> Unit = _
  view_info(Self, Int, FixedArray[Double]) -> Int = _
  view_read_next(Self, Int, FixedArray[Double]) -> Int = _
  view_read_answer(Self, Int, Int, Bytes, Double) -> Unit = _
  pdf_open(Self, Bytes) -> Int = _
  pdf_pages(Self, Int) -> Int = _
  pdf_page_size(Self, Int, Int, FixedArray[Double]) -> Unit = _
  pdf_page_load(Self, Int, Int, Int) -> Int = _
  pdf_close(Self, Int) -> Unit = _
  view_text(Self, Int, Int) -> String? = _
  view_still(Self, Int) -> Bytes = _
  save_file(Self, String, Bytes) -> Bool = _
  word_at(Self, String, Int) -> (Int, Int) = _
  open_url(Self, String) -> Bool = _
  over_done(Self, Bool) -> Unit = _
  open_tab(Self, String) -> Bool = _
  hold_words(Self, String, String, String) -> Unit = _
  post_take(Self) -> Int = _
  post_next(Self) -> (String, String, Bytes)? = _
  ref_begin(Self, Double, Double, Double, Int) -> Unit = _
  ref_text(Self, String, Double, Int, Int, Double, Double, Int, FixedArray[Double]) -> Unit = _
  ref_end(Self, String) -> Bool = _
  ref_frame(Self, String) -> Bool = _
  bl_start(Self, String) -> Int = _
  bl_port(Self, Int) -> Int = _
  bl_open(Self, Int, String) -> Int = _
  bl_back(Self, Int) -> String = _
  bl_end(Self, Int) -> Unit = _
  pk_start(Self, Int) -> Int = _
  pk_state(Self, Int) -> Int = _
  pk_count(Self, Int) -> Int = _
  pk_name(Self, Int, Int) -> String = _
  pk_bytes(Self, Int, Int) -> Bytes = _
  pk_end(Self, Int) -> Unit = _
  kp_begin(Self, String, String, Int) -> Int = _
  kp_append(Self, Int, Bytes) -> Int = _
  kp_finish(Self, Int) -> Unit = _
  kp_state(Self, Int) -> Int = _
  kp_where(Self, Int) -> String = _
  kp_end(Self, Int) -> Unit = _
  ga_access(Self) -> Int = _
  ga_ask(Self) -> Unit = _
  ga_answers(Self) -> Int = _
  ga_read(Self) -> Int = _
  ga_read_state(Self, Int) -> Int = _
  ga_read_rows(Self, Int) -> String = _
  ga_read_end(Self, Int) -> Unit = _
  pk_photo(Self, String) -> Int = _
  cs_known(Self, String) -> Int = _
  cs_decode(Self, Bytes, String) -> String = _
  mk_start(Self, Bytes, String) -> Int = _
  mk_state(Self, Int) -> Int = _
  mk_png(Self, Int) -> Bytes = _
  nt_show(Self, String, String, String, String, String) -> Unit = _
  nt_cancel(Self, String) -> Unit = _
  nt_state(Self, Int) -> Int = _
  nt_text(Self, Int) -> String = _
  st_open(Self) -> Int = _
  st_h264(Self, Int, Bytes, Int, Int) -> Unit = _
  st_frame(Self, Int, Bytes, Int, Double) -> Unit = _
  st_jpeg(Self, Int, Bytes, Double) -> Unit = _
  st_next(Self, Int) -> String = _
  st_show(Self, Int, Double) -> Unit = _
  st_close(Self, Int) -> Unit = _
  st_h264_here(Self) -> Int = _
  cl_read(Self) -> Int = _
  cl_state(Self, Int) -> Int = _
  cl_picture(Self, Int) -> Int = _
  cl_text(Self, Int) -> String = _
  cl_png(Self, Int) -> Bytes = _
  cl_end(Self, Int) -> Unit = _
  cl_set(Self, String, Bytes, String) -> Unit = _
  dv_copy_shown(Self) -> Int = _
  dv_key_catch(Self, Int) -> Unit = _
  dv_ime_inset(Self) -> Double = _
  dv_keep_awake(Self, Int) -> Unit = _
  dv_haptic(Self, Int) -> Unit = _
  ncall_call(Self, String, String) -> Int = _
  ncall_state(Self, Int) -> Int = _
  ncall_result(Self, Int) -> String = _
  ncall_end(Self, Int) -> Unit = _
}

///|
impl Host with window_setup(_, _, _, _, _, _) {
  ()
}

///|
impl Host with window_inset(_) {
  false
}

///|
impl Host with window_drag(_) {
  ()
}

///|
impl Host with set_cursor(_, _) {
  ()
}

///|
impl Host with run(_, _, _, _, _, _, _) {
  abort("mbui: no host: an app's main imports mbui/host")
}

///|
impl Host with now(_) {
  0.0
}

///|
impl Host with wall_ms(_) {
  0.0
}

///|
impl Host with event_time(_) {
  -1.0
}

///|
impl Host with platform(_) {
  0
}

///|
impl Host with request_frame(_) {
  ()
}

///|
impl Host with wake_after(_, _) {
  ()
}

///|
impl Host with font_metrics(_, _, _, _, _) {
  ()
}

///|
impl Host with shape(_, _, _, _, _, _) {
  0
}

///|
impl Host with text_key(_, _, _, _, _) {
  0
}

///|
impl Host with glyph(_, _, _) {
  ()
}

///|
impl Host with face_add(_, _, _, _) {
  false
}

///|
impl Host with face_add_bytes(_, _, _, _) {
  false
}

///|
impl Host with face_clear(_, _) {
  ()
}

///|
impl Host with atlas_generation(_) {
  0
}

///|
impl Host with present(_, _, _, _, _, _) {
  ()
}

///|
impl Host with set_ime(_, _, _, _, _, _, _, _, _) {
  ()
}

///|
impl Host with clipboard_set(_, _) {
  ()
}

///|
impl Host with clipboard_set_secret(_, _, _) {
  ()
}

///|
impl Host with log(_, _) {
  ()
}

///|
impl Host with bench_mode(_) {
  0
}

///|
impl Host with set_outside(_, _) {
  false
}

///|
impl Host with frame_awaiting(_, _, _) {
  ()
}

///|
impl Host with own_clock(_) {
  false
}

///|
impl Host with reduce_motion(_) {
  false
}

///|
impl Host with exit(_, _) {
  ()
}

///|
impl Host with mem_bytes(_) {
  -1.0
}

///|
impl Host with set_back(_, _) {
  ()
}

///|
impl Host with back_enabled(_, _) {
  ()
}

///|
impl Host with reduce_transparency(_) {
  false
}

///|
impl Host with gpu_ms(_) {
  -1.0
}

///|
impl Host with env(_, _) {
  ""
}

///|
impl Host with set_app_state(_, _) {
  ()
}

///|
impl Host with system_dark(_) {
  false
}

///|
impl Host with set_dark(_, _) {
  ()
}

///|
impl Host with set_sideways(_, _) {
  ()
}

///|
impl Host with share(_, _, _, _, _) {
  false
}

///|
impl Host with shared_in(_) {
  ""
}

///|
impl Host with shared_in_file(_, _) {
  b""
}

///|
impl Host with app_version(_) {
  0
}

///|
impl Host with update_install(_, _, _, _, _) {
  ()
}

///|
impl Host with update_state(_) {
  ""
}

///|
impl Host with install_package(_, _, _) {
  ()
}

///|
impl Host with drive(_, _, _) {
  false
}

///|
impl Host with image_load(_, _, _) {
  0
}

///|
impl Host with image_load_bytes(_, _, _) {
  0
}

///|
impl Host with image_info(_, _, _) {
  0
}

///|
impl Host with image_free(_, _) {
  ()
}

///|
impl Host with image_pixels(_, _, _) {
  false
}

///|
impl Host with view_site_next(_, _) {
  ""
}

///|
impl Host with view_site_body(_, _, _) {
  b""
}

///|
impl Host with view_site_head(_, _, _, _, _) {
  ()
}

///|
impl Host with view_site_chunk(_, _, _, _) {
  ()
}

///|
impl Host with view_site_end(_, _, _, _) {
  ()
}

///|
impl Host with view_site_state(_, _) {
  ""
}

///|
impl Host with view_site_load(_, _, _) {
  ()
}

///|
impl Host with view_tell(_, _, _, _) {
  ()
}

///|
impl Host with view_open(_, _, _) {
  0
}

///|
impl Host with view_place(_, _, _, _, _, _, _, _, _, _, _, _) {
  ()
}

///|
impl Host with view_close(_, _) {
  ()
}

///|
impl Host with view_control(_, _, _, _) {
  ()
}

///|
impl Host with view_info(_, _, _) {
  -1
}

///|
impl Host with view_read_next(_, _, _) {
  0
}

///|
impl Host with view_read_answer(_, _, _, _, _) {
  ()
}

///|
impl Host with pdf_open(_, _) {
  0
}

///|
impl Host with pdf_pages(_, _) {
  0
}

///|
impl Host with pdf_page_size(_, _, _, _) {
  ()
}

///|
impl Host with pdf_page_load(_, _, _, _) {
  0
}

///|
impl Host with pdf_close(_, _) {
  ()
}

///|
impl Host with view_text(_, _, _) {
  None
}

///|
impl Host with view_still(_, _) {
  b""
}

///|
impl Host with save_file(_, _, _) {
  false
}

///|
impl Host with word_at(_, _, _) {
  (-1, -1)
}

///|
impl Host with open_url(_, _) {
  false
}

///|
impl Host with over_done(_, _) {
  ()
}

///|
impl Host with open_tab(_, _) {
  false
}

///|
impl Host with hold_words(_, _, _, _) {
  ()
}

///|
impl Host with post_take(_) {
  0
}

///|
impl Host with post_next(_) {
  None
}

///|
impl Host with ref_begin(_, _, _, _, _) {
  ()
}

///|
impl Host with ref_text(_, _, _, _, _, _, _, _, _) {
  ()
}

///|
impl Host with ref_end(_, _) {
  false
}

///|
impl Host with ref_frame(_, _) {
  false
}

///|
impl Host with bl_start(_, _) {
  0
}

///|
impl Host with bl_port(_, _) {
  0
}

///|
impl Host with bl_open(_, _, _) {
  0
}

///|
impl Host with bl_back(_, _) {
  ""
}

///|
impl Host with bl_end(_, _) {
  ()
}

///|
impl Host with pk_start(_, _) {
  0
}

///|
impl Host with pk_state(_, _) {
  0
}

///|
impl Host with pk_count(_, _) {
  0
}

///|
impl Host with pk_name(_, _, _) {
  ""
}

///|
impl Host with pk_bytes(_, _, _) {
  b""
}

///|
impl Host with pk_end(_, _) {
  ()
}

///|
impl Host with kp_begin(_, _, _, _) {
  0
}

///|
impl Host with kp_append(_, _, _) {
  0
}

///|
impl Host with kp_finish(_, _) {
  ()
}

///|
impl Host with kp_state(_, _) {
  0
}

///|
impl Host with kp_where(_, _) {
  ""
}

///|
impl Host with kp_end(_, _) {
  ()
}

///|
impl Host with ga_access(_) {
  0
}

///|
impl Host with ga_ask(_) {
  ()
}

///|
impl Host with ga_answers(_) {
  0
}

///|
impl Host with ga_read(_) {
  0
}

///|
impl Host with ga_read_state(_, _) {
  0
}

///|
impl Host with ga_read_rows(_, _) {
  ""
}

///|
impl Host with ga_read_end(_, _) {
  ()
}

///|
impl Host with pk_photo(_, _) {
  0
}

///|
impl Host with cs_known(_, _) {
  0
}

///|
impl Host with cs_decode(_, _, _) {
  ""
}

///|
impl Host with mk_start(_, _, _) {
  0
}

///|
impl Host with mk_state(_, _) {
  0
}

///|
impl Host with mk_png(_, _) {
  b""
}

///|
impl Host with nt_show(_, _, _, _, _, _) {
  ()
}

///|
impl Host with nt_cancel(_, _) {
  ()
}

///|
impl Host with nt_state(_, _) {
  0
}

///|
impl Host with nt_text(_, _) {
  ""
}

///|
impl Host with st_open(_) {
  0
}

///|
impl Host with st_h264(_, _, _, _, _) {
  ()
}

///|
impl Host with st_frame(_, _, _, _, _) {
  ()
}

///|
impl Host with st_jpeg(_, _, _, _) {
  ()
}

///|
impl Host with st_next(_, _) {
  ""
}

///|
impl Host with st_show(_, _, _) {
  ()
}

///|
impl Host with st_close(_, _) {
  ()
}

///|
impl Host with st_h264_here(_) {
  0
}

///|
impl Host with cl_read(_) {
  0
}

///|
impl Host with cl_state(_, _) {
  0
}

///|
impl Host with cl_picture(_, _) {
  0
}

///|
impl Host with cl_text(_, _) {
  ""
}

///|
impl Host with cl_png(_, _) {
  b""
}

///|
impl Host with cl_end(_, _) {
  ()
}

///|
impl Host with cl_set(_, _, _, _) {
  ()
}

///|
impl Host with dv_copy_shown(_) {
  0
}

///|
impl Host with dv_key_catch(_, _) {
  ()
}

///|
impl Host with dv_ime_inset(_) {
  0.0
}

///|
impl Host with dv_keep_awake(_, _) {
  ()
}

///|
impl Host with dv_haptic(_, _) {
  ()
}

///|
impl Host with ncall_call(_, _, _) {
  0
}

///|
impl Host with ncall_state(_, _) {
  0
}

///|
impl Host with ncall_result(_, _) {
  ""
}

///|
impl Host with ncall_end(_, _) {
  ()
}

///|
priv struct NoHost {}

///|
impl Host for NoHost

///|
// set as the program starts (mbui/host's init), or by a Tester for its test
let current : Ref[&Host] = { val: NoHost::{  } }

///|
/// Who answers from now on: the platform's (mbui/host's init, as the program starts), a Tester's fake.
pub fn set_host(h : &Host) -> Unit {
  current.val = h
}

///|
/// The desktop's window as the app wants it, said before `run`: its first size (`w` by `h`; MBUI_WIN=<w>x<h> still
/// has the last word) and its least (`min_w` by `min_h`), and with `inset` no title bar of the system's: the app's own
/// top row is it (macOS: the window's buttons in it, 16 in and centred on its first 44; the app drags the window by
/// it, Ctx::window_drag). Nothing where there is no window to size (iOS, Android, a browser's page).
pub fn window_setup(min_w : Double, min_h : Double, w : Double, h : Double, inset? : Bool = false) -> Unit {
  current.val.window_setup(min_w, min_h, w, h, inset)
}

///|
/// Whether the window's buttons are in the app's top row now (an inset window, not full screen): the room the app
/// leaves them there.
pub fn window_inset() -> Bool {
  current.val.window_inset()
}

///|
/// The press under way moves the window (a press on the app's own top row, @ui's Ctx::window_drag): the host's from
/// here, as its title bar's would be.
pub fn window_drag() -> Unit {
  current.val.window_drag()
}

///|
/// The pointer's shape from now on: 0 the arrow, 1 a hand, 2 the text's I-beam, 3 resizing sideways, 4 up and down,
/// 5 an open hand. Nothing where there is no pointer.
pub fn set_cursor(kind : Int) -> Unit {
  current.val.set_cursor(kind)
}

///|
pub fn run(
  title : String,
  frame : FuncRef[(Double, Double, Double, Double) -> Unit],
  pointer : FuncRef[(Int, Double, Double, Int) -> Unit],
  wheel : FuncRef[(Double, Double, Double, Double, Int) -> Unit],
  key : FuncRef[(Int, Int) -> Unit],
  text : FuncRef[(Int, String, Int, Int) -> Unit],
) -> Unit {
  current.val.run(title, frame, pointer, wheel, key, text)
}

///|
pub fn now() -> Double {
  current.val.now()
}

///|
/// The time of day, in ms since 1970 (UTC), as the machine's clock has it: for what is shown of it only (@ui.wall_ms).
/// A run to a declared moment (a scripted shot) has its own: from a fixed day, on with its frames' clock.
pub fn wall_ms() -> Double {
  current.val.wall_ms()
}

///|
/// When the input event being delivered happened, on now()'s clock (ms):
/// a touch's own time, which comes before it is handled (a frame's touches
/// are handled together); negative when the host doesn't say.
pub fn event_time() -> Double {
  current.val.event_time()
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser.
pub fn platform() -> Int {
  current.val.platform()
}

///|
pub fn request_frame() -> Unit {
  current.val.request_frame()
}

///|
pub fn wake_after(ms : Double) -> Unit {
  current.val.wake_after(ms)
}

///|
/// Ascent, descent and line height of the system font (or its code face,
/// `style` & style_mono; slanted with style_italic) at this size and weight,
/// then the ascent and descent of the font a Han ideograph falls back to, then
/// 1 where the host sets lines of words on whole device pixels (Android), 0
/// where not (six numbers in `out`).
pub fn font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  current.val.font_metrics(size, weight, style, out)
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
  current.val.shape(text, size, weight, style, out)
}

///|
/// The glyph key of `text` drawn whole as one piece (the way the platform draws it in a line: a word whose letters
/// join), for `glyph`.
pub fn text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  current.val.text_key(text, size, weight, style)
}

///|
pub fn glyph(key : Int, out : FixedArray[Double]) -> Unit {
  current.val.glyph(key, out)
}

///|
/// A font file (TrueType or OpenType, at `path`) made part of face `face` (style.mbt: face_ui, face_text, face_code,
/// or 4 to 15 for what names it), for `weight` (0: a variable file, every weight from it). False when the host could
/// not read it as a font (the face as it was). What was shaped or drawn before is the host's to forget
/// (atlas_generation moves on).
pub fn face_add(face : Int, path : String, weight : Int) -> Bool {
  current.val.face_add(face, path, weight)
}

///|
/// As face_add, the font's file being `data` (one the app carries in itself, or has fetched and kept).
pub fn face_add_bytes(face : Int, data : Bytes, weight : Int) -> Bool {
  current.val.face_add_bytes(face, data, weight)
}

///|
/// Face `face` given up: what was in it is in the system's face again.
pub fn face_clear(face : Int) -> Unit {
  current.val.face_clear(face)
}

///|
pub fn atlas_generation() -> Int {
  current.val.atlas_generation()
}

///|
pub fn present(
  buf : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  current.val.present(buf, count, r, g, b)
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
  current.val.set_ime(active, x, y, w, h, text, sel_start, sel_end)
}

///|
pub fn clipboard_set(s : String) -> Unit {
  current.val.clipboard_set(s)
}

///|
/// A secret put on the system's clipboard: marked sensitive where the system masks such (Android 13 on), and taken
/// off `clear_ms` later unless something else was copied meanwhile (0: kept). Elsewhere as clipboard_set.
pub fn clipboard_set_secret(s : String, clear_ms~ : Double) -> Unit {
  current.val.clipboard_set_secret(s, clear_ms)
}

///|
pub fn log(s : String) -> Unit {
  current.val.log(s)
}

///|
pub fn bench_mode() -> Int {
  current.val.bench_mode()
}

///|
/// Who is told as what the host does for the app is done (`f(kind, id, state)`: kind 1 an image or a PDF's page
/// decoded, 2 a native view ready — a page loaded and its picture taken, a video's first frame —; state 1 done, -1
/// failed), on the main thread, between frames. False where the host sends no such events.
pub fn set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool {
  current.val.set_outside(f)
}

///|
/// As the frame just built left it: how many of the app's asks the host has not answered yet (effect.mb's outside)
/// and what they are ("" when none). A run to a declared moment keeps its clock still while any is awaited.
pub fn frame_awaiting(awaiting : Int, what : String) -> Unit {
  current.val.frame_awaiting(awaiting, what)
}

///|
/// Whether the run is on a clock of its own (its frames', 1/60 s a frame from 0, still while the app awaits the host:
/// a picture's run, mac_app.m's settle, MBView's shot_at), not the machine's.
pub fn own_clock() -> Bool {
  current.val.own_clock()
}

///|
/// Whether the system asks for less motion (macOS and iOS: Reduce Motion;
/// Android: animations off, its animator duration scale 0). Read at most
/// once a second.
pub fn reduce_motion() -> Bool {
  current.val.reduce_motion()
}

///|
pub fn exit(code : Int) -> Unit {
  current.val.exit(code)
}

///|
pub fn mem_bytes() -> Double {
  current.val.mem_bytes()
}

///|
/// Where the system's back goes (Android's back gesture, predictive or not,
/// and its back button; a mouse's back button): `back(kind, x, progress,
/// edge)`, kind 0 a back gesture started at x (logical pixels), 1 it moved
/// (to x, `progress` 0-1 as the system has it), 2 let go to go back (or a
/// back with no gesture), 3 called off; edge 0 the left, 1 the right.
/// Called before `run`.
pub fn set_back(back : FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit {
  current.val.set_back(back)
}

///|
/// Whether the app takes back now (a page to go back to): when not, the
/// system does what it does (Android leaves the app).
pub fn back_enabled(on : Bool) -> Unit {
  current.val.back_enabled(on)
}

///|
/// Whether the system asks for less transparency (glass drawn solid):
/// macOS's and iOS's Reduce Transparency, Windows' transparency effects
/// turned off; Android has no such setting (never).
pub fn reduce_transparency() -> Bool {
  current.val.reduce_transparency()
}

///|
/// The GPU's time for the last frame it finished, in ms (-1: not known on
/// this host).
pub fn gpu_ms() -> Double {
  current.val.gpu_ms()
}

///|
/// An environment variable ("" when unset; in a browser, the page's query
/// parameter of that name).
pub fn env(name : String) -> String {
  current.val.env(name)
}

///|
/// Who to tell when the app comes to the front or leaves it: `f` gets 1 while its window is shown, | 2 while it is
/// also in front (the key window of the active app; Android: the activity resumed with the window's focus). Told on
/// each change, on the app's thread (Android: before the GL thread pauses). Hosts that never tell leave the app as
/// shown and in front.
pub fn set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit {
  current.val.set_app_state(f)
}

///|
/// Whether the system is set to dark (macOS's appearance, Android's night mode, iOS's interface style, the browser's
/// prefers-color-scheme): what an app that follows the system shows. Asked each frame; a host asks for a frame when
/// it changes. Hosts that cannot tell say light.
pub fn system_dark() -> Bool {
  current.val.system_dark()
}

///|
/// The app is drawn dark (or light) from now on: the host's own parts follow it (Android's status and navigation
/// bars' icons, the Mac window's title bar). Said when it changes.
pub fn set_dark(dark : Bool) -> Unit {
  current.val.set_dark(dark)
}

///|
/// Turned sideways for a film (still.fail's player, Player.kt): landscape asked for (a phone with rotation locked
/// turns too) and the system's bars out of the way (a swipe brings them for a while); `false`, upright as it was.
/// Android does it (the activity's requested orientation, its window's insets controller); elsewhere nothing turns.
pub fn set_sideways(on : Bool) -> Unit {
  current.val.set_sideways(on)
}

///|
/// Words (`text`), or a file of `data` named `name` (`mime`), handed to another app through the system's share sheet
/// (Android's chooser, macOS's sharing picker); false where there is none (or no app takes it).
pub fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  current.val.share(text, name, mime, data)
}

///|
/// What another app shared into this one since last asked (Android's ACTION_SEND of text or files, ACTION_SEND_MULTIPLE
/// of files; MBUI_SHARE_FILES, paths split by |, on macOS for scripted runs), as JSON text `{"text","title","files"}`,
/// `files` each `{"name","type","size"}` (absent when none); "" when nothing was.
pub fn shared_in() -> String {
  current.val.shared_in()
}

///|
/// The i-th of the files shared in (`shared_in`'s `files`), taken once: empty after, or where there is none.
pub fn shared_in_file(i : Int) -> Bytes {
  current.val.shared_in_file(i)
}

///|
/// This build's version code, as the system has it (Android's); 0 where the app does not update itself.
pub fn app_version() -> Int {
  current.val.app_version()
}

///|
/// A newer build at `url` (its `sha256`, `size` bytes) downloaded as `name`, checked and handed to the system's
/// installer (Android: still.fail's Updates.kt); nothing elsewhere. How it goes: `update_state`.
pub fn update_install(url : String, sha256 : String, size : Double, name : String) -> Unit {
  current.val.update_install(url, sha256, size, name)
}

///|
/// How an update goes, as JSON text: `{"phase","percent","error"}` (phase idle, allow: the person's leave to install
/// apps asked for, downloading, retrying, installing, handed, failed); "" where there is none.
pub fn update_state() -> String {
  current.val.update_state()
}

///|
/// A package (an APK a chat has) handed to the system's installer, which asks the person to confirm (Android:
/// still.fail's Install.kt installApk). What comes of it, when it is not installed, comes on @host.system_channel
/// (system.mbt `install`: the leave to install apps asked for, or why it failed: "unsupported" where there is no
/// installer).
pub fn install_package(name : String, data : Bytes) -> Unit {
  current.val.install_package(name, data)
}

///|
/// A scripted run's input given to the host to send as its own (src/ui/drive.mbt): `drive_insert` words committed and
/// `drive_mark` composed by the input method (macOS: NSTextInputClient's insertText and setMarkedText; Android: the
/// view's InputConnection), `drive_newline` its Enter, `drive_paste` the system's paste of the clipboard (Cmd+V,
/// KEYCODE_PASTE), `drive_backspace`, `drive_shot` the window's picture saved at `text` (a path); 6 and 7 one of the
/// app's notifications (notify.mbt) whose title or words hold `text`, tapped (6) or only looked for (7), false when none
/// does; 8 the window resized to "<w>x<h>"; 9 the directory `text` watched for what the run's runner has done, each
/// file come there posted on channel "runner" (done_watch.h: macOS, Android, Windows). False where the host has no
/// such path (the caller sends it to the app itself).
pub fn drive(kind : Int, text : String) -> Bool {
  current.val.drive(kind, text)
}

///|
/// Starts decoding the image at `src` (a file path or an http(s) URL);
/// returns its id.
pub fn image_load(src : String, max_px : Int) -> Int {
  current.val.image_load(src, max_px)
}

///|
/// Starts decoding an encoded image (JPEG, PNG, HEIC, WebP…) in memory.
pub fn image_load_bytes(data : Bytes, max_px : Int) -> Int {
  current.val.image_load_bytes(data, max_px)
}

///|
/// 0 while decoding, 1 when ready, -1 if it failed. Ready, `out` gets the
/// decoded width and height and the original's, in pixels.
pub fn image_info(id : Int, out : FixedArray[Double]) -> Int {
  current.val.image_info(id, out)
}

///|
pub fn image_free(id : Int) -> Unit {
  current.val.image_free(id)
}

///|
/// A ready image's pixels as decoded (image_info's width by height, rows from the top, RGBA premultiplied) into `out`
/// (at least w × h × 4 long): false where it is not ready or cannot be read back.
pub fn image_pixels(id : Int, out : FixedArray[Byte]) -> Bool {
  current.val.image_pixels(id, out)
}

///|
/// What a site (a view of kind 3) has to say, oldest first: a JSON text, "" when nothing waits. `{"req":n,"method",
/// "path","headers":[[k,v]…],"page":true|false}` a request of its own host the app answers (`view_site_head`, then
/// `view_site_chunk`s, then `view_site_end`); `{"gone":n}` a request the page let go of (nothing more of it is taken);
/// `{"leave":url}` a link to elsewhere tapped (not followed); `{"late":n}` a request with no head after `head_wait_ms`
/// (view_tell 3; it waits on); `{"slow":n}` an answer more of which waits than `backlog` (the host takes no more of
/// it, and fails its body once what waits is read: the app ends it). Of a page's or a site's, `{"said":text}`: what
/// its page's scripts said to the app (`mbuiHost.post(text)`), in the order said.
pub fn view_site_next(id : Int) -> String {
  current.val.view_site_next(id)
}

///|
/// A request's body (empty when it has none, or the host's web view does not hand it over: Android's).
pub fn view_site_body(id : Int, req : Int) -> Bytes {
  current.val.view_site_body(id, req)
}

///|
/// A request's answer begins: its status and headers (`[[k,v]…]` as JSON text).
pub fn view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  current.val.view_site_head(id, req, status, headers)
}

///|
/// The next piece of a request's answer's body.
pub fn view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  current.val.view_site_chunk(id, req, data)
}

///|
/// A request's answer ends ("" whole; else why it broke off). A request with no head yet fails with it.
pub fn view_site_end(id : Int, req : Int, error : String) -> Unit {
  current.val.view_site_end(id, req, error)
}

///|
/// Where the site's page is: `{"path","back","forward","loading","title"}` as JSON text.
pub fn view_site_state(id : Int) -> String {
  current.val.view_site_state(id)
}

///|
/// The site's page at `path` of its own host.
pub fn view_site_load(id : Int, path : String) -> Unit {
  current.val.view_site_load(id, path)
}

///|
/// What the app tells a view beyond its controls: `what` 1 a script to run in its page (a page's or a site's): in the
/// page there once it has loaded, or has said something (`{"said":…}`) since it started; one sent while a page loads
/// waits for it, all in the order sent. 2 who takes a finger on it: "all", "through", "pinch" or "vertical", then the
/// slop in points (ui's NativeView::touch). 3 a site's settings, as JSON: `head_wait_ms` (how long a request waits for
/// its head before the host says `{"late":n}`, still waiting), `backlog` (how many bytes of an answer may wait for the
/// page to read them before the host says `{"slow":n}` and takes no more of it).
pub fn view_tell(id : Int, what : Int, text : String) -> Unit {
  current.val.view_tell(id, what, text)
}

///|
/// A native view of `kind`: 1 a video (and audio) player, its bytes read through the app (`view_read_next`), `arg`
/// its MIME type ("video/mp4"); 2 a web page of `arg`'s HTML, its scripts on, nothing of the device's files or the
/// app's reachable, its links not followed; 3 a site served by the app: a web view at `arg` (a path) of a host of its
/// own, each of whose requests the app answers (`view_site_next`). Hidden until placed. 0 when this host has no such
/// view.
pub fn view_open(kind : Int, arg : String) -> Int {
  current.val.view_open(kind, arg)
}

///|
/// Where the view shows, in the app's coordinates (logical pixels from the window's top left): its content in (x, y,
/// w, h) (a video's picture is stretched to it), its corners round by `radius` (0: square), seen only within the clip
/// (cx0, cy0)-(cx1, cy1); hidden when not `shown`. Told again whenever it moves (each frame it does).
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
  current.val.view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, radius, shown)
}

///|
/// The view gone (its player stopped, its page closed).
pub fn view_close(id : Int) -> Unit {
  current.val.view_close(id)
}

///|
/// A player told: `op` 1 play, 2 pause, 3 to `value` ms (the frame there, exactly), 4 at `value` times its speed; a
/// site: 5 back, 6 forward, 7 reload, 8 laid out at its rect over `value` and drawn at `value` times (a viewport's
/// own size shown smaller).
pub fn view_control(id : Int, op : Int, value : Double) -> Unit {
  current.val.view_control(id, op, value)
}

///|
/// How the view stands: -1 failed (a file the player cannot play, a page that cannot load), 0 opening, 1 ready.
/// `out` (10): its length in ms (-1 not known), where it is (ms), playing (1), the picture's own width and height
/// (pixels), the bytes it has been given, whether a frame has been drawn (a page: loaded), buffering (1), how far on it
/// has what it needs to play (ms; 0 not said), played to its end (1).
pub fn view_info(id : Int, out : FixedArray[Double]) -> Int {
  current.val.view_info(id, out)
}

///|
/// A read the player waits on: its id (0: none waiting), `out` [0] its offset, [1] how many bytes it wants. Each is
/// answered once (`view_read_answer`); the host asks for a frame when one comes.
pub fn view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  current.val.view_read_next(id, out)
}

///|
/// Read `req`'s answer: the bytes from its offset (at most as many as it wanted; fewer is fine, none only at the
/// file's end), `total` the file's whole size (-1 not known: Apple's player needs it, so give it); -2: it could not be
/// read (the player fails).
pub fn view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit {
  current.val.view_read_answer(id, req, data, total)
}

///|
/// A PDF opened from its bytes: its id, or 0 where the host draws none.
pub fn pdf_open(data : Bytes) -> Int {
  current.val.pdf_open(data)
}

///|
/// How many pages it has; -1 when it could not be opened.
pub fn pdf_pages(doc : Int) -> Int {
  current.val.pdf_pages(doc)
}

///|
/// A page's size in points (`out` [0] width, [1] height).
pub fn pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  current.val.pdf_page_size(doc, page, out)
}

///|
/// A page drawn (on white, off the app's thread) at most `max_px` on its longer side: an image's id, as image_load's
/// (image_info, image_free).
pub fn pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  current.val.pdf_page_load(doc, page, max_px)
}

///|
pub fn pdf_close(doc : Int) -> Unit {
  current.val.pdf_close(doc)
}

///|
/// What a video view says beyond its info: `what` 1 its frames' times (ms, comma between: view_control 20 asks them
/// read), 2 how a frame grabbed stands (view_control 21 at a time in ms: "1" grabbing, "2" here, "-1" failed, "0"
/// none); None while not known.
pub fn view_text(id : Int, what : Int) -> String? {
  current.val.view_text(id, what)
}

///|
/// A video view's frame grabbed (PNG), taken once.
pub fn view_still(id : Int) -> Bytes {
  current.val.view_still(id)
}

///|
/// A file put where the system keeps downloads (Android: Downloads, through MediaStore; macOS: ~/Downloads): true
/// once it is there.
pub fn save_file(name : String, data : Bytes) -> Bool {
  current.val.save_file(name, data)
}

///|
/// The word of `text` around `off` (UTF-16 offsets, its start and end) as the system finds words (Android's
/// BreakIterator, Apple's CFStringTokenizer: a dictionary's words in Chinese and Japanese); (-1, -1) where the host has
/// no such thing (Windows here) or `off` is in no word.
pub fn word_at(text : String, off : Int) -> (Int, Int) {
  current.val.word_at(text, off)
}

///|
/// `url` handed to the system: the browser, or the app it belongs to (Android's ACTION_VIEW, macOS's NSWorkspace,
/// iOS's UIApplication, Windows' ShellExecute). False when nothing took it.
pub fn open_url(url : String) -> Bool {
  current.val.open_url(url)
}

///|
/// The app over another app (system.mbt `over`: Android's OverActivity, a share sheet over the app it came from) done:
/// it goes, back to the app it was over; `open_app`, on into the app's own window. Nothing where it never is over one.
pub fn over_done(open_app~ : Bool) -> Unit {
  current.val.over_done(open_app)
}

///|
/// A page shown in a browser's tab over the app, the app under it (Android's Custom Tab, the system's browser where
/// none takes one); elsewhere as open_url. False when nothing took it.
pub fn open_tab(url : String) -> Bool {
  current.val.open_tab(url)
}

///|
/// What the notice says that holds the app up while it listens for a browser coming back (@host.browser_login, the
/// core's loopback listeners: Android's foreground service, in `channel`, named as the system's settings list it);
/// said before the browser opens, kept for the next. Other hosts keep no notice.
pub fn hold_words(channel~ : String, title~ : String, body~ : String) -> Unit {
  current.val.hold_words(channel, title, body)
}

///|
/// What was posted from outside the frames since the last take (`mb_post`, any thread: post.h), taken now as a frame
/// begins: how many. They are handed on one at a time (`post_next`), in the order posted.
pub fn post_take() -> Int {
  current.val.post_take()
}

///|
/// The next message taken (`post_take`): its channel, its JSON and the bytes beside it (empty: none). None when all
/// taken are handed on, or dropped since (`mb_post_drop`: a core stopped).
pub fn post_next() -> (String, String, Bytes)? {
  current.val.post_next()
}

///|
/// Starts a picture `w`×`h` points at `scale` pixels a point, on a ground of `bg` (0xRRGGBB).
pub fn ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit {
  current.val.ref_begin(w, h, scale, bg)
}

///|
/// `text` drawn into it by the platform, in its system font (style: style_italic, style_mono) at `size` and
/// `weight`, starting at `x` with its baseline at `base`, in `color` (0xRRGGBB), as one line. `out`: the width it
/// advances, then its ink box (left, top, right, bottom, in points from x and the baseline, y down; all 0 if the host
/// does not say).
pub fn ref_text(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  x : Double,
  base : Double,
  color : Int,
  out : FixedArray[Double],
) -> Unit {
  current.val.ref_text(text, size, weight, style, x, base, color, out)
}

///|
/// The picture written as `name`.png.
pub fn ref_end(name : String) -> Bool {
  current.val.ref_end(name)
}

///|
/// The window's picture as `name`.png: the frame last drawn, or (Android, a browser) the one drawn next; the caller
/// keeps both the same.
pub fn ref_frame(name : String) -> Bool {
  current.val.ref_frame(name)
}

///|
fn bl_start(path : String) -> Int {
  current.val.bl_start(path)
}

///|
fn bl_port(id : Int) -> Int {
  current.val.bl_port(id)
}

///|
fn bl_open(id : Int, url : String) -> Int {
  current.val.bl_open(id, url)
}

///|
fn bl_back(id : Int) -> String {
  current.val.bl_back(id)
}

///|
fn bl_end(id : Int) -> Unit {
  current.val.bl_end(id)
}

///|
fn pk_start(kind : Int) -> Int {
  current.val.pk_start(kind)
}

///|
fn pk_state(id : Int) -> Int {
  current.val.pk_state(id)
}

///|
fn pk_count(id : Int) -> Int {
  current.val.pk_count(id)
}

///|
fn pk_name(id : Int, i : Int) -> String {
  current.val.pk_name(id, i)
}

///|
fn pk_bytes(id : Int, i : Int) -> Bytes {
  current.val.pk_bytes(id, i)
}

///|
fn pk_end(id : Int) -> Unit {
  current.val.pk_end(id)
}

///|
fn kp_begin(name : String, mime : String, way : Int) -> Int {
  current.val.kp_begin(name, mime, way)
}

///|
fn kp_append(id : Int, data : Bytes) -> Int {
  current.val.kp_append(id, data)
}

///|
fn kp_finish(id : Int) -> Unit {
  current.val.kp_finish(id)
}

///|
fn kp_state(id : Int) -> Int {
  current.val.kp_state(id)
}

///|
fn kp_where(id : Int) -> String {
  current.val.kp_where(id)
}

///|
fn kp_end(id : Int) -> Unit {
  current.val.kp_end(id)
}

///|
fn ga_access() -> Int {
  current.val.ga_access()
}

///|
fn ga_ask() -> Unit {
  current.val.ga_ask()
}

///|
fn ga_answers() -> Int {
  current.val.ga_answers()
}

///|
fn ga_read() -> Int {
  current.val.ga_read()
}

///|
fn ga_read_state(id : Int) -> Int {
  current.val.ga_read_state(id)
}

///|
fn ga_read_rows(id : Int) -> String {
  current.val.ga_read_rows(id)
}

///|
fn ga_read_end(id : Int) -> Unit {
  current.val.ga_read_end(id)
}

///|
fn pk_photo(src : String) -> Int {
  current.val.pk_photo(src)
}

///|
fn cs_known(charset : String) -> Int {
  current.val.cs_known(charset)
}

///|
fn cs_decode(data : Bytes, charset : String) -> String {
  current.val.cs_decode(data, charset)
}

///|
fn mk_start(image : Bytes, marks : String) -> Int {
  current.val.mk_start(image, marks)
}

///|
fn mk_state(id : Int) -> Int {
  current.val.mk_state(id)
}

///|
fn mk_png(id : Int) -> Bytes {
  current.val.mk_png(id)
}

///|
fn nt_show(channel : String, tag : String, title : String, body : String, opens : String) -> Unit {
  current.val.nt_show(channel, tag, title, body, opens)
}

///|
fn nt_cancel(tag : String) -> Unit {
  current.val.nt_cancel(tag)
}

///|
fn nt_state(what : Int) -> Int {
  current.val.nt_state(what)
}

///|
fn nt_text(what : Int) -> String {
  current.val.nt_text(what)
}

///|
fn st_open() -> Int {
  current.val.st_open()
}

///|
fn st_h264(id : Int, avcc : Bytes, w : Int, h : Int) -> Unit {
  current.val.st_h264(id, avcc, w, h)
}

///|
fn st_frame(id : Int, data : Bytes, key : Int, ts : Double) -> Unit {
  current.val.st_frame(id, data, key, ts)
}

///|
fn st_jpeg(id : Int, data : Bytes, ts : Double) -> Unit {
  current.val.st_jpeg(id, data, ts)
}

///|
fn st_next(id : Int) -> String {
  current.val.st_next(id)
}

///|
fn st_show(id : Int, ts : Double) -> Unit {
  current.val.st_show(id, ts)
}

///|
fn st_close(id : Int) -> Unit {
  current.val.st_close(id)
}

///|
fn st_h264_here() -> Int {
  current.val.st_h264_here()
}

///|
fn cl_read() -> Int {
  current.val.cl_read()
}

///|
fn cl_state(id : Int) -> Int {
  current.val.cl_state(id)
}

///|
fn cl_picture(id : Int) -> Int {
  current.val.cl_picture(id)
}

///|
fn cl_text(id : Int) -> String {
  current.val.cl_text(id)
}

///|
fn cl_png(id : Int) -> Bytes {
  current.val.cl_png(id)
}

///|
fn cl_end(id : Int) -> Unit {
  current.val.cl_end(id)
}

///|
fn cl_set(text : String, png : Bytes, label : String) -> Unit {
  current.val.cl_set(text, png, label)
}

///|
fn dv_copy_shown() -> Int {
  current.val.dv_copy_shown()
}

///|
fn dv_key_catch(on : Int) -> Unit {
  current.val.dv_key_catch(on)
}

///|
fn dv_ime_inset() -> Double {
  current.val.dv_ime_inset()
}

///|
fn dv_keep_awake(on : Int) -> Unit {
  current.val.dv_keep_awake(on)
}

///|
fn dv_haptic(kind : Int) -> Unit {
  current.val.dv_haptic(kind)
}

///|
fn ncall_call(name : String, params : String) -> Int {
  current.val.ncall_call(name, params)
}

///|
fn ncall_state(id : Int) -> Int {
  current.val.ncall_state(id)
}

///|
fn ncall_result(id : Int) -> String {
  current.val.ncall_result(id)
}

///|
fn ncall_end(id : Int) -> Unit {
  current.val.ncall_end(id)
}
