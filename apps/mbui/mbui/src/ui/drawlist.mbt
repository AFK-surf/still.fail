// A frame as a draw list (.dl): what a renderer needs to draw it, and nothing of how it was built. A Tester over a
// host's kept text (Tester::new(text=)) draws a screen's frame as that host would; its draw list, handed to the host's
// renderer offscreen (src/render, `mbui-render`), is that screen's picture on that host, with no app, no window and no
// clock. So screens are compared as draw lists everywhere, and as pixels only by each renderer, from these.
//
// What is drawn is named by what it is, never by what was drawn before it: a glyph by its words, font and cluster, an
// image by its source and size, so that the same screen reached by other steps is the same list to the byte. Atlas
// places and image ids are each renderer's own.
//
// The format, a line each, numbers as MoonBit writes doubles (exact), in this order:
//   mbui-dl 4|5|6|7|8|9           (9: an instance's 60 numbers, where it fades out towards a cut across 56-59, written
//                                 only where something does; 8: 56, where it fades out towards a cut down 52-55, written
//                                 only where something does; 7: 52, the rounded clip outside its own that its own cuts
//                                 through 40-51, written only where something has one; 6: 40, a box's corners each its
//                                 own 36-39, written only where some box's are not one; 5: 36, how it is turned 32-35,
//                                 written only where something is turned; 4: 32, how smooth its clip's corners are
//                                 28-31; 3 had 28, its clip's corners' radii 24-27, round; 2 had 24)
//   window W H SCALE              the window in points, its device pixels a point
//   clear R G B                   what is under everything (0-1), as this frame was presented
//   glyph N SIZE WEIGHT STYLE CLUSTER "TEXT"
//                                 glyph N (from 0, in the order the instances first draw them): cluster CLUSTER of the
//                                 words TEXT as the host shapes them in that font (-1: TEXT by itself, the host's
//                                 text_key). Where one glyph was made by several, the shortest words name it, then the
//                                 first in UTF-16 order, then the lowest cluster; words keyed by themselves before any.
//                                 Unnamed (no kept text): SIZE WEIGHT STYLE 0 0 0, CLUSTER -1, TEXT "".
//   image N PX "SOURCE" [BYTES]   image N (from 0, in the order the instances first draw them): its source and the long
//                                 side it was asked at; BYTES when the app handed it over as bytes, how many
//                                 (Tester::drawlist_images)
//   bytes N BASE64                those bytes, when the list is to carry them (Tester::drawlist(bytes=true)): a list a
//                                 renderer draws by itself, with no files beside it
//   i N0 … N31                    an instance (scene.mbt: its 32 numbers, 36, 40, 52, 56 or 60), in drawing order, but a glyph's 12 its
//                                 glyph's N (13 0) and an image's 20 its image's N; 16-19 and 24-27 the rounded
//                                 rect it is cut to (its rect, its corners' radii: top left, top right, bottom right,
//                                 bottom left), 28-31 how smooth those corners are (smooth.mbt)

///|
/// What the last frame drew, as a draw list (the file's head); `bytes`: with the pictures handed over as bytes in it.
pub fn Tester::drawlist(self : Tester, bytes? : Bool = false) -> String {
  ignore(self)
  drawlist_of(g(), bytes~)
}

///|
/// The images the last frame drew that the app handed over as bytes (Ctx::image_bytes, add_image), in the list's
/// order: their sources and bytes, for a renderer beside the draw list (its `.img<N>` files).
pub fn Tester::drawlist_images(self : Tester) -> Array[(Int, String, Bytes)] {
  ignore(self)
  let out : Array[(Int, String, Bytes)] = []
  for k, e in drawn_images(g()) {
    match image_data.get(e.1) {
      Some(b) => out.push((k, e.1, b))
      None => ()
    }
  }
  out
}

