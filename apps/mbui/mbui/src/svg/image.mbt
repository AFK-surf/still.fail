// usvg's images (parser/image.rs) and resvg's (image.rs): `image` elements and feImage's pictures, from data URLs or
// files, raster ones decoded when drawn, SVG ones read as a tree of their own.

///|
priv enum ImageData {
  /// the format ("png", "jpeg", "gif", "webp") and the encoded bytes
  Encoded(String, Bytes)
  Nested(Tree)
}

///|
fn convert_image(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  let href = match doc.raw_attr(node, "href") {
    Some(h) => h
    None => return
  }
  let kind = match get_href_data(href, state) {
    Some(k) => k
    None => return
  }
  let visible = match doc.find_attr(node, "visibility") {
    Some(v) => parse_visibility(v).unwrap_or(Visible) == Visible
    None => true
  }
  let rendering = match doc.find_attr(node, "image-rendering") {
    Some(v) => parse_image_rendering(v).unwrap_or(state.opt.image_rendering)
    None => state.opt.image_rendering
  }
  let id = if state.parent_markers.is_empty() { doc.element_id(node) } else { "" }
  let actual = match image_actual_size(kind) {
    Some(s) => s
    None => return
  }
  let x = doc.convert_user_length(node, "x", state, Length::zero())
  let y = doc.convert_user_length(node, "y", state, Length::zero())
  let mut width = doc.convert_user_length(node, "width", state, { number: actual.width.to_double(), unit: LNone })
  let mut height = doc.convert_user_length(node, "height", state, { number: actual.height.to_double(), unit: LNone })
  match (doc.attr_length(node, "width"), doc.attr_length(node, "height")) {
    (Some(_), None) => height = actual.height * (width / actual.width)
    (None, Some(_)) => width = actual.width * (height / actual.height)
    _ => ()
  }
  let aspect = doc.attr_aspect(node).unwrap_or(AspectRatio::default())
  let rect = match @skia.NonZeroRect::from_xywh(x, y, width, height) {
    Some(r) => r
    None => return
  }
  convert_image_inner(kind, id, visible, rendering, aspect, actual, rect, cache, parent)
}

///|
fn convert_image_inner(
  kind : ImageData,
  id : String,
  visible : Bool,
  rendering : ImageRendering,
  aspect : AspectRatio,
  actual : @skia.Size,
  rect : @skia.NonZeroRect,
  cache : Cache,
  parent : Group,
) -> Unit {
  let aligned = fit_view_box(actual, rect, aspect)
  let (ax, ay) = aligned_pos(aspect.align, rect.x(), rect.y(), rect.width() - aligned.width, rect.height() - aligned.height)
  let view_box = size_to_non_zero_rect(aligned, ax, ay)
  let image_ts = @skia.Transform::from_row(
    view_box.width() / actual.width,
    0.0,
    0.0,
    view_box.height() / actual.height,
    view_box.x(),
    view_box.y(),
  )
  let abs_transform = parent.abs_transform.pre_concat(image_ts)
  let abs_bbox = match view_box.transform(parent.abs_transform) {
    Some(b) => b
    None => return
  }
  let g = Group::empty()
  g.id = id
  g.children.push(NImage({ id: "", visible, size: actual, rendering, kind, abs_transform, abs_bbox }))
  g.transform = image_ts
  g.abs_transform = abs_transform
  if aspect.slice {
    let path = new_simple_path(@skia.PathBuilder::from_rect(rect.to_rect()))
    path.fill = Some(Fill::default())
    let root = Group::empty()
    root.children.push(NPath(path))
    let clip : ClipPath = {
      id: cache.gen_clip_path_id(),
      transform: @skia.Transform::default(),
      clip_path: None,
      root,
    }
    let g2 = Group::empty()
    g2.id = g.id
    g.id = ""
    g2.abs_transform = parent.abs_transform
    g2.clip_path = Some(clip)
    g2.children.push(NGroup(g))
    let bbox = rect.to_rect()
    g2.fixed_bbox = Some(bbox)
    g2.fixed_abs_bbox = bbox.transform(g2.abs_transform)
    parent.children.push(NGroup(g2))
  } else {
    parent.children.push(NGroup(g))
  }
}

