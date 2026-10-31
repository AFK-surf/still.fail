// The platform's host (host_native.mbt and its C, Objective-C, C++; host_js.mbt and web/host.js) as mbui/hostapi's
// `Host`, set as the program starts: an app's main imports this package for it (and for its code linked in). Nothing
// else imports it: a test's program, given a Tester's fake host, links none of it.

///|
priv struct Native {}

///|
fn init {
  @hostapi.set_host(Native::{  })
}

///|
impl @hostapi.Host for Native with window_setup(_, min_w, min_h, w, h, inset) {
  window_setup(min_w, min_h, w, h, inset~)
}

///|
impl @hostapi.Host for Native with window_hold(_) {
  window_hold()
}

///|
impl @hostapi.Host for Native with window_show(_) {
  window_show()
}

///|
impl @hostapi.Host for Native with window_inset(_) {
  window_inset()
}

///|
impl @hostapi.Host for Native with full_screen(_) {
  full_screen()
}

///|
impl @hostapi.Host for Native with set_full_screen(_, on) {
  set_full_screen(on)
}

///|
impl @hostapi.Host for Native with window_corner(_) {
  window_corner()
}

///|
impl @hostapi.Host for Native with window_corner_at(_, k) {
  window_corner_at(k)
}

///|
impl @hostapi.Host for Native with window_drag(_) {
  window_drag()
}

///|
impl @hostapi.Host for Native with window_act(_, what) {
  window_act(what)
}

///|
impl @hostapi.Host for Native with window_zoomed(_) {
  window_zoomed()
}

///|
impl @hostapi.Host for Native with window_snap(_, x, y, w, h) {
  window_snap(x, y, w, h)
}

///|
impl @hostapi.Host for Native with window_snap_state(_) {
  window_snap_state()
}

///|
impl @hostapi.Host for Native with window_opens(_) {
  window_opens()
}

///|
impl @hostapi.Host for Native with window_open(_, what) {
  window_open(what)
}

///|
impl @hostapi.Host for Native with set_cursor(_, kind) {
  set_cursor(kind)
}

///|
impl @hostapi.Host for Native with set_badge(_, n) {
  set_badge(n)
}

///|
impl @hostapi.Host for Native with menu_setup(_, json) {
  menu_setup(json)
}

///|
impl @hostapi.Host for Native with local_station(_) {
  local_station()
}

///|
impl @hostapi.Host for Native with local_station_act(_, a) {
  local_station_act(a)
}

///|
impl @hostapi.Host for Native with mods_held(_) {
  mods_held()
}

///|
impl @hostapi.Host for Native with run(_, title, frame, pointer, wheel, key, text) {
  run(title, frame, pointer, wheel, key, text)
}

///|
impl @hostapi.Host for Native with now(_) {
  now()
}

///|
impl @hostapi.Host for Native with wall_ms(_) {
  wall_ms()
}

///|
impl @hostapi.Host for Native with utc_offset_min(_, at_ms) {
  utc_offset_min(at_ms)
}

///|
impl @hostapi.Host for Native with event_time(_) {
  event_time()
}

///|
impl @hostapi.Host for Native with event_finger(_) {
  event_finger()
}

///|
impl @hostapi.Host for Native with frame_late(_) {
  frame_late()
}

///|
impl @hostapi.Host for Native with platform(_) {
  platform()
}

///|
impl @hostapi.Host for Native with request_frame(_) {
  request_frame()
}

///|
impl @hostapi.Host for Native with wake_after(_, ms) {
  wake_after(ms)
}

///|
impl @hostapi.Host for Native with font_metrics(_, size, weight, style, out) {
  font_metrics(size, weight, style, out)
}

///|
impl @hostapi.Host for Native with shape(_, text, size, weight, style, out) {
  shape(text, size, weight, style, out)
}

///|
impl @hostapi.Host for Native with text_key(_, text, size, weight, style) {
  text_key(text, size, weight, style)
}

///|
impl @hostapi.Host for Native with glyph(_, key, out) {
  glyph(key, out)
}

///|
impl @hostapi.Host for Native with glyph_put(_, key, x, y) {
  glyph_put(key, x, y)
}

///|
impl @hostapi.Host for Native with atlas_size(_, colour) {
  atlas_size(colour)
}

///|
impl @hostapi.Host for Native with glyphs_ahead(_, keys, n) {
  glyphs_ahead(keys, n)
}

///|
impl @hostapi.Host for Native with face_add(_, face, path, weight) {
  face_add(face, path, weight)
}

///|
impl @hostapi.Host for Native with face_add_bytes(_, face, data, weight) {
  face_add_bytes(face, data, weight)
}

