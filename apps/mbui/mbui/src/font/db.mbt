// A font database (fontdb 0.24): faces loaded from font files with their families, style, weight and stretch, and
// CSS's font matching over them (CSS Fonts 3 §5.2, as fontdb does it after font-kit).

///|
pub(all) enum FontStyle {
  Normal
  Italic
  Oblique
} derive(Eq, Show, Debug)

///|
pub(all) struct FaceInfo {
  id : Int
  data : Bytes
  index : Int
  /// (family, is English US)
  families : Array[(String, Bool)]
  post_script_name : String
  style : FontStyle
  weight : Int
  /// usWidthClass, 1 (ultra-condensed) to 9 (ultra-expanded)
  stretch : Int
  monospaced : Bool
}

///|
pub struct FontDb {
  faces : Array[FaceInfo]
  mut serif : String
  mut sans_serif : String
  mut cursive : String
  mut fantasy : String
  mut monospace : String
  /// faces parsed, by id
  parsed : Map[Int, Face]
}

///|
pub fn FontDb::new() -> FontDb {
  {
    faces: [],
    serif: "Times New Roman",
    sans_serif: "Arial",
    cursive: "Comic Sans MS",
    fantasy: "Impact",
    monospace: "Courier New",
    parsed: {},
  }
}

///|
pub fn FontDb::set_serif_family(self : FontDb, f : String) -> Unit {
  self.serif = f
}

///|
pub fn FontDb::set_sans_serif_family(self : FontDb, f : String) -> Unit {
  self.sans_serif = f
}

///|
pub fn FontDb::set_cursive_family(self : FontDb, f : String) -> Unit {
  self.cursive = f
}

///|
pub fn FontDb::set_fantasy_family(self : FontDb, f : String) -> Unit {
  self.fantasy = f
}

///|
pub fn FontDb::set_monospace_family(self : FontDb, f : String) -> Unit {
  self.monospace = f
}

///|
pub fn FontDb::faces(self : FontDb) -> Array[FaceInfo] {
  self.faces
}

///|
/// Adds every face of a font file (one that cannot be read or has no family name is left out).
pub fn FontDb::load_font_data(self : FontDb, data : Bytes) -> Unit {
  let n = face_count(data)
  for i in 0..<n {
    match face_info(data, i, self.faces.length()) {
      Some(info) => self.faces.push(info)
      None => ()
    }
  }
}

///|
pub fn FontDb::face(self : FontDb, id : Int) -> Face? {
  match self.parsed.get(id) {
    Some(f) => Some(f)
    None => {
      if id < 0 || id >= self.faces.length() {
        return None
      }
      let info = self.faces[id]
      match Face::parse(info.data, info.index) {
        Some(f) => {
          self.parsed[id] = f
          Some(f)
        }
        None => None
      }
    }
  }
}

///|
fn face_info(data : Bytes, index : Int, id : Int) -> FaceInfo? {
  let face = match Face::parse(data, index) {
    Some(f) => f
    None => return None
  }
  let names = face.names()
  let is_unicode = fn(r : NameRecord) { r.platform == 0 || r.platform == 3 }
  let is_mac_roman = fn(r : NameRecord) { r.platform == 1 && r.encoding == 0 }
  let is_english_us = fn(r : NameRecord) {
    (r.platform == 3 && r.language == 0x409) || (r.platform == 1 && r.language == 0)
  }
  let collect = fn(name_id : Int) {
    let out : Array[(String, Bool)] = []
    for r in names {
      if r.name_id == name_id && is_unicode(r) {
        out.push((r.text, is_english_us(r)))
      }
    }
    if !out.iter().any(fn(f) { f.1 }) {
      for r in names {
        if r.name_id == name_id && is_mac_roman(r) {
          out.push((r.text, is_english_us(r)))
          break
        }
      }
    }
    out
  }
  let mut families = collect(16)
  if families.is_empty() {
    families = collect(1)
  }
  if families.length() > 1 {
    let mut idx = -1
    for i, f in families {
      if f.1 {
        idx = i
        break
      }
    }
    if idx > 0 {
      let t = families[0]
      families[0] = families[idx]
      families[idx] = t
    }
  }
  if families.is_empty() {
    return None
  }
  let mut post_script_name : String? = None
  for r in names {
    if r.name_id == 6 && (is_unicode(r) || is_mac_roman(r)) {
      post_script_name = Some(r.text)
      break
    }
  }
  let post_script_name = match post_script_name {
    Some(p) => p
    None => return None
  }
  let mut style : FontStyle = Normal
  let mut weight = 400
  let mut stretch = 5
  if face.has_table("OS/2") {
    let sel = face.fs_selection()
    style = if (sel & 1) != 0 {
      Italic
    } else if (sel & 0x200) != 0 {
      Oblique
    } else {
      Normal
    }
    weight = face.weight()
    let w = face.width_class()
    stretch = if w >= 1 && w <= 9 { w } else { 5 }
  }
  let (monospaced, italic) = match face.table("post") {
    Some((o, len)) =>
      if len >= 16 {
        (u32(data, o + 12) != 0, u32(data, o + 4) != 0)
      } else {
        (false, false)
      }
    None => (false, false)
  }
  if style == Normal && italic {
    style = Italic
  }
  Some({ id, data, index, families, post_script_name, style, weight, stretch, monospaced })
}

