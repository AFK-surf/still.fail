// The offscreen application scene in classic Wasm. Text, decoded images and the final frame use the Mac's native
// renderer through scalar host calls; the scene and drive run in the same Tester as sffilm.
///|
struct WasmHost { }
///|
fn metrics(size : Double, weight : Int, style : Int) -> Unit = "probe" "metrics"
///|
fn shape_host(size : Double, weight : Int, style : Int, capacity : Int) -> Int = "probe" "shape"
///|
fn text_key_host(size : Double, weight : Int, style : Int) -> Int = "probe" "textKey"
///|
fn glyph(key : Int) -> Unit = "probe" "glyph"
///|
fn glyph_put(key : Int, x : Int, y : Int) -> Unit = "probe" "glyphPut"
///|
fn atlas_size(colour : Bool) -> Int = "probe" "atlasSize"
///|
fn atlas_generation() -> Int = "probe" "atlasGeneration"
///|
fn result_at(i : Int) -> Double = "probe" "result"
///|
fn face_add_host(face : Int, weight : Int) -> Bool = "probe" "faceAdd"
///|
fn face_add_bytes_host(face : Int, weight : Int) -> Bool = "probe" "faceAddBytes"
///|
fn face_add_family_host(face : Int) -> Bool = "probe" "faceAddFamily"
///|
fn face_clear_host(face : Int) -> Unit = "probe" "faceClear"
///|
fn option_length(key : Int) -> Int = "probe" "optionLength"
///|
fn option_point(key : Int, i : Int) -> Int = "probe" "optionPoint"
///|
fn option_number(key : Int) -> Double = "probe" "optionNumber"
///|
fn image_load_host(max_px : Int) -> Int = "probe" "imageLoad"
///|
fn image_bytes_host(max_px : Int) -> Int = "probe" "imageBytes"
///|
fn image_info_host(id : Int) -> Int = "probe" "imageInfo"
///|
fn image_pixels_host(id : Int, capacity : Int) -> Int = "probe" "imagePixels"
///|
fn image_pixel_at(i : Int) -> Int = "probe" "imagePixelAt"
///|
fn image_free_host(id : Int) -> Unit = "probe" "imageFree"
///|
fn host_turn() -> Unit = "probe" "turn"
///|
fn host_view(w : Double, h : Double, scale : Double) -> Unit = "probe" "view"

///|
let host_text : Ref[String] = Ref("")
///|
let host_bytes : Ref[Bytes] = Ref(b"")
///|
let unsupported_pixels : Ref[Bool] = Ref(false)
///|
pub fn bytes_length() -> Int { host_bytes.val.length() }
///|
pub fn bytes_unit(i : Int) -> Int { host_bytes.val[i].to_int() }
///|
fn option(key : Int) -> String {
  let out = StringBuilder()
  for i in 0..<option_length(key) { out.write_char(option_point(key, i).unsafe_to_char()) }
  out.to_string()
}
///|
pub fn text_length() -> Int { host_text.val.length() }
///|
pub fn text_unit(i : Int) -> Int { host_text.val.code_unit_at(i).to_int() }
///|
fn shape_text(text : String, size : Double, weight : Int, style : Int, capacity : Int) -> Int {
  host_text.val = text
  shape_host(size, weight, style, capacity)
}
///|
fn text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  host_text.val = text
  text_key_host(size, weight, style)
}

