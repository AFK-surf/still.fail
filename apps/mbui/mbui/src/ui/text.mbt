// Text: the host shapes a string into grapheme clusters (with the system's
// own engine: Core Text on Apple platforms, canvas 2D in browsers) and
// rasterizes each cluster into its atlas on demand. Line breaking (UAX #14,
// from mbui/text), caret geometry and hit testing are done here, the same on
// every platform.
//
// What the host draws as one piece: a cluster, or a ligature the shaper made of
// several (the host gives it to the first, with the advance shared out). A word
// in a script whose letters take their shapes from their neighbours (Arabic,
// the Indic scripts…) is made one cluster here (@hostapi.text_key), so the host
// rasterizes it whole, joined as it is when the system draws it; a caret in it
// goes before or after the whole word. Right-to-left text is put in its visual
// order line by line (UAX #9, @text.Bidi): each line's clusters reordered, the
// caret and hit testing following them.

///|
struct Shaped {
  starts : Array[Int]
  lens : Array[Int]
  adv : Array[Double]
  keys : Array[Int]
  cu : Array[Int]
  // before each cluster: 0 no line break, 1 a break opportunity, 2 a hard
  // line break (UAX #14)
  brk : Array[Int]
  len : Int
  // the text's bidirectional levels, when any is not 0 (None: all left to right)
  bidi : @text.Bidi?
  // with letter spacing: how far each cluster's piece is drawn in from where it starts (half the spacing, the
  // other half after it; every advance has the whole of it)
  pad : Double
  // the last layout made of it (with no indent), for the next one asked
  // for with the same line height and wrapping, in a width it fits
  mut lay : TextLayout?
  mut lay_max : Double
  mut lay_line : Double
  mut lay_trim : Bool
  mut lay_wrap : Bool
  // the last frame it was asked for in (shapes_thin)
  mut used : Int
}

///|
pub struct TextLayout {
  text : String
  shaped : Shaped
  line_start : Array[Int]
  line_end : Array[Int]
  line_w : Array[Double]
  xs : Array[Double]
  line_of : Array[Int]
  w : Double
  h : Double
  ascent : Double
  line_h : Double
  // each cluster's bidi level on its line (empty: all left to right)
  lv : Array[Int]
}

///|
struct Glyph {
  u : Double
  v : Double
  gw : Double
  gh : Double
  ox : Double
  oy : Double
  color : Bool
  // its plot in the atlas (@hostapi.Atlas; -1: nothing to draw), and whether that is colour glyphs' own
  plot : Int
  in_colour : Bool
}

///|
/// The strings shaped in one font (size, weight, style) with one letter spacing.
struct FontShapes {
  size : Double
  weight : Int
  style : Int
  spacing : Double
  map : Map[String, Shaped]
}

///|
struct TextCache {
  fonts : Array[FontShapes]
  // strings shaped, in all fonts
  mut shaped : Int
  // ascent, descent, line height; the ascent and descent of the font Han falls back to; whether the host sets lines
  // on whole pixels
  metrics : Map[Int64, (Double, Double, Double, Double, Double, Bool)]
  glyphs : Map[Int, Glyph]
  // where they are in the host's atlas, and in colour glyphs' own (made as the first is asked for, at the size the
  // host's has; colour glyphs' none where the host keeps them with the others)
  mut atlas : @hostapi.Atlas?
  mut colour_atlas : @hostapi.Atlas?
  // the glyphs of what was shaped in this frame that it has not drawn yet, for the host to draw ahead (glyphs_ahead)
  fresh : Array[Int]
  mut generation : Int
  // the frame being drawn, and the last that let go of what was shaped longest ago (shapes_thin)
  mut frame : Int
  mut thinned : Int
  buf : FixedArray[Double]
  gbuf : FixedArray[Double]
}

///|
let text_cache : TextCache = {
  fonts: [],
  shaped: 0,
  metrics: Map::new(),
  glyphs: Map::new(),
  atlas: None,
  colour_atlas: None,
  fresh: [],
  generation: -1,
  frame: 0,
  thinned: -1,
  buf: FixedArray::make(4 * 8192, 0.0),
  gbuf: FixedArray::make(8, 0.0),
}

///|
/// A frame begins: what it shapes and draws from the atlas is kept through it. What the host drew and measured
/// before, forgotten where it is gone (@hostapi.atlas_generation).
fn text_frame() -> Unit {
  text_cache.frame = text_cache.frame + 1
  for a in [text_cache.atlas, text_cache.colour_atlas] {
    match a {
      Some(a) => a.next_frame()
      None => ()
    }
  }
  let g = h_atlas_generation()
  if g != text_cache.generation {
    // (a host moves it on as its faces or its scale change, a face it was given is here (a page's, loaded later than
    // asked), its atlas is lost: what was measured in the face before is forgotten with the glyphs)
    let first = text_cache.generation < 0
    text_cache.generation = g
    glyphs_forget()
    // (and the frame drawn whole: its glyphs drawn again where they were, the same numbers, other pixels: hostcall.mbt
    // `presented`, docs/partial-redraw.md)
    presented.forget()
    if !first {
      clear_shapes()
      text_cache.fonts.clear()
      text_cache.metrics.clear()
    }
  }
}

///|
/// Every glyph forgotten, and where it was in the atlas: drawn again as it is next asked for.
fn glyphs_forget() -> Unit {
  text_cache.glyphs.clear()
  text_cache.fresh.clear()
  text_cache.atlas = None
  text_cache.colour_atlas = None
}

