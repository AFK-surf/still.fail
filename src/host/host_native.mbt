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

///|
#borrow(s)
extern "C" fn ffi_clipboard_secret(s : String, clear_ms : Double) -> Unit = "mb_host_clipboard_secret"

#borrow(s)
extern "C" fn ffi_log(s : String) -> Unit = "mb_host_log"

extern "C" fn ffi_bench_mode() -> Int = "mb_host_bench_mode"

///|
extern "C" fn ffi_set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Int = "mb_host_set_outside"

///|
#borrow(what)
#borrow(what)
extern "C" fn ffi_frame_awaiting(awaiting : Int, what : String) -> Unit = "mb_host_frame_awaiting"

///|
extern "C" fn ffi_reduce_motion() -> Int = "mb_host_reduce_motion"

///|
extern "C" fn ffi_own_clock() -> Int = "mb_host_own_clock"

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

extern "C" fn ffi_system_dark() -> Int = "mb_host_system_dark"

extern "C" fn ffi_set_dark(dark : Int) -> Unit = "mb_host_set_dark"

///|
extern "C" fn ffi_set_sideways(on : Int) -> Unit = "mb_host_set_sideways"


///|
#borrow(text, name, mime, data)
extern "C" fn ffi_share(text : String, name : String, mime : String, data : Bytes) -> Int = "mb_host_share"

///|
extern "C" fn ffi_shared_in() -> String = "mb_host_shared_in"

///|
extern "C" fn ffi_shared_in_file(i : Int) -> Bytes = "mb_host_shared_in_file"

///|
#borrow(text)
extern "C" fn ffi_word_at(text : String, off : Int) -> Double = "mb_host_word_at"

///|
#borrow(url)
extern "C" fn ffi_open_url(url : String) -> Int = "mb_host_open_url"

///|
#borrow(url)
extern "C" fn ffi_open_tab(url : String) -> Int = "mb_host_open_tab"

///|
extern "C" fn ffi_over_done(open_app : Int) -> Unit = "mb_host_over_done"

///|
#borrow(channel, title, body)
extern "C" fn ffi_hold_words(channel : String, title : String, body : String) -> Unit = "mb_host_hold_words"

///|
extern "C" fn ffi_app_version() -> Int = "mb_host_app_version"

///|
#borrow(url, sha256, name)
extern "C" fn ffi_update_install(url : String, sha256 : String, size : Double, name : String) -> Unit = "mb_host_update_install"

///|
extern "C" fn ffi_update_state() -> String = "mb_host_update_state"

///|
#borrow(name, data)
extern "C" fn ffi_install_package(name : String, data : Bytes) -> Unit = "mb_host_install_package"

///|
extern "C" fn ffi_window_setup(min_w : Double, min_h : Double, w : Double, h : Double, inset : Int) -> Unit = "mb_host_window_setup"

///|
extern "C" fn ffi_window_inset() -> Int = "mb_host_window_inset"

///|
extern "C" fn ffi_window_drag() -> Unit = "mb_host_window_drag"

///|
extern "C" fn ffi_set_cursor(kind : Int) -> Unit = "mb_host_set_cursor"

///|
/// The desktop's window as the app wants it, said before `run`: its first size (`w` by `h`; MBUI_WIN=<w>x<h> still
/// has the last word) and its least (`min_w` by `min_h`), and with `inset` no title bar of the system's: the app's own
/// top row is it (macOS: the window's buttons in it, 16 in and centred on its first 44; the app drags the window by
/// it, Ctx::window_drag). Nothing where there is no window to size (iOS, Android, a browser's page).
pub fn window_setup(min_w : Double, min_h : Double, w : Double, h : Double, inset? : Bool = false) -> Unit {
  ffi_window_setup(min_w, min_h, w, h, if inset { 1 } else { 0 })
}