///|
impl @hostapi.Host for WasmHost with font_metrics(_, size, weight, style, out) {
  metrics(size, weight, style)
  for i in 0..<out.length() { out[i] = result_at(i) }
}
///|
impl @hostapi.Host for WasmHost with shape(_, text, size, weight, style, out) {
  let n = shape_text(text, size, weight, style, out.length())
  for i in 0..<(n * 4) { out[i] = result_at(i) }
  n
}
///|
impl @hostapi.Host for WasmHost with text_key(_, text, size, weight, style) {
  text_key(text, size, weight, style)
}
///|
impl @hostapi.Host for WasmHost with glyph(_, key, out) {
  glyph(key)
  for i in 0..<out.length() { out[i] = result_at(i) }
}
///|
impl @hostapi.Host for WasmHost with glyph_put(_, key, x, y) { glyph_put(key, x, y) }
///|
impl @hostapi.Host for WasmHost with atlas_size(_, colour) { atlas_size(colour) }
///|
impl @hostapi.Host for WasmHost with atlas_generation(_) { atlas_generation() }
///|
impl @hostapi.Host for WasmHost with face_add(_, face, path, weight) {
  host_text.val = path
  face_add_host(face, weight)
}
///|
impl @hostapi.Host for WasmHost with face_add_bytes(_, face, data, weight) {
  host_bytes.val = data
  face_add_bytes_host(face, weight)
}
///|
impl @hostapi.Host for WasmHost with face_add_family(_, face, family) {
  host_text.val = family
  face_add_family_host(face)
}
///|
impl @hostapi.Host for WasmHost with face_clear(_, face) { face_clear_host(face) }
///|
impl @hostapi.Host for WasmHost with image_load(_, src, max_px) {
  host_text.val = src
  image_load_host(max_px)
}
///|
impl @hostapi.Host for WasmHost with image_load_bytes(_, data, max_px) {
  host_bytes.val = data
  image_bytes_host(max_px)
}
///|
impl @hostapi.Host for WasmHost with image_info(_, id, out) {
  let state = image_info_host(id)
  if state == 1 { for i in 0..<out.length() { out[i] = result_at(i) } }
  state
}
///|
impl @hostapi.Host for WasmHost with image_pixels(_, id, out) {
  let n = image_pixels_host(id, out.length())
  if n < 0 { return false }
  for i in 0..<n { out[i] = image_pixel_at(i).to_byte() }
  true
}
///|
impl @hostapi.Host for WasmHost with image_free(_, id) { image_free_host(id) }
///|
impl @hostapi.Host for WasmHost with drawn_pixels(_, _, _, _, _, _) {
  unsupported_pixels.val = true
  false
}
///|
impl @hostapi.Host for WasmHost with drawn_pixels_of(_, _, _, _, _, _, _, _, _, _) {
  unsupported_pixels.val = true
  false
}

///|
let instance_data : Ref[FixedArray[Double]] = Ref(FixedArray::make(0, 0.0))
///|
let ground : Ref[(Double, Double, Double)] = Ref((0.0, 0.0, 0.0))
///|
let current_tester : Ref[@ui.Tester?] = Ref(None)

