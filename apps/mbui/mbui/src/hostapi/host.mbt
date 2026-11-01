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
  set_window_zoom(Self, Double) -> Unit = _
  set_window_key(Self, FuncRef[(Int, Int) -> Int]) -> Unit = _
  window_setup(Self, Double, Double, Double, Double, Bool) -> Unit = _
  window_inset(Self) -> Bool = _
  window_hold(Self) -> Unit = _
  window_show(Self) -> Unit = _
  full_screen(Self) -> Bool = _
  set_full_screen(Self, Bool) -> Unit = _
  window_corner(Self) -> Double = _
  window_corner_at(Self, Int) -> Double = _
  window_drag(Self) -> Unit = _
  window_act(Self, Int) -> Unit = _
  window_zoomed(Self) -> Bool = _
  window_snap(Self, Double, Double, Double, Double) -> Unit = _
  window_snap_state(Self) -> Int = _
  window_opens(Self) -> Bool = _
  window_open(Self, String) -> Bool = _
  set_cursor(Self, Int) -> Unit = _
  set_badge(Self, Int) -> Unit = _
  menu_setup(Self, String) -> Unit = _
  local_station(Self) -> String = _
  local_station_act(Self, String) -> Unit = _
  mods_held(Self) -> Int = _
  run(Self, String, FuncRef[(Double, Double, Double, Double) -> Unit], FuncRef[(Int, Double, Double, Int) -> Unit], FuncRef[(Double, Double, Double, Double, Int) -> Unit], FuncRef[(Int, Int) -> Unit], FuncRef[(Int, String, Int, Int) -> Unit]) -> Unit = _
  now(Self) -> Double = _
  wall_ms(Self) -> Double = _
  utc_offset_min(Self, Double) -> Int = _
  event_time(Self) -> Double = _
  event_finger(Self) -> Int = _
  frame_late(Self) -> Double = _
  platform(Self) -> Int = _
  request_frame(Self) -> Unit = _
  wake_after(Self, Double) -> Unit = _
  font_metrics(Self, Double, Int, Int, FixedArray[Double]) -> Unit = _
  shape(Self, String, Double, Int, Int, FixedArray[Double]) -> Int = _
  text_key(Self, String, Double, Int, Int) -> Int = _
  glyph(Self, Int, FixedArray[Double]) -> Unit = _
  glyph_put(Self, Int, Int, Int) -> Unit = _
  atlas_size(Self, Bool) -> Int = _
  glyphs_ahead(Self, FixedArray[Int], Int) -> Unit = _
  face_add(Self, Int, String, Int) -> Bool = _
  face_add_bytes(Self, Int, Bytes, Int) -> Bool = _
  face_clear(Self, Int) -> Unit = _
  face_add_family(Self, Int, String) -> Bool = _
  local_font_families(Self) -> String = _
  atlas_generation(Self) -> Int = _
  present(Self, FixedArray[Double], Int, Double, Double, Double) -> Unit = _
  set_ime(Self, Bool, Double, Double, Double, Double, String, Int, Int) -> Unit = _
  text_menu(Self, Bool, Double, Double, Double, Double, Int) -> Unit = _
  edit_can(Self, Int) -> Unit = _
  clipboard_set(Self, String) -> Unit = _
  clipboard_set_secret(Self, String, Double) -> Unit = _
  clipboard_secret_off(Self) -> Unit = _
  clipboard_set_image(Self, Bytes) -> Unit = _
  log(Self, String) -> Unit = _
  bench_mode(Self) -> Int = _
  set_outside(Self, FuncRef[(Int, Int, Int) -> Unit]) -> Bool = _
  frame_awaiting(Self, Int, String) -> Unit = _
  own_clock(Self) -> Bool = _
  reduce_motion(Self) -> Bool = _
  keys_platform(Self) -> Int = _
  exit(Self, Int) -> Unit = _
  mem_bytes(Self) -> Double = _
  set_back(Self, FuncRef[(Int, Double, Double, Int) -> Unit]) -> Unit = _
  back_enabled(Self, Bool) -> Unit = _
  reduce_transparency(Self) -> Bool = _
  gpu_ms(Self) -> Double = _
  cpu_ms(Self) -> Double = _
  env(Self, String) -> String = _
  set_app_state(Self, FuncRef[(Int) -> Unit]) -> Unit = _
  system_dark(Self) -> Bool = _
  font_scale(Self) -> Double = _
  native_pointing(Self) -> Int = _
  keyboard(Self) -> Int = _
  a11y_on(Self) -> Bool = _
  a11y_tree(Self, String) -> Unit = _
  set_dark(Self, Bool) -> Unit = _
  set_sideways(Self, Bool) -> Unit = _
  set_turnable(Self, Bool) -> Bool = _
  share(Self, String, String, String, Bytes) -> Bool = _
  perf_state(Self) -> Int = _
  set_perf(Self, Bool) -> Unit = _
  perf_line(Self, String) -> Unit = _
  perf_where(Self) -> String = _
  perf_size(Self) -> Double = _
  perf_read(Self) -> Bytes = _
  shared_in(Self) -> String = _
  shared_in_file(Self, Int) -> Bytes = _
  app_version(Self) -> Int = _
  update_fetch(Self, String, String, Double, String, Bool) -> Unit = _
  update_apply(Self, String) -> Unit = _
  update_state(Self) -> String = _
  install_package(Self, String, Bytes) -> Unit = _
  drive(Self, Int, String) -> Bool = _
  image_load(Self, String, Int) -> Int = _
  image_load_bytes(Self, Bytes, Int) -> Int = _
  image_info(Self, Int, FixedArray[Double]) -> Int = _
  image_free(Self, Int) -> Unit = _
  image_pixels(Self, Int, FixedArray[Byte]) -> Bool = _
  drawn_pixels(Self, Int, Int, Int, Int, FixedArray[Byte]) -> Bool = _
  drawn_pixels_of(Self, FixedArray[Double], Int, Double, Double, Double, Double, Int, Int, FixedArray[Byte]) -> Bool = _
  view_site_next(Self, Int) -> String = _
  view_site_body(Self, Int, Int) -> Bytes = _
  view_site_head(Self, Int, Int, Int, String) -> Unit = _
  view_site_chunk(Self, Int, Int, Bytes) -> Unit = _
  view_site_end(Self, Int, Int, String) -> Unit = _
  view_site_state(Self, Int) -> String = _
  view_site_load(Self, Int, String) -> Unit = _
  view_tell(Self, Int, Int, String) -> Unit = _
  view_open(Self, Int, String) -> Int = _
  view_place(Self, Int, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Bool) -> Unit = _
  view_close(Self, Int) -> Unit = _
  view_control(Self, Int, Int, Double) -> Unit = _
  view_info(Self, Int, FixedArray[Double]) -> Int = _
  view_read_next(Self, Int, FixedArray[Double]) -> Int = _
  view_read_answer(Self, Int, Int, Bytes, Double, Bool) -> Unit = _
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
  bl_start(Self, String, String) -> Int = _
  bl_port(Self, Int) -> Int = _
  bl_open(Self, Int, String) -> Int = _
  bl_back(Self, Int) -> String = _
  bl_end(Self, Int) -> Unit = _
  pw_able(Self) -> Bool = _
  pw_run(Self, String) -> Int = _
  pw_out(Self, Int) -> String = _
  pw_end(Self, Int) -> Unit = _
  af_able(Self) -> Bool = _
  af_ask(Self, String) -> Int = _
  af_take(Self) -> String = _
  af_end(Self) -> Unit = _
  wa_able(Self) -> Bool = _
  wa_get(Self, String) -> Int = _
  wa_out(Self, Int) -> String = _
  wa_end(Self, Int) -> Unit = _
  pk_start(Self, Int) -> Int = _
  pk_state(Self, Int) -> Int = _
  pk_count(Self, Int) -> Int = _
  pk_name(Self, Int, Int) -> String = _
  pk_bytes(Self, Int, Int) -> Bytes = _
  pk_info(Self, Int, Int) -> String = _
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
  rn_dirty(Self, Double, Double, Double, Double) -> Unit = _
  nv_bar(Self, String) -> Int = _
  nv_able(Self) -> Bool = _
  nt_cancel(Self, String) -> Unit = _
  nt_state(Self, Int) -> Int = _
  nt_text(Self, Int) -> String = _
  st_audio_here(Self) -> Int = _
  st_audio(Self, Int, Bytes) -> Unit = _
  st_layers(Self) -> Int = _
  st_pointer(Self, Int, Bytes, Double, Double, Double, Double) -> Unit = _
  st_pointer_at(Self, Int, Double, Double, Int) -> Unit = _
  st_direct(Self, Int, Double, Double, Int) -> Unit = _
  st_h265_here(Self) -> Int = _
  st_hevc(Self, Int, Bytes, Int, Int) -> Unit = _
  st_open(Self) -> Int = _
  st_h264(Self, Int, Bytes, Int, Int) -> Unit = _
  st_frame(Self, Int, Bytes, Int, Double) -> Unit = _
  st_jpeg(Self, Int, Bytes, Double) -> Unit = _
  st_next(Self, Int) -> String = _
  st_show(Self, Int, Double) -> Unit = _
  st_close(Self, Int) -> Unit = _
  st_h264_here(Self) -> Int = _
  st_feeds(Self) -> Int = _
  st_codec(Self, Int, String, Bytes) -> Unit = _
  cl_read(Self) -> Int = _
  cl_state(Self, Int) -> Int = _
  cl_picture(Self, Int) -> Int = _
  cl_text(Self, Int) -> String = _
  cl_png(Self, Int) -> Bytes = _
  cl_files(Self, Int) -> Int = _
  cl_file_name(Self, Int, Int) -> String = _
  cl_file(Self, Int, Int) -> Bytes = _
  cl_end(Self, Int) -> Unit = _
  cl_set(Self, String, Bytes, String) -> Unit = _
  dv_copy_shown(Self) -> Int = _
  dv_key_catch(Self, Int) -> Unit = _
  dv_ime_inset(Self) -> Double = _
  dv_keep_awake(Self, Int) -> Unit = _
  dv_haptic(Self, Int) -> Unit = _
  dv_ime_action(Self, Int) -> Unit = _
  ncall_call(Self, String, String) -> Int = _
  ncall_state(Self, Int) -> Int = _
  ncall_result(Self, Int) -> String = _
  ncall_end(Self, Int) -> Unit = _
}

