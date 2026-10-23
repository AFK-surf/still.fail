// The mbui app's pictures against Android's, pixel by pixel (scripts/android-ref.sh compare; was android_ref.py):
//
//   androidref REFS MBUI OUT ALLOWED NAME…
//
// REFS/NAME.png (Android's), MBUI/NAME.png (the mbui app's: its window as mbui-render drew it, the window between the
// system's bars, which is put where it lies on the screen here; or the whole screen): every pixel whose colour differs
// counts (a channel more than one step apart: Android's same picture on two runners has differed by that alone, 31 px
// at circles' edges, one channel a step; within a run it never has), but those under the system's bars (their icons
// the system's: REFS/android.json `bars`, the rows at the top and the bottom) and those inside a region ALLOWED lets
// differ. allowed.json: {"NAME": {"regions": [{"x", "y", "w", "h", "why"}], "left": N, "texts_left": N, "why": …}}:
// `left` the pixels the mbui app is known to differ by still, outside its regions (what is not done yet, said in
// `why`): a screen fails when it differs by more, and is told to lower it when by fewer (the number only falls).
//
// Words are compared by where they stand, not by their pixels (a line set a fraction of a pixel apart differs in every
// pixel along its edges, which hides what else differs): REFS/NAME.texts.json (Android's lines: ScreensRefTest, in the
// screen's pixels) and MBUI/NAME.texts.json (the mbui app's: the Tester's text runs, in points, with the window's scale
// and where it lies), each line {"t": words, "x0", "x1": its first letter's left, its last's right, "b": its baseline,
// "top", "bot"}. Their boxes (both apps', a pixel around) are left out of the pixels compared; the lines are paired by
// their words (in order where words repeat) and one counts as apart when its left, right or baseline is more than
// TEXT_PX from Android's, or when either app has a line the other has not. allowed.json's `texts_left`: how many lines
// are known apart still (the number only falls, as `left`).
//
// Out: OUT/NAME.png (Android | mbui | Android greyed with the differing pixels red, the allowed regions outlined blue,
// the words' boxes left out green, at half size), OUT/report.md (each screen's count and where its differences lie, its
// lines apart). Exit 1 when a screen differs outside its regions by more than its `left`, its lines apart are more than
// its `texts_left`, or a picture is missing or of another size.

///|
/// The cells differences are counted in, for where they lie (pixels a side).
let cell = 16

///|
/// How far a line may stand from Android's (its left, right or baseline, in the screen's pixels) and be where it is.
let text_px = 0.5

///|
/// How far around a line's box its pixels are left out (antialiasing reaches past the box by a pixel).
let text_pad = 2

///|
priv struct Line {
  t : String
  x0 : Double
  x1 : Double
  b : Double
  top : Double
  bot : Double
  /// the pieces it was joined from (rows), none for a line as it came
  of : Array[Line]
}

///|
fn fail(why : String) -> Unit {
  @sys.eprintln("androidref: " + why)
  @sys.exit(1)
}

///|
fn json_at(path : String) -> Json? {
  match @sys.read_text(path) {
    Some(text) => try Some(@json.parse(text)) catch { _ => None }
    None => None
  }
}

///|
fn num(j : Json?, key : String) -> Double {
  match j {
    Some(Object(m)) =>
      match m.get(key) {
        Some(Number(d, ..)) => d
        _ => 0.0
      }
    _ => 0.0
  }
}

