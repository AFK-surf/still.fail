// Words that may be selected: the rich paragraphs in a box (a message's Markdown, a person's words), taken in the order
// they are laid out as one text, one paragraph to a line. The app marks the box while building it (Ctx::words) with a
// key and, if it has one, the passage selected (offsets in that text) and its colour; once laid out, what the box holds
// is kept under the key (Ctx::words_of: where each paragraph is, its layout) for the app to find offsets, words and
// rects in, from a finger's place; the passage is drawn behind the words of each paragraph it covers. Selection itself
// (holding, widening by words, handles, what to do with it) is the app's: this is what it needs of the layout.

///|
/// A paragraph among the words: its layout, where its text's top left is in the window, its size, and where its
/// text starts in the words' (UTF-16).
pub struct WordsPiece {
  layout : RichLayout
  x : Double
  y : Double
  w : Double
  h : Double
  start : Int
}

///|
/// Words as last laid out: their text (the paragraphs one to a line) and their paragraphs, in order.
pub struct Words {
  text : String
  pieces : Array[WordsPiece]
}

///|
priv struct WordsMark {
  node : Int
  key : String
  a : Int
  b : Int
  color : Int64
}

///|
/// The boxes marked this frame.
let words_marks : Array[WordsMark] = []

///|
/// What each key's box held when last laid out.
let words_kept : Map[String, Words] = {}

///|
/// This frame's selections, by rich node: the range in its own text and the colour drawn behind it.
let words_sel : Map[Int, (Int, Int, Int64)] = {}

///|
/// Box `i` (built this frame) holds words that may be selected, kept as `key` once laid out (words_of); `a` until
/// `b` of them is drawn selected, `color` behind it (none while `a` >= `b`).
pub fn Ctx::words(
  self : Ctx,
  i : Int,
  key : String,
  a? : Int = 0,
  b? : Int = 0,
  color? : Int64 = 0L,
) -> Unit {
  ignore(self)
  words_marks.push({ node: i, key, a, b, color })
}

///|
/// The words of the box marked `key` as they were last laid out (None when it was not built the last frame).
pub fn Ctx::words_of(self : Ctx, key : String) -> Words? {
  ignore(self)
  words_kept.get(key)
}

///|
/// Once laid out: what each marked box holds, kept; the selections to draw. Words kept elsewhere than before (their
/// box moved: a page sliding in, a list scrolled) are a layout read back that moved (Ctx::read_changed): what the
/// app placed from them this frame (handles over a passage, words_of read while building) was placed where they were
/// the pass before, and is placed again as the frame is built again.
fn Ctx::words_after_layout(self : Ctx) -> Unit {
  words_sel.clear()
  if words_marks.is_empty() {
    words_kept.clear()
    return
  }
  let seen : Map[String, Bool] = {}
  for m in words_marks {
    let pieces : Array[WordsPiece] = []
    let sb = StringBuilder()
    let nodes : Array[Int] = []
    self.rich_nodes(m.node, nodes)
    for i in nodes {
      let n = self.nodes[i]
      match n.rl {
        Some(rl) => {
          if pieces.length() > 0 {
            sb.write_char('\n')
          }
          let start = sb.to_string().length()
          sb.write_string(rl.text)
          pieces.push({
            layout: rl,
            x: n.x + n.pad_l,
            y: n.y + n.pad_t,
            w: rl.w,
            h: rl.h,
            start,
          })
          if m.a < m.b {
            let la = imax(m.a - start, 0)
            let lb = imin(m.b - start, rl.text.length())
            if la < lb {
              words_sel[i] = (la, lb, m.color)
            }
          }
        }
        None => ()
      }
    }
    match words_kept.get(m.key) {
      Some(was) if !same_place(was.pieces, pieces) => self.read_changed("words_of \"" + m.key + "\"")
      _ => ()
    }
    words_kept[m.key] = { text: sb.to_string(), pieces }
    seen[m.key] = true
  }
  words_marks.clear()
  let gone : Array[String] = []
  words_kept.each(fn(k, _) { if !seen.contains(k) { gone.push(k) } })
  for k in gone {
    words_kept.remove(k)
  }
}

///|
/// Whether paragraphs kept twice lie in the same places, the same size.
fn same_place(a : Array[WordsPiece], b : Array[WordsPiece]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for k in 0..<a.length() {
    let p = a[k]
    let q = b[k]
    if p.x != q.x || p.y != q.y || p.w != q.w || p.h != q.h || p.start != q.start {
      return false
    }
  }
  true
}

///|
/// The rich nodes under node `i`, in the order they were built.
fn Ctx::rich_nodes(self : Ctx, i : Int, out : Array[Int]) -> Unit {
  let n = self.nodes[i]
  if n.kind == kind_rich {
    out.push(i)
    return
  }
  let mut k = n.first
  while k >= 0 {
    self.rich_nodes(k, out)
    k = self.nodes[k].next
  }
}

///|
/// The selection drawn behind rich node `i`'s words this frame (paint_rich).
fn Ctx::paint_selection(self : Ctx, i : Int, lay : RichLayout, ox : Double, oy : Double, alpha : Double) -> Unit {
  match words_sel.get(i) {
    Some((a, b, color)) =>
      for r in lay.rects(a, b) {
        self.emit_rect(ox + r.0, oy + r.1, r.2, r.3, 0.0, color, 0.0, 0L, alpha)
      }
    None => ()
  }
}

