// The faces the app's words are set in (@hostapi.face_add): its own words, what people wrote and code each in a face of
// its own, chosen and given here (a file the app has, or fetched), else the system's. A face given (or given up)
// changes how words already shaped measure: what was kept of them is forgotten at once, and they are shaped again
// in it.

///|
/// Which faces are given, 1 to 15 (index 0 unused): only a face given changes a style (style_words is set only with
/// a face for it, so what people wrote stays in the app's words' style, the same text records, until one is).
let faces_given : FixedArray[Bool] = FixedArray::make(@hostapi.faces_most, false)

///|
/// A font file (at `path`) made part of face `face` (@hostapi.face_ui, face_text, face_code, or 4 to 15 for words that
/// name it: Ctx::rich's `face`), for `weight` (0: a variable file, every weight from it). False when the host could not
/// take it (the face as it was). Every word shaped before is shaped again.
pub fn face_add(face : Int, path : String, weight? : Int = 0) -> Bool {
  if face <= 0 || face >= @hostapi.faces_most {
    return false
  }
  let ok = h_face_add(face, path, weight)
  if ok {
    faces_given[face] = true
    words_forgotten()
  }
  ok
}

///|
/// As face_add, the font's file being `data`: one the app carries in itself, or fetched and kept.
pub fn face_add_bytes(face : Int, data : Bytes, weight? : Int = 0) -> Bool {
  if face <= 0 || face >= @hostapi.faces_most {
    return false
  }
  let ok = h_face_add_bytes(face, data, weight)
  if ok {
    faces_given[face] = true
    words_forgotten()
  }
  ok
}

///|
/// Face `face` set in a family installed on this machine (`family`, one of local_font_families'): its every style the
/// system's. False where the host has none of it (the face as it was). Every word shaped before is shaped again.
pub fn face_add_family(face : Int, family : String) -> Bool {
  if face <= 0 || face >= @hostapi.faces_most || family == "" {
    return false
  }
  let ok = h_face_add_family(face, family)
  if ok {
    faces_given[face] = true
    words_forgotten()
  }
  ok
}

///|
/// The font families installed on this machine (@hostapi.local_font_families), a JSON array of their names; "" where
/// there is no way to them. Under a Tester: as it is set (Tester::set_local_fonts).
pub fn local_font_families() -> String {
  match fake.val {
    Some(f) => f.local_fonts
    None => @hostapi.local_font_families()
  }
}

///|
/// Face `face` given up: its words in the system's face again.
pub fn face_clear(face : Int) -> Unit {
  if face <= 0 || face >= @hostapi.faces_most {
    return
  }
  h_face_clear(face)
  if faces_given[face] {
    faces_given[face] = false
    words_forgotten()
  }
}

///|
/// Whether face `face` is given (face_add).
pub fn face_given(face : Int) -> Bool {
  face > 0 && face < @hostapi.faces_most && faces_given[face]
}

///|
/// What words in a paragraph said to be `words` (what people wrote) and in `face` (0: none named) add to each run's
/// style: the face named where it is given; what people wrote marked so where a face is given for it.
fn faces_style(words : Bool, face : Int) -> Int {
  (if face_given(face) { @hostapi.style_face(face) } else { 0 }) |
  (if words && face_given(@hostapi.face_text) { @hostapi.style_words } else { 0 })
}

///|
/// How many times the faces changed: words laid out before (a text's or a paragraph's, its node's layout kept) are laid
/// out again.
let words_shaped_in : Ref[Int] = Ref::new(0)

///|
/// Everything shaped and measured forgotten (its faces changed): shaped again as it is next asked for; the window's
/// tree's words measured and drawn again in them at once (view_words_rescaled), as an old view's are laid out again.
fn words_forgotten() -> Unit {
  words_shaped_in.val += 1
  clear_shapes()
  text_cache.fonts.clear()
  text_cache.metrics.clear()
  glyphs_forget()
  text_cache.generation = -1
  view_words_rescaled()
}

///|
/// As at the start (a Tester's): no face given.
fn faces_reset() -> Unit {
  words_shaped_in.val = 0
  faces_env_read.val = false
  for i in 0..<faces_given.length() {
    faces_given[i] = false
  }
}

///|
/// Whether MBUI_FACES was read (once, as the first frame begins).
let faces_env_read : Ref[Bool] = Ref::new(false)

///|
/// The faces a run is given from outside, as its first frame begins: MBUI_FACES, `face:path` or `face:path:weight`
/// apart by `;` (a host's own check of a face, a screenshot in it). Nothing without it.
fn faces_from_env() -> Unit {
  if faces_env_read.val {
    return
  }
  faces_env_read.val = true
  for item in h_env("MBUI_FACES").split(";") {
    let parts = item.split(":").map(fn(p) { p.to_string() }).collect()
    if parts.length() < 2 {
      continue
    }
    match digits(parts[0]) {
      Some(face) => {
        let weight = if parts.length() > 2 { digits(parts[2]).unwrap_or(0) } else { 0 }
        ignore(face_add(face, parts[1], weight~))
      }
      None => ()
    }
  }
}
