// harfrust's buffer (buffer.rs): glyph infos and positions, the output side substitutions write into, cluster
// merging. Glyph flags (unsafe-to-break and the like) are not kept: they only mark the result for line breaking,
// in mask bits no feature uses.

///|
pub(all) struct GlyphInfo {
  /// a character before glyphs are mapped, a glyph after
  mut glyph_id : Int
  mut mask : Int
  mut cluster : Int
  /// two words of per-stage variables, read by byte and halfword as HarfBuzz lays them out (little-endian)
  mut var1 : Int
  mut var2 : Int
}

///|
fn GlyphInfo::new() -> GlyphInfo {
  { glyph_id: 0, mask: 0, cluster: 0, var1: 0, var2: 0 }
}

///|
fn GlyphInfo::copy(self : GlyphInfo) -> GlyphInfo {
  { ..self }
}

///|
pub(all) struct GlyphPosition {
  mut x_advance : Int
  mut y_advance : Int
  mut x_offset : Int
  mut y_offset : Int
  /// attach chain (low 16 bits, signed) and attach type (byte 2)
  mut attach : Int
}

///|
fn GlyphPosition::new() -> GlyphPosition {
  { x_advance: 0, y_advance: 0, x_offset: 0, y_offset: 0, attach: 0 }
}

