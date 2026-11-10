// A widget drawn by mbui itself: an HTML fragment (mbui/html read and styled it into boxes) made as nodes of the
// window's tree, each box one node laid out as CSS lays it out (View::css_laid), drawn as its style says (its ground,
// corners, edge, shadow, opacity), its words in pieces as its elements style them (View::words_runs), what sits in a
// line whole in a row that wraps, a grid's tracks as rows of cells, a table's columns shared by how much each holds,
// an <svg> as a picture (mbui's SVG renderer). It is made again whole as what it is worked out of changes (its HTML,
// the theme's tokens, the room it has): a widget's code never changes once sent, so that is a theme or a width.
// What the app draws its own way (an element of its vocabulary, an icon) is asked of it first (Hooks::element).

///|
/// What the app says of how a widget is drawn: the defaults sheet (what an element with no CSS of its own looks like:
/// the app's), the theme's tokens and size of words, whether dark, whether motion is reduced; elements it draws
/// itself (`element`: whether it drew element `i` in the node given); where a link leads.
pub(all) struct Hooks {
  defaults : @html.Sheet
  tokens : () -> Array[(String, String)]
  size : () -> Double
  dark : () -> Bool
  element : (@view.View, @html.Styled, @html.Box) -> Bool
  /// an element of the app's own vocabulary as the HTML it stands for at the widget's width (a chart), read in its place
  expand : (@html.Elem, Double) -> String?
  on_link : (String) -> Unit
}

///|
/// The widget `html` (as it changes) drawn in `parent`, as wide as it is given, as tall as it comes to.
#callsite(autofill(loc))
pub fn widget_node(parent : @view.View, html : () -> String, hooks : Hooks, loc~ : SourceLoc) -> @view.View {
  // what using it changed of its elements' attributes (a tab chosen, a box ticked), by their place: kept while it is
  // shown, its HTML the same
  let changed : Map[Int, Array[(String, String?)]] = {}
  let version = @signals.signal(0)
  parent.by_room(loc~, fn(held, room) {
    // what it is made of: made again whole as any of it changes (a width to the point)
    let key = fn() -> (String, Int, Bool, Double, Array[(String, String)], Int) {
      (html(), room.width().round().to_int(), (hooks.dark)(), (hooks.size)(), (hooks.tokens)(), version.get())
    }
    let shown = Ref("")
    held.pick(key, fn(p, k) {
      let (h, w, dark, size, tokens, _) = k
      if shown.val != h {
        changed.clear()
        shown.val = h
      }
      let env : @html.Env = { width: w.to_double(), dark, reduced_motion: false, root_size: size, tokens }
      let styled = @html.style_widget(h, hooks.defaults, env, fn(_, _) { false }, expand=fn(e) { (hooks.expand)(e, w.to_double()) }, changed~)
      let b : Builder = { styled, hooks, env, changed, version }
      let root = p.box(fn(col) {
        col.css_laid(Is({ ..@view.CssLaid::block(), padding: lens(styled.root.padding) })) |> ignore
        // (its root's ground is what it is drawn on: none of its own, as a widget on a bubble)
        decorate(col, { ..styled.root, background: 0L })
        b.flow(col, styled.boxes)
      })
      ignore(root)
    })
  })
}

///|
priv struct Builder {
  styled : @html.Styled
  hooks : Hooks
  env : @html.Env
  changed : Map[Int, Array[(String, String?)]]
  version : @signals.Signal[Int]
}

// ── lengths and looks ────────────────────────────────────────────────

///|
fn dim(l : @html.Len) -> @flex.Dim {
  match l {
    Auto => Auto
    Of(p, 0.0) => Pt(p)
    Of(0.0, f) => Pct(f * 100.0)
    // points and a share: as points (a widget's calc of both is rare; its share taken as of none)
    Of(p, _) => Pt(p)
  }
}

///|
fn lens(ls : Array[@html.Len]) -> (@flex.Dim, @flex.Dim, @flex.Dim, @flex.Dim) {
  // CSS's top, right, bottom, left as left, top, right, bottom
  (dim(ls[3]), dim(ls[0]), dim(ls[1]), dim(ls[2]))
}

///|
fn align(a : String, normal : @flex.Align) -> @flex.Align {
  match a {
    "start" => FlexStart
    "end" => FlexEnd
    "center" => Center
    "stretch" => Stretch
    "baseline" => FlexStart
    "space-between" => SpaceBetween
    "space-around" => SpaceAround
    "space-evenly" => SpaceEvenly
    _ => normal
  }
}

///|
fn gap_of(l : @html.Len) -> Double {
  match l {
    Of(p, _) => p
    Auto => 0.0
  }
}

///|
/// A box's layout as its style says, its own kind deciding which way it lays out what it holds.
fn laid(st : @html.Style, direction : @flex.FlexDirection) -> @view.CssLaid {
  let bw = st.border_width
  let row = direction == Row || direction == RowReverse
  {
    direction,
    wrap: match st.flex_wrap {
      "wrap" => Wrap
      "wrap-reverse" => WrapReverse
      _ => NoWrap
    },
    justify: align(st.justify, FlexStart),
    align_items: align(st.align_items, Stretch),
    align_self: align(st.align_self, Auto),
    align_content: align(st.align_content, FlexStart),
    absolute: st.position == "absolute",
    inset: (dim(st.left), dim(st.top), dim(st.right), dim(st.bottom)),
    margin: lens(st.margin),
    padding: lens(st.padding),
    border: (bw[3], bw[0], bw[1], bw[2]),
    width: dim(st.width),
    height: dim(st.height),
    min_width: dim(st.min_width),
    min_height: dim(st.min_height),
    max_width: dim(st.max_width),
    max_height: dim(st.max_height),
    row_gap: gap_of(if row { st.row_gap } else { st.row_gap }),
    column_gap: gap_of(st.column_gap),
    grow: st.grow,
    shrink: st.shrink,
    basis: dim(st.basis),
    aspect: st.aspect,
    border_box: st.box_sizing == "border-box",
    hidden: st.overflow != "visible",
  }
}

