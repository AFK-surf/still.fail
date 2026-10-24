// The Tester's fake host as mbui/hostapi's `Host` (Tester::new sets it): what the app asks of its host directly
// (@hostapi.log, @hostapi.decode_charset…) answered as what the framework asks through its own calls is (hostcall.mbt,
// hostread.mbt, ctx.mbt…: their fake's side, which they take while a Tester runs). What none of those answers, as a
// host with nothing for it answers (hostapi's defaults). A test's program has no other host: it links no host's code.

///|
impl @hostapi.Host for FakeHost with install_package(_, a0, a1) {
  install_package(a0, a1)
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
impl @hostapi.Host for FakeHost with update_install(_, a0, a1, a2, a3) {
  update_install(a0, a1, a2, a3)
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
impl @hostapi.Host for FakeHost with image_free(_, a0) {
  h_image_free(a0)
}

///|
impl @hostapi.Host for FakeHost with view_open(_, a0, a1) {
  h_view_open(a0, a1)
}

///|
impl @hostapi.Host for FakeHost with view_place(_, a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) {
  h_view_place(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
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
impl @hostapi.Host for FakeHost with dock_available(_) {
  dock_available()
}

///|
impl @hostapi.Host for FakeHost with mods_held(_) {
  mods_held()
}

///|
impl @hostapi.Host for FakeHost with dock_send(_, a0) {
  dock_send(a0)
}

///|
impl @hostapi.Host for FakeHost with dock_stop(_) {
  dock_stop()
}

///|
impl @hostapi.Host for FakeHost with dock_kept(_) {
  dock_kept()
}

///|
impl @hostapi.Host for FakeHost with dock_keep(_, a0) {
  dock_keep(a0)
}

///|
impl @hostapi.Host for FakeHost with window_drag(_) {
  h_window_drag()
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