///|
/// The images drawn in the last frame, in the order the instances first draw them: (id, source, px).
fn drawn_images(c : Ctx) -> Array[(Int, String, Int)] {
  let by_id : Map[Int, (String, Int)] = {}
  image_cache.each(fn(src, es) {
    for e in es {
      by_id[e.id] = (src, e.px)
    }
  })
  let seen : Map[Int, Bool] = {}
  let out : Array[(Int, String, Int)] = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      let id = c.inst[b + 20].to_int()
      if !seen.contains(id) {
        seen[id] = true
        match by_id.get(id) {
          Some((src, px)) => out.push((id, src, px))
          // a stream's picture (stream.mbt): its size and frame's time in place of a source
          None =>
            match stream_of_image(id) {
              Some(s) => {
                let px = match s.size {
                  Some((w, h)) => if w > h { w } else { h }
                  None => 0
                }
                out.push((id, stream_drawn(id), px))
              }
              None => out.push((id, "", 0))
            }
        }
      }
    }
  }
  out
}

///|
fn dl_num(sb : StringBuilder, v : Double) -> Unit {
  sb.write_char(' ')
  // (whole numbers without a fraction: what most are)
  if v == v.floor() && v.abs() < 1.0e15 {
    sb.write_string(v.to_int64().to_string())
  } else {
    sb.write_string(v.to_string())
  }
}

///|
/// A kept text's key ("size|weight|style|text") as its font's numbers and its words.
fn font_and_text(sk : String) -> ((Double, Int, Int), String)? {
  let parts = sk.split("|").to_array()
  if parts.length() < 4 {
    return None
  }
  let n = fn(s : StringView) -> Double {
    match (try Some(@json.parse(s.to_owned())) catch { _ => None }) {
      Some(Number(d, ..)) => d
      _ => 0.0
    }
  }
  let skip = parts[0].length() + parts[1].length() + parts[2].length() + 3
  Some(((n(parts[0]), n(parts[1]).to_int(), n(parts[2]).to_int()), sk.view(start_offset=skip).to_owned()))
}

///|
/// What glyph `key` is, by the kept text: (font, cluster, words), by the rule the format says.
fn glyph_names() -> Map[Int, ((Double, Int, Int), Int, String)] {
  let named : Map[Int, ((Double, Int, Int), Int, String)] = {}
  // shorter words, then words before in UTF-16 order, then a lower cluster; by themselves (-1) before any
  let better = fn(a : ((Double, Int, Int), Int, String), b : ((Double, Int, Int), Int, String)) -> Bool {
    if (a.1 < 0) != (b.1 < 0) {
      a.1 < 0
    } else if a.2.length() != b.2.length() {
      a.2.length() < b.2.length()
    } else if a.2 != b.2 {
      a.2 < b.2
    } else {
      a.1 < b.1
    }
  }
  let put = fn(key : Int, name : ((Double, Int, Int), Int, String)) {
    match named.get(key) {
      Some(was) if !better(name, was) => ()
      _ => named[key] = name
    }
  }
  match text_table.val {
    Some(t) => {
      t.keys.each(fn(sk, key) {
        match font_and_text(sk) {
          Some((font, text)) => put(key, (font, -1, text))
          None => ()
        }
      })
      t.shapes.each(fn(sk, r) {
        match font_and_text(sk) {
          Some((font, text)) => {
            let mut k = 0
            while k * 4 + 3 < r.length() {
              let key = r[k * 4 + 3].to_int()
              if key >= 0 {
                put(key, (font, k, text))
              }
              k = k + 1
            }
          }
          None => ()
        }
      })
    }
    None => ()
  }
  named
}

///|
/// A glyph drawn (instance `k`) whose words are not known: over a host's kept text, a glyph that is not one of its
/// (the list would draw it as another), said; else unnamed (a renderer draws it as nothing).
fn no_glyph_name(k : Int) -> String {
  if text_table.val is Some(_) {
    let s = "Tester::drawlist: instance \{k} draws a glyph the host's kept text does not have"
    println(s)
    abort(s)
  }
  " 0 0 0 -1 \"\""
}

