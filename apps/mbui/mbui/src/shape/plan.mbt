// The shape plan (harfrust's planner.rs, plan.rs, ot/map.rs, tag.rs): which OpenType script and language system
// a run uses, the features the default shaper asks for, each feature's mask bits, and the lookups to apply in
// order, stage by stage.

///|
/// A feature asked for: `value` from cluster `start` to `end` (-1: to the end); global when it covers all.
pub(all) struct Feature {
  tag : Int
  value : Int
  start : Int
  end : Int
}

///|
pub fn Feature::new(name : String, value : Int) -> Feature {
  { tag: tag(name), value, start: 0, end: -1 }
}

///|
fn Feature::is_global(self : Feature) -> Bool {
  self.start == 0 && self.end == -1
}

///|
const F_GLOBAL : Int = 0x0001

///|
const F_HAS_FALLBACK : Int = 0x0002

///|
const F_MANUAL_ZWNJ : Int = 0x0004

///|
const F_MANUAL_ZWJ : Int = 0x0008

///|
const F_GLOBAL_SEARCH : Int = 0x0010

///|
const F_RANDOM : Int = 0x0020

///|
const F_PER_SYLLABLE : Int = 0x0040

///|
const MAX_VALUE : Int = 255

///|
const GLOBAL_BIT_SHIFT : Int = 31

///|
let global_bit_mask : Int = 1 << 31

///|
priv struct FeatureInfo {
  tag : Int
  seq : Int
  mut max_value : Int
  mut flags : Int
  mut default_value : Int
  stage : Array[Int]
}

///|
priv struct FeatureMap {
  tag : Int
  index : Array[Int]
  stage : Array[Int]
  shift : Int
  mask : Int
  one_mask : Int
  needs_fallback : Bool
  auto_zwnj : Bool
  auto_zwj : Bool
  random : Bool
  per_syllable : Bool
}

///|
priv struct LookupMap {
  index : Int
  auto_zwnj : Bool
  auto_zwj : Bool
  random : Bool
  mask : Int
  per_syllable : Bool
}

///|
pub struct ShapePlan {
  direction : Direction
  script : Int
  priv ot : OtData
  priv features : Array[FeatureMap]
  priv global_mask : Int
  /// GSUB's and GPOS's lookups, and where each stage's end
  priv lookups : Array[Array[LookupMap]]
  priv stages : Array[Array[Int]]
  priv frac_mask : Int
  priv numr_mask : Int
  priv dnom_mask : Int
  priv rtlm_mask : Int
  priv kern_mask : Int
  priv requested_kerning : Bool
  priv has_frac : Bool
  priv has_vert : Bool
  priv zero_marks : Bool
  priv fallback_glyph_classes : Bool
  priv fallback_mark_positioning : Bool
  priv adjust_mark_positioning_when_zeroing : Bool
  priv apply_gpos : Bool
  priv apply_kern : Bool
  priv user_features : Array[Feature]
}

///|
fn ShapePlan::get_1_mask(self : ShapePlan, t : Int) -> Int {
  for f in self.features {
    if f.tag == t {
      return f.one_mask
    }
  }
  0
}

///|
fn ShapePlan::get_mask(self : ShapePlan, t : Int) -> (Int, Int) {
  for f in self.features {
    if f.tag == t {
      return (f.mask, f.shift)
    }
  }
  (0, 0)
}

///|
fn ShapePlan::feature_index(self : ShapePlan, table : Int, t : Int) -> Int {
  for f in self.features {
    if f.tag == t {
      return f.index[table]
    }
  }
  -1
}

///|
/// The OpenType script tags for a Unicode script, most preferred first.
fn script_tags(script : Int) -> Array[Int] {
  if script == 0 {
    return []
  }
  let tags = []
  let new_tag = match script {
    0x42656E67 => tag("bng2") // Beng
    0x44657661 => tag("dev2") // Deva
    0x47756A72 => tag("gjr2") // Gujr
    0x47757275 => tag("gur2") // Guru
    0x4B6E6461 => tag("knd2") // Knda
    0x4D6C796D => tag("mlm2") // Mlym
    0x4F727961 => tag("ory2") // Orya
    0x54616D6C => tag("tml2") // Taml
    0x54656C75 => tag("tel2") // Telu
    0x4D796D72 => tag("mym2") // Mymr
    _ => 0
  }
  if new_tag != 0 {
    if new_tag != tag("mym2") {
      tags.push((new_tag & 0xFFFFFF00) | 0x33)
    }
    tags.push(new_tag)
  }
  let old = match script {
    0x5A6D7468 => tag("math") // Zmth
    0x48697261 => tag("kana") // Hira
    0x4C616F6F => tag("lao ")
    0x59696969 => tag("yi  ")
    0x4E6B6F6F => tag("nko ")
    0x56616969 => tag("vai ")
    _ => script | 0x20000000
  }
  tags.push(old)
  tags
}

