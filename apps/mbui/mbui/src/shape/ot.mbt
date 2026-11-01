// The OpenType layout tables as harfrust reads them (ot/mod.rs, ot/lookup/coverage.rs, ot/lookup/build.rs): GDEF's
// glyph classes, GSUB's and GPOS's script, feature and lookup lists, coverage and class definitions. Everything is
// read in place from the font's bytes; offsets here are from the start of the font file.

///|
fn rd8(d : Bytes, i : Int) -> Int {
  if i < 0 || i >= d.length() {
    0
  } else {
    d[i].to_int()
  }
}

///|
fn rd16(d : Bytes, i : Int) -> Int {
  if i < 0 || i + 2 > d.length() {
    0
  } else {
    (d[i].to_int() << 8) | d[i + 1].to_int()
  }
}

///|
fn rds16(d : Bytes, i : Int) -> Int {
  let v = rd16(d, i)
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn rd24(d : Bytes, i : Int) -> Int {
  (rd8(d, i) << 16) | (rd8(d, i + 1) << 8) | rd8(d, i + 2)
}

///|
fn rd32(d : Bytes, i : Int) -> Int {
  (rd16(d, i) << 16) | rd16(d, i + 2)
}

///|
/// An offset at `at` from `base`, or 0 when it is null.
fn off16(d : Bytes, base : Int, at : Int) -> Int {
  let o = rd16(d, at)
  if o == 0 {
    0
  } else {
    base + o
  }
}

///|
/// The coverage index of `glyph` in the coverage table at `cov`, or -1.
fn coverage_get(d : Bytes, cov : Int, glyph : Int) -> Int {
  if cov == 0 {
    return -1
  }
  match rd16(d, cov) {
    1 => {
      let count = rd16(d, cov + 2)
      let mut lo = 0
      let mut hi = count
      while lo < hi {
        let mid = (lo + hi) / 2
        let g = rd16(d, cov + 4 + mid * 2)
        if g < glyph {
          lo = mid + 1
        } else if g > glyph {
          hi = mid
        } else {
          return mid
        }
      }
      -1
    }
    2 => {
      let count = rd16(d, cov + 2)
      let mut lo = 0
      let mut hi = count
      while lo < hi {
        let mid = (lo + hi) / 2
        let r = cov + 4 + mid * 6
        let start = rd16(d, r)
        let end = rd16(d, r + 2)
        if end < glyph {
          lo = mid + 1
        } else if start > glyph {
          hi = mid
        } else {
          return rd16(d, r + 4) + glyph - start
        }
      }
      -1
    }
    _ => -1
  }
}

///|
/// The class of `glyph` in the class definition at `cd` (0 when it has none).
fn class_get(d : Bytes, cd : Int, glyph : Int) -> Int {
  if cd == 0 {
    return 0
  }
  match rd16(d, cd) {
    1 => {
      let start = rd16(d, cd + 2)
      let count = rd16(d, cd + 4)
      let i = glyph - start
      if i >= 0 && i < count {
        rd16(d, cd + 6 + i * 2)
      } else {
        0
      }
    }
    2 => {
      let count = rd16(d, cd + 2)
      let mut lo = 0
      let mut hi = count
      while lo < hi {
        let mid = (lo + hi) / 2
        let r = cd + 4 + mid * 6
        let start = rd16(d, r)
        let end = rd16(d, r + 2)
        if end < glyph {
          lo = mid + 1
        } else if start > glyph {
          hi = mid
        } else {
          return rd16(d, r + 4)
        }
      }
      0
    }
    _ => 0
  }
}

// lookup flags

///|
const LOOKUP_RIGHT_TO_LEFT : Int = 0x0001

///|
const LOOKUP_IGNORE_MARKS : Int = 0x0008

///|
const LOOKUP_IGNORE_FLAGS : Int = 0x000E

///|
const LOOKUP_USE_MARK_FILTERING_SET : Int = 0x0010

///|
const LOOKUP_MARK_ATTACHMENT_TYPE_MASK : Int = 0xFF00

///|
priv struct Lookup {
  kind : Int
  props : Int
  /// each subtable's offset, through extension subtables
  subtables : Array[Int]
  is_reverse : Bool
}

///|
priv struct LayoutTable {
  is_gsub : Bool
  script_list : Int
  feature_list : Int
  lookup_list : Int
  lookups : Array[Lookup?]
  built : Array[Bool]
}

///|
fn LayoutTable::parse(d : Bytes, at : Int, is_gsub : Bool) -> LayoutTable? {
  if at <= 0 || rd16(d, at) != 1 {
    return None
  }
  let lookup_list = off16(d, at, at + 8)
  let count = if lookup_list == 0 { 0 } else { rd16(d, lookup_list) }
  Some({
    is_gsub,
    script_list: off16(d, at, at + 4),
    feature_list: off16(d, at, at + 6),
    lookup_list,
    lookups: Array::make(count, None),
    built: Array::make(count, false),
  })
}

///|
fn LayoutTable::lookup_count(self : LayoutTable) -> Int {
  self.lookups.length()
}

///|
fn LayoutTable::lookup(self : LayoutTable, d : Bytes, index : Int) -> Lookup? {
  if index < 0 || index >= self.lookups.length() {
    return None
  }
  if !self.built[index] {
    self.built[index] = true
    self.lookups[index] = build_lookup(d, self.lookup_list, index, self.is_gsub)
  }
  self.lookups[index]
}

///|
fn build_lookup(d : Bytes, list : Int, index : Int, is_gsub : Bool) -> Lookup? {
  let at = off16(d, list, list + 2 + index * 2)
  if at == 0 {
    return None
  }
  let mut kind = rd16(d, at)
  let flag = rd16(d, at + 2)
  let count = rd16(d, at + 4)
  let mut props = flag
  if (flag & LOOKUP_USE_MARK_FILTERING_SET) != 0 {
    props = props | (rd16(d, at + 6 + count * 2) << 16)
  }
  let ext = if is_gsub { 7 } else { 9 }
  let subtables = []
  let mut ext_kind = 0
  for i in 0..<count {
    let s = off16(d, at, at + 6 + i * 2)
    if s == 0 {
      continue
    }
    if kind == ext {
      if rd16(d, s) != 1 {
        continue
      }
      let k = rd16(d, s + 2)
      if k == ext {
        continue
      }
      if ext_kind == 0 {
        ext_kind = k
      }
      subtables.push(s + rd32(d, s + 4))
    } else {
      subtables.push(s)
    }
  }
  if kind == ext {
    kind = ext_kind
  }
  Some({ kind, props, subtables, is_reverse: is_gsub && kind == 8 })
}

///|
/// The script's index among the script list's records, for the first of `tags` it has, else DFLT, dflt or latn
/// (the second of the answer says it was one of those).
fn LayoutTable::select_script(self : LayoutTable, d : Bytes, tags : Array[Int]) -> (Int, Bool, Int)? {
  let list = self.script_list
  if list == 0 {
    return None
  }
  let count = rd16(d, list)
  let find = fn(t : Int) -> Int {
    let mut lo = 0
    let mut hi = count
    while lo < hi {
      let mid = (lo + hi) / 2
      let v = rd32(d, list + 2 + mid * 6)
      if v.reinterpret_as_uint() < t.reinterpret_as_uint() {
        lo = mid + 1
      } else if v.reinterpret_as_uint() > t.reinterpret_as_uint() {
        hi = mid
      } else {
        return mid
      }
    }
    -1
  }
  for t in tags {
    let i = find(t)
    if i >= 0 {
      return Some((i, true, t))
    }
  }
  for t in [tag("DFLT"), tag("dflt"), tag("latn")] {
    let i = find(t)
    if i >= 0 {
      return Some((i, false, t))
    }
  }
  None
}

///|
fn LayoutTable::script(self : LayoutTable, d : Bytes, index : Int) -> Int {
  off16(d, self.script_list, self.script_list + 2 + index * 6 + 4)
}

///|
/// The language system `lang` (an index among the script's records, or -1 for its default).
fn LayoutTable::langsys(self : LayoutTable, d : Bytes, script : Int, lang : Int) -> Int {
  let s = self.script(d, script)
  if s == 0 {
    return 0
  }
  if lang < 0 {
    off16(d, s, s)
  } else {
    off16(d, s, s + 4 + lang * 6 + 4)
  }
}

///|
fn LayoutTable::select_language(self : LayoutTable, d : Bytes, script : Int, tags : Array[Int]) -> Int {
  let s = self.script(d, script)
  if s == 0 {
    return -1
  }
  let count = rd16(d, s + 2)
  let find = fn(t : Int) -> Int {
    let mut lo = 0
    let mut hi = count
    while lo < hi {
      let mid = (lo + hi) / 2
      let v = rd32(d, s + 4 + mid * 6)
      if v.reinterpret_as_uint() < t.reinterpret_as_uint() {
        lo = mid + 1
      } else if v.reinterpret_as_uint() > t.reinterpret_as_uint() {
        hi = mid
      } else {
        return mid
      }
    }
    -1
  }
  for t in tags {
    let i = find(t)
    if i >= 0 {
      return i
    }
  }
  find(tag("dflt"))
}

///|
fn LayoutTable::feature_tag(self : LayoutTable, d : Bytes, index : Int) -> Int {
  rd32(d, self.feature_list + 2 + index * 6)
}

///|
fn LayoutTable::required_feature(self : LayoutTable, d : Bytes, script : Int, lang : Int) -> Int {
  let ls = self.langsys(d, script, lang)
  if ls == 0 {
    return -1
  }
  let idx = rd16(d, ls + 2)
  if idx == 0xFFFF {
    -1
  } else {
    idx
  }
}

///|
fn LayoutTable::find_feature(self : LayoutTable, d : Bytes, script : Int, lang : Int, t : Int) -> Int {
  let ls = self.langsys(d, script, lang)
  if ls == 0 || self.feature_list == 0 {
    return -1
  }
  let fcount = rd16(d, self.feature_list)
  let count = rd16(d, ls + 4)
  for i in 0..<count {
    let fi = rd16(d, ls + 6 + i * 2)
    if fi < fcount && self.feature_tag(d, fi) == t {
      return fi
    }
  }
  -1
}

///|
fn LayoutTable::feature_index(self : LayoutTable, d : Bytes, t : Int) -> Int {
  if self.feature_list == 0 {
    return -1
  }
  for i in 0..<rd16(d, self.feature_list) {
    if self.feature_tag(d, i) == t {
      return i
    }
  }
  -1
}

///|
fn LayoutTable::feature_lookups(self : LayoutTable, d : Bytes, index : Int) -> Array[Int] {
  let f = off16(d, self.feature_list, self.feature_list + 2 + index * 6 + 4)
  if f == 0 {
    return []
  }
  let count = rd16(d, f + 2)
  Array::makei(count, fn(i) { rd16(d, f + 4 + i * 2) })
}

///|
/// The font's layout data: GDEF's classes and the two tables.
priv struct OtData {
  data : Bytes
  glyph_classes : Int
  mark_classes : Int
  mark_sets : Array[Int]
  gsub : LayoutTable?
  gpos : LayoutTable?
  has_kern : Bool
}

///|
fn OtData::new(face : @font.Face) -> OtData {
  let d = face.data()
  let at = fn(t : String) -> Int {
    match face.table(t) {
      Some((o, _)) => o
      None => 0
    }
  }
  let gdef = at("GDEF")
  let mut glyph_classes = 0
  let mut mark_classes = 0
  let mark_sets = []
  if gdef != 0 && rd16(d, gdef) == 1 {
    glyph_classes = off16(d, gdef, gdef + 4)
    mark_classes = off16(d, gdef, gdef + 10)
    if rd16(d, gdef + 2) >= 2 {
      let sets = off16(d, gdef, gdef + 12)
      if sets != 0 && rd16(d, sets) == 1 {
        for i in 0..<rd16(d, sets + 2) {
          mark_sets.push(sets + rd32(d, sets + 4 + i * 4))
        }
      }
    }
  }
  {
    data: d,
    glyph_classes,
    mark_classes,
    mark_sets,
    gsub: LayoutTable::parse(d, at("GSUB"), true),
    gpos: LayoutTable::parse(d, at("GPOS"), false),
    has_kern: at("kern") != 0,
  }
}

///|
fn OtData::table(self : OtData, is_gsub : Bool) -> LayoutTable? {
  if is_gsub {
    self.gsub
  } else {
    self.gpos
  }
}

///|
fn OtData::has_glyph_classes(self : OtData) -> Bool {
  self.glyph_classes != 0
}

///|
fn OtData::glyph_props(self : OtData, glyph : Int) -> Int {
  match class_get(self.data, self.glyph_classes, glyph) {
    1 => GPROPS_BASE_GLYPH
    2 => GPROPS_LIGATURE
    3 => ((class_get(self.data, self.mark_classes, glyph) & 0xFF) << 8) | GPROPS_MARK
    _ => 0
  }
}

///|
fn OtData::is_mark_glyph(self : OtData, glyph : Int, set : Int) -> Bool {
  set < self.mark_sets.length() && coverage_get(self.data, self.mark_sets[set], glyph) >= 0
}

///|
/// An anchor's coordinates (formats 1 to 3: without hinting and variations the same).
fn OtData::anchor(self : OtData, at : Int) -> (Int, Int) {
  (rds16(self.data, at + 2), rds16(self.data, at + 4))
}