///|
fn fit_view_box(size : @skia.Size, rect : @skia.NonZeroRect, aspect : AspectRatio) -> @skia.Size {
  let s = rect.size()
  if aspect.align == AlignNone {
    s
  } else if aspect.slice {
    size_scale(size, s, true)
  } else {
    size_scale(size, s, false)
  }
}

///|
/// Size::scale_to / expand_to (size_scale_f64 in f32).
fn size_scale(s1 : @skia.Size, s2 : @skia.Size, expand : Bool) -> @skia.Size {
  let rw = s2.height * s1.width / s1.height
  let with_h = if expand { rw <= s2.width } else { rw >= s2.width }
  if !with_h {
    { width: rw, height: s2.height }
  } else {
    let h = s2.width * s1.height / s1.width
    { width: s2.width, height: h }
  }
}

///|
fn image_actual_size(kind : ImageData) -> @skia.Size? {
  match kind {
    Nested(t) => Some(t.size)
    Encoded(_, data) =>
      match encoded_image_size(data) {
        Some((w, h)) => @skia.Size::from_wh(fi(w), fi(h))
        None => None
      }
  }
}

///|
/// The width and height a picture's header says (the imagesize crate's blob_size, for the formats usvg reads).
fn encoded_image_size(b : Bytes) -> (Int, Int)? {
  let n = b.length()
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let le16 = fn(i : Int) -> Int { u8(i) | (u8(i + 1) << 8) }
  let be32 = fn(i : Int) -> Int { (be16(i) << 16) | be16(i + 2) }
  match image_format(b) {
    Some("png") => if n >= 24 { Some((be32(16), be32(20))) } else { None }
    Some("gif") => if n >= 10 { Some((le16(6), le16(8))) } else { None }
    Some("webp") => {
      let kind = u8(15)
      if kind == 0x20 {
        Some((le16(26) & 0x3FFF, le16(28) & 0x3FFF))
      } else if kind == 0x4C {
        let bits = u8(21) | (u8(22) << 8) | (u8(23) << 16) | (u8(24) << 24)
        Some(((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1))
      } else if kind == 0x58 {
        Some(((u8(24) | (u8(25) << 8) | (u8(26) << 16)) + 1, (u8(27) | (u8(28) << 8) | (u8(29) << 16)) + 1))
      } else {
        None
      }
    }
    Some("jpeg") => {
      let mut i = 2
      while i + 9 < n {
        if u8(i) != 0xFF {
          i += 1
          continue
        }
        let m = u8(i + 1)
        if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) || m == 0xFF {
          i += if m == 0xFF { 1 } else { 2 }
          continue
        }
        if m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC {
          return Some((be16(i + 7), be16(i + 5)))
        }
        i += 2 + be16(i + 2)
      }
      None
    }
    _ => None
  }
}

///|
fn image_format(b : Bytes) -> String? {
  let n = b.length()
  if n >= 8 && b[0] == b'\x89' && b[1] == b'P' && b[2] == b'N' && b[3] == b'G' {
    Some("png")
  } else if n >= 6 && b[0] == b'G' && b[1] == b'I' && b[2] == b'F' {
    Some("gif")
  } else if n >= 3 && b[0] == b'\xFF' && b[1] == b'\xD8' && b[2] == b'\xFF' {
    Some("jpeg")
  } else if n >= 16 && b[0] == b'R' && b[1] == b'I' && b[2] == b'F' && b[3] == b'F' && b[8] == b'W' && b[9] == b'E' &&
    b[10] == b'B' && b[11] == b'P' {
    Some("webp")
  } else {
    None
  }
}

///|
fn get_href_data(href : String, state : State) -> ImageData? {
  match parse_data_url(href) {
    Some((mime, data)) =>
      match mime {
        "image/jpg" | "image/jpeg" => Some(Encoded("jpeg", data))
        "image/png" => Some(Encoded("png", data))
        "image/gif" => Some(Encoded("gif", data))
        "image/webp" => Some(Encoded("webp", data))
        "image/svg+xml" => load_sub_svg(data, state.opt)
        "text/plain" =>
          match image_format(data) {
            Some(f) => Some(Encoded(f, data))
            None => load_sub_svg(data, state.opt)
          }
        _ => None
      }
    None => {
      let data = match (state.opt.read_file)(href) {
        Some(d) => d
        None => return None
      }
      let lower = href.to_lower()
      if lower.has_suffix(".svg") || lower.has_suffix(".svgz") {
        load_sub_svg(data, state.opt)
      } else {
        match image_format(data) {
          Some(f) => Some(Encoded(f, data))
          None => None
        }
      }
    }
  }
}

