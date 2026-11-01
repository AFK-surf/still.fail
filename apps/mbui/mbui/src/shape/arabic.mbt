// The Arabic shaper (harfrust's ot/shaper/arabic.rs): each letter's joining form found by the joining state
// machine and given its feature's mask (isol, fina, medi, init and Syriac's), the features in their stages, and
// modifier combining marks moved first.

///|
const SHAPER_DEFAULT : Int = 0

///|
const SHAPER_ARABIC : Int = 1

///|
let arabic_features : Array[String] = ["isol", "fina", "fin2", "fin3", "medi", "med2", "init"]

///|
const ARABIC_NONE : Int = 7

///|
/// The state machine: for each state and joining type, the action for the previous letter, the action for this
/// one, and the next state.
let arabic_state_table : Array[Array[(Int, Int, Int)]] = [
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 0, 1), (7, 0, 6)],
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 2, 5), (7, 0, 6)],
  [(7, 7, 0), (7, 0, 2), (6, 1, 1), (6, 1, 3), (6, 1, 4), (6, 1, 6)],
  [(7, 7, 0), (7, 0, 2), (4, 1, 1), (4, 1, 3), (4, 1, 4), (4, 1, 6)],
  [(7, 7, 0), (7, 0, 2), (5, 0, 1), (5, 0, 2), (5, 2, 5), (5, 0, 6)],
  [(7, 7, 0), (7, 0, 2), (0, 0, 1), (0, 0, 2), (0, 2, 5), (0, 0, 6)],
  [(7, 7, 0), (7, 0, 2), (7, 0, 1), (7, 0, 2), (7, 3, 5), (7, 0, 6)],
]

///|
fn arabic_joining_type(u : Int, gc : Int) -> Int {
  let t = arabic_joining_type_raw(u)
  if t != 7 {
    return t
  }
  if gc == GC_NON_SPACING_MARK || gc == GC_ENCLOSING_MARK || gc == GC_FORMAT {
    6
  } else {
    0
  }
}

///|
fn feature_is_syriac(t : String) -> Bool {
  let last = t.code_unit_at(3).to_int()
  last == 0x32 || last == 0x33
}

///|
/// Which shaper a script gets (ot/shaper/mod.rs categorize; the shapers not ported yet are the default one).
fn categorize(script : Int, direction : Direction, gsub_script : Int) -> Int {
  if script == tag("Arab") || script == tag("Syrc") {
    if (gsub_script != tag("DFLT") || script == tag("Arab")) && direction.is_horizontal() {
      SHAPER_ARABIC
    } else {
      SHAPER_DEFAULT
    }
  } else if ["Beng", "Deva", "Gujr", "Guru", "Knda", "Mlym", "Orya", "Taml", "Telu"].iter().any(fn(t) { tag(t) == script }) {
    // the Universal Shaping Engine's (for a font with the '3' tags) is not ported: these get the Indic shaper
    if gsub_script == tag("DFLT") || gsub_script == tag("latn") {
      SHAPER_DEFAULT
    } else {
      SHAPER_INDIC
    }
  } else {
    SHAPER_DEFAULT
  }
}

///|
fn arabic_joining(buffer : Buffer) -> Unit {
  let mut prev = -1
  let mut state = 0
  for i in 0..<buffer.len {
    let info = buffer.info[i]
    let this_type = arabic_joining_type(info.glyph_id, info.general_category())
    if this_type == 6 {
      info.set_shaper_auxiliary(ARABIC_NONE)
      continue
    }
    let (prev_action, this_action, next_state) = arabic_state_table[state][this_type]
    if prev_action != ARABIC_NONE && prev >= 0 {
      buffer.info[prev].set_shaper_auxiliary(prev_action)
    }
    info.set_shaper_auxiliary(this_action)
    prev = i
    state = next_state
  }
}

///|
fn arabic_setup_masks(plan : ShapePlan, buffer : Buffer) -> Unit {
  arabic_joining(buffer)
  if plan.script == tag("Mong") {
    for i in 1..<buffer.len {
      let u = buffer.info[i].glyph_id
      if (u >= 0x180B && u <= 0x180D) || u == 0x180F {
        buffer.info[i].set_shaper_auxiliary(buffer.info[i - 1].shaper_auxiliary())
      }
    }
  }
  for i in 0..<buffer.len {
    let info = buffer.info[i]
    info.mask = info.mask | plan.arabic_masks[info.shaper_auxiliary()]
  }
}

///|
let modifier_combining_marks : Array[Int] = [
  0x0654, 0x0655, 0x0658, 0x06DC, 0x06E3, 0x06E7, 0x06E8, 0x08CA, 0x08CB, 0x08CD, 0x08CE, 0x08CF, 0x08D3, 0x08F3,
]

///|
fn arabic_reorder_marks(buffer : Buffer, start : Int, end : Int) -> Unit {
  let mut start = start
  let mut i = start
  for cc in [220, 230] {
    while i < end && buffer.info[i].modified_combining_class() < cc {
      i += 1
    }
    if i == end {
      break
    }
    if buffer.info[i].modified_combining_class() > cc {
      continue
    }
    let mut j = i
    while j < end {
      let info = buffer.info[j]
      if info.modified_combining_class() != cc || !modifier_combining_marks.contains(info.glyph_id) {
        break
      }
      j += 1
    }
    if i == j {
      continue
    }
    buffer.merge_clusters(start, j)
    // rotate [start, j) left by i - start
    let moved = buffer.info[start:j].to_array()
    let k = i - start
    for n in 0..<moved.length() {
      buffer.info[start + n] = moved[(n + k) % moved.length()]
    }
    let new_start = start + j - i
    let new_cc = if cc == 220 { 25 } else { 26 }
    for n in start..<new_start {
      buffer.info[n].set_modified_combining_class(new_cc)
    }
    start = new_start
    i = j
  }
}
