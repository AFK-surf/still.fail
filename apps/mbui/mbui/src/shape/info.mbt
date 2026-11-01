// harfrust's glyph info helpers (ot/layout.rs): the modified general category and combining class kept in
// unicode_props, joiners, ligature ids and components in lig_props, GDEF classes and what GSUB did in glyph_props.

///|
fn GlyphInfo::set_general_category(self : GlyphInfo, gc : Int) -> Unit {
  self.set_unicode_props(gc | (self.unicode_props() & (0xFF & (UPROPS_GENERAL_CATEGORY ^ 0xFF))))
}

///|
fn GlyphInfo::is_unicode_mark(self : GlyphInfo) -> Bool {
  gc_is_mark(self.general_category())
}

///|
fn GlyphInfo::set_modified_combining_class(self : GlyphInfo, c : Int) -> Unit {
  if !self.is_unicode_mark() {
    return
  }
  self.set_unicode_props(((c & 0xFF) << 8) | (self.unicode_props() & 0xFF))
}

///|
fn GlyphInfo::modified_combining_class(self : GlyphInfo) -> Int {
  if self.is_unicode_mark() {
    (self.unicode_props() >> 8) & 0xFF
  } else {
    0
  }
}

///|
fn GlyphInfo::is_unicode_space(self : GlyphInfo) -> Bool {
  self.general_category() == GC_SPACE_SEPARATOR
}

///|
fn GlyphInfo::set_space_fallback_type(self : GlyphInfo, s : Int) -> Unit {
  if !self.is_unicode_space() {
    return
  }
  self.set_unicode_props(((s & 0xFF) << 8) | (self.unicode_props() & 0xFF))
}

///|
fn GlyphInfo::space_fallback_type(self : GlyphInfo) -> Int {
  if self.is_unicode_space() {
    (self.unicode_props() >> 8) & 0xFF
  } else {
    0
  }
}

///|
fn GlyphInfo::is_variation_selector(self : GlyphInfo) -> Bool {
  self.general_category() == GC_FORMAT && (self.unicode_props() & UPROPS_CF_VS) != 0
}

///|
fn GlyphInfo::set_variation_selector(self : GlyphInfo, customize : Bool) -> Unit {
  if customize {
    self.set_general_category(GC_FORMAT)
    self.set_unicode_props(self.unicode_props() | UPROPS_CF_VS)
  } else {
    self.set_general_category(GC_NON_SPACING_MARK)
  }
}

///|
fn GlyphInfo::is_default_ignorable(self : GlyphInfo) -> Bool {
  (self.unicode_props() & UPROPS_IGNORABLE) != 0 && !self.substituted()
}

///|
fn GlyphInfo::clear_default_ignorable(self : GlyphInfo) -> Unit {
  self.set_unicode_props(self.unicode_props() & (UPROPS_IGNORABLE ^ 0xFFFF))
}

///|
fn GlyphInfo::is_hidden(self : GlyphInfo) -> Bool {
  (self.unicode_props() & UPROPS_HIDDEN) != 0
}

///|
fn GlyphInfo::set_continuation(self : GlyphInfo, buffer : Buffer) -> Unit {
  buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_CONTINUATIONS
  self.set_unicode_props(self.unicode_props() | UPROPS_CONTINUATION)
}

///|
fn GlyphInfo::clear_continuation(self : GlyphInfo) -> Unit {
  self.set_unicode_props(self.unicode_props() & (UPROPS_CONTINUATION ^ 0xFFFF))
}

///|
fn GlyphInfo::is_continuation(self : GlyphInfo) -> Bool {
  (self.unicode_props() & UPROPS_CONTINUATION) != 0
}

///|
fn GlyphInfo::is_unicode_format(self : GlyphInfo) -> Bool {
  self.general_category() == GC_FORMAT
}

///|
fn GlyphInfo::is_zwnj(self : GlyphInfo) -> Bool {
  self.is_unicode_format() && (self.unicode_props() & UPROPS_CF_ZWNJ) != 0
}

///|
fn GlyphInfo::is_zwj(self : GlyphInfo) -> Bool {
  self.is_unicode_format() && (self.unicode_props() & UPROPS_CF_ZWJ) != 0
}

///|
fn GlyphInfo::set_lig_props_for_ligature(self : GlyphInfo, lig_id : Int, comps : Int) -> Unit {
  self.set_lig_props((lig_id << 5) | 0x10 | (comps & 0x0F))
}

///|
fn GlyphInfo::set_lig_props_for_mark(self : GlyphInfo, lig_id : Int, comp : Int) -> Unit {
  self.set_lig_props((lig_id << 5) | (comp & 0x0F))
}

///|
fn GlyphInfo::set_lig_props_for_component(self : GlyphInfo, comp : Int) -> Unit {
  self.set_lig_props_for_mark(0, comp)
}

///|
fn GlyphInfo::lig_id(self : GlyphInfo) -> Int {
  self.lig_props() >> 5
}

///|
fn GlyphInfo::ligated_internal(self : GlyphInfo) -> Bool {
  (self.lig_props() & 0x10) != 0
}

///|
fn GlyphInfo::lig_comp(self : GlyphInfo) -> Int {
  if self.ligated_internal() {
    0
  } else {
    self.lig_props() & 0x0F
  }
}

///|
fn GlyphInfo::lig_num_comps(self : GlyphInfo) -> Int {
  if (self.glyph_props() & GPROPS_LIGATURE) != 0 && self.ligated_internal() {
    self.lig_props() & 0x0F
  } else {
    1
  }
}

///|
fn GlyphInfo::is_base_glyph(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_BASE_GLYPH) != 0
}

///|
fn GlyphInfo::is_ligature(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_LIGATURE) != 0
}

///|
fn GlyphInfo::is_mark(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_MARK) != 0
}

///|
fn GlyphInfo::substituted(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_SUBSTITUTED) != 0
}

///|
fn GlyphInfo::ligated(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_LIGATED) != 0
}

///|
fn GlyphInfo::multiplied(self : GlyphInfo) -> Bool {
  (self.glyph_props() & GPROPS_MULTIPLIED) != 0
}

///|
fn GlyphInfo::lig_num_comps_in_ligation(self : GlyphInfo) -> Int {
  if self.multiplied() && self.lig_comp() != 0 {
    0
  } else {
    self.lig_num_comps()
  }
}

///|
fn GlyphInfo::ligated_and_didnt_multiply(self : GlyphInfo) -> Bool {
  self.ligated() && !self.multiplied()
}

///|
fn GlyphInfo::clear_ligated_and_multiplied(self : GlyphInfo) -> Unit {
  self.set_glyph_props(self.glyph_props() & ((GPROPS_LIGATED | GPROPS_MULTIPLIED) ^ 0xFFFF))
}

///|
fn GlyphInfo::clear_substituted(self : GlyphInfo) -> Unit {
  self.set_glyph_props(self.glyph_props() & (GPROPS_SUBSTITUTED ^ 0xFFFF))
}

///|
fn grapheme_group(_a : GlyphInfo, b : GlyphInfo) -> Bool {
  b.is_continuation()
}

///|
fn reverse_graphemes(buffer : Buffer) -> Unit {
  buffer.reverse_groups(grapheme_group, false)
}

///|
let script_common : Int = tag("Zyyy")

///|
let script_inherited : Int = tag("Zinh")

///|
let script_unknown : Int = tag("Zzzz")