///|
/// How many times as large as the host makes its glyphs (the window's pixels a point) what is painted now draws its
/// words: a shot's pixels a point over the window's (shot.mbt), 1 elsewhere.
// kept across runs: set only while a shot is painted, within one frame's paint, and put back
let words_zoom : Ref[Double] = Ref::new(1.0)

///|
/// The glyphs of words `text`, shaped as `s` is in `size`, `weight`, `style` and `spacing`, shaped again words_zoom
/// times as large, cluster for cluster: a shot drawn at more pixels a point than the window's draws its words by them,
/// each made by the host as crisp as that. None at 1, or where they do not come to as many clusters.
fn zoomed_keys(text : String, s : Shaped, size : Double, weight : Int, style : Int, spacing : Double) -> Array[Int]? {
  let k = words_zoom.val
  if k == 1.0 {
    return None
  }
  let big = shape(text, size * k, weight, style~, spacing=spacing * k)
  if big.keys.length() == s.keys.length() {
    Some(big.keys)
  } else {
    None
  }
}

///|
/// Ascent, descent and line height of the system font at this size (its
/// code face, slanted, its serif face: `style`, @hostapi.style_mono, style_italic, style_serif).
fn font_metrics(
  size : Double,
  weight : Int,
  style? : Int = 0,
) -> (Double, Double, Double) {
  let (a, d, l, _, _, _) = all_metrics(size, weight, style)
  (a, d, l)
}

///|
/// Ascent and descent of the font a Han ideograph falls back to at this size (Noto Sans CJK, PingFang, Microsoft
/// YaHei): taller than most Latin faces. A host that does not say (a kept text from before) answers the font's own.
fn han_metrics(size : Double, weight : Int, style? : Int = 0) -> (Double, Double) {
  let (_, _, _, a, d, _) = all_metrics(size, weight, style)
  (a, d)
}

///|
/// Lines set as a browser sets them (Blink's LayoutNG), not as Android does: by the first font's ascent and descent
/// alone, each on a whole point, what is left of the line halved and rounded down above them (FontHeight::AddLeading);
/// what falls back to another font (Chinese) on the same baseline. A frame set as a web page is (a desktop's window,
/// as the desktop app's pages) says so (set_web_lines).
let web_lines : Ref[Bool] = Ref(false)

///|
/// Whether lines are set as a browser sets them from now on (web_lines); the layouts made the other way let go.
pub fn set_web_lines(on : Bool) -> Unit {
  if web_lines.val != on {
    web_lines.val = on
    for f in text_cache.fonts {
      for _, s in f.map {
        s.lay = None
      }
    }
  }
}

///|
/// A line's ascent and descent as it is set (`cjk`: Chinese in it): the first font's, the taller of it and the font Han
/// falls back to with Chinese in it, as Android measures a line by the fonts it draws in; as a browser sets it
/// (web_lines), the first font's alone, each on a whole point.
fn line_metrics(size : Double, weight : Int, cjk : Bool, style? : Int = 0) -> (Double, Double) {
  let (a, d, _) = font_metrics(size, weight, style~)
  if web_lines.val {
    (a.round(), d.round())
  } else if cjk {
    let (ha, hd) = han_metrics(size, weight, style~)
    (dmax(a, ha), dmax(d, hd))
  } else {
    (a, d)
  }
}

///|
/// Whether lines are set as a browser sets them now (set_web_lines).
pub fn web_lines_on() -> Bool {
  web_lines.val
}

///|
/// Where the baseline of one line of words in `size` and `weight` (no Chinese in it) falls from the top of a line
/// `line` high, as set_line sets it: by the ascent and descent of the face the words are in, or, given `em`, of a face
/// reaching those shares of its size above and below its baseline (one the words are not in, to compare with).
pub fn line_baseline(
  line : Double,
  size? : Double = 15.0,
  weight? : Int = 400,
  em? : (Double, Double),
) -> Double {
  let (asc, desc) = match em {
    Some((a, d)) if web_lines.val => ((a * size).round(), (d * size).round())
    Some((a, d)) => (a * size, d * size)
    None => line_metrics(size, weight, false)
  }
  set_line(line, asc, desc, g().scale, whole_pixel_lines(size, weight)).1
}

///|
/// Whether the host sets a line of words on whole device pixels, as Android's StaticLayout does (its font metrics
/// whole pixels too): the sixth number it answers of font_metrics, 1. A host that does not say does not.
fn whole_pixel_lines(size : Double, weight : Int, style? : Int = 0) -> Bool {
  all_metrics(size, weight, style).5
}

///|
fn all_metrics(size : Double, weight : Int, style : Int) -> (Double, Double, Double, Double, Double, Bool) {
  // (the font's figures change no line of it: its metrics are the same either way)
  let style = style & @hostapi.style_tabular.lnot()
  // (the size in tenths, the weight, the style's bits: faces and all, each in a field of its own)
  let key = (((size * 10.0).to_int() * 1000 + weight).to_int64() << 12) | (style & 4095).to_int64()
  match text_cache.metrics.get(key) {
    Some(m) => m
    None => {
      let o = FixedArray::make(6, -1.0)
      h_font_metrics(size, weight, style, o)
      // (-1: not said)
      let m = (
        o[0],
        o[1],
        o[2],
        if o[3] < 0.0 { o[0] } else { o[3] },
        if o[4] < 0.0 { o[1] } else { o[4] },
        o[5] == 1.0,
      )
      text_cache.metrics[key] = m
      m
    }
  }
}

