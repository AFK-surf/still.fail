// GPOS's subtables (harfrust's ot/lookup/gpos.rs, ot/gpos/mod.rs): single and pair adjustment, cursive
// attachment, marks on bases, ligatures and marks, and propagating attachments into offsets at the end.

///|
const ATTACH_MARK : Int = 1

///|
const ATTACH_CURSIVE : Int = 2

///|
fn value_size(format : Int) -> Int {
  (format & 0xFF).popcnt() * 2
}

///|
/// Adds the value record at `at` (of `format`) to the glyph at `idx`; answers whether it changed something.
fn apply_value(ctx : ApplyContext, idx : Int, at : Int, format : Int, base : Int) -> Bool {
  let d = ctx.ot.data
  let horizontal = ctx.buffer.direction.is_horizontal()
  if idx >= ctx.buffer.pos.length() {
    return false
  }
  let pos = ctx.buffer.pos[idx]
  let mut p = at
  let mut worked = false
  if (format & 0x01) != 0 {
    let v = rds16(d, p)
    p += 2
    pos.x_offset += v
    worked = worked || v != 0
  }
  if (format & 0x02) != 0 {
    let v = rds16(d, p)
    p += 2
    pos.y_offset += v
    worked = worked || v != 0
  }
  if (format & 0x04) != 0 {
    let v = rds16(d, p)
    p += 2
    if horizontal {
      pos.x_advance += v
      worked = worked || v != 0
    }
  }
  if (format & 0x08) != 0 {
    let v = rds16(d, p)
    p += 2
    if !horizontal {
      pos.y_advance -= v
      worked = worked || v != 0
    }
  }
  if (format & 0xF0) == 0 || ctx.ot.coords.length() == 0 || ctx.ot.face.gdef_var_store() == 0 {
    return worked
  }
  // the variation deltas of the device fields, from the record's parent table
  let delta = fn(applies : Bool) -> Float? {
    let device = rd16(d, p)
    p += 2
    if !applies {
      return None
    }
    let v = ctx.ot.device_delta(if device == 0 { 0 } else { base + device })
    worked = worked || v != 0.0
    Some(v)
  }
  if (format & 0x10) != 0 {
    match delta(true) {
      Some(v) => pos.x_offset += round_f(v)
      None => ()
    }
  }
  if (format & 0x20) != 0 {
    match delta(true) {
      Some(v) => pos.y_offset += round_f(v)
      None => ()
    }
  }
  if (format & 0x40) != 0 {
    match delta(horizontal) {
      Some(v) => pos.x_advance += round_f(v)
      None => ()
    }
  }
  if (format & 0x80) != 0 {
    match delta(!horizontal) {
      Some(v) => pos.y_advance -= round_f(v)
      None => ()
    }
  }
  worked
}

///|
fn apply_gpos_subtable(ctx : ApplyContext, kind : Int, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  let format = rd16(d, s)
  match kind {
    1 => {
      let vf = rd16(d, s + 4)
      if format == 1 {
        ignore(apply_value(ctx, ctx.buffer.idx, s + 6, vf, s))
      } else if format == 2 {
        if index >= rd16(d, s + 6) {
          return false
        }
        ignore(apply_value(ctx, ctx.buffer.idx, s + 8 + index * value_size(vf), vf, s))
      } else {
        return false
      }
      ctx.buffer.idx += 1
      true
    }
    2 => apply_pair_pos(ctx, s, index)
    3 => apply_cursive(ctx, s, index)
    4 => apply_mark_base(ctx, s, index)
    5 => apply_mark_lig(ctx, s, index)
    6 => apply_mark_mark(ctx, s, index)
    7 => apply_context(ctx, s, false)
    8 => apply_context(ctx, s, true)
    _ => false
  }
}

///|
fn apply_pair(ctx : ApplyContext, second : Int, at1 : Int, vf1 : Int, at2 : Int, vf2 : Int, base : Int) -> Bool {
  if vf1 != 0 {
    ignore(apply_value(ctx, ctx.buffer.idx, at1, vf1, base))
  }
  let mut buf_idx = second
  if vf2 != 0 {
    ignore(apply_value(ctx, second, at2, vf2, base))
    buf_idx += 1
  }
  ctx.buffer.idx = buf_idx
  true
}

