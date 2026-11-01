// Positioning marks without GPOS (harfrust's fallback.rs): marks go above or below their base by combining class,
// from the glyphs' ink boxes.

///|
const CC_ATTACHED_BELOW_LEFT : Int = 200

///|
const CC_ATTACHED_BELOW : Int = 202

///|
const CC_ATTACHED_ABOVE : Int = 214

///|
const CC_ATTACHED_ABOVE_RIGHT : Int = 216

///|
const CC_BELOW_LEFT : Int = 218

///|
const CC_BELOW : Int = 220

///|
const CC_BELOW_RIGHT : Int = 222

///|
const CC_ABOVE_LEFT : Int = 228

///|
const CC_ABOVE : Int = 230

///|
const CC_ABOVE_RIGHT : Int = 232

///|
const CC_DOUBLE_BELOW : Int = 233

///|
const CC_DOUBLE_ABOVE : Int = 234

///|
fn recategorize_combining_class(u : Int, class : Int) -> Int {
  if class >= 200 {
    return class
  }
  let mut class = class
  if (u & 0xFFFFFF00) == 0x0E00 {
    if class == 0 {
      match u {
        0x0E31 | 0x0E34 | 0x0E35 | 0x0E36 | 0x0E37 | 0x0E47 | 0x0E4C | 0x0E4D | 0x0E4E =>
          class = CC_ABOVE_RIGHT
        0x0EB1 | 0x0EB4 | 0x0EB5 | 0x0EB6 | 0x0EB7 | 0x0EBB | 0x0ECC | 0x0ECD => class = CC_ABOVE
        0x0EBC => class = CC_BELOW
        _ => ()
      }
    } else if u == 0x0E3A {
      class = CC_BELOW_RIGHT
    }
  }
  // the modified classes (Hebrew's permuted, Arabic's, Thai's, Lao's, Tibetan's)
  match class {
    22 | 15 | 16 | 17 | 23 | 18 | 19 | 20 | 21 | 24 | 25 => CC_BELOW
    13 => CC_ATTACHED_ABOVE
    10 => CC_ABOVE_RIGHT
    11 | 14 => CC_ABOVE_LEFT
    26 => CC_ABOVE
    12 => class
    28 | 29 | 31 | 32 | 27 | 34 | 35 | 36 => CC_ABOVE
    30 | 33 => CC_BELOW
    3 => CC_BELOW_RIGHT
    107 => CC_ABOVE_RIGHT
    118 => CC_BELOW
    122 => CC_ABOVE
    129 => CC_BELOW
    132 => CC_ABOVE
    131 => CC_BELOW
    _ => class
  }
}

///|
fn recategorize_marks(buffer : Buffer) -> Unit {
  for i in 0..<buffer.len {
    let info = buffer.info[i]
    if info.general_category() == GC_NON_SPACING_MARK {
      info.set_modified_combining_class(
        recategorize_combining_class(info.glyph_id, info.modified_combining_class()),
      )
    }
  }
}

///|
priv struct Extents {
  mut x_bearing : Int
  mut y_bearing : Int
  mut width : Int
  mut height : Int
}

///|
fn glyph_extents(face : @font.Face, glyph : Int) -> Extents? {
  match face.glyph_bbox(glyph) {
    Some((x0, y0, x1, y1)) => Some({ x_bearing: x0, y_bearing: y1, width: x1 - x0, height: y0 - y1 })
    None => None
  }
}

///|
fn position_mark(
  face : @font.Face,
  direction : Direction,
  glyph : Int,
  pos : GlyphPosition,
  base : Extents,
  cc : Int,
) -> Unit {
  guard glyph_extents(face, glyph) is Some(mark) else { return }
  let y_gap = face.units_per_em() / 16
  pos.x_offset = 0
  pos.y_offset = 0
  if (cc == CC_DOUBLE_BELOW || cc == CC_DOUBLE_ABOVE) && direction.is_horizontal() {
    pos.x_offset += base.x_bearing +
      (if direction.is_forward() { base.width } else { 0 }) -
      mark.width / 2 -
      mark.x_bearing
  } else if cc == CC_ATTACHED_BELOW_LEFT || cc == CC_BELOW_LEFT || cc == CC_ABOVE_LEFT {
    pos.x_offset += base.x_bearing - mark.x_bearing
  } else if cc == CC_ATTACHED_ABOVE_RIGHT || cc == CC_BELOW_RIGHT || cc == CC_ABOVE_RIGHT {
    pos.x_offset += base.x_bearing + base.width - mark.width - mark.x_bearing
  } else {
    pos.x_offset += base.x_bearing + (base.width - mark.width) / 2 - mark.x_bearing
  }
  let is_attached = cc == CC_ATTACHED_BELOW_LEFT ||
    cc == CC_ATTACHED_BELOW ||
    cc == CC_ATTACHED_ABOVE ||
    cc == CC_ATTACHED_ABOVE_RIGHT
  if cc == CC_DOUBLE_BELOW ||
    cc == CC_BELOW_LEFT ||
    cc == CC_BELOW ||
    cc == CC_BELOW_RIGHT ||
    cc == CC_ATTACHED_BELOW_LEFT ||
    cc == CC_ATTACHED_BELOW {
    if !is_attached {
      base.height -= y_gap
    }
    pos.y_offset = base.y_bearing + base.height - mark.y_bearing
    if (y_gap > 0) == (pos.y_offset > 0) {
      base.height -= pos.y_offset
      pos.y_offset = 0
    }
    base.height += mark.height
  } else if cc == CC_DOUBLE_ABOVE ||
    cc == CC_ABOVE_LEFT ||
    cc == CC_ABOVE ||
    cc == CC_ABOVE_RIGHT ||
    cc == CC_ATTACHED_ABOVE ||
    cc == CC_ATTACHED_ABOVE_RIGHT {
    if !is_attached {
      base.y_bearing += y_gap
      base.height -= y_gap
    }
    pos.y_offset = base.y_bearing - (mark.y_bearing + mark.height)
    if (y_gap > 0) != (pos.y_offset > 0) {
      let correction = -(pos.y_offset / 2)
      base.y_bearing += correction
      base.height -= correction
      pos.y_offset += correction
    }
    base.y_bearing -= mark.height
    base.height += mark.height
  }
}

