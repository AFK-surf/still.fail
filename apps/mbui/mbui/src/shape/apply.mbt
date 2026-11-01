// Applying lookups (harfrust's ot/apply.rs, ot/layout.rs, ot/lookup/mod.rs): which glyphs a lookup skips, matching
// input, backtrack and lookahead sequences, recursing into nested lookups, ligating, and walking the buffer.

///|
const MAX_NESTING_LEVEL : Int = 64

///|
const MAX_CONTEXT_LENGTH : Int = 64

///|
priv struct Matcher {
  lookup_props : Int
  mask : Int
  ignore_zwnj : Bool
  ignore_zwj : Bool
  ignore_hidden : Bool
  per_syllable : Bool
}

///|
fn Matcher::default() -> Matcher {
  {
    lookup_props: 0,
    mask: 0,
    ignore_zwnj: false,
    ignore_zwj: false,
    ignore_hidden: false,
    per_syllable: false,
  }
}

///|
/// How a glyph answers a matcher (MaySkip/MayMatch/MatchResult): 0 no, 1 yes, 2 maybe.
const NO : Int = 0

///|
const YES : Int = 1

///|
const MAYBE : Int = 2

///|
const MATCH : Int = 0

///|
const NOT_MATCH : Int = 1

///|
const SKIP : Int = 2

///|
priv struct ApplyContext {
  is_gsub : Bool
  ot : OtData
  buffer : Buffer
  mut lookup_mask : Int
  mut per_syllable : Bool
  mut lookup_index : Int
  mut lookup_props : Int
  mut nesting_level_left : Int
  mut auto_zwnj : Bool
  mut auto_zwj : Bool
  mut random : Bool
  mut random_state : Int
  mut last_base : Int
  mut last_base_until : Int
  mut matcher : Matcher
  mut context_matcher : Matcher
  mut match_positions : Array[Int]
}

///|
fn ApplyContext::new(is_gsub : Bool, ot : OtData, buffer : Buffer) -> ApplyContext {
  {
    is_gsub,
    ot,
    buffer,
    lookup_mask: 1,
    per_syllable: false,
    lookup_index: 0xFFFF,
    lookup_props: -1,
    nesting_level_left: MAX_NESTING_LEVEL,
    auto_zwnj: true,
    auto_zwj: true,
    random: false,
    random_state: 1,
    last_base: -1,
    last_base_until: 0,
    matcher: Matcher::default(),
    context_matcher: Matcher::default(),
    match_positions: [0],
  }
}

///|
fn ApplyContext::new_matcher(self : ApplyContext, context_match : Bool) -> Matcher {
  {
    lookup_props: self.lookup_props,
    ignore_zwnj: !self.is_gsub || (context_match && self.auto_zwnj),
    ignore_zwj: context_match || self.auto_zwj,
    ignore_hidden: !self.is_gsub,
    mask: if context_match { -1 } else { self.lookup_mask },
    per_syllable: self.is_gsub && self.per_syllable,
  }
}

///|
fn ApplyContext::update_matchers(self : ApplyContext) -> Unit {
  self.matcher = self.new_matcher(false)
  self.context_matcher = self.new_matcher(true)
}

///|
fn ApplyContext::set_lookup_mask(self : ApplyContext, mask : Int) -> Unit {
  self.lookup_mask = mask
  self.last_base = -1
  self.last_base_until = 0
}

///|
fn ApplyContext::random_number(self : ApplyContext) -> Int {
  let s = (self.random_state.to_int64() & 0xFFFFFFFFL) * 48271L
  self.random_state = ((s & 0xFFFFFFFFL) % 2147483647L).to_int()
  self.random_state
}

///|
fn ApplyContext::set_match_position(self : ApplyContext, i : Int, position : Int) -> Unit {
  while self.match_positions.length() <= i {
    self.match_positions.push(0)
  }
  self.match_positions[i] = position
}

