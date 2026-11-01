// Shaping a run with the default shaper (harfrust's shape.rs): Unicode properties, clusters, normalization and
// glyph mapping, GSUB, advances, GPOS (or the old `kern` table), mark widths and default ignorables.

///|
/// A font to shape with: its face and the layout tables read from it, with plans kept by what they were made for.
pub struct ShapeFont {
  face : @font.Face
  priv ot : OtData
  priv plans : Array[(String, ShapePlan)]
}

///|
pub fn ShapeFont::new(face : @font.Face) -> ShapeFont {
  { face, ot: OtData::new(face), plans: [] }
}

///|
fn ShapeFont::plan(self : ShapeFont, direction : Direction, script : Int, features : Array[Feature]) -> ShapePlan {
  let key = StringBuilder::new()
  key.write_string("\{direction} \{script}")
  for f in features {
    key.write_string(" \{f.tag}=\{f.value}:\{f.start}:\{f.end}")
  }
  let key = key.to_string()
  for p in self.plans {
    if p.0 == key {
      return p.1
    }
  }
  let plan = ShapePlan::new(self.ot, direction, script, features)
  self.plans.push((key, plan))
  plan
}

///|
/// Shapes the buffer's characters into glyphs and positions, in font units. The buffer's direction is used as set;
/// its script is guessed from its characters when not set.
pub fn shape(font : ShapeFont, buffer : Buffer, features : Array[Feature]) -> Unit {
  buffer.guess_script()
  if buffer.len == 0 {
    return
  }
  let plan = font.plan(buffer.direction, buffer.script, features)
  let face = font.face
  let target_direction = buffer.direction
  buffer.ensure(buffer.len)
  set_unicode_props(buffer, plan.global_mask)
  form_clusters(buffer)
  ensure_native_direction(buffer)
  // substitute_pre
  rotate_chars(face, plan, buffer, target_direction)
  normalize(face, buffer, plan.shaper)
  setup_masks(plan, buffer)
  if plan.fallback_mark_positioning {
    recategorize_marks(buffer)
  }
  for i in 0..<buffer.len {
    buffer.info[i].glyph_id = buffer.info[i].normalizer_glyph_index()
  }
  for i in 0..<buffer.len {
    let info = buffer.info[i]
    info.set_glyph_props(plan.ot.glyph_props(info.glyph_id))
    info.set_lig_props(0)
  }
  if plan.fallback_glyph_classes {
    for i in 0..<buffer.len {
      let info = buffer.info[i]
      let class = if info.general_category() != GC_NON_SPACING_MARK || info.is_default_ignorable() {
        GPROPS_BASE_GLYPH
      } else {
        GPROPS_MARK
      }
      info.set_glyph_props(class)
    }
  }
  plan.apply_layout_table(buffer, true)
  // position
  buffer.clear_positions()
  let horizontal = buffer.direction.is_horizontal()
  for i in 0..<buffer.len {
    let g = buffer.info[i].glyph_id
    if horizontal {
      buffer.pos[i].x_advance = face.advance(g)
    } else {
      let v = match face.vertical_advance(g) {
        Some(v) => v
        None => {
          let m = face.metrics()
          (m.ascent - m.descent).to_int()
        }
      }
      buffer.pos[i].y_advance = -v
      buffer.pos[i].x_offset -= face.advance(g) / 2
      buffer.pos[i].y_offset -= face.metrics().ascent.to_int()
    }
  }
  if (buffer.scratch_flags & SCRATCH_HAS_SPACE_FALLBACK) != 0 {
    fallback_spaces(face, buffer)
  }
  let adjust_offsets = plan.adjust_mark_positioning_when_zeroing && buffer.direction.is_forward()
  position_start(buffer)
  if plan.apply_gpos {
    plan.apply_layout_table(buffer, false)
  }
  if plan.apply_kern {
    apply_kern_table(face, plan, buffer)
  }
  if plan.zero_marks {
    for i in 0..<buffer.len {
      if buffer.info[i].is_mark() {
        let pos = buffer.pos[i]
        if adjust_offsets {
          pos.x_offset -= pos.x_advance
          pos.y_offset -= pos.y_advance
        }
        pos.x_advance = 0
        pos.y_advance = 0
      }
    }
  }
  if (buffer.scratch_flags & SCRATCH_HAS_DEFAULT_IGNORABLES) != 0 {
    for i in 0..<buffer.len {
      if buffer.info[i].is_default_ignorable() {
        let pos = buffer.pos[i]
        pos.x_advance = 0
        pos.y_advance = 0
        if horizontal {
          pos.x_offset = 0
        } else {
          pos.y_offset = 0
        }
      }
    }
  }
  position_finish_offsets(buffer)
  if plan.fallback_mark_positioning {
    position_marks(face, plan, buffer, adjust_offsets)
  }
  if buffer.direction.is_backward() {
    buffer.reverse()
  }
  // substitute_post
  if (buffer.scratch_flags & SCRATCH_HAS_DEFAULT_IGNORABLES) != 0 {
    match nominal_glyph(face, 0x20) {
      Some(invisible) =>
        for i in 0..<buffer.len {
          if buffer.info[i].is_default_ignorable() {
            buffer.info[i].glyph_id = invisible
          }
        }
      None => buffer.delete_glyphs_inplace(fn(info) { info.is_default_ignorable() })
    }
  }
  buffer.direction = target_direction
}