///|
impl @hostapi.Host for Native with face_clear(_, face) {
  face_clear(face)
}

///|
impl @hostapi.Host for Native with face_add_family(_, face, family) {
  face_add_family(face, family)
}

///|
impl @hostapi.Host for Native with local_font_families(_) {
  local_font_families()
}

///|
impl @hostapi.Host for Native with atlas_generation(_) {
  atlas_generation()
}

///|
impl @hostapi.Host for Native with present(_, buf, count, r, g, b) {
  present(buf, count, r, g, b)
}

///|
impl @hostapi.Host for Native with set_ime(_, active, x, y, w, h, text, sel_start, sel_end) {
  set_ime(active, x, y, w, h, text, sel_start, sel_end)
}

///|
impl @hostapi.Host for Native with text_menu(_, shown, x, y, w, h, can) {
  ffi_text_menu(if shown { 1 } else { 0 }, x, y, w, h, can)
}

///|
impl @hostapi.Host for Native with edit_can(_, can) {
  ffi_edit_can(can)
}

///|
impl @hostapi.Host for Native with clipboard_set(_, s) {
  clipboard_set(s)
}

///|
impl @hostapi.Host for Native with clipboard_set_image(_, data) {
  clipboard_set_image(data)
}

///|
impl @hostapi.Host for Native with clipboard_set_secret(_, s, clear_ms) {
  clipboard_set_secret(s, clear_ms~)
}

///|
impl @hostapi.Host for Native with clipboard_secret_off(_) {
  clipboard_secret_off()
}

///|
impl @hostapi.Host for Native with log(_, s) {
  log(s)
}

///|
impl @hostapi.Host for Native with bench_mode(_) {
  bench_mode()
}

///|
impl @hostapi.Host for Native with set_outside(_, f) {
  set_outside(f)
}

///|
impl @hostapi.Host for Native with frame_awaiting(_, awaiting, what) {
  frame_awaiting(awaiting, what)
}

///|
impl @hostapi.Host for Native with own_clock(_) {
  own_clock()
}

///|
impl @hostapi.Host for Native with reduce_motion(_) {
  reduce_motion()
}

///|
impl @hostapi.Host for Native with exit(_, code) {
  exit(code)
}

///|
impl @hostapi.Host for Native with mem_bytes(_) {
  mem_bytes()
}

///|
impl @hostapi.Host for Native with set_back(_, back) {
  set_back(back)
}

///|
impl @hostapi.Host for Native with back_enabled(_, on) {
  back_enabled(on)
}

///|
impl @hostapi.Host for Native with reduce_transparency(_) {
  reduce_transparency()
}

///|
impl @hostapi.Host for Native with gpu_ms(_) {
  gpu_ms()
}

///|
impl @hostapi.Host for Native with cpu_ms(_) {
  cpu_ms()
}

///|
impl @hostapi.Host for Native with perf_state(_) {
  perf_state()
}

///|
impl @hostapi.Host for Native with set_perf(_, on) {
  set_perf(on)
}

///|
impl @hostapi.Host for Native with perf_line(_, line) {
  perf_line(line)
}

///|
impl @hostapi.Host for Native with perf_where(_) {
  perf_where()
}

///|
impl @hostapi.Host for Native with perf_size(_) {
  perf_size()
}

///|
impl @hostapi.Host for Native with perf_read(_) {
  perf_read()
}

///|
impl @hostapi.Host for Native with env(_, name) {
  env(name)
}

///|
impl @hostapi.Host for Native with set_app_state(_, f) {
  set_app_state(f)
}

///|
impl @hostapi.Host for Native with system_dark(_) {
  system_dark()
}

///|
impl @hostapi.Host for Native with font_scale(_) {
  font_scale()
}

///|
impl @hostapi.Host for Native with native_pointing(_) {
  native_pointing()
}

///|
impl @hostapi.Host for Native with keyboard(_) {
  keyboard()
}

///|
impl @hostapi.Host for Native with a11y_on(_) {
  a11y_on()
}

///|
impl @hostapi.Host for Native with a11y_tree(_, s) {
  a11y_tree(s)
}

///|
impl @hostapi.Host for Native with set_dark(_, dark) {
  set_dark(dark)
}

///|
impl @hostapi.Host for Native with set_sideways(_, on) {
  set_sideways(on)
}

///|
impl @hostapi.Host for Native with set_turnable(_, on) {
  set_turnable(on)
}

///|
impl @hostapi.Host for Native with share(_, text, name, mime, data) {
  share(text, name, mime, data)
}

///|
impl @hostapi.Host for Native with shared_in(_) {
  shared_in()
}