///|
fn check_glyph_property(ot : OtData, info : GlyphInfo, match_props : Int) -> Bool {
  let glyph_props = info.glyph_props()
  if (glyph_props & match_props & LOOKUP_IGNORE_FLAGS) != 0 {
    return false
  }
  if (glyph_props & GPROPS_MARK) != 0 {
    if (match_props & LOOKUP_USE_MARK_FILTERING_SET) != 0 {
      return ot.is_mark_glyph(info.glyph_id, (match_props >> 16) & 0xFFFF)
    }
    if (match_props & LOOKUP_MARK_ATTACHMENT_TYPE_MASK) != 0 {
      return (match_props & LOOKUP_MARK_ATTACHMENT_TYPE_MASK) ==
        (glyph_props & LOOKUP_MARK_ATTACHMENT_TYPE_MASK)
    }
  }
  true
}

///|
fn Matcher::may_skip(self : Matcher, info : GlyphInfo, ot : OtData, lookup_props : Int) -> Int {
  if !check_glyph_property(ot, info, lookup_props) {
    return YES
  }
  if info.is_default_ignorable() &&
    (self.ignore_zwnj || !info.is_zwnj()) &&
    (self.ignore_zwj || !info.is_zwj()) &&
    (self.ignore_hidden || !info.is_hidden()) {
    return MAYBE
  }
  NO
}

///|
fn Matcher::may_match(
  self : Matcher,
  info : GlyphInfo,
  glyph_data : Int,
  match_func : ((GlyphInfo, Int) -> Bool)?,
  syllable : Int,
) -> Int {
  if (info.mask & self.mask) == 0 ||
    (self.per_syllable && syllable != 0 && syllable != info.syllable()) {
    return NO
  }
  match match_func {
    Some(f) => if f(info, glyph_data) { YES } else { NO }
    None => MAYBE
  }
}

///|
priv struct SkippingIterator {
  ctx : ApplyContext
  matcher : Matcher
  match_func : ((GlyphInfo, Int) -> Bool)?
  mut buf_len : Int
  mut glyph_data : Int
  mut buf_idx : Int
  mut lookup_props : Int
  mut syllable : Int
}

///|
fn SkippingIterator::new(
  ctx : ApplyContext,
  context_match : Bool,
  match_func : ((GlyphInfo, Int) -> Bool)?,
) -> SkippingIterator {
  let matcher = if context_match { ctx.context_matcher } else { ctx.matcher }
  {
    ctx,
    matcher,
    match_func,
    buf_len: ctx.buffer.len,
    glyph_data: 0,
    buf_idx: 0,
    lookup_props: matcher.lookup_props,
    syllable: 0,
  }
}

///|
fn SkippingIterator::match_info(self : SkippingIterator, info : GlyphInfo) -> Int {
  let skip = self.matcher.may_skip(info, self.ctx.ot, self.lookup_props)
  if skip == YES {
    return SKIP
  }
  let m = self.matcher.may_match(info, self.glyph_data, self.match_func, self.syllable)
  if m == YES || (m == MAYBE && skip == NO) {
    return MATCH
  }
  if skip == NO {
    return NOT_MATCH
  }
  SKIP
}

///|
fn SkippingIterator::match_at(self : SkippingIterator, idx : Int) -> Int {
  if idx < 0 || idx >= self.ctx.buffer.info.length() {
    return NOT_MATCH
  }
  self.match_info(self.ctx.buffer.info[idx])
}

///|
fn SkippingIterator::may_skip(self : SkippingIterator, info : GlyphInfo) -> Int {
  self.matcher.may_skip(info, self.ctx.ot, self.lookup_props)
}

///|
fn SkippingIterator::reset(self : SkippingIterator, start : Int) -> Unit {
  self.buf_idx = start
  self.buf_len = self.ctx.buffer.len
  let b = self.ctx.buffer
  self.syllable = if b.idx < b.info.length() { b.info[b.idx].syllable() } else { 0 }
}

