// GSUB's subtables (harfrust's ot/lookup/gsub.rs): single, multiple, alternate and ligature substitution, the
// contexts (context.mbt) and reverse chaining.

///|
fn apply_gsub_subtable(ctx : ApplyContext, kind : Int, s : Int, index : Int) -> Bool {
  let d = ctx.ot.data
  let format = rd16(d, s)
  match kind {
    1 =>
      if format == 1 {
        let delta = rds16(d, s + 4)
        ctx.replace_glyph((ctx.buffer.cur(0).glyph_id + delta) & 0xFFFF)
        true
      } else if format == 2 {
        if index >= rd16(d, s + 4) {
          return false
        }
        ctx.replace_glyph(rd16(d, s + 6 + index * 2))
        true
      } else {
        false
      }
    2 => {
      if format != 1 || index >= rd16(d, s + 4) {
        return false
      }
      let seq = off16(d, s, s + 6 + index * 2)
      if seq == 0 {
        return false
      }
      let count = rd16(d, seq)
      if count == 0 {
        ctx.buffer.delete_glyph()
      } else if count == 1 {
        ctx.replace_glyph(rd16(d, seq + 2))
      } else {
        let class = if ctx.buffer.cur(0).is_ligature() { GPROPS_BASE_GLYPH } else { 0 }
        let lig_id = ctx.buffer.cur(0).lig_id()
        for i in 0..<count {
          if lig_id == 0 {
            ctx.buffer.cur(0).set_lig_props_for_component(i)
          }
          ctx.output_glyph_for_component(rd16(d, seq + 2 + i * 2), class)
        }
        ctx.buffer.skip_glyph()
      }
      true
    }
    3 => {
      if format != 1 || index >= rd16(d, s + 4) {
        return false
      }
      let set = off16(d, s, s + 6 + index * 2)
      if set == 0 {
        return false
      }
      let count = rd16(d, set)
      if count == 0 {
        return false
      }
      let glyph_mask = ctx.buffer.cur(0).mask
      let lookup_mask = ctx.lookup_mask
      let mut alt_index = (lookup_mask & glyph_mask).reinterpret_as_uint() >>
        lookup_mask.ctz()
      if alt_index == 255 && ctx.random {
        alt_index = (ctx.random_number() % count + 1).reinterpret_as_uint()
      }
      let i = alt_index.reinterpret_as_int()
      if i < 1 || i > 0xFFFF || i - 1 >= count {
        return false
      }
      ctx.replace_glyph(rd16(d, set + 2 + (i - 1) * 2))
      true
    }
    4 => {
      if format != 1 || index >= rd16(d, s + 4) {
        return false
      }
      let set = off16(d, s, s + 6 + index * 2)
      if set == 0 {
        return false
      }
      apply_ligature_set(ctx, set)
    }
    5 => apply_context(ctx, s, false)
    6 => apply_context(ctx, s, true)
    8 => apply_reverse_chain(ctx, s, index)
    _ => false
  }
}

///|
fn apply_ligature_set(ctx : ApplyContext, set : Int) -> Bool {
  let d = ctx.ot.data
  let count = rd16(d, set)
  // The glyph after this one, when it cannot be skipped: ligatures whose second component is another need not be
  // tried (as harfrust does; the outcome is the same as trying them).
  let mut second = -1
  if count > 1 {
    let iter = SkippingIterator::new(ctx, true, Some(fn(_i, _v) { true }))
    iter.reset(ctx.buffer.idx)
    let (ok, _) = iter.next()
    if ok {
      let info = ctx.buffer.info[iter.buf_idx]
      if iter.may_skip(info) == NO {
        second = info.glyph_id
      }
    }
  }
  for i in 0..<count {
    let lig = off16(d, set, set + 2 + i * 2)
    if lig == 0 {
      continue
    }
    let comp_count = rd16(d, lig + 2)
    if second >= 0 && comp_count > 1 && rd16(d, lig + 4) != second {
      continue
    }
    if apply_ligature(ctx, lig) {
      return true
    }
  }
  false
}

///|
fn apply_ligature(ctx : ApplyContext, lig : Int) -> Bool {
  let d = ctx.ot.data
  let glyph = rd16(d, lig)
  let comp_count = rd16(d, lig + 2)
  let n = if comp_count > 0 { comp_count - 1 } else { 0 }
  if n == 0 {
    ctx.replace_glyph(glyph)
    return true
  }
  let (ok, match_end, total) = match_input(ctx, n, fn(info, i) {
    i < n && info.glyph_id == rd16(d, lig + 4 + i * 2)
  })
  if !ok {
    return false
  }
  ligate_input(ctx, n + 1, match_end, total, glyph)
  true
}

///|
fn apply_reverse_chain(ctx : ApplyContext, s : Int, index : Int) -> Bool {
  if ctx.nesting_level_left != MAX_NESTING_LEVEL {
    return false
  }
  let d = ctx.ot.data
  if rd16(d, s) != 1 {
    return false
  }
  let back = rd16(d, s + 4)
  let back_at = s + 6
  let ahead = rd16(d, back_at + back * 2)
  let ahead_at = back_at + back * 2 + 2
  let subst_count = rd16(d, ahead_at + ahead * 2)
  let subst_at = ahead_at + ahead * 2 + 2
  if index >= subst_count {
    return false
  }
  let substitute = rd16(d, subst_at + index * 2)
  let (ok1, _) = match_backtrack(ctx, back, fn(info, i) {
    coverage_get(d, off16(d, s, back_at + i * 2), info.glyph_id) >= 0
  })
  if !ok1 {
    return false
  }
  let (ok2, _) = match_lookahead(
    ctx,
    ahead,
    fn(info, i) { coverage_get(d, off16(d, s, ahead_at + i * 2), info.glyph_id) >= 0 },
    ctx.buffer.idx + 1,
  )
  if !ok2 {
    return false
  }
  ctx.replace_glyph_inplace(substitute)
  true
}