///|
impl @hostapi.Host for Native with shared_in_file(_, i) {
  shared_in_file(i)
}

///|
impl @hostapi.Host for Native with app_version(_) {
  app_version()
}

///|
impl @hostapi.Host for Native with update_fetch(_, url, sha256, size, name, now) {
  update_fetch(url, sha256, size, name, now)
}

///|
impl @hostapi.Host for Native with update_apply(_, said) {
  update_apply(said)
}

///|
impl @hostapi.Host for Native with update_state(_) {
  update_state()
}

///|
impl @hostapi.Host for Native with install_package(_, name, data) {
  install_package(name, data)
}

///|
impl @hostapi.Host for Native with drive(_, kind, text) {
  drive(kind, text)
}

///|
impl @hostapi.Host for Native with image_load(_, src, max_px) {
  image_load(src, max_px)
}

///|
impl @hostapi.Host for Native with image_load_bytes(_, data, max_px) {
  image_load_bytes(data, max_px)
}

///|
impl @hostapi.Host for Native with image_info(_, id, out) {
  image_info(id, out)
}

///|
impl @hostapi.Host for Native with image_free(_, id) {
  image_free(id)
}

///|
impl @hostapi.Host for Native with image_pixels(_, id, out) {
  image_pixels(id, out)
}

///|
impl @hostapi.Host for Native with drawn_pixels(_, x, y, w, h, out) {
  drawn_pixels(x, y, w, h, out)
}

///|
impl @hostapi.Host for Native with drawn_pixels_of(_, inst, count, r, g, b, scale, w, h, out) {
  drawn_pixels_of(inst, count, r, g, b, scale, w, h, out)
}

///|
impl @hostapi.Host for Native with view_site_next(_, id) {
  view_site_next(id)
}

///|
impl @hostapi.Host for Native with view_site_body(_, id, req) {
  view_site_body(id, req)
}

///|
impl @hostapi.Host for Native with view_site_head(_, id, req, status, headers) {
  view_site_head(id, req, status, headers)
}

///|
impl @hostapi.Host for Native with view_site_chunk(_, id, req, data) {
  view_site_chunk(id, req, data)
}

///|
impl @hostapi.Host for Native with view_site_end(_, id, req, error) {
  view_site_end(id, req, error)
}

///|
impl @hostapi.Host for Native with view_site_state(_, id) {
  view_site_state(id)
}

///|
impl @hostapi.Host for Native with view_site_load(_, id, path) {
  view_site_load(id, path)
}

///|
impl @hostapi.Host for Native with view_tell(_, id, what, text) {
  view_tell(id, what, text)
}

///|
impl @hostapi.Host for Native with view_open(_, kind, arg) {
  view_open(kind, arg)
}

///|
impl @hostapi.Host for Native with view_place(_, id, x, y, w, h, cx0, cy0, cx1, cy1, r0, r1, r2, r3, shown) {
  view_place(id, x, y, w, h, cx0, cy0, cx1, cy1, r0, r1, r2, r3, shown)
}

///|
impl @hostapi.Host for Native with view_close(_, id) {
  view_close(id)
}

///|
impl @hostapi.Host for Native with view_control(_, id, op, value) {
  view_control(id, op, value)
}

///|
impl @hostapi.Host for Native with view_info(_, id, out) {
  view_info(id, out)
}

///|
impl @hostapi.Host for Native with view_read_next(_, id, out) {
  view_read_next(id, out)
}

///|
impl @hostapi.Host for Native with view_read_answer(_, id, req, data, total, more) {
  view_read_answer(id, req, data, total, more)
}

///|
impl @hostapi.Host for Native with pdf_open(_, data) {
  pdf_open(data)
}

///|
impl @hostapi.Host for Native with pdf_pages(_, doc) {
  pdf_pages(doc)
}

///|
impl @hostapi.Host for Native with pdf_page_size(_, doc, page, out) {
  pdf_page_size(doc, page, out)
}

///|
impl @hostapi.Host for Native with pdf_page_load(_, doc, page, max_px) {
  pdf_page_load(doc, page, max_px)
}

///|
impl @hostapi.Host for Native with pdf_close(_, doc) {
  pdf_close(doc)
}

///|
impl @hostapi.Host for Native with view_text(_, id, what) {
  view_text(id, what)
}

///|
impl @hostapi.Host for Native with view_still(_, id) {
  view_still(id)
}

///|
impl @hostapi.Host for Native with save_file(_, name, data) {
  save_file(name, data)
}

///|
impl @hostapi.Host for Native with word_at(_, text, off) {
  word_at(text, off)
}