///|
fn flex_direction(st : @html.Style) -> @flex.FlexDirection {
  match st.flex_direction {
    "column" => Column
    "column-reverse" => ColumnReverse
    "row-reverse" => RowReverse
    _ => Row
  }
}

///|
/// How round a corner is in points (a share of its size taken as a pill's, the most a corner comes to).
fn corner(l : @html.Len) -> Double {
  match l {
    Of(p, 0.0) => p
    Of(_, f) if f >= 0.25 => 9999.0
    Of(p, f) => p + f * 40.0
    Auto => 0.0
  }
}

///|
/// What a box draws: its ground, corners, edge (borders all alike; others drawn as a side's line: side_lines), its
/// shadow, how opaque, whether it shows, whether it cuts what it holds.
fn decorate(v : @view.View, st : @html.Style) -> Unit {
  if st.background != 0L {
    v.ground(Is(st.background)) |> ignore
  }
  let r = st.radius.map(corner)
  if r[0] == r[1] && r[1] == r[2] && r[2] == r[3] {
    if r[0] > 0.0 {
      v.radius(Is(r[0])) |> ignore
    }
  } else {
    v.corners(Is(Some((r[0], r[1], r[2], r[3])))) |> ignore
  }
  let bw = st.border_width
  let bc = st.border_color
  if bw[0] > 0.0 && bw.iter().all(fn(w) { w == bw[0] }) && bc.iter().all(fn(c) { c == bc[0] }) {
    if @html.alpha_of(bc[0]) > 0 {
      v.edge(Is((bw[0], bc[0]))) |> ignore
    }
  } else {
    side_lines(v, st)
  }
  let (sx, sy, blur, _, sc, inset) = st.shadow
  if blur >= 0.0 && @html.alpha_of(sc) > 0 {
    if inset {
      // an inset ring (a box-shadow drawn as an outline inside): its edge
      if sx == 0.0 && sy == 0.0 && blur == 0.0 {
        v.edge(Is((st.shadow.3, sc))) |> ignore
      }
    } else {
      v.shadow(Is((dmax(blur, 0.5), sy, sc))) |> ignore
    }
  }
  if st.opacity < 1.0 {
    v.alpha(Is(st.opacity)) |> ignore
  }
  if !st.visible {
    v.hides(Is(true)) |> ignore
  }
  if st.overflow != "visible" {
    v.clips(Is(true)) |> ignore
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
/// A box's borders where they are not all alike: each side drawn as a line of its width over the border's room.
fn side_lines(v : @view.View, st : @html.Style) -> Unit {
  let bw = st.border_width
  let bc = st.border_color
  for k in 0..<4 {
    let w = bw[k]
    if w <= 0.0 || @html.alpha_of(bc[k]) == 0 {
      continue
    }
    let c = bc[k]
    v.box(fn(line) {
      // (an absolute box's insets are from inside the borders: out by the borders to lie on them)
      let (l, t, rr, b) = (-bw[3], -bw[0], -bw[1], -bw[2])
      let inset : (@flex.Dim, @flex.Dim, @flex.Dim, @flex.Dim) = match k {
        0 => (Pt(l), Pt(t), Pt(rr), Auto)
        1 => (Auto, Pt(t), Pt(rr), Pt(b))
        2 => (Pt(l), Auto, Pt(rr), Pt(b))
        _ => (Pt(l), Pt(t), Auto, Pt(b))
      }
      let size = if k == 0 || k == 2 {
        { ..@view.CssLaid::block(), absolute: true, inset, height: Pt(w) }
      } else {
        { ..@view.CssLaid::block(), absolute: true, inset, width: Pt(w) }
      }
      line.css_laid(Is(size)).ground(Is(c)) |> ignore
    })
    |> ignore
  }
}

// ── boxes ────────────────────────────────────────────────────────────

///|
/// Blocks one under another in `col` (a flow): margins between two the larger of the two (CSS's collapsing).
fn Builder::flow(self : Builder, col : @view.View, boxes : Array[@html.Box]) -> Unit {
  let mut before = 0.0
  for i, b in boxes {
    let st = b.style
    let absolute = st.position == "absolute"
    let top = match st.margin[0] {
      Of(p, 0.0) => p
      _ => 0.0
    }
    // the larger of the margins between it and the one before, said as its own top
    let collapsed = if i == 0 || absolute { top } else if top >= 0.0 && before >= 0.0 { dmax(top, before) - before } else { top }
    self.box(col, b, top=Some(collapsed))
    if !absolute {
      before = match st.margin[2] {
        Of(p, 0.0) => p
        _ => 0.0
      }
    }
  }
}

///|
/// Box `b` in `p`: its node, laid out and drawn as its kind and style say. `top`: its top margin where its flow
/// collapsed it.
fn Builder::box(self : Builder, p : @view.View, b : @html.Box, top? : Double? = None) -> Unit {
  let st = b.style
  // the app's own first
  if b.el >= 0 && (self.hooks.element)(p, self.styled, b) {
    return
  }
  match b.kind {
    Line(pieces) => self.line(p, b, pieces)
    _ =>
      p.box(fn(v) {
        let direction : @flex.FlexDirection = match b.kind {
          Flex => flex_direction(st)
          Item(_) | TableRow => Row
          _ => Column
        }
        let l = laid(st, direction)
        let l = match top {
          Some(t) => { ..l, margin: (l.margin.0, Pt(t), l.margin.2, l.margin.3) }
          None => l
        }
        // a flow's blocks stretch across it; what is inline-level in a flow keeps its own width
        let l = match b.kind {
          Flow | Item(_) | TableCell | Table => if st.display.has_prefix("inline") { l } else { { ..l, align_items: Stretch } }
          _ => l
        }
        // (a grid's own alignment is of its cells: the rows it is made of stretch across it)
        let l = if b.kind is Grid { { ..l, align_items: Stretch, justify: FlexStart } } else { l }
        v.css_laid(Is(l)) |> ignore
        decorate(v, st)
        self.behave(v, b)
        match b.kind {
          Flow | TableCell => self.flow(v, b.kids)
          Flex => for k in b.kids { self.box(v, k) }
          Grid => self.grid(v, b)
          Table => self.table(v, b)
          TableRow => for k in b.kids { self.box(v, k) }
          Item(marker) => {
            if marker != "" {
              v.box(fn(m) {
                m.css_laid(Is({ ..@view.CssLaid::block(), width: Pt(st.font_size * 1.3), shrink: 0.0, padding: (Pt(0.0), Pt(0.0), Pt(st.font_size * 0.3), Pt(0.0)) }))
                .words(Is(marker), ink=st.color, look=words_look(st))
                |> ignore
              })
              |> ignore
            }
            v.box(fn(c) {
              c.css_laid(Is({ ..@view.CssLaid::block(), grow: 1.0, shrink: 1.0, basis: Pt(0.0) })) |> ignore
              self.flow(c, b.kids)
            })
            |> ignore
          }
          Svg(markup) => self.svg(v, b, markup)
          Img(src, alt) => self.img(v, b, src, alt)
          Control(what, words) => {
            self.control(v, b, what, words)
            self.behave_control(v, b, what)
          }
          Line(_) => ()
        }
      })
      |> ignore
  }
}

///|
/// How a style's words are set: its size, weight, line, whether they wrap.
fn words_look(st : @html.Style) -> @view.WordsLook {
  let size = st.font_size
  let line = if st.line_height > 0.0 { st.line_height } else { (size * 1.45).round() }
  {
    size,
    weight: st.font_weight,
    line,
    wrap: st.white_space != "nowrap" && st.white_space != "pre",
    tracking: if st.letter_spacing != 0.0 { @view.Points(st.letter_spacing) } else { @view.letters_own },
    balance: false,
  }
}

///|
/// A line's pieces: one node of words where they are all words, else a row that wraps of its words and what sits in
/// it whole.
fn Builder::line(self : Builder, p : @view.View, b : @html.Box, pieces : Array[@html.Inline]) -> Unit {
  let st = b.style
  let atoms = pieces.iter().any(fn(x) { x is Atom(_) })
  if !atoms {
    self.words(p, st, pieces)
    return
  }
  p.box(fn(row) {
    let justify : @flex.Align = match st.text_align {
      "center" => Center
      "end" => FlexEnd
      _ => FlexStart
    }
    row.css_laid(Is({ ..@view.CssLaid::block(), direction: Row, wrap: Wrap, align_items: Center, justify })) |> ignore
    let run = []
    let close = fn() {
      if !run.is_empty() {
        let words = run.copy()
        run.clear()
        self.words(row, st, words, shrinks=true)
      }
    }
    for x in pieces {
      match x {
        Atom(a) => {
          close()
          self.box(row, a)
        }
        Break => {
          close()
          // a break: the rest on a line of its own
          row.box(fn(br) { br.css_laid(Is({ ..@view.CssLaid::block(), width: Pct(100.0), height: Pt(0.0) })) |> ignore }) |> ignore
        }
        w => run.push(w)
      }
    }
    close()
  })
  |> ignore
}

///|
/// Words in pieces (a line's, or a run of one between what sits in it whole) in one node, set as `st` (what holds
/// them) says, each piece as its own element's style differs from it.
fn Builder::words(self : Builder, p : @view.View, st : @html.Style, pieces : Array[@html.Inline], shrinks? : Bool = false) -> Unit {
  let runs : Array[@text.Run] = []
  let text = StringBuilder()
  for x in pieces {
    match x {
      Words(t, s, link, _) => {
        let r = @text.span(
          t,
          weight=if s.font_weight != st.font_weight { s.font_weight } else { 0 },
          italic=s.italic,
          mono=s.mono,
          serif=s.serif,
          scale=if st.font_size > 0.0 { s.font_size / st.font_size } else { 1.0 },
          color=if s.color != st.color || link != "" { s.color } else { 0L },
          bg=if s.background != st.background && s.background != 0L { s.background } else { 0L },
          strike=s.strike,
          underline=s.underline,
          link~,
        )
        runs.push(r)
        text.write_string(t)
      }
      Break => {
        runs.push(@text.span("\n"))
        text.write_string("\n")
      }
      Atom(_) => ()
    }
  }
  ignore(text)
  if runs.is_empty() {
    return
  }
  let look = words_look(st)
  p.box(fn(w) {
    let l = { ..@view.CssLaid::block(), shrink: if shrinks { 1.0 } else { 1.0 }, align_self: if st.text_align == "end" { FlexEnd } else { Auto } }
    w.css_laid(Is(l)) |> ignore
    let plain = runs.iter().all(fn(r) { r == @text.span(r.text) })
    if plain {
      let all = StringBuilder()
      for r in runs {
        all.write_string(r.text)
      }
      w.words(Is(all.to_string()), ink=st.color, look~) |> ignore
    } else {
      w.words_runs(Is(runs), ink=st.color, look~)
      .runs_look(Is({ ..@view.runs_plain, link: st.color, code_ground: 0L, code_ink: 0L, code_scale: 1.0 }))
      |> ignore
      if runs.iter().any(fn(r) { r.link != "" }) {
        @ui.runs_links(w, fn() { runs }, self.hooks.on_link) |> ignore
      }
    }
    if st.text_align == "center" {
      w.words_centered(Is(true)) |> ignore
    }
    if st.ellipsis {
      w.allow_ellipsis(Is(true)) |> ignore
    }
  })
  |> ignore
}

// ── grids and tables ─────────────────────────────────────────────────

///|
/// A grid track: so many fr, or so many points, or as wide as what is in it.
priv enum Track {
  Fr(Double)
  Fixed(Double)
  Content
}

///|
/// Its columns' tracks at width `w`, `gap` apart.
fn tracks_of(template : String, w : Double, gap : Double, b : @html.Basis) -> Array[Track] {
  let out = []
  let one = fn(t : String) -> Track {
    let t = t.trim().to_string()
    if t.has_suffix("fr") {
      match @html.parse_number(t.view(end_offset=t.length() - 2).to_owned()) {
        Some(x) => Fr(x)
        None => Fr(1.0)
      }
    } else if t.has_prefix("minmax(") && t.has_suffix(")") {
      let args = @html.split_top(t.view(start_offset=7, end_offset=t.length() - 1).to_owned(), ','.to_int())
      if args.length() == 2 && args[1].has_suffix("fr") {
        Fr(@html.parse_number(args[1].view(end_offset=args[1].length() - 2).to_owned()).unwrap_or(1.0))
      } else {
        match @html.parse_len(args.get(1).unwrap_or(""), b) {
          Some(Of(p, f)) => Fixed(p + f * w)
          _ => Content
        }
      }
    } else {
      match @html.parse_len(t, b) {
        Some(Of(p, f)) => Fixed(p + f * w)
        _ => Content
      }
    }
  }
  for word in @html.split_words(template) {
    if word.has_prefix("repeat(") && word.has_suffix(")") {
      let args = @html.split_top(word.view(start_offset=7, end_offset=word.length() - 1).to_owned(), ','.to_int())
      if args.length() != 2 {
        continue
      }
      let what = @html.split_words(args[1])
      let count = match args[0] {
        "auto-fit" | "auto-fill" => {
          // as many as fit at their least: minmax's first, or the track's own
          let least = {
            let t = what.get(0).unwrap_or("")
            let at_least = if t.has_prefix("minmax(") {
              @html.split_top(t.view(start_offset=7, end_offset=t.length() - 1).to_owned(), ','.to_int()).get(0).unwrap_or(t)
            } else {
              t
            }
            match @html.parse_len(at_least, b) {
              Some(Of(p, f)) => p + f * w
              _ => 160.0
            }
          }
          let n = ((w + gap) / (dmax(least, 1.0) + gap)).floor().to_int()
          if n < 1 {
            1
          } else {
            n
          }
        }
        n => @html.parse_int(n).unwrap_or(1)
      }
      for _ in 0..<count {
        for t in what {
          out.push(one(t))
        }
      }
    } else {
      out.push(one(word))
    }
  }
  if out.is_empty() {
    [Fr(1.0)]
  } else {
    out
  }
}

///|
/// How many columns an item takes (grid-column: span n, or 1 / -1 for all of them).
fn span_of(g : String, columns : Int) -> Int {
  let t = g.trim().to_string()
  if t.has_prefix("span ") {
    return @html.parse_int(t.view(start_offset=5).trim().to_string()).unwrap_or(1)
  }
  match t.find("/") {
    Some(at) => {
      let a = @html.parse_int(t.view(end_offset=at).trim().to_string()).unwrap_or(1)
      let rest = t.view(start_offset=at + 1).trim().to_string()
      if rest.has_prefix("span ") {
        @html.parse_int(rest.view(start_offset=5).trim().to_string()).unwrap_or(1)
      } else {
        let z = @html.parse_int(rest).unwrap_or(a + 1)
        let end = if z < 0 { columns + 2 + z } else { z }
        if end > a {
          end - a
        } else {
          1
        }
      }
    }
    None => 1
  }
}

///|
/// A grid: its items put in rows of its columns (spanning as they say), each row a row of cells of its tracks.
fn Builder::grid(self : Builder, v : @view.View, b : @html.Box) -> Unit {
  let st = b.style
  let bb : @html.Basis = { em: st.font_size, rem: self.env.root_size, vw: self.env.width }
  let make = fn(at : @view.View, w : Double) {
    let cg = gap_of(st.column_gap)
    let rg = gap_of(st.row_gap)
    let tracks = tracks_of(st.grid_columns, w, cg, bb)
    let n = tracks.length()
    // the items in rows
    let rows : Array[Array[(@html.Box, Int, Int)]] = []
    let mut row : Array[(@html.Box, Int, Int)] = []
    let mut col = 0
    for k in b.kids {
      if k.style.position == "absolute" {
        continue
      }
      let span = {
        let s = span_of(k.style.grid_column, n)
        if s > n {
          n
        } else if s < 1 {
          1
        } else {
          s
        }
      }
      if col + span > n {
        rows.push(row)
        row = []
        col = 0
      }
      row.push((k, col, span))
      col += span
    }
    if !row.is_empty() {
      rows.push(row)
    }
    at.css_laid(Is({ ..@view.CssLaid::block(), row_gap: rg })) |> ignore
    for r in rows {
      at.box(fn(line) {
        line.css_laid(Is({ ..@view.CssLaid::block(), direction: Row, column_gap: cg, align_items: align(st.align_items, Stretch) })) |> ignore
        let mut c = 0
        for item in r {
          let (k, start, span) = item
          // empty tracks before it
          while c < start {
            track_cell(line, tracks[c], fn(_) {  })
            c += 1
          }
          // its tracks together
          let mut fr = 0.0
          let mut fixed = 0.0
          for t in tracks[start:start + span] {
            match t {
              Fr(x) => fr += x
              Fixed(x) => fixed += x
              Content => ()
            }
          }
          fixed += cg * (span - 1).to_double()
          let cell_track : Track = if fr > 0.0 { Fr(fr) } else if fixed > 0.0 { Fixed(fixed) } else { Content }
          track_cell(line, cell_track, fn(cell) {
            cell.css_laid(Is({ ..cell_laid(cell_track), align_items: align(st.justify_items, Stretch) })) |> ignore
            self.box(cell, k)
          })
          c = start + span
        }
        while c < n {
          track_cell(line, tracks[c], fn(_) {  })
          c += 1
        }
      })
      |> ignore
    }
  }
  if st.grid_columns.contains("auto-fit") || st.grid_columns.contains("auto-fill") || st.grid_columns.contains("%") {
    v.by_room(fn(held, room) {
      held.pick(fn() { room.width().round() }, fn(p, w) { p.box(fn(at) { make(at, w) }) |> ignore })
    })
    |> ignore
  } else {
    v.box(fn(at) { make(at, self.env.width) }) |> ignore
  }
}

///|
fn cell_laid(t : Track) -> @view.CssLaid {
  match t {
    Fr(x) => { ..@view.CssLaid::block(), grow: x, shrink: 1.0, basis: Pt(0.0), min_width: Pt(0.0) }
    Fixed(x) => { ..@view.CssLaid::block(), width: Pt(x), shrink: 0.0 }
    Content => { ..@view.CssLaid::block(), shrink: 0.0 }
  }
}

///|
fn track_cell(line : @view.View, t : Track, fill : (@view.View) -> Unit) -> Unit {
  line.box(fn(cell) {
    cell.css_laid(Is(cell_laid(t))) |> ignore
    fill(cell)
  })
  |> ignore
}

///|
/// How much a box holds to read, for a table's columns: its words' length.
fn words_in(b : @html.Box) -> Int {
  let mut n = 0
  match b.kind {
    Line(ps) =>
      for x in ps {
        match x {
          Words(t, _, _, _) => n += t.length()
          Atom(a) => n += words_in(a) + 2
          Break => ()
        }
      }
    Control(_, w) => n += w.length() + 4
    Svg(_) | Img(_, _) => n += 8
    _ => ()
  }
  for k in b.kids {
    n += words_in(k)
  }
  n
}

///|
/// A table: its rows one under another, its columns shared by how much the most of each holds (between 3 and 40
/// letters' worth), each cell as its row's track.
fn Builder::table(self : Builder, v : @view.View, b : @html.Box) -> Unit {
  let mut columns = 0
  for r in b.kids {
    if r.kind is TableRow {
      let mut c = 0
      for cell in r.kids {
        c += span_cell(cell)
      }
      if c > columns {
        columns = c
      }
    }
  }
  let weights = Array::make(columns, 3)
  for r in b.kids {
    if r.kind is TableRow {
      let mut c = 0
      for cell in r.kids {
        let span = span_cell(cell)
        if span == 1 && c < columns {
          let n = words_in(cell)
          let n = if n > 40 { 40 } else if n < 3 { 3 } else { n }
          if n > weights[c] {
            weights[c] = n
          }
        }
        c += span
      }
    }
  }
  for r in b.kids {
    match r.kind {
      TableRow =>
        v.box(fn(row) {
          let l = laid(r.style, Row)
          row.css_laid(Is({ ..l, align_items: Stretch })) |> ignore
          decorate(row, r.style)
          let mut c = 0
          for cell in r.kids {
            let span = span_cell(cell)
            let mut w = 0
            for k in c..<(c + span) {
              if k < columns {
                w += weights[k]
              }
            }
            c += span
            row.box(fn(td) {
              let l = laid(cell.style, Column)
              td.css_laid(Is({ ..l, grow: w.to_double(), shrink: 1.0, basis: Pt(0.0), min_width: Pt(0.0) })) |> ignore
              decorate(td, cell.style)
              self.flow(td, cell.kids)
            })
            |> ignore
          }
        })
        |> ignore
      _ => self.box(v, r)
    }
  }
}

///|
fn span_cell(cell : @html.Box) -> Int {
  ignore(cell)
  1
}

// ── what it holds whole ──────────────────────────────────────────────

///|
/// An <svg> as a picture: as wide as its CSS or its own width says (all the room where neither does), as tall as its
/// proportions make that.
fn Builder::svg(self : Builder, v : @view.View, b : @html.Box, markup : String) -> Unit {
  ignore(self)
  svg_node(v, markup, b.style)
}

///|
/// SVG `markup` as a picture in `v` (laid out as `st` says: as wide as its CSS or its own width says, all the room where
/// neither does, as tall as its proportions make that), kept by what it is.
pub fn svg_node(v : @view.View, markup : String, st : @html.Style) -> Unit {
  let bytes = @utf8.encode(markup)
  let key = "mem:widget/" + @zip.sha256(bytes).view(end_offset=24).to_owned()
  @ui.add_image(key, bytes)
  let (iw, ih) = match @svg.svg_size(markup, @svg.Options::default()) {
    Some((w, h)) => (w.to_double(), h.to_double())
    None => (300.0, 150.0)
  }
  let aspect = if ih > 0.0 { iw / ih } else { 2.0 }
  let width : @flex.Dim = match st.width {
    Auto => if markup.contains(" width=\"") { Pt(iw) } else { Pct(100.0) }
    w => dim(w)
  }
  let height : @flex.Dim = match st.height {
    Auto => Auto
    h => dim(h)
  }
  let l = laid(st, Column)
  v.css_laid(Is({ ..l, width, height, max_width: if l.max_width == Auto { Pct(100.0) } else { l.max_width }, aspect: if height == Auto { aspect } else { 0.0 }, shrink: 0.0 }))
  .image(Is(Some((key, "", 4096))))
  .image_contains(Is(true))
  |> ignore
}

///|
/// An image from a data: URL (a widget loads none from the network).
fn Builder::img(self : Builder, v : @view.View, b : @html.Box, src : String, alt : String) -> Unit {
  let st = b.style
  ignore(alt)
  match data_url(src) {
    Some(bytes) => {
      let key = "mem:widget/" + @zip.sha256(bytes).view(end_offset=24).to_owned()
      @ui.add_image(key, bytes)
      let l = laid(st, Column)
      v.css_laid(Is({ ..l, width: if l.width == Auto { Pct(100.0) } else { l.width }, max_width: Pct(100.0) }))
      .image(Is(Some((key, "", 4096))))
      .image_contains(Is(true))
      |> ignore
    }
    None => ()
  }
}

///|
/// The bytes of a data: URL (base64 or percent-encoded).
fn data_url(src : String) -> Bytes? {
  guard src.has_prefix("data:") else { return None }
  match src.find(",") {
    None => None
    Some(at) => {
      let head = src.view(start_offset=5, end_offset=at).to_owned()
      let body = src.view(start_offset=at + 1).to_owned()
      if head.has_suffix(";base64") {
        base64(body)
      } else {
        Some(@utf8.encode(percent_decoded(body)))
      }
    }
  }
}

///|
fn percent_decoded(s : String) -> String {
  if !s.contains("%") {
    return s
  }
  let bytes = []
  let raw = @utf8.encode(s)
  let mut i = 0
  while i < raw.length() {
    let c = raw[i].to_int()
    if c == '%'.to_int() && i + 2 < raw.length() {
      let h = hex(raw[i + 1].to_int())
      let l = hex(raw[i + 2].to_int())
      if h >= 0 && l >= 0 {
        bytes.push((h * 16 + l).to_byte())
        i += 3
        continue
      }
    }
    bytes.push(raw[i])
    i += 1
  }
  @utf8.decode_lossy(Bytes::from_array(bytes))
}

///|
fn hex(c : Int) -> Int {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    c - 'a'.to_int() + 10
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn base64(s : String) -> Bytes? {
  let out = []
  let mut acc = 0
  let mut bits = 0
  for c in s {
    let v = if c >= 'A' && c <= 'Z' {
      c.to_int() - 'A'.to_int()
    } else if c >= 'a' && c <= 'z' {
      c.to_int() - 'a'.to_int() + 26
    } else if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int() + 52
    } else if c == '+' || c == '-' {
      62
    } else if c == '/' || c == '_' {
      63
    } else if c == '=' || c == ' ' || c == '\n' || c == '\r' {
      continue
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

///|
/// A control as it is drawn at rest: a box (a check, a radio's circle, a range's track and its thumb, a progress's
/// fill, a field with its words), its look as its CSS says where it says one.
fn Builder::control(self : Builder, v : @view.View, b : @html.Box, what : String, words : String) -> Unit {
  let st = b.style
  let el = if b.el >= 0 { Some(self.styled.tree.els[b.el].elem) } else { None }
  let checked = el.map(fn(e) { e.has("checked") }).unwrap_or(false)
  let accent = match self.env.tokens.iter().find_first(fn(t) { t.0 == "--brand" }) {
    Some(t) => @html.parse_color(t.1, st.color, self.env.dark).unwrap_or(st.color)
    None => st.color
  }
  let line = @html.faded(st.color, 0.35)
  let l = laid(st, Row)
  match what {
    "checkbox" | "radio" => {
      let side = match st.width {
        Of(p, 0.0) if p > 0.0 => p
        _ => 16.0
      }
      v.css_laid(Is({ ..l, width: Pt(side), height: Pt(side), shrink: 0.0, justify: Center, align_items: Center }))
      .radius(Is(if what == "radio" { side / 2.0 } else { 4.0 }))
      |> ignore
      if checked {
        v.ground(Is(accent)) |> ignore
        v.box(fn(dot) {
          if what == "radio" {
            dot.css_laid(Is({ ..@view.CssLaid::block(), width: Pt(side * 0.4), height: Pt(side * 0.4) })).radius(Is(side)).ground(Is(0xFFFFFFFFL)) |> ignore
          } else {
            dot.words(Is("✓"), ink=0xFFFFFFFFL, look={ ..words_look(st), size: side * 0.75, line: side, weight: 700 }) |> ignore
          }
        })
        |> ignore
      } else {
        v.edge(Is((1.5, line))) |> ignore
      }
    }
    "range" | "progress" | "meter" => {
      let share = match el {
        Some(e) => {
          let value = @html.parse_number(e.attr("value").unwrap_or(if what == "range" { "50" } else { "0" })).unwrap_or(0.0)
          let lo = if what == "range" { @html.parse_number(e.attr("min").unwrap_or("0")).unwrap_or(0.0) } else { 0.0 }
          let hi = @html.parse_number(e.attr("max").unwrap_or(if what == "range" { "100" } else { "1" })).unwrap_or(1.0)
          if hi > lo {
            let k = (value - lo) / (hi - lo)
            if k < 0.0 {
              0.0
            } else if k > 1.0 {
              1.0
            } else {
              k
            }
          } else {
            0.0
          }
        }
        None => 0.0
      }
      let tall = if what == "range" { 16.0 } else { 6.0 }
      v.css_laid(Is({ ..l, width: if l.width == Auto { Pct(100.0) } else { l.width }, height: Pt(tall), align_items: Center, direction: Row }))
      |> ignore
      v.box(fn(track) {
        track.css_laid(Is({ ..@view.CssLaid::block(), grow: 1.0, height: Pt(if what == "range" { 4.0 } else { tall }), direction: Row, hidden: true }))
        .radius(Is(tall))
        .ground(Is(@html.faded(st.color, 0.15)))
        |> ignore
        track.box(fn(fill) {
          fill.css_laid(Is({ ..@view.CssLaid::block(), width: Pct(share * 100.0) })).ground(Is(accent)).radius(Is(tall)) |> ignore
        })
        |> ignore
      })
      |> ignore
      if what == "range" {
        v.box(fn(thumb) {
          thumb.css_laid(Is({ ..@view.CssLaid::block(), absolute: true, inset: (Pct(share * 100.0), Pt(0.0), Auto, Auto), width: Pt(16.0), height: Pt(16.0), margin: (Pt(-8.0 * share * 2.0), Pt(0.0), Pt(0.0), Pt(0.0)) }))
          .radius(Is(8.0))
          .ground(Is(0xFFFFFFFFL))
          .edge(Is((1.0, line)))
          .shadow(Is((2.0, 1.0, 0x00000033L)))
          |> ignore
        })
        |> ignore
      }
    }
    "color" => {
      let c = @html.parse_color(words, st.color, false).unwrap_or(0x000000FFL)
      v.css_laid(Is({ ..l, width: Pt(36.0), height: Pt(24.0) })).radius(Is(6.0)).ground(Is(c)) |> ignore
    }
    _ => {
      // a field (text, select, textarea) or a button: its box as its CSS says, its words in it
      let placeholder = el.map(fn(e) { !e.has("value") && e.has("placeholder") }).unwrap_or(false)
      let field_default = st.border_width.iter().all(fn(w) { w == 0.0 }) && st.background == 0L
      v.css_laid(Is({ ..l, align_items: if what == "textarea" { FlexStart } else { Center }, padding: if field_default { (Pt(8.0), Pt(4.0), Pt(8.0), Pt(4.0)) } else { l.padding }, width: if l.width == Auto && what != "button" { Pct(100.0) } else { l.width } }))
      |> ignore
      decorate(v, st)
      if field_default && what != "button" {
        v.edge(Is((1.0, line))).radius(Is(6.0)) |> ignore
      }
      v.box(fn(w) {
        w.css_laid(Is({ ..@view.CssLaid::block(), grow: 1.0, shrink: 1.0 }))
        .words(Is(words), ink=if placeholder { @html.faded(st.color, 0.55) } else { st.color }, look={ ..words_look(st), wrap: what == "textarea" })
        |> ignore
      })
      |> ignore
      if what == "select" {
        v.words(Is("⌄"), ink=@html.faded(st.color, 0.6), look=words_look(st)) |> ignore
      }
    }
  }
}

// ── what it does as it is used ───────────────────────────────────────

///|
/// Element `i`'s attribute `name` set (None: taken away) as using the widget changed it.
fn Builder::set_attr(self : Builder, i : Int, name : String, value : String?) -> Unit {
  let list = match self.changed.get(i) {
    Some(l) => l
    None => {
      let l = []
      self.changed[i] = l
      l
    }
  }
  match list.search_by(fn(c) { c.0 == name }) {
    Some(k) => list[k] = (name, value)
    None => list.push((name, value))
  }
}

///|
fn Builder::elem(self : Builder, i : Int) -> @html.Elem {
  self.styled.tree.els[i].elem
}

///|
/// Element `i`'s classes with `cls` in them or not.
fn Builder::set_class(self : Builder, i : Int, cls : String, on : Bool) -> Unit {
  let have = self.elem(i).classes().filter(fn(c) { c != cls })
  if on {
    have.push(cls)
  }
  self.set_attr(i, "class", Some(have.join(" ")))
}

///|
fn Builder::by_id(self : Builder, id : String) -> Int? {
  for k, p in self.styled.tree.els {
    if p.elem.attr("id") == Some(id) {
      return Some(k)
    }
  }
  None
}

///|
/// The element of `tag` (or with `role`) that holds element `i`, nearest first.
fn Builder::up(self : Builder, i : Int, ok : (@html.Elem) -> Bool) -> Int? {
  let mut p = self.styled.tree.els[i].parent
  while p >= 0 {
    if ok(self.elem(p)) {
      return Some(p)
    }
    p = self.styled.tree.els[p].parent
  }
  None
}

///|
/// What a box does when pressed, where HTML or the design system says it does something without a script: a tab of a
/// tab list shows its panel and hides the others' (components.js's tabs), a summary opens or closes its details, a
/// label holding a box to tick ticks it.
fn Builder::behave(self : Builder, v : @view.View, b : @html.Box) -> Unit {
  guard b.el >= 0 else { return }
  let i = b.el
  let e = self.elem(i)
  let disabled = e.has("disabled") || e.attr("aria-disabled") == Some("true")
  if e.attr("role") == Some("tab") && !disabled {
    match self.up(i, fn(x) { x.attr("role") == Some("tablist") }) {
      Some(list) => {
        let selected = e.attr("aria-selected") == Some("true")
        v.says(Is(Some(@view.said(Tab, label=e.text().trim().to_string(), selected~)))) |> ignore
        v.on_press(fn() {
          let mine = e.attr("aria-controls")
          for k, p in self.styled.tree.els {
            if p.elem.attr("role") == Some("tab") && self.up(k, fn(x) { x.attr("role") == Some("tablist") }) == Some(list) {
              let on = k == i
              self.set_class(k, "active", on)
              self.set_attr(k, "aria-selected", Some(on.to_string()))
              match p.elem.attr("aria-controls").bind(fn(id) { self.by_id(id) }) {
                Some(panel) => {
                  let hide = !on && p.elem.attr("aria-controls") != mine
                  self.set_attr(panel, "hidden", if hide { Some("") } else { None })
                }
                None => ()
              }
            }
          }
          self.version.set(self.version.get() + 1)
        })
        |> ignore
      }
      None => ()
    }
    return
  }
  if e.tag == "summary" {
    match self.up(i, fn(x) { x.tag == "details" }) {
      Some(d) => {
        let open = self.elem(d).has("open")
        v.says(Is(Some(@view.said(Button, label=e.text().trim().to_string(), expanded=open)))) |> ignore
        v.on_press(fn() {
          self.set_attr(d, "open", if open { None } else { Some("") })
          self.version.set(self.version.get() + 1)
        })
        |> ignore
      }
      None => ()
    }
    return
  }
  if e.tag == "label" {
    // the box it holds (or names), ticked by a press anywhere on it
    let mut target = -1
    for k in self.styled.tree.kids[i] {
      ignore(k)
    }
    for k, p in self.styled.tree.els {
      if p.elem.tag == "input" && self.up(k, fn(x) { physical_equal(x, e) }) is Some(_) {
        target = k
        break
      }
    }
    match e.attr("for").bind(fn(id) { self.by_id(id) }) {
      Some(k) => target = k
      None => ()
    }
    if target >= 0 {
      let input = self.elem(target)
      let ty = input.attr("type").unwrap_or("")
      if (ty == "checkbox" || ty == "radio") && !input.has("disabled") {
        let checked = input.has("checked")
        v.says(Is(Some(@view.said(if ty == "radio" { Radio } else { Checkbox }, label=e.text().trim().to_string(), check=if checked { On } else { Off })))) |> ignore
        v.on_press(fn() { self.tick(target) }) |> ignore
      }
    }
  }
}

///|
/// A box to tick ticked or not as it is pressed (a radio: the others of its name not).
fn Builder::tick(self : Builder, i : Int) -> Unit {
  let e = self.elem(i)
  let ty = e.attr("type").unwrap_or("")
  if ty == "radio" {
    let name = e.attr("name")
    for k, p in self.styled.tree.els {
      if p.elem.tag == "input" && p.elem.attr("type") == Some("radio") && p.elem.attr("name") == name {
        self.set_attr(k, "checked", if k == i { Some("") } else { None })
      }
    }
  } else {
    self.set_attr(i, "checked", if e.has("checked") { None } else { Some("") })
  }
  self.version.set(self.version.get() + 1)
}

///|
/// A control pressed on its own (not in a label that does it): a box to tick ticked.
fn Builder::behave_control(self : Builder, v : @view.View, b : @html.Box, what : String) -> Unit {
  guard b.el >= 0 else { return }
  let i = b.el
  let e = self.elem(i)
  guard (what == "checkbox" || what == "radio") && !e.has("disabled") else { return }
  // (in a label, the label takes the press)
  if self.up(i, fn(x) { x.tag == "label" }) is Some(_) {
    return
  }
  let checked = e.has("checked")
  let label = e.attr("aria-label").unwrap_or(e.attr("name").unwrap_or(what))
  v.says(Is(Some(@view.said(if what == "radio" { Radio } else { Checkbox }, label~, check=if checked { On } else { Off })))) |> ignore
  v.on_press(fn() { self.tick(i) }) |> ignore
}