///|
fn SkippingIterator::reset_back(self : SkippingIterator, start : Int) -> Unit {
  self.buf_idx = start
  let b = self.ctx.buffer
  self.syllable = if b.idx < b.info.length() { b.info[b.idx].syllable() } else { 0 }
}

///|
/// Steps forward to the next glyph that matches; on failure the answer's second is where it is unsafe to break to.
fn SkippingIterator::next(self : SkippingIterator) -> (Bool, Int) {
  let stop = if self.buf_len > 0 { self.buf_len - 1 } else { 0 }
  while self.buf_idx < stop {
    self.buf_idx += 1
    match self.match_at(self.buf_idx) {
      MATCH => {
        self.glyph_data += 1
        return (true, 0)
      }
      NOT_MATCH => return (false, self.buf_idx + 1)
      _ => ()
    }
  }
  (false, self.buf_idx + 1)
}

///|
fn SkippingIterator::prev(self : SkippingIterator) -> (Bool, Int) {
  let out = self.ctx.buffer.out_info()
  while self.buf_idx > 0 {
    self.buf_idx -= 1
    let r = if self.buf_idx < out.length() {
      self.match_info(out[self.buf_idx])
    } else {
      NOT_MATCH
    }
    match r {
      MATCH => {
        self.glyph_data += 1
        return (true, 0)
      }
      NOT_MATCH => return (false, if self.buf_idx > 1 { self.buf_idx - 1 } else { 0 })
      _ => ()
    }
  }
  (false, 0)
}

///|
/// Matches `input_len` more glyphs after the current one; answers whether it did, the end of the match (or how far
/// it looked), and the number of ligature components the matched glyphs stand for.
fn match_input(
  ctx : ApplyContext,
  input_len : Int,
  match_func : (GlyphInfo, Int) -> Bool,
) -> (Bool, Int, Int) {
  let count = input_len + 1
  let buffer = ctx.buffer
  if count == 1 {
    ctx.set_match_position(0, buffer.idx)
    return (true, buffer.idx + 1, buffer.cur(0).lig_num_comps())
  }
  if count > MAX_CONTEXT_LENGTH {
    return (false, 0, 0)
  }
  let iter = SkippingIterator::new(ctx, false, Some(match_func))
  iter.reset(buffer.idx)
  iter.glyph_data = 0
  let first = buffer.cur(0)
  let first_lig_id = first.lig_id()
  let first_lig_comp = first.lig_comp()
  let mut total = 0
  // 0 not checked, 1 may not skip, 2 may skip
  let mut ligbase = 0
  for i in 1..<count {
    let (ok, unsafe_to) = iter.next()
    if !ok {
      return (false, unsafe_to, 0)
    }
    ctx.set_match_position(i, iter.buf_idx)
    let this = buffer.info[iter.buf_idx]
    let this_lig_id = this.lig_id()
    let this_lig_comp = this.lig_comp()
    if first_lig_id != 0 && first_lig_comp != 0 {
      if first_lig_id != this_lig_id || first_lig_comp != this_lig_comp {
        if ligbase == 0 {
          let out = buffer.out_info()
          let mut j = buffer.out_len
          let mut found = false
          while j > 0 {
            let info = out[j - 1]
            if info.lig_id() != first_lig_id {
              break
            }
            j -= 1
            if info.lig_comp() == 0 {
              found = true
              break
            }
          }
          ligbase = if found && j < out.length() && iter.may_skip(out[j]) == YES {
            2
          } else {
            1
          }
        }
        if ligbase == 1 {
          return (false, 0, 0)
        }
      }
    } else if this_lig_id != 0 && this_lig_comp != 0 && this_lig_id != first_lig_id {
      return (false, 0, 0)
    }
    total += this.lig_num_comps_in_ligation()
  }
  ctx.match_positions[0] = buffer.idx
  (true, iter.buf_idx + 1, total + first.lig_num_comps())
}