///|
impl @hostapi.Host for Native with open_url(_, url) {
  open_url(url)
}

///|
impl @hostapi.Host for Native with over_done(_, open_app) {
  over_done(open_app~)
}

///|
impl @hostapi.Host for Native with open_tab(_, url) {
  open_tab(url)
}

///|
impl @hostapi.Host for Native with hold_words(_, channel, title, body) {
  hold_words(channel~, title~, body~)
}

///|
impl @hostapi.Host for Native with post_take(_) {
  post_take()
}

///|
impl @hostapi.Host for Native with post_next(_) {
  post_next()
}

///|
impl @hostapi.Host for Native with ref_begin(_, w, h, scale, bg) {
  ref_begin(w, h, scale, bg)
}

///|
impl @hostapi.Host for Native with ref_text(_, text, size, weight, style, x, base, color, out) {
  ref_text(text, size, weight, style, x, base, color, out)
}

///|
impl @hostapi.Host for Native with ref_end(_, name) {
  ref_end(name)
}

///|
impl @hostapi.Host for Native with ref_frame(_, name) {
  ref_frame(name)
}

///|
impl @hostapi.Host for Native with bl_start(_, path) {
  bl_start(path)
}

///|
impl @hostapi.Host for Native with bl_port(_, id) {
  bl_port(id)
}

///|
impl @hostapi.Host for Native with bl_open(_, id, url) {
  bl_open(id, url)
}

///|
impl @hostapi.Host for Native with bl_back(_, id) {
  bl_back(id)
}

///|
impl @hostapi.Host for Native with bl_end(_, id) {
  bl_end(id)
}

///|
impl @hostapi.Host for Native with pk_start(_, kind) {
  pk_start(kind)
}

///|
impl @hostapi.Host for Native with pk_state(_, id) {
  pk_state(id)
}

///|
impl @hostapi.Host for Native with pk_count(_, id) {
  pk_count(id)
}

///|
impl @hostapi.Host for Native with pk_name(_, id, i) {
  pk_name(id, i)
}

///|
impl @hostapi.Host for Native with pk_bytes(_, id, i) {
  pk_bytes(id, i)
}

///|
impl @hostapi.Host for Native with pk_info(_, id, i) {
  pk_info(id, i)
}

///|
impl @hostapi.Host for Native with pk_end(_, id) {
  pk_end(id)
}

///|
impl @hostapi.Host for Native with kp_begin(_, name, mime, way) {
  kp_begin(name, mime, way)
}

///|
impl @hostapi.Host for Native with kp_append(_, id, data) {
  kp_append(id, data)
}

///|
impl @hostapi.Host for Native with kp_finish(_, id) {
  kp_finish(id)
}

///|
impl @hostapi.Host for Native with kp_state(_, id) {
  kp_state(id)
}

///|
impl @hostapi.Host for Native with kp_where(_, id) {
  kp_where(id)
}

///|
impl @hostapi.Host for Native with kp_end(_, id) {
  kp_end(id)
}

///|
impl @hostapi.Host for Native with ga_access(_) {
  ga_access()
}

///|
impl @hostapi.Host for Native with ga_ask(_) {
  ga_ask()
}

///|
impl @hostapi.Host for Native with ga_answers(_) {
  ga_answers()
}

///|
impl @hostapi.Host for Native with ga_read(_) {
  ga_read()
}

///|
impl @hostapi.Host for Native with ga_read_state(_, id) {
  ga_read_state(id)
}

///|
impl @hostapi.Host for Native with ga_read_rows(_, id) {
  ga_read_rows(id)
}

///|
impl @hostapi.Host for Native with ga_read_end(_, id) {
  ga_read_end(id)
}

///|
impl @hostapi.Host for Native with pk_photo(_, src) {
  pk_photo(src)
}

///|
impl @hostapi.Host for Native with cs_known(_, charset) {
  cs_known(charset)
}

///|
impl @hostapi.Host for Native with cs_decode(_, data, charset) {
  cs_decode(data, charset)
}

///|
impl @hostapi.Host for Native with mk_start(_, image, marks) {
  mk_start(image, marks)
}

///|
impl @hostapi.Host for Native with mk_state(_, id) {
  mk_state(id)
}

///|
impl @hostapi.Host for Native with mk_png(_, id) {
  mk_png(id)
}

///|
impl @hostapi.Host for Native with nt_show(_, channel, tag, title, body, opens) {
  nt_show(channel, tag, title, body, opens)
}

///|
impl @hostapi.Host for Native with nt_cancel(_, tag) {
  nt_cancel(tag)
}