///|
fn apply_pair_pos(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  let format = rd16(d, s)
  let vf1 = rd16(d, s + 4)
  let vf2 = rd16(d, s + 6)
  let len1 = value_size(vf1)
  let len2 = value_size(vf2)
  if format != 1 && format != 2 {
    return false
  }
  if format == 2 {
    // a matrix that does not fit leaves the subtable out
    let c1 = rd16(d, s + 12)
    let c2 = rd16(d, s + 14)
    if s + 16 + c1 * c2 * (len1 + len2) > d.length() {
      return false
    }
  }
  let iter = SkippingIterator::new(ctx, false, None)
  iter.reset(ctx.buffer.idx)
  let (ok, _) = iter.next()
  if !ok {
    return false
  }
  let second_index = iter.buf_idx
  let second = ctx.buffer.info[second_index].glyph_id
  if format == 1 {
    if index >= rd16(d, s + 8) {
      return false
    }
    let set = off16(d, s, s + 10 + index * 2)
    if set == 0 {
      return false
    }
    let record_len = 2 + len1 + len2
    let mut lo = 0
    let mut hi = rd16(d, set)
    while lo < hi {
      let mid = (lo + hi) / 2
      let r = set + 2 + mid * record_len
      let g = rd16(d, r)
      if g < second {
        lo = mid + 1
      } else if g > second {
        hi = mid
      } else {
        return apply_pair(ctx, second_index, r + 2, vf1, r + 2 + len1, vf2, set)
      }
    }
    false
  } else {
    let class1 = class_get(d, off16(d, s, s + 8), ctx.buffer.cur(0).glyph_id)
    let class2 = class_get(d, off16(d, s, s + 10), second)
    let c1 = rd16(d, s + 12)
    let c2 = rd16(d, s + 14)
    if class1 >= c1 || class2 >= c2 {
      return false
    }
    let r = s + 16 + (class1 * c2 + class2) * (len1 + len2)
    apply_pair(ctx, second_index, r, vf1, r + len1, vf2, s)
  }
}

///|
fn reverse_cursive_minor_offset(pos : Array[GlyphPosition], i : Int, direction : Direction, new_parent : Int) -> Unit {
  let this = pos[i]
  let chain = this.attach_chain()
  let attach_type = this.attach_type()
  if chain == 0 || (attach_type & ATTACH_CURSIVE) == 0 {
    return
  }
  this.set_attach_chain(0)
  let j = i + chain
  if j < 0 || j >= pos.length() || j == new_parent {
    return
  }
  reverse_cursive_minor_offset(pos, j, direction, new_parent)
  let offset = if direction.is_horizontal() { this.y_offset } else { this.x_offset }
  let next = pos[j]
  if direction.is_horizontal() {
    next.y_offset = -offset
  } else {
    next.x_offset = -offset
  }
  next.set_attach_chain(-chain)
  next.set_attach_type(attach_type)
}