///|
fn scene_arg(name : String) -> String {
  match name {
    "MBUI_FIXTURE" => option(0)
    "MBUI_DARK" => option(2)
    "MBUI_WINDOW" => option(9)
    "MBUI_HOLD" => option(10)
    "MBUI_FAILED" => option(11)
    "MBUI_FAILED_WHY" => option(12)
    "MBUI_SAID" => option(13)
    "MBUI_UPDATE" => option(14)
    "MBUI_FILM_AUTOFILL" => option(15)
    "MBUI_CORE_MS" => option(16)
    "MBUI_UPDATES_MS" => option(17)
    "MBUI_FIX_PACE" => option(18)
    "MBUI_FIX_CORE" => option(19)
    "MBUI_FIXTURE_JSON" => option(20)
    // (1Password's answers in a scene: the native film's only)
    "MBUI_FILM_OP" => ""
    _ => @halt.saying("picture: unsupported scene option \{name}")
  }
}
///|
pub fn draw() -> Int {
  // (the app as it runs on a host: what faults shown by its boundary, as there, and said on the log)
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { println("fault: " + said) })
  let source = @sffilmscene.source(scene_arg)
  let view = fn(c : @ui.Ctx) { @sfapp.view(c, source()) }
  let t = @ui.Tester::new(view, tree=fn(root : @view.View) { @sfapp.app_tree(source())(root) },
    w=option_number(0), h=option_number(1), scale=option_number(2),
    platform=option_number(3).to_int(), dark=option_number(4) == 1.0,
    pointing?=match option(5) { "finger" => Some(@ui.Pointing::Finger); "mouse" => Some(@ui.Pointing::Mouse); _ => None },
    native?=match option(6) { "finger" => Some(@ui.Pointing::Finger); "mouse" => Some(@ui.Pointing::Mouse); _ => None },
    keyboard?=match option(7) { "1" => Some(true); "0" => Some(false); _ => None },
    env=[("MBUI_TEXT_RECORD", "1"), ("MBUI_LOCALE", option(1)), ("MBUI_DARK", option(2))],
    corners_held=false, words_over_held=false, window_corner=option_number(11), nav_able=option_number(12) == 1.0,
    live={ host: WasmHost::{}, turn: fn() { host_turn() } },
    before=fn() {
      let z = @ui.window_zoom()
      host_view(option_number(0) / z, option_number(1) / z, option_number(2) * z)
    })
  current_tester.val = Some(t)
  t.set_frame_period(1000.0 / option_number(6))
  if option_number(10) == 1.0 { t.set_window_inset(true) }
  if option_number(9) > 0.0 { t.set_font_scale(option_number(9)) }
  if option(8) != "" { t.set_local_station(option(8)) }
  let prepare = option(3)
  let script = option(4)
  let max = option_number(7).to_int()
  if prepare != "" && !drive_passed(t.drive(prepare, max~)) {
    println("picture: scene preparation did not pass")
    return -1
  }
  if script != "" {
    let frame = option_number(8).to_int()
    if frame >= 0 {
      let (reached, logs) = t.film_frame(script, frame, max~)
      for line in logs { if line.has_prefix("DRIVE") { println(line) } }
      if !reached { println("picture: requested frame was not reached"); return -1 }
    } else if !drive_passed(t.drive(script, max~)) {
      println("picture: scene steps did not pass")
      return -1
    }
  } else if prepare == "" && (option_number(10) == 1.0 || option_number(9) > 0.0 || option(8) != "") {
    t.draw()
  }
  if option_number(5) > 0.0 { t.run_for_exact(option_number(5)) }
  if unsupported_pixels.val {
    println("picture: reading back drawn pixels is not supported by the Wasm host")
    return -1
  }
  // Each broken corner is named, so a picture of a known fault (a change's before) is taken by MBUI_FILM_ALLOW_CORNER_FAULTS
  // with the prepared renderer, not a patched and rebuilt one.
  let faults = t.corner_faults()
  for fault in faults { println("picture: \{fault}") }
  if !faults.is_empty() && option_number(13) != 1.0 {
    println("picture: the corner rule is broken (MBUI_FILM_ALLOW_CORNER_FAULTS=1 draws it anyway)")
    return -1
  }
  if !t.pending().is_empty() || !t.failed_images_drawn().is_empty() || !t.holes().is_empty() {
    println("picture: an image is pending or failed, or a native view is visible")
    return -1
  }
  let (values, count, bg) = t.presented()
  for k in 0..<count {
    let pos = k * 60
    if values[pos + 5] == 4.0 {
      match t.live_image(values[pos + 20].to_int()) {
        Some(id) => values[pos + 20] = id.to_double()
        None => return -1
      }
    }
  }
  instance_data.val = values
  ground.val = bg
  count
}
///|
pub fn done() -> Unit {
  match current_tester.val {
    Some(t) => {
      t.end_run(WasmHost::{})
      current_tester.val = None
    }
    None => ()
  }
}
///|
pub fn item(i : Int) -> Double { instance_data.val[i] }
///|
pub fn background(i : Int) -> Double {
  match i { 0 => ground.val.0; 1 => ground.val.1; _ => ground.val.2 }
}

///|
fn drive_passed(logs : Array[String]) -> Bool {
  let mut passed = false
  for line in logs {
    if line.has_prefix("DRIVE") { println(line) }
    if line.has_prefix("DRIVE start:") || line.has_prefix("DRIVE FAIL") || line == "DRIVE END 1" {
      passed = false
    } else if line == "DRIVE PASS" {
      passed = true
    }
  }
  passed
}

///|
fn main { }

///|
/// A film of the scene (MBUI_FILM and the rest of mbui's film arguments, src/film/film.mbt, as the host's environment
/// has them): mbui's own film over this host's text and pictures, drawn and written by the Mac host's renderer and
/// writer (the Node host's). The process ends as the film's run ends it.
pub fn film() -> Unit {
  @hostapi.set_host(WasmHost::{})
  let source = @sffilmscene.source(@film.arg)
  @film.run(fn(c) { @sfapp.view(c, source()) }, tree=fn(root) { @sfapp.app_tree(source())(root) })
}

///|
pub fn film_text_length() -> Int {
  @film.wasm_text_length()
}

///|
pub fn film_text_unit(i : Int) -> Int {
  @film.wasm_text_unit(i)
}

///|
pub fn film_item(i : Int) -> Double {
  @film.wasm_item(i)
}
