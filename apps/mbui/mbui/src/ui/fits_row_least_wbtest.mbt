// A row kept no narrower than what it holds that leaves out what has not the room (an old view's `keep` and `drop`,
// a node's View::keeps_held and View::fits): its least is what is left once all it may leave out has left and its
// words cut short are at their least, so what is beside it squeezes it to that, what may leave leaving on the way.

///|
/// The words of the row's title: longer than its row has room for at the narrower widths.
let fits_least_title : String = "the title of a chat that is cut short"

///|
/// Words cut short beside the title, where a row holds two such.
let fits_least_second : String = "more words cut short beside it"

///|
/// The widths the window's row is laid out at, wide to narrow.
let fits_least_widths : Array[Double] = [640.0, 520.0, 440.0, 400.0, 360.0, 320.0, 280.0, 240.0, 200.0, 160.0]

///|
/// Each part of the row as one width laid it out: its name, whether it was left out, its x and width (rounded to a
/// hundredth; none of either where it was left out).
fn fits_least_said(name : String, out : Bool, x : Double, w : Double) -> String {
  if out {
    "\{name}: out"
  } else {
    let r = fn(v : Double) { (v * 100.0).round() / 100.0 }
    "\{name}: \{r(x)} \{r(w)}"
  }
}

///|
/// The old view's: a row as wide as the window's width holding a row that keeps what it holds (Fill, `keep`, 8 apart)
/// of words cut short, three boxes 30 wide that may leave (the third first) and a ⋯ 20 wide, and beside it a box 200
/// wide that gives way down to 80.
fn fits_least_old(
  widths : Array[Double],
  scales? : Array[Double] = [1.0],
  boxed? : Bool = false,
  two? : Bool = false,
) -> Array[String] {
  let width = @signals.signal(widths[0], same=fn(a, b) { a == b })
  let ids : Ref[(Int, Array[Int], Int, Int, Int)] = Ref((0, [], 0, 0, 0))
  let t = Tester::new(
    fn(c) {
      let (row, more, beside) = (c.id("row"), c.id("more"), c.id("beside"))
      let drops = [c.id("d1"), c.id("d2"), c.id("d3")]
      c.box(dir=Row, w=Px(width.get()), h=Px(20.0), fn() {
        c.box(dir=Row, w=Fill(1.0), keep=true, gap=8.0, id=row, taps=false, fn() {
          let title = if boxed {
            let mut i = 0
            c.box(fn() { i = c.text(fits_least_title, size=10.0, w=Cut, wrap=false) }) |> ignore
            i
          } else {
            c.text(fits_least_title, size=10.0, w=Cut, wrap=false)
          }
          if two {
            c.text(fits_least_second, size=10.0, w=Cut, wrap=false) |> ignore
          }
          for j, d in drops {
            c.box(w=Px(30.0), h=Px(20.0), id=d, taps=false, drop=3 - j, fn() {  }) |> ignore
          }
          c.box(w=Px(20.0), h=Px(20.0), id=more, taps=false, more=true, fn() {  }) |> ignore
          ids.val = (title, drops, more, row, beside)
        })
        |> ignore
        c.box(w=Px(200.0), min_w=80.0, h=Px(20.0), id=beside, taps=false, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=800.0,
    h=100.0,
  )
  t.draw()
  let out = []
  for scale in scales {
    t.set_font_scale(scale)
    for w in widths {
      width.set(w)
      t.frame()
      let (title, drops, more, row, beside) = ids.val
      let n = g().nodes[title]
      let lines = [fits_least_said("title", n.opacity == 0.0, n.x, n.fw)]
      for j, d in drops {
        let (x, _, bw, _, o) = laid_box(d)
        lines.push(fits_least_said("d\{j + 1}", o == 0.0, x, bw))
      }
      let (mx, _, mw, _, mo) = laid_box(more)
      // (the ⋯ not there: laid out none wide)
      lines.push(fits_least_said("more", mo == 0.0 || mw == 0.0, mx, mw))
      let (rx, _, rw, _, _) = laid_box(row)
      lines.push(fits_least_said("row", false, rx, rw))
      let (bx, _, bw, _, _) = laid_box(beside)
      lines.push(fits_least_said("beside", false, bx, bw))
      out.push("\{scale} \{w}: " + lines.join(", "))
    }
  }
  out
}

///|
/// The same as nodes of the window's tree: the row grown from none (Fill), giving way, kept no narrower than what it
/// holds (View::keeps_held) and leaving out what has not the room (View::fits).
fn fits_least_nodes(
  widths : Array[Double],
  scales? : Array[Double] = [1.0],
  boxed? : Bool = false,
  two? : Bool = false,
) -> Array[String] {
  let t = Tester::new(fn(_c) {  }, w=800.0, h=100.0)
  t.check_looks(false)
  let width = @signals.signal(widths[0], same=fn(a, b) { a == b })
  let parts : Ref[Array[@view.View]] = Ref([])
  let look : @view.WordsLook = { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false }
  set_view_app(fn(root) {
    root.box(fn(outer) {
      outer.row(Is(true)).width(By(fn() { Some(width.get()) })).height(Is(Some(20.0))) |> ignore
      let mut title : @view.View? = None
      let drops = []
      let mut more : @view.View? = None
      let row = outer.box(fn(k) {
        k
        .row(Is(true))
        .basis(Is(Some(0.0)))
        .grow(Is(1.0))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .keeps_held(Is(true))
        .fits(Is(true))
        .gap(Is(8.0))
        |> ignore
        let words = fn(w : @view.View) { w.cuts(Is(true)).words(Is(fits_least_title), ink=0x333333FFL, look~) |> ignore }
        title = Some(
          if boxed {
            // (in a box sized by what it holds, giving way as an old view's in a row does)
            let mut held : @view.View? = None
            k.box(fn(b) {
              b.row(Is(true)).shrink(Is(1.0)) |> ignore
              held = Some(b.box(words))
            })
            |> ignore
            held.unwrap()
          } else {
            k.box(words)
          },
        )
        if two {
          k.box(fn(w) { w.cuts(Is(true)).words(Is(fits_least_second), ink=0x333333FFL, look~) |> ignore }) |> ignore
        }
        for j in 0..<3 {
          drops.push(k.box(fn(d) { d.width(Is(Some(30.0))).height(Is(Some(20.0))).drops(Is(3 - j)) |> ignore }))
        }
        more = Some(k.box(fn(m) { m.width(Is(Some(20.0))).height(Is(Some(20.0))).drops(Is(-1)) |> ignore }))
      })
      let beside = outer.box(fn(b) {
        b.width(Is(Some(200.0))).min_width(Is(Some(80.0))).shrink(Is(1.0)).height(Is(Some(20.0))) |> ignore
      })
      parts.val = [title.unwrap()] + drops + [more.unwrap(), row, beside]
    })
    |> ignore
  })
  t.draw()
  let names = ["title", "d1", "d2", "d3", "more", "row", "beside"]
  let out = []
  for scale in scales {
    t.set_font_scale(scale)
    for w in widths {
      width.set(w)
      t.frame()
      let lines = []
      for j, v in parts.val {
        let (x, _, vw, _) = v.rect()
        lines.push(fits_least_said(names[j], v.left_out(), x, vw))
      }
      out.push("\{scale} \{w}: " + lines.join(", "))
    }
  }
  out
}

///|
/// Where the old view's and the nodes' differ, each width's two lines.
fn fits_least_differ(old : Array[String], nodes : Array[String]) -> String {
  let differ = []
  for j, o in old {
    if o != nodes[j] {
      differ.push("old:   \{o}\nnodes: \{nodes[j]}")
    }
  }
  differ.join("\n")
}

///|
test "a row kept no narrower than what it holds that leaves out what has not the room, squeezed by what is beside it: down to what is left once all that may leave has and its words cut short are at their least (four of their size), as an old view's keep; each part where the old view's is, the same left out" {
  let said = fits_least_differ(fits_least_old(fits_least_widths), fits_least_nodes(fits_least_widths))
  assert_eq(said, "")
}

///|
test "such a row's words cut short in a box sized by what it holds: what the box keeps is what its words keep, as an old view's" {
  let said = fits_least_differ(
    fits_least_old(fits_least_widths, boxed=true),
    fits_least_nodes(fits_least_widths, boxed=true),
  )
  assert_eq(said, "")
}

///|
test "such a row as the system's words grow to 1.3: what its words cut short keep grows with them, at once, as an old view's" {
  let scales = [1.0, 1.3]
  let old = fits_least_old(fits_least_widths, scales~)
  let nodes = fits_least_nodes(fits_least_widths, scales~)
  // (larger, it leaves out more at the same width: four of their size is more)
  assert_true(old[fits_least_widths.length() + 5] != old[5], msg="the same at 1.3: \{old[5]}")
  assert_eq(fits_least_differ(old, nodes), "")
}

///|
/// The known gap (mbui's AGENTS.md, Two views): where such a row and what is beside it are both at their least and still have
/// not the room, an old view comes down further as a last resort (ui's squeeze.mbt, Node's soft_least: words cut short
/// under four of their size, the widest first); a node's row stays at its least, what is beside it at its own, and the
/// two reach past their row. Till nodes have a last resort of their own, it is held here as it is.
test "such a row holding two words cut short: as an old view's but where it and what is beside it are both at their least and still have not the room (the known gap: no last resort for nodes), only there" {
  let said = fits_least_differ(
    fits_least_old(fits_least_widths, two=true),
    fits_least_nodes(fits_least_widths, two=true),
  )
  assert_eq(
    said,
    "old:   1 160: title: 0 24.3, d1: out, d2: out, d3: out, more: 60 20, row: 0 80, beside: 80 80\n" +
    "nodes: 1 160: title: 0 44.18, d1: out, d2: out, d3: out, more: 96 20, row: 0 116, beside: 116 80",
  )
}

///|
test "what such a row may leave out is what it holds itself: what may leave in a box it holds (not a row that leaves out what has not the room) is never left out, the box as wide as what it holds" {
  let t = Tester::new(fn(_c) {  }, w=800.0, h=100.0)
  t.check_looks(false)
  let width = @signals.signal(400.0, same=fn(a, b) { a == b })
  let parts : Ref[Array[@view.View]] = Ref([])
  let look : @view.WordsLook = { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false }
  set_view_app(fn(root) {
    root.box(fn(outer) {
      outer.row(Is(true)).width(By(fn() { Some(width.get()) })).height(Is(Some(20.0))) |> ignore
      let drops = []
      let mut inner : @view.View? = None
      let row = outer.box(fn(k) {
        k
        .row(Is(true))
        .basis(Is(Some(0.0)))
        .grow(Is(1.0))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .keeps_held(Is(true))
        .fits(Is(true))
        .gap(Is(8.0))
        |> ignore
        k.box(fn(w) { w.cuts(Is(true)).words(Is(fits_least_title), ink=0x333333FFL, look~) |> ignore }) |> ignore
        inner = Some(
          k.box(fn(m) {
            m.row(Is(true)).gap(Is(8.0)) |> ignore
            for j in 0..<3 {
              drops.push(m.box(fn(d) { d.width(Is(Some(30.0))).height(Is(Some(20.0))).drops(Is(3 - j)) |> ignore }))
            }
          }),
        )
      })
      let beside = outer.box(fn(b) {
        b.width(Is(Some(200.0))).min_width(Is(Some(80.0))).shrink(Is(1.0)).height(Is(Some(20.0))) |> ignore
      })
      parts.val = drops + [inner.unwrap(), row, beside]
    })
    |> ignore
  })
  t.draw()
  width.set(200.0)
  t.frame()
  let p = parts.val
  let said = (
    p[0].left_out() || p[1].left_out() || p[2].left_out(),
    p[3].rect().2,
    // (the row: its words at four of their size, 8, what it holds whole)
    p[4].rect().2,
    p[5].rect().2,
  )
  assert_eq(said, (false, 106.0, 40.0 + 8.0 + 106.0, 80.0))
}
