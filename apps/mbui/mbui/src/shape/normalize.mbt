// Normalization as harfrust does it before GSUB (normalize.rs): decompose what the font has no glyph for, reorder
// marks by combining class, then compose again where the font has the composed glyph. Each character's glyph is
// kept in normalizer_glyph_index for mapping afterwards.

///|
fn nominal_glyph(face : @font.Face, c : Int) -> Int? {
  let g = face.glyph_index(c)
  if g == 0 {
    None
  } else {
    Some(g)
  }
}

///|
fn output_char(buffer : Buffer, unichar : Int, glyph : Int) -> Unit {
  buffer.cur(0).set_normalizer_glyph_index(glyph)
  buffer.output_glyph(unichar)
  match buffer.prev() {
    Some(p) => p.init_unicode_props(buffer)
    None => ()
  }
}

///|
fn next_char(buffer : Buffer, glyph : Int) -> Unit {
  buffer.cur(0).set_normalizer_glyph_index(glyph)
  buffer.next_glyph()
}

///|
fn decompose_char(face : @font.Face, buffer : Buffer, shortest : Bool, ab : Int, indic : Bool) -> Int {
  guard (if indic { indic_decompose(ab) } else { decompose(ab) }) is Some((a, b)) else { return 0 }
  let a_glyph = nominal_glyph(face, a)
  let b_glyph = if b != 0 {
    match nominal_glyph(face, b) {
      Some(g) => Some(g)
      None => return 0
    }
  } else {
    None
  }
  if a_glyph is Some(ag) && shortest {
    output_char(buffer, a, ag)
    if b_glyph is Some(bg) {
      output_char(buffer, b, bg)
      return 2
    }
    return 1
  }
  let ret = decompose_char(face, buffer, shortest, a, indic)
  if ret != 0 {
    if b_glyph is Some(bg) {
      output_char(buffer, b, bg)
      return ret + 1
    }
    return ret
  }
  if a_glyph is Some(ag) {
    output_char(buffer, a, ag)
    if b_glyph is Some(bg) {
      output_char(buffer, b, bg)
      return 2
    }
    return 1
  }
  0
}

///|
fn decompose_current_character(face : @font.Face, buffer : Buffer, shortest : Bool, indic : Bool) -> Unit {
  let u = buffer.cur(0).glyph_id
  let glyph = nominal_glyph(face, u)
  if glyph is Some(g) && shortest {
    next_char(buffer, g)
    return
  }
  if decompose_char(face, buffer, shortest, u, indic) > 0 {
    buffer.skip_glyph()
    return
  }
  if glyph is Some(g) {
    next_char(buffer, g)
    return
  }
  if buffer.cur(0).is_unicode_space() {
    let space_type = space_fallback(u)
    if space_type != 0 {
      match nominal_glyph(face, 0x20) {
        Some(space_glyph) => {
          buffer.cur(0).set_space_fallback_type(space_type)
          next_char(buffer, space_glyph)
          buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_SPACE_FALLBACK
          return
        }
        None => ()
      }
    }
  }
  if u == 0x2011 {
    match nominal_glyph(face, 0x2010) {
      Some(g) => {
        next_char(buffer, g)
        return
      }
      None => ()
    }
  }
  next_char(buffer, 0)
}

///|
fn set_current_glyph(face : @font.Face, buffer : Buffer) -> Unit {
  let info = buffer.cur(0)
  match nominal_glyph(face, info.glyph_id) {
    Some(g) => info.set_normalizer_glyph_index(g)
    None => ()
  }
}

///|
fn handle_variation_selector_cluster(face : @font.Face, buffer : Buffer, end : Int) -> Unit {
  while buffer.idx < end - 1 && buffer.successful {
    if is_variation_selector(buffer.cur(1).glyph_id) {
      let base = buffer.cur(0).glyph_id
      let selector = buffer.cur(1).glyph_id
      match face.glyph_variant(base, selector) {
        Some(g) if g != 0 => {
          buffer.cur(0).set_normalizer_glyph_index(g)
          let unicode = buffer.cur(0).glyph_id
          buffer.replace_glyphs(2, 1, [unicode])
        }
        _ => {
          set_current_glyph(face, buffer)
          buffer.next_glyph()
          buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_VARIATION_SELECTOR_FALLBACK
          buffer.cur(0).set_variation_selector(true)
          set_current_glyph(face, buffer)
          buffer.next_glyph()
        }
      }
      while buffer.idx < end && is_variation_selector(buffer.cur(0).glyph_id) {
        set_current_glyph(face, buffer)
        buffer.next_glyph()
      }
    } else {
      set_current_glyph(face, buffer)
      buffer.next_glyph()
    }
  }
  if buffer.idx < end {
    set_current_glyph(face, buffer)
    buffer.next_glyph()
  }
}