///|
/// Matches `len` glyphs before the current one, in the output; answers whether it did and where the match starts.
fn match_backtrack(ctx : ApplyContext, len : Int, match_func : (GlyphInfo, Int) -> Bool) -> (Bool, Int) {
  if len == 0 {
    return (true, ctx.buffer.backtrack_len())
  }
  let iter = SkippingIterator::new(ctx, true, Some(match_func))
  iter.reset_back(ctx.buffer.backtrack_len())
  iter.glyph_data = 0
  for _ in 0..<len {
    let (ok, unsafe_from) = iter.prev()
    if !ok {
      return (false, unsafe_from)
    }
  }
  (true, iter.buf_idx)
}

///|
/// Matches `len` glyphs from after `start`; answers whether it did and where the match ends.
fn match_lookahead(
  ctx : ApplyContext,
  len : Int,
  match_func : (GlyphInfo, Int) -> Bool,
  start : Int,
) -> (Bool, Int) {
  if len == 0 {
    return (true, start)
  }
  let iter = SkippingIterator::new(ctx, true, Some(match_func))
  iter.reset(start - 1)
  iter.glyph_data = 0
  for _ in 0..<len {
    let (ok, unsafe_to) = iter.next()
    if !ok {
      return (false, unsafe_to)
    }
  }
  (true, iter.buf_idx + 1)
}

///|
/// Applies a context rule's nested lookups (`records`: pairs of sequence index and lookup index) at the matched
/// positions.
fn apply_lookup(ctx : ApplyContext, input_len : Int, match_end : Int, records : Array[(Int, Int)]) -> Unit {
  let buffer = ctx.buffer
  let mut count = input_len + 1
  let backtrack_len = buffer.backtrack_len()
  let delta0 = backtrack_len - buffer.idx
  for j in 0..<count {
    ctx.match_positions[j] = ctx.match_positions[j] + delta0
  }
  let mut end = backtrack_len + match_end - buffer.idx
  for record in records {
    if !buffer.successful {
      break
    }
    let (idx, lookup_index) = record
    if idx >= count {
      continue
    }
    let orig_len = buffer.backtrack_len() + buffer.lookahead_len()
    if ctx.match_positions[idx] >= orig_len {
      continue
    }
    if !buffer.move_to(ctx.match_positions[idx]) {
      break
    }
    if buffer.max_ops <= 0 {
      break
    }
    if !ctx.recurse(lookup_index) {
      continue
    }
    let new_len = buffer.backtrack_len() + buffer.lookahead_len()
    let mut delta = new_len - orig_len
    if delta == 0 {
      continue
    }
    end += delta
    if end < ctx.match_positions[idx] {
      delta += ctx.match_positions[idx] - end
      end = ctx.match_positions[idx]
    }
    let mut next = idx + 1
    if delta > 0 {
      if delta + count > MAX_CONTEXT_LENGTH {
        break
      }
      while ctx.match_positions.length() < delta + count {
        ctx.match_positions.push(0)
      }
    } else {
      if delta < next - count {
        delta = next - count
      }
      next = next - delta
    }
    // copy_within(next..count, next + delta)
    let moved = ctx.match_positions[next:count].to_array()
    for k in 0..<moved.length() {
      ctx.set_match_position(next + delta + k, moved[k])
    }
    next = next + delta
    count = count + delta
    for j in (idx + 1)..<next {
      ctx.match_positions[j] = ctx.match_positions[j - 1] + 1
    }
    while next < count {
      ctx.match_positions[next] = ctx.match_positions[next] + delta
      next += 1
    }
  }
  ignore(buffer.move_to(end))
}

///|
fn ApplyContext::recurse(self : ApplyContext, sub_lookup : Int) -> Bool {
  if self.nesting_level_left == 0 {
    self.buffer.successful = false
    return false
  }
  self.buffer.max_ops -= 1
  if self.buffer.max_ops < 0 {
    self.buffer.successful = false
    return false
  }
  self.nesting_level_left -= 1
  let saved_props = self.lookup_props
  let saved_index = self.lookup_index
  let saved_positions = self.match_positions
  self.match_positions = [0]
  self.lookup_index = sub_lookup
  let applied = match self.ot.table(self.is_gsub) {
    Some(table) =>
      match table.lookup(self.ot.data, sub_lookup) {
        Some(lookup) => {
          self.lookup_props = lookup.props
          self.update_matchers()
          apply_lookup_here(self, lookup)
        }
        None => false
      }
    None => false
  }
  self.lookup_props = saved_props
  self.lookup_index = saved_index
  self.update_matchers()
  self.match_positions = saved_positions
  self.nesting_level_left += 1
  applied
}