///|
fn apply_cursive(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  if rd16(d, s) != 1 || index >= rd16(d, s + 4) {
    return false
  }
  let entry_this = off16(d, s, s + 6 + index * 4)
  if entry_this == 0 {
    return false
  }
  let buffer = ctx.buffer
  let iter = SkippingIterator::new(ctx, false, None)
  iter.buf_idx = buffer.idx
  let (ok, _) = iter.prev()
  if !ok {
    return false
  }
  let i = iter.buf_idx
  let index_prev = coverage_get(d, off16(d, s, s + 2), buffer.info[i].glyph_id)
  if index_prev < 0 || index_prev >= rd16(d, s + 4) {
    return false
  }
  let exit_prev = off16(d, s, s + 6 + index_prev * 4 + 2)
  if exit_prev == 0 {
    return false
  }
  let (exit_x, exit_y) = ctx.ot.anchor(exit_prev)
  let (entry_x, entry_y) = ctx.ot.anchor(entry_this)
  let (exit_x, exit_y) = (round_f(exit_x), round_f(exit_y))
  let (entry_x, entry_y) = (round_f(entry_x), round_f(entry_y))
  let direction = buffer.direction
  let j = buffer.idx
  let pos = buffer.pos
  let prev_pos = pos[i]
  let this_pos = pos[j]
  match direction {
    LeftToRight => {
      prev_pos.x_advance = exit_x + prev_pos.x_offset
      let dd = entry_x + this_pos.x_offset
      this_pos.x_advance -= dd
      this_pos.x_offset -= dd
    }
    RightToLeft => {
      let dd = exit_x + prev_pos.x_offset
      prev_pos.x_advance -= dd
      prev_pos.x_offset -= dd
      this_pos.x_advance = entry_x + this_pos.x_offset
    }
    TopToBottom => {
      prev_pos.y_advance = exit_y + prev_pos.y_offset
      let dd = entry_y + this_pos.y_offset
      this_pos.y_advance -= dd
      this_pos.y_offset -= dd
    }
    BottomToTop => {
      let dd = exit_y + prev_pos.y_offset
      prev_pos.y_advance -= dd
      prev_pos.y_offset -= dd
      this_pos.y_advance = entry_y
    }
  }
  let mut child = i
  let mut parent = j
  let mut x_offset = entry_x - exit_x
  let mut y_offset = entry_y - exit_y
  if (ctx.lookup_props & LOOKUP_RIGHT_TO_LEFT) == 0 {
    child = j
    parent = i
    x_offset = -x_offset
    y_offset = -y_offset
  }
  reverse_cursive_minor_offset(pos, child, direction, parent)
  let child_pos = pos[child]
  child_pos.set_attach_type(ATTACH_CURSIVE)
  let chain = parent - child
  child_pos.set_attach_chain(chain)
  if child_pos.attach_chain() != chain {
    child_pos.set_attach_chain(0)
  }
  if direction.is_horizontal() {
    child_pos.y_offset = y_offset
  } else {
    child_pos.x_offset = x_offset
  }
  let child_chain = child_pos.attach_chain()
  buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_GPOS_ATTACHMENT
  let parent_pos = pos[parent]
  if parent_pos.attach_chain() == -child_chain {
    parent_pos.set_attach_chain(0)
    if direction.is_horizontal() {
      parent_pos.y_offset = 0
    } else {
      parent_pos.x_offset = 0
    }
  }
  buffer.idx += 1
  true
}

///|
fn cross_offset(pos : Array[GlyphPosition], index : Int, direction : Direction) -> Int {
  let cross = fn(p : GlyphPosition) { if direction.is_horizontal() { p.y_offset } else { p.x_offset } }
  let mut i = index
  let mut this = pos[i]
  let mut offset = cross(this)
  while (this.attach_type() & ATTACH_CURSIVE) != 0 && this.attach_chain() != 0 {
    let parent = i + this.attach_chain()
    if parent < 0 || parent >= pos.length() {
      break
    }
    i = parent
    this = pos[i]
    offset += cross(this)
  }
  offset
}

///|
fn attach_mark(ctx : ApplyContext, base_anchor : Int, mark_anchor : Int, base_pos : Int) -> Bool {
  let (base_x, base_y) = ctx.ot.anchor(base_anchor)
  let (mark_x, mark_y) = ctx.ot.anchor(mark_anchor)
  let buffer = ctx.buffer
  let base_offset = cross_offset(buffer.pos, base_pos, buffer.direction)
  let idx = buffer.idx
  let chain = base_pos - idx
  let pos = buffer.pos[idx]
  if chain < -0x8000 || chain > 0x7FFF {
    pos.set_attach_chain(0)
    buffer.idx += 1
    return true
  }
  pos.x_offset = round_f(base_x - mark_x)
  pos.y_offset = round_f(base_y - mark_y)
  if buffer.direction.is_horizontal() {
    pos.y_offset += base_offset
  } else {
    pos.x_offset += base_offset
  }
  pos.set_attach_type(ATTACH_MARK)
  pos.set_attach_chain(chain)
  buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_GPOS_ATTACHMENT
  buffer.idx += 1
  true
}