///|
/// The text from `a` until `b` (clamped to it).
pub fn Words::slice(self : Words, a : Int, b : Int) -> String {
  let n = self.text.length()
  let a = imax(0, imin(a, n))
  let b = imax(a, imin(b, n))
  self.text.view(start_offset=a, end_offset=b).to_string()
}

///|
/// The offset in the words of a point in the window (Pick.kt offsetAt): in the paragraph whose lines hold its height
/// (the nearest across, beside a table's cell); else the start of the next one down; past them all, their end.
pub fn Words::offset_at(self : Words, x : Double, y : Double) -> Int {
  let mut hit : WordsPiece? = None
  let mut best = 1.0e18
  for p in self.pieces {
    if y >= p.y && y < p.y + p.h {
      let d = if x < p.x {
        p.x - x
      } else if x > p.x + p.w {
        x - p.x - p.w
      } else {
        0.0
      }
      if d < best {
        best = d
        hit = Some(p)
      }
    }
  }
  match hit {
    Some(p) => {
      let off = p.layout.offset_at(x - p.x, y - p.y)
      p.start + imax(0, imin(off, p.layout.text.length()))
    }
    None => {
      for p in self.pieces {
        if y < p.y {
          return p.start
        }
      }
      self.text.length()
    }
  }
}

///|
/// The boxes (x, y, w, h in the window; one a line) the words from `a` until `b` cover.
pub fn Words::rects(self : Words, a : Int, b : Int) -> Array[(Double, Double, Double, Double)] {
  let out = []
  for p in self.pieces {
    let la = imax(a - p.start, 0)
    let lb = imin(b - p.start, p.layout.text.length())
    if la < lb {
      for r in p.layout.rects(la, lb) {
        out.push((p.x + r.0, p.y + r.1, r.2, r.3))
      }
    }
  }
  out
}

///|
/// The word at an offset, as a phone picks one (Pick.kt wordAt: the system's word boundaries, a dictionary's for
/// Chinese where the host has one): a word as it is; a space or a mark, only that character.
pub fn Words::word_at(self : Words, off : Int) -> (Int, Int) {
  word_at(self.text, off)
}

///|
/// The word of `text` at `off` (UTF-16): the host's word boundaries (Android's BreakIterator, Apple's
/// CFStringTokenizer, the browser's Intl.Segmenter), else this one's own: letters and digits together, a Han, kana or
/// Hangul character alone, anything else (a space, a mark) alone.
pub fn word_at(text : String, off : Int) -> (Int, Int) {
  let n = text.length()
  if n == 0 {
    return (0, 0)
  }
  let i = imax(0, imin(off, n - 1))
  let (s, e) = h_word_at(text, i)
  if s >= 0 && e > s && s <= i && i < e {
    let w = text.view(start_offset=s, end_offset=e).to_string()
    if w.trim(chars=" \t\n").length() > 0 {
      return (s, e)
    }
    return (i, i + 1)
  }
  own_word_at(text, i)
}

///|
/// A character's kind for own_word_at: 1 a word's (letters, digits, `_`, an apostrophe within), 2 one that is a word
/// alone (Han, kana, Hangul), 0 anything else.
fn word_kind(c : Int) -> Int {
  if (c >= 0x4E00 && c <= 0x9FFF) ||
    (c >= 0x3400 && c <= 0x4DBF) ||
    (c >= 0x3040 && c <= 0x30FF) ||
    (c >= 0xAC00 && c <= 0xD7AF) ||
    (c >= 0xF900 && c <= 0xFAFF) {
    2
  } else if (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    (c >= 0xC0 && c <= 0x24F && c != 0xD7 && c != 0xF7) ||
    (c >= 0x370 && c <= 0x52F) {
    1
  } else {
    0
  }
}

///|
fn own_word_at(text : String, i : Int) -> (Int, Int) {
  let unit = fn(k : Int) -> Int { text.at(k).to_int() }
  let k = word_kind(unit(i))
  if k != 1 {
    // a surrogate pair stays whole
    let c = unit(i)
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length() {
      return (i, i + 2)
    }
    if c >= 0xDC00 && c <= 0xDFFF && i > 0 {
      return (i - 1, i + 1)
    }
    return (i, i + 1)
  }
  let n = text.length()
  let mut s = i
  while s > 0 && word_kind(unit(s - 1)) == 1 {
    s = s - 1
  }
  let mut e = i + 1
  while e < n && word_kind(unit(e)) == 1 {
    e = e + 1
  }
  (s, e)
}

///|
/// The press under way is the app's from here (a hold that picks words, Pick.kt): no tap of what it went down on once
/// lifted, nothing under it scrolled or dragged by it while it lasts, no edge swipe; the pointer is still told
/// (Ctx::pointer), so the app follows the finger. Nothing when no finger is down.
pub fn Ctx::take_press(self : Ctx) -> Unit {
  if !self.down {
    return
  }
  self.active = 0
  self.taken_at = self.press_at
  self.drag_scroll = 0
  self.dragging = false
  self.editor_drag = false
  if self.edge != 2 {
    self.edge = 0
  }
}

///|
/// Where a tap landed since the last frame, wherever it was (on a button, a list, nothing), if one did: a press let
/// go without dragging, not one the app took (Ctx::take_press). For what a tap anywhere lets go of (a pick of words).
pub fn Ctx::tapped_anywhere(self : Ctx) -> (Double, Double)? {
  self.tapped
}
