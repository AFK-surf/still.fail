// usvg's text elements (parser/text.rs): `text`, `tspan`, `tref` and `textPath` as chunks of characters (a chunk
// starts where a character has an absolute position or a text path starts or ends) made of spans of one style each.
// Offsets into a chunk's text are UTF-8 bytes, as in Rust.

///|
priv struct TDeco {
  fill : Fill?
  stroke : SStroke?
}

///|
priv enum BShift {
  BsBaseline
  BsSub
  BsSuper
  BsNumber(Float)
}

///|
priv struct SFont {
  families : Array[FontFamily]
  style : @font.FontStyle
  /// 1 (ultra-condensed) to 9 (ultra-expanded)
  stretch : Int
  weight : Int
  variations : Array[(String, Float)]
}

///|
fn SFont::key(self : SFont) -> String {
  let sb = StringBuilder::new()
  for f in self.families {
    sb.write_string(f.to_string())
    sb.write_char('|')
  }
  sb.write_string(self.style.to_string())
  sb.write_string("|" + self.stretch.to_string() + "|" + self.weight.to_string())
  for v in self.variations {
    sb.write_string("|" + v.0 + "=" + v.1.to_string())
  }
  sb.to_string()
}

///|
priv struct TextSpan {
  start : Int
  mut end : Int
  fill : Fill?
  stroke : SStroke?
  paint_order : PaintOrder
  font : SFont
  font_size : Float
  small_caps : Bool
  apply_kerning : Bool
  /// font-optical-sizing: auto (the default) sets an opsz axis the font has to the font size
  optical_auto : Bool
  underline : TDeco?
  overline : TDeco?
  line_through : TDeco?
  visible : Bool
  dominant_baseline : String
  alignment_baseline : String
  baseline_shift : Array[BShift]
  letter_spacing : Float
  word_spacing : Float
  text_length : Float?
  length_adjust_glyphs : Bool
}

///|
priv enum TextFlow {
  Linear
  OnPath(Float, @skia.Path)
}

///|
priv struct TextChunk {
  x : Float?
  y : Float?
  /// 0 start, 1 middle, 2 end
  anchor : Int
  spans : Array[TextSpan]
  flow : TextFlow
  /// the characters, and where each starts in UTF-8 bytes
  chars : Array[Char]
  bytes : Array[Int]
  mut byte_len : Int
}

///|
fn TextChunk::push(self : TextChunk, c : Char) -> Unit {
  self.chars.push(c)
  self.bytes.push(self.byte_len)
  self.byte_len += utf8_len(c)
}