///|
fn drawlist_of(c : Ctx, bytes? : Bool = false) -> String {
  // over a host's kept text, what it lacks was shaped by the fake host: its glyphs' atlas places are not the host's,
  // and named by the host's they would be drawn as other glyphs (a renderer's picture of words never drawn). Said, not
  // drawn
  match text_table.val {
    Some(t) if t.missing.length() > 0 => {
      let s = "Tester::drawlist: the host's kept text lacks \{t.missing.length()} of what was drawn (record its text again): " +
        t.missing[:5].to_array().join(", ")
      println(s)
      abort(s)
    }
    _ => ()
  }
  let sb = StringBuilder()
  // (fading towards a cut across: 9 and its 60 numbers; down: 8 and 56; an outer clip: 7 and 52; a box's corners each its own: 6 and 40;
  // turned: 5 and 36; else 4 and 32, as before anything turned)
  let mut fades = false
  let mut across = false
  let mut turned = false
  let mut each = false
  let mut outer = false
  for k in 0..<c.ninst {
    let o = k * inst_size
    if c.inst[o + 32] != 0.0 {
      turned = true
    }
    let r = c.inst[o + 4]
    if c.inst[o + 36] != r || c.inst[o + 37] != r || c.inst[o + 38] != r || c.inst[o + 39] != r {
      each = true
    }
    if inst_has_outer(c.inst, o) {
      outer = true
    }
    if c.inst[o + 53] > 0.0 || c.inst[o + 55] > 0.0 {
      fades = true
    }
    if c.inst[o + 57] > 0.0 || c.inst[o + 59] > 0.0 {
      across = true
    }
  }
  let numbers = if across {
    inst_size
  } else if fades {
    56
  } else if outer {
    52
  } else if each {
    40
  } else if turned {
    36
  } else {
    32
  }
  sb.write_string(
    if across {
      "mbui-dl 9\n"
    } else if fades {
      "mbui-dl 8\n"
    } else if outer {
      "mbui-dl 7\n"
    } else if each {
      "mbui-dl 6\n"
    } else if turned {
      "mbui-dl 5\n"
    } else {
      "mbui-dl 4\n"
    },
  )
  sb.write_string("window")
  dl_num(sb, c.width)
  dl_num(sb, c.height)
  dl_num(sb, c.scale)
  sb.write_string("\nclear")
  let (r, g, b) = c.clear
  dl_num(sb, r)
  dl_num(sb, g)
  dl_num(sb, b)
  sb.write_char('\n')
  // the glyphs drawn, by what they are: their atlas places to their keys
  let key_at = glyph_keys()
  let names = glyph_names()
  // each glyph drawn, numbered as first drawn, by its name (one name, one number)
  let glyph_no : Map[String, Int] = {}
  let inst_glyph : Map[Int, Int] = {}
  for k in 0..<c.ninst {
    let o = k * inst_size
    let kind = c.inst[o + 5]
    if kind == 1.0 || kind == 3.0 || kind == 7.0 {
      let name = match key_at.get("\{c.inst[o + 12]} \{c.inst[o + 13]}") {
        Some(key) =>
          match names.get(key) {
            Some(((size, weight, style), cluster, text)) => {
              let s = StringBuilder()
              dl_num(s, size)
              s.write_string(" \{weight} \{style} \{cluster} " + Json::string(text).stringify())
              s.to_string()
            }
            None => no_glyph_name(k)
          }
        None => no_glyph_name(k)
      }
      let n = match glyph_no.get(name) {
        Some(n) => n
        None => {
          let n = glyph_no.length()
          glyph_no[name] = n
          sb.write_string("glyph \{n}" + name + "\n")
          n
        }
      }
      inst_glyph[k] = n
    }
  }
  // each image drawn, numbered as first drawn
  let image_no : Map[Int, Int] = {}
  for n, e in drawn_images(c) {
    image_no[e.0] = n
    sb.write_string("image \{n} \{e.2} " + Json::string(e.1).stringify())
    match image_data.get(e.1) {
      Some(data) => {
        sb.write_string(" \{data.length()}")
        if bytes {
          sb.write_string("\nbytes \{n} " + @codec.base64(data))
        }
      }
      None => ()
    }
    sb.write_char('\n')
  }
  for k in 0..<c.ninst {
    sb.write_string("i")
    let o = k * inst_size
    for j in 0..<numbers {
      let v = match (j, inst_glyph.get(k)) {
        (12, Some(n)) => n.to_double()
        (13, Some(_)) => 0.0
        _ =>
          if j == 20 && c.inst[o + 5] == 4.0 {
            image_no.get(c.inst[o + 20].to_int()).unwrap_or(-1).to_double()
          } else {
            c.inst[o + j]
          }
      }
      dl_num(sb, v)
    }
    sb.write_char('\n')
  }
  sb.to_string()
}

