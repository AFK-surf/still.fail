// Context and chained context subtables, for both GSUB and GPOS (harfrust's ot/lookup/context.rs): by glyphs,
// by classes and by coverages. The rules of a set are tried in order; the first that matches applies its lookups.

///|
fn read_records(d : Bytes, at : Int, count : Int) -> Array[(Int, Int)] {
  Array::makei(count, fn(i) { (rd16(d, at + i * 4), rd16(d, at + i * 4 + 2)) })
}

///|
priv struct ContextRule {
  backtrack : Array[Int]
  input : Array[Int]
  lookahead : Array[Int]
  records : Array[(Int, Int)]
  chained : Bool
}

///|
fn read_rule(d : Bytes, r : Int, chained : Bool) -> ContextRule {
  if !chained {
    let glyph_count = rd16(d, r)
    let record_count = rd16(d, r + 2)
    let n = if glyph_count > 0 { glyph_count - 1 } else { 0 }
    {
      backtrack: [],
      input: Array::makei(n, fn(i) { rd16(d, r + 4 + i * 2) }),
      lookahead: [],
      records: read_records(d, r + 4 + n * 2, record_count),
      chained,
    }
  } else {
    let back = rd16(d, r)
    let back_end = r + 2 + back * 2
    let input_count = rd16(d, back_end)
    let n = if input_count > 0 { input_count - 1 } else { 0 }
    let input_end = back_end + 2 + n * 2
    let ahead = rd16(d, input_end)
    let ahead_end = input_end + 2 + ahead * 2
    let record_count = rd16(d, ahead_end)
    {
      backtrack: Array::makei(back, fn(i) { rd16(d, r + 2 + i * 2) }),
      input: Array::makei(n, fn(i) { rd16(d, back_end + 2 + i * 2) }),
      lookahead: Array::makei(ahead, fn(i) { rd16(d, input_end + 2 + i * 2) }),
      records: read_records(d, ahead_end + 2, record_count),
      chained,
    }
  }
}

///|
/// Applies a rule, its values matched against glyphs by `backtrack`, `input` and `lookahead`.
fn apply_rule(
  ctx : ApplyContext,
  rule : ContextRule,
  backtrack : (GlyphInfo, Int) -> Bool,
  input : (GlyphInfo, Int) -> Bool,
  lookahead : (GlyphInfo, Int) -> Bool,
) -> Bool {
  let (ok, match_end, _) = match_input(ctx, rule.input.length(), fn(info, i) {
    i < rule.input.length() && input(info, rule.input[i])
  })
  if !ok {
    return false
  }
  if !rule.chained {
    apply_lookup(ctx, rule.input.length(), match_end, rule.records)
    return true
  }
  let (ok2, _) = match_lookahead(
    ctx,
    rule.lookahead.length(),
    fn(info, i) { i < rule.lookahead.length() && lookahead(info, rule.lookahead[i]) },
    match_end,
  )
  if !ok2 {
    return false
  }
  let (ok3, _) = match_backtrack(ctx, rule.backtrack.length(), fn(info, i) {
    i < rule.backtrack.length() && backtrack(info, rule.backtrack[i])
  })
  if !ok3 {
    return false
  }
  apply_lookup(ctx, rule.input.length(), match_end, rule.records)
  true
}

///|
fn apply_rule_set(
  ctx : ApplyContext,
  set : Int,
  chained : Bool,
  backtrack : (GlyphInfo, Int) -> Bool,
  input : (GlyphInfo, Int) -> Bool,
  lookahead : (GlyphInfo, Int) -> Bool,
) -> Bool {
  let d = ctx.ot.data
  if set == 0 {
    return false
  }
  for i in 0..<rd16(d, set) {
    let r = off16(d, set, set + 2 + i * 2)
    if r == 0 {
      continue
    }
    if apply_rule(ctx, read_rule(d, r, chained), backtrack, input, lookahead) {
      return true
    }
  }
  false
}