///|
/// A CSS font family: a name or a generic one.
pub(all) enum Family {
  Named(String)
  Serif
  SansSerif
  Cursive
  Fantasy
  Monospace
} derive(Eq, Show, Debug)

///|
pub fn FontDb::family_name(self : FontDb, f : Family) -> String {
  match f {
    Named(n) => n
    Serif => self.serif
    SansSerif => self.sans_serif
    Cursive => self.cursive
    Fantasy => self.fantasy
    Monospace => self.monospace
  }
}

///|
/// The face that best matches a CSS query (Database::query), None where no family has a face.
pub fn FontDb::query(self : FontDb, families : Array[Family], weight : Int, stretch : Int, style : FontStyle) -> Int? {
  for family in families {
    let name = self.family_name(family)
    let candidates = self.faces.filter(fn(f) { f.families.iter().any(fn(n) { n.0 == name }) })
    if !candidates.is_empty() {
      match find_best_match(candidates, weight, stretch, style) {
        Some(i) => return Some(candidates[i].id)
        None => ()
      }
    }
  }
  None
}

///|
fn find_best_match(c : Array[FaceInfo], weight : Int, stretch : Int, style : FontStyle) -> Int? {
  let mut set = Array::makei(c.length(), fn(i) { i })
  // 4a: font-stretch
  let matching_stretch = if set.iter().any(fn(i) { c[i].stretch == stretch }) {
    stretch
  } else if stretch <= 5 {
    let narrower = set.filter(fn(i) { c[i].stretch < stretch })
    if !narrower.is_empty() {
      c[min_by(narrower, fn(i) { stretch - c[i].stretch })].stretch
    } else {
      c[min_by(set, fn(i) { c[i].stretch - stretch })].stretch
    }
  } else {
    let wider = set.filter(fn(i) { c[i].stretch > stretch })
    if !wider.is_empty() {
      c[min_by(wider, fn(i) { c[i].stretch - stretch })].stretch
    } else {
      c[min_by(set, fn(i) { stretch - c[i].stretch })].stretch
    }
  }
  set = set.filter(fn(i) { c[i].stretch == matching_stretch })
  // 4b: font-style
  let prefs : Array[FontStyle] = match style {
    Italic => [Italic, Oblique, Normal]
    Oblique => [Oblique, Italic, Normal]
    Normal => [Normal, Oblique, Italic]
  }
  let mut matching_style : FontStyle? = None
  for p in prefs {
    if set.iter().any(fn(i) { c[i].style == p }) {
      matching_style = Some(p)
      break
    }
  }
  let matching_style = match matching_style {
    Some(s) => s
    None => return None
  }
  set = set.filter(fn(i) { c[i].style == matching_style })
  // 4c: font-weight
  let w = weight
  let matching_weight = if set.iter().any(fn(i) { c[i].weight == w }) {
    w
  } else if w >= 400 && w < 450 && set.iter().any(fn(i) { c[i].weight == 500 }) {
    500
  } else if w >= 450 && w <= 500 && set.iter().any(fn(i) { c[i].weight == 400 }) {
    400
  } else if w <= 500 {
    let thinner = set.filter(fn(i) { c[i].weight <= w })
    if !thinner.is_empty() {
      c[min_by(thinner, fn(i) { w - c[i].weight })].weight
    } else {
      c[min_by(set, fn(i) { c[i].weight - w })].weight
    }
  } else {
    let fatter = set.filter(fn(i) { c[i].weight >= w })
    if !fatter.is_empty() {
      c[min_by(fatter, fn(i) { c[i].weight - w })].weight
    } else {
      c[min_by(set, fn(i) { w - c[i].weight })].weight
    }
  }
  set = set.filter(fn(i) { c[i].weight == matching_weight })
  set.get(0)
}

///|
/// The first index with the least key (Iterator::min_by_key keeps the first of equals).
fn min_by(set : Array[Int], key : (Int) -> Int) -> Int {
  let mut best = set[0]
  let mut best_key = key(best)
  for i in set {
    let k = key(i)
    if k < best_key {
      best = i
      best_key = k
    }
  }
  best
}
