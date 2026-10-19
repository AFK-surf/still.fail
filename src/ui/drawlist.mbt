// A frame as a draw list (.dl): what a renderer needs to draw it, and nothing of how it was built. A Tester over a
// host's kept text (Tester::new(text=)) draws a screen's frame as that host would; its draw list, handed to the host's
// renderer offscreen (src/render, `mbui-render`), is that screen's picture on that host, with no app, no window and no
// clock. So screens are compared as draw lists everywhere, and as pixels only by each renderer, from these.
//
// The format, a line each, numbers as MoonBit writes doubles (exact):
//   mbui-dl 1
//   window W H SCALE              the window in points, its device pixels a point
//   clear R G B                   what is under everything (0-1)
//   glyph U V KEY SIZE WEIGHT STYLE CLUSTER "TEXT"
//                                 a glyph drawn here: where the host's atlas had it (U V, as the instances say), and
//                                 what it is, for a renderer to make it again: cluster CLUSTER of the words TEXT as the
//                                 host shapes them in that font (-1: TEXT by itself, the host's text_key)
//   image ID PX "SOURCE" [BYTES]  an image drawn here: the id the instances say, the long side it was asked at, its
//                                 source, and when the app handed it over as bytes, how many (Tester::drawlist_images)
//   i N0 … N23                    an instance (scene.mbt: its 24 numbers), in drawing order
// A renderer makes each glyph and image again by what it is, and puts its own atlas place and image id in their
// instances (12-13, 20); everything else it draws as it is.

///|
/// What the last frame drew, as a draw list (the file's head). Glyphs are named by what the kept text
/// (Tester::new(text=)) says they are; without it, by nothing (`""`): such a list is for comparing, not rendering.
pub fn Tester::drawlist(self : Tester) -> String {
  ignore(self)
  drawlist_of(g())
}

///|
/// The images the last frame drew that the app handed over as bytes (Ctx::image_bytes, add_image): their sources and
/// bytes, for a renderer beside the draw list.
pub fn Tester::drawlist_images(self : Tester) -> Array[(String, Bytes)] {
  ignore(self)
  let c = g()
  let out : Array[(String, Bytes)] = []
  for e in drawn_images(c) {
    match image_data.get(e.1) {
      Some(b) => out.push((e.1, b))
      None => ()
    }
  }
  out
}

///|
/// The images drawn in the last frame: (id, source, px), by id.
fn drawn_images(c : Ctx) -> Array[(Int, String, Int)] {
  let ids : Map[Int, Bool] = {}
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 4.0 {
      ids[c.inst[b + 20].to_int()] = true
    }
  }
  let out : Array[(Int, String, Int)] = []
  image_cache.each(fn(src, es) {
    for e in es {
      if ids.contains(e.id) {
        out.push((e.id, src, e.px))
      }
    }
  })
  out.sort_by_key(x => x.0)
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
/// A kept text's key ("size|weight|style|text") as its font ("size weight style") and its words.
fn font_and_text(sk : String) -> (String, String)? {
  let parts = sk.split("|").to_array()
  if parts.length() < 4 {
    return None
  }
  let skip = parts[0].length() + parts[1].length() + parts[2].length() + 3
  Some(("\{parts[0]} \{parts[1]} \{parts[2]}", sk.view(start_offset=skip).to_owned()))
}

///|
fn drawlist_of(c : Ctx) -> String {
  let sb = StringBuilder()
  sb.write_string("mbui-dl 1\n")
  sb.write_string("window")
  dl_num(sb, c.width)
  dl_num(sb, c.height)
  dl_num(sb, c.scale)
  sb.write_string("\nclear")
  // (what h_present gives the host)
  dl_num(sb, 0.961)
  dl_num(sb, 0.961)
  dl_num(sb, 0.969)
  sb.write_char('\n')
  // the glyphs drawn, by where the atlas has them, named by the kept text
  let by_place : Map[String, Int] = {}
  let named : Map[Int, (String, Int, String)] = {}
  match text_table.val {
    Some(t) => {
      t.glyphs.each(fn(key, r) { if r.length() >= 2 { by_place["\{r[0]} \{r[1]}"] = key } })
      // what the host said each key is: a cluster of words it shaped, or words it keyed by themselves
      t.keys.each(fn(sk, key) {
        match font_and_text(sk) {
          Some((font, text)) => named[key] = (font, -1, text)
          None => ()
        }
      })
      t.shapes.each(fn(sk, r) {
        match font_and_text(sk) {
          Some((font, text)) => {
            let mut k = 0
            while k * 4 + 3 < r.length() {
              let key = r[k * 4 + 3].to_int()
              if !named.contains(key) {
                named[key] = (font, k, text)
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
  let said : Map[String, Bool] = {}
  for k in 0..<c.ninst {
    let b = k * inst_size
    let kind = c.inst[b + 5]
    if kind == 1.0 || kind == 3.0 || kind == 7.0 {
      let u = c.inst[b + 12]
      let v = c.inst[b + 13]
      let place = "\{u} \{v}"
      if !said.contains(place) {
        said[place] = true
        sb.write_string("glyph")
        dl_num(sb, u)
        dl_num(sb, v)
        match by_place.get(place) {
          Some(key) => {
            sb.write_string(" \{key}")
            match named.get(key) {
              Some((font, cluster, text)) => sb.write_string(" \{font} \{cluster} " + Json::string(text).stringify())
              None => sb.write_string(" 0 0 0 -1 \"\"")
            }
          }
          None => sb.write_string(" -1 0 0 0 -1 \"\"")
        }
        sb.write_char('\n')
      }
    }
  }
  for e in drawn_images(c) {
    sb.write_string("image \{e.0} \{e.2} " + Json::string(e.1).stringify())
    match image_data.get(e.1) {
      Some(bytes) => sb.write_string(" \{bytes.length()}")
      None => ()
    }
    sb.write_char('\n')
  }
  for k in 0..<c.ninst {
    sb.write_string("i")
    for j in 0..<inst_size {
      dl_num(sb, c.inst[k * inst_size + j])
    }
    sb.write_char('\n')
  }
  sb.to_string()
}