///|
fn set_unicode_props(buffer : Buffer, global_mask : Int) -> Unit {
  let len = buffer.len
  let mut i = 0
  while i < len {
    let info = buffer.info[i]
    info.mask = global_mask
    info.init_unicode_props(buffer)
    if info.glyph_id < 0x80 {
      i += 1
      continue
    }
    let gc = info.general_category()
    if (
        gc_flag(gc) &
        (
          gc_flag(GC_LOWERCASE_LETTER) |
          gc_flag(GC_UPPERCASE_LETTER) |
          gc_flag(GC_TITLECASE_LETTER) |
          gc_flag(GC_OTHER_LETTER) |
          gc_flag(GC_SPACE_SEPARATOR)
        )
      ) !=
      0 {
      i += 1
      continue
    }
    let u = info.glyph_id
    if gc == GC_MODIFIER_SYMBOL && u >= 0x1F3FB && u <= 0x1F3FF {
      info.set_continuation(buffer)
    } else if i != 0 && u >= 0x1F1E6 && u <= 0x1F1FF {
      let prev = buffer.info[i - 1]
      if prev.glyph_id >= 0x1F1E6 && prev.glyph_id <= 0x1F1FF && !prev.is_continuation() {
        info.set_continuation(buffer)
      }
    } else if info.is_zwj() {
      info.set_continuation(buffer)
      if i + 1 < len {
        let next = buffer.info[i + 1]
        if is_emoji_extended_pictographic(next.glyph_id) {
          next.mask = global_mask
          next.init_unicode_props(buffer)
          next.set_continuation(buffer)
          i += 1
        }
      }
    } else if (u >= 0xFF9E && u <= 0xFF9F) || (u >= 0xE0020 && u <= 0xE007F) {
      info.set_continuation(buffer)
    } else if u == 0x2044 {
      buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_FRACTION_SLASH
    }
    i += 1
  }
}

///|
fn form_clusters(buffer : Buffer) -> Unit {
  if (buffer.scratch_flags & SCRATCH_HAS_CONTINUATIONS) == 0 {
    return
  }
  let mut start = 0
  while start < buffer.len {
    let end = buffer.group_end(start, grapheme_group)
    buffer.merge_clusters(start, end)
    start = end
  }
}

///|
/// The direction a script is written in: 1 left to right, -1 right to left, 0 either.
fn script_direction(script : Int) -> Int {
  let rtl = [
    "Arab", "Hebr", "Syrc", "Thaa", "Cprt", "Khar", "Phnx", "Nkoo", "Lydi", "Avst",
    "Armi", "Phli", "Prti", "Sarb", "Orkh", "Samr", "Mand", "Merc", "Mero", "Mani",
    "Mend", "Nbat", "Narb", "Palm", "Phlp", "Hatr", "Adlm", "Rohg", "Sogo", "Sogd",
    "Elym", "Chrs", "Yezi", "Ougr", "Gara", "Sidt",
  ]
  for t in rtl {
    if tag(t) == script {
      return -1
    }
  }
  for t in ["Hung", "Ital", "Runr", "Tfng"] {
    if tag(t) == script {
      return 0
    }
  }
  1
}

///|
fn ensure_native_direction(buffer : Buffer) -> Unit {
  let dir = buffer.direction
  let mut hor = if buffer.script == 0 { 1 } else { script_direction(buffer.script) }
  if hor == -1 && dir == LeftToRight {
    let mut found_number = false
    let mut found_letter = false
    let mut found_ri = false
    for i in 0..<buffer.len {
      let info = buffer.info[i]
      let gc = info.general_category()
      if gc == GC_DECIMAL_NUMBER {
        found_number = true
      } else if gc >= GC_LOWERCASE_LETTER && gc <= GC_UPPERCASE_LETTER {
        found_letter = true
        break
      } else if info.glyph_id >= 0x1F1E6 && info.glyph_id <= 0x1F1FF {
        found_ri = true
      }
    }
    if (found_number || found_ri) && !found_letter {
      hor = 1
    }
  }
  let native = if hor == 1 { LeftToRight } else { RightToLeft }
  if (dir.is_horizontal() && hor != 0 && dir != native) || (!dir.is_horizontal() && dir != TopToBottom) {
    reverse_graphemes(buffer)
    buffer.direction = match dir {
      LeftToRight => RightToLeft
      RightToLeft => LeftToRight
      TopToBottom => BottomToTop
      BottomToTop => TopToBottom
    }
  }
}