///|
/// Whether the window's buttons are in the app's top row now (an inset window, not full screen): the room the app
/// leaves them there.
pub fn window_inset() -> Bool {
  ffi_window_inset() != 0
}

///|
/// The press under way moves the window (a press on the app's own top row, @ui's Ctx::window_drag): the host's from
/// here, as its title bar's would be.
pub fn window_drag() -> Unit {
  ffi_window_drag()
}

///|
/// The pointer's shape from now on: 0 the arrow, 1 a hand, 2 the text's I-beam, 3 resizing sideways, 4 up and down,
/// 5 an open hand. Nothing where there is no pointer.
pub fn set_cursor(kind : Int) -> Unit {
  ffi_set_cursor(kind)
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
  ffi_run(title, frame, pointer, wheel, key, text)
}

///|
pub fn now() -> Double {
  ffi_now()
}

///|
extern "C" fn ffi_wall_ms() -> Double = "mb_host_wall_ms"

///|
/// The time of day, in ms since 1970 (UTC), as the machine's clock has it: for what is shown of it only (@ui.wall_ms).
/// A run to a declared moment (a scripted shot) has its own: from a fixed day, on with its frames' clock.
pub fn wall_ms() -> Double {
  ffi_wall_ms()
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
/// A secret put on the system's clipboard: marked sensitive where the system masks such (Android 13 on), and taken
/// off `clear_ms` later unless something else was copied meanwhile (0: kept). Elsewhere as clipboard_set.
pub fn clipboard_set_secret(s : String, clear_ms~ : Double) -> Unit {
  ffi_clipboard_secret(s, clear_ms)
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
/// Who is told as what the host does for the app is done (`f(kind, id, state)`: kind 1 an image or a PDF's page
/// decoded, 2 a native view ready — a page loaded and its picture taken, a video's first frame —; state 1 done, -1
/// failed), on the main thread, between frames. False where the host sends no such events.
pub fn set_outside(f : FuncRef[(Int, Int, Int) -> Unit]) -> Bool {
  ffi_set_outside(f) != 0
}

///|
/// As the frame just built left it: how many of the app's asks the host has not answered yet (effect.mb's outside)
/// and what they are ("" when none). A run to a declared moment keeps its clock still while any is awaited.
pub fn frame_awaiting(awaiting : Int, what : String) -> Unit {
  ffi_frame_awaiting(awaiting, what)
}

///|
/// Whether the run is on a clock of its own (its frames', 1/60 s a frame from 0, still while the app awaits the host:
/// a picture's run, mac_app.m's settle, MBView's shot_at), not the machine's.
pub fn own_clock() -> Bool {
  ffi_own_clock() != 0
}

///|
/// Whether the system asks for less motion (macOS and iOS: Reduce Motion;
/// Android: animations off, its animator duration scale 0). Read at most
/// once a second.
pub fn reduce_motion() -> Bool {
  let t = ffi_now()
  if t - reduce_read.val > 1000.0 || reduce_read.val < 0.0 {
    reduce_read.val = t
    reduce_said.val = ffi_reduce_motion() != 0
  }
  reduce_said.val
}

///|
let reduce_read : Ref[Double] = { val: -1.0 }

///|
let reduce_said : Ref[Bool] = { val: false }

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
/// Whether the system is set to dark (macOS's appearance, Android's night mode, iOS's interface style, the browser's
/// prefers-color-scheme): what an app that follows the system shows. Asked each frame; a host asks for a frame when
/// it changes. Hosts that cannot tell say light.
pub fn system_dark() -> Bool {
  ffi_system_dark() != 0
}

///|
/// The app is drawn dark (or light) from now on: the host's own parts follow it (Android's status and navigation
/// bars' icons, the Mac window's title bar). Said when it changes.
pub fn set_dark(dark : Bool) -> Unit {
  ffi_set_dark(if dark { 1 } else { 0 })
}

///|
/// Turned sideways for a film (still.fail's player, Player.kt): landscape asked for (a phone with rotation locked
/// turns too) and the system's bars out of the way (a swipe brings them for a while); `false`, upright as it was.
/// Android does it (the activity's requested orientation, its window's insets controller); elsewhere nothing turns.
pub fn set_sideways(on : Bool) -> Unit {
  ffi_set_sideways(if on { 1 } else { 0 })
}


///|
/// Words (`text`), or a file of `data` named `name` (`mime`), handed to another app through the system's share sheet
/// (Android's chooser, macOS's sharing picker); false where there is none (or no app takes it).
pub fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  ffi_share(text, name, mime, data) != 0
}

///|
/// What another app shared into this one since last asked (Android's ACTION_SEND of text or files, ACTION_SEND_MULTIPLE
/// of files; MBUI_SHARE_FILES, paths split by |, on macOS for scripted runs), as JSON text `{"text","title","files"}`,
/// `files` each `{"name","type","size"}` (absent when none); "" when nothing was.
pub fn shared_in() -> String {
  ffi_shared_in()
}

///|
/// The i-th of the files shared in (`shared_in`'s `files`), taken once: empty after, or where there is none.
pub fn shared_in_file(i : Int) -> Bytes {
  ffi_shared_in_file(i)
}

///|
/// This build's version code, as the system has it (Android's); 0 where the app does not update itself.
pub fn app_version() -> Int {
  ffi_app_version()
}

///|
/// A newer build at `url` (its `sha256`, `size` bytes) downloaded as `name`, checked and handed to the system's
/// installer (Android: still.fail's Updates.kt); nothing elsewhere. How it goes: `update_state`.
pub fn update_install(url : String, sha256 : String, size : Double, name : String) -> Unit {
  ffi_update_install(url, sha256, size, name)
}

///|
/// How an update goes, as JSON text: `{"phase","percent","error"}` (phase idle, allow: the person's leave to install
/// apps asked for, downloading, retrying, installing, handed, failed); "" where there is none.
pub fn update_state() -> String {
  ffi_update_state()
}

///|
/// A package (an APK a chat has) handed to the system's installer, which asks the person to confirm (Android:
/// still.fail's Install.kt installApk). What comes of it, when it is not installed, comes on @host.system_channel
/// (system.mbt `install`: the leave to install apps asked for, or why it failed: "unsupported" where there is no
/// installer).
pub fn install_package(name : String, data : Bytes) -> Unit {
  ffi_install_package(name, data)
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

// Files kept on the device (keep.mbt): Keeps.java on Android, apple_views.m on macOS and iOS, win_app.c on Windows.

///|
#borrow(name, mime)
extern "C" fn kp_begin(name : String, mime : String, way : Int) -> Int = "mb_host_keep_begin"

///|
#borrow(data)
extern "C" fn kp_append(id : Int, data : Bytes) -> Int = "mb_host_keep_append"

///|
extern "C" fn kp_finish(id : Int) -> Unit = "mb_host_keep_finish"

///|
extern "C" fn kp_state(id : Int) -> Int = "mb_host_keep_state"

///|
extern "C" fn kp_where(id : Int) -> String = "mb_host_keep_where"

///|
extern "C" fn kp_end(id : Int) -> Unit = "mb_host_keep_end"

// The gallery (gallery.mbt): Gallery.java on Android; none elsewhere.

///|
extern "C" fn ga_access() -> Int = "mb_host_gallery_access"

///|
extern "C" fn ga_ask() -> Unit = "mb_host_gallery_ask"

///|
extern "C" fn ga_answers() -> Int = "mb_host_gallery_answers"

///|
extern "C" fn ga_read() -> Int = "mb_host_gallery_read"

///|
extern "C" fn ga_read_state(id : Int) -> Int = "mb_host_gallery_read_state"

///|
extern "C" fn ga_read_rows(id : Int) -> String = "mb_host_gallery_read_rows"

///|
extern "C" fn ga_read_end(id : Int) -> Unit = "mb_host_gallery_read_end"

///|
#borrow(src)
extern "C" fn pk_photo(src : String) -> Int = "mb_host_pick_photo"

// Text in a legacy encoding (charset.mbt).

///|
#borrow(charset)
extern "C" fn cs_known(charset : String) -> Int = "mb_host_charset_known"

///|
#borrow(data, charset)
extern "C" fn cs_decode(data : Bytes, charset : String) -> String = "mb_host_charset_decode"

// Marks drawn onto an image (marks.mbt): Marks.java on Android, apple_views.m on macOS and iOS.

///|
#borrow(image, marks)
extern "C" fn mk_start(image : Bytes, marks : String) -> Int = "mb_host_marks_start"

///|
extern "C" fn mk_state(id : Int) -> Int = "mb_host_marks_state"

///|
extern "C" fn mk_png(id : Int) -> Bytes = "mb_host_marks_png"

// Notifications (notify.mbt): dev.mbui.Notices on Android (android_host.c), kept and said on the log elsewhere.

///|
#borrow(channel, tag, title, body, opens)
extern "C" fn nt_show(
  channel : String,
  tag : String,
  title : String,
  body : String,
  opens : String,
) -> Unit = "mb_host_notice_show"

///|
#borrow(tag)
extern "C" fn nt_cancel(tag : String) -> Unit = "mb_host_notice_cancel"

///|
/// 0: what the system allows (0 unknown, 1 granted, 2 denied, 3 can be asked); 1: ask it (1 asked); 2: its answer,
/// once (-1 none yet, 0 refused, 1 allowed)
extern "C" fn nt_state(what : Int) -> Int = "mb_host_notice_state"

///|
/// 0: a notification tapped (its `opens`), once; 1: the push token; 2: a push delivered, once
extern "C" fn nt_text(what : Int) -> String = "mb_host_notice_text"

// Native views over the canvas (src/ui/native.mbt): a system view (a video player, a web page) the host keeps in the
// window under the app's surface, shown through a hole the app paints in it (instances of kind 9: transparent,
// written without blending), so what the app paints after the hole draws over the view (a bar, a video's controls)
// and what it paints over its edges clips it. Ids are the host's own, from 1; 0 where the host has none of that kind.

///|
#borrow(arg)
extern "C" fn ffi_view_open(kind : Int, arg : String) -> Int = "mb_host_view_open"

///|
extern "C" fn ffi_view_place(
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
  shown : Int,
) -> Unit = "mb_host_view_place"

///|
extern "C" fn ffi_view_close(id : Int) -> Unit = "mb_host_view_close"

///|
extern "C" fn ffi_view_control(id : Int, op : Int, value : Double) -> Unit = "mb_host_view_control"

///|
#borrow(out)
extern "C" fn ffi_view_info(id : Int, out : FixedArray[Double]) -> Int = "mb_host_view_info"

///|
#borrow(out)
extern "C" fn ffi_view_read_next(id : Int, out : FixedArray[Double]) -> Int = "mb_host_view_read_next"

///|
#borrow(data)
extern "C" fn ffi_view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit = "mb_host_view_read_answer"

///|
extern "C" fn ffi_view_site_next(id : Int) -> String = "mb_host_view_site_next"

///|
extern "C" fn ffi_view_site_body(id : Int, req : Int) -> Bytes = "mb_host_view_site_body"

///|
#borrow(headers)
extern "C" fn ffi_view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit = "mb_host_view_site_head"

///|
#borrow(data)
extern "C" fn ffi_view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit = "mb_host_view_site_chunk"

///|
#borrow(error)
extern "C" fn ffi_view_site_end(id : Int, req : Int, error : String) -> Unit = "mb_host_view_site_end"

///|
extern "C" fn ffi_view_site_state(id : Int) -> String = "mb_host_view_site_state"

///|
#borrow(path)
extern "C" fn ffi_view_site_load(id : Int, path : String) -> Unit = "mb_host_view_site_load"

///|
/// What a site (a view of kind 3) has to say, oldest first: a JSON text, "" when nothing waits. `{"req":n,"method",
/// "path","headers":[[k,v]…],"page":true|false}` a request of its own host the app answers (`view_site_head`, then
/// `view_site_chunk`s, then `view_site_end`); `{"gone":n}` a request the page let go of (nothing more of it is taken);
/// `{"leave":url}` a link to elsewhere tapped (not followed); `{"late":n}` a request with no head after `head_wait_ms`
/// (view_tell 3; it waits on); `{"slow":n}` an answer more of which waits than `backlog` (the host takes no more of
/// it, and fails its body once what waits is read: the app ends it). Of a page's or a site's, `{"said":text}`: what
/// its page's scripts said to the app (`mbuiHost.post(text)`), in the order said.
pub fn view_site_next(id : Int) -> String {
  ffi_view_site_next(id)
}

///|
/// A request's body (empty when it has none, or the host's web view does not hand it over: Android's).
pub fn view_site_body(id : Int, req : Int) -> Bytes {
  ffi_view_site_body(id, req)
}

///|
/// A request's answer begins: its status and headers (`[[k,v]…]` as JSON text).
pub fn view_site_head(id : Int, req : Int, status : Int, headers : String) -> Unit {
  ffi_view_site_head(id, req, status, headers)
}

///|
/// The next piece of a request's answer's body.
pub fn view_site_chunk(id : Int, req : Int, data : Bytes) -> Unit {
  ffi_view_site_chunk(id, req, data)
}

///|
/// A request's answer ends ("" whole; else why it broke off). A request with no head yet fails with it.
pub fn view_site_end(id : Int, req : Int, error : String) -> Unit {
  ffi_view_site_end(id, req, error)
}

///|
/// Where the site's page is: `{"path","back","forward","loading","title"}` as JSON text.
pub fn view_site_state(id : Int) -> String {
  ffi_view_site_state(id)
}

///|
/// The site's page at `path` of its own host.
pub fn view_site_load(id : Int, path : String) -> Unit {
  ffi_view_site_load(id, path)
}

///|
#borrow(text)
extern "C" fn ffi_view_tell(id : Int, what : Int, text : String) -> Unit = "mb_host_view_tell"

///|
/// What the app tells a view beyond its controls: `what` 1 a script to run in its page (a page's or a site's): in the
/// page there once it has loaded, or has said something (`{"said":…}`) since it started; one sent while a page loads
/// waits for it, all in the order sent. 2 who takes a finger on it: "all", "through", "pinch" or "vertical", then the
/// slop in points (ui's NativeView::touch). 3 a site's settings, as JSON: `head_wait_ms` (how long a request waits for
/// its head before the host says `{"late":n}`, still waiting), `backlog` (how many bytes of an answer may wait for the
/// page to read them before the host says `{"slow":n}` and takes no more of it).
pub fn view_tell(id : Int, what : Int, text : String) -> Unit {
  ffi_view_tell(id, what, text)
}

///|
/// A native view of `kind`: 1 a video (and audio) player, its bytes read through the app (`view_read_next`), `arg`
/// its MIME type ("video/mp4"); 2 a web page of `arg`'s HTML, its scripts on, nothing of the device's files or the
/// app's reachable, its links not followed; 3 a site served by the app: a web view at `arg` (a path) of a host of its
/// own, each of whose requests the app answers (`view_site_next`). Hidden until placed. 0 when this host has no such
/// view.
pub fn view_open(kind : Int, arg : String) -> Int {
  ffi_view_open(kind, arg)
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
  ffi_view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, radius, if shown { 1 } else { 0 })
}

///|
/// The view gone (its player stopped, its page closed).
pub fn view_close(id : Int) -> Unit {
  ffi_view_close(id)
}

///|
/// A player told: `op` 1 play, 2 pause, 3 to `value` ms (the frame there, exactly), 4 at `value` times its speed; a
/// site: 5 back, 6 forward, 7 reload, 8 laid out at its rect over `value` and drawn at `value` times (a viewport's
/// own size shown smaller).
pub fn view_control(id : Int, op : Int, value : Double) -> Unit {
  ffi_view_control(id, op, value)
}

///|
/// How the view stands: -1 failed (a file the player cannot play, a page that cannot load), 0 opening, 1 ready.
/// `out` (10): its length in ms (-1 not known), where it is (ms), playing (1), the picture's own width and height
/// (pixels), the bytes it has been given, whether a frame has been drawn (a page: loaded), buffering (1), how far on it
/// has what it needs to play (ms; 0 not said), played to its end (1).
pub fn view_info(id : Int, out : FixedArray[Double]) -> Int {
  ffi_view_info(id, out)
}

///|
/// A read the player waits on: its id (0: none waiting), `out` [0] its offset, [1] how many bytes it wants. Each is
/// answered once (`view_read_answer`); the host asks for a frame when one comes.
pub fn view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  ffi_view_read_next(id, out)
}

