// The differential text test (scripts/textdiff.sh): every string of the corpus (src/text/testdata/corpus.txt, copied
// into corpus.mbt) in each of its fonts, drawn a page at a time by mbui's own path (the host shapes it into clusters,
// each cluster rasterized on its own into the atlas, laid out and placed here) and then by the platform's own text
// drawing (@host.ref_text) at the same places. Each page gives two pictures, PAGE-mbui.png and PAGE-native.png, and a
// line on the log for each string ("TXD {…}": where it is, the width each side advances), which
// scripts/textdiff.mjs compares.
//
// MBUI_TEXTDIFF_ONLY=<id prefix>: only those strings.

///|
priv struct Row {
  id : String
  text : String
  size : Double
  weight : Int
  style : Int
}

///|
priv struct State {
  mut page : Int
  mut frames : Int
  // rows of each page: the first and the end, made for the window's height
  starts : Array[Int]
  mut laid_h : Double
}

///|
let pad_x = 8.0

///|
let gap_y = 8.0

///|
/// \t, \u{XXXX} and \\ in the corpus's text.
fn unescape(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c == 92 && i + 1 < n {
      let d = s.code_unit_at(i + 1).to_int()
      if d == 116 {
        sb.write_char('\t')
        i = i + 2
        continue
      }
      if d == 92 {
        sb.write_char('\\')
        i = i + 2
        continue
      }
      if d == 117 && i + 2 < n && s.code_unit_at(i + 2).to_int() == 123 {
        let mut j = i + 3
        let mut v = 0
        while j < n && s.code_unit_at(j).to_int() != 125 {
          let h = s.code_unit_at(j).to_int()
          let x = if h >= 48 && h <= 57 {
            h - 48
          } else if h >= 65 && h <= 70 {
            h - 55
          } else if h >= 97 && h <= 102 {
            h - 87
          } else {
            0
          }
          v = v * 16 + x
          j = j + 1
        }
        sb.write_char(Int::unsafe_to_char(v))
        i = j + 1
        continue
      }
    }
    sb.write_char(Int::unsafe_to_char(c))
    i = i + 1
  }
  sb.to_string()
}

///|
fn corpus_rows(only : String) -> Array[Row] {
  let rows = []
  for line in corpus.split("\n") {
    let l = line.to_owned()
    if l.trim(chars=" ").length() == 0 || l.has_prefix("#") {
      continue
    }
    let parts = l.split(" | ").map(fn(p) { p.to_owned() }).to_array()
    if parts.length() < 3 {
      continue
    }
    let id = parts[0].trim(chars=" ").to_owned()
    if only != "" && !id.has_prefix(only) {
      continue
    }
    let variants = parts[1].trim(chars=" ").to_owned()
    // the text is all after the second separator, as written (it may hold " | " itself)
    let rest = []
    for k in 2..<parts.length() {
      rest.push(parts[k])
    }
    let text = unescape(rest.join(" | "))
    let v = if variants == "" { "S" } else { variants }
    for ch in v {
      let fonts : Array[(Double, Int, Int)] = match ch {
        'S' => [(11.0, 400, 0), (15.0, 400, 0), (20.0, 400, 0), (28.0, 400, 0)]
        'r' => [(15.0, 400, 0)]
        'b' => [(15.0, 700, 0)]
        'B' => [(28.0, 700, 0)]
        'i' => [(15.0, 400, @host.style_italic)]
        'm' => [(15.0, 400, @host.style_mono)]
        _ => []
      }
      for f in fonts {
        rows.push({ id, text, size: f.0, weight: f.1, style: f.2 })
      }
    }
  }
  rows
}

