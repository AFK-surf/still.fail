// The two sides' items matched and what differs (main.mbt). An item on either side: an element of the page (its box as
// getBoundingClientRect has it; its own words' box beside it) or a node of mbui's frame (Tester::boxes). Matched, in
// this order, each item once:
//   1. words: the same words (whitespace folded), the nearest of those first;
//   2. aria-label to a box's `label`, the same;
//   3. name: the page's class (vanilla-extract's debug name, `shell_dock`) to a box's `name` (written the same), or to
//      the name a move_state moves it by (`dock`: a class of that export's, any file's);
//   4. place: what paints something (a ground other than what is behind it, an edge, a picture) and is left, to what paints
//      something on the other side and covers nearly the same room (what shows of each: 80% of their union in common);
//   5. press: what takes a press or has a label, to the same on the other side, in nearly the same room (60%).
// Of a pair, what differs is listed: where it is or how big (beyond a pixel; words by their left, their middle and how
// wide they are drawn), its corner, its ground, its words' size, colour and opacity. Left over: on the page only (what
// mbui is missing), in mbui only (extra): what has words, a label or paints something; the page's wrappers that paint
// nothing are only counted.

///|
struct Rect {
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
fn Rect::area(self : Rect) -> Double {
  if self.w > 0.0 && self.h > 0.0 {
    self.w * self.h
  } else {
    0.0
  }
}

///|
/// What two rects have in common over what they cover between them.
fn Rect::iou(self : Rect, o : Rect) -> Double {
  let l = dmax(self.x, o.x)
  let t = dmax(self.y, o.y)
  let r = dmin(self.x + self.w, o.x + o.w)
  let b = dmin(self.y + self.h, o.y + o.h)
  if r <= l || b <= t {
    return 0.0
  }
  let both = (r - l) * (b - t)
  both / (self.area() + o.area() - both)
}

///|
/// What of it is inside `o` (none: where it was, 0 by 0).
fn Rect::within(self : Rect, o : Rect) -> Rect {
  let l = dmax(self.x, o.x)
  let t = dmax(self.y, o.y)
  let r = dmin(self.x + self.w, o.x + o.w)
  let b = dmin(self.y + self.h, o.y + o.h)
  if r <= l || b <= t {
    { ..self, w: 0.0, h: 0.0 }
  } else {
    { x: l, y: t, w: r - l, h: b - t }
  }
}

///|
fn Rect::to_string(self : Rect) -> String {
  "\{n1(self.x)},\{n1(self.y)} \{n1(self.w)}×\{n1(self.h)}"
}

///|
struct El {
  web : Bool
  index : Int
  /// the page's tag, or mbui's kind (Laid::kind)
  tag : String
  names : Array[String]
  label : String
  text : String
  /// how wide its words are drawn (mbui's; the page's are its words' box's)
  words_w : Double
  /// it takes presses (a button, a link, a field; a box with an id that takes its presses)
  hit : Bool
  /// it draws a picture of its own (an image, an icon's drawing)
  draws : Bool
  /// its ground made of what is under it (mbui's glass; the page's backdrop-filter is a ground of its own colour)
  glass : Bool
  parent : Int
  box : Rect
  cut : Rect
  /// the page's own words' box (None: none, or mbui's: its box is its words')
  words : Rect?
  radius : Double
  bg : (Int, Int, Int, Int)
  border_w : Double
  font_size : Double
  color : (Int, Int, Int, Int)
  opacity : Double
}

///|
fn El::shown(self : El) -> Bool {
  self.cut.w > 0.5 && self.cut.h > 0.5 && self.opacity > 0.01
}

///|
fn El::paints(self : El) -> Bool {
  self.bg.3 > 0 || self.border_w > 0.0
}

///|
/// What paints something to be seen: an edge, a picture of its own, or a ground other than what is behind it (the
/// nearest ground above it in its tree, else the page's).
fn surfaces(es : Array[El], ground : (Int, Int, Int, Int)) -> Map[Int, Bool] {
  let by : Map[Int, El] = {}
  for e in es {
    by[e.index] = e
  }
  let out = {}
  for e in es {
    if e.border_w > 0.0 || e.draws || e.glass {
      out[e.index] = true
      continue
    }
    if e.bg.3 == 0 {
      continue
    }
    let mut behind = ground
    let mut p = e.parent
    while p >= 0 {
      match by.get(p) {
        Some(q) => {
          if q.bg.3 == 255 {
            behind = q.bg
            break
          }
          p = q.parent
        }
        None => break
      }
    }
    if far(e.bg, behind) {
      out[e.index] = true
    }
  }
  out
}

///|
/// Where it is compared: its words' box for words (mbui's: its box as wide as its words).
fn El::rect(self : El, by_words : Bool) -> Rect {
  match (by_words, self.words) {
    (true, Some(r)) => r
    (true, None) if self.words_w > 0.0 => { ..self.box, w: self.words_w }
    _ => self.box
  }
}

///|
fn El::who(self : El) -> String {
  let sb = StringBuilder()
  sb.write_string(self.tag)
  if self.names.length() > 0 {
    sb.write_string(" " + self.names.join(" "))
  }
  if self.label != "" {
    sb.write_string(" [" + self.label + "]")
  }
  if self.text != "" {
    sb.write_string(" 「" + cut_words(self.text, 24) + "」")
  }
  sb.to_string()
}

///|
fn El::to_json(self : El) -> Json {
  let rect = fn(r : Rect) { Json::array([r.x.to_json(), r.y.to_json(), r.w.to_json(), r.h.to_json()]) }
  let rgba = fn(c : (Int, Int, Int, Int)) {
    Json::array([c.0.to_json(), c.1.to_json(), c.2.to_json(), c.3.to_json()])
  }
  Json::object({
    "index": self.index.to_json(),
    "kind": Json::string(self.tag),
    "names": Json::array(self.names.map(Json::string)),
    "label": Json::string(self.label),
    "text": Json::string(self.text),
    "box": rect(self.box),
    "cut": rect(self.cut),
    "radius": self.radius.to_json(),
    "bg": rgba(self.bg),
    "border_w": self.border_w.to_json(),
    "font_size": self.font_size.to_json(),
    "color": rgba(self.color),
    "opacity": self.opacity.to_json(),
  })
}

///|
fn rect_of(v : Json?) -> Rect? {
  match v {
    Some(Array([Number(x, ..), Number(y, ..), Number(w, ..), Number(h, ..)])) => Some({ x, y, w, h })
    _ => None
  }
}

///|
fn rgba_of(v : Json?) -> (Int, Int, Int, Int) {
  match v {
    Some(Array([Number(r, ..), Number(g, ..), Number(b, ..), Number(a, ..)])) =>
      (r.to_int(), g.to_int(), b.to_int(), a.to_int())
    _ => (0, 0, 0, 0)
  }
}

///|
fn rgba_int(c : Int64) -> (Int, Int, Int, Int) {
  (
    ((c >> 24) & 0xFFL).to_int(),
    ((c >> 16) & 0xFFL).to_int(),
    ((c >> 8) & 0xFFL).to_int(),
    (c & 0xFFL).to_int(),
  )
}

///|
/// An element as web-layout.mjs wrote it.
fn from_web(v : Json) -> El {
  let names = match field(v, "names") {
    Some(Array(a)) =>
      a.filter_map(fn(n) {
        match n {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
  let box : Rect = { x: num(v, "x", 0.0), y: num(v, "y", 0.0), w: num(v, "w", 0.0), h: num(v, "h", 0.0) }
  {
    web: true,
    index: num(v, "index", -1.0).to_int(),
    tag: str(v, "tag"),
    names,
    label: str(v, "label"),
    text: fold_words(str(v, "text")),
    words_w: 0.0,
    hit: field(v, "hit") is Some(True),
    draws: ["img", "svg", "video", "canvas"].contains(str(v, "tag")),
    glass: false,
    parent: num(v, "parent", -1.0).to_int(),
    box,
    cut: rect_of(field(v, "cut")).unwrap_or(box),
    // (what of its words shows: an ellipsis's room, not the line they would run on to)
    words: match rect_of(field(v, "words")) {
      Some(r) => Some(r.within(rect_of(field(v, "cut")).unwrap_or(box)))
      None => None
    },
    radius: corner(num(v, "radius", 0.0), box),
    bg: rgba_of(field(v, "bg")),
    border_w: num(v, "border_w", 0.0),
    font_size: num(v, "font_size", 0.0),
    color: rgba_of(field(v, "color")),
    opacity: num(v, "opacity", 1.0),
  }
}

///|
/// A node of mbui's frame.
fn from_laid(b : @ui.Laid) -> El {
  let names = []
  if b.name != "" {
    names.push(b.name)
  }
  if b.moves != "" && b.moves != b.name {
    names.push(b.moves)
  }
  let (cx, cy, cw, ch) = b.cut
  {
    web: false,
    index: b.index,
    tag: b.kind,
    names,
    label: b.label,
    text: fold_words(b.text),
    words_w: b.words_w,
    hit: b.hit,
    draws: b.draws,
    glass: b.glass,
    parent: b.parent,
    box: { x: b.x, y: b.y, w: b.w, h: b.h },
    cut: { x: cx, y: cy, w: cw, h: ch },
    words: None,
    radius: corner(b.radius, { x: b.x, y: b.y, w: b.w, h: b.h }),
    bg: rgba_int(b.bg),
    border_w: b.border_w,
    font_size: b.font_size,
    color: rgba_int(b.color),
    opacity: b.opacity,
  }
}

///|
/// A corner as drawn: no more than half the box's shorter side (999, a pill's, as its half height).
fn corner(r : Double, box : Rect) -> Double {
  dmin(r, dmin(box.w, box.h) / 2.0)
}

///|
/// Two items taken as one, and by what.
struct Pair {
  web : El
  mine : El
  by : String
  /// either paints something to be seen (surfaces): its corner and ground compared
  seen : Bool
}

///|
struct Report {
  pairs : Array[Pair]
  web_only : Array[El]
  mine_only : Array[El]
  /// the page's shown elements painting nothing, with no words nor label, left unmatched (its wrappers)
  wrappers : Int
}

///|
fn compare(theirs : Array[El], mine : Array[El], ground : (Int, Int, Int, Int)) -> Report {
  let web = theirs.filter(fn(e) { e.shown() })
  let ours = mine.filter(fn(e) { e.shown() })
  let paints_w = surfaces(theirs, ground)
  let paints_m = surfaces(mine, ground)
  let used_w : Map[Int, Bool] = {}
  let used_m : Map[Int, Bool] = {}
  let pairs : Array[Pair] = []
  // pairs of the same key, the nearest taken first
  let by_key = fn(
    by : String,
    key_w : (El) -> Array[String],
    key_m : (El) -> Array[String],
    by_words : Bool,
  ) {
    let groups : Map[String, Array[El]] = {}
    for m in ours {
      if used_m.contains(m.index) {
        continue
      }
      for k in key_m(m) {
        match groups.get(k) {
          Some(a) => a.push(m)
          None => groups[k] = [m]
        }
      }
    }
    let cands : Array[(Double, El, El)] = []
    for w in web {
      if used_w.contains(w.index) {
        continue
      }
      for k in key_w(w) {
        match groups.get(k) {
          Some(ms) =>
            for m in ms {
              let a = w.rect(by_words)
              let b = m.rect(by_words)
              let d = (a.x - b.x).abs() + (a.y - b.y).abs() + (a.w - b.w).abs() + (a.h - b.h).abs()
              cands.push((d, w, m))
            }
          None => ()
        }
      }
    }
    cands.sort_by(fn(p, q) { p.0.compare(q.0) })
    for c in cands {
      let (_, w, m) = c
      if used_w.contains(w.index) || used_m.contains(m.index) {
        continue
      }
      used_w[w.index] = true
      used_m[m.index] = true
      pairs.push({ web: w, mine: m, by, seen: paints_w.contains(w.index) || paints_m.contains(m.index) })
    }
  }
  by_key("words", fn(e) { if e.text != "" { [e.text] } else { [] } }, fn(e) { if e.text != "" { [e.text] } else { [] } }, true)
  by_key("label", fn(e) { if e.label != "" { [e.label] } else { [] } }, fn(e) { if e.label != "" { [e.label] } else { [] } }, false)
  // a page's class `file_export`: by itself, and its export alone (what a move_state's name is)
  by_key(
    "name",
    fn(e) {
      let keys = []
      for n in e.names {
        keys.push(n)
        match n.rev_find("_") {
          Some(i) => keys.push("." + n.unsafe_substring(start=i + 1, end=n.length()))
          None => ()
        }
      }
      keys
    },
    fn(e) { e.names.map(fn(n) { if n.contains("_") { n } else { "." + n } }) },
    false,
  )
  // by the room they cover: what is `fit` on each side and left, the most in common first
  let by_room = fn(by : String, fit_w : (El) -> Bool, fit_m : (El) -> Bool, least : Double) {
    let cands : Array[(Double, El, El)] = []
    for w in web {
      if used_w.contains(w.index) || !fit_w(w) {
        continue
      }
      for m in ours {
        if used_m.contains(m.index) || !fit_m(m) {
          continue
        }
        let k = w.cut.iou(m.cut)
        if k >= least {
          cands.push((k, w, m))
        }
      }
    }
    cands.sort_by(fn(p, q) { q.0.compare(p.0) })
    for c in cands {
      let (_, w, m) = c
      if used_w.contains(w.index) || used_m.contains(m.index) {
        continue
      }
      used_w[w.index] = true
      used_m[m.index] = true
      pairs.push({ web: w, mine: m, by, seen: paints_w.contains(w.index) || paints_m.contains(m.index) })
    }
  }
  by_room("place", fn(e) { paints_w.contains(e.index) }, fn(e) { paints_m.contains(e.index) }, 0.8)
  by_room("press", fn(e) { e.hit || e.label != "" }, fn(e) { e.hit || e.label != "" }, 0.6)
  let web_only = web.filter(fn(e) {
    !used_w.contains(e.index) && (e.text != "" || e.label != "" || paints_w.contains(e.index))
  })
  let mine_only = ours.filter(fn(e) {
    !used_m.contains(e.index) && (e.text != "" || e.label != "" || paints_m.contains(e.index))
  })
  let wrappers = web.length() - pairs.length() - web_only.length()
  { pairs, web_only, mine_only, wrappers }
}

///|
/// How far apart a pixel is still the same.
let px_same : Double = 1.0

///|
/// Where and how big: mbui's less the page's, each beyond a pixel ("" none).
fn Pair::moved(self : Pair) -> String {
  let a = self.web.rect(self.by == "words")
  let b = self.mine.rect(self.by == "words")
  let parts = []
  // (words: their left, their middle, how wide; how tall their box is is each side's line's, not compared)
  let ds = if self.by == "words" {
    [("x", b.x - a.x), ("中线y", b.y + b.h / 2.0 - (a.y + a.h / 2.0)), ("字宽", b.w - a.w)]
  } else {
    [("x", b.x - a.x), ("y", b.y - a.y), ("w", b.w - a.w), ("h", b.h - a.h)]
  }
  for d in ds {
    if d.1.abs() > px_same {
      parts.push(d.0 + signed(d.1))
    }
  }
  parts.join(" ")
}

///|
/// How it looks, where the two differ ("" none): its corner and ground (what paints), its words' size and colour,
/// its opacity.
fn Pair::looks(self : Pair) -> String {
  let w = self.web
  let m = self.mine
  let parts = []
  // (words: the page's element holding them may be a button with a ground, mbui's is the words alone)
  let seen = self.seen && self.by != "words"
  if seen && (w.radius - m.radius).abs() > 0.5 {
    parts.push("圆角 \{n1(w.radius)}→\{n1(m.radius)}")
  }
  // (mbui's glass is a ground of what is under it: no colour of its own to compare)
  if seen && !m.glass && far(w.bg, m.bg) {
    parts.push("底色 \{hex(w.bg)}→\{hex(m.bg)}")
  }
  if self.by == "words" {
    if (w.font_size - m.font_size).abs() > 0.1 {
      parts.push("字号 \{n1(w.font_size)}→\{n1(m.font_size)}")
    }
    if far(w.color, m.color) {
      parts.push("字色 \{hex(w.color)}→\{hex(m.color)}")
    }
  }
  if (w.opacity - m.opacity).abs() > 0.05 {
    parts.push("不透明度 \{n2(w.opacity)}→\{n2(m.opacity)}")
  }
  parts.join("，")
}

///|
fn far(a : (Int, Int, Int, Int), b : (Int, Int, Int, Int)) -> Bool {
  // (nothing painted either way: the same, whatever its channels)
  if a.3 == 0 && b.3 == 0 {
    return false
  }
  (a.0 - b.0).abs() > 4 || (a.1 - b.1).abs() > 4 || (a.2 - b.2).abs() > 4 || (a.3 - b.3).abs() > 4
}

///|
fn Report::summary(self : Report) -> String {
  let moved = self.pairs.filter(fn(p) { p.moved() != "" }).length()
  let looks = self.pairs.filter(fn(p) { p.looks() != "" }).length()
  "\{self.pairs.length()} matched (\{moved} off in place or size, \{looks} in look), \{self.web_only.length()} only on the page, \{self.mine_only.length()} only in mbui"
}

///|
fn by_place(a : El, b : El) -> Int {
  let c = a.box.y.compare(b.box.y)
  if c != 0 {
    c
  } else {
    a.box.x.compare(b.box.x)
  }
}

///|
/// The report, in Markdown.
fn Report::markdown(
  self : Report,
  title : String,
  w : Double,
  h : Double,
  steps : Array[Json],
  notes : Array[String],
  missing : Array[(String, Json)],
  loose : Array[(String, String)],
) -> String {
  let sb = StringBuilder()
  let line = fn(s : String) {
    sb.write_string(s)
    sb.write_char('\n')
  }
  let cell = fn(s : String) { s.replace_all(old="|", new="\\|").replace_all(old="\n", new=" ") }
  line("# 布局对照：\{title}")
  line("")
  line("窗口 \{n1(w)}×\{n1(h)}，浅色；步骤 `\{Json::array(steps).stringify()}`，每步之后 \{n1(step_ms)} ms 取数。")
  for n in notes {
    line("- 步骤：\{n}")
  }
  if missing.length() > 0 {
    line("- mbui 要了网页没有的 topic（空着，算加载中）：" + missing.map(fn(k) { "`" + k.0 + "`" }).join("、"))
  }
  if loose.length() > 0 {
    line("- 参数不同、按同名的那一个给的 topic：" + loose.map(fn(k) { "`" + k.0 + "`" }).join("、"))
  }
  line("")
  let moved = self.pairs.filter(fn(p) { p.moved() != "" })
  let looks = self.pairs.filter(fn(p) { p.looks() != "" })
  let same = self.pairs.filter(fn(p) { p.moved() == "" && p.looks() == "" }).length()
  line("| | 个数 |")
  line("|---|---|")
  line("| 对上、没差 | \{same} |")
  line("| 对上、位置或大小差 > \{n1(px_same)} px | \{moved.length()} |")
  line("| 对上、外观差 | \{looks.length()} |")
  line("| 只在网页（mbui 缺） | \{self.web_only.length()} |")
  line("| 只在 mbui（多出来） | \{self.mine_only.length()} |")
  line("| 网页的包裹层（不画东西、没字，不比） | \{self.wrappers} |")
  line("")
  line("配对：words 按字，label 按 aria-label，name 按类名，place 按位置（都画了和身后不同的底或边、重合 80% 以上），press 按位置（都能点或有 label、重合 60% 以上）。差值是 mbui 减网页；字比左边、中线和字宽。")
  line("")
  let pair_rows = fn(ps : Array[Pair], what : (Pair) -> String) {
    let sorted = ps.copy()
    sorted.sort_by(fn(a, b) { by_place(a.web, b.web) })
    line("| 网页 | mbui | 配对 | 网页的框 | mbui 的框 | 差 |")
    line("|---|---|---|---|---|---|")
    for p in sorted {
      let by_words = p.by == "words"
      line(
        "| \{cell(p.web.who())} | \{cell(p.mine.who())} | \{p.by} | \{p.web.rect(by_words).to_string()} | \{p.mine.rect(by_words).to_string()} | \{cell(what(p))} |",
      )
    }
    line("")
  }
  line("## 位置或大小不同")
  line("")
  pair_rows(moved, fn(p) { p.moved() })
  line("## 外观不同")
  line("")
  pair_rows(looks, fn(p) { p.looks() })
  let only_rows = fn(es : Array[El]) {
    let sorted = es.copy()
    sorted.sort_by(by_place)
    line("| 是什么 | 框 | 圆角 | 底色 | 字号 |")
    line("|---|---|---|---|---|")
    for e in sorted {
      let r = e.rect(e.text != "")
      line(
        "| \{cell(e.who())} | \{r.to_string()} | \{n1(e.radius)} | \{if e.bg.3 > 0 { hex(e.bg) } else { "" }} | \{if e.font_size > 0.0 && e.text != "" { n1(e.font_size) } else { "" }} |",
      )
    }
    line("")
  }
  line("## 只在网页（mbui 缺的）")
  line("")
  only_rows(self.web_only)
  line("## 只在 mbui（多出来的）")
  line("")
  only_rows(self.mine_only)
  sb.to_string()
}

// ── numbers and words ───────────────────────────────────────────────────

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// A number to a tenth, without a trailing ".0".
fn n1(v : Double) -> String {
  let r = (v * 10.0).round() / 10.0
  if r == r.floor() {
    r.to_int().to_string()
  } else {
    r.to_string()
  }
}

///|
fn n2(v : Double) -> String {
  ((v * 100.0).round() / 100.0).to_string()
}

///|
fn signed(v : Double) -> String {
  if v > 0.0 {
    "+" + n1(v)
  } else {
    n1(v)
  }
}

///|
fn hex(c : (Int, Int, Int, Int)) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  sb.write_char('#')
  for v in [c.0, c.1, c.2, c.3] {
    sb.write_char(digits[(v >> 4) & 0xF].unsafe_to_char())
    sb.write_char(digits[v & 0xF].unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Words with every run of whitespace one space, none at either end.
fn fold_words(s : String) -> String {
  let sb = StringBuilder()
  let mut space = false
  let mut any = false
  for ch in s {
    if ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r' || ch == '\u{a0}' {
      space = true
    } else {
      if space && any {
        sb.write_char(' ')
      }
      space = false
      any = true
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn cut_words(s : String, most : Int) -> String {
  let cs = s.to_array()
  if cs.length() <= most {
    s
  } else {
    String::from_array(cs[:most].to_array()) + "…"
  }
}