///|
/// Read `req`'s answer: the bytes from its offset (at most as many as it wanted; fewer is fine, none only at the
/// file's end), `total` the file's whole size (-1 not known: Apple's player needs it, so give it); -2: it could not be
/// read (the player fails).
pub fn view_read_answer(id : Int, req : Int, data : Bytes, total : Double) -> Unit {
  ffi_view_read_answer(id, req, data, total)
}

// PDFs drawn by the system (Android's PdfRenderer, Core Graphics' CGPDF), page by page into images.

///|
#borrow(data)
extern "C" fn ffi_pdf_open(data : Bytes) -> Int = "mb_host_pdf_open"

///|
extern "C" fn ffi_pdf_pages(doc : Int) -> Int = "mb_host_pdf_pages"

///|
#borrow(out)
extern "C" fn ffi_pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit = "mb_host_pdf_page_size"

///|
extern "C" fn ffi_pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int = "mb_host_pdf_page_load"

///|
extern "C" fn ffi_pdf_close(doc : Int) -> Unit = "mb_host_pdf_close"

///|
/// A PDF opened from its bytes: its id, or 0 where the host draws none.
pub fn pdf_open(data : Bytes) -> Int {
  ffi_pdf_open(data)
}

///|
/// How many pages it has; -1 when it could not be opened.
pub fn pdf_pages(doc : Int) -> Int {
  ffi_pdf_pages(doc)
}