///|
fn utf8_len(c : Char) -> Int {
  let v = c.to_int()
  if v < 0x80 {
    1
  } else if v < 0x800 {
    2
  } else if v < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// The character index of a byte offset (ByteIndex::code_point_at).
fn TextChunk::char_at_byte(self : TextChunk, b : Int) -> Int {
  let mut i = 0
  while i < self.bytes.length() && self.bytes[i] != b {
    i += 1
  }
  i
}

///|
priv struct CharPos {
  mut x : Float?
  mut y : Float?
  mut dx : Float?
  mut dy : Float?
}

///|
priv struct ParsedText {
  id : String
  rendering : TextRendering
  dx : Array[Float]
  dy : Array[Float]
  rotate : Array[Float]
  vertical : Bool
  chunks : Array[TextChunk]
  abs_transform : @skia.Transform
}

///|
fn convert_text(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  let pos_list = resolve_positions_list(doc, node, state)
  let rotate = resolve_rotate_list(doc, node)
  let vertical = match doc.find_attr(node, "writing-mode") {
    Some("tb") | Some("tb-rl") | Some("vertical-rl") | Some("vertical-lr") => true
    _ => false
  }
  let chunks = collect_text_chunks(doc, node, pos_list, state, cache)
  let rendering = match doc.find_attr(node, "text-rendering") {
    Some(v) => parse_text_rendering(v).unwrap_or(state.opt.text_rendering)
    None => state.opt.text_rendering
  }
  let id = if state.parent_markers.is_empty() { doc.element_id(node) } else { "" }
  let text : ParsedText = {
    id,
    rendering,
    dx: pos_list.map(fn(p) { p.dx.unwrap_or(0.0) }),
    dy: pos_list.map(fn(p) { p.dy.unwrap_or(0.0) }),
    rotate,
    vertical,
    chunks,
    abs_transform: parent.abs_transform,
  }
  match layout_and_flatten(text, state.opt) {
    Some(t) => parent.children.push(NText(t))
    None => ()
  }
}

///|
priv struct IterState {
  mut chars_count : Int
  mut split_chunk : Bool
  mut flow : TextFlow
  chunks : Array[TextChunk]
}

///|
fn collect_text_chunks(doc : SDoc, node : Int, pos : Array[CharPos], state : State, cache : Cache) -> Array[TextChunk] {
  let st : IterState = { chars_count: 0, split_chunk: false, flow: Linear, chunks: [] }
  collect_chunks_impl(doc, node, pos, state, cache, st)
  st.chunks
}

///|
fn count_chars(doc : SDoc, node : Int) -> Int {
  let mut n = 0
  for d in doc.descendants(node) {
    if doc.nodes[d].kind == SText {
      n += char_count(doc.nodes[d].text)
    }
  }
  n
}

///|
fn char_count(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
fn collect_chunks_impl(doc : SDoc, parent : Int, pos : Array[CharPos], state : State, cache : Cache, st : IterState) -> Unit {
  for child in doc.children(parent) {
    if doc.is_element(child) {
      if doc.tag(child) == "textPath" {
        if doc.tag(parent) != "text" {
          st.chars_count += count_chars(doc, child)
          continue
        }
        match resolve_text_flow(doc, child, state) {
          Some(f) => st.flow = f
          None => {
            st.chars_count += count_chars(doc, child)
            continue
          }
        }
        st.split_chunk = true
      }
      collect_chunks_impl(doc, child, pos, state, cache, st)
      st.flow = Linear
      if doc.tag(child) == "textPath" {
        st.split_chunk = true
      }
      continue
    }
    let text = doc.nodes[child].text
    if !doc.is_visible_element(parent, state.opt) {
      st.chars_count += char_count(text)
      continue
    }
    let anchor = match doc.find_attr(parent, "text-anchor") {
      Some("middle") => 1
      Some("end") => 2
      _ => 0
    }
    let font_size = resolve_font_size(doc, parent, state)
    if !(font_size > 0.0 && ffin(font_size)) {
      st.chars_count += char_count(text)
      continue
    }
    let font = convert_font(doc, parent, state)
    let raw_order = match doc.find_attr(parent, "paint-order") {
      Some(v) => parse_paint_order(v)
      None => default_paint_order()
    }
    let mut dominant = doc.find_attr(parent, "dominant-baseline").unwrap_or("auto")
    if dominant == "no-change" {
      dominant = doc.find_attr(doc.parent_element(parent), "dominant-baseline").unwrap_or("auto")
    }
    let mut apply_kerning = true
    if doc.resolve_length(parent, "kerning", state, -1.0) == 0.0 {
      apply_kerning = false
    } else if doc.find_attr(parent, "font-kerning") == Some("none") {
      apply_kerning = false
    }
    let mut text_length = doc.try_convert_length(parent, "textLength", UserSpaceOnUse, state)
    match text_length {
      Some(n) => if n < 0.0 { text_length = None }
      None => ()
    }
    let visible = match doc.find_attr(parent, "visibility") {
      Some(v) => parse_visibility(v).unwrap_or(Visible) == Visible
      None => true
    }
    let (underline, overline, line_through) = resolve_decoration(doc, parent, state, cache)
    let span : TextSpan = {
      start: 0,
      end: 0,
      fill: resolve_fill(doc, parent, true, state, cache),
      stroke: resolve_stroke(doc, parent, true, state, cache),
      paint_order: svg_paint_order(raw_order),
      font,
      font_size,
      small_caps: doc.find_attr(parent, "font-variant") == Some("small-caps"),
      apply_kerning,
      optical_auto: doc.find_attr(parent, "font-optical-sizing") != Some("none"),
      underline,
      overline,
      line_through,
      visible,
      dominant_baseline: dominant,
      alignment_baseline: doc.find_attr(parent, "alignment-baseline").unwrap_or("auto"),
      baseline_shift: convert_baseline_shift(doc, parent, state),
      letter_spacing: doc.resolve_length(parent, "letter-spacing", state, 0.0),
      word_spacing: doc.resolve_length(parent, "word-spacing", state, 0.0),
      text_length,
      length_adjust_glyphs: doc.find_attr(parent, "lengthAdjust") == Some("spacingAndGlyphs"),
    }
    let mut is_new_span = true
    for c in text {
      let p = pos[st.chars_count]
      let is_new_chunk = p.x is Some(_) || p.y is Some(_) || st.split_chunk || st.chunks.is_empty()
      st.split_chunk = false
      let char_len = utf8_len(c)
      if is_new_chunk {
        let chunk : TextChunk = {
          x: p.x,
          y: p.y,
          anchor,
          spans: [{ ..span, start: 0, end: char_len }],
          flow: st.flow,
          chars: [],
          bytes: [],
          byte_len: 0,
        }
        chunk.push(c)
        st.chunks.push(chunk)
      } else if is_new_span {
        let chunk = st.chunks[st.chunks.length() - 1]
        chunk.spans.push({ ..span, start: chunk.byte_len, end: chunk.byte_len + char_len })
        chunk.push(c)
      } else {
        let chunk = st.chunks[st.chunks.length() - 1]
        chunk.push(c)
        let last = chunk.spans[chunk.spans.length() - 1]
        last.end = last.end + char_len
      }
      is_new_span = false
      st.chars_count += 1
    }
  }
}

///|
fn resolve_text_flow(doc : SDoc, node : Int, state : State) -> TextFlow? {
  let mut path : @skia.Path? = None
  match doc.attr(node, "path") {
    Some(d) => path = convert_path_data(d)
    None => ()
  }
  if path is None {
    let link = doc.node_attr(node, "href")
    if link < 0 {
      return None
    }
    let p = match convert_shape(doc, link, state) {
      Some(p) => p
      None => return None
    }
    let ts = doc.resolve_transform(link, "transform", state)
    path = if !ts.is_identity() { p.transform(ts) } else { Some(p) }
    if path is None || non_empty_id(doc.element_id(link)) is None {
      return None
    }
  }
  let path = path.unwrap()
  let so = doc.attr_length(node, "startOffset").unwrap_or(Length::zero())
  let start_offset = if so.unit == Percent {
    fd(path_length(path) * (so.number / 100.0))
  } else {
    doc.resolve_length(node, "startOffset", state, 0.0)
  }
  Some(OnPath(start_offset, path))
}

///|
fn convert_font(doc : SDoc, node : Int, state : State) -> SFont {
  let style : @font.FontStyle = match doc.find_attr(node, "font-style") {
    Some("italic") => Italic
    Some("oblique") => Oblique
    _ => Normal
  }
  let stretch = {
    let mut s = 5
    for n in doc.ancestors(node) {
      if doc.has_attr(n, "font-stretch") {
        s = match doc.attr(n, "font-stretch").unwrap_or("") {
          "narrower" | "condensed" => 3
          "ultra-condensed" => 1
          "extra-condensed" => 2
          "semi-condensed" => 4
          "semi-expanded" => 6
          "wider" | "expanded" => 7
          "extra-expanded" => 8
          "ultra-expanded" => 9
          _ => 5
        }
        break
      }
    }
    s
  }
  let weight = resolve_font_weight(doc, node)
  let variations = parse_font_variation_settings(doc, node)
  let has = fn(tag : String) { variations.iter().any(fn(v) { v.0 == tag }) }
  let has_wght = has("wght")
  let has_wdth = has("wdth")
  let has_ital = has("ital")
  let has_slnt = has("slnt")
  if !has_wght {
    variations.push(("wght", fi(weight)))
  }
  if !has_wdth {
    let w : Float = match stretch {
      1 => 50.0
      2 => 62.5
      3 => 75.0
      4 => 87.5
      6 => 112.5
      7 => 125.0
      8 => 150.0
      9 => 200.0
      _ => 100.0
    }
    if w != 100.0 {
      variations.push(("wdth", w))
    }
  }
  if !has_ital && style == Italic {
    variations.push(("ital", 1.0))
  }
  if !has_slnt && style == Oblique {
    variations.push(("slnt", -12.0))
  }
  let mut families_text = ""
  for n in doc.ancestors(node) {
    if doc.has_attr(n, "font-family") {
      families_text = doc.attr(n, "font-family").unwrap_or("")
      break
    }
  }
  let mut families = parse_font_families(families_text).unwrap_or([])
  if families.is_empty() {
    families = [FNamed(state.opt.font_family)]
  }
  { families, style, stretch, weight, variations }
}

///|
fn parse_font_variation_settings(doc : SDoc, node : Int) -> Array[(String, Float)] {
  let mut value : String? = None
  for n in doc.ancestors(node) {
    if doc.has_attr(n, "font-variation-settings") {
      value = Some(doc.attr(n, "font-variation-settings").unwrap_or(""))
      break
    }
  }
  let out : Array[(String, Float)] = []
  let value = match value {
    Some(v) => v
    None => return out
  }
  if value.to_lower() == "normal" || value == "" {
    return out
  }
  for part in value.split(",") {
    let part = part.trim(chars=" \t\n\r").to_string()
    if part == "" {
      continue
    }
    let q = part.code_unit_at(0).to_int()
    if q != 0x22 && q != 0x27 {
      continue
    }
    let rest = part.view(start_offset=1).to_string()
    let close = match rest.find(Int::unsafe_to_char(q).to_string()) {
      Some(i) => i
      None => rest.length()
    }
    let tag = rest.view(end_offset=close).to_string()
    if tag.length() != 4 {
      continue
    }
    let num = if close + 1 <= rest.length() {
      rest.view(start_offset=if close < rest.length() { close + 1 } else { close }).to_string().trim(chars=" \t\n\r").to_string()
    } else {
      ""
    }
    match parse_number_str(num) {
      Some(v) => out.push((tag, fd(v)))
      None => ()
    }
  }
  out
}

///|
fn resolve_font_weight(doc : SDoc, node : Int) -> Int {
  let nodes = doc.ancestors(node)
  let mut weight = 400
  let mut i = nodes.length() - 2
  while i >= 0 {
    let n = nodes[i]
    i -= 1
    weight = match doc.attr(n, "font-weight").unwrap_or("") {
      "normal" => 400
      "bold" => 700
      "100" => 100
      "200" => 200
      "300" => 300
      "400" => 400
      "500" => 500
      "600" => 600
      "700" => 700
      "800" => 800
      "900" => 900
      "bolder" => {
        let step = if weight == 400 { 300 } else { 100 }
        let w = weight + step
        if w > 900 { 900 } else if w < 100 { 100 } else { w }
      }
      "lighter" => {
        let step = if weight == 400 { 200 } else { 100 }
        let w = weight - step
        if w > 900 { 900 } else if w < 100 { 100 } else { w }
      }
      _ => weight
    }
  }
  weight
}

///|
fn resolve_positions_list(doc : SDoc, text_node : Int, state : State) -> Array[CharPos] {
  let total = count_chars(doc, text_node)
  let list = Array::makei(total, fn(_) { { x: None, y: None, dx: None, dy: None } })
  let mut offset = 0
  for child in doc.descendants(text_node) {
    if doc.is_element(child) {
      let tag = doc.tag(child)
      if !(tag == "text" || tag == "tspan") {
        continue
      }
      let child_chars = count_chars(doc, child)
      for aid in ["x", "y", "dx", "dy"] {
        match convert_list(doc, child, aid, state) {
          Some(nums) => {
            let len = if nums.length() < child_chars { nums.length() } else { child_chars }
            for i in 0..<len {
              let p = list[offset + i]
              match aid {
                "x" => p.x = Some(nums[i])
                "y" => p.y = Some(nums[i])
                "dx" => p.dx = Some(nums[i])
                _ => p.dy = Some(nums[i])
              }
            }
          }
          None => ()
        }
      }
    } else if doc.nodes[child].kind == SText {
      offset += char_count(doc.nodes[child].text)
    }
  }
  list
}

///|
fn resolve_rotate_list(doc : SDoc, text_node : Int) -> Array[Float] {
  let list = Array::make(count_chars(doc, text_node), (0.0 : Float))
  let mut last : Float = 0.0
  let mut offset = 0
  for child in doc.descendants(text_node) {
    if doc.is_element(child) {
      match doc.attr_numbers(child, "rotate") {
        Some(rotate) =>
          for i in 0..<count_chars(doc, child) {
            match rotate.get(i) {
              Some(a) => {
                list[offset + i] = a
                last = a
              }
              None => list[offset + i] = last
            }
          }
        None => ()
      }
    } else if doc.nodes[child].kind == SText {
      offset += char_count(doc.nodes[child].text)
    }
  }
  list
}

///|
fn resolve_decoration(doc : SDoc, tspan : Int, state : State, cache : Cache) -> (TDeco?, TDeco?, TDeco?) {
  let find = fn(n : Int, value : String) {
    match doc.attr(n, "text-decoration") {
      Some(s) => s.split(" ").any(fn(v) { v.to_string() == value })
      None => false
    }
  }
  let gen = fn(value : String) -> TDeco? {
    if !doc.ancestors(tspan).iter().any(fn(n) { find(n, value) }) {
      return None
    }
    let mut node = -1
    for n in doc.ancestors(tspan) {
      if find(n, value) || doc.tag(n) == "text" {
        node = n
        break
      }
    }
    if node < 0 {
      return Some({ fill: None, stroke: None })
    }
    Some({ fill: resolve_fill(doc, node, true, state, cache), stroke: resolve_stroke(doc, node, true, state, cache) })
  }
  (gen("underline"), gen("overline"), gen("line-through"))
}

///|
fn convert_baseline_shift(doc : SDoc, node : Int, state : State) -> Array[BShift] {
  let shift : Array[BShift] = []
  for n in doc.ancestors(node) {
    if doc.tag(n) == "text" {
      break
    }
    let len = match doc.raw_attr(n, "baseline-shift") {
      Some(v) => parse_length_str(v)
      None => None
    }
    match len {
      Some(l) =>
        if l.unit == Percent {
          shift.push(BsNumber(resolve_font_size(doc, n, state) * (fd(l.number) / 100.0)))
        } else {
          shift.push(BsNumber(convert_length(l, doc, n, "baseline-shift", ObjectBoundingBox, state)))
        }
      None =>
        match doc.attr(n, "baseline-shift") {
          Some("sub") => shift.push(BsSub)
          Some("super") => shift.push(BsSuper)
          Some(_) => shift.push(BsBaseline)
          None => ()
        }
    }
  }
  if shift.iter().all(fn(s) { s is BsBaseline }) {
    shift.clear()
  }
  shift
}
