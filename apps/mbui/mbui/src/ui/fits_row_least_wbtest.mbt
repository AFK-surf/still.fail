// A row kept no narrower than what it holds that leaves out what has not the room (an old view's `keep` and `drop`,
// a node's View::keeps_held and View::fits): its least is what is left once all it may leave out has left and its
// words cut short are at their least, so what is beside it squeezes it to that, what may leave leaving on the way; as
// a last resort, where it and what is beside it are both at their least and still have not the room, its words cut
// short come down under that by what is missing (flex's fit_soft_held).

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
  let look : @view.WordsLook = { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
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
test "such a row holding two words cut short, it and what is beside it at their least and still without the room: as a last resort its words come down under four of their size by what is missing, as an old view's (Node's soft_least)" {
  let said = fits_least_differ(
    fits_least_old(fits_least_widths, two=true),
    fits_least_nodes(fits_least_widths, two=true),
  )
  assert_eq(said, "")
  // (at 160 the row at 80, under the 116 it keeps of its words at four of their size)
  let nodes = fits_least_nodes([160.0], two=true)
  assert_true(nodes[0].contains("row: 0 80,"), msg=nodes[0])
}

///|
test "what such a row may leave out is what it holds itself: what may leave in a box it holds (not a row that leaves out what has not the room) is never left out, the box as wide as what it holds" {
  let t = Tester::new(fn(_c) {  }, w=800.0, h=100.0)
  t.check_looks(false)
  let width = @signals.signal(400.0, same=fn(a, b) { a == b })
  let parts : Ref[Array[@view.View]] = Ref([])
  let look : @view.WordsLook = { size: 10.0, weight: 400, line: 14.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
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
    // (the row: as a last resort its words under four of their size, what it holds whole, what is beside it at its
    // least, the two in their room)
    p[4].rect().2,
    p[5].rect().2,
  )
  assert_eq(said, (false, 106.0, 200.0 - 80.0, 80.0))
}

///|
/// The title of a chat's bar in the tests of its last resort: longer than its row has room for at all their widths.
let fits_bar_title : String = "a chat whose title is long enough to be cut short here"

///|
/// The words before a find's field where it has not looked in all (find_bar's note), in a box that clips them.
let fits_bar_note : String = "held 300 of 1200 here so far"

///|
/// Each width a bar's title row and its find laid out: what the old view's and the nodes' are compared by (each part's
/// place, or left out), and the title's width and the find's field's.
struct FitsBar {
  said : String
  title : Double
  field : Double
}

///|
fn fits_bar_part(name : String, out : Bool, x : Double, w : Double) -> String {
  let r = fn(v : Double) { (v * 10.0).round() / 10.0 }
  if out {
    "\{name} out"
  } else {
    "\{name} \{r(x)}+\{r(w)}"
  }
}

///|
/// The old view's: a chat's bar as its old view had it (chat_bar), a row as wide as the width given holding, 16 apart,
/// its title's row that keeps what it holds (Fill, `keep`, 8 in, 4 at its end, 10 apart: chat_bar_title_row) and a
/// find (find_bar: its field 320 wide giving way to 160, with the note before it where `note`). In the title's row: the
/// title cut short (16) in a box at most 42% of the width, 80 at least; people 100 wide that leave first; an agent 120
/// wide; another 60 wide that leaves next.
fn fits_bar_old(widths : Array[Double], note? : Bool = false) -> Array[FitsBar] {
  let width = @signals.signal(widths[0], same=fn(a, b) { a == b })
  let ids : Ref[Array[Int]] = Ref([])
  let t = Tester::new(
    fn(c) {
      let (row, tbox, people, a1, a2, find, field) = (
        c.id("row"),
        c.id("tbox"),
        c.id("people"),
        c.id("a1"),
        c.id("a2"),
        c.id("find"),
        c.id("field"),
      )
      c.box(dir=Row, w=Px(width.get()), h=Px(32.0), gap=16.0, fn() {
        let mut title = 0
        c.box(dir=Row, w=Fill(1.0), keep=true, pl=8.0, pr=4.0, gap=10.0, id=row, taps=false, fn() {
          c.box(dir=Row, max_w=dmax(80.0, width.get() * 0.42), id=tbox, taps=false, fn() {
            title = c.text(fits_bar_title, size=16.0, w=Cut, wrap=false)
          })
          |> ignore
          c.box(w=Px(100.0), h=Px(20.0), id=people, taps=false, drop=1, fn() {  }) |> ignore
          c.box(w=Px(120.0), h=Px(20.0), id=a1, taps=false, fn() {  }) |> ignore
          c.box(w=Px(60.0), h=Px(20.0), id=a2, taps=false, drop=2, fn() {  }) |> ignore
        })
        |> ignore
        c.box(dir=Row, gap=8.0, id=find, taps=false, fn() {
          if note {
            c.box(max_w=320.0, clip=true, taps=false, fn() { c.text(fits_bar_note, size=12.0, wrap=false) |> ignore })
            |> ignore
          }
          c.box(dir=Row, w=Px(320.0), min_w=160.0, h=Px(32.0), id=field, taps=false, fn() {  }) |> ignore
        })
        |> ignore
        ids.val = [title, tbox, people, a1, a2, find, row, field]
      })
      |> ignore
    },
    w=1000.0,
    h=100.0,
  )
  t.draw()
  let out = []
  for w in widths {
    width.set(w)
    t.frame()
    let v = ids.val
    let title = g().nodes[v[0]].fw
    let parts = ["\{w}: title \{(title * 10.0).round() / 10.0}"]
    for j, name in ["box", "people", "a1", "a2", "find", "row"] {
      let (x, _, bw, _, o) = laid_box(v[j + 1])
      parts.push(fits_bar_part(name, o == 0.0, x, bw))
    }
    let (_, _, field, _, _) = laid_box(v[7])
    out.push({ said: parts.join(", "), title, field })
  }
  out
}

///|
/// The same as nodes of the window's tree (chat_bar_wide_node's): the title's row grown from none, giving way, kept no
/// narrower than what it holds and leaving out what has not the room; the title's box giving way; the find giving way
/// down to what the old view's keeps (its field at 160, the note at none).
fn fits_bar_nodes(widths : Array[Double], note? : Bool = false) -> Array[FitsBar] {
  let t = Tester::new(fn(_c) {  }, w=1000.0, h=100.0)
  t.check_looks(false)
  let width = @signals.signal(widths[0], same=fn(a, b) { a == b })
  let parts : Ref[Array[@view.View]] = Ref([])
  let look : @view.WordsLook = { size: 16.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
  set_view_app(fn(root) {
    root.box(fn(outer) {
      outer.row(Is(true)).width(By(fn() { Some(width.get()) })).height(Is(Some(32.0))).gap(Is(16.0)) |> ignore
      let got = []
      let row = outer.box(fn(k) {
        k
        .row(Is(true))
        .basis(Is(Some(0.0)))
        .grow(Is(1.0))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .keeps_held(Is(true))
        .fits(Is(true))
        .padding(Is((8.0, 0.0, 4.0, 0.0)))
        .gap(Is(10.0))
        |> ignore
        let mut words : @view.View? = None
        let tbox = k.box(fn(tb) {
          tb.row(Is(true)).max_width(By(fn() { Some(dmax(80.0, width.get() * 0.42)) })).shrink(Is(1.0)) |> ignore
          words = Some(tb.box(fn(w) { w.cuts(Is(true)).words(Is(fits_bar_title), ink=0x333333FFL, look~) |> ignore }))
        })
        got.push(words.unwrap())
        got.push(tbox)
        got.push(k.box(fn(d) { d.width(Is(Some(100.0))).height(Is(Some(20.0))).drops(Is(1)) |> ignore }))
        got.push(k.box(fn(d) { d.width(Is(Some(120.0))).height(Is(Some(20.0))) |> ignore }))
        got.push(k.box(fn(d) { d.width(Is(Some(60.0))).height(Is(Some(20.0))).drops(Is(2)) |> ignore }))
      })
      let mut field : @view.View? = None
      let find = outer.box(fn(e) {
        // (no narrower than the old view's: its field at its least, the note's at none, 8 apart)
        e.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(if note { 168.0 } else { 160.0 }))).gap(Is(8.0)) |> ignore
        if note {
          e.box(fn(n) {
            n.max_width(Is(Some(320.0))).clips(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            n.box(fn(w) {
              w.words(Is(fits_bar_note), ink=0x333333FFL, look={ ..look, size: 12.0, line: 16.0 }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        field = Some(
          e.box(fn(f) {
            f.row(Is(true)).width(Is(Some(320.0))).min_width(Is(Some(160.0))).height(Is(Some(32.0))).shrink(Is(1.0))
            |> ignore
          }),
        )
      })
      parts.val = got + [find, row, field.unwrap()]
    })
    |> ignore
  })
  t.draw()
  let out = []
  for w in widths {
    width.set(w)
    t.frame()
    let v = parts.val
    let title = v[0].rect().2
    let said = ["\{w}: title \{(title * 10.0).round() / 10.0}"]
    for j, name in ["box", "people", "a1", "a2", "find", "row"] {
      let (x, _, vw, _) = v[j + 1].rect()
      said.push(fits_bar_part(name, v[j + 1].left_out(), x, vw))
    }
    out.push({ said: said.join(", "), title, field: v[7].rect().2 })
  }
  out
}

///|
/// Where the old view's bar and the nodes' differ, each width's two lines.
fn fits_bar_differ(old : Array[FitsBar], nodes : Array[FitsBar]) -> String {
  let differ = []
  for j, o in old {
    if o.said != nodes[j].said {
      differ.push("old:   \{o.said}\nnodes: \{nodes[j].said}")
    }
  }
  differ.join("\n")
}

///|
test "a chat's bar, its title's row beside a find: what may leave leaves, the title kept at four of its size while the find gives way, and as a last resort (the find at its least) the title under that by what is missing, each part where the old view's is" {
  let widths = [680.0, 520.0, 400.0, 360.0]
  let old = fits_bar_old(widths)
  let nodes = fits_bar_nodes(widths)
  assert_eq(fits_bar_differ(old, nodes), "")
  // (at 520 and 400 the title at four of its size, the find giving way; at 360 the find at its least, the title 42)
  let r = fn(v : Double) { (v * 10.0).round() / 10.0 }
  assert_eq(
    nodes.map(fn(b) { (r(b.title), r(b.field)) }),
    [(132.0, 320.0), (64.0, 298.0), (64.0, 178.0), (42.0, 160.0)],
  )
}

///|
test "a chat's bar with the find's note before its field: as a last resort the title comes down by what is missing, the note at none and the field at its least, as the old view's" {
  let widths = [360.0]
  let old = fits_bar_old(widths, note=true)
  let nodes = fits_bar_nodes(widths, note=true)
  assert_eq(fits_bar_differ(old, nodes), "")
  assert_eq(((nodes[0].title * 10.0).round() / 10.0, nodes[0].field), (34.0, 160.0))
}

///|
test "a chat's bar narrowing: its title cut short is never under four of its size while the find has more to give" {
  let widths = [820.0, 760.0, 720.0, 680.0, 640.0, 600.0, 560.0, 520.0, 480.0, 440.0, 400.0, 380.0, 370.0, 360.0]
  let nodes = fits_bar_nodes(widths)
  let under = []
  for j, b in nodes {
    if b.field > 160.0 + 0.01 && b.title < 4.0 * 16.0 - 0.01 {
      under.push(nodes[j].said)
    }
  }
  assert_eq(under.join("\n"), "")
  // (and the last resort is reached: at 360 the title is under it)
  assert_true(nodes[nodes.length() - 1].title < 64.0 - 0.01, msg=nodes[nodes.length() - 1].said)
}
