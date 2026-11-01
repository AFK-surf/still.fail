// The Indic shaper (harfrust's ot/shaper/indic.rs, indic_machine.rs, syllabic.rs, vowel_constraints.rs): syllables
// found by the Ragel machine, consonants placed by what the font's below/post/pre-base forms would substitute, the
// initial reordering before the basic features and the final one after them.

///|
const SHAPER_INDIC : Int = 2

// categories (indic::category)

///|
const OT_X : Int = 0

///|
const OT_C : Int = 1

///|
const OT_V : Int = 2

///|
const OT_N : Int = 3

///|
const OT_H : Int = 4

///|
const OT_ZWNJ : Int = 5

///|
const OT_ZWJ : Int = 6

///|
const OT_M : Int = 7

///|
const OT_SM : Int = 8

///|
const OT_PLACEHOLDER : Int = 10

///|
const OT_DOTTEDCIRCLE : Int = 11

///|
const OT_RS : Int = 12

///|
const OT_MPST : Int = 13

///|
const OT_REPHA : Int = 14

///|
const OT_RA : Int = 15

///|
const OT_CM : Int = 16

///|
const OT_CS : Int = 18

// positions (indic::position)

///|
const POS_RA_TO_BECOME_REPH : Int = 1

///|
const POS_PRE_M : Int = 2

///|
const POS_PRE_C : Int = 3

///|
const POS_BASE_C : Int = 4

///|
const POS_AFTER_MAIN : Int = 5

///|
const POS_BEFORE_SUB : Int = 7

///|
const POS_BELOW_C : Int = 8

///|
const POS_AFTER_SUB : Int = 9

///|
const POS_BEFORE_POST : Int = 10

///|
const POS_POST_C : Int = 11

///|
const POS_AFTER_POST : Int = 12

///|
const POS_SMVD : Int = 13

///|
const POS_END : Int = 14

///|
fn cat_flag(c : Int) -> Int {
  if c < 32 && c >= 0 {
    1 << c
  } else {
    0
  }
}

///|
let consonant_flags : Int = cat_flag(OT_C) |
  cat_flag(OT_CS) |
  cat_flag(OT_RA) |
  cat_flag(OT_CM) |
  cat_flag(OT_V) |
  cat_flag(OT_PLACEHOLDER) |
  cat_flag(OT_DOTTEDCIRCLE)

///|
let joiner_flags : Int = cat_flag(OT_ZWJ) | cat_flag(OT_ZWNJ)

///|
fn GlyphInfo::is_one_of(self : GlyphInfo, flags : Int) -> Bool {
  if self.ligated() {
    return false
  }
  (cat_flag(self.shaper_category()) & flags) != 0
}

///|
fn GlyphInfo::is_joiner(self : GlyphInfo) -> Bool {
  self.is_one_of(joiner_flags)
}

///|
fn GlyphInfo::is_consonant(self : GlyphInfo) -> Bool {
  self.is_one_of(consonant_flags)
}

///|
fn GlyphInfo::is_halant(self : GlyphInfo) -> Bool {
  self.is_one_of(cat_flag(OT_H))
}