///|
fn find_mark_base(ctx : ApplyContext, accept : (Buffer, Int) -> Bool, coverage : Int) -> Int {
  let buffer = ctx.buffer
  if ctx.last_base_until > buffer.idx {
    ctx.last_base_until = 0
    ctx.last_base = -1
  }
  let mut last_base = ctx.last_base
  let iter = SkippingIterator::new(ctx, false, None)
  iter.lookup_props = LOOKUP_IGNORE_MARKS
  let mut j = buffer.idx
  while j > ctx.last_base_until {
    let mut matched = iter.match_at(j - 1)
    if matched == MATCH &&
      !accept(buffer, j - 1) &&
      coverage_get(ctx.ot.data, coverage, buffer.info[j - 1].glyph_id) < 0 {
      matched = SKIP
    }
    if matched == MATCH {
      last_base = j - 1
      break
    }
    j -= 1
  }
  ctx.last_base_until = buffer.idx
  ctx.last_base = last_base
  last_base
}

///|
fn accept_base(buffer : Buffer, idx : Int) -> Bool {
  let info = buffer.info[idx]
  if !info.multiplied() || info.lig_comp() == 0 || idx == 0 {
    return true
  }
  let prev = buffer.info[idx - 1]
  prev.is_mark() ||
  !prev.multiplied() ||
  info.lig_id() != prev.lig_id() ||
  info.lig_comp() != prev.lig_comp() + 1
}

///|
fn accept_ligature(buffer : Buffer, idx : Int) -> Bool {
  let info = buffer.info[idx]
  !info.multiplied() || info.lig_comp() == 0
}

///|
/// The anchor and class of mark `index` in the mark array at `marks`.
fn mark_record(d : Bytes, marks : Int, index : Int) -> (Int, Int)? {
  if marks == 0 || index >= rd16(d, marks) {
    return None
  }
  let r = marks + 2 + index * 4
  let anchor = off16(d, marks, r + 2)
  if anchor == 0 {
    return None
  }
  Some((anchor, rd16(d, r)))
}

///|
/// The anchor at (`row`, `column`) of an anchor matrix at `at` with `columns` columns.
fn anchor_at(d : Bytes, at : Int, columns : Int, row : Int, column : Int) -> Int {
  if at == 0 || row >= rd16(d, at) || column >= columns {
    return 0
  }
  off16(d, at, at + 2 + (row * columns + column) * 2)
}

///|
fn apply_mark_base(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  if rd16(d, s) != 1 {
    return false
  }
  let base_cov = off16(d, s, s + 4)
  if base_cov == 0 {
    return false
  }
  let base_pos = find_mark_base(ctx, accept_base, base_cov)
  if base_pos < 0 {
    return false
  }
  let base_index = coverage_get(d, base_cov, ctx.buffer.info[base_pos].glyph_id)
  if base_index < 0 {
    return false
  }
  guard mark_record(d, off16(d, s, s + 8), index) is Some((mark_anchor, class)) else { return false }
  let base_anchor = anchor_at(d, off16(d, s, s + 10), rd16(d, s + 6), base_index, class)
  if base_anchor == 0 {
    return false
  }
  attach_mark(ctx, base_anchor, mark_anchor, base_pos)
}

///|
fn apply_mark_lig(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  if rd16(d, s) != 1 {
    return false
  }
  let lig_cov = off16(d, s, s + 4)
  if lig_cov == 0 {
    return false
  }
  let lig_pos = find_mark_base(ctx, accept_ligature, lig_cov)
  if lig_pos < 0 {
    return false
  }
  let lig_info = ctx.buffer.info[lig_pos]
  let lig_id = lig_info.lig_id()
  let lig_index = coverage_get(d, lig_cov, lig_info.glyph_id)
  if lig_index < 0 {
    return false
  }
  let ligatures = off16(d, s, s + 10)
  if ligatures == 0 || lig_index >= rd16(d, ligatures) {
    return false
  }
  let attach = off16(d, ligatures, ligatures + 2 + lig_index * 2)
  if attach == 0 {
    return false
  }
  let comp_count = rd16(d, attach)
  if comp_count == 0 {
    return false
  }
  let cur = ctx.buffer.cur(0)
  let mark_id = cur.lig_id()
  let mark_comp = cur.lig_comp()
  let comp_index = (if lig_id != 0 && lig_id == mark_id && mark_comp > 0 {
    if mark_comp < comp_count {
      mark_comp
    } else {
      comp_count
    }
  } else {
    comp_count
  }) -
    1
  guard mark_record(d, off16(d, s, s + 8), index) is Some((mark_anchor, class)) else { return false }
  let base_anchor = anchor_at(d, attach, rd16(d, s + 6), comp_index, class)
  if base_anchor == 0 {
    return false
  }
  attach_mark(ctx, base_anchor, mark_anchor, lig_pos)
}

