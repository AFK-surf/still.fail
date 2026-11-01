// The Tester's fake host as mbui/hostapi's `Host` (Tester::new sets it): what the app asks of its host directly
// (@hostapi.log, @hostapi.decode_charset…) answered as what the framework asks through its own calls is (hostcall.mbt,
// hostread.mbt, ctx.mbt…: their fake's side, which they take while a Tester runs). What none of those answers, as a
// host with nothing for it answers (hostapi's defaults). A test's program has no other host: it links no host's code.

///|
impl @hostapi.Host for FakeHost with install_package(_, a0, a1) {
  install_package(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with window_show(self) {
  self.window_shows = self.window_shows + 1
}

///|
impl @hostapi.Host for FakeHost with reduce_motion(_) {
  reduced_motion()
}

///|
impl @hostapi.Host for FakeHost with drive(_, a0, a1) {
  h_drive(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with update_fetch(_, a0, a1, a2, a3, a4) {
  update_fetch(a0, a1, a2, a3, a4)
}

///|
impl @hostapi.Host for FakeHost with update_apply(_, a0) {
  update_apply(a0)
}

///|
impl @hostapi.Host for FakeHost with update_state(_) {
  update_state()
}

///|
impl @hostapi.Host for FakeHost with now(_) {
  h_now()
}

///|
impl @hostapi.Host for FakeHost with wall_ms(_) {
  h_wall_ms()
}

///|
impl @hostapi.Host for FakeHost with event_time(_) {
  h_event_time()
}

///|
impl @hostapi.Host for FakeHost with event_finger(_) {
  h_event_finger()
}

///|
impl @hostapi.Host for FakeHost with frame_late(_) {
  h_frame_late()
}

///|
impl @hostapi.Host for FakeHost with platform(_) {
  h_platform()
}

///|
impl @hostapi.Host for FakeHost with request_frame(_) {
  h_request_frame()
}

///|
impl @hostapi.Host for FakeHost with wake_after(_, a0) {
  h_wake_after(a0)
}

///|
impl @hostapi.Host for FakeHost with font_metrics(_, a0, a1, a2, a3) {
  h_font_metrics(a0, a1, a2, a3)
}

///|
impl @hostapi.Host for FakeHost with shape(_, a0, a1, a2, a3, a4) {
  h_shape(a0, a1, a2, a3, a4)
}

///|
impl @hostapi.Host for FakeHost with text_key(_, a0, a1, a2, a3) {
  h_text_key(a0, a1, a2, a3)
}

///|
impl @hostapi.Host for FakeHost with glyph(_, a0, a1) {
  h_glyph(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with glyph_put(_, a0, a1, a2) {
  h_glyph_put(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with atlas_size(_, a0) {
  h_atlas_size(a0)
}

///|
impl @hostapi.Host for FakeHost with face_add(_, a0, a1, a2) {
  h_face_add(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with face_add_bytes(_, a0, a1, a2) {
  h_face_add_bytes(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with face_clear(_, a0) {
  h_face_clear(a0)
}

///|
impl @hostapi.Host for FakeHost with face_add_family(_, a0, a1) {
  h_face_add_family(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with local_font_families(_) {
  local_font_families()
}

///|
impl @hostapi.Host for FakeHost with atlas_generation(_) {
  h_atlas_generation()
}

///|
impl @hostapi.Host for FakeHost with reduce_transparency(_) {
  h_reduce_transparency()
}

///|
impl @hostapi.Host for FakeHost with gpu_ms(_) {
  h_gpu_ms()
}

///|
impl @hostapi.Host for FakeHost with cpu_ms(_) {
  h_cpu_ms()
}

///|
impl @hostapi.Host for FakeHost with perf_state(_) {
  match fake.val {
    Some(f) => f.perf
    None => -1
  }
}

///|
impl @hostapi.Host for FakeHost with set_perf(_, on) {
  match fake.val {
    Some(f) =>
      if f.perf >= 0 {
        f.perf_sets.push(on)
        f.perf = if on { 1 } else { 0 }
      }
    None => ()
  }
}

///|
impl @hostapi.Host for FakeHost with perf_line(_, line) {
  match fake.val {
    Some(f) => if f.perf == 1 { f.perf_lines.push(line) }
    None => ()
  }
}

///|
impl @hostapi.Host for FakeHost with perf_where(_) {
  match fake.val {
    Some(f) if f.perf >= 0 => "Documents/perf"
    _ => ""
  }
}

///|
impl @hostapi.Host for FakeHost with perf_size(_) {
  // (what the lines weigh is the real host's, whose times are not a test's: as the test says, Tester::set_perf_size)
  match fake.val {
    Some(f) => f.perf_bytes
    None => 0.0
  }
}

///|
impl @hostapi.Host for FakeHost with set_ime(_, a0, a1, a2, a3, a4, a5, a6, a7) {
  h_set_ime(a0, a1, a2, a3, a4, a5, a6, a7)
}

///|
impl @hostapi.Host for FakeHost with clipboard_set(_, a0) {
  h_clipboard_set(a0)
}

///|
impl @hostapi.Host for FakeHost with word_at(_, a0, a1) {
  h_word_at(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with open_url(_, a0) {
  h_open_url(a0)
}

///|
impl @hostapi.Host for FakeHost with open_tab(_, a0) {
  h_open_tab(a0)
}

///|
impl @hostapi.Host for FakeHost with back_enabled(_, a0) {
  h_back_enabled(a0)
}

///|
impl @hostapi.Host for FakeHost with log(_, a0) {
  h_log(a0)
}

///|
impl @hostapi.Host for FakeHost with image_load(_, a0, a1) {
  h_image_load(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with image_info(_, a0, a1) {
  h_image_info(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with image_pixels(_, a0, a1) {
  h_image_pixels(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with drawn_pixels(_, a0, a1, a2, a3, a4) {
  h_drawn_pixels(a0, a1, a2, a3, a4)
}

///|
impl @hostapi.Host for FakeHost with drawn_pixels_of(_, inst, count, _, _, _, scale, w, h, out) {
  h_drawn_pixels_of(inst, count, scale, w, h, out)
}

///|
impl @hostapi.Host for FakeHost with image_free(_, a0) {
  h_image_free(a0)
}

///|
impl @hostapi.Host for FakeHost with view_open(_, a0, a1) {
  h_view_open(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_place(_, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13) {
  h_view_place(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13)
}

///|
impl @hostapi.Host for FakeHost with view_close(_, a0) {
  h_view_close(a0)
}

///|
impl @hostapi.Host for FakeHost with view_control(_, a0, a1, a2) {
  h_view_control(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with view_info(_, a0, a1) {
  h_view_info_of(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_site_next(_, a0) {
  h_view_site_next(a0)
}

///|
impl @hostapi.Host for FakeHost with view_tell(_, a0, a1, a2) {
  h_view_tell(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with view_site_body(_, a0, a1) {
  h_view_site_body(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_site_head(_, a0, a1, a2, a3) {
  h_view_site_head(a0, a1, a2, a3)
}

///|
impl @hostapi.Host for FakeHost with view_site_chunk(_, a0, a1, a2) {
  h_view_site_chunk(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with view_site_end(_, a0, a1, a2) {
  h_view_site_end(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with view_site_state(_, a0) {
  h_view_site_state(a0)
}

///|
impl @hostapi.Host for FakeHost with view_text(_, a0, a1) {
  h_view_text(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_still(_, a0) {
  h_view_still(a0)
}

///|
impl @hostapi.Host for FakeHost with view_site_load(_, a0, a1) {
  h_view_site_load(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_read_next(_, a0, a1) {
  h_view_read_next(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_read_answer(_, a0, a1, a2, a3, a4) {
  h_view_read_answer(a0, a1, a2, a3, a4)
}

///|
impl @hostapi.Host for FakeHost with pdf_open(_, a0) {
  h_pdf_open(a0)
}

///|
impl @hostapi.Host for FakeHost with pdf_pages(_, a0) {
  h_pdf_pages(a0)
}

///|
impl @hostapi.Host for FakeHost with pdf_page_size(_, a0, a1, a2) {
  h_pdf_page_size(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with pdf_page_load(_, a0, a1, a2) {
  h_pdf_page_load(a0, a1, a2)
}

///|
impl @hostapi.Host for FakeHost with pdf_close(_, a0) {
  h_pdf_close(a0)
}

///|
impl @hostapi.Host for FakeHost with set_cursor(_, a0) {
  h_set_cursor(a0)
}

///|
impl @hostapi.Host for FakeHost with set_badge(_, a0) {
  set_badge(a0)
}

///|
impl @hostapi.Host for FakeHost with local_station(_) {
  local_station()
}

///|
impl @hostapi.Host for FakeHost with local_station_act(_, a0) {
  local_station_act(a0)
}

///|
impl @hostapi.Host for FakeHost with mods_held(_) {
  mods_held()
}

///|
impl @hostapi.Host for FakeHost with window_drag(_) {
  h_window_drag()
}

///|
impl @hostapi.Host for FakeHost with window_act(_, what) {
  h_window_act(what)
}

///|
impl @hostapi.Host for FakeHost with window_zoomed(_) {
  window_zoomed()
}

///|
impl @hostapi.Host for FakeHost with window_snap(_, x, y, w, h) {
  h_window_snap(x, y, w, h)
}

///|
impl @hostapi.Host for FakeHost with window_snap_state(_) {
  window_snap_state()
}

///|
impl @hostapi.Host for FakeHost with window_opens(_) {
  window_opens()
}

///|
impl @hostapi.Host for FakeHost with window_open(_, what) {
  h_window_open(what)
}

///|
impl @hostapi.Host for FakeHost with shared_in(_) {
  shared_in()
}

///|
impl @hostapi.Host for FakeHost with shared_in_file(_, a0) {
  shared_in_file(a0)
}

///|
impl @hostapi.Host for FakeHost with share(_, a0, a1, a2, a3) {
  share(a0, a1, a2, a3)
}

///|
impl @hostapi.Host for FakeHost with own_clock(_) {
  own_clock()
}

///|
impl @hostapi.Host for FakeHost with system_dark(_) {
  system_dark()
}

///|
impl @hostapi.Host for FakeHost with window_inset(_) {
  window_inset()
}

///|
impl @hostapi.Host for FakeHost with full_screen(_) {
  full_screen()
}

///|
impl @hostapi.Host for FakeHost with set_full_screen(_, on) {
  h_set_full_screen(on)
}

///|
impl @hostapi.Host for FakeHost with window_corner(_) {
  window_corner()
}

///|
impl @hostapi.Host for FakeHost with window_corner_at(_, k) {
  window_corner_at(k)
}

///|
impl @hostapi.Host for FakeHost with nv_able(_) {
  nav_able()
}

///|
impl @hostapi.Host for FakeHost with nv_bar(_, spec) {
  nav_bar_said(spec)
}

///|
impl @hostapi.Host for FakeHost with env(_, a0) {
  h_env(a0)
}

///|
impl @hostapi.Host for FakeHost with app_version(_) {
  app_version()
}
///|
impl @hostapi.Host for FakeHost with clipboard_set_secret(_, s, clear_ms) {
  h_clipboard_secret(s, clear_ms)
}

///|
impl @hostapi.Host for FakeHost with clipboard_secret_off(_) {
  h_clipboard_secret_off()
}

///|
impl @hostapi.Host for FakeHost with clipboard_set_image(_, data) {
  h_clipboard_image(data)
}

///|
impl @hostapi.Host for FakeHost with present(_, buf, count, _, _, _) {
  h_present(buf, count)
}

///|
impl @hostapi.Host for FakeHost with over_done(_, open_app) {
  over_done(open_app~)
}

///|
impl @hostapi.Host for FakeHost with hold_words(_, channel, title, body) {
  hold_words(channel~, title~, body~)
}

///|
/// The legacy encodings it decodes (@hostapi.decode_charset): GB18030 and the two it holds (fake_gb18030.mbt); the
/// system's others are a host's own (its contract's).
fn fake_charset(charset : String) -> Bool {
  let c = charset.to_upper()
  c == "GB18030" || c == "GBK" || c == "GB2312"
}

///|
impl @hostapi.Host for FakeHost with cs_known(_, charset) {
  if fake_charset(charset) {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with cs_decode(_, data, charset) {
  if fake_charset(charset) {
    gb18030_decode(data)
  } else {
    ""
  }
}

///|
/// (a Tester's gallery, Tester::gallery: all of it; none given, as a host the app may read none of: 0)
impl @hostapi.Host for FakeHost with ga_access(self) {
  if self.gallery is Some(_) {
    1
  } else {
    0
  }
}

///|
impl @hostapi.Host for FakeHost with ga_read(self) {
  self.gallery_read()
}

///|
impl @hostapi.Host for FakeHost with ga_read_state(self, a0) {
  self.gallery_read_state(a0)
}

///|
impl @hostapi.Host for FakeHost with ga_read_rows(self, a0) {
  self.gallery_read_rows(a0)
}

///|
impl @hostapi.Host for FakeHost with ga_read_end(self, a0) {
  self.gallery_read_end(a0)
}

// This device's password manager (@hostapi passwords.mbt) as a test has it: none, unless it says how `op` answers
// (`fake_op`: its exit code, output and error output for the arguments given), each run ended at once.

///|
/// How `op` answers a test, given its arguments: None, no password manager here.
pub let fake_op : Ref[((Array[String]) -> (Int, String, String))?] = Ref(None)

///|
/// The runs of `op` asked for in a test, by their id (from 1): their arguments.
pub let fake_op_runs : Array[Array[String]] = []

///|
impl @hostapi.Host for FakeHost with pw_able(_) {
  fake_op.val is Some(_)
}

///|
impl @hostapi.Host for FakeHost with pw_run(_, args) {
  guard fake_op.val is Some(_) else { return 0 }
  let given = args.split("\u{1f}").map(fn(a) { a.to_owned() }).to_array()
  // (each argument ended by the separator: the last piece is none)
  ignore(given.pop())
  fake_op_runs.push(given)
  fake_op_runs.length()
}

///|
impl @hostapi.Host for FakeHost with pw_out(_, id) {
  guard fake_op.val is Some(answer) && id >= 1 && id <= fake_op_runs.length() else { return "" }
  let (code, out, err) = answer(fake_op_runs[id - 1])
  "\{code}\u{1f}\{out}\u{1f}\{err}\u{1f}"
}

///|
impl @hostapi.Host for FakeHost with pw_end(_, _) {
  ()
}

// The system's autofill (@hostapi autofill.mbt) as a test has it: none, unless it says there is a service
// (`fake_autofill`); the sites asked for kept, the login the person picked there given by `fake_autofill_picks`.

///|
/// Whether a test's host has an autofill service.
pub let fake_autofill : Ref[Bool] = Ref(false)

///|
/// The sites the autofill service was asked for in a test, in order; "" where the ask was let go of.
pub let fake_autofill_asks : Array[String] = []

///|
let fake_autofill_picked : Ref[String] = Ref("")

///|
/// The person picks a login in the autofill service's offer: its site's host, account and password, taken once.
pub fn fake_autofill_picks(host : String, username : String, password : String) -> Unit {
  fake_autofill_picked.val = "\{host}\u{1f}\{username}\u{1f}\{password}\u{1f}"
}

///|
impl @hostapi.Host for FakeHost with af_able(_) {
  fake_autofill.val
}

///|
impl @hostapi.Host for FakeHost with af_ask(_, host) {
  guard fake_autofill.val else { return 0 }
  fake_autofill_asks.push(host)
  1
}

///|
impl @hostapi.Host for FakeHost with af_take(_) {
  let p = fake_autofill_picked.val
  fake_autofill_picked.val = ""
  p
}

///|
impl @hostapi.Host for FakeHost with af_end(_) {
  fake_autofill_picked.val = ""
  fake_autofill_asks.push("")
}

// This device's passkeys (@hostapi passkeys.mbt) as a test has them: none, unless it says how the device answers
// (`fake_passkey`: given the relying party, the client data, the verification and the ids asked, the host's answer as
// it gives it), each ask ended at once.

///|
/// How the device answers a test's ask for a passkey: None, no passkeys here.
pub let fake_passkey : Ref[((String, String, String, String) -> String)?] = Ref(None)

///|
/// The asks for a passkey in a test, by their id (from 1): the relying party, the client data, the verification, the
/// ids asked (hex, joined by commas).
pub let fake_passkey_asks : Array[(String, String, String, String)] = []

///|
impl @hostapi.Host for FakeHost with wa_able(_) {
  fake_passkey.val is Some(_)
}

///|
impl @hostapi.Host for FakeHost with wa_get(_, ask) {
  guard fake_passkey.val is Some(_) else { return 0 }
  let p = ask.split("\u{1f}").map(fn(a) { a.to_owned() }).to_array()
  fake_passkey_asks.push((p.get(0).unwrap_or(""), p.get(1).unwrap_or(""), p.get(2).unwrap_or(""), p.get(3).unwrap_or("")))
  fake_passkey_asks.length()
}

///|
impl @hostapi.Host for FakeHost with wa_out(_, id) {
  guard fake_passkey.val is Some(answer) && id >= 1 && id <= fake_passkey_asks.length() else { return "" }
  let (rp, client, uv, ids) = fake_passkey_asks[id - 1]
  answer(rp, client, uv, ids)
}

///|
impl @hostapi.Host for FakeHost with wa_end(_, _) {
  ()
}