///|
/// The Indic features, in order (indic_feature's indices), and whether each is global.
let indic_features : Array[(String, Int)] = [
  ("nukt", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("akhn", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("rphf", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("rkrf", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("pref", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("blwf", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("abvf", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("half", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("pstf", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("vatu", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("cjct", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("init", F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("pres", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("abvs", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("blws", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("psts", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
  ("haln", F_GLOBAL | F_MANUAL_ZWNJ | F_MANUAL_ZWJ | F_PER_SYLLABLE),
]

///|
const F_RPHF : Int = 2

///|
const F_PREF : Int = 4

///|
const F_BLWF : Int = 5

///|
const F_ABVF : Int = 6

///|
const F_HALF : Int = 7

///|
const F_PSTF : Int = 8

///|
const F_INIT : Int = 11

// reph positions and modes

///|
const REPH_IMPLICIT : Int = 0

///|
const REPH_EXPLICIT : Int = 1

///|
const REPH_LOG_REPHA : Int = 2

///|
/// A script's configuration: (script, has an old spec, virama, reph position, reph mode, blwf before and after).
let indic_configs : Array[(String, Bool, Int, Int, Int, Bool)] = [
  ("Deva", true, 0x094D, POS_BEFORE_POST, REPH_IMPLICIT, true),
  ("Beng", true, 0x09CD, POS_AFTER_SUB, REPH_IMPLICIT, true),
  ("Guru", true, 0x0A4D, POS_BEFORE_SUB, REPH_IMPLICIT, true),
  ("Gujr", true, 0x0ACD, POS_BEFORE_POST, REPH_IMPLICIT, true),
  ("Orya", true, 0x0B4D, POS_AFTER_MAIN, REPH_IMPLICIT, true),
  ("Taml", true, 0x0BCD, POS_AFTER_POST, REPH_IMPLICIT, true),
  ("Telu", true, 0x0C4D, POS_AFTER_POST, REPH_EXPLICIT, false),
  ("Knda", true, 0x0CCD, POS_AFTER_POST, REPH_IMPLICIT, false),
  ("Mlym", true, 0x0D4D, POS_AFTER_MAIN, REPH_LOG_REPHA, true),
  ("Sinh", false, 0x0DCA, POS_AFTER_POST, REPH_EXPLICIT, true),
]

///|
/// The Indic shaper's part of a plan.
priv struct IndicPlan {
  has_old_spec : Bool
  virama : Int
  reph_pos : Int
  reph_mode : Int
  blwf_pre_and_post : Bool
  is_old_spec : Bool
  zero_context : Bool
  /// each would-substitute feature's GSUB lookups (indices into the plan's lookups): rphf, pref, blwf, pstf, vatu
  rphf : (Int, Int)
  pref : (Int, Int)
  blwf : (Int, Int)
  pstf : (Int, Int)
  vatu : (Int, Int)
  mask_array : Array[Int]
}

///|
fn indic_plan_new(
  script : Int,
  chosen_gsub_script : Int,
  features : Array[FeatureMap],
  stages : Array[(Int, Int)],
) -> IndicPlan {
  let mut config = ("", false, 0, POS_BEFORE_POST, REPH_IMPLICIT, true)
  for c in indic_configs {
    if tag(c.0) == script {
      config = c
    }
  }
  let is_old_spec = config.1 && (chosen_gsub_script == 0 || (chosen_gsub_script & 0xFF) != 0x32)
  let zero_context = is_old_spec && script != tag("Mlym")
  let feature = fn(t : String) -> FeatureMap? {
    for f in features {
      if f.tag == tag(t) {
        return Some(f)
      }
    }
    None
  }
  let range = fn(t : String) -> (Int, Int) {
    match feature(t) {
      Some(f) => {
        let stage = f.stage[0]
        if stage >= stages.length() {
          return (0, 0)
        }
        let start = if stage == 0 { 0 } else { stages[stage - 1].0 }
        (start, stages[stage].0)
      }
      None => (0, 0)
    }
  }
  let mask_array = indic_features.map(fn(f) {
    if (f.1 & F_GLOBAL) != 0 {
      0
    } else {
      match feature(f.0) {
        Some(m) => m.one_mask
        None => 0
      }
    }
  })
  {
    has_old_spec: config.1,
    virama: config.2,
    reph_pos: config.3,
    reph_mode: config.4,
    blwf_pre_and_post: config.5,
    is_old_spec,
    zero_context,
    rphf: range("rphf"),
    pref: range("pref"),
    blwf: range("blwf"),
    pstf: range("pstf"),
    vatu: range("vatu"),
    mask_array,
  }
}

///|
/// Whether a feature's lookups would substitute the glyphs (IndicWouldSubstituteFeature).
fn ShapePlan::would_substitute(self : ShapePlan, lookups : (Int, Int), zero_context : Bool, glyphs : Array[Int]) -> Bool {
  guard self.ot.gsub is Some(table) else { return false }
  for k in lookups.0..<lookups.1 {
    let lm = self.lookups[0][k]
    match table.lookup(self.ot.data, lm.index) {
      Some(lookup) => if would_apply_lookup(self.ot, lookup, glyphs, zero_context) { return true }
      None => ()
    }
  }
  false
}

///|
fn indic_decompose(ab : Int) -> (Int, Int)? {
  match ab {
    0x0931 | 0x09DC | 0x09DD | 0x0B94 => None
    _ => decompose(ab)
  }
}

///|
fn indic_compose(a : Int, b : Int) -> Int? {
  if gc_is_mark(general_category(a)) {
    return None
  }
  if a == 0x09AF && b == 0x09BC {
    return Some(0x09DF)
  }
  compose(a, b)
}

///|
fn indic_setup_masks(buffer : Buffer) -> Unit {
  for i in 0..<buffer.len {
    let (c, p) = indic_categories(buffer.info[i].glyph_id)
    buffer.info[i].set_shaper_category(c)
    buffer.info[i].set_shaper_auxiliary(p)
  }
}

///|
/// The vowel constraints: a dotted circle between vowels that would look like another.
fn preprocess_vowel_constraints(buffer : Buffer) -> Unit {
  let script = buffer.script
  let rules = vowel_constraints.filter(fn(r) { tag(r.0) == script })
  let deva = script == tag("Deva")
  if rules.length() == 0 && !deva {
    return
  }
  let cur = fn(i : Int) { if buffer.idx + i < buffer.len { buffer.info[buffer.idx + i].glyph_id } else { 0 } }
  let dotted = fn() {
    buffer.output_glyph(0x25CC)
    buffer.out_info()[buffer.out_len - 1].clear_continuation()
  }
  buffer.clear_output()
  buffer.idx = 0
  while buffer.idx + 1 < buffer.len {
    let mut matched = false
    let c0 = cur(0)
    let c1 = cur(1)
    for r in rules {
      if r.1 == c0 && r.2.contains(c1) {
        matched = true
      }
    }
    if deva && c0 == 0x0930 && c1 == 0x094D && buffer.idx + 2 < buffer.len && cur(2) == 0x0907 {
      buffer.next_glyph()
      buffer.next_glyph()
      dotted()
    }
    buffer.next_glyph()
    if matched {
      dotted()
      buffer.next_glyph()
    }
  }
  ignore(buffer.sync())
}

///|
/// The syllable machine (find_syllables_indic): each glyph's syllable byte is serial << 4 | kind.
fn find_syllables_indic(buffer : Buffer) -> Unit {
  let mut cs = 31
  let mut ts = 0
  let mut te = 0
  let mut act = 0
  let mut p = 0
  let pe = buffer.len
  let eof = buffer.len
  let mut serial = 1
  let found = fn(kind : Int) {
    for i in ts..<te {
      if i < buffer.len {
        buffer.info[i].set_syllable((serial << 4) | kind)
      }
    }
    serial += 1
    if serial == 16 {
      serial = 1
    }
    if kind == 4 {
      buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_BROKEN_SYLLABLE
    }
  }
  while p != pe || p == eof {
    if indic_machine_from_state_actions[cs] == 10 {
      ts = p
    }
    let mut trans = 0
    if p == eof {
      if indic_machine_eof_trans[cs] > 0 {
        trans = indic_machine_eof_trans[cs] - 1
      }
    } else {
      let keys = cs << 1
      let inds = indic_machine_index_offsets[cs]
      let c = buffer.info[p].shaper_category()
      if c <= 57 && c >= 1 {
        let ic = indic_machine_char_class[c - 1]
        if ic <= indic_machine_trans_keys[keys + 1] && ic >= indic_machine_trans_keys[keys] {
          trans = indic_machine_indices[inds + (ic - indic_machine_trans_keys[keys])]
        } else {
          trans = indic_machine_index_defaults[cs]
        }
      } else {
        trans = indic_machine_index_defaults[cs]
      }
    }
    cs = indic_machine_cond_targs[trans]
    match indic_machine_cond_actions[trans] {
      2 => te = p + 1
      11 => {
        te = p + 1
        found(5)
      }
      14 => {
        te = p
        p = p - 1
        found(0)
      }
      15 => {
        te = p
        p = p - 1
        found(1)
      }
      18 => {
        te = p
        p = p - 1
        found(2)
      }
      20 => {
        te = p
        p = p - 1
        found(3)
      }
      16 => {
        te = p
        p = p - 1
        found(4)
      }
      17 => {
        te = p
        p = p - 1
        found(5)
      }
      1 => {
        p = te - 1
        found(0)
      }
      3 => {
        p = te - 1
        found(1)
      }
      7 => {
        p = te - 1
        found(2)
      }
      8 => {
        p = te - 1
        found(3)
      }
      4 => {
        p = te - 1
        found(4)
      }
      6 =>
        match act {
          1 => {
            p = te - 1
            found(0)
          }
          5 => {
            p = te - 1
            found(5)
          }
          6 => {
            p = te - 1
            found(4)
          }
          7 => {
            p = te - 1
            found(5)
          }
          _ => ()
        }
      19 => {
        te = p + 1
        act = 1
      }
      13 => {
        te = p + 1
        act = 5
      }
      5 => {
        te = p + 1
        act = 6
      }
      12 => {
        te = p + 1
        act = 7
      }
      _ => ()
    }
    if p == eof {
      if cs >= 31 {
        break
      }
    } else {
      if indic_machine_to_state_actions[cs] == 9 {
        ts = 0
      }
      p += 1
      continue
    }
    break
  }
}

///|
/// Inserts a dotted circle at the start of each broken syllable (syllabic.rs).
fn insert_dotted_circles(face : @font.Face, buffer : Buffer, broken : Int, category : Int, repha : Int, position : Int) -> Bool {
  if (buffer.scratch_flags & SCRATCH_HAS_BROKEN_SYLLABLE) == 0 {
    return false
  }
  guard nominal_glyph(face, 0x25CC) is Some(glyph) else { return false }
  buffer.clear_output()
  buffer.idx = 0
  let mut last = 0
  while buffer.idx < buffer.len {
    let syllable = buffer.cur(0).syllable()
    if last != syllable && (syllable & 0x0F) == broken {
      last = syllable
      let g = GlyphInfo::new()
      g.glyph_id = glyph
      g.set_shaper_category(category)
      if position >= 0 {
        g.set_shaper_auxiliary(position)
      }
      g.cluster = buffer.cur(0).cluster
      g.mask = buffer.cur(0).mask
      g.set_syllable(syllable)
      if repha >= 0 {
        while buffer.idx < buffer.len && last == buffer.cur(0).syllable() && buffer.cur(0).shaper_category() == repha {
          buffer.next_glyph()
        }
      }
      buffer.output_info(g)
    } else {
      buffer.next_glyph()
    }
  }
  ignore(buffer.sync())
  true
}

///|
fn rotate_left(buffer : Buffer, a : Int, b : Int) -> Unit {
  // [a, b] inclusive: the first to the end
  if b <= a {
    return
  }
  let first = buffer.info[a]
  for i in a..<b {
    buffer.info[i] = buffer.info[i + 1]
  }
  buffer.info[b] = first
}

///|
fn rotate_right(buffer : Buffer, a : Int, b : Int) -> Unit {
  if b <= a {
    return
  }
  let last = buffer.info[b]
  let mut i = b
  while i > a {
    buffer.info[i] = buffer.info[i - 1]
    i -= 1
  }
  buffer.info[a] = last
}

///|
fn indic_pause(plan : ShapePlan, face : @font.Face, buffer : Buffer, which : Int) -> Unit {
  match which {
    1 => find_syllables_indic(buffer)
    2 => indic_initial_reordering(plan, face, buffer)
    3 => indic_final_reordering(plan, face, buffer)
    4 =>
      for i in 0..<buffer.len {
        buffer.info[i].set_syllable(0)
      }
    _ => ()
  }
}

///|
fn indic_initial_reordering(plan : ShapePlan, face : @font.Face, buffer : Buffer) -> Unit {
  guard plan.indic is Some(ip) else { return }
  // update_consonant_positions
  if ip.virama != 0 {
    match nominal_glyph(face, ip.virama) {
      Some(virama) =>
        for i in 0..<buffer.len {
          let info = buffer.info[i]
          if info.shaper_auxiliary() == POS_BASE_C {
            info.set_shaper_auxiliary(consonant_position(plan, ip, info.glyph_id, virama))
          }
        }
      None => ()
    }
  }
  ignore(insert_dotted_circles(face, buffer, 4, OT_DOTTEDCIRCLE, OT_REPHA, POS_END))
  let mut start = 0
  let mut end = buffer.next_syllable(0)
  while start < buffer.len {
    let kind = buffer.info[start].syllable() & 0x0F
    if kind == 0 || kind == 1 || kind == 2 || kind == 4 {
      initial_reordering_consonant_syllable(plan, ip, buffer, start, end)
    }
    start = end
    end = buffer.next_syllable(start)
  }
}

///|
fn consonant_position(plan : ShapePlan, ip : IndicPlan, consonant : Int, virama : Int) -> Int {
  let ws = fn(r : (Int, Int), g : Array[Int]) { plan.would_substitute(r, ip.zero_context, g) }
  if ws(ip.blwf, [virama, consonant]) ||
    ws(ip.blwf, [consonant, virama]) ||
    ws(ip.vatu, [virama, consonant]) ||
    ws(ip.vatu, [consonant, virama]) {
    return POS_BELOW_C
  }
  if ws(ip.pstf, [virama, consonant]) || ws(ip.pstf, [consonant, virama]) {
    return POS_POST_C
  }
  if ws(ip.pref, [virama, consonant]) || ws(ip.pref, [consonant, virama]) {
    return POS_POST_C
  }
  POS_BASE_C
}

///|
fn initial_reordering_consonant_syllable(plan : ShapePlan, ip : IndicPlan, buffer : Buffer, start : Int, end : Int) -> Unit {
  let info = fn(i : Int) { buffer.info[i] }
  let cat = fn(i : Int) { buffer.info[i].shaper_category() }
  let pos = fn(i : Int) { buffer.info[i].shaper_auxiliary() }
  let set_pos = fn(i : Int, p : Int) { buffer.info[i].set_shaper_auxiliary(p) }
  if buffer.script == tag("Knda") &&
    start + 3 <= end &&
    info(start).is_one_of(cat_flag(OT_RA)) &&
    info(start + 1).is_one_of(cat_flag(OT_H)) &&
    info(start + 2).is_one_of(cat_flag(OT_ZWJ)) {
    buffer.merge_clusters(start + 1, start + 3)
    let t = buffer.info[start + 1]
    buffer.info[start + 1] = buffer.info[start + 2]
    buffer.info[start + 2] = t
  }
  let mut base = end
  let mut has_reph = false
  let mut limit = start
  if ip.mask_array[F_RPHF] != 0 &&
    start + 3 <= end &&
    (
      (ip.reph_mode == REPH_IMPLICIT && !info(start + 2).is_joiner()) ||
      (ip.reph_mode == REPH_EXPLICIT && cat(start + 2) == OT_ZWJ)
    ) {
    let g = [info(start).glyph_id, info(start + 1).glyph_id]
    let g3 = [info(start).glyph_id, info(start + 1).glyph_id, if ip.reph_mode == REPH_EXPLICIT { info(start + 2).glyph_id } else { 0 }]
    if plan.would_substitute(ip.rphf, ip.zero_context, g) ||
      (ip.reph_mode == REPH_EXPLICIT && plan.would_substitute(ip.rphf, ip.zero_context, g3)) {
      limit += 2
      while limit < end && info(limit).is_joiner() {
        limit += 1
      }
      base = start
      has_reph = true
    }
  } else if ip.reph_mode == REPH_LOG_REPHA && cat(start) == OT_REPHA {
    limit += 1
    while limit < end && info(limit).is_joiner() {
      limit += 1
    }
    base = start
    has_reph = true
  }
  let mut i = end
  let mut seen_below = false
  while true {
    i -= 1
    let inf = info(i)
    if inf.is_consonant() {
      if pos(i) != POS_BELOW_C && (pos(i) != POS_POST_C || seen_below) {
        base = i
        break
      }
      if pos(i) == POS_BELOW_C {
        seen_below = true
      }
      base = i
    } else if start < i && cat(i) == OT_ZWJ && cat(i - 1) == OT_H {
      break
    }
    if i <= limit {
      break
    }
  }
  if has_reph && base == start && limit - base <= 2 {
    has_reph = false
  }
  for k in start..<base {
    set_pos(k, if pos(k) < POS_PRE_C { pos(k) } else { POS_PRE_C })
  }
  if base < end {
    set_pos(base, POS_BASE_C)
  }
  if has_reph {
    set_pos(start, POS_RA_TO_BECOME_REPH)
  }
  if ip.is_old_spec {
    let disallow_double_halants = buffer.script == tag("Knda")
    for k in (base + 1)..<end {
      if cat(k) == OT_H {
        let mut j = end - 1
        while j > k {
          if info(j).is_consonant() || (disallow_double_halants && cat(j) == OT_H) {
            break
          }
          j -= 1
        }
        if cat(j) != OT_H && j > k {
          rotate_left(buffer, k, j)
        }
        break
      }
    }
  }
  // attach misc marks to the previous char
  let mut last_pos = 0
  for k in start..<end {
    let c = cat(k)
    let ok = (
        cat_flag(c) &
        (cat_flag(OT_ZWJ) | cat_flag(OT_ZWNJ) | cat_flag(OT_N) | cat_flag(OT_RS) | cat_flag(OT_CM) | cat_flag(OT_H))
      ) !=
      0
    if ok {
      let mut p = last_pos
      if c == OT_H && p == POS_PRE_M {
        let mut j = k
        while j >= start + 1 {
          let prev = pos(j - 1)
          if prev != POS_PRE_M {
            p = prev
            break
          }
          j -= 1
        }
      }
      set_pos(k, p)
    } else if pos(k) != POS_SMVD {
      if c == OT_MPST && k > start && cat(k - 1) == OT_SM {
        set_pos(k - 1, pos(k))
      }
      last_pos = pos(k)
    }
  }
  let mut last = base
  for k in (base + 1)..<end {
    if info(k).is_consonant() {
      for o in (last + 1)..<k {
        if pos(o) < POS_SMVD {
          set_pos(o, pos(k))
        }
      }
      last = k
    } else if (cat_flag(cat(k)) & (cat_flag(OT_M) | cat_flag(OT_MPST))) != 0 {
      last = k
    }
  }
  // sort by position, remembering where each came from
  let syllable = info(start).syllable()
  for k in start..<end {
    buffer.info[k].set_syllable(k - start)
  }
  for k in (start + 1)..<end {
    let item = buffer.info[k]
    let mut j = k
    while j > start && buffer.info[j - 1].shaper_auxiliary() > item.shaper_auxiliary() {
      buffer.info[j] = buffer.info[j - 1]
      j -= 1
    }
    buffer.info[j] = item
  }
  let mut first_left_matra = end
  let mut last_left_matra = end
  base = end
  for k in start..<end {
    if pos(k) == POS_BASE_C {
      base = k
      break
    } else if pos(k) == POS_PRE_M {
      if first_left_matra == end {
        first_left_matra = k
      }
      last_left_matra = k
    }
  }
  if first_left_matra < last_left_matra {
    buffer.reverse_range(first_left_matra, last_left_matra + 1)
    let mut k = first_left_matra
    for j in first_left_matra..=last_left_matra {
      if (cat_flag(cat(j)) & (cat_flag(OT_M) | cat_flag(OT_MPST))) != 0 {
        buffer.reverse_range(k, j + 1)
        k = j + 1
      }
    }
  }
  if ip.is_old_spec || end - start > 127 {
    buffer.merge_clusters(base, end)
  } else {
    for k in base..<end {
      let order = info(k).syllable()
      if order != 255 {
        let mut mn = k
        let mut mx = k
        let mut j = start + order
        while j != k {
          mn = if j < mn { j } else { mn }
          mx = if j > mx { j } else { mx }
          let next = start + info(j).syllable()
          info(j).set_syllable(255)
          j = next
        }
        buffer.merge_clusters(if base > mn { base } else { mn }, mx + 1)
      }
    }
  }
  for k in start..<end {
    buffer.info[k].set_syllable(syllable)
  }
  // masks
  for k in start..<end {
    if pos(k) != POS_RA_TO_BECOME_REPH {
      break
    }
    info(k).mask = info(k).mask | ip.mask_array[F_RPHF]
  }
  let mut mask = ip.mask_array[F_HALF]
  if !ip.is_old_spec && ip.blwf_pre_and_post {
    mask = mask | ip.mask_array[F_BLWF]
  }
  for k in start..<base {
    info(k).mask = info(k).mask | mask
  }
  mask = ip.mask_array[F_BLWF] | ip.mask_array[F_ABVF] | ip.mask_array[F_PSTF]
  for k in (base + 1)..<end {
    info(k).mask = info(k).mask | mask
  }
  if ip.is_old_spec && buffer.script == tag("Deva") {
    let top = if base > 0 { base - 1 } else { 0 }
    for k in start..<top {
      if cat(k) == OT_RA && cat(k + 1) == OT_H && (k + 2 == base || cat(k + 2) != OT_ZWJ) {
        info(k).mask = info(k).mask | ip.mask_array[F_BLWF]
        info(k + 1).mask = info(k + 1).mask | ip.mask_array[F_BLWF]
      }
    }
  }
  let pref_len = 2
  if ip.mask_array[F_PREF] != 0 && base + pref_len < end {
    for k in (base + 1)..<(end - pref_len + 1) {
      if plan.would_substitute(ip.pref, ip.zero_context, [info(k).glyph_id, info(k + 1).glyph_id]) {
        for j in k..<(k + pref_len) {
          info(j).mask = info(j).mask | ip.mask_array[F_PREF]
        }
        break
      }
    }
  }
  for k in (start + 1)..<end {
    if info(k).is_joiner() {
      let non_joiner = cat(k) == OT_ZWNJ
      let mut j = k
      while true {
        j -= 1
        if non_joiner {
          info(j).mask = info(j).mask & (ip.mask_array[F_HALF] ^ -1)
        }
        if j <= start || info(j).is_consonant() {
          break
        }
      }
    }
  }
}

///|
fn indic_final_reordering(plan : ShapePlan, face : @font.Face, buffer : Buffer) -> Unit {
  guard plan.indic is Some(ip) else { return }
  if buffer.len == 0 {
    return
  }
  let virama = if ip.virama != 0 { nominal_glyph(face, ip.virama) } else { None }
  let mut start = 0
  let mut end = buffer.next_syllable(0)
  while start < buffer.len {
    final_reordering_syllable(buffer, ip, virama, start, end)
    start = end
    end = buffer.next_syllable(start)
  }
}

///|
fn final_reordering_syllable(buffer : Buffer, ip : IndicPlan, virama : Int?, start : Int, end : Int) -> Unit {
  let info = fn(i : Int) { buffer.info[i] }
  let cat = fn(i : Int) { buffer.info[i].shaper_category() }
  let pos = fn(i : Int) { buffer.info[i].shaper_auxiliary() }
  let mlym_or_taml = buffer.script == tag("Mlym") || buffer.script == tag("Taml")
  match virama {
    Some(v) =>
      for k in start..<end {
        let inf = info(k)
        if inf.glyph_id == v && inf.ligated() && inf.multiplied() {
          inf.set_shaper_category(OT_H)
          inf.clear_ligated_and_multiplied()
        }
      }
    None => ()
  }
  let mut try_pref = ip.mask_array[F_PREF] != 0
  let mut base = start
  while base < end {
    if pos(base) >= POS_BASE_C {
      if try_pref && base + 1 < end {
        for k in (base + 1)..<end {
          let inf = info(k)
          if (inf.mask & ip.mask_array[F_PREF]) != 0 {
            if !(inf.substituted() && inf.ligated_and_didnt_multiply()) {
              base = k
              while base < end && info(base).is_halant() {
                base += 1
              }
              if base < end {
                info(base).set_shaper_auxiliary(POS_BASE_C)
              }
              try_pref = false
            }
            break
          }
          if base == end {
            break
          }
        }
      }
      if buffer.script == tag("Mlym") {
        let mut k = base + 1
        while k < end {
          while k < end && info(k).is_joiner() {
            k += 1
          }
          if k == end || !info(k).is_halant() {
            break
          }
          k += 1
          while k < end && info(k).is_joiner() {
            k += 1
          }
          if k < end && info(k).is_consonant() && pos(k) == POS_BELOW_C {
            base = k
            info(k).set_shaper_auxiliary(POS_BASE_C)
          }
          k += 1
        }
      }
      if start < base && pos(base) > POS_BASE_C {
        base -= 1
      }
      break
    }
    base += 1
  }
  if base == end && start < base && info(base - 1).is_one_of(cat_flag(OT_ZWJ)) {
    base -= 1
  }
  if base < end {
    while start < base && info(base).is_one_of(cat_flag(OT_N) | cat_flag(OT_H)) {
      base -= 1
    }
  }
  // reorder matras
  if start + 1 < end && start < base {
    let mut new_pos = if base == end { base - 2 } else { base - 1 }
    if !mlym_or_taml {
      while true {
        while new_pos > start && !info(new_pos).is_one_of(cat_flag(OT_M) | cat_flag(OT_MPST) | cat_flag(OT_H)) {
          new_pos -= 1
        }
        if info(new_pos).is_halant() && pos(new_pos) != POS_PRE_M {
          if new_pos + 1 < end && cat(new_pos + 1) == OT_ZWJ && new_pos > start {
            new_pos -= 1
            continue
          }
        } else {
          new_pos = start
        }
        break
      }
    }
    if start < new_pos && pos(new_pos) != POS_PRE_M {
      let mut k = new_pos
      while k >= start + 1 {
        if pos(k - 1) == POS_PRE_M {
          let old_pos = k - 1
          if old_pos < base && base <= new_pos {
            base -= 1
          }
          rotate_left(buffer, old_pos, new_pos)
          buffer.merge_clusters(new_pos, if end < base + 1 { end } else { base + 1 })
          new_pos -= 1
        }
        k -= 1
      }
    } else {
      for k in start..<base {
        if pos(k) == POS_PRE_M {
          buffer.merge_clusters(k, if end < base + 1 { end } else { base + 1 })
          break
        }
      }
    }
  }
  // reph
  if start + 1 < end &&
    pos(start) == POS_RA_TO_BECOME_REPH &&
    ((cat(start) == OT_REPHA) != info(start).ligated_and_didnt_multiply()) {
    let mut new_reph_pos = start + 1
    let mut done = false
    let reph_pos = ip.reph_pos
    if reph_pos != POS_AFTER_POST {
      new_reph_pos = start + 1
      while new_reph_pos < base && !info(new_reph_pos).is_halant() {
        new_reph_pos += 1
      }
      if new_reph_pos < base && info(new_reph_pos).is_halant() {
        if new_reph_pos + 1 < base && info(new_reph_pos + 1).is_joiner() {
          new_reph_pos += 1
        }
        done = true
      }
      if !done && reph_pos == POS_AFTER_MAIN {
        new_reph_pos = base
        while new_reph_pos + 1 < end && pos(new_reph_pos + 1) <= POS_AFTER_MAIN {
          new_reph_pos += 1
        }
        if new_reph_pos < end {
          done = true
        }
      }
      if !done && reph_pos == POS_AFTER_SUB {
        new_reph_pos = base
        while new_reph_pos + 1 < end &&
          (cat_flag(pos(new_reph_pos + 1)) & (cat_flag(POS_POST_C) | cat_flag(POS_AFTER_POST) | cat_flag(POS_SMVD))) ==
          0 {
          new_reph_pos += 1
        }
        if new_reph_pos < end {
          done = true
        }
      }
    }
    if !done {
      new_reph_pos = start + 1
      while new_reph_pos < base && !info(new_reph_pos).is_halant() {
        new_reph_pos += 1
      }
      if new_reph_pos < base && info(new_reph_pos).is_halant() {
        if new_reph_pos + 1 < base && info(new_reph_pos + 1).is_joiner() {
          new_reph_pos += 1
        }
        done = true
      }
    }
    if !done {
      new_reph_pos = end - 1
      while new_reph_pos > start && pos(new_reph_pos) == POS_SMVD {
        new_reph_pos -= 1
      }
      if info(new_reph_pos).is_halant() {
        for k in (base + 1)..<new_reph_pos {
          if (cat_flag(cat(k)) & (cat_flag(OT_M) | cat_flag(OT_MPST))) != 0 {
            new_reph_pos -= 1
          }
        }
      }
    }
    buffer.merge_clusters(start, new_reph_pos + 1)
    rotate_left(buffer, start, new_reph_pos)
    if start < base && base <= new_reph_pos {
      base -= 1
    }
  }
  // pre-base reordering forms
  if try_pref && base + 1 < end {
    for k in (base + 1)..<end {
      if (info(k).mask & ip.mask_array[F_PREF]) != 0 {
        if info(k).ligated_and_didnt_multiply() {
          let mut new_pos = base
          if !mlym_or_taml {
            while new_pos > start && !info(new_pos - 1).is_one_of(cat_flag(OT_M) | cat_flag(OT_MPST) | cat_flag(OT_H)) {
              new_pos -= 1
            }
          }
          if new_pos > start && info(new_pos - 1).is_halant() {
            if new_pos < end && info(new_pos).is_joiner() {
              new_pos += 1
            }
          }
          let old_pos = k
          buffer.merge_clusters(new_pos, old_pos + 1)
          rotate_right(buffer, new_pos, old_pos)
          if new_pos <= base && base < old_pos {
            base += 1
          }
        }
        break
      }
    }
  }
  if pos(start) == POS_PRE_M {
    let prev_gc = if start == 0 { -1 } else { info(start - 1).general_category() }
    if start == 0 || !(prev_gc >= GC_FORMAT && prev_gc <= GC_NON_SPACING_MARK) {
      info(start).mask = info(start).mask | ip.mask_array[F_INIT]
    }
  }
}