///|
/// Whether two draw lists are the same screen, across machines: line by line and word by word (split on blanks), the
/// same words, but on the lines of numbers (window, clear, an instance's i) two numbers may be a share of 1e-9 of the
/// larger apart (of 1 under 1); a glyph's, an image's and bytes' lines word for word: what a
/// machine's last bits make of a sum or a sine (an arc's points on an arm64 Mac and on an x64 Linux), not what is
/// drawn. What a list is compared with a reference kept in a file by (a snapshot another machine wrote); on one
/// machine a list is the same to the byte, and compared as it is.
pub fn drawlist_same(a : String, b : String) -> Bool {
  drawlist_first_unlike(a, b) is None
}

///|
/// The first line (from 1) where `a` and `b` are not the same (`drawlist_same`), with both of its texts ("" past the
/// end of a list); None when they are.
pub fn drawlist_first_unlike(a : String, b : String) -> (Int, String, String)? {
  let la = a.split("\n").to_array()
  let lb = b.split("\n").to_array()
  let n = if la.length() > lb.length() { la.length() } else { lb.length() }
  for i in 0..<n {
    let x = la.get(i).map(fn(v) { v.to_string() }).unwrap_or("")
    let y = lb.get(i).map(fn(v) { v.to_string() }).unwrap_or("")
    if i >= la.length() || i >= lb.length() || !dl_line_same(x, y) {
      return Some((i + 1, x, y))
    }
  }
  None
}

///|
fn dl_line_same(x : String, y : String) -> Bool {
  if x == y {
    return true
  }
  let wx = x.split(" ").filter(fn(w) { w != "" }).to_array()
  let wy = y.split(" ").filter(fn(w) { w != "" }).to_array()
  if wx.length() != wy.length() {
    return false
  }
  // (only the lines of numbers: a glyph's or an image's words, and bytes' base64, word for word)
  match wx.get(0).map(fn(w) { w.to_string() }) {
    Some("window") | Some("clear") | Some("i") => ()
    _ => return false
  }
  for k in 0..<wx.length() {
    let p = wx[k].to_string()
    let q = wy[k].to_string()
    if p == q {
      continue
    }
    match (dl_number(p), dl_number(q)) {
      (Some(u), Some(v)) => {
        let most = dmax(1.0, dmax(u.abs(), v.abs()))
        if (u - v).abs() > 1.0e-9 * most {
          return false
        }
      }
      _ => return false
    }
  }
  true
}

///|
/// A word of a draw list as the number it is (as dl_num writes them), None when it is not one.
fn dl_number(w : String) -> Double? {
  if w == "" {
    return None
  }
  for ch in w {
    if !((ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.' || ch == 'e' || ch == 'E') {
      return None
    }
  }
  match (try Some(@json.parse(w)) catch { _ => None }) {
    Some(Number(d, ..)) => Some(d)
    _ => None
  }
}