///|
/// Whether the code unit starts a character set in a CJK font: Han, kana, Hangul, bopomofo, CJK and full-width
/// punctuation (a surrogate: the supplementary ideographs).
fn is_cjk(c : Int) -> Bool {
  (c >= 0x2E80 && c <= 0x9FFF) ||
  (c >= 0xAC00 && c <= 0xD7AF) ||
  (c >= 0xD840 && c <= 0xD87F) ||
  (c >= 0xF900 && c <= 0xFAFF) ||
  (c >= 0xFE30 && c <= 0xFE4F) ||
  (c >= 0xFF00 && c <= 0xFFEF)
}

///|
/// Whether any of the words is in a CJK font's characters (is_cjk).
fn words_cjk(text : String) -> Bool {
  for i in 0..<text.length() {
    if is_cjk(text.unsafe_charcode_at(i)) {
      return true
    }
  }
  false
}

///|
/// How a line of words is set in a line `line` high, its font reaching `asc` above the baseline and `desc` below, as
/// Android sets it (Compose's line height: LineHeightStyle Center, Trim.None, Mode.Tight): the room over the font
/// shared out above and below; a font taller than its line not cut (the first line keeps the font's top, the last its
/// bottom). On a host that sets lines on whole pixels (`px`: Android's, whole_pixel_lines) the line is rounded up to
/// one and the room shared in them, below the bigger half; elsewhere the line is as asked and the room halved. A font
/// taller than its line there is padded as Compose pads a theme's words (Material's Text: LineHeightStyle Center,
/// Trim.None, Mode.Fixed) unless `trim` (words in a TextStyle of their own, with no LineHeightStyle, or Trim.Both:
/// SendText.kt's): the first line over by what its ascent lost, the last under by as much or what its descent lost,
/// whichever more (TextLayout getLineHeightPaddings), where `trim` keeps the font's own reach and no more.
/// (pitch: from a line to the next; the first line's baseline from the top; how much more than the lines' pitch
/// the words are high.)
fn set_line(
  line : Double,
  asc : Double,
  desc : Double,
  sc : Double,
  px : Bool,
  trim? : Bool = false,
) -> (Double, Double, Double) {
  // as a browser: the room halved, rounded down above; a font taller than its line overflows it, the line as asked
  if web_lines.val {
    return (line, asc + ((line - asc - desc) / 2.0).floor(), 0.0)
  }
  let sc = if sc > 0.0 { sc } else { 1.0 }
  let pitch = if px { (line * sc - 1.0e-6).ceil() / sc } else { line }
  let room = pitch - asc - desc
  if room >= 0.0 {
    let below = if px { (room * sc / 2.0 - 1.0e-6).ceil() / sc } else { room / 2.0 }
    (pitch, pitch - desc - below, 0.0)
  } else if px && !trim {
    // (a 32 px bold Chinese line in 118 pixels: 97 + 25 high, its font's 97 + 24; Compose on an emulator, 2026-10-22)
    let missing = (-room * sc).round()
    let lost = (missing / 2.0).floor()
    let over = missing - lost
    let under = if lost > 0.0 { dmax(over, lost) } else { 0.0 }
    (pitch, asc, (over + under) / sc)
  } else {
    (pitch, asc, -room)
  }
}

///|
/// The shapes of one font: looked up by the string alone, no key to build.
fn font_shapes(size : Double, weight : Int, style : Int, spacing : Double) -> Map[String, Shaped] {
  for f in text_cache.fonts {
    if f.size == size && f.weight == weight && f.style == style && f.spacing == spacing {
      return f.map
    }
  }
  let map = Map::new()
  text_cache.fonts.push({ size, weight, style, spacing, map })
  map
}

///|
/// The most strings kept shaped: past it, what was asked for longest ago is let go (shapes_thin).
let shapes_most : Int = 6000

///|
/// The half of what is shaped that was asked for longest ago let go, never what this frame asked for: shaped again if
/// it is asked for again. (Every shape let go at once, a frame shaped again everything on the screen.)
fn shapes_thin() -> Unit {
  if text_cache.thinned == text_cache.frame {
    return
  }
  text_cache.thinned = text_cache.frame
  let used = []
  for f in text_cache.fonts {
    for _, s in f.map {
      used.push(s.used)
    }
  }
  if used.is_empty() {
    return
  }
  used.sort()
  let cut = used[used.length() / 2]
  let mut kept = 0
  for f in text_cache.fonts {
    let gone = []
    for t, s in f.map {
      if s.used < cut || (s.used == cut && cut < text_cache.frame) {
        gone.push(t)
        // (a shape and its last layout refer to each other: clear_shapes)
        s.lay = None
      } else {
        kept = kept + 1
      }
    }
    for t in gone {
      f.map.remove(t)
    }
  }
  text_cache.shaped = kept
}

///|
fn clear_shapes() -> Unit {
  for f in text_cache.fonts {
    // a shape and its last layout refer to each other (reference counts
    // never free a cycle): let go of the layout first
    for _, s in f.map {
      s.lay = None
    }
    f.map.clear()
  }
  text_cache.shaped = 0
}

///|
/// Whether `text` has a digit in it: words with none are shaped the same with their digits all one width
/// (@hostapi.style_tabular) as without, in the same font, their glyphs the same (shape asks it of the host only where
/// it changes something, the glyphs of the rest kept once).
fn has_digit(text : String) -> Bool {
  for i in 0..<text.length() {
    let c = text.at(i).to_int()
    if c >= 48 && c <= 57 {
      return true
    }
  }
  false
}