///|
/// A page's size in points (`out` [0] width, [1] height).
pub fn pdf_page_size(doc : Int, page : Int, out : FixedArray[Double]) -> Unit {
  ffi_pdf_page_size(doc, page, out)
}

///|
/// A page drawn (on white, off the app's thread) at most `max_px` on its longer side: an image's id, as image_load's
/// (image_info, image_free).
pub fn pdf_page_load(doc : Int, page : Int, max_px : Int) -> Int {
  ffi_pdf_page_load(doc, page, max_px)
}

///|
pub fn pdf_close(doc : Int) -> Unit {
  ffi_pdf_close(doc)
}

///|
extern "C" fn ffi_view_text(id : Int, what : Int) -> String = "mb_host_view_text"

///|
extern "C" fn ffi_view_text_known(id : Int, what : Int) -> Int = "mb_host_view_text_known"

///|
extern "C" fn ffi_view_still(id : Int) -> Bytes = "mb_host_view_still"

///|
/// What a video view says beyond its info: `what` 1 its frames' times (ms, comma between: view_control 20 asks them
/// read), 2 how a frame grabbed stands (view_control 21 at a time in ms: "1" grabbing, "2" here, "-1" failed, "0"
/// none); None while not known.
pub fn view_text(id : Int, what : Int) -> String? {
  if ffi_view_text_known(id, what) == 0 {
    None
  } else {
    Some(ffi_view_text(id, what))
  }
}

