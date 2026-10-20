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
//   mbui-dl 2
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
//   i N0 … N23                    an instance (scene.mbt: its 24 numbers), in drawing order, but a glyph's 12 its
//                                 glyph's N (13 0) and an image's 20 its image's N

///|
/// What the last frame drew, as a draw list (the file's head).
pub fn Tester::drawlist(self : Tester) -> String {
  ignore(self)
  drawlist_of(g())
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
          None => out.push((id, "", 0))
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
fn drawlist_of(c : Ctx) -> String {
  let sb = StringBuilder()
  sb.write_string("mbui-dl 2\n")
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
  // the glyphs drawn, by what they are: their atlas places (as this Tester's host had them) to their keys
  let key_at : Map[String, Int] = {}
  match text_table.val {
    Some(t) => t.glyphs.each(fn(key, r) { if r.length() >= 2 { key_at["\{r[0]} \{r[1]}"] = key } })
    None => ()
  }
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
            None => " 0 0 0 -1 \"\""
          }
        None => " 0 0 0 -1 \"\""
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
      Some(bytes) => sb.write_string(" \{bytes.length()}")
      None => ()
    }
    sb.write_char('\n')
  }
  for k in 0..<c.ninst {
    sb.write_string("i")
    let o = k * inst_size
    for j in 0..<inst_size {
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