///|
/// With `spacing` (letter spacing, as Android's: each cluster's advance has it, half before its piece and half
/// after), shaped with no ligatures (@hostapi.style_no_ligatures): a ligature's letters would not be spaced.
fn shape(text : String, size : Double, weight : Int, style? : Int = 0, spacing? : Double = 0.0) -> Shaped {
  let style = if spacing != 0.0 { style | @hostapi.style_no_ligatures } else { style }
  // (digits all one width only where they would not be: the code face's are, and words with none have none)
  let style = if (style & @hostapi.style_tabular) != 0 &&
    ((style & @hostapi.style_mono) != 0 || !has_digit(text)) {
    style & @hostapi.style_tabular.lnot()
  } else {
    style
  }
  let shapes = font_shapes(size, weight, style, spacing)
  match shapes.get(text) {
    Some(s) => {
      s.used = text_cache.frame
      s
    }
    None => {
      if text_cache.shaped > shapes_most {
        shapes_thin()
      }
      let out = text_cache.buf
      let m = if text.length() == 0 {
        0
      } else {
        h_shape(text, size, weight, style, out)
      }
      let lb = if m > 1 { Some(@text.line_breaks(text)) } else { None }
      // UAX #29's clusters: a host that cut one in two (a Thai vowel sign some segmenters leave on its own) is
      // made whole again
      // (ASCII, the most of what is shaped: every host's clusters are UAX #29's, nothing joins, nothing reads right
      // to left)
      let mut ascii = true
      for k in 0..<text.length() {
        if text.at(k).to_int() >= 0x80 {
          ascii = false
          break
        }
      }
      let gb = if m > 1 && !ascii { Some(@text.graphemes(text)) } else { None }
      let boundary = FixedArray::make(text.length() + 1, m <= 1 || ascii)
      match gb {
        Some(g) =>
          for b in g {
            boundary[b] = true
          }
        None => ()
      }
      let starts = Array::new(capacity=m)
      let lens = Array::new(capacity=m)
      let adv = Array::new(capacity=m)
      let keys = Array::new(capacity=m)
      let cu = Array::new(capacity=m)
      let mut i = 0
      while i < m {
        let st = out[i * 4].to_int()
        // what joins it: the rest of its grapheme cluster, and the rest of a word in a joining script (which ends
        // where a line may break)
        let word = !ascii && joining(text, st) && out[i * 4 + 3] != -1.0
        let mut j = i + 1
        while j < m {
          let sj = out[j * 4].to_int()
          if !boundary[sj] {
            j = j + 1
            continue
          }
          let opp = match lb {
            Some(b) => b[sj]
            None => 0
          }
          if !word || opp != 0 || out[j * 4 + 3] == -1.0 || !joining(text, sj) {
            break
          }
          j = j + 1
        }
        let k0 = out[i * 4 + 3].to_int()
        if j - i >= 2 {
          let end = out[(j - 1) * 4].to_int() + out[(j - 1) * 4 + 1].to_int()
          let mut a = 0.0
          let mut drawn = false
          for k in i..<j {
            a = a + out[k * 4 + 2]
            drawn = drawn || out[k * 4 + 3] != -1.0
          }
          starts.push(st)
          lens.push(end - st)
          adv.push(a)
          keys.push(
            if k0 == -2 {
              -2
            } else if drawn && !is_nl(text.at(st).to_int()) {
              h_text_key(text.unsafe_substring(start=st, end~), size, weight, style)
            } else {
              k0
            },
          )
        } else {
          starts.push(st)
          lens.push(out[i * 4 + 1].to_int())
          adv.push(out[i * 4 + 2])
          keys.push(k0)
        }
        cu.push(if st < text.length() { text.at(st).to_int() } else { 0 })
        i = j
      }
      // ligatures: a cluster the shaper drew as part of the one before it (-2 from the host) has that one's piece
      // drawn over it; the piece, the whole ligature, is the first's, the advance shared out evenly
      let mut c = 0
      while c < keys.length() {
        if keys[c] != -2 {
          c = c + 1
          continue
        }
        let u = c - 1
        let mut e = c
        while e < keys.length() && keys[e] == -2 {
          e = e + 1
        }
        if u < 0 || keys[u] < 0 {
          for k in c..<e {
            keys[k] = h_text_key(text.unsafe_substring(start=starts[k], end=starts[k] + lens[k]), size, weight, style)
          }
        } else {
          let end = starts[e - 1] + lens[e - 1]
          keys[u] = h_text_key(text.unsafe_substring(start=starts[u], end~), size, weight, style)
          let mut a = 0.0
          for k in u..<e {
            a = a + adv[k]
          }
          for k in u..<e {
            adv[k] = a / (e - u).to_double()
            if k > u {
              keys[k] = -1
            }
          }
        }
        c = e
      }
      let n = starts.length()
      if spacing != 0.0 {
        for k in 0..<n {
          if !is_nl(cu[k]) {
            adv[k] = adv[k] + spacing
          }
        }
      }
      let brk = Array::make(n, 0)
      if n > 1 {
        match lb {
          Some(b) =>
            for k in 1..<n {
              brk[k] = b[starts[k]]
            }
          None => ()
        }
      }
      let bd = if ascii { None } else { Some(@text.Bidi::new(text)) }
      let bd = match bd {
        Some(b) if b.is_mixed() => Some(b)
        _ => None
      }
      // L4: a bracket (or another mirrored character) reading right to left is drawn as its mirror image, ")" for
      // "(" (each cluster is drawn on its own, out of the line the shaper would have mirrored it in)
      match bd {
        Some(bd) => {
          for k in 0..<n {
            if lens[k] == 1 && bd.levels[starts[k]] % 2 == 1 && keys[k] >= 0 {
              let c = text.at(starts[k]).to_int()
              let m = @text.mirror(c)
              if m != c {
                keys[k] = h_text_key(Int::unsafe_to_char(m).to_string(), size, weight, style)
              }
            }
          }
        }
        None => ()
      }
      let s = {
        starts,
        lens,
        adv,
        keys,
        cu,
        brk,
        len: text.length(),
        bidi: bd,
        pad: spacing / 2.0,
        lay: None,
        lay_max: 0.0,
        lay_line: 0.0,
        lay_trim: false,
        lay_wrap: false,
        used: text_cache.frame,
      }
      shapes[text] = s
      text_cache.shaped = text_cache.shaped + 1
      // its glyphs not drawn yet: drawn ahead unless this frame draws them (glyphs_ahead)
      for k in keys {
        if k >= 0 && text_cache.fresh.length() < glyphs_ahead_most && !text_cache.glyphs.contains(k) {
          text_cache.fresh.push(k)
        }
      }
      s
    }
  }
}