///|
/// A video view's frame grabbed (PNG), taken once.
pub fn view_still(id : Int) -> Bytes {
  ffi_view_still(id)
}

///|
#borrow(name, data)
extern "C" fn ffi_save_file(name : String, data : Bytes) -> Int = "mb_host_save_file"

///|
/// A file put where the system keeps downloads (Android: Downloads, through MediaStore; macOS: ~/Downloads): true
/// once it is there.
pub fn save_file(name : String, data : Bytes) -> Bool {
  ffi_save_file(name, data) != 0
}

///|
/// The word of `text` around `off` (UTF-16 offsets, its start and end) as the system finds words (Android's
/// BreakIterator, Apple's CFStringTokenizer: a dictionary's words in Chinese and Japanese); (-1, -1) where the host has
/// no such thing (Windows here) or `off` is in no word.
pub fn word_at(text : String, off : Int) -> (Int, Int) {
  word_pair(ffi_word_at(text, off))
}

///|
/// A word's start and end as a host gives them: start × 2³² + end, or negative for none.
fn word_pair(v : Double) -> (Int, Int) {
  if v < 0.0 {
    return (-1, -1)
  }
  let k = 4294967296.0
  let s = (v / k).floor()
  ((s).to_int(), (v - s * k).to_int())
}

///|
/// `url` handed to the system: the browser, or the app it belongs to (Android's ACTION_VIEW, macOS's NSWorkspace,
/// iOS's UIApplication, Windows' ShellExecute). False when nothing took it.
pub fn open_url(url : String) -> Bool {
  ffi_open_url(url) != 0
}