///|
/// The font's line height and ascent, as mbui's text puts its baseline in a line of its own height (Ctx::text) or a
/// paragraph's (Ctx::rich: the larger of the paragraph's font's and the run's).
fn line_of(r : Row) -> (Double, Double) {
  let o = FixedArray::make(4, 0.0)
  @host.font_metrics(r.size, r.weight, 0, o)
  let lh = o[2]
  let asc0 = (lh - o[0] - o[1]) / 2.0 + o[0]
  if r.style == 0 {
    (lh, asc0)
  } else {
    @host.font_metrics(r.size, r.weight, r.style, o)
    let asc = (lh - o[0] - o[1]) / 2.0 + o[0]
    let desc = dmax(lh - asc0, lh - asc)
    let a = dmax(asc0, asc)
    (a + desc, a)
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn row_h(r : Row) -> Double {
  let (lh, _) = line_of(r)
  (lh + gap_y).ceil()
}

///|
fn paginate(rows : Array[Row], h : Double) -> Array[Int] {
  let starts = [0]
  let mut y = gap_y
  for i, r in rows {
    let rh = row_h(r)
    if y + rh > h && i > starts[starts.length() - 1] {
      starts.push(i)
      y = gap_y
    }
    y = y + rh
  }
  starts.push(rows.length())
  starts
}

///|
fn json_str(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    let v = c.to_int()
    if c == '"' || c == '\\' {
      sb.write_char('\\')
      sb.write_char(c)
    } else if v < 32 || v > 126 {
      if v > 0xFFFF {
        let u = v - 0x10000
        sb.write_string(hex4(0xD800 + (u >> 10)))
        sb.write_string(hex4(0xDC00 + (u & 0x3FF)))
      } else {
        sb.write_string(hex4(v))
      }
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
fn hex4(v : Int) -> String {
  let d = "0123456789abcdef"
  let sb = StringBuilder()
  sb.write_string("\\u")
  for k in [12, 8, 4, 0] {
    sb.write_char(d.code_unit_at((v >> k) & 15).to_int() |> Int::unsafe_to_char)
  }
  sb.to_string()
}

///|
fn num(x : Double) -> String {
  let r = (x * 1000.0).round() / 1000.0
  r.to_string()
}

///|
/// The rows of a page drawn by mbui: each in a box of its own height, the text at its top left.
fn draw_page(c : @ui.Ctx, rows : Array[Row], a : Int, b : Int) -> Unit {
  c.column(pady=gap_y, bg=0xFFFFFFFFL, w=Fill(1.0), h=Fill(1.0), fn() {
    for i in a..<b {
      let r = rows[i]
      c.box(h=Px(row_h(r)), pl=pad_x, align=AStart, fn() {
        if r.style == 0 {
          c.text(r.text, size=r.size, weight=r.weight, color=0x000000FFL, wrap=false)
          |> ignore
        } else {
          c.rich(
            [
              @ui.span(
                r.text,
                italic=(r.style & @host.style_italic) != 0,
                mono=(r.style & @host.style_mono) != 0,
              ),
            ],
            size=r.size,
            weight=r.weight,
            color=0x000000FFL,
            wrap=false,
          )
          |> ignore
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The same rows drawn by the platform, and a line on the log for each.
fn draw_native(c : @ui.Ctx, rows : Array[Row], page : Int, a : Int, b : Int) -> Unit {
  let sc = c.scale
  @host.ref_begin(c.width, c.height, sc, 0xFFFFFF)
  let out = FixedArray::make(5, 0.0)
  let mut y = gap_y
  for i in a..<b {
    let r = rows[i]
    let (_, asc) = line_of(r)
    let rh = row_h(r)
    // mbui puts each glyph's bitmap on whole pixels, its baseline on a pixel row
    let base = ((y + asc) * sc).round() / sc
    @host.ref_text(r.text, r.size, r.weight, r.style, pad_x, base, 0x000000, out)
    let mine = @ui.text_advance(r.text, size=r.size, weight=r.weight, style=r.style)
    @host.log(
      "TXD {\"page\":\{page},\"row\":\{i},\"id\":\{json_str(r.id)},\"text\":\{json_str(r.text)},\"size\":\{num(r.size)},\"weight\":\{r.weight},\"style\":\{r.style},\"top\":\{num(y)},\"h\":\{num(rh)},\"x\":\{num(pad_x)},\"base\":\{num(base)},\"scale\":\{num(sc)},\"mbui\":\{num(mine)},\"native\":\{num(out[0])},\"ink\":[\{num(out[1])},\{num(out[2])},\{num(out[3])},\{num(out[4])}]}",
    )
    y = y + rh
  }
  @host.ref_end("p\{page}-native") |> ignore
}

///|
fn view(c : @ui.Ctx, rows : Array[Row], st : State) -> Unit {
  c.request_frame()
  if st.starts.length() == 0 || st.laid_h != c.height {
    // the window's height known (and settled): the pages made for it, started again
    st.starts.clear()
    for s in paginate(rows, c.height - gap_y) {
      st.starts.push(s)
    }
    st.laid_h = c.height
    st.page = 0
    st.frames = 0
    @host.log(
      "TXD start {\"rows\":\{rows.length()},\"pages\":\{st.starts.length() - 1},\"w\":\{num(c.width)},\"h\":\{num(c.height)},\"scale\":\{num(c.scale)},\"platform\":\{@host.platform()}}",
    )
  }
  let pages = st.starts.length() - 1
  if st.page >= pages {
    @host.log("TXD done")
    @host.exit(0)
    return
  }
  let a = st.starts[st.page]
  let b = st.starts[st.page + 1]
  draw_page(c, rows, a, b)
  st.frames = st.frames + 1
  // a few frames for the window and the atlas to settle, then both pictures of the page (the window's as drawn last,
  // or next: the same page either way)
  if st.frames == 8 {
    @host.ref_frame("p\{st.page}-mbui") |> ignore
    draw_native(c, rows, st.page, a, b)
  }
  if st.frames == 12 {
    st.page = st.page + 1
    st.frames = 0
  }
}

///|
fn main {
  let rows = corpus_rows(@ui.env("MBUI_TEXTDIFF_ONLY"))
  let st = { page: 0, frames: 0, starts: [], laid_h: -1.0 }
  @ui.run("textdiff", fn(c) {
    // drawn in the colours Core Text's side is (iOS's)
    c.set_theme(@ui.Theme::ios_light())
    view(c, rows, st)
  })
}