///|
fn rotate_chars(face : @font.Face, plan : ShapePlan, buffer : Buffer, target : Direction) -> Unit {
  if target.is_backward() {
    for i in 0..<buffer.len {
      let info = buffer.info[i]
      match mirroring(info.glyph_id) {
        Some(c) if nominal_glyph(face, c) is Some(_) => {
          info.glyph_id = c
          continue
        }
        _ => ()
      }
      info.mask = info.mask | plan.rtlm_mask
    }
  }
}

///|
fn setup_masks(plan : ShapePlan, buffer : Buffer) -> Unit {
  if (buffer.scratch_flags & SCRATCH_HAS_FRACTION_SLASH) != 0 && plan.has_frac {
    let (pre_mask, post_mask) = if buffer.direction.is_forward() {
      (plan.numr_mask | plan.frac_mask, plan.frac_mask | plan.dnom_mask)
    } else {
      (plan.frac_mask | plan.dnom_mask, plan.numr_mask | plan.frac_mask)
    }
    let len = buffer.len
    let mut i = 0
    while i < len {
      if buffer.info[i].glyph_id == 0x2044 {
        let mut start = i
        while start > 0 && buffer.info[start - 1].general_category() == GC_DECIMAL_NUMBER {
          start -= 1
        }
        let mut end = i + 1
        while end < len && buffer.info[end].general_category() == GC_DECIMAL_NUMBER {
          end += 1
        }
        if start == i || end == i + 1 {
          i += 1
          continue
        }
        for k in start..<i {
          buffer.info[k].mask = buffer.info[k].mask | pre_mask
        }
        buffer.info[i].mask = buffer.info[i].mask | plan.frac_mask
        for k in (i + 1)..<end {
          buffer.info[k].mask = buffer.info[k].mask | post_mask
        }
        i = end
      } else {
        i += 1
      }
    }
  }
  if plan.shaper == SHAPER_ARABIC {
    arabic_setup_masks(plan, buffer)
  }
  for f in plan.user_features {
    if !f.is_global() {
      let (mask, shift) = plan.get_mask(f.tag)
      buffer.set_masks(f.value << shift, mask, f.start, f.end)
    }
  }
}

///|
/// The old `kern` table's pairs, split between the two glyphs (aat/kern.rs, its format 0 subtables).
fn apply_kern_table(face : @font.Face, plan : ShapePlan, buffer : Buffer) -> Unit {
  if !plan.requested_kerning || !buffer.direction.is_horizontal() {
    return
  }
  let reverse = buffer.direction.is_backward()
  if reverse {
    buffer.reverse()
  }
  let ctx = ApplyContext::new(false, plan.ot, buffer)
  ctx.set_lookup_mask(plan.kern_mask)
  ctx.lookup_props = LOOKUP_IGNORE_MARKS
  ctx.update_matchers()
  let iter = SkippingIterator::new(ctx, false, None)
  let mut i = 0
  while i < buffer.len {
    if (buffer.info[i].mask & plan.kern_mask) == 0 {
      i += 1
      continue
    }
    iter.buf_idx = i
    let (ok, unsafe_to) = iter.next()
    if !ok {
      i = unsafe_to
      continue
    }
    let j = iter.buf_idx
    let kern = face.kerning(buffer.info[i].glyph_id, buffer.info[j].glyph_id)
    if kern != 0 {
      let kern1 = kern >> 1
      let kern2 = kern - kern1
      buffer.pos[i].x_advance += kern1
      buffer.pos[j].x_advance += kern2
      buffer.pos[j].x_offset += kern2
    }
    i = j
  }
  if reverse {
    buffer.reverse()
  }
}

///|
fn fallback_spaces(face : @font.Face, buffer : Buffer) -> Unit {
  let upem = face.units_per_em()
  let horizontal = buffer.direction.is_horizontal()
  for i in 0..<buffer.len {
    let info = buffer.info[i]
    let pos = buffer.pos[i]
    if !info.is_unicode_space() || info.ligated() {
      continue
    }
    let t = info.space_fallback_type()
    let set = fn(v : Int) {
      if horizontal {
        pos.x_advance = v
      } else {
        pos.y_advance = -v
      }
    }
    match t {
      1 | 2 | 3 | 4 | 5 | 6 | 16 => set((upem + t / 2) / t)
      17 => set(upem * 4 / 18)
      19 =>
        for u in 0x30..=0x39 {
          match nominal_glyph(face, u) {
            Some(g) => {
              if horizontal {
                pos.x_advance = face.advance(g)
              }
              break
            }
            None => ()
          }
        }
      20 => {
        let punct = match nominal_glyph(face, 0x2E) {
          Some(g) => Some(g)
          None => nominal_glyph(face, 0x2C)
        }
        match punct {
          Some(g) => if horizontal { pos.x_advance = face.advance(g) }
          None => ()
        }
      }
      21 =>
        if horizontal {
          pos.x_advance = pos.x_advance / 2
        } else {
          pos.y_advance = pos.y_advance / 2
        }
      _ => ()
    }
  }
}