///|
/// The code point at UTF-16 offset i.
fn cp_at(text : String, i : Int) -> Int {
  let c = text.at(i).to_int()
  if c >= 0xD800 && c < 0xDC00 && i + 1 < text.length() {
    let d = text.at(i + 1).to_int()
    if d >= 0xDC00 && d < 0xE000 {
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  c
}

///|
/// Whether the cluster at offset i is of a script whose letters take their shapes from the letters beside them
/// (cursive joining: Arabic, Syriac, N'Ko, Mongolian…; conjuncts and reordered vowel signs: the Indic scripts,
/// Myanmar, Khmer, Tibetan) or joins them (ZWJ, ZWNJ): a word of them is drawn whole. Arabic's digits and number
/// signs are not (they read left to right in a right-to-left line).
fn joining(text : String, i : Int) -> Bool {
  if i >= text.length() {
    return false
  }
  let c = cp_at(text, i)
  if c < 0x600 {
    return false
  }
  if c <= 0x8FF {
    // Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic and the Arabic supplements, less their numbers
    !((c >= 0x600 && c <= 0x605) ||
    (c >= 0x660 && c <= 0x66C) ||
    (c >= 0x6F0 && c <= 0x6F9) ||
    c == 0x6DD ||
    (c >= 0x7C0 && c <= 0x7C9) ||
    c == 0x890 ||
    c == 0x891 ||
    c == 0x8E2)
  } else {
    (c >= 0x900 && c <= 0xDFF) ||
    (c >= 0xF00 && c <= 0x109F) ||
    (c >= 0x1780 && c <= 0x18AF) ||
    c == 0x200C ||
    c == 0x200D ||
    (c >= 0xA8E0 && c <= 0xA8FF) ||
    (c >= 0xA9E0 && c <= 0xA9FF) ||
    (c >= 0xAA60 && c <= 0xAA7F) ||
    (c >= 0xFB50 && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFE) ||
    (c >= 0x10D00 && c <= 0x10D3F) ||
    (c >= 0x11000 && c <= 0x111FF)
  }
}

///|
/// A line's clusters [a, e) (without the spaces it ends in) put in their visual order from x: their xs, and their
/// levels (UAX #9 with L1) into lv.
fn bidi_line(
  b : @text.Bidi,
  starts : Array[Int],
  lens : Array[Int],
  adv : Array[Double],
  xs : Array[Double],
  lv : Array[Int],
  a : Int,
  e : Int,
  x0 : Double,
) -> Unit {
  if e <= a {
    return
  }
  let base = starts[a]
  let ll = b.line_levels(base, starts[e - 1] + lens[e - 1])
  let levels = Array::makei(e - a, fn(k) { ll[starts[a + k] - base] })
  for k, l in levels {
    lv[a + k] = l
  }
  let order = @text.visual_order(levels[:])
  let mut x = x0
  for k in order {
    xs[a + k] = x
    x = x + adv[a + k]
  }
}

///|
/// The x of a caret before cluster c (its left edge, or right edge read right to left).
fn caret_before(xs : Array[Double], adv : Array[Double], lv : Array[Int], c : Int) -> Double {
  if c < lv.length() && lv[c] % 2 == 1 {
    xs[c] + adv[c]
  } else {
    xs[c]
  }
}

///|
/// The x of a caret after cluster c.
fn caret_after(xs : Array[Double], adv : Array[Double], lv : Array[Int], c : Int) -> Double {
  if c < lv.length() && lv[c] % 2 == 1 {
    xs[c]
  } else {
    xs[c] + adv[c]
  }
}

///|
/// The offset nearest x on a line of clusters [a, b) in visual order (some right to left).
fn bidi_offset_at(
  starts : Array[Int],
  lens : Array[Int],
  adv : Array[Double],
  xs : Array[Double],
  lv : Array[Int],
  cu : Array[Int],
  a : Int,
  b : Int,
  x : Double,
) -> Int {
  let mut left = -1
  let mut right = -1
  for c in a..<b {
    if is_nl(cu[c]) {
      continue
    }
    let rtl = lv[c] % 2 == 1
    if x >= xs[c] && x < xs[c] + adv[c] {
      let first_half = x < xs[c] + adv[c] / 2.0
      return if first_half != rtl { starts[c] } else { starts[c] + lens[c] }
    }
    if left < 0 || xs[c] < xs[left] {
      left = c
    }
    if right < 0 || xs[c] > xs[right] {
      right = c
    }
  }
  if left < 0 {
    return if a < starts.length() { starts[a] } else { 0 }
  }
  if x < xs[left] {
    if lv[left] % 2 == 1 {
      starts[left] + lens[left]
    } else {
      starts[left]
    }
  } else if lv[right] % 2 == 1 {
    starts[right]
  } else {
    starts[right] + lens[right]
  }
}

///|
/// The most glyphs a frame asks its host to draw ahead.
let glyphs_ahead_most : Int = 4096

///|
/// The glyphs of what the frame shaped and did not draw (a page pushed, still off the screen; the lines below what a
/// list shows), handed to the host as the frame's painting is over, to draw them ahead, off the frames' thread: there
/// when they come into view, a frame or more later, not all drawn in the frame they first show in. What is drawn is the
/// same; only when the work is done changes (@hostapi.glyphs_ahead).
fn glyphs_ahead() -> Unit {
  let fresh = text_cache.fresh
  if fresh.is_empty() {
    return
  }
  let keys = FixedArray::make(fresh.length(), 0)
  let mut n = 0
  for k in fresh {
    if !text_cache.glyphs.contains(k) {
      keys[n] = k
      n = n + 1
    }
  }
  fresh.clear()
  if n > 0 {
    h_glyphs_ahead(keys, n)
  }
}

///|
/// A glyph with nothing to draw (nothing in it, too large for the atlas, or no room in it for now).
// kept across runs: a value (no field of it changes)
let no_glyph : Glyph = {
  u: 0.0,
  v: 0.0,
  gw: 0.0,
  gh: 0.0,
  ox: 0.0,
  oy: 0.0,
  color: false,
  plot: -1,
  in_colour: false,
}

///|
/// The glyphs in the atlas by their places ("u v", as an instance has them): their keys.
fn glyph_keys() -> Map[String, Int] {
  let at : Map[String, Int] = {}
  text_cache.glyphs.each(fn(key, g) { if g.plot >= 0 { at["\{g.u} \{g.v}"] = key } })
  at
}

///|
/// The host's atlas a glyph goes in as its glyphs are placed in it: colour glyphs' own (`colour`, where the host keeps
/// one), else the words'; how far across past its place in it the glyph is said (@hostapi.colour_atlas_u).
fn atlas_for(colour : Bool) -> (@hostapi.Atlas, Int) {
  if colour {
    let a = match text_cache.colour_atlas {
      Some(a) => a
      None => {
        let a = @hostapi.Atlas::new(h_atlas_size(true))
        text_cache.colour_atlas = Some(a)
        a
      }
    }
    if a.sized() {
      return (a, @hostapi.colour_atlas_u)
    }
  }
  match text_cache.atlas {
    Some(a) => (a, 0)
    None => {
      let a = @hostapi.Atlas::new(h_atlas_size(false))
      text_cache.atlas = Some(a)
      (a, 0)
    }
  }
}

///|
/// Glyph `key` as it is drawn at `sc` pixels a point: where it is in the atlas, drawn from in this frame. One not in it
/// is drawn by the host and put there (its pixels its size at `sc`), in place of the glyphs drawn from longest ago where
/// it is full (@hostapi.Atlas); with no room while this frame is drawn, it is not drawn in it (asked for again by the
/// next).
fn glyph(key : Int, sc : Double) -> Glyph {
  match text_cache.glyphs.get(key) {
    Some(g) => {
      if g.plot >= 0 {
        atlas_for(g.in_colour).0.drawn(g.plot)
      }
      g
    }
    None => {
      let o = text_cache.gbuf
      h_glyph(key, o)
      let color = o[6] > 0.5
      let (a, across) = atlas_for(color)
      let w = (o[2] * sc).round().to_int()
      let h = (o[3] * sc).round().to_int()
      if !a.holds(w, h) {
        text_cache.glyphs[key] = no_glyph
        return no_glyph
      }
      match a.place(key, w, h, fn(k) { text_cache.glyphs.remove(k) }) {
        Some((plot, x, y)) => {
          h_glyph_put(key, x + across, y)
          let g = {
            u: (x + across).to_double(),
            v: y.to_double(),
            gw: o[2],
            gh: o[3],
            ox: o[4],
            oy: o[5],
            color,
            plot,
            in_colour: across > 0,
          }
          text_cache.glyphs[key] = g
          g
        }
        None => no_glyph
      }
    }
  }
}

///|
/// Line terminators (Line_Break BK, CR, LF, NL).
fn is_nl(c : Int) -> Bool {
  c == 10 || c == 13 || c == 11 || c == 12 || c == 0x85 || c == 0x2028 || c == 0x2029
}

///|
/// Whether there is a line break in `s`.
fn has_nl(s : String) -> Bool {
  s.iter().any(fn(ch) { is_nl(ch.to_int()) })
}

///|
/// Words that do not wrap put on one line, as CSS's white-space: nowrap puts them: each line break in them, with the
/// spaces round it, one space; none before the first words or after the last. `texts` are a paragraph's runs in order
/// (a break may run from one into the next), each its own again; None where there is no line break in them.
fn one_line(texts : Array[String]) -> Array[String]? {
  guard texts.iter().any(has_nl) else { None }
  let chars : Array[(Char, Int)] = []
  for k, s in texts {
    for ch in s {
      chars.push((ch, k))
    }
  }
  let blank = fn(ch : Char) { ch == ' ' || ch == '\t' || is_nl(ch.to_int()) }
  let out = texts.map(fn(_) { StringBuilder::new() })
  let n = chars.length()
  let mut said = false
  let mut i = 0
  while i < n {
    let (ch, k) = chars[i]
    if !blank(ch) {
      out[k].write_char(ch)
      said = true
      i = i + 1
      continue
    }
    // blanks: with a line break among them, one space where words are either side; else as they are
    let mut j = i
    let mut broken = false
    while j < n && blank(chars[j].0) {
      broken = broken || is_nl(chars[j].0.to_int())
      j = j + 1
    }
    if !broken {
      for m in i..<j {
        out[chars[m].1].write_char(chars[m].0)
      }
    } else if said && j < n {
      out[k].write_char(' ')
    }
    i = j
  }
  Some(out.map(fn(sb) { sb.to_string() }))
}

///|
/// Whether cluster i ends a line by itself: a line terminator followed by a
/// hard break (not CR before LF, when the host makes them two clusters).
fn Shaped::hard_end(self : Shaped, i : Int) -> Bool {
  is_nl(self.cu[i]) && (i + 1 >= self.starts.length() || self.brk[i + 1] == 2)
}

///|
fn layout_text(
  text : String,
  size : Double,
  weight : Int,
  max_w : Double,
  wrap : Bool,
  indent? : Double = 0.0,
  line? : Double = 0.0,
  trim? : Bool = false,
  spacing? : Double = 0.0,
  style? : Int = 0,
) -> TextLayout {
  let s = shape(text, size, weight, style~, spacing~)
  // greedy wrapping gives the same lines in any width from the widest
  // line up to the one they were made in (as Node::text_layout)
  if indent == 0.0 {
    match s.lay {
      Some(tl) if s.lay_line == line &&
        s.lay_trim == trim &&
        s.lay_wrap == wrap &&
        (!wrap || (tl.w <= max_w + 0.01 && max_w <= s.lay_max)) => return tl
      _ => ()
    }
  }
  let n = s.starts.length()
  let xs = Array::make(n, 0.0)
  let line_of = Array::make(n, 0)
  let line_start = []
  let line_end = []
  let line_w = []
  let mut ls = 0
  let mut i = 0
  // the first line may start indented
  let mut x = indent
  let mut last_break = -1
  let mut w_max = 0.0
  fn finish(start : Int, end : Int) {
    // width without trailing spaces, but for the words whole on one line: their spaces at the end are theirs, as
    // Android measures a line that needs no breaking (BoringLayout: "当前延迟 " then its figure, a space between)
    let whole = n > 0 && start == 0 && end == n && !is_nl(s.cu[n - 1])
    let mut e = end
    while e > start && ((s.cu[e - 1] == 32 && !whole) || is_nl(s.cu[e - 1])) {
      e = e - 1
    }
    let lw = if e > start { xs[e - 1] + s.adv[e - 1] } else { 0.0 }
    line_start.push(start)
    line_end.push(end)
    line_w.push(lw)
    if lw > w_max {
      w_max = lw
    }
  }

  while i < n {
    let c = s.cu[i]
    if s.hard_end(i) {
      xs[i] = x
      line_of[i] = line_start.length()
      finish(ls, i + 1)
      ls = i + 1
      i = i + 1
      x = 0.0
      last_break = -1
      continue
    }
    if i > ls && s.brk[i] != 0 {
      last_break = i
    }
    let a = s.adv[i]
    if wrap && x + a > max_w + 0.01 && i > ls && c != 32 {
      let brk = if last_break > ls { last_break } else { i }
      finish(ls, brk)
      ls = brk
      i = brk
      x = 0.0
      last_break = -1
      continue
    }
    xs[i] = x
    line_of[i] = line_start.length()
    x = x + a
    i = i + 1
  }
  if ls < n || line_start.length() == 0 || (n > 0 && s.hard_end(n - 1)) {
    finish(ls, n)
  }
  let lines = line_start.length()
  // a line as high as asked, the glyphs in its middle; measured by the first line's fonts, as Android measures them
  // (Chinese in it: the CJK font's, taller), the lines after it set in the same place
  let (_, _, own_h) = font_metrics(size, weight)
  let mut cjk = false
  if lines > 0 {
    for c in line_start[0]..<line_end[0] {
      if is_cjk(s.cu[c]) {
        cjk = true
        break
      }
    }
  }
  let (asc, desc) = line_metrics(size, weight, cjk)
  let (line_h, ascent, extra) = set_line(
    if line > 0.0 {
      line
    } else {
      own_h
    },
    asc,
    desc,
    g().scale,
    whole_pixel_lines(size, weight),
    trim~,
  )
  // right to left: each line's clusters in their visual order
  let lv = match s.bidi {
    Some(b) => {
      let lv = Array::make(n, 0)
      for l in 0..<lines {
        let a = line_start[l]
        let mut e = line_end[l]
        while e > a && (s.cu[e - 1] == 32 || is_nl(s.cu[e - 1])) {
          e = e - 1
        }
        bidi_line(b, s.starts, s.lens, s.adv, xs, lv, a, e, if l == 0 { indent } else { 0.0 })
        // the spaces it ends in stay after it, read left to right
        for c in e..<line_end[l] {
          lv[c] = 0
        }
      }
      lv
    }
    None => []
  }
  let tl = {
    text,
    shaped: s,
    line_start,
    line_end,
    line_w,
    xs,
    line_of,
    w: w_max,
    h: lines.to_double() * line_h + extra,
    ascent,
    line_h,
    lv,
  }
  if indent == 0.0 {
    s.lay = Some(tl)
    s.lay_max = max_w
    s.lay_line = line
    s.lay_trim = trim
    s.lay_wrap = wrap
  }
  tl
}

///|
/// Caret position (x, line) for a UTF-16 offset.
fn TextLayout::caret(self : TextLayout, off : Int) -> (Double, Int) {
  let s = self.shaped
  let n = s.starts.length()
  if n == 0 {
    return (0.0, 0)
  }
  let mut c = 0
  while c < n && s.starts[c] < off {
    c = c + 1
  }
  if c >= n {
    let last = n - 1
    if s.hard_end(last) {
      return (0.0, self.line_start.length() - 1)
    }
    (caret_after(self.xs, s.adv, self.lv, last), self.line_of[last])
  } else {
    (caret_before(self.xs, s.adv, self.lv, c), self.line_of[c])
  }
}

///|
/// The UTF-16 offset nearest to a point inside the text.
fn TextLayout::offset_at(self : TextLayout, x : Double, y : Double) -> Int {
  let s = self.shaped
  let lines = self.line_start.length()
  if lines == 0 || s.starts.length() == 0 {
    return 0
  }
  let line = imin(imax((y / self.line_h).to_int(), 0), lines - 1)
  let a = self.line_start[line]
  let b = self.line_end[line]
  if self.lv.length() > 0 {
    return bidi_offset_at(s.starts, s.lens, s.adv, self.xs, self.lv, s.cu, a, b, x)
  }
  for c in a..<b {
    if is_nl(s.cu[c]) {
      return s.starts[c]
    }
    if x < self.xs[c] + s.adv[c] / 2.0 {
      return s.starts[c]
    }
  }
  if b >= s.starts.length() {
    s.len
  } else {
    s.starts[b]
  }
}

///|
/// The line starting at offset `off` that the one before wraps into (no line break between them), or -1: where an
/// offset is the end of one line and the start of the next.
fn TextLayout::wrapped_into(self : TextLayout, off : Int) -> Int {
  let s = self.shaped
  for l in 1..<self.line_start.length() {
    let c = self.line_start[l]
    if c < s.starts.length() && s.starts[c] == off {
      return if s.hard_end(c - 1) { -1 } else { l }
    }
  }
  -1
}

///|
/// The caret's place (x, line) at offset `off`, as TextLayout::caret; with `up`, where a line wraps into the next
/// there, at the end of the line before instead of the next one's start (where a move to that line's end, or the
/// pointer past it, put the caret).
fn TextLayout::caret_side(self : TextLayout, off : Int, up : Bool) -> (Double, Int) {
  let l = if up { self.wrapped_into(off) } else { -1 }
  if l > 0 {
    let s = self.shaped
    return (caret_after(self.xs, s.adv, self.lv, self.line_end[l - 1] - 1), l - 1)
  }
  self.caret(off)
}

///|
/// The offset nearest to `x` on line `line`, and whether a caret there shows on that line where the line wraps into
/// the next at it (caret_side's `up`): past the line's end, where its words go on on the next.
fn TextLayout::offset_on(self : TextLayout, x : Double, line : Int) -> (Int, Bool) {
  let off = self.offset_at(x, (line.to_double() + 0.5) * self.line_h)
  (off, line + 1 < self.line_start.length() && self.wrapped_into(off) == line + 1)
}

///|
/// The start (`d` -1) or the end (1) of the line the caret at `off` shows on (`up`: caret_side's), and whether the
/// caret there shows on it as caret_side's `up` says: its end before its line break, or where it wraps into the next,
/// the next one's start shown at its own end.
fn TextLayout::line_end_at(self : TextLayout, off : Int, up : Bool, d : Int) -> (Int, Bool) {
  let (_, line) = self.caret_side(off, up)
  let (a, b) = self.line_range(line)
  let s = self.shaped
  let e = self.line_end[line]
  if d < 0 {
    (a, false)
  } else if line + 1 >= self.line_start.length() {
    (b, false)
  } else if e > 0 && s.hard_end(e - 1) {
    (s.starts[e - 1], false)
  } else {
    (b, true)
  }
}

///|
/// The start and end offsets of a line.
fn TextLayout::line_range(self : TextLayout, line : Int) -> (Int, Int) {
  let s = self.shaped
  let a = self.line_start[line]
  let b = self.line_end[line]
  let start = if a < s.starts.length() { s.starts[a] } else { s.len }
  let end = if b < s.starts.length() { s.starts[b] } else { s.len }
  (start, end)
}

///|
/// The width `text` advances on one line in that font (style: @hostapi.style_italic, style_mono), as mbui lays it out:
/// for comparing with the platform's own (src/textdiff).
pub fn text_advance(
  text : String,
  size? : Double = 15.0,
  weight? : Int = 400,
  style? : Int = 0,
) -> Double {
  let s = shape(text, size, weight, style~)
  let mut w = 0.0
  for a in s.adv {
    w = w + a
  }
  w
}