///|
fn apply_mark_mark(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  if rd16(d, s) != 1 {
    return false
  }
  let buffer = ctx.buffer
  let iter = SkippingIterator::new(ctx, false, None)
  iter.buf_idx = buffer.idx
  iter.lookup_props = ctx.lookup_props & (LOOKUP_IGNORE_FLAGS ^ -1)
  let (ok, _) = iter.prev()
  if !ok {
    return false
  }
  let mark2_pos = iter.buf_idx
  let mark2 = buffer.info[mark2_pos]
  if !mark2.is_mark() {
    return false
  }
  let cur = buffer.cur(0)
  let id1 = cur.lig_id()
  let comp1 = cur.lig_comp()
  let id2 = mark2.lig_id()
  let comp2 = mark2.lig_comp()
  let matches = if id1 == id2 {
    id1 == 0 || comp1 == comp2
  } else {
    (id1 > 0 && comp1 == 0) || (id2 > 0 && comp2 == 0)
  }
  if !matches {
    return false
  }
  let mark2_index = coverage_get(d, off16(d, s, s + 4), mark2.glyph_id)
  if mark2_index < 0 {
    return false
  }
  guard mark_record(d, off16(d, s, s + 8), index) is Some((mark1_anchor, class)) else { return false }
  let mark2_anchor = anchor_at(d, off16(d, s, s + 10), rd16(d, s + 6), mark2_index, class)
  if mark2_anchor == 0 {
    return false
  }
  attach_mark(ctx, mark2_anchor, mark1_anchor, mark2_pos)
}

///|
fn position_start(buffer : Buffer) -> Unit {
  for i in 0..<buffer.len {
    buffer.pos[i].set_attach_chain(0)
    buffer.pos[i].set_attach_type(0)
  }
}

///|
fn propagate_attachment_offsets(pos : Array[GlyphPosition], len : Int, i : Int, direction : Direction, nesting : Int) -> Unit {
  let this = pos[i]
  let chain = this.attach_chain()
  let kind = this.attach_type()
  this.set_attach_chain(0)
  let j = i + chain
  if j < 0 || j >= len || nesting == 0 {
    return
  }
  if pos[j].attach_chain() != 0 {
    propagate_attachment_offsets(pos, len, j, direction, nesting - 1)
  }
  let parent = pos[j]
  if kind == ATTACH_MARK {
    if direction.is_horizontal() {
      this.x_offset += parent.x_offset
    } else {
      this.y_offset += parent.y_offset
    }
    if j < i {
      if direction.is_forward() {
        for k in j..<i {
          this.x_offset -= pos[k].x_advance
          this.y_offset -= pos[k].y_advance
        }
      } else {
        for k in (j + 1)..<(i + 1) {
          this.x_offset += pos[k].x_advance
          this.y_offset += pos[k].y_advance
        }
      }
    } else if direction.is_forward() {
      for k in i..<j {
        this.x_offset += pos[k].x_advance
        this.y_offset += pos[k].y_advance
      }
    } else {
      for k in (i + 1)..<(j + 1) {
        this.x_offset -= pos[k].x_advance
        this.y_offset -= pos[k].y_advance
      }
    }
  } else if kind == ATTACH_CURSIVE {
    if direction.is_horizontal() {
      this.y_offset += parent.y_offset
    } else {
      this.x_offset += parent.x_offset
    }
  }
}

///|
fn position_finish_offsets(buffer : Buffer) -> Unit {
  if (buffer.scratch_flags & SCRATCH_HAS_GPOS_ATTACHMENT) == 0 {
    return
  }
  let len = buffer.len
  let pos = buffer.pos
  if buffer.direction.is_forward() {
    for i in 0..<len {
      if pos[i].attach_chain() != 0 {
        propagate_attachment_offsets(pos, len, i, buffer.direction, MAX_NESTING_LEVEL)
      }
    }
  } else {
    let mut i = len - 1
    while i >= 0 {
      if pos[i].attach_chain() != 0 {
        propagate_attachment_offsets(pos, len, i, buffer.direction, MAX_NESTING_LEVEL)
      }
      i -= 1
    }
  }
}