///|
fn text_of(j : Json?, key : String) -> String {
  match j {
    Some(Object(m)) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// A screen's lines (texts.json), in the screen's pixels: the mbui app's in points, with the window's scale, put `top`
/// rows down (where its window lies on the screen; none for one edge to edge: {"scale", "edge", "lines"}); Android's
/// in the screen's pixels already (a list). None where there is no such file.
fn texts(path : String, top? : Double = 0.0) -> Array[Line]? {
  let j = json_at(path)
  match j {
    Some(Array(ls)) =>
      Some(
        ls.map(fn(l) {
          let l = Some(l)
          {
            t: text_of(l, "t"),
            x0: num(l, "x0"),
            x1: num(l, "x1"),
            b: num(l, "b"),
            top: num(l, "top"),
            bot: num(l, "bot"),
            of: [],
          }
        }),
      )
    Some(Object(m)) => {
      let scale = num(j, "scale")
      // (a window edge to edge, under the system's bars: on the screen from its top)
      let top = match m.get("edge") {
        Some(True) => 0.0
        _ => top
      }
      let lines = match m.get("lines") {
        Some(Array(ls)) => ls
        _ => []
      }
      Some(
        lines.map(fn(l) {
          let l = Some(l)
          {
            t: text_of(l, "t"),
            x0: num(l, "x0") * scale,
            x1: num(l, "x1") * scale,
            b: num(l, "b") * scale + top,
            top: num(l, "top") * scale + top,
            bot: num(l, "bot") * scale + top,
            of: [],
          }
        }),
      )
    }
    _ => None
  }
}

///|
/// Python's round (half to even), as the rows were keyed by.
fn round_even(v : Double) -> Int {
  let f = v.floor()
  let d = v - f
  if d > 0.5 {
    f.to_int() + 1
  } else if d < 0.5 {
    f.to_int()
  } else if f.to_int() % 2 == 0 {
    f.to_int()
  } else {
    f.to_int() + 1
  }
}

///|
/// Lines on one baseline (within a pixel) joined into one, left to right, where more than one: (the joined, the rest).
fn rows(lines : Array[Line]) -> (Array[Line], Array[Line]) {
  let by : Map[Int, Array[Line]] = {}
  for l in lines {
    let k = round_even(l.b)
    match by.get(k) {
      Some(a) => a.push(l)
      None => by[k] = [l]
    }
  }
  let keys = by.keys().collect()
  keys.sort()
  let joined = []
  let rest = []
  for k in keys {
    let ls = by[k]
    if ls.length() < 2 {
      for l in ls {
        rest.push(l)
      }
      continue
    }
    let ls = ls.copy()
    ls.sort_by(fn(a, b) { a.x0.compare(b.x0) })
    let mut top = ls[0].top
    let mut bot = ls[0].bot
    for l in ls {
      top = @cmp.minimum(top, l.top)
      bot = @cmp.maximum(bot, l.bot)
    }
    joined.push({
      t: ls.map(fn(l) { l.t }).join(" "),
      x0: ls[0].x0,
      x1: ls[ls.length() - 1].x1,
      b: ls[0].b,
      top,
      bot,
      of: ls,
    })
  }
  (joined, rest)
}

///|
/// Words with their spaces taken out.
fn flat(t : String) -> String {
  let b = StringBuilder::new()
  for c in t {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// Whether `a` is the very line `b` (the same object, as Python's `in` finds it among lines).
fn same(a : Line, b : Line) -> Bool {
  physical_equal(a, b)
}

///|
fn take(from : Array[Line], l : Line) -> Bool {
  for i in 0..<from.length() {
    if same(from[i], l) {
      from.remove(i) |> ignore
      return true
    }
  }
  false
}

///|
/// The lines paired by their words, in order where words repeat: (Android's, mbui's), and those of each alone. Words
/// one app sets as one line and the other as pieces side by side on one baseline (a name inside a sentence, a Text of
/// its own) are paired as one line: the pieces joined, spaces aside.
fn pair(
  android : Array[Line],
  mbui : Array[Line],
) -> (Array[(Line, Line)], Array[Line], Array[Line]) {
  let left = mbui.copy()
  let pairs = []
  let alone = []
  for a in android {
    match left.search_by(fn(m) { m.t == a.t }) {
      Some(k) => pairs.push((a, left.remove(k)))
      None => alone.push(a)
    }
  }
  let (joined_a, alone_a) = rows(alone)
  let (joined_m, left) = rows(left)
  for a in joined_a.copy() + alone_a.copy() {
    let both = joined_m + left
    match both.search_by(fn(m) { flat(m.t) == flat(a.t) }) {
      None => continue
      Some(k) => {
        let m = both[k]
        pairs.push((a, m))
        if !take(joined_a, a) {
          take(alone_a, a) |> ignore
        }
        if !take(joined_m, m) {
          take(left, m) |> ignore
        }
      }
    }
  }
  // (pieces that paired with nothing joined: alone as the pieces they are)
  let lone_a = alone_a.copy()
  for j in joined_a {
    for p in j.of {
      lone_a.push(p)
    }
  }
  let lone_m = left.copy()
  for j in joined_m {
    for p in j.of {
      lone_m.push(p)
    }
  }
  (pairs, lone_a, lone_m)
}

///|
/// The cells with differences, joined where they touch, as rectangles (x, y, w, h, pixels) in the screen's pixels, the
/// most first.
fn regions(cells : Map[(Int, Int), Int]) -> Array[(Int, Int, Int, Int, Int)] {
  let starts = cells.keys().collect()
  starts.sort()
  let seen : Map[(Int, Int), Bool] = {}
  let out = []
  for start in starts {
    if seen.contains(start) {
      continue
    }
    let stack = [start]
    seen[start] = true
    let mut x0 = start.0
    let mut x1 = start.0
    let mut y0 = start.1
    let mut y1 = start.1
    let mut n = 0
    while stack.pop() is Some((cx, cy)) {
      n += cells.get((cx, cy)).unwrap_or(0)
      x0 = @cmp.minimum(x0, cx)
      x1 = @cmp.maximum(x1, cx)
      y0 = @cmp.minimum(y0, cy)
      y1 = @cmp.maximum(y1, cy)
      for nb in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)] {
        if cells.contains(nb) && !seen.contains(nb) {
          seen[nb] = true
          stack.push(nb)
        }
      }
    }
    out.push((x0 * cell, y0 * cell, (x1 - x0 + 1) * cell, (y1 - y0 + 1) * cell, n))
  }
  // (the most first; as found where as many)
  let order = Array::makei(out.length(), fn(i) { i })
  order.sort_by(fn(a, b) {
    let c = out[b].4.compare(out[a].4)
    if c != 0 {
      c
    } else {
      a.compare(b)
    }
  })
  order.map(fn(i) { out[i] })
}

///|
/// `v` with its sign and one decimal (Python's `{:+.1f}`).
fn signed1(v : Double) -> String {
  let tenths = (v.abs() * 10.0).round()
  let neg = v < 0.0 || (v == 0.0 && 1.0 / v < 0.0)
  let whole = (tenths / 10.0).floor().to_int()
  let frac = (tenths - whole.to_double() * 10.0).to_int()
  (if neg { "-" } else { "+" }) + whole.to_string() + "." + frac.to_string()
}

///|
/// The first `n` characters of `s`.
fn first(s : String, n : Int) -> String {
  let b = StringBuilder::new()
  let mut i = 0
  for c in s {
    if i >= n {
      break
    }
    b.write_char(c)
    i += 1
  }
  b.to_string()
}

///|
/// A picture's pixels as rows of RGB bytes, `rows` long, its own rows `off` down (black above and below: a window put
/// where it lies on the screen).
priv struct Rows {
  pic : @png.Picture
  off : Int
}

///|
fn Rows::rgb(self : Rows, x : Int, y : Int) -> (Int, Int, Int) {
  let y = y - self.off
  if y < 0 || y >= self.pic.h {
    (0, 0, 0)
  } else {
    self.pic.rgb(x, y)
  }
}

///|
// kept across runs: a table, never written
let crc_table : FixedArray[UInt] = {
  let t = FixedArray::make(256, 0U)
  for n in 0..<256 {
    let mut c = n.reinterpret_as_uint()
    for _ in 0..<8 {
      c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
    }
    t[n] = c
  }
  t
}

///|
fn be32(buf : @buffer.Buffer, v : UInt) -> Unit {
  buf.write_byte((v >> 24).to_byte())
  buf.write_byte(((v >> 16) & 0xFFU).to_byte())
  buf.write_byte(((v >> 8) & 0xFFU).to_byte())
  buf.write_byte((v & 0xFFU).to_byte())
}

///|
fn chunk(out : @buffer.Buffer, kind : Bytes, data : Bytes) -> Unit {
  be32(out, data.length().reinterpret_as_uint())
  let mut c = 0xFFFFFFFFU
  for b in kind {
    out.write_byte(b)
    c = crc_table[((c ^ b.to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  for b in data {
    out.write_byte(b)
    c = crc_table[((c ^ b.to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  be32(out, c ^ 0xFFFFFFFFU)
}

///|
/// RGB rows (`w` × `h`, 3 bytes a pixel) as a PNG: its data in stored deflate blocks (the artifact it goes in is
/// zipped).
fn png_of(w : Int, h : Int, rgb : FixedArray[Byte]) -> Bytes {
  let raw = @buffer.new(size_hint=h * (w * 3 + 1))
  for y in 0..<h {
    raw.write_byte(b'\x00')
    for i in 0..<(w * 3) {
      raw.write_byte(rgb[y * w * 3 + i])
    }
  }
  let data = raw.to_bytes()
  let z = @buffer.new(size_hint=data.length() + data.length() / 65535 * 5 + 16)
  z.write_byte(b'\x78')
  z.write_byte(b'\x01')
  let mut at = 0
  while at < data.length() || at == 0 {
    let n = @cmp.minimum(65535, data.length() - at)
    let last = at + n >= data.length()
    z.write_byte(if last { b'\x01' } else { b'\x00' })
    z.write_byte((n & 0xFF).to_byte())
    z.write_byte((n >> 8).to_byte())
    z.write_byte((n.lnot() & 0xFF).to_byte())
    z.write_byte(((n.lnot() >> 8) & 0xFF).to_byte())
    for i in at..<(at + n) {
      z.write_byte(data[i])
    }
    at += n
    if last {
      break
    }
  }
  // adler-32 of the data
  let mut s1 = 1U
  let mut s2 = 0U
  for b in data {
    s1 = (s1 + b.to_uint()) % 65521U
    s2 = (s2 + s1) % 65521U
  }
  be32(z, (s2 << 16) | s1)
  let out = @buffer.new()
  for b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    out.write_byte(b.to_byte())
  }
  let ihdr = @buffer.new()
  be32(ihdr, w.reinterpret_as_uint())
  be32(ihdr, h.reinterpret_as_uint())
  for b in [8, 2, 0, 0, 0] {
    ihdr.write_byte(b.to_byte())
  }
  chunk(out, b"IHDR", ihdr.to_bytes())
  chunk(out, b"IDAT", z.to_bytes())
  chunk(out, b"IEND", b"")
  out.to_bytes()
}

///|
fn main {
  let argv = @env.args()
  if argv.length() < 5 {
    @sys.eprintln("androidref REFS MBUI OUT ALLOWED NAME…")
    @sys.exit(2)
    return
  }
  let refs = argv[1]
  let mbui = argv[2]
  let out = argv[3]
  let allowed = json_at(argv[4])
  let names = argv[5:].to_array()
  let system = json_at(@sys.join(refs, "android.json"))
  let bars = match system {
    Some(Object(m)) => m.get("bars")
    _ => None
  }
  let bar_top = num(bars, "top").to_int()
  let bar_bottom = num(bars, "bottom").to_int()
  @sys.makedirs(out)
  let report = [
    "| screen | pixels differing | outside its regions (left) | where (x, y, w, h: pixels) |", "|---|---|---|---|",
  ]
  let text_report = [
    "| screen | Android's lines | lines apart (texts_left) | which (pixels: mbui's less Android's) |", "|---|---|---|---|",
  ]
  let failed : Array[String] = []
  let lower : Array[String] = []
  for name in names {
    let a_path = @sys.join(refs, name + ".png")
    let m_path = @sys.join(mbui, name + ".png")
    if !@sys.exists(a_path) || !@sys.exists(m_path) {
      report.push(
        "| \{name} | — | missing: \{if !@sys.exists(a_path) { "Android" } else { "mbui" }}'s picture | |",
      )
      failed.push(name)
      continue
    }
    let a = match @png.read(a_path) {
      Ok(p) => p
      Err(why) => {
        fail(why)
        return
      }
    }
    let m = match @png.read(m_path) {
      Ok(p) => p
      Err(why) => {
        fail(why)
        return
      }
    }
    let aw = a.w
    let ah = a.h
    // the mbui app's window put where it lies on the screen (from the screen's top where it is the whole screen)
    let off = if m.w == aw && m.h == ah { 0 } else { bar_top }
    if m.w != aw || off + m.h > ah {
      report.push("| \{name} | — | another size: Android \{aw}×\{ah}, mbui \{m.w}×\{m.h} | |")
      failed.push(name)
      continue
    }
    let ar : Rows = { pic: a, off: 0 }
    let mr : Rows = { pic: m, off }
    let mine = match allowed {
      Some(Object(all)) => all.get(name)
      _ => None
    }
    let rects : Array[(Int, Int, Int, Int)] = match mine {
      Some(Object(o)) =>
        match o.get("regions") {
          Some(Array(rs)) =>
            rs.map(fn(r) {
              let r = Some(r)
              let x = num(r, "x").to_int()
              let y = num(r, "y").to_int()
              (x, y, x + num(r, "w").to_int(), y + num(r, "h").to_int())
            })
          _ => []
        }
      _ => []
    }
    let left = num(mine, "left").to_int()
    let texts_left = num(mine, "texts_left").to_int()
    // the words: compared by where they stand; their boxes left out of the pixels
    let a_texts = texts(@sys.join(refs, name + ".texts.json"))
    let m_texts = texts(@sys.join(mbui, name + ".texts.json"), top=bar_top.to_double())
    let boxes : Array[(Int, Int, Int, Int)] = []
    let apart : Array[(Double, String)] = []
    match (a_texts, m_texts) {
      (Some(at), Some(mt)) => {
        for l in at + mt {
          boxes.push(
            (
              l.x0.to_int() - text_pad,
              l.top.to_int() - text_pad,
              l.x1.to_int() + 1 + text_pad,
              l.bot.to_int() + 1 + text_pad,
            ),
          )
        }
        let (pairs, alone_a, alone_m) = pair(at, mt)
        for p in pairs {
          let (al, ml) = p
          let d0 = ml.x0 - al.x0
          let d1 = ml.x1 - al.x1
          let d2 = ml.b - al.b
          let most = @cmp.maximum(@cmp.maximum(d0.abs(), d1.abs()), d2.abs())
          if most > text_px {
            apart.push(
              (
                most,
                "\"\{first(al.t, 24)}\" left \{signed1(d0)} right \{signed1(d1)} baseline \{signed1(d2)}",
              ),
            )
          }
        }
        for l in alone_a {
          apart.push((1.0e9, "\"\{first(l.t, 24)}\" Android's alone"))
        }
        for l in alone_m {
          apart.push((1.0e9, "\"\{first(l.t, 24)}\" mbui's alone"))
        }
        // (the farthest first; as found where as far)
        let order = Array::makei(apart.length(), fn(i) { i })
        order.sort_by(fn(x, y) {
          let c = apart[y].0.compare(apart[x].0)
          if c != 0 {
            c
          } else {
            x.compare(y)
          }
        })
        let sorted = order.map(fn(i) { apart[i] })
        apart.clear()
        for s in sorted {
          apart.push(s)
        }
      }
      _ => ()
    }
    // (a row's boxes, for the rows they cover)
    let row_boxes : Array[Array[(Int, Int)]] = Array::makei(ah, fn(_) { [] })
    for bx in boxes {
      for y in @cmp.maximum(0, bx.1)..<@cmp.minimum(ah, bx.3) {
        row_boxes[y].push((bx.0, bx.2))
      }
    }
    let mut total = 0
    let mut outside = 0
    let cells : Map[(Int, Int), Int] = {}
    let diff = FixedArray::make(aw * ah * 3, b'\x00')
    for y in 0..<ah {
      let base = y * aw * 3
      if y < bar_top || y >= ah - bar_bottom {
        for i in 0..<(aw * 3) {
          diff[base + i] = b'\xd0'
        }
        continue
      }
      let spans = row_boxes[y]
      for x in 0..<aw {
        let (r1, g1, b1) = ar.rgb(x, y)
        let (r2, g2, b2) = mr.rgb(x, y)
        let g = 128 + (r1 * 30 + g1 * 59 + b1 * 11) / 100 / 2
        let k = base + x * 3
        let in_box = spans.iter().any(fn(s) { s.0 <= x && x < s.1 })
        if in_box {
          diff[k] = (g / 2).to_byte()
          diff[k + 1] = g.to_byte()
          diff[k + 2] = (g / 2).to_byte()
        } else if (r1 - r2).abs() > 1 || (g1 - g2).abs() > 1 || (b1 - b2).abs() > 1 {
          total += 1
          let inside = rects.iter().any(fn(r) { r.0 <= x && x < r.2 && r.1 <= y && y < r.3 })
          if !inside {
            outside += 1
            let c = (x / cell, y / cell)
            cells[c] = cells.get(c).unwrap_or(0) + 1
          }
          diff[k] = b'\xe0'
          diff[k + 1] = b'\x20'
          diff[k + 2] = b'\x20'
        } else {
          diff[k] = g.to_byte()
          diff[k + 1] = g.to_byte()
          diff[k + 2] = g.to_byte()
        }
      }
      for r in rects {
        let (x0, y0, x1, y1) = r
        if y == y0 || y == y1 - 1 {
          for x in @cmp.maximum(0, x0)..<@cmp.minimum(aw, x1) {
            diff[base + x * 3] = b'\x20'
            diff[base + x * 3 + 1] = b'\x60'
            diff[base + x * 3 + 2] = b'\xe0'
          }
        } else if y0 < y && y < y1 - 1 {
          for x in [x0, x1 - 1] {
            if 0 <= x && x < aw {
              diff[base + x * 3] = b'\x20'
              diff[base + x * 3 + 1] = b'\x60'
              diff[base + x * 3 + 2] = b'\xe0'
            }
          }
        }
      }
    }
    // Android | mbui | the differences, at half size
    let hw = (aw + 1) / 2
    let pw = (hw + 8) * 3
    let ph = (ah + 1) / 2
    let half = FixedArray::make(pw * ph * 3, b'\xff')
    for hy in 0..<ph {
      let y = hy * 2
      for panel in 0..<3 {
        for hx in 0..<hw {
          let x = hx * 2
          let (r, g, b) = match panel {
            0 => ar.rgb(x, y)
            1 => mr.rgb(x, y)
            _ => {
              let k = (y * aw + x) * 3
              (diff[k].to_int(), diff[k + 1].to_int(), diff[k + 2].to_int())
            }
          }
          let k = (hy * pw + panel * (hw + 8) + hx) * 3
          half[k] = r.to_byte()
          half[k + 1] = g.to_byte()
          half[k + 2] = b.to_byte()
        }
      }
    }
    @sys.write_bytes(@sys.join(out, name + ".png"), png_of(pw, ph, half)) |> ignore
    let found = regions(cells)
    let where_ = found[:@cmp.minimum(8, found.length())]
      .iter()
      .map(fn(r) { "\{r.0}, \{r.1}, \{r.2}, \{r.3}: \{r.4}" })
      .collect()
      .join("; ")
    report.push("| \{name} | \{total} of \{aw * ah} | \{outside} (\{left}) | \{where_} |")
    if outside > left {
      failed.push(name)
    } else if outside < left {
      lower.push("\{name} \{outside} (was \{left})")
    }
    if a_texts is Some(at) && m_texts is Some(_) {
      let which = apart[:@cmp.minimum(8, apart.length())].iter().map(fn(p) { p.1 }).collect().join("; ")
      text_report.push("| \{name} | \{at.length()} | \{apart.length()} (\{texts_left}) | \{which} |")
      if apart.length() > texts_left {
        failed.push(name)
      } else if apart.length() < texts_left {
        lower.push("\{name} texts_left \{apart.length()} (was \{texts_left})")
      }
    }
  }
  let lines = report.copy()
  if text_report.length() > 2 {
    lines.push("")
    for t in text_report {
      lines.push(t)
    }
  }
  lines.push("")
  lines.push(
    "Android | mbui | Android greyed, the pixels that differ red, the regions allowed.json lets differ outlined blue, the words' boxes (compared by where they stand) green: \{out}/NAME.png.",
  )
  let text = lines.join("\n") + "\n"
  @sys.write_text(@sys.join(out, "report.md"), text) |> ignore
  @sys.out(text)
  if !lower.is_empty() {
    @sys.println_out(
      "android-ref: closer to Android's than allowed.json's `left` says, lower it: " + lower.join(", "),
    )
  }
  if !failed.is_empty() {
    let seen : Map[String, Bool] = {}
    let names_failed = []
    for f in failed {
      if !seen.contains(f) {
        seen[f] = true
        names_failed.push(f)
      }
    }
    names_failed.sort()
    @sys.println_out(
      "android-ref: \{names_failed.length()} of \{names.length()} screens differ from Android's by more than allowed.json allows (its regions, its `left`): " +
      names_failed.join(", "),
    )
    @sys.exit(1)
  }
}