///|
fn decompose_multi_char_cluster(face : @font.Face, buffer : Buffer, end : Int, short_circuit : Bool, indic : Bool) -> Unit {
  for i in buffer.idx..<end {
    if is_variation_selector(buffer.info[i].glyph_id) {
      handle_variation_selector_cluster(face, buffer, end)
      return
    }
  }
  while buffer.idx < end && buffer.successful {
    decompose_current_character(face, buffer, short_circuit, indic)
  }
}

///|
/// Normalizes in the default shaper's way (ComposedDiacritics, which short-circuits).
fn normalize(face : @font.Face, buffer : Buffer, shaper : Int) -> Unit {
  if buffer.len == 0 {
    return
  }
  // the Indic shaper normalizes as ComposedDiacriticsNoShortCircuit, with its own decompositions
  let indic = shaper == SHAPER_INDIC
  let might_short_circuit = !indic
  let mut all_simple = true
  // first round: decompose
  buffer.clear_output()
  let count = buffer.len
  buffer.idx = 0
  while true {
    let mut end = buffer.idx + 1
    while end < count && !buffer.info[end].is_unicode_mark() {
      end += 1
    }
    if end < count {
      end -= 1
    }
    if might_short_circuit {
      let mut done = 0
      for k in buffer.idx..<end {
        match nominal_glyph(face, buffer.info[k].glyph_id) {
          Some(g) => buffer.info[k].set_normalizer_glyph_index(g)
          None => break
        }
        done += 1
      }
      buffer.next_glyphs(done)
    }
    while buffer.idx < end && buffer.successful {
      decompose_current_character(face, buffer, might_short_circuit, indic)
    }
    if buffer.idx == count || !buffer.successful {
      break
    }
    all_simple = false
    end = buffer.idx + 1
    while end < count && buffer.info[end].is_unicode_mark() {
      end += 1
    }
    decompose_multi_char_cluster(face, buffer, end, false, indic)
    if buffer.idx >= count || !buffer.successful {
      break
    }
  }
  ignore(buffer.sync())
  // second round: reorder marks
  if !all_simple {
    let count = buffer.len
    let mut i = 0
    while i < count {
      if buffer.info[i].modified_combining_class() == 0 {
        i += 1
        continue
      }
      let mut end = i + 1
      while end < count && buffer.info[end].modified_combining_class() != 0 {
        end += 1
      }
      if end - i <= 32 {
        buffer.sort(i, end, fn(a, b) {
          a.modified_combining_class() > b.modified_combining_class()
        })
        if shaper == SHAPER_ARABIC {
          arabic_reorder_marks(buffer, i, end)
        }
      }
      i = end + 1
    }
  }
  if (buffer.scratch_flags & SCRATCH_HAS_CGJ) != 0 {
    for i in 1..<(buffer.len - 1) {
      let info = buffer.info[i]
      if info.glyph_id == 0x034F {
        let last = buffer.info[i - 1].modified_combining_class()
        let next = buffer.info[i + 1].modified_combining_class()
        if next == 0 || last <= next {
          info.unhide()
        }
      }
    }
  }
  // third round: recompose
  if !all_simple && buffer.successful {
    let count = buffer.len
    let mut starter = 0
    buffer.clear_output()
    buffer.next_glyph()
    while buffer.idx < count && buffer.successful {
      let cur = buffer.cur(0)
      if cur.is_unicode_mark() &&
        (
          starter == buffer.out_len - 1 ||
          buffer.out_info()[buffer.out_len - 1].modified_combining_class() < cur.modified_combining_class()
        ) {
        match (if indic { indic_compose(buffer.out_info()[starter].glyph_id, cur.glyph_id) } else { compose(buffer.out_info()[starter].glyph_id, cur.glyph_id) }) {
          Some(composed) =>
            match nominal_glyph(face, composed) {
              Some(g) => {
                buffer.next_glyph()
                if !buffer.successful {
                  return
                }
                buffer.merge_out_clusters(starter, buffer.out_len)
                buffer.out_len -= 1
                let info = buffer.out_info()[starter]
                info.glyph_id = composed
                info.set_normalizer_glyph_index(g)
                info.init_unicode_props(buffer)
                continue
              }
              None => ()
            }
          None => ()
        }
      }
      buffer.next_glyph()
      if buffer.out_info()[buffer.out_len - 1].modified_combining_class() == 0 {
        starter = buffer.out_len - 1
      }
    }
    ignore(buffer.sync())
  }
}