///|
fn ApplyContext::set_glyph_class(
  self : ApplyContext,
  glyph : Int,
  class_guess : Int,
  ligature : Bool,
  component : Bool,
) -> Unit {
  let cur = self.buffer.cur(0)
  let mut props = cur.glyph_props()
  props = props | GPROPS_SUBSTITUTED
  if ligature {
    props = props | GPROPS_LIGATED
    props = props & (GPROPS_MULTIPLIED ^ 0xFFFF)
  }
  if component {
    props = props | GPROPS_MULTIPLIED
  }
  if self.ot.has_glyph_classes() {
    props = props & GPROPS_PRESERVE
    cur.set_glyph_props(props | self.ot.glyph_props(glyph))
  } else if class_guess != 0 {
    props = props & GPROPS_PRESERVE
    cur.set_glyph_props(props | class_guess)
  } else {
    cur.set_glyph_props(props)
  }
}

///|
fn ApplyContext::replace_glyph(self : ApplyContext, glyph : Int) -> Unit {
  self.set_glyph_class(glyph, 0, false, false)
  self.buffer.replace_glyph(glyph)
}

///|
fn ApplyContext::replace_glyph_inplace(self : ApplyContext, glyph : Int) -> Unit {
  self.set_glyph_class(glyph, 0, false, false)
  self.buffer.cur(0).glyph_id = glyph
}

///|
fn ApplyContext::replace_glyph_with_ligature(self : ApplyContext, glyph : Int, class_guess : Int) -> Unit {
  self.set_glyph_class(glyph, class_guess, true, false)
  self.buffer.replace_glyph(glyph)
}

///|
fn ApplyContext::output_glyph_for_component(self : ApplyContext, glyph : Int, class_guess : Int) -> Unit {
  self.set_glyph_class(glyph, class_guess, false, true)
  self.buffer.output_glyph(glyph)
}

///|
fn ligate_input(ctx : ApplyContext, count : Int, match_end : Int, total_component_count : Int, lig_glyph : Int) -> Unit {
  let buffer = ctx.buffer
  let first_info = buffer.info[ctx.match_positions[0]]
  let mut is_base_ligature = first_info.is_base_glyph()
  let mut is_mark_ligature = first_info.is_mark()
  for i in 1..<count {
    if !buffer.info[ctx.match_positions[i]].is_mark() {
      is_base_ligature = false
      is_mark_ligature = false
    }
  }
  buffer.merge_clusters(buffer.idx, match_end)
  let is_ligature = !is_base_ligature && !is_mark_ligature
  let class = if is_ligature { GPROPS_LIGATURE } else { 0 }
  let lig_id = if is_ligature { buffer.allocate_lig_id() } else { 0 }
  let first = buffer.cur(0)
  let mut last_lig_id = first.lig_id()
  let mut last_num_comps = first.lig_num_comps()
  let mut comps_so_far = last_num_comps
  if is_ligature {
    first.set_lig_props_for_ligature(lig_id, total_component_count)
    if first.general_category() == GC_NON_SPACING_MARK {
      first.set_general_category(GC_OTHER_LETTER)
    }
  }
  ctx.replace_glyph_with_ligature(lig_glyph, class)
  for i in 1..<count {
    while buffer.idx < ctx.match_positions[i] && buffer.successful {
      if is_ligature {
        let cur = buffer.cur(0)
        let mut this_comp = cur.lig_comp()
        if this_comp == 0 {
          this_comp = last_num_comps
        }
        let new_lig_comp = comps_so_far - last_num_comps +
          (if this_comp < last_num_comps { this_comp } else { last_num_comps })
        cur.set_lig_props_for_mark(lig_id, new_lig_comp)
      }
      buffer.next_glyph()
    }
    let cur = buffer.cur(0)
    last_lig_id = cur.lig_id()
    last_num_comps = cur.lig_num_comps_in_ligation()
    comps_so_far += last_num_comps
    buffer.idx += 1
  }
  if !is_mark_ligature && last_lig_id != 0 {
    let mut k = buffer.idx
    while k < buffer.len {
      let info = buffer.info[k]
      if last_lig_id != info.lig_id() {
        break
      }
      let this_comp = info.lig_comp()
      if this_comp == 0 {
        break
      }
      let new_lig_comp = comps_so_far - last_num_comps +
        (if this_comp < last_num_comps { this_comp } else { last_num_comps })
      info.set_lig_props_for_mark(lig_id, new_lig_comp)
      k += 1
    }
  }
}