///|
fn apply_context(ctx : ApplyContext, s : Int, chained : Bool) -> Bool {
  let d = ctx.ot.data
  let by_glyph = fn(info : GlyphInfo, v : Int) { info.glyph_id == v }
  match rd16(d, s) {
    1 => {
      let count = rd16(d, s + 4)
      let index = coverage_get(d, off16(d, s, s + 2), ctx.buffer.cur(0).glyph_id)
      if index < 0 || index >= count {
        return false
      }
      apply_rule_set(ctx, off16(d, s, s + 6 + index * 2), chained, by_glyph, by_glyph, by_glyph)
    }
    2 => {
      let (back_cd, input_cd, ahead_cd, count, sets) = if chained {
        (off16(d, s, s + 4), off16(d, s, s + 6), off16(d, s, s + 8), rd16(d, s + 10), s + 12)
      } else {
        (0, off16(d, s, s + 4), 0, rd16(d, s + 6), s + 8)
      }
      let index = class_get(d, input_cd, ctx.buffer.cur(0).glyph_id)
      if index >= count {
        return false
      }
      apply_rule_set(
        ctx,
        off16(d, s, sets + index * 2),
        chained,
        fn(info, v) { class_get(d, back_cd, info.glyph_id) == v },
        fn(info, v) { class_get(d, input_cd, info.glyph_id) == v },
        fn(info, v) { class_get(d, ahead_cd, info.glyph_id) == v },
      )
    }
    3 => {
      let covered = fn(at : Int) {
        fn(info : GlyphInfo, v : Int) { coverage_get(d, off16(d, s, at + v * 2), info.glyph_id) >= 0 }
      }
      if !chained {
        let glyph_count = rd16(d, s + 2)
        let record_count = rd16(d, s + 4)
        let n = if glyph_count > 0 { glyph_count - 1 } else { 0 }
        let rule = {
          backtrack: [],
          input: Array::makei(n, fn(i) { i }),
          lookahead: [],
          records: read_records(d, s + 6 + glyph_count * 2, record_count),
          chained,
        }
        // the coverages after the first, which the current glyph has matched
        apply_rule(ctx, rule, by_glyph, covered(s + 8), by_glyph)
      } else {
        let back = rd16(d, s + 2)
        let back_at = s + 4
        let input_count = rd16(d, back_at + back * 2)
        let input_at = back_at + back * 2 + 2
        let ahead = rd16(d, input_at + input_count * 2)
        let ahead_at = input_at + input_count * 2 + 2
        let record_count = rd16(d, ahead_at + ahead * 2)
        let n = if input_count > 0 { input_count - 1 } else { 0 }
        let rule = {
          backtrack: Array::makei(back, fn(i) { i }),
          input: Array::makei(n, fn(i) { i }),
          lookahead: Array::makei(ahead, fn(i) { i }),
          records: read_records(d, ahead_at + ahead * 2 + 2, record_count),
          chained,
        }
        apply_rule(ctx, rule, covered(back_at), covered(input_at + 2), covered(ahead_at))
      }
    }
    _ => false
  }
}

///|
/// Whether a GSUB lookup would substitute exactly these glyphs, without looking at a buffer (CachedLookup's
/// would_apply); `zero_context` refuses rules with backtrack or lookahead.
fn would_apply_lookup(ot : OtData, lookup : Lookup, glyphs : Array[Int], zero_context : Bool) -> Bool {
  let d = ot.data
  let n = glyphs.length()
  if n == 0 {
    return false
  }
  for s in lookup.subtables {
    let index = coverage_get(d, subtable_coverage(d, true, lookup.kind, s), glyphs[0])
    if index < 0 {
      continue
    }
    let applies = match lookup.kind {
      1 | 2 | 3 | 8 => n == 1
      4 => {
        let set = if index < rd16(d, s + 4) { off16(d, s, s + 6 + index * 2) } else { 0 }
        let mut any = false
        if set != 0 {
          for i in 0..<rd16(d, set) {
            let lig = off16(d, set, set + 2 + i * 2)
            if lig == 0 {
              continue
            }
            let count = rd16(d, lig + 2)
            let comps = if count > 0 { count - 1 } else { 0 }
            if n == comps + 1 {
              let mut ok = true
              for k in 0..<comps {
                if rd16(d, lig + 4 + k * 2) != glyphs[k + 1] {
                  ok = false
                  break
                }
              }
              if ok {
                any = true
                break
              }
            }
          }
        }
        any
      }
      5 | 6 => context_would_apply(d, s, lookup.kind == 6, index, glyphs, zero_context)
      _ => false
    }
    if applies {
      return true
    }
  }
  false
}

///|
fn context_would_apply(d : Bytes, s : Int, chained : Bool, index : Int, glyphs : Array[Int], zero_context : Bool) -> Bool {
  let n = glyphs.length()
  let rules_would_apply = fn(set : Int, matches : (Int, Int) -> Bool) -> Bool {
    if set == 0 {
      return false
    }
    for i in 0..<rd16(d, set) {
      let r = off16(d, set, set + 2 + i * 2)
      if r == 0 {
        continue
      }
      let rule = read_rule(d, r, chained)
      if zero_context && (rule.backtrack.length() > 0 || rule.lookahead.length() > 0) {
        continue
      }
      if n != rule.input.length() + 1 {
        continue
      }
      let mut ok = true
      for k in 0..<rule.input.length() {
        if !matches(glyphs[k + 1], rule.input[k]) {
          ok = false
          break
        }
      }
      if ok {
        return true
      }
    }
    false
  }
  match rd16(d, s) {
    1 => {
      let count = rd16(d, s + 4)
      if index >= count {
        return false
      }
      rules_would_apply(off16(d, s, s + 6 + index * 2), fn(g, v) { g == v })
    }
    2 => {
      let (input_cd, count, sets) = if chained {
        (off16(d, s, s + 6), rd16(d, s + 10), s + 12)
      } else {
        (off16(d, s, s + 4), rd16(d, s + 6), s + 8)
      }
      let class = class_get(d, input_cd, glyphs[0])
      if class >= count {
        return false
      }
      rules_would_apply(off16(d, s, sets + class * 2), fn(g, v) { class_get(d, input_cd, g) == v })
    }
    3 => {
      let (back, input_count, input_at, ahead) = if chained {
        let back = rd16(d, s + 2)
        let input_count = rd16(d, s + 4 + back * 2)
        let input_at = s + 4 + back * 2 + 2
        (back, input_count, input_at, rd16(d, input_at + input_count * 2))
      } else {
        (0, rd16(d, s + 2), s + 6, 0)
      }
      if zero_context && (back > 0 || ahead > 0) {
        return false
      }
      if n != input_count {
        return false
      }
      for k in 1..<input_count {
        if coverage_get(d, off16(d, s, input_at + k * 2), glyphs[k]) < 0 {
          return false
        }
      }
      true
    }
    _ => false
  }
}