///|
/// The app over another app (system.mbt `over`: Android's OverActivity, a share sheet over the app it came from) done:
/// it goes, back to the app it was over; `open_app`, on into the app's own window. Nothing where it never is over one.
pub fn over_done(open_app~ : Bool) -> Unit {
  ffi_over_done(if open_app { 1 } else { 0 })
}

///|
/// A page shown in a browser's tab over the app, the app under it (Android's Custom Tab, the system's browser where
/// none takes one); elsewhere as open_url. False when nothing took it.
pub fn open_tab(url : String) -> Bool {
  ffi_open_tab(url) != 0
}

///|
/// What the notice says that holds the app up while it listens for a browser coming back (@host.browser_login, the
/// core's loopback listeners: Android's foreground service, in `channel`, named as the system's settings list it);
/// said before the browser opens, kept for the next. Other hosts keep no notice.
pub fn hold_words(channel~ : String, title~ : String, body~ : String) -> Unit {
  ffi_hold_words(channel, title, body)
}

///|
extern "C" fn ffi_post_take() -> Int = "mb_host_post_take"

///|
extern "C" fn ffi_post_next() -> String = "mb_host_post_next"

///|
extern "C" fn ffi_post_json() -> String = "mb_host_post_json"

///|
extern "C" fn ffi_post_bytes() -> Bytes = "mb_host_post_bytes"

///|
/// What was posted from outside the frames since the last take (`mb_post`, any thread: post.h), taken now as a frame
/// begins: how many. They are handed on one at a time (`post_next`), in the order posted.
pub fn post_take() -> Int {
  ffi_post_take()
}

///|
/// The next message taken (`post_take`): its channel, its JSON and the bytes beside it (empty: none). None when all
/// taken are handed on, or dropped since (`mb_post_drop`: a core stopped).
pub fn post_next() -> (String, String, Bytes)? {
  let channel = ffi_post_next()
  if channel == "" {
    None
  } else {
    Some((channel, ffi_post_json(), ffi_post_bytes()))
  }
}