///|
fn load_sub_svg(data : Bytes, opt : Options) -> ImageData? {
  let nested : Options = {
    ..Options::default(),
    dpi: opt.dpi,
    font_size: opt.font_size,
    languages: opt.languages,
    shape_rendering: opt.shape_rendering,
    text_rendering: opt.text_rendering,
    image_rendering: opt.image_rendering,
    default_width: opt.default_width,
    default_height: opt.default_height,
    fonts: opt.fonts,
  }
  let data = if data.length() >= 2 && data[0] == b'\x1F' && data[1] == b'\x8B' {
    match @zip.gunzip(data) {
      Some(d) => d
      None => return None
    }
  } else {
    data
  }
  let text = @utf8.decode(data) catch { _ => return None }
  match tree_from_str(text, nested) {
    Some(t) => Some(Nested(t))
    None => None
  }
}

///|
/// A `data:` URL's MIME type (type/subtype, lower case; text/plain where it has none or a broken one) and its
/// bytes (the data_url crate's process + decode_to_vec); None where it is not one.
fn parse_data_url(href : String) -> (String, Bytes)? {
  let s = href.trim(chars=" \t\n\r\u{0C}").to_string()
  if s.length() < 5 || s.view(end_offset=5).to_string().to_lower() != "data:" {
    return None
  }
  let rest = s.view(start_offset=5).to_string()
  let comma = match rest.find(",") {
    Some(c) => c
    None => return None
  }
  let meta = rest.view(end_offset=comma).to_string()
  let body = rest.view(start_offset=comma + 1).to_string()
  let mut meta_t = meta.trim(chars=" \t\n\r").to_string()
  let mut base64 = false
  let lower = meta_t.to_lower()
  match lower.rev_find(";") {
    Some(i) => {
      let tail = lower.view(start_offset=i + 1).to_string().trim(chars=" ").to_string()
      if tail == "base64" {
        base64 = true
        meta_t = meta_t.view(end_offset=i).to_string()
      }
    }
    None => ()
  }
  let mime = {
    let essence = match meta_t.find(";") {
      Some(i) => meta_t.view(end_offset=i).to_string()
      None => meta_t
    }
    let essence = essence.trim(chars=" \t\n\r").to_string().to_lower()
    match essence.find("/") {
      Some(i) =>
        if i > 0 && i < essence.length() - 1 {
          essence
        } else {
          "text/plain"
        }
      None => "text/plain"
    }
  }
  let bytes = percent_decode(body)
  if base64 {
    match forgiving_base64(bytes) {
      Some(b) => Some((mime, b))
      None => None
    }
  } else {
    Some((mime, bytes))
  }
}

///|
fn hex_val(c : Int) -> Int {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else {
    -1
  }
}

///|
fn percent_decode(s : String) -> Bytes {
  let utf8 = @utf8.encode(s)
  let out : Array[Byte] = []
  let n = utf8.length()
  let mut i = 0
  while i < n {
    let c = utf8[i].to_int()
    if c == 0x25 && i + 2 < n && hex_val(utf8[i + 1].to_int()) >= 0 && hex_val(utf8[i + 2].to_int()) >= 0 {
      out.push((hex_val(utf8[i + 1].to_int()) * 16 + hex_val(utf8[i + 2].to_int())).to_byte())
      i += 3
    } else {
      out.push(utf8[i])
      i += 1
    }
  }
  Bytes::from_array(out)
}

///|
/// WHATWG's forgiving-base64 decode.
fn forgiving_base64(b : Bytes) -> Bytes? {
  let vals : Array[Int] = []
  for byte in b {
    let c = byte.to_int()
    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D {
      continue
    }
    vals.push(c)
  }
  // trailing padding
  if vals.length() % 4 == 0 {
    if vals.length() >= 1 && vals[vals.length() - 1] == 0x3D {
      ignore(vals.pop())
      if vals.length() >= 1 && vals[vals.length() - 1] == 0x3D {
        ignore(vals.pop())
      }
    }
  }
  if vals.length() % 4 == 1 {
    return None
  }
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for c in vals {
    let v = if c >= 0x41 && c <= 0x5A {
      c - 0x41
    } else if c >= 0x61 && c <= 0x7A {
      c - 0x61 + 26
    } else if c >= 0x30 && c <= 0x39 {
      c - 0x30 + 52
    } else if c == 0x2B {
      62
    } else if c == 0x2F {
      63
    } else {
      return None
    }
    acc = (acc << 6) | v
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.push(((acc >> bits) & 0xFF).to_byte())
    }
  }
  Some(Bytes::from_array(out))
}