///|
fn GlyphPosition::attach_chain(self : GlyphPosition) -> Int {
  let v = self.attach & 0xFFFF
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn GlyphPosition::set_attach_chain(self : GlyphPosition, n : Int) -> Unit {
  self.attach = (self.attach & 0xFFFF0000) | (n & 0xFFFF)
}

///|
fn GlyphPosition::attach_type(self : GlyphPosition) -> Int {
  (self.attach >> 16) & 0xFF
}

///|
fn GlyphPosition::set_attach_type(self : GlyphPosition, n : Int) -> Unit {
  self.attach = (self.attach & 0xFF00FFFF) | ((n & 0xFF) << 16)
}

// per-stage variables (ot/layout.rs, normalize.rs, ot/shaper/mod.rs)

///|
fn GlyphInfo::glyph_props(self : GlyphInfo) -> Int {
  self.var1 & 0xFFFF
}

///|
fn GlyphInfo::set_glyph_props(self : GlyphInfo, v : Int) -> Unit {
  self.var1 = (self.var1 & 0xFFFF0000) | (v & 0xFFFF)
}

///|
fn GlyphInfo::lig_props(self : GlyphInfo) -> Int {
  (self.var1 >> 16) & 0xFF
}

///|
fn GlyphInfo::set_lig_props(self : GlyphInfo, v : Int) -> Unit {
  self.var1 = (self.var1 & 0xFF00FFFF) | ((v & 0xFF) << 16)
}

///|
fn GlyphInfo::syllable(self : GlyphInfo) -> Int {
  (self.var1 >> 24) & 0xFF
}

///|
fn GlyphInfo::set_syllable(self : GlyphInfo, v : Int) -> Unit {
  self.var1 = (self.var1 & 0x00FFFFFF) | ((v & 0xFF) << 24)
}

///|
fn GlyphInfo::normalizer_glyph_index(self : GlyphInfo) -> Int {
  self.var1
}

///|
fn GlyphInfo::set_normalizer_glyph_index(self : GlyphInfo, v : Int) -> Unit {
  self.var1 = v
}

///|
fn GlyphInfo::unicode_props(self : GlyphInfo) -> Int {
  self.var2 & 0xFFFF
}

///|
fn GlyphInfo::set_unicode_props(self : GlyphInfo, v : Int) -> Unit {
  self.var2 = (self.var2 & 0xFFFF0000) | (v & 0xFFFF)
}

///|
fn GlyphInfo::shaper_category(self : GlyphInfo) -> Int {
  (self.var2 >> 16) & 0xFF
}

///|
fn GlyphInfo::set_shaper_category(self : GlyphInfo, v : Int) -> Unit {
  self.var2 = (self.var2 & 0xFF00FFFF) | ((v & 0xFF) << 16)
}

///|
fn GlyphInfo::shaper_auxiliary(self : GlyphInfo) -> Int {
  (self.var2 >> 24) & 0xFF
}

///|
fn GlyphInfo::set_shaper_auxiliary(self : GlyphInfo, v : Int) -> Unit {
  self.var2 = (self.var2 & 0x00FFFFFF) | ((v & 0xFF) << 24)
}

// unicode props (UnicodeProps)

///|
const UPROPS_GENERAL_CATEGORY : Int = 0x001F

///|
const UPROPS_IGNORABLE : Int = 0x0020

///|
const UPROPS_HIDDEN : Int = 0x0040

///|
const UPROPS_CONTINUATION : Int = 0x0080

///|
const UPROPS_CF_ZWJ : Int = 0x0100

///|
const UPROPS_CF_ZWNJ : Int = 0x0200

///|
const UPROPS_CF_VS : Int = 0x0400

// glyph props (GlyphPropsFlags)

///|
const GPROPS_BASE_GLYPH : Int = 0x02

///|
const GPROPS_LIGATURE : Int = 0x04

///|
const GPROPS_MARK : Int = 0x08

///|
const GPROPS_CLASS_MASK : Int = 0x0E

///|
const GPROPS_SUBSTITUTED : Int = 0x10

///|
const GPROPS_LIGATED : Int = 0x20

///|
const GPROPS_MULTIPLIED : Int = 0x40

///|
const GPROPS_PRESERVE : Int = 0x70

// scratch flags

///|
const SCRATCH_HAS_FRACTION_SLASH : Int = 0x01

///|
const SCRATCH_HAS_DEFAULT_IGNORABLES : Int = 0x02

///|
const SCRATCH_HAS_SPACE_FALLBACK : Int = 0x04

///|
const SCRATCH_HAS_GPOS_ATTACHMENT : Int = 0x08

///|
const SCRATCH_HAS_CGJ : Int = 0x10

///|
const SCRATCH_HAS_BROKEN_SYLLABLE : Int = 0x20

///|
const SCRATCH_HAS_VARIATION_SELECTOR_FALLBACK : Int = 0x40

///|
const SCRATCH_HAS_CONTINUATIONS : Int = 0x80

///|
const SCRATCH_SHAPER0 : Int = 0x01000000

///|
fn GlyphInfo::general_category(self : GlyphInfo) -> Int {
  self.unicode_props() & UPROPS_GENERAL_CATEGORY
}

///|
fn GlyphInfo::init_unicode_props(self : GlyphInfo, buffer : Buffer) -> Unit {
  let u = self.glyph_id
  let gc = general_category(u)
  let mut props = gc
  if u >= 0x80 {
    if is_default_ignorable(u) {
      props = props | UPROPS_IGNORABLE
      buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_DEFAULT_IGNORABLES
      if u == 0x200C {
        props = props | UPROPS_CF_ZWNJ
      } else if u == 0x200D {
        props = props | UPROPS_CF_ZWJ
      } else if (u >= 0x180B && u <= 0x180D) || u == 0x180F {
        props = props | UPROPS_HIDDEN
      } else if u >= 0xE0020 && u <= 0xE007F {
        props = props | UPROPS_HIDDEN
      } else if u == 0x034F {
        props = props | UPROPS_HIDDEN
        buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_CGJ
      }
    }
    if gc_is_mark(gc) {
      buffer.scratch_flags = buffer.scratch_flags | SCRATCH_HAS_CONTINUATIONS
      props = props | UPROPS_CONTINUATION
      props = props | (modified_combining_class(u) << 8)
    }
  }
  self.set_unicode_props(props)
}

///|
fn GlyphInfo::unhide(self : GlyphInfo) -> Unit {
  self.set_unicode_props(self.unicode_props() & (UPROPS_HIDDEN ^ 0xFFFF))
}

///|
pub(all) enum Direction {
  LeftToRight
  RightToLeft
  TopToBottom
  BottomToTop
} derive(Eq, Show, Debug)

///|
fn Direction::is_horizontal(self : Direction) -> Bool {
  self == LeftToRight || self == RightToLeft
}

///|
fn Direction::is_backward(self : Direction) -> Bool {
  self == RightToLeft || self == BottomToTop
}

///|
fn Direction::is_forward(self : Direction) -> Bool {
  !self.is_backward()
}

///|
pub struct Buffer {
  mut direction : Direction
  mut script : Int
  mut successful : Bool
  mut have_output : Bool
  mut have_separate_output : Bool
  mut have_positions : Bool
  mut idx : Int
  mut len : Int
  mut out_len : Int
  mut info : Array[GlyphInfo]
  mut out : Array[GlyphInfo]
  pos : Array[GlyphPosition]
  context_before : Array[Int]
  context_after : Array[Int]
  mut serial : Int
  mut scratch_flags : Int
  mut max_ops : Int
}

///|
pub fn Buffer::new() -> Buffer {
  {
    direction: LeftToRight,
    script: 0,
    successful: true,
    have_output: false,
    have_separate_output: false,
    have_positions: false,
    idx: 0,
    len: 0,
    out_len: 0,
    info: [],
    out: [],
    pos: [],
    context_before: [],
    context_after: [],
    serial: 0,
    scratch_flags: 0,
    max_ops: 0x1FFFFFFF,
  }
}

///|
/// Adds a character with its cluster value.
pub fn Buffer::push(self : Buffer, c : Int, cluster : Int) -> Unit {
  self.info.push({ glyph_id: c, mask: 0, cluster, var1: 0, var2: 0 })
  self.len += 1
}

///|
pub fn Buffer::set_direction(self : Buffer, d : Direction) -> Unit {
  self.direction = d
}

///|
/// The script of the first character with one (not Common, Inherited or Unknown), as guess_segment_properties.
pub fn Buffer::guess_script(self : Buffer) -> Unit {
  if self.script != 0 {
    return
  }
  for i in self.info {
    let s = script_of(i.glyph_id)
    if s != script_common && s != script_inherited && s != script_unknown {
      self.script = s
      return
    }
  }
}

///|
pub fn Buffer::glyph_infos(self : Buffer) -> Array[GlyphInfo] {
  self.info[0:self.len].to_array()
}

///|
pub fn Buffer::glyph_positions(self : Buffer) -> Array[GlyphPosition] {
  self.pos[0:self.len].to_array()
}

///|
fn Buffer::ensure(self : Buffer, size : Int) -> Unit {
  while self.info.length() < size {
    self.info.push(GlyphInfo::new())
  }
  while self.pos.length() < size {
    self.pos.push(GlyphPosition::new())
  }
  while self.out.length() < size {
    self.out.push(GlyphInfo::new())
  }
}

///|
fn Buffer::out_info(self : Buffer) -> Array[GlyphInfo] {
  if self.have_separate_output {
    self.out
  } else {
    self.info
  }
}

///|
fn Buffer::set_out_info(self : Buffer, i : Int, info : GlyphInfo) -> Unit {
  if self.have_separate_output {
    self.ensure(i + 1)
    self.out[i] = info.copy()
  } else {
    self.info[i] = info.copy()
  }
}

///|
fn Buffer::copy_infos_to_out(self : Buffer, src : Int, dst : Int, count : Int) -> Unit {
  if self.have_separate_output {
    self.ensure(dst + count)
    for k in 0..<count {
      self.out[dst + k] = self.info[src + k].copy()
    }
  } else {
    for k in 0..<count {
      self.info[dst + k] = self.info[src + k].copy()
    }
  }
}

///|
fn Buffer::copy_out_to_infos(self : Buffer, src : Int, dst : Int, count : Int) -> Unit {
  if self.have_separate_output {
    for k in 0..<count {
      self.info[dst + k] = self.out[src + k].copy()
    }
  } else {
    let mut k = count - 1
    while k >= 0 {
      self.info[dst + k] = self.info[src + k].copy()
      k -= 1
    }
  }
}

///|
fn Buffer::cur(self : Buffer, i : Int) -> GlyphInfo {
  self.info[self.idx + i]
}

///|
fn Buffer::cur_pos(self : Buffer) -> GlyphPosition {
  self.pos[self.idx]
}

///|
fn Buffer::prev(self : Buffer) -> GlyphInfo? {
  if self.out_len == 0 {
    None
  } else {
    Some(self.out_info()[self.out_len - 1])
  }
}

///|
fn Buffer::backtrack_len(self : Buffer) -> Int {
  if self.have_output {
    self.out_len
  } else {
    self.idx
  }
}

///|
fn Buffer::lookahead_len(self : Buffer) -> Int {
  self.len - self.idx
}

///|
fn Buffer::next_serial(self : Buffer) -> Int {
  self.serial = (self.serial + 1) & 0xFF
  if self.serial == 0 {
    self.serial += 1
  }
  self.serial
}

///|
fn Buffer::allocate_lig_id(self : Buffer) -> Int {
  let mut lig_id = self.next_serial() & 0x07
  if lig_id == 0 {
    lig_id = self.allocate_lig_id()
  }
  lig_id
}

///|
fn Buffer::reverse_range(self : Buffer, start : Int, end : Int) -> Unit {
  if end - start < 2 {
    return
  }
  let mut a = start
  let mut b = end - 1
  while a < b {
    let t = self.info[a]
    self.info[a] = self.info[b]
    self.info[b] = t
    if self.have_positions {
      let p = self.pos[a]
      self.pos[a] = self.pos[b]
      self.pos[b] = p
    }
    a += 1
    b -= 1
  }
}

///|
fn Buffer::reverse(self : Buffer) -> Unit {
  if self.len == 0 {
    return
  }
  self.reverse_range(0, self.len)
}

///|
fn Buffer::reverse_groups(self : Buffer, group : (GlyphInfo, GlyphInfo) -> Bool, merge : Bool) -> Unit {
  if self.len == 0 {
    return
  }
  let mut start = 0
  let mut i = 1
  while i < self.len {
    if !group(self.info[i - 1], self.info[i]) {
      if merge {
        self.merge_clusters(start, i)
      }
      self.reverse_range(start, i)
      start = i
    }
    i += 1
  }
  if merge {
    self.merge_clusters(start, i)
  }
  self.reverse_range(start, i)
  self.reverse()
}

///|
fn Buffer::group_end(self : Buffer, start : Int, group : (GlyphInfo, GlyphInfo) -> Bool) -> Int {
  let mut s = start + 1
  while s < self.len && group(self.info[s - 1], self.info[s]) {
    s += 1
  }
  s
}

///|
fn Buffer::sync(self : Buffer) -> Bool {
  if !self.successful {
    self.have_output = false
    self.out_len = 0
    self.idx = 0
    return false
  }
  self.next_glyphs(self.len - self.idx)
  if self.have_separate_output {
    let t = self.info
    self.info = self.out
    self.out = t
    self.have_separate_output = false
  }
  self.len = self.out_len
  self.have_output = false
  self.out_len = 0
  self.idx = 0
  true
}

///|
fn Buffer::clear_output(self : Buffer) -> Unit {
  self.have_output = true
  self.have_positions = false
  self.idx = 0
  self.out_len = 0
  self.have_separate_output = false
}

///|
fn Buffer::clear_positions(self : Buffer) -> Unit {
  self.have_output = false
  self.have_positions = true
  self.out_len = 0
  self.have_separate_output = false
  self.ensure(self.len)
  for i in 0..<self.pos.length() {
    self.pos[i] = GlyphPosition::new()
  }
}

///|
fn Buffer::make_room_for(self : Buffer, num_in : Int, num_out : Int) -> Unit {
  self.ensure(self.out_len + num_out)
  if !self.have_separate_output && self.out_len + num_out > self.idx + num_in {
    self.have_separate_output = true
    for k in 0..<self.out_len {
      self.out[k] = self.info[k].copy()
    }
  }
}

///|
fn Buffer::replace_glyphs(self : Buffer, num_in : Int, num_out : Int, glyphs : Array[Int]) -> Unit {
  self.make_room_for(num_in, num_out)
  self.merge_clusters(self.idx, self.idx + num_in)
  let orig = self.info[self.idx].copy()
  for k in 0..<num_out {
    let o = orig.copy()
    o.glyph_id = glyphs[k]
    self.set_out_info(self.out_len + k, o)
  }
  self.idx += num_in
  self.out_len += num_out
}

///|
fn Buffer::replace_glyph(self : Buffer, glyph : Int) -> Unit {
  if self.have_separate_output || self.out_len != self.idx {
    self.make_room_for(1, 1)
    self.set_out_info(self.out_len, self.info[self.idx])
  }
  self.out_info()[self.out_len].glyph_id = glyph
  self.idx += 1
  self.out_len += 1
}

///|
fn Buffer::output_glyph(self : Buffer, glyph : Int) -> Unit {
  self.make_room_for(0, 1)
  if self.idx == self.len && self.out_len == 0 {
    return
  }
  let out_len = self.out_len
  if self.idx < self.len {
    self.set_out_info(out_len, self.info[self.idx])
  } else {
    self.set_out_info(out_len, self.out_info()[out_len - 1])
  }
  self.out_info()[out_len].glyph_id = glyph
  self.out_len += 1
}

///|
fn Buffer::output_info(self : Buffer, info : GlyphInfo) -> Unit {
  self.make_room_for(0, 1)
  self.set_out_info(self.out_len, info)
  self.out_len += 1
}

///|
fn Buffer::copy_glyph(self : Buffer) -> Unit {
  self.make_room_for(0, 1)
  self.set_out_info(self.out_len, self.info[self.idx])
  self.out_len += 1
}

///|
fn Buffer::next_glyph(self : Buffer) -> Unit {
  if self.have_output {
    if self.have_separate_output || self.out_len != self.idx {
      self.ensure(self.out_len + 1)
      self.set_out_info(self.out_len, self.info[self.idx])
    }
    self.out_len += 1
  }
  self.idx += 1
}

///|
fn Buffer::next_glyphs(self : Buffer, n : Int) -> Unit {
  if self.have_output {
    if self.have_separate_output || self.out_len != self.idx {
      self.ensure(self.out_len + n)
      self.copy_infos_to_out(self.idx, self.out_len, n)
    }
    self.out_len += n
  }
  self.idx += n
}

///|
fn Buffer::skip_glyph(self : Buffer) -> Unit {
  self.idx += 1
}

///|
fn Buffer::set_masks(self : Buffer, value : Int, mask : Int, cluster_start : Int, cluster_end : Int) -> Unit {
  if mask == 0 {
    return
  }
  let not_mask = mask ^ -1
  let value = value & mask
  for k in 0..<self.len {
    let info = self.info[k]
    if cluster_start == 0 && cluster_end == -1 {
      info.mask = (info.mask & not_mask) | value
    } else if cluster_start <= info.cluster && (cluster_end == -1 || info.cluster < cluster_end) {
      info.mask = (info.mask & not_mask) | value
    }
  }
}

///|
fn Buffer::merge_clusters(self : Buffer, start : Int, end : Int) -> Unit {
  if end - start < 2 {
    return
  }
  let mut start = start
  let mut end = end
  let mut cluster = self.info[start].cluster
  for k in start..<end {
    if self.info[k].cluster < cluster {
      cluster = self.info[k].cluster
    }
  }
  if cluster != self.info[end - 1].cluster {
    while end < self.len && self.info[end - 1].cluster == self.info[end].cluster {
      end += 1
    }
  }
  if cluster != self.info[start].cluster {
    while self.idx < start && self.info[start - 1].cluster == self.info[start].cluster {
      start -= 1
    }
  }
  let start_cluster = self.info[start].cluster
  if self.idx == start && start_cluster != cluster {
    let out = self.out_info()
    let mut i = self.out_len
    while i != 0 {
      if out[i - 1].cluster != start_cluster {
        break
      }
      out[i - 1].cluster = cluster
      i -= 1
    }
  }
  for k in start..<end {
    self.info[k].cluster = cluster
  }
}

///|
fn Buffer::merge_out_clusters(self : Buffer, start : Int, end : Int) -> Unit {
  if end - start < 2 {
    return
  }
  let out = self.out_info()
  let mut start = start
  let mut end = end
  let mut cluster = out[start].cluster
  for k in start..<end {
    if out[k].cluster < cluster {
      cluster = out[k].cluster
    }
  }
  while start != 0 && out[start - 1].cluster == out[start].cluster {
    start -= 1
  }
  while end < self.out_len && out[end - 1].cluster == out[end].cluster {
    end += 1
  }
  if end == self.out_len {
    let end_cluster = out[end - 1].cluster
    let mut i = self.idx
    while i < self.len {
      if self.info[i].cluster != end_cluster {
        break
      }
      self.info[i].cluster = cluster
      i += 1
    }
  }
  for k in start..<end {
    out[k].cluster = cluster
  }
}

///|
fn Buffer::delete_glyph(self : Buffer) -> Unit {
  self.merge_deleted_cluster()
  self.skip_glyph()
}

///|
fn Buffer::merge_deleted_cluster(self : Buffer) -> Unit {
  let cluster = self.info[self.idx].cluster
  if self.idx + 1 < self.len && self.info[self.idx + 1].cluster == cluster {
    return
  }
  if self.out_len > 0 {
    let out = self.out_info()
    let old = out[self.out_len - 1].cluster
    if old == cluster {
      return
    }
    if cluster < old {
      let mut i = self.out_len
      while i != 0 {
        if out[i - 1].cluster != old {
          break
        }
        out[i - 1].cluster = cluster
        i -= 1
      }
    }
    return
  }
  if self.idx + 1 < self.len {
    self.merge_clusters(self.idx, self.idx + 2)
  }
}

///|
fn Buffer::delete_glyphs_inplace(self : Buffer, filter : (GlyphInfo) -> Bool) -> Unit {
  let mut j = 0
  for i in 0..<self.len {
    let info = self.info[i]
    if filter(info) {
      let cluster = info.cluster
      if i + 1 < self.len && self.info[i + 1].cluster == cluster {
        continue
      }
      if j != 0 {
        let old = self.info[j - 1].cluster
        if cluster < old {
          let mut k = j
          while k > 0 {
            if self.info[k - 1].cluster != old {
              break
            }
            self.info[k - 1].cluster = cluster
            k -= 1
          }
        }
        continue
      }
      if i + 1 < self.len {
        self.merge_clusters(i, i + 2)
      }
      continue
    }
    if j != i {
      self.info[j] = info
      if i < self.pos.length() && j < self.pos.length() {
        self.pos[j] = self.pos[i]
      }
    }
    j += 1
  }
  self.len = j
}

///|
fn Buffer::move_to(self : Buffer, i : Int) -> Bool {
  if !self.have_output {
    self.idx = i
    return true
  }
  if !self.successful {
    return false
  }
  if self.out_len < i {
    let count = i - self.out_len
    self.make_room_for(count, count)
    self.copy_infos_to_out(self.idx, self.out_len, count)
    self.idx += count
    self.out_len += count
  } else if self.out_len > i {
    let count = self.out_len - i
    if self.idx < count {
      self.shift_forward(count - self.idx)
    }
    self.idx -= count
    self.out_len -= count
    self.copy_out_to_infos(self.out_len, self.idx, count)
  }
  true
}

///|
fn Buffer::shift_forward(self : Buffer, count : Int) -> Unit {
  self.ensure(self.len + count)
  let moved = self.len - self.idx
  let mut k = moved - 1
  while k >= 0 {
    self.info[self.idx + count + k] = self.info[self.idx + k]
    k -= 1
  }
  for k in moved..<count {
    self.info[self.idx + k] = GlyphInfo::new()
  }
  self.len += count
  self.idx += count
}

///|
/// An insertion sort of [start, end) where `cmp(a, b)` says a goes after b, merging the clusters of what moves.
fn Buffer::sort(self : Buffer, start : Int, end : Int, cmp : (GlyphInfo, GlyphInfo) -> Bool) -> Unit {
  for i in (start + 1)..<end {
    let item = self.info[i]
    let mut j = i
    while j > start && cmp(self.info[j - 1], item) {
      j -= 1
    }
    if i == j {
      continue
    }
    self.merge_clusters(j, i + 1)
    let mut k = i
    while k > j {
      self.info[k] = self.info[k - 1]
      k -= 1
    }
    self.info[j] = item
  }
}

///|
fn Buffer::next_syllable(self : Buffer, start : Int) -> Int {
  if start >= self.len {
    return start
  }
  let s = self.info[start].syllable()
  let mut i = start
  while i < self.len && i - start < 127 && self.info[i].syllable() == s {
    i += 1
  }
  i
}