///|
impl @hostapi.Host for Native with rn_dirty(_, x, y, w, h) {
  rn_dirty(x, y, w, h)
}

///|
impl @hostapi.Host for Native with nv_bar(_, spec) {
  nv_bar(spec)
}

///|
impl @hostapi.Host for Native with nv_able(_) {
  nv_able() != 0
}

///|
impl @hostapi.Host for Native with nt_state(_, what) {
  nt_state(what)
}

///|
impl @hostapi.Host for Native with nt_text(_, what) {
  nt_text(what)
}

///|
impl @hostapi.Host for Native with st_open(_) {
  st_open()
}

///|
impl @hostapi.Host for Native with st_h264(_, id, avcc, w, h) {
  st_h264(id, avcc, w, h)
}

///|
impl @hostapi.Host for Native with st_frame(_, id, data, key, ts) {
  st_frame(id, data, key, ts)
}

///|
impl @hostapi.Host for Native with st_jpeg(_, id, data, ts) {
  st_jpeg(id, data, ts)
}

///|
impl @hostapi.Host for Native with st_next(_, id) {
  st_next(id)
}

///|
impl @hostapi.Host for Native with st_show(_, id, ts) {
  st_show(id, ts)
}

///|
impl @hostapi.Host for Native with st_close(_, id) {
  st_close(id)
}

///|
impl @hostapi.Host for Native with st_h264_here(_) {
  st_h264_here()
}

///|
impl @hostapi.Host for Native with st_feeds(_) {
  st_feeds()
}

///|
impl @hostapi.Host for Native with st_codec(_, id, cmd, data) {
  st_codec(id, cmd, data)
}

///|
impl @hostapi.Host for Native with cl_read(_) {
  cl_read()
}

///|
impl @hostapi.Host for Native with cl_state(_, id) {
  cl_state(id)
}

///|
impl @hostapi.Host for Native with cl_picture(_, id) {
  cl_picture(id)
}

///|
impl @hostapi.Host for Native with cl_text(_, id) {
  cl_text(id)
}

///|
impl @hostapi.Host for Native with cl_png(_, id) {
  cl_png(id)
}

///|
impl @hostapi.Host for Native with cl_files(_, id) {
  cl_files(id)
}

///|
impl @hostapi.Host for Native with cl_file_name(_, id, i) {
  cl_file_name(id, i)
}

///|
impl @hostapi.Host for Native with cl_file(_, id, i) {
  cl_file(id, i)
}

///|
impl @hostapi.Host for Native with cl_end(_, id) {
  cl_end(id)
}

///|
impl @hostapi.Host for Native with cl_set(_, text, png, label) {
  cl_set(text, png, label)
}

///|
impl @hostapi.Host for Native with dv_copy_shown(_) {
  dv_copy_shown()
}

///|
impl @hostapi.Host for Native with dv_key_catch(_, on) {
  dv_key_catch(on)
}

///|
impl @hostapi.Host for Native with dv_ime_inset(_) {
  dv_ime_inset()
}

///|
impl @hostapi.Host for Native with dv_keep_awake(_, on) {
  dv_keep_awake(on)
}

///|
impl @hostapi.Host for Native with dv_haptic(_, kind) {
  dv_haptic(kind)
}

///|
impl @hostapi.Host for Native with dv_ime_action(_, kind) {
  dv_ime_action(kind)
}

///|
impl @hostapi.Host for Native with ncall_call(_, name, params) {
  ncall_call(name, params)
}

///|
impl @hostapi.Host for Native with ncall_state(_, id) {
  ncall_state(id)
}

///|
impl @hostapi.Host for Native with ncall_result(_, id) {
  ncall_result(id)
}

///|
impl @hostapi.Host for Native with ncall_end(_, id) {
  ncall_end(id)
}

///|
impl @hostapi.Host for Native with st_audio_here(_) { st_audio_here() }

///|
impl @hostapi.Host for Native with st_audio(_, id, data) { st_audio(id, data) }

///|
impl @hostapi.Host for Native with st_layers(_) { st_layers() }

///|
impl @hostapi.Host for Native with st_pointer(_, id, png, w, h, hx, hy) { st_pointer(id, png, w, h, hx, hy) }

///|
impl @hostapi.Host for Native with st_pointer_at(_, id, x, y, shown) { st_pointer_at(id, x, y, shown) }

///|
impl @hostapi.Host for Native with st_direct(_, id, route, after, what) { st_direct(id, route, after, what) }

impl @hostapi.Host for Native with st_h265_here(_) { st_h265_here() }

///|
impl @hostapi.Host for Native with st_hevc(_, id, hvcc, w, h) { st_hevc(id, hvcc, w, h) }
