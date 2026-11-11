// A node's glyphs each drawn by a look of their own (View::glyphs_by) as an old view's are (Ctx::glyphs_by, scene.mbt's
// glyph_next): told the same of each glyph (its number, its line, its middle along it), drawn the same; the cells a
// line of words is cut into (glyph_cells) where the node's glyphs are; drawn again as its state changes on a way, and
// asking for nothing once that is over.

///|
/// How long the way the glyphs of glyphs_way_tester come in on takes.
let glyphs_way_ms : Double = 300.0

///|
/// A look for each glyph worked out of where it is alone: fainter down its words, moved by its line and along it,
/// narrower by its number.
fn glyph_look_of(at : GlyphAt) -> GlyphLook {
  {
    alpha: 1.0 - (at.index % 4).to_double() * 0.2,
    dx: at.cx * 0.05,
    dy: at.line.to_double() * 3.0,
    scale: 1.0,
    sx: if at.index % 2 == 0 { 1.0 } else { 0.75 },
  }
}

///|
/// `words` at 15 on 22 in a column `w` wide (wrapped), in two pieces split at `cut`, the second bold where `runs`, each
/// glyph drawn by glyph_look_of: by an old view (Ctx::rich or Ctx::text, Ctx::glyphs_by) or by a node (View::words_runs
/// or View::words, View::glyphs_by). What is read at once (the Tester's reads are the last made's): what each glyph was
/// told (its number, line, middle along it and its line's box), and each glyph drawn, to a hundredth.
fn glyphs_told_drawn(node : Bool, runs : Bool, words : String, cut : Int, w : Double) -> (Array[String], Array[String]) {
  let first = words.exact_view(end=cut).to_owned()
  let second = words.exact_view(start=cut).to_owned()
  let told : Array[String] = []
  let r2 = fn(x : Double) { (x * 100.0).round() / 100.0 }
  // (what each glyph is told, kept as it is asked: the frame's last asking of each number the one kept)
  let tell = fn(at : GlyphAt) {
    let s = "\{at.index}: line \{at.line}, cx \{r2(at.cx)}, box \{r2(at.x)},\{r2(at.y)} \{r2(at.h)}"
    if at.index < told.length() {
      told[at.index] = s
    } else if at.index == told.length() {
      told.push(s)
    }
    glyph_look_of(at)
  }
  let t = if node {
    Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  } else {
    Tester::new(
      fn(c) {
        let col = c.column(w=Px(w), align=AStart, fn() {
          if runs {
            c.rich([plain(first), bold(second)], size=15.0, line=22.0, wrap=true) |> ignore
          } else {
            c.text(words, size=15.0, line=22.0, wrap=true) |> ignore
          }
        })
        c.glyphs_by(col, tell)
      },
      w=400.0,
      h=300.0,
    )
  }
  t.check_looks(false)
  if node {
    set_view_app(fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(col) {
        col.width(Is(Some(w))).lines_up(Is(Some(Start))) |> ignore
        col.box(fn(v) {
          if runs {
            v.words_runs(Is([@view.words_run(first), @view.words_run(second, weight=700)])) |> ignore
          } else {
            v.words(Is(words)) |> ignore
          }
          v.glyphs_by(Is(0), fn(_, at) { tell(at) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t.draw()
  let drawn = t
    .drawn_instances_keyed()
    .filter(fn(a) { a[5] == 1.0 })
    .map(fn(a) { "\{r2(a[0])},\{r2(a[1])} \{r2(a[2])}x\{r2(a[3])} a\{r2(a[11])}" })
  (told.copy(), drawn)
}

///|
test "a node's glyphs by a look of their own: each told its number, its line and its middle along it as an old view's are, and drawn alike, plain and in pieces, on one line and on more" {
  for runs in [false, true] {
    for w in [300.0, 60.0] {
      let at = "\{if runs { "in pieces" } else { "plain" }}, \{w} wide"
      let (old_told, old_drawn) = glyphs_told_drawn(false, runs, "ab cd efg hij", 6, w)
      let (made_told, made_drawn) = glyphs_told_drawn(true, runs, "ab cd efg hij", 6, w)
      assert_eq(made_told, old_told, msg="\{at}: told")
      assert_eq(made_drawn, old_drawn, msg="\{at}: drawn: only made \{Repr(made_drawn.filter(fn(x) { !old_drawn.contains(x) }))} | only old \{Repr(old_drawn.filter(fn(x) { !made_drawn.contains(x) }))}")
      // (all its glyphs told and drawn: ab cd efg hij, 10)
      assert_eq(made_told.length(), 10, msg="\{at}: \{Repr(made_told)}")
      // (narrow: on two lines, the middle along each from its own start: the second line's first glyph as the first's)
      if w < 100.0 {
        assert_true(made_told[0].has_prefix("0: line 0, cx 3.75,") && made_told[4].has_prefix("4: line 1, cx 3.75,"), msg="\{at}: \{Repr(made_told)}")
      }
    }
  }
}

///|
/// The middle along its line each glyph of `words` on one line at 15 is told, drawn by a node (View::words; `mono`:
/// View::words_runs of one piece in the code face), the system's size of words `scale`.
fn node_glyph_middles(words : String, mono : Bool, scale : Double) -> Array[Double] {
  let told : Array[Double] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  t.set_font_scale(scale)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      let look = { ..@view.words_plain, wrap: false }
      if mono {
        v.words_runs(Is([@text.span(words, mono=true)]), look~) |> ignore
      } else {
        v.words(Is(words), look~) |> ignore
      }
      v.glyphs_by(Is(0), fn(_, at) {
        if at.index == told.length() {
          told.push(at.cx)
        }
        { alpha: 1.0, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 }
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.draw()
  told
}

///|
test "the cells a line of words is cut into (glyph_cells): each glyph's middle where a node drawing them tells it, plain and in the code face, the system's words at 1 and at 1.3" {
  for case in [("ab cd 读 chat_rows.mbt", false), ("moon test --target", true)] {
    let (words, mono) = case
    for scale in [1.0, 1.3] {
      let told = node_glyph_middles(words, mono, scale)
      let cells = glyph_cells(words, { ..@view.words_plain, wrap: false }, scale, mono~).map(fn(c) { c.0 })
      assert_eq(cells, told, msg="\{words} at \{scale}")
      assert_true(cells.length() > 0 && cells.iter().all(fn(x) { x > 0.0 }), msg="\{Repr(cells)}")
    }
  }
}

///|
/// Words whose glyphs come in on a way from the moment `from` says (none: in already), each as opaque as it has come.
fn glyphs_way_tester(from : @signals.Signal[Double]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(v) {
      v.words(Is("abcd")) |> ignore
      v.glyphs_by(
        By(fn() {
          let f = from.get()
          if f < 0.0 {
            1.0
          } else {
            let at = v.drawn_while(fn(now) { now < f + glyphs_way_ms })
            if at >= f + glyphs_way_ms {
              1.0
            } else {
              (at - f) / glyphs_way_ms
            }
          }
        }),
        fn(p, _) { { alpha: p, dx: 0.0, dy: 0.0, scale: 1.0, sx: 1.0 } },
      )
      |> ignore
    })
    |> ignore
  })
  t
}

///|
/// How opaque each glyph drawn in the last frame is, to a hundredth.
fn glyph_alphas(t : Tester) -> Array[Double] {
  t.drawn_instances_keyed().filter(fn(a) { a[5] == 1.0 }).map(fn(a) { (a[11] * 100.0).round() / 100.0 })
}

///|
test "a node's glyphs by a state on a way: drawn as it is at each moment said, whatever the rate; asking for no frame once it is over, nor while it does not change" {
  let from = @signals.signal(-1.0)
  let t = glyphs_way_tester(from)
  t.draw()
  assert_eq(glyph_alphas(t), [1.0, 1.0, 1.0, 1.0])
  // (nothing said to change: nothing asks for a frame)
  assert_eq(t.idle_said(), None)
  // (on its way from now: half way at half its time, each glyph half as opaque)
  from.set(t.time())
  t.run_for(glyphs_way_ms / 2.0)
  assert_eq(glyph_alphas(t), [0.5, 0.5, 0.5, 0.5])
  // (over: whole, and nothing asks for a frame)
  t.run_for(glyphs_way_ms)
  assert_eq(glyph_alphas(t), [1.0, 1.0, 1.0, 1.0])
  assert_eq(t.idle_said(), None)
}