///|
fn ShapePlan::new(ot : OtData, direction : Direction, script : Int, user_features : Array[Feature]) -> ShapePlan {
  let d = ot.data
  let tables = [ot.gsub, ot.gpos]
  let script_tags = script_tags(script)
  let script_index = [-1, -1]
  let lang_index = [-1, -1]
  let chosen_script = [0, 0]
  for ti in 0..<2 {
    guard tables[ti] is Some(table) else { continue }
    match table.select_script(d, script_tags) {
      Some((idx, _found, t)) => {
        script_index[ti] = idx
        chosen_script[ti] = t
        lang_index[ti] = table.select_language(d, idx, [])
      }
      None => ()
    }
  }
  // collect_features (the default shaper adds none of its own)
  let infos : Array[FeatureInfo] = []
  let current_stage = [0, 0]
  let pauses : Array[Array[Int]] = [[], []]
  let add = fn(t : Int, flags : Int, value : Int) {
    infos.push({
      tag: t,
      seq: infos.length(),
      max_value: value,
      flags,
      default_value: if (flags & F_GLOBAL) != 0 { value } else { 0 },
      stage: [current_stage[0], current_stage[1]],
    })
  }
  let enable = fn(t : Int, flags : Int, value : Int) { add(t, flags | F_GLOBAL, value) }
  let add_pause = fn(ti : Int) {
    pauses[ti].push(current_stage[ti])
    current_stage[ti] += 1
  }
  enable(tag("rvrn"), 0, 1)
  add_pause(0)
  match direction {
    LeftToRight => {
      enable(tag("ltra"), 0, 1)
      enable(tag("ltrm"), 0, 1)
    }
    RightToLeft => {
      enable(tag("rtla"), 0, 1)
      add(tag("rtlm"), 0, 1)
    }
    _ => ()
  }
  add(tag("frac"), 0, 1)
  add(tag("numr"), 0, 1)
  add(tag("dnom"), 0, 1)
  enable(tag("rand"), F_RANDOM, MAX_VALUE)
  enable(tag("trak"), F_HAS_FALLBACK, 1)
  enable(tag("Harf"), 0, 1)
  enable(tag("HARF"), 0, 1)
  enable(tag("Buzz"), 0, 1)
  enable(tag("BUZZ"), 0, 1)
  for t in ["abvm", "blwm", "ccmp", "locl"] {
    add(tag(t), F_GLOBAL, 1)
  }
  add(tag("mark"), F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ, 1)
  add(tag("mkmk"), F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ, 1)
  add(tag("rlig"), F_GLOBAL, 1)
  if direction.is_horizontal() {
    for t in ["calt", "clig", "curs", "dist"] {
      add(tag(t), F_GLOBAL, 1)
    }
    add(tag("kern"), F_GLOBAL | F_HAS_FALLBACK, 1)
    for t in ["liga", "rclt"] {
      add(tag(t), F_GLOBAL, 1)
    }
  } else {
    enable(tag("vert"), F_GLOBAL_SEARCH, 1)
  }
  for f in user_features {
    add(f.tag, if f.is_global() { F_GLOBAL } else { 0 }, f.value)
  }
  // compile: the required feature
  let required_index = [-1, -1]
  let required_tag = [0, 0]
  for ti in 0..<2 {
    guard tables[ti] is Some(table) else { continue }
    if script_index[ti] >= 0 {
      let idx = table.required_feature(d, script_index[ti], lang_index[ti])
      if idx >= 0 {
        required_index[ti] = idx
        required_tag[ti] = table.feature_tag(d, idx)
      }
    }
  }
  // dedup_feature_infos: by tag, then in the order they came
  infos.sort_by(fn(a, b) {
    let c = a.tag.reinterpret_as_uint().compare(b.tag.reinterpret_as_uint())
    if c != 0 {
      c
    } else {
      a.seq.compare(b.seq)
    }
  })
  let deduped : Array[FeatureInfo] = []
  for info in infos {
    if deduped.length() == 0 || deduped[deduped.length() - 1].tag != info.tag {
      deduped.push({ ..info, stage: [info.stage[0], info.stage[1]] })
      continue
    }
    let j = deduped[deduped.length() - 1]
    if (info.flags & F_GLOBAL) != 0 {
      j.flags = j.flags | F_GLOBAL
      j.max_value = info.max_value
      j.default_value = info.default_value
    } else {
      if (j.flags & F_GLOBAL) != 0 {
        j.flags = j.flags ^ F_GLOBAL
      }
      if info.max_value > j.max_value {
        j.max_value = info.max_value
      }
    }
    j.flags = j.flags | (info.flags & F_HAS_FALLBACK)
    if info.stage[0] < j.stage[0] {
      j.stage[0] = info.stage[0]
    }
    if info.stage[1] < j.stage[1] {
      j.stage[1] = info.stage[1]
    }
  }
  // collect_feature_maps
  let features : Array[FeatureMap] = []
  let required_stage = [0, 0]
  let mut global_mask = global_bit_mask
  let mut next_bit = 4
  for info in deduped {
    let bits_needed = if (info.flags & F_GLOBAL) != 0 && info.max_value == 1 {
      0
    } else {
      let num_bits = 32 - info.max_value.clz()
      if num_bits < 8 {
        num_bits
      } else {
        8
      }
    }
    if info.max_value == 0 || next_bit + bits_needed >= GLOBAL_BIT_SHIFT {
      continue
    }
    let mut found = false
    let feature_index = [-1, -1]
    for ti in 0..<2 {
      guard tables[ti] is Some(table) else { continue }
      if required_tag[ti] == info.tag {
        required_stage[ti] = info.stage[ti]
      }
      if script_index[ti] >= 0 {
        let idx = table.find_feature(d, script_index[ti], lang_index[ti], info.tag)
        if idx >= 0 {
          feature_index[ti] = idx
          found = true
        }
      }
    }
    if !found && (info.flags & F_GLOBAL_SEARCH) != 0 {
      for ti in 0..<2 {
        guard tables[ti] is Some(table) else { continue }
        let idx = table.feature_index(d, info.tag)
        if idx >= 0 {
          feature_index[ti] = idx
          found = true
        }
      }
    }
    if !found && (info.flags & F_HAS_FALLBACK) == 0 {
      continue
    }
    let (shift, mask) = if (info.flags & F_GLOBAL) != 0 && info.max_value == 1 {
      (GLOBAL_BIT_SHIFT, global_bit_mask)
    } else {
      let shift = next_bit
      let mask = (1 << (next_bit + bits_needed)) - (1 << next_bit)
      next_bit += bits_needed
      global_mask = global_mask | ((info.default_value << shift) & mask)
      (shift, mask)
    }
    features.push({
      tag: info.tag,
      index: feature_index,
      stage: info.stage,
      shift,
      mask,
      one_mask: (1 << shift) & mask,
      needs_fallback: !found,
      auto_zwnj: (info.flags & F_MANUAL_ZWNJ) == 0,
      auto_zwj: (info.flags & F_MANUAL_ZWJ) == 0,
      random: (info.flags & F_RANDOM) != 0,
      per_syllable: (info.flags & F_PER_SYLLABLE) != 0,
    })
  }
  add_pause(0)
  add_pause(1)
  // collect_lookup_stages
  let lookups : Array[Array[LookupMap]] = [[], []]
  let stages : Array[Array[Int]] = [[], []]
  for ti in 0..<2 {
    let mut stage_index = 0
    let mut last_lookup = 0
    for stage in 0..<current_stage[ti] {
      let list = lookups[ti]
      let add_lookups = fn(feature_index : Int, mask : Int, auto_zwnj : Bool, auto_zwj : Bool, random : Bool, per_syllable : Bool) {
        guard tables[ti] is Some(table) else { return }
        for index in table.feature_lookups(d, feature_index) {
          if index < table.lookup_count() {
            list.push({ index, auto_zwnj, auto_zwj, random, mask, per_syllable })
          }
        }
      }
      if required_index[ti] >= 0 && required_stage[ti] == stage {
        add_lookups(required_index[ti], global_bit_mask, true, true, false, false)
      }
      for f in features {
        if f.index[ti] >= 0 && f.stage[ti] == stage {
          add_lookups(f.index[ti], f.mask, f.auto_zwnj, f.auto_zwj, f.random, f.per_syllable)
        }
      }
      if last_lookup + 1 < list.length() {
        let tail = list[last_lookup:].to_array()
        tail.sort_by(fn(a, b) {
          let c = a.index.compare(b.index)
          if c != 0 {
            return c
          }
          let c = a.auto_zwnj.compare(b.auto_zwnj)
          if c != 0 {
            return c
          }
          let c = a.auto_zwj.compare(b.auto_zwj)
          if c != 0 {
            return c
          }
          let c = a.random.compare(b.random)
          if c != 0 {
            return c
          }
          let c = a.mask.reinterpret_as_uint().compare(b.mask.reinterpret_as_uint())
          if c != 0 {
            return c
          }
          a.per_syllable.compare(b.per_syllable)
        })
        while list.length() > last_lookup {
          ignore(list.pop())
        }
        for l in tail {
          if list.length() > last_lookup && list[list.length() - 1].index == l.index {
            let j = list[list.length() - 1]
            list[list.length() - 1] = {
              index: j.index,
              auto_zwnj: j.auto_zwnj && l.auto_zwnj,
              auto_zwj: j.auto_zwj && l.auto_zwj,
              random: j.random,
              mask: j.mask | l.mask,
              per_syllable: j.per_syllable,
            }
          } else {
            list.push(l)
          }
        }
      }
      last_lookup = list.length()
      if stage_index < pauses[ti].length() && pauses[ti][stage_index] == stage {
        stages[ti].push(last_lookup)
        stage_index += 1
      }
    }
  }
  let ot_get_1 = fn(t : String) -> Int {
    for f in features {
      if f.tag == tag(t) {
        return f.one_mask
      }
    }
    0
  }
  let frac_mask = ot_get_1("frac")
  let numr_mask = ot_get_1("numr")
  let dnom_mask = ot_get_1("dnom")
  let horizontal = direction.is_horizontal()
  let kern_tag = if horizontal { tag("kern") } else { tag("vkrn") }
  let mut kern_mask = 0
  let mut has_gpos_kern = false
  for f in features {
    if f.tag == kern_tag {
      kern_mask = f.mask
      has_gpos_kern = f.index[1] >= 0
    }
  }
  let has_gpos = ot.gpos is Some(_)
  let apply_gpos = has_gpos
  // the old `kern` table, when GPOS does not kern (the default shaper positions as a fallback)
  let has_kern_table = ot.has_kern
  let apply_kern = (!has_gpos_kern || !apply_gpos) && has_kern_table
  let adjust = !apply_gpos
  {
    direction,
    script,
    ot,
    features,
    global_mask,
    lookups,
    stages,
    frac_mask,
    numr_mask,
    dnom_mask,
    rtlm_mask: ot_get_1("rtlm"),
    kern_mask,
    requested_kerning: kern_mask != 0,
    has_frac: frac_mask != 0 || (numr_mask != 0 && dnom_mask != 0),
    has_vert: ot_get_1("vert") != 0,
    zero_marks: true,
    fallback_glyph_classes: !ot.has_glyph_classes(),
    fallback_mark_positioning: adjust,
    adjust_mark_positioning_when_zeroing: adjust,
    apply_gpos,
    apply_kern,
    user_features,
  }
}

///|
/// Applies GSUB's or GPOS's lookups, stage by stage.
fn ShapePlan::apply_layout_table(self : ShapePlan, buffer : Buffer, is_gsub : Bool) -> Unit {
  let ti = if is_gsub { 0 } else { 1 }
  guard self.ot.table(is_gsub) is Some(table) else { return }
  let ctx = ApplyContext::new(is_gsub, self.ot, buffer)
  let mut start = 0
  for end in self.stages[ti] {
    for k in start..<end {
      let lm = self.lookups[ti][k]
      guard table.lookup(self.ot.data, lm.index) is Some(lookup) else { continue }
      ctx.lookup_index = lm.index
      ctx.set_lookup_mask(lm.mask)
      ctx.auto_zwj = lm.auto_zwj
      ctx.auto_zwnj = lm.auto_zwnj
      ctx.random = lm.random
      ctx.per_syllable = lm.per_syllable
      apply_string(ctx, lookup)
    }
    start = end
  }
}