// ── drawing (resvg image.rs) ──────────────────────────────────────────

///|
fn render_image(image : SImage, ts : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  if !image.visible {
    return
  }
  render_image_kind(image.kind, ts, image.rendering, pixmap)
}

///|
fn render_image_kind(kind : ImageData, ts : @skia.Transform, rendering : ImageRendering, pixmap : @skia.Pixmap) -> Unit {
  match kind {
    Nested(tree) => {
      let sub = @skia.Pixmap::new(pixmap.width, pixmap.height).unwrap()
      render_tree(tree, ts, sub)
      pixmap.draw_pixmap(0, 0, sub, @skia.PixmapPaint::default(), @skia.Transform::default(), None)
    }
    Encoded(format, data) => {
      let raster = match decode_raster(format, data) {
        Some(r) => r
        None => return
      }
      let rect = match @skia.Rect::from_xywh(0.0, 0.0, fi(raster.width), fi(raster.height)) {
        Some(r) => r
        None => return
      }
      let quality : @skia.FilterQuality = match rendering {
        OptimizeQuality | HighQuality => Bicubic
        Smooth => Bilinear
        IrOptimizeSpeed | IrCrispEdges | Pixelated => Nearest
      }
      let paint = @skia.Paint::default()
      paint.shader = @skia.Pattern::new(raster, Pad, quality, 1.0, @skia.Transform::default())
      pixmap.fill_rect(rect, paint, ts, None)
    }
  }
}

///|
fn decode_raster(format : String, data : Bytes) -> @skia.Pixmap? {
  match format {
    "png" =>
      match @pixels.decode_png(data) {
        Some((w, h, rgba)) => {
          for i in 0..<(w * h) {
            let a = rgba[i * 4 + 3].to_int()
            for k in 0..<3 {
              rgba[i * 4 + k] = @skia.premultiply_u8(rgba[i * 4 + k].to_int(), a).to_byte()
            }
          }
          @skia.Pixmap::from_data(rgba, w, h)
        }
        None => None
      }
    "gif" =>
      match decode_gif(data) {
        Some((w, h, rgba)) => {
          premultiply_f64(rgba)
          @skia.Pixmap::from_data(rgba, w, h)
        }
        None => None
      }
    "jpeg" =>
      match decode_jpeg(data) {
        Some((w, h, rgba)) => @skia.Pixmap::from_data(rgba, w, h)
        None => None
      }
    "webp" =>
      match decode_webp(data) {
        Some((w, h, rgba)) => {
          premultiply_f64(rgba)
          @skia.Pixmap::from_data(rgba, w, h)
        }
        None => None
      }
    _ => None
  }
}

///|
/// resvg's rgba_to_pixmap: (c · a/255 + 0.5) in f64.
fn premultiply_f64(d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    let a = d[i * 4 + 3].to_int().to_double() / 255.0
    for k in 0..<3 {
      let v = d[i * 4 + k].to_int().to_double() * a + 0.5
      d[i * 4 + k] = (if v >= 255.0 { 255 } else { v.to_int() }).to_byte()
    }
  }
}