///|
fn position_around_base(face : @font.Face, plan : ShapePlan, buffer : Buffer, base : Int, end : Int, adjust : Bool) -> Unit {
  let base_info = buffer.info[base]
  let base_pos = buffer.pos[base]
  let base_glyph = base_info.glyph_id
  guard glyph_extents(face, base_glyph) is Some(base_extents) else {
    for i in (base + 1)..<end {
      if buffer.info[i].general_category() == GC_NON_SPACING_MARK {
        let pos = buffer.pos[i]
        if adjust {
          pos.x_offset -= pos.x_advance
          pos.y_offset -= pos.y_advance
        }
        pos.x_advance = 0
        pos.y_advance = 0
      }
    }
    return
  }
  base_extents.y_bearing += base_pos.y_offset
  base_extents.x_bearing = 0
  base_extents.width = face.advance(base_glyph)
  let lig_id = base_info.lig_id()
  let num_lig_components = base_info.lig_num_comps()
  let mut x_offset = 0
  let mut y_offset = 0
  let direction = buffer.direction
  if direction.is_forward() {
    x_offset = -base_pos.x_advance
    y_offset = -base_pos.y_advance
  }
  let mut last_lig_component = -1
  let mut last_combining_class = 255
  let mut component_extents = { ..base_extents }
  let mut cluster_extents = { ..base_extents }
  for i in (base + 1)..<end {
    let info = buffer.info[i]
    let pos = buffer.pos[i]
    if info.modified_combining_class() != 0 {
      if num_lig_components > 1 {
        let this_lig_id = info.lig_id()
        let mut this_lig_component = info.lig_comp() - 1
        if lig_id == 0 || lig_id != this_lig_id || this_lig_component >= num_lig_components {
          this_lig_component = num_lig_components - 1
        }
        if last_lig_component != this_lig_component {
          last_lig_component = this_lig_component
          last_combining_class = 255
          component_extents = { ..base_extents }
          let horizontal_ltr = if plan.direction.is_horizontal() {
            plan.direction == LeftToRight
          } else {
            plan.script == 0 || script_direction(plan.script) != -1
          }
          let component = if horizontal_ltr {
            this_lig_component
          } else {
            num_lig_components - 1 - this_lig_component
          }
          component_extents.x_bearing += component * component_extents.width / num_lig_components
          component_extents.width = component_extents.width / num_lig_components
        }
      }
      let cc = info.modified_combining_class()
      if last_combining_class != cc {
        last_combining_class = cc
        cluster_extents = { ..component_extents }
      }
      position_mark(face, direction, info.glyph_id, pos, cluster_extents, cc)
      pos.x_advance = 0
      pos.y_advance = 0
      pos.x_offset += x_offset
      pos.y_offset += y_offset
    } else if direction.is_forward() {
      x_offset -= pos.x_advance
      y_offset -= pos.y_advance
    } else {
      x_offset += pos.x_advance
      y_offset += pos.y_advance
    }
  }
}

///|
fn position_cluster(face : @font.Face, plan : ShapePlan, buffer : Buffer, start : Int, end : Int, adjust : Bool) -> Unit {
  if end - start < 2 {
    return
  }
  let mut i = start
  while i < end {
    if !buffer.info[i].is_unicode_mark() {
      let mut j = i + 1
      while j < end {
        let info = buffer.info[j]
        if !(info.is_hidden() || info.is_default_ignorable() || info.is_unicode_mark()) {
          break
        }
        j += 1
      }
      position_around_base(face, plan, buffer, i, j, adjust)
      i = j - 1
    }
    i += 1
  }
}

///|
fn position_marks(face : @font.Face, plan : ShapePlan, buffer : Buffer, adjust : Bool) -> Unit {
  let mut start = 0
  let len = buffer.len
  for i in 1..<len {
    let info = buffer.info[i]
    if !info.is_unicode_mark() && !info.is_hidden() && !info.is_default_ignorable() {
      position_cluster(face, plan, buffer, start, i, adjust)
      start = i
    }
  }
  position_cluster(face, plan, buffer, start, len, adjust)
}