///|
/// The coverage table of a subtable, by its lookup's type.
fn subtable_coverage(d : Bytes, is_gsub : Bool, kind : Int, s : Int) -> Int {
  let context = if is_gsub { 5 } else { 7 }
  let chained = if is_gsub { 6 } else { 8 }
  if kind == context && rd16(d, s) == 3 {
    off16(d, s, s + 6)
  } else if kind == chained && rd16(d, s) == 3 {
    let b = rd16(d, s + 2)
    off16(d, s, s + 4 + b * 2 + 2)
  } else {
    off16(d, s, s + 2)
  }
}

///|
/// Applies a lookup at the buffer's current glyph: its first subtable that covers the glyph and applies.
fn apply_lookup_here(ctx : ApplyContext, lookup : Lookup) -> Bool {
  let d = ctx.ot.data
  let glyph = ctx.buffer.cur(0).glyph_id
  for s in lookup.subtables {
    let index = coverage_get(d, subtable_coverage(d, ctx.is_gsub, lookup.kind, s), glyph)
    if index < 0 {
      continue
    }
    let applied = if ctx.is_gsub {
      apply_gsub_subtable(ctx, lookup.kind, s, index)
    } else {
      apply_gpos_subtable(ctx, lookup.kind, s, index)
    }
    if applied {
      return true
    }
  }
  false
}

///|
fn apply_string(ctx : ApplyContext, lookup : Lookup) -> Unit {
  let buffer = ctx.buffer
  if buffer.len == 0 || ctx.lookup_mask == 0 {
    return
  }
  ctx.lookup_props = lookup.props
  ctx.update_matchers()
  let ot = ctx.ot
  if !lookup.is_reverse {
    if ctx.is_gsub {
      buffer.clear_output()
    }
    buffer.idx = 0
    while buffer.successful {
      let mut j = buffer.idx
      while j < buffer.len {
        let info = buffer.info[j]
        if (info.mask & ctx.lookup_mask) != 0 && check_glyph_property(ot, info, ctx.lookup_props) {
          break
        }
        j += 1
      }
      if j > buffer.idx {
        buffer.next_glyphs(j - buffer.idx)
      }
      if buffer.idx >= buffer.len {
        break
      }
      if !apply_lookup_here(ctx, lookup) {
        buffer.next_glyph()
      }
    }
    if ctx.is_gsub {
      ignore(buffer.sync())
    }
  } else {
    buffer.idx = buffer.len - 1
    while true {
      let mut idx = buffer.idx
      while idx >= 0 {
        let info = buffer.info[idx]
        if (info.mask & ctx.lookup_mask) != 0 && check_glyph_property(ot, info, ctx.lookup_props) {
          break
        }
        idx -= 1
      }
      if idx < 0 {
        buffer.idx = 0
        break
      }
      buffer.idx = idx
      ignore(apply_lookup_here(ctx, lookup))
      if idx == 0 {
        break
      }
      buffer.idx = idx - 1
    }
  }
}
