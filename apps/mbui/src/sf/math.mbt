// The core's formula placements, drawn with the same alphabet as Android and the web. No TeX is read here.

///|
let math_alphabet : Ref[Json?] = { val: None }

///|
let math_drawings : Map[String, @ui.InlineDrawing] = {}

///|
let math_points : Ref[Int] = Ref(0)

///|
fn init {
  @ui.on_reset(fn() { math_drawings.clear(); math_points.val = 0; math_alphabet.val = None })
}

///|
fn math_field(j : Json, key : String) -> Json {
  match j { Object(m) => m.get(key).unwrap_or(Json::null()); _ => Json::null() }
}

///|
fn math_array(j : Json) -> Array[Json] {
  match j { Array(a) => a; _ => [] }
}

///|
fn math_string(j : Json) -> String {
  match j { String(s) => s; _ => "" }
}

///|
fn math_number(j : Json) -> Double {
  match j { Number(n, ..) => n; _ => 0.0 }
}

///|
fn math_inline(j : Json) -> @ui.InlineDrawing? {
  if math_string(math_field(j, "font")) != "tex-4.1.3" { return None }
  let key = j.stringify()
  if math_drawings.get(key) is Some(d) { return Some(d) }
  let alphabet = match math_alphabet.val {
    Some(j) => j
    None => {
      let j = @json.parse(math_font_json) catch { _ => return None }
      math_alphabet.val = Some(j)
      j
    }
  }
  let glyphs = math_field(alphabet, "glyphs")
  let paths : Array[Array[(Array[Double], Bool)]] = []
  for item in math_array(math_field(j, "draw")) {
    let a = math_array(item)
    if a.length() != 5 { return None }
    let path = math_string(math_field(glyphs, math_string(a[0])))
    if path == "" { return None }
    let sx = math_number(a[1]) / 1000.0
    let sy = math_number(a[2]) / 1000.0
    let x = math_number(a[3]) / 1000.0
    let y = math_number(a[4]) / 1000.0
    // Flatten the packaged curves once; a quarter pixel in 250 px/em gives small glyph curves their full detail.
    paths.push(@pixels.svg_path(path, 0.25).map(fn(p) {
      let pts = p.0.copy()
      let mut i = 0
      while i + 1 < pts.length() {
        pts[i] = pts[i] * sx + x
        pts[i + 1] = pts[i + 1] * sy + y
        i += 2
      }
      (pts, p.1)
    }))
  }
  for item in math_array(math_field(j, "rects")) {
    let a = math_array(item)
    if a.length() != 4 { return None }
    let x = math_number(a[0]) / 1000.0
    let y = math_number(a[1]) / 1000.0
    let w = math_number(a[2]) / 1000.0
    let h = math_number(a[3]) / 1000.0
    paths.push([([x, y, x+w, y, x+w, y+h, x, y+h], true)])
  }
  let words = []
  for item in math_array(math_field(j, "text")) {
    let a = math_array(item)
    if a.length() != 5 { return None }
    words.push((math_string(a[0]), math_number(a[3]) / 1000.0, math_number(a[4]) / 1000.0, math_number(a[1])))
  }
  let d : @ui.InlineDrawing = {
    width: math_number(math_field(j, "width")) / 1000.0,
    height: math_number(math_field(j, "height")) / 1000.0,
    baseline: math_number(math_field(j, "baseline")) / 1000.0,
    paths,
    words,
  }
  let mut points = 0
  for p in paths { for curve in p { points += curve.0.length() } }
  // Bound the expanded geometry too, not just the number of short TeX sources (about 8 MB of doubles).
  if points <= 1000000 {
    if math_points.val + points > 1000000 || math_drawings.length() >= 128 { math_drawings.clear(); math_points.val = 0 }
    math_drawings[key] = d
    math_points.val += points
  }
  Some(d)
}