///|
/// The first frame of a GIF as RGBA (the gif crate with ColorOutput::RGBA): the frame's own size, a transparent
/// index transparent.
fn decode_gif(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  let n = b.length()
  if n < 13 {
    return None
  }
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let le16 = fn(i : Int) -> Int { u8(i) | (u8(i + 1) << 8) }
  let flags = u8(10)
  let mut i = 13
  let mut global : Array[Int] = []
  if (flags & 0x80) != 0 {
    let size = 3 * (1 << ((flags & 7) + 1))
    global = Array::makei(size, fn(k) { u8(13 + k) })
    i += size
  }
  let mut transparent = -1
  while i < n {
    let block = u8(i)
    if block == 0x21 {
      // an extension: a graphic control one says the transparent index
      let label = u8(i + 1)
      i += 2
      if label == 0xF9 && u8(i) >= 4 {
        let packed = u8(i + 1)
        transparent = if (packed & 1) != 0 { u8(i + 4) } else { -1 }
      }
      while i < n && u8(i) != 0 {
        i += u8(i) + 1
      }
      i += 1
    } else if block == 0x2C {
      let w = le16(i + 5)
      let h = le16(i + 7)
      let f = u8(i + 9)
      i += 10
      let mut table = global
      if (f & 0x80) != 0 {
        let size = 3 * (1 << ((f & 7) + 1))
        let start = i
        table = Array::makei(size, fn(k) { u8(start + k) })
        i += size
      }
      let interlaced = (f & 0x40) != 0
      let min_code = u8(i)
      i += 1
      let data : Array[Int] = []
      while i < n && u8(i) != 0 {
        let len = u8(i)
        for k in 1..=len {
          data.push(u8(i + k))
        }
        i += len + 1
      }
      if w == 0 || h == 0 {
        return None
      }
      let indices = gif_lzw(data, min_code, w * h)
      let out = FixedArray::make(w * h * 4, b'\x00')
      let rows : Array[Int] = if interlaced {
        let r = []
        for start_step in [(0, 8), (4, 8), (2, 4), (1, 2)] {
          let mut y = start_step.0
          while y < h {
            r.push(y)
            y += start_step.1
          }
        }
        r
      } else {
        Array::makei(h, fn(y) { y })
      }
      for row in 0..<h {
        let y = rows[row]
        for x in 0..<w {
          let k = row * w + x
          let idx = if k < indices.length() { indices[k] } else { 0 }
          let o = (y * w + x) * 4
          if idx == transparent {
            continue
          }
          if idx * 3 + 2 < table.length() {
            out[o] = table[idx * 3].to_byte()
            out[o + 1] = table[idx * 3 + 1].to_byte()
            out[o + 2] = table[idx * 3 + 2].to_byte()
            out[o + 3] = b'\xFF'
          }
        }
      }
      return Some((w, h, out))
    } else {
      return None
    }
  }
  None
}

///|
fn gif_lzw(data : Array[Int], min_code : Int, limit : Int) -> Array[Int] {
  let out : Array[Int] = []
  if min_code < 1 || min_code > 11 {
    return out
  }
  let clear = 1 << min_code
  let eoi = clear + 1
  let prefix = FixedArray::make(4096, 0)
  let suffix = FixedArray::make(4096, 0)
  for k in 0..<clear {
    suffix[k] = k
  }
  let mut size = min_code + 1
  let mut next = eoi + 1
  let mut prev = -1
  let mut bits = 0
  let mut acc = 0
  let mut p = 0
  let stack = FixedArray::make(4097, 0)
  while out.length() < limit {
    while bits < size && p < data.length() {
      acc = acc | (data[p] << bits)
      bits += 8
      p += 1
    }
    if bits < size {
      break
    }
    let code = acc & ((1 << size) - 1)
    acc = acc >> size
    bits -= size
    if code == clear {
      size = min_code + 1
      next = eoi + 1
      prev = -1
      continue
    }
    if code == eoi {
      break
    }
    if prev < 0 {
      if code >= clear {
        break
      }
      out.push(code)
      prev = code
      continue
    }
    let c = if code < next { code } else if code == next { prev } else { break }
    // the string of c, written backwards, its root last
    let mut sp = 0
    let mut k = c
    while k > eoi {
      stack[sp] = suffix[k]
      sp += 1
      k = prefix[k]
    }
    stack[sp] = k
    sp += 1
    let first = k
    while sp > 0 {
      sp -= 1
      out.push(stack[sp])
    }
    if code == next {
      out.push(first)
    }
    if next < 4096 {
      prefix[next] = prev
      suffix[next] = first
      next += 1
      if next == (1 << size) && size < 12 {
        size += 1
      }
    }
    prev = code
  }
  out
}

///|
fn decode_jpeg(data : Bytes) -> (Int, Int, FixedArray[Byte])? {
  @pixels.decode_jpeg(data)
}

///|
fn decode_webp(data : Bytes) -> (Int, Int, FixedArray[Byte])? {
  @pixels.decode_webp(data)
}