///|
impl Host with set_window_zoom(_, _) {
  ()
}

///|
impl Host with set_window_key(_, _) {
  ()
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
impl Host with window_hold(_) {
  ()
}

///|
impl Host with window_show(_) {
  ()
}

///|
impl Host with full_screen(_) {
  false
}

///|
impl Host with set_full_screen(_, _) {
  ()
}

///|
impl Host with window_corner(_) {
  0.0
}

///|
impl Host with window_corner_at(self, _) {
  self.window_corner()
}

///|
impl Host with window_drag(_) {
  ()
}

///|
impl Host with window_act(_, _) {
  ()
}

///|
impl Host with window_zoomed(_) {
  false
}

///|
impl Host with window_snap(_, _, _, _, _) {
  ()
}

///|
impl Host with window_snap_state(_) {
  0
}

///|
impl Host with window_opens(_) {
  false
}

///|
impl Host with window_open(_, _) {
  false
}

///|
impl Host with set_cursor(_, _) {
  ()
}

///|
impl Host with set_badge(_, _) {
  ()
}

///|
impl Host with menu_setup(_, _) {
  ()
}

///|
impl Host with local_station(_) {
  ""
}

///|
impl Host with local_station_act(_, _) {
  ()
}

///|
impl Host with mods_held(_) {
  0
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
impl Host with utc_offset_min(_, _) {
  0
}

///|
impl Host with event_time(_) {
  -1.0
}

///|
impl Host with event_finger(_) {
  -1
}

///|
impl Host with frame_late(_) {
  0.0
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
impl Host with glyph_put(_, _, _, _) {
  ()
}

///|
impl Host with atlas_size(_, _) {
  0
}

///|
impl Host with glyphs_ahead(_, _, _) {
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
impl Host with face_add_family(_, _, _) {
  false
}

///|
impl Host with local_font_families(_) {
  ""
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
impl Host with text_menu(_, _, _, _, _, _, _) {
  ()
}

///|
impl Host with edit_can(_, _) {
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
impl Host with clipboard_secret_off(_) {
  ()
}

///|
impl Host with clipboard_set_image(_, _) {
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
impl Host with keys_platform(_) {
  -1
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
impl Host with cpu_ms(_) {
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
impl Host with a11y_on(_) {
  false
}

///|
impl Host with a11y_tree(_, _) {
  ()
}

///|
impl Host with font_scale(_) {
  1.0
}

///|
impl Host with system_dark(_) {
  false
}

///|
impl Host with native_pointing(_) {
  0
}

///|
impl Host with keyboard(_) {
  -1
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
impl Host with set_turnable(_, _) {
  false
}

///|
impl Host with share(_, _, _, _, _) {
  false
}

///|
impl Host with perf_state(_) {
  -1
}

///|
impl Host with set_perf(_, _) {
  ()
}

///|
impl Host with perf_line(_, _) {
  ()
}

///|
impl Host with perf_where(_) {
  ""
}

///|
impl Host with perf_size(_) {
  0.0
}

///|
impl Host with perf_read(_) {
  b""
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
impl Host with update_fetch(_, _, _, _, _, _) {
  ()
}

///|
impl Host with update_apply(_, _) {
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
impl Host with drawn_pixels(_, _, _, _, _, _) {
  false
}

///|
impl Host with drawn_pixels_of(_, _, _, _, _, _, _, _, _, _) {
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
impl Host with view_place(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _) {
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
impl Host with view_read_answer(_, _, _, _, _, _) {
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
impl Host with bl_start(_, _, _) {
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
impl Host with pw_able(_) {
  false
}

///|
impl Host with pw_run(_, _) {
  0
}

///|
impl Host with pw_out(_, _) {
  ""
}

///|
impl Host with pw_end(_, _) {
  ()
}

///|
impl Host with af_able(_) {
  false
}

///|
impl Host with af_ask(_, _) {
  0
}

///|
impl Host with af_take(_) {
  ""
}

///|
impl Host with af_end(_) {
  ()
}

///|
impl Host with wa_able(_) {
  false
}

///|
impl Host with wa_get(_, _) {
  0
}

///|
impl Host with wa_out(_, _) {
  ""
}

///|
impl Host with wa_end(_, _) {
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
impl Host with pk_info(_, _, _) {
  ""
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
impl Host with rn_dirty(_, _, _, _, _) {
  ()
}

///|
impl Host with nv_bar(_, _) {
  0
}

///|
impl Host with nv_able(_) {
  false
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
impl Host with st_feeds(_) {
  0
}

///|
impl Host with st_codec(_, _, _, _) {
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
impl Host with cl_files(_, _) {
  0
}

///|
impl Host with cl_file_name(_, _, _) {
  ""
}

///|
impl Host with cl_file(_, _, _) {
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
impl Host with dv_ime_action(_, _) {
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
  sideways_now.set(false)
  turnable_now.set(false)
  // (a new host has been handed nothing)
  nav_said.val = None
}

///|
/// Who answers now: the platform's in a program with mbui/host, asked before a Tester gives its fake (a film's,
/// mbui/src/film: its text and pictures the platform's, Tester::new's `live`).
pub fn host() -> &Host {
  current.val
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
/// The desktop's window kept out of sight as it opens, till the app shows it (window_show), said before `run`: its
/// frames drawn meanwhile, it comes up with what the app has drawn by then, not its ground before that. Nothing where
/// the system shows the app's window itself (iOS, Android, a browser's page) or a host keeps it as it was (Windows,
/// Linux: shown at once).
pub fn window_hold() -> Unit {
  current.val.window_hold()
}

///|
/// The window held (window_hold) shown now; nothing once it is.
pub fn window_show() -> Unit {
  current.val.window_show()
}

///|
/// Whether the window's buttons are in the app's top row now (an inset window, not full screen): the room the app
/// leaves them there.
pub fn window_inset() -> Bool {
  current.val.window_inset()
}

///|
/// Whether the desktop's window fills the screen now (macOS's full screen). False where there is no such window.
pub fn full_screen() -> Bool {
  current.val.full_screen()
}

///|
/// The desktop's window made to fill the screen, or back as it was (macOS's full screen, as its green button does).
/// Nothing where there is no window to size.
pub fn set_full_screen(on : Bool) -> Unit {
  current.val.set_full_screen(on)
}

///|
/// Draw content at this many window points per content point; it takes effect on the next frame.
pub fn set_window_zoom(zoom : Double) -> Unit {
  current.val.set_window_zoom(zoom)
}

///|
/// An app's window-wide key, offered before an embedded native page takes it; nonzero when the app took it.
pub fn set_window_key(f : FuncRef[(Int, Int) -> Int]) -> Unit {
  current.val.set_window_key(f)
}

///|
/// How round the system draws the window's corners now, in points: the outermost corner of all, what lies in it
/// concentric with it as with any container's (@ui's corners.mbt). 0 where they are square (filling the screen,
/// maximised, a browser's page, Windows 10) or where the system says nothing of them.
pub fn window_corner() -> Double {
  current.val.window_corner()
}

///|
/// How round the system draws the window's corner `k` (0 top left, then round it): each its own where they differ (an
/// iPhone Duo's outer screen: the two along its hinge 8, the others 59), window_corner the roundest of them.
pub fn window_corner_at(k : Int) -> Double {
  current.val.window_corner_at(k)
}

///|
/// The press under way moves the window (a press on the app's own top row, @ui's Ctx::window_drag): the host's from
/// here, as its title bar's would be.
pub fn window_drag() -> Unit {
  current.val.window_drag()
}

///|
/// What the window's own buttons do, asked by the app where it draws them (a window whose top row is the app's and
/// whose system draws no buttons in it: Windows'): 1 minimized, 2 maximized or back as it was, 3 closed (as its close
/// button closes it). Nothing where there is no such window.
pub fn window_act(what : Int) -> Unit {
  current.val.window_act(what)
}

///|
/// Whether the window is maximized now (Windows: what its maximize button brings back as it was). False where there
/// is no such window.
pub fn window_zoomed() -> Bool {
  current.val.window_zoomed()
}

///|
/// Where the app draws the window's maximize button this frame, in points in the window (w 0: none): the host's there,
/// as its title bar's own (Windows: hit as its maximize button, so the system's Snap Layouts open from it as the
/// pointer rests on it; the press on it the host's, which maximizes the window or brings it back). The pointer there is
/// the host's, not the app's: window_snap_state says how it stands. Nothing where there is no such window.
pub fn window_snap(x : Double, y : Double, w : Double, h : Double) -> Unit {
  current.val.window_snap(x, y, w, h)
}

///|
/// How the pointer stands on the window's maximize button the app draws (window_snap): 0 not on it, 1 on it, 2
/// pressing it. The app is drawn again as it changes.
pub fn window_snap_state() -> Int {
  current.val.window_snap_state()
}

///|
/// Whether the app can open a window of its own beside this one (window_open): a desktop's (macOS, Windows, Linux);
/// false on a phone, a tablet and the web.
pub fn window_opens() -> Bool {
  current.val.window_opens()
}

///|
/// Another window of the app opened beside this one, for `what` (the app's words for what it shows there): another run
/// of the same program, as the system starts it, with MBUI_WINDOW=`what` in its environment; it runs once, as many
/// times as asked (not handed to the one running, as the app started again is), and ends as its window closes. Whether
/// it was started (false where window_opens is not).
pub fn window_open(what : String) -> Bool {
  current.val.window_open(what)
}

///|
/// The pointer's shape from now on: 0 the arrow, 1 a hand, 2 the text's I-beam, 3 resizing sideways, 4 up and down,
/// 5 an open hand, 6 a closed hand, 7 a crosshair, 8 what cannot be done. Nothing where there is no pointer.
pub fn set_cursor(kind : Int) -> Unit {
  current.val.set_cursor(kind)
}

///|
/// The number on the app's icon (macOS's Dock tile: what waits for the person); 0 none. Nothing where the system
/// shows none.
pub fn set_badge(n : Int) -> Unit {
  current.val.set_badge(n)
}

///|
/// The app's menus in the system's menu bar (macOS's), as JSON: an array of menus, each
/// `{"title": …, "items": [item, …]}` (the first the app's own, its title the system's), an item
/// `{"title": …, "role": …}` the system's own (`about`, `hide`, `hideOthers`, `showAll`, `quit`, `undo`, `redo`,
/// `cut`, `copy`, `paste`, `selectAll`, `services`, `close`, `minimize`, `zoom`, `fullScreen`, `front`: their keys
/// the system's),
/// `{"title": …, "action": …, "keys"?: "Mod+Shift+H", "enabled"?: false}` the app's (chosen, said on `system_channel` as
/// `{"menu": action}`; its keys shown, the app's to take), or `{"separator": true}`; a menu `"role": "window"` is the
/// system's list of windows too, `"role": "actions"` one of the app's actions only (their keys never taken by the
/// menu), `"role": "tray"` the menu of the app's icon in Windows' notification area and among a Linux desktop's apps'
/// icons (no menu bar's: its items' roles `show`, the window brought back, and `quit`; the Mac leaves it out). Given
/// again as what it shows changes. Nothing where the system has no menu bar nor such an icon.
pub fn menu_setup(json : String) -> Unit {
  current.val.menu_setup(json)
}

///|
/// This machine's station as the system says it (macOS: its data ~/.stillfail, whether it runs and by what, its release
/// and whether the installer put one there, `installed`, the workspace its data is in, what is being done to it and
/// what failed last), as JSON; "" where there is none or no way to it.
pub fn local_station() -> String {
  current.val.local_station()
}

///|
/// Something done to this machine's station: start, stop, restart (as `local_station` then says), log, folder (opened);
/// `install {"origin", "token", "channel"}` (the station's installer with a workspace's one-time token: downloaded,
/// joined, run as a service) and `update {"origin", "channel"}` (the installer with none: the station here brought up
/// to the latest release, run as a service), `doing` while they run, as the others.
pub fn local_station_act(action : String) -> Unit {
  current.val.local_station_act(action)
}

///|
/// The keys held down now that change what a press or a drag does (shift 1, control 2, option/alt 4, command 8: as a
/// key's own modifiers are told): what a drag let go does by them (Finder's ⌥ a copy). None where there is no keyboard.
pub fn mods_held() -> Int {
  current.val.mods_held()
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
/// What the pointer's event being delivered came from, where one machine has both: 1 a finger on the screen, 0 a
/// mouse, a trackpad or a pen (Windows: a touch screen beside a mouse); -1 where the host does not say (its system's
/// hand: Android's and iOS's fingers, a Mac's pointer).
pub fn event_finger() -> Int {
  current.val.event_finger()
}

///|
/// How far the machine's local time is ahead of UTC at `at_ms` (ms since 1970), in minutes (its zone and summer time):
/// for a date or a time of day shown only. A run to a declared moment (a scripted shot) has 0, as its wall_ms is its own.
pub fn utc_offset_min(at_ms : Double) -> Int {
  current.val.utc_offset_min(at_ms)
}

///|
/// When the input event being delivered happened, on now()'s clock (ms):
/// a touch's own time, which comes before it is handled (a frame's touches
/// are handled together); negative when the host doesn't say.
pub fn event_time() -> Double {
  current.val.event_time()
}

///|
/// How much later than its time (the moment it was drawn for: the frame's `t`) the frame before this one reached the
/// screen, in ms: 0 on time, as a host says where it cannot tell (a Tester's, a browser's), and where frames are not
/// drawn one after the other (the first after a pause).
pub fn frame_late() -> Double {
  current.val.frame_late()
}

///|
/// The system: 0 macOS, 1 iOS, 2 Android, 3 Windows, 4 a browser, 5 Linux.
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
/// Glyph `key` (a cluster `shape` or `text_key` gave) drawn, its picture held for `glyph_put`: in `out` 0 and 0 (where
/// it goes in the atlas is the caller's: atlas.mbt), its picture's width and height in points (its pixels at the
/// host's scale; 0: nothing to draw), where its top left is from the pen on the baseline, and 1 where it is in colours
/// of its own (an emoji), else 0. Drawn again each time it is asked for: the caller asks for what its atlas lacks.
pub fn glyph(key : Int, out : FixedArray[Double]) -> Unit {
  current.val.glyph(key, out)
}

///|
/// The picture of glyph `key`, drawn by the `glyph` asked last, put in its atlas with its top left at pixel `x`, `y`
/// (there before the next frame is drawn), over whatever was there: in colour glyphs' own atlas (where the host has
/// one) `x` is `colour_atlas_u` past its place across in it, as its instances say it.
pub fn glyph_put(key : Int, x : Int, y : Int) -> Unit {
  current.val.glyph_put(key, x, y)
}

///|
/// The side of the host's atlas the glyphs of its words are drawn from, in pixels, or (`colour`) of colour glyphs'
/// own (an emoji's: 0, they are in the words' atlas with the others); 0: none.
pub fn atlas_size(colour : Bool) -> Int {
  current.val.atlas_size(colour)
}

///|
/// How far across past its place in it a glyph in colour glyphs' own atlas is said, to the host (glyph_put) and in its
/// instances (scene.mbt: its renderer takes the atlas by it).
pub let colour_atlas_u : Int = 16384

///|
/// The glyphs of the first `n` of `keys`, shaped and not drawn yet (on a page still off the screen, or below what is
/// shown), for the host to draw ahead, off the frames' thread, so that `glyph` finds them drawn when they come into
/// view. What `glyph` answers is the same either way: only when the work is done changes. A host may do nothing.
pub fn glyphs_ahead(keys : FixedArray[Int], n : Int) -> Unit {
  current.val.glyphs_ahead(keys, n)
}

///|
/// A font file (TrueType or OpenType, at `path`) made part of face `face` (style.mbt: face_ui, face_text, face_code,
/// or 4 to 15 for what names it), for `weight` (0: a variable file, every weight from it). False when the host could
/// not read it as a font (the face as it was). What was shaped or drawn before is the host's to forget
/// (atlas_generation moves on).
/// Face `face` set in a family installed on this machine (`family`, as local_font_families names it): its every style
/// the system's. False where the host has none of that name (or no way to it).
pub fn face_add_family(face : Int, family : String) -> Bool {
  current.val.face_add_family(face, family)
}

///|
/// The font families installed on this machine, as a JSON array of their names, in the order of the user's
/// language (the system's hidden ones left out); "" where the host has no way to them (a phone, a browser).
pub fn local_font_families() -> String {
  current.val.local_font_families()
}

///|
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
/// Moves on as what the host drew and measured before is gone: its faces or its scale changed, its atlas lost (a new
/// drawing surface). Never as its atlas fills: what goes where in it is the caller's (atlas.mbt).
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
/// What a field's selected words can have done to them: cut, copy, paste, select all (text_menu's `can`).
pub let text_menu_cut : Int = 1

///|
pub let text_menu_copy : Int = 2

///|
pub let text_menu_paste : Int = 4

///|
pub let text_menu_select_all : Int = 8

///|
/// What a field has to undo and to do again (edit_can's `can`, beside the four above).
pub let text_menu_undo : Int = 16

///|
pub let text_menu_redo : Int = 32

///|
/// The system's floating menu for a field's words (Android's text toolbar: ActionMode.TYPE_FLOATING) `shown` over the
/// window's rectangle (`x`, `y`, `w`, `h`: the words picked, or the caret), offering what `can` says (text_menu_*); or
/// put away. What is chosen comes as the keys and the paste the field already takes (select all, copy, cut: keys 12,
/// 13, 14; paste: the clipboard's words as text), the menu then gone. A host with none shows nothing.
pub fn text_menu(shown : Bool, x : Double, y : Double, w : Double, h : Double, can : Int) -> Unit {
  current.val.text_menu(shown, x, y, w, h, can)
}

///|
/// What the menu bar's editing items (a Mac's 编辑: 撤销, 重做, 剪切, 拷贝, 粘贴, 全选) can do now, said as it changes:
/// text_menu_* (text_menu_undo, text_menu_redo with them) for the field with the focus, or copy for the words picked
/// with the pointer where no field has it; an item it does not say is greyed, as the system's fields have theirs. A
/// host with no menu bar does nothing with it.
pub fn edit_can(can : Int) -> Unit {
  current.val.edit_can(can)
}

///|
pub fn clipboard_set(s : String) -> Unit {
  current.val.clipboard_set(s)
}

///|
/// A secret put on the system's clipboard: marked sensitive where the system masks such (Android 13 on), kept out of
/// the clipboard's history and the cloud's where it keeps them (Windows), kept to this device (iOS, which takes it off
/// itself `clear_ms` later). Elsewhere as clipboard_set. The app takes it off `clear_ms` later on its own clock
/// (Ctx::copy_secret: clipboard_secret_off).
pub fn clipboard_set_secret(s : String, clear_ms~ : Double) -> Unit {
  current.val.clipboard_set_secret(s, clear_ms)
}

///|
/// The last secret put on the clipboard (clipboard_set_secret) taken off, unless something else was copied since
/// (the app's or another's: the system says whether the clipboard changed). As the app ends before then, a desktop
/// host takes it off itself (Windows).
pub fn clipboard_secret_off() -> Unit {
  current.val.clipboard_secret_off()
}

///|
/// A picture put on the system's clipboard (an image file's bytes: PNG, JPEG…), as a picture other apps paste. A host
/// with no such clipboard (a browser's page, Android) puts nothing.
pub fn clipboard_set_image(data : Bytes) -> Unit {
  current.val.clipboard_set_image(data)
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
/// The system whose keys the person types with, as `platform` numbers them, where it is not the host's own: a
/// browser's, the system under it (⌥← a word on a Mac's, Ctrl+← on Windows'); -1 the host's own.
pub fn keys_platform() -> Int {
  current.val.keys_platform()
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
/// The CPU's time the whole process has had since it started, every thread's (the app's and what runs beside it: a
/// core's, the system's for it), in ms (-1: not known on this host): a probe's (MBUI_PROBE) share of a CPU.
pub fn cpu_ms() -> Double {
  current.val.cpu_ms()
}

///|
/// An environment variable ("" when unset; in a browser, the page's query
/// parameter of that name).
pub fn env(name : String) -> String {
  current.val.env(name)
}

///|
/// Who to tell when the app comes to the front or leaves it: `f` gets 1 while its window is shown, | 2 while it is
/// also in front (the key window of the active app; Android: the activity resumed with the window's focus), | 4 where
/// the app goes on with its window not shown (a desktop's app put away to the notification area or minimized: what
/// comes from outside, the core's words, still runs its frames, though nothing of them is shown: Windows'). Told on
/// each change, on the app's thread (Android: before the GL thread pauses). Hosts that never tell leave the app as
/// shown and in front.
pub fn set_app_state(f : FuncRef[(Int) -> Unit]) -> Unit {
  current.val.set_app_state(f)
}

///|
/// Whether something reads the app's widgets out (Android: an accessibility service on, TalkBack's or another's): the
/// app then tells the host what its widgets are as they change (`a11y_tree`, @ui's semantics.mbt).
pub fn a11y_on() -> Bool {
  current.val.a11y_on()
}

///|
/// What the app's widgets are now, for the system's accessibility (@ui's semantics.mbt says the lines). What is asked
/// of one comes back on the channel `a11y_channel`.
pub fn a11y_tree(tree : String) -> Unit {
  current.val.a11y_tree(tree)
}

///|
/// The channel what the system's accessibility asks of a widget is posted on (`{"id": widget, "action": name}`): the
/// framework's own (@ui takes it).
pub let a11y_channel : String = "a11y"

///|
/// How much bigger the system's setting for the size of words makes them (Android's fontScale: 1 as it is, 1.3 the
/// largest of most phones' steps; Windows' Text size, up to 2.25; Linux's text scaling): words are drawn that much
/// bigger, as Compose's sp are; lengths are not.
pub fn font_scale() -> Double {
  current.val.font_scale()
}

///|
/// What the system was started to be used with (the native input), as the host can tell at launch: 1 touch (iOS and
/// iPadOS with no pointing device, Android with no mouse or touchpad among its input devices, Windows with a touch
/// screen and no mouse or in tablet mode), 2 keyboard and mouse (macOS; iOS and iPadOS with a pointer, Android with a
/// mouse or a touchpad: DeX, ChromeOS; Windows otherwise), 0 where it cannot tell (the platform's then: @ui).
pub fn native_pointing() -> Int {
  current.val.native_pointing()
}

///|
/// Whether a keyboard is at hand now, as the host can tell it as it is asked (it asks for a frame as one comes or
/// goes): 1 yes (macOS and Windows always; Android with a physical keyboard of letters among its input devices, iOS and
/// iPadOS with one connected: GCKeyboard), 0 no, -1 where it cannot tell (the platform's then: @ui).
pub fn keyboard() -> Int {
  current.val.keyboard()
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
/// Android does it (the activity's requested orientation, its window's insets controller), and iOS (the scene's
/// orientations, the status bar and the home indicator hidden); elsewhere nothing turns.
pub fn set_sideways(on : Bool) -> Unit {
  sideways_now.set(on)
  current.val.set_sideways(on)
}

///|
/// A phone held upright only (Android's portrait, an iPhone's) let turn as the person holds it while `on` (a station's
/// screen looked at): the system's rotation lock honoured, so with it on Android offers its turn button as the phone is
/// turned (a fixed portrait gets none); `false`, upright only again. Set_sideways still turns it while it asks. Android
/// and iOS do it where the app is held upright (a phone; a tablet turns anyway); elsewhere nothing changes.
pub fn set_turnable(on : Bool) -> Unit {
  turnable_now.set(current.val.set_turnable(on) && on)
}

///|
/// Whether the app has the device turned sideways (set_sideways), or lets a phone held upright only turn as it is held
/// (set_turnable): its window as wide as it is because the app turned it or let it turn, for a film or a screen over
/// all of it, not because the screen is another kind (what a layout goes by is not this turn: still.fail's @sf.layout
/// keeps the one it had).
pub fn sideways() -> Bool {
  sideways_now.get() || turnable_now.get()
}

///|
/// Whether the app has turned the device sideways itself (set_sideways on): a film or a screen over all of the window,
/// to its edges, under what the system has at its sides (@ui.system_bars `left` and `right`, a phone's cutout) too.
pub fn turned_sideways() -> Bool {
  sideways_now.get()
}

///|
// kept across runs: put back as a host is set
let sideways_now : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
// kept across runs: put back as a host is set
let turnable_now : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether this device can keep a performance record, and keeps one (-1 it cannot, 0 off, 1 on): the host remembers it
/// across launches (a setting of this device's, not synced) and starts recording as the app starts when it is on. Every
/// 5 s while on, the host writes a line of what the process takes (its share of a CPU, by thread, the device's thermal
/// state, …) to a file of the app's own, and the app's frames their summary (perf_line): nothing leaves the device.
/// iOS keeps one; elsewhere -1.
pub fn perf_state() -> Int {
  current.val.perf_state()
}

///|
/// Whether a performance record is being kept now (perf_state 1): asked each frame by the frame probe (a flag the host
/// reads, nothing more).
pub fn perf_recording() -> Bool {
  perf_state() == 1
}

///|
/// The performance record kept from now on, or no longer (perf_state), at once and from the next launch on; nothing
/// where the device keeps none.
pub fn set_perf(on : Bool) -> Unit {
  if perf_state() < 0 {
    return
  }
  current.val.set_perf(on)
}

///|
/// A line of the app's into the performance record while it is kept (the host puts the wall time before it): the
/// frame probe's summary, what the app is doing that warms a device (a station's screen looked at). Nothing while it
/// is not kept.
pub fn perf_line(line : String) -> Unit {
  if perf_recording() {
    current.val.perf_line(line)
  }
}

///|
/// Where the performance record's files are, as the device's files show the app's ("Documents/perf"): "" where none is
/// kept.
pub fn perf_where() -> String {
  current.val.perf_where()
}

///|
/// How many bytes the performance record's files have on the device now (the last few files, each at most a few MB).
pub fn perf_size() -> Double {
  current.val.perf_size()
}

///|
/// The performance record's files as one, the oldest first (what is written meanwhile in it too), to hand on through
/// the system's share sheet (@hostapi.share): a release build's files are nowhere a person can take them from. Empty
/// where none is kept.
pub fn perf_read() -> Bytes {
  current.val.perf_read()
}

///|
/// Words (`text`), or a file of `data` named `name` (`mime`), handed to another app through the system's share sheet
/// (Android's chooser, macOS's sharing picker); false where there is none (or no app takes it).
pub fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  current.val.share(text, name, mime, data)
}

///|
/// What another app shared into this one since last asked (Android's ACTION_SEND of text or files, ACTION_SEND_MULTIPLE
/// of files; iOS's share extension, what it kept taken as the app comes to the front: src/host/ios_share.m;
/// MBUI_SHARE_FILES, paths split by |, on macOS and iOS for scripted runs), as JSON text `{"text","title","files"}`,
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
/// A newer build at `url` (its `sha256`, `size` bytes) downloaded as `name` by itself and checked, made ready to be put
/// in this app's place (`update_apply`; Android's Updates.java puts it in place by itself once the app has been out of
/// sight a while). `now`: asked by the person, downloaded at once; else it may wait for a network that costs nothing
/// (Android's: none metered). One already ready, or coming, by that name: nothing more. Nothing where the app does
/// not update itself. How it goes: `update_state`.
pub fn update_fetch(url : String, sha256 : String, size : Double, name : String, now : Bool) -> Unit {
  current.val.update_fetch(url, sha256, size, name, now)
}

///|
/// The build made ready (`update_fetch`) put in this app's place now: the app ends, and is opened again as the newer
/// build where the system lets it (macOS, Windows, Linux); where it does not (Android: no app opens itself from
/// behind), the newer build says `said` in a notification that opens it. Where the person's leave to install apps
/// is wanted (Android's), the system's page for it is opened first, and once it is given the build is put in place.
pub fn update_apply(said : String) -> Unit {
  current.val.update_apply(said)
}

///|
/// How an update goes, as JSON text: `{"phase","percent","error","file"}`: phase idle, waiting (for a network that
/// costs nothing), downloading, retrying, ready (downloaded and checked, waiting to be put in place), allow (the
/// person's leave to install apps wanted), installing, failed; `file` the build's name (update_fetch's) while there is
/// one; `away` true where a build ready is put in place by itself while the app is out of sight (Android's); "" where
/// the app does not update itself.
pub fn update_state() -> String {
  current.val.update_state()
}

///|
/// A package (an APK a chat has) handed to the system's installer, which asks the person to confirm (Android:
/// still.fail's Install.kt installApk). What comes of it, when it is not installed, comes on @hostapi.system_channel
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
/// The frame presented last, drawn again by the renderer as it was, and its pixels in the rectangle `x`, `y`, `w` by `h`
/// (device pixels from its top left) into `out` (at least w × h × 4 long: RGBA premultiplied, rows from the top): false
/// where the rectangle is not all in it, or the frame cannot be read back here.
pub fn drawn_pixels(x : Int, y : Int, w : Int, h : Int, out : FixedArray[Byte]) -> Bool {
  current.val.drawn_pixels(x, y, w, h, out)
}

///|
/// Instances never presented (`count` of them in `inst`, as `present` takes a frame's: a shot's, mbui/src/ui/shot.mbt)
/// drawn by the renderer as a frame is, but `scale` device pixels a point (whatever the window's) into a picture of
/// their own `w` by `h` device pixels, their 0, 0 its top left, on its ground `r`, `g`, `b`, and its pixels into `out`
/// as drawn_pixels gives the frame's (RGBA premultiplied, rows from the top); the frame presented stays as it was
/// (drawn again, it is the same). False where nothing can be read back here.
pub fn drawn_pixels_of(
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
  current.val.drawn_pixels_of(inst, count, r, g, b, scale, w, h, out)
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
/// page to read them before the host says `{"slow":n}` and takes no more of it). 4 where the app draws what takes a
/// press over it. 5 (any view, `text` "") raised over all the others: stacked under none of them, the one a press goes
/// to where they meet (ui's stack_views, as the app paints them); a view opened goes over those opened before it.
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
/// What the image (scene.mbt's slot 20) of the instance the app paints where a native view shows (kind 9) is: this plus
/// the view's id (exact in the renderers' 32-bit floats, above `stream_tex_base`'s). Its c2 says the part of the view's
/// content it covers (u0 v0 du dv, shares of the content's rect). A host whose views are under its surface (macOS,
/// iOS, Windows, the browser) leaves the canvas clear there, a hole the view shows through, and draws nothing of it; a
/// host that draws each view into a picture of its own (Android: NativeViews.Picture) draws that part of it there, in
/// the frame, so it moves as what is around it does.
pub let view_tex_base : Int = 8388608

///|
/// Where the view shows, in the app's coordinates (logical pixels from the window's top left): its content in (x, y,
/// w, h) (a video's picture is stretched to it), its corners round by `r0` to `r3` (top left, then round it; 0:
/// square), seen only within the clip (cx0, cy0)-(cx1, cy1); hidden when not `shown`. Told again whenever it moves
/// (each frame it does).
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
  r0 : Double,
  r1 : Double,
  r2 : Double,
  r3 : Double,
  shown : Bool,
) -> Unit {
  current.val.view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, r0, r1, r2, r3, shown)
}

///|
/// The view gone (its player stopped, its page closed).
pub fn view_close(id : Int) -> Unit {
  current.val.view_close(id)
}

///|
/// A player told: `op` 1 play, 2 pause, 3 to `value` ms (the frame there, exactly), 4 at `value` times its speed, 11
/// to about `value` ms at once (the nearest key frame: nothing before it decoded); a site: 5 back, 6 forward, 7
/// reload, 8 laid out at its rect over `value` and drawn at `value` times (a viewport's own size shown smaller).
pub fn view_control(id : Int, op : Int, value : Double) -> Unit {
  current.val.view_control(id, op, value)
}

///|
/// How the view stands: -1 failed, -2 a player's format unsupported, -3 its file not parseable, -4 unsupported or
/// damaged, 0 opening, 1 ready.
/// `out` (10): its length in ms (-1 not known), where it is (ms), playing (1; and while it seeks within what it has, if
/// it is to play), the picture's own width and height (pixels), the bytes it has been given, whether a frame has been
/// drawn (a page: loaded), buffering (1: to play and waiting on bytes still to come through the app, not a seek
/// within what it has, nor one while paused), how far on it has what it needs to play (ms; 0 not said), played to its
/// end (1).
pub fn view_info(id : Int, out : FixedArray[Double]) -> Int {
  current.val.view_info(id, out)
}

///|
/// A read the player waits on: its id (0: none waiting), `out` [0] its offset, [1] how many bytes it wants; or minus
/// the id of one it let go of (it wants none of what is left of it: the app stops reading it, answers it no more).
/// Each is answered as its bytes come (`view_read_answer`); the host asks for a frame when one comes.
pub fn view_read_next(id : Int, out : FixedArray[Double]) -> Int {
  current.val.view_read_next(id, out)
}

///|
/// Read `req`'s next bytes, as they come: those after what it was answered before (all of them at most as many as it
/// wanted; fewer is fine, none only at the file's end), `more` while more of it comes (its last answer may bring
/// none); `total` the file's whole size (-1 not known: Apple's player needs it, so give it, at the latest with its
/// last answer); -2: it could not be read (its last: the player fails).
pub fn view_read_answer(id : Int, req : Int, data : Bytes, total : Double, more : Bool) -> Unit {
  current.val.view_read_answer(id, req, data, total, more)
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
/// none takes one; iOS's SFSafariViewController); elsewhere as open_url. False when nothing took it.
pub fn open_tab(url : String) -> Bool {
  current.val.open_tab(url)
}

///|
/// What the notice says that holds the app up while it listens for a browser coming back (@hostapi.browser_login, the
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
fn bl_start(path : String, done : String) -> Int {
  current.val.bl_start(path, done)
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

// This device's password manager (passwords.mbt): `op`, run with the arguments given (a JSON array), how it ended.

///|
fn pw_able() -> Bool {
  current.val.pw_able()
}

///|
fn pw_run(args : String) -> Int {
  current.val.pw_run(args)
}

///|
fn pw_out(id : Int) -> String {
  current.val.pw_out(id)
}

///|
fn pw_end(id : Int) -> Unit {
  current.val.pw_end(id)
}

// The system's autofill (autofill.mbt): a login of a site asked of its service, the one picked taken.

///|
fn af_able() -> Bool {
  current.val.af_able()
}

///|
fn af_ask(host : String) -> Int {
  current.val.af_ask(host)
}

///|
fn af_take() -> String {
  current.val.af_take()
}

///|
fn af_end() -> Unit {
  current.val.af_end()
}

// This device's passkeys (passkeys.mbt): a sign-in signed, how it ended.

///|
fn wa_able() -> Bool {
  current.val.wa_able()
}

///|
fn wa_get(ask : String) -> Int {
  current.val.wa_get(ask)
}

///|
fn wa_out(id : Int) -> String {
  current.val.wa_out(id)
}

///|
fn wa_end(id : Int) -> Unit {
  current.val.wa_end(id)
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
fn pk_info(id : Int, i : Int) -> String {
  current.val.pk_info(id, i)
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
fn nv_bar(spec : String) -> Int {
  current.val.nv_bar(spec)
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
fn st_feeds() -> Int {
  current.val.st_feeds()
}

///|
fn st_codec(id : Int, cmd : String, data : Bytes) -> Unit {
  current.val.st_codec(id, cmd, data)
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
fn cl_files(id : Int) -> Int {
  current.val.cl_files(id)
}

///|
fn cl_file_name(id : Int, i : Int) -> String {
  current.val.cl_file_name(id, i)
}

///|
fn cl_file(id : Int, i : Int) -> Bytes {
  current.val.cl_file(id, i)
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
fn dv_ime_action(kind : Int) -> Unit {
  current.val.dv_ime_action(kind)
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

///|
/// A part of the next frame presented that changed from the one before (points), for a host that keeps its picture
/// and draws only those parts again, the rest as it drew it (docs/partial-redraw.md): said once for each part before
/// `present`; `w` < 0, all of it; once with `w` 0, none. A frame nothing was said for is drawn whole.
pub fn render_dirty(x : Double, y : Double, w : Double, h : Double) -> Unit {
  current.val.rn_dirty(x, y, w, h)
}

///|
impl Host with st_audio_here(_) { 0 }

///|
impl Host with st_audio(_, _, _) { () }

///|
fn st_audio_here() -> Int { current.val.st_audio_here() }

///|
fn st_audio(id : Int, data : Bytes) -> Unit { current.val.st_audio(id, data) }

///|
impl Host with st_layers(_) { 0 }

///|
fn st_layers() -> Int { current.val.st_layers() }

///|
impl Host with st_pointer(_, _, _, _, _, _, _) { () }

///|
fn st_pointer(id : Int, png : Bytes, w : Double, h : Double, hx : Double, hy : Double) -> Unit {
  current.val.st_pointer(id, png, w, h, hx, hy)
}

///|
impl Host with st_pointer_at(_, _, _, _, _) { () }

///|
fn st_pointer_at(id : Int, x : Double, y : Double, shown : Int) -> Unit {
  current.val.st_pointer_at(id, x, y, shown)
}

///|
impl Host with st_direct(_, _, _, _, _) { () }

///|
fn st_direct(id : Int, route : Double, after : Double, what : Int) -> Unit {
  current.val.st_direct(id, route, after, what)
}
impl Host with st_h265_here(_) { 0 }

///|
impl Host with st_hevc(_, _, _, _, _) { () }

///|
fn st_h265_here() -> Int { current.val.st_h265_here() }

///|
fn st_hevc(id : Int, hvcc : Bytes, w : Int, h : Int) -> Unit { current.val.st_hevc(id, hvcc, w, h) }
