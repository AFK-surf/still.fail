// A narrow page's choice as nodes (seg_fill_node) drawn as the old view's (segmented on a narrow page: seg's filling
// Seg), every instance the same: each chosen, at rest; in a room its words fill (their sides narrower), short of it
// (their words smaller), far short of it (the chosen one alone, a chevron); at the system's larger words.

///|
/// Three options in a box `w` wide (12 from its sides), the one `chosen`: as an old view's (`node` false) or as
/// nodes; drawn at rest.
fn seg_fill_drawn(node : Bool, w : Double, chosen : Int, labels : Array[String], scale? : Double = 1.0) -> Array[String] {
  let at = @signals.signal(chosen)
  let t = if node {
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=200.0, platform=2)
    t.set_font_scale(scale)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(b) {
        b.padding(Is((12.0, 20.0, 12.0, 0.0))) |> ignore
        seg_fill_node(b, fn() { labels }, fn() { at.get() }, fn(k) { at.set(k) }) |> ignore
      })
      |> ignore
    })
    t
  } else {
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          with_look(Narrow, fn() {
            c.box(style=@ui.css("w=Full px=S3 pt=S5"), fn() {
              let k = segmented(c, "choice", labels, at.get())
              if k != at.get() {
                at.set(k)
              }
            })
            |> ignore
          })
        })
      },
      w~,
      h=200.0,
      platform=2,
    )
    t.set_font_scale(scale)
    t
  }
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  seg_drawn(t)
}

///|
/// What the window draws, each instance's numbers rounded to a hundredth (a glyph's place in its atlas left out), in one
/// order; read at once.
fn seg_drawn(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) {
    a
    .mapi(fn(j, x) {
      if a[5] == 1.0 && j == 12 {
        if x >= 16384.0 { "colour" } else { "mono" }
      } else if a[5] == 1.0 && j == 13 {
        "-"
      } else {
        ((x * 100.0).round() / 100.0).to_string()
      }
    })
    .join(",")
  })
  all.sort()
  all
}

///|
/// `made` the same as `old`, every instance; else what each has alone, said.
fn seg_same(made : Array[String], old : Array[String], what : String) -> Unit raise {
  assert_true(old.length() > 0, msg="\{what}: nothing drawn")
  if made != old {
    let only_old = old.filter(fn(x) { !made.contains(x) })
    let only_made = made.filter(fn(x) { !old.contains(x) })
    fail("\{what}: made \{made.length()}, old \{old.length()}\nold's alone:\n  \{only_old.join("\n  ")}\nmade's alone:\n  \{only_made.join("\n  ")}")
  }
}

///|
test "a narrow page's choice as nodes, drawn as the old view's: each chosen, filling its room, its words fitted short of it, at larger words" {
  let three = ["不提示", "做完就提示", "按模型判断"]
  let five = ["全部", "自动", "关闭", "仅工作日", "每天提醒我"]
  for case in [(390.0, three, 1.0), (390.0, five, 1.0), (260.0, five, 1.0), (200.0, five, 1.0), (390.0, three, 2.0), (390.0, five, 1.5)] {
    let (w, labels, scale) = case
    for k in 0..<labels.length() {
      seg_same(seg_fill_drawn(true, w, k, labels, scale~), seg_fill_drawn(false, w, k, labels, scale~), "\{w} \{labels.length()} at \{scale}, chosen \{k}")
    }
  }
}

///|
test "a narrow page's choice as nodes too narrow for its options side by side, drawn as the old view's: the chosen one's words cut short with a chevron at its end, each chosen, at larger words" {
  let two = ["按天", "按周"]
  let three = ["不提示", "做完就提示", "按模型判断"]
  let cases = [(90.0, three, 1.0), (80.0, three, 1.5)]
  for w = 60; w <= 92; w = w + 2 {
    cases.push((w.to_double(), two, 2.0))
  }
  let wrong = []
  for case in cases {
    let (w, labels, scale) = case
    for k in 0..<labels.length() {
      let old = seg_fill_drawn(false, w, k, labels, scale~)
      let made = seg_fill_drawn(true, w, k, labels, scale~)
      // (not side by side: no words of the others drawn)
      let drawn = @ui.view_tree().unwrap().drawn()
      for j, l in labels {
        if j != k {
          assert_true(!drawn.iter().any(fn(d) { d.words == l }), msg="\{Repr(case)}: a pick, \{l} not drawn")
        }
      }
      try {
        seg_same(made, old, "\{w} \{labels.length()} at \{scale}, chosen \{k}")
      } catch {
        Failure(e) => wrong.push(e)
        e => wrong.push(e.to_string())
      }
    }
  }
  // (every case's, said together)
  assert_true(wrong.is_empty(), msg=wrong.join("\n"))
}

///|
/// A choice of `labels` in a window `w` wide (12 from its sides, 20 from its top), the first chosen: as an old view's
/// (`node` false) or as nodes; `scrolled`, in a column that scrolls (as tall as the window less 20, something 600 tall
/// under it: a page's list, as the old view's list is, pulled past its ends where its platform's is). Each choice made
/// counted. At rest.
priv struct SegRig {
  t : @ui.Tester
  at : @signals.Signal[Int]
  chosen : Ref[Int]
}

///|
fn seg_rig(node : Bool, w : Double, labels : Array[String], scrolled? : Bool = false) -> SegRig {
  let at = @signals.signal(0)
  let chosen = Ref(0)
  let choose = fn(k : Int) {
    chosen.val += 1
    at.set(k)
  }
  let t = if node {
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w~, h=200.0, platform=2)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      let body = fn(b : @view.View) {
        b.padding(Is((12.0, 20.0, 12.0, 0.0))) |> ignore
        seg_fill_node(b, fn() { labels }, fn() { at.get() }, choose) |> ignore
      }
      if scrolled {
        root.box(fn(v) {
          v.height(Is(Some(180.0))) |> ignore
          v.scrolls(@view.Scroll::list(), fn(s) {
            s.box(body) |> ignore
            s.box(fn(tall) { tall.height(Is(Some(600.0))) |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      } else {
        root.box(body) |> ignore
      }
    })
    t
  } else {
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          with_look(Narrow, fn() {
            let body = fn() {
              c.box(style=@ui.css("w=Full px=S3 pt=S5"), fn() {
                let k = segmented(c, "choice", labels, at.get())
                if k != at.get() {
                  choose(k)
                }
              })
              |> ignore
            }
            if scrolled {
              @kit.scroll_area(c, "scrolled", 180.0, fn() {
                body()
                c.box(h=Px(600.0), fn() {  }) |> ignore
              })
            } else {
              body()
            }
          })
        })
      },
      w~,
      h=200.0,
      platform=2,
    )
    t
  }
  t.run_for(@ui.move_most_ms)
  { t, at, chosen }
}

///|
/// What a finger does at a moment (ms after the first of it): down at an x, moved to a point, let go, called off; or
/// what changes about where it is drawn (the window resized, the system's size of words).
priv enum SegStep {
  Down(Double)
  Move(Double, Double)
  Up
  Off
  Change((@ui.Tester) -> Unit)
}

///|
/// `steps` (each at its moment, from now) and what is drawn at each of `moments`, on one time line, in time order: at
/// each moment one of them is at (and every `grid` ms between, where said) the clock brought there, then the steps there
/// taken, as a host hands on what came at that moment, then a frame drawn there, then what is drawn read. The finger on the track's middle, up and down, where it went down unless moved.
fn seg_drive(t : @ui.Tester, steps : Array[(Double, SegStep)], moments : Array[Double], grid? : Double = 0.0) -> Array[
  Array[String],
] raise {
  let t0 = t.time()
  let at : Array[Double] = []
  for s in steps {
    at.push(s.0)
  }
  for m in moments {
    at.push(m)
  }
  if grid > 0.0 {
    let last = at.fold(init=0.0, fn(a, b) { dmax(a, b) })
    let mut g = grid
    while g < last {
      at.push(g)
      g += grid
    }
  }
  at.sort()
  let out = []
  let mut where_ = (0.0, 20.0 + 17.0)
  let mut prev = -1.0
  for p in at {
    if p == prev {
      continue
    }
    prev = p
    // (the clock brought to this moment first, nothing drawn: what comes now comes at it, as the host's events do)
    assert_true(t0 + p >= t.time(), msg="the time line goes on: \{p} after \{t.time() - t0}")
    t.advance(t0 + p - t.time())
    assert_true(t.time() == t0 + p, msg="at \{p} as its steps come: \{t.time() - t0}")
    for s in steps {
      if s.0 == p {
        match s.1 {
          Down(x) => {
            where_ = (x, where_.1)
            t.touch(0, x, where_.1)
          }
          Move(x, y) => {
            where_ = (x, y)
            t.touch(1, x, y)
          }
          Up => t.touch(2, where_.0, where_.1)
          Off => t.touch(3, where_.0, where_.1)
          Change(f) => f(t)
        }
      }
    }
    t.frame_at(t0 + p)
    if moments.contains(p) {
      out.push(seg_drawn(t))
    }
  }
  out
}

///|
/// A rig made (seg_rig) and driven (seg_drive) at once, alone (a Tester is the one there is while it is used: the old
/// view's and the node's never made side by side): what is drawn at `moments`, how often one was chosen, the one chosen.
fn seg_run(
  node : Bool,
  w : Double,
  labels : Array[String],
  steps : Array[(Double, SegStep)],
  moments : Array[Double],
  scrolled? : Bool = false,
  grid? : Double = 0.0,
) -> (Array[Array[String]], Int, Int) raise {
  let r = seg_rig(node, w, labels, scrolled~)
  let drawn = seg_drive(r.t, steps, moments, grid~)
  (drawn, r.chosen.val, r.at.get())
}

///|
/// Every moment where `made` is drawn otherwise than `old`, each said (seg_same's).
fn seg_unlike(made : Array[Array[String]], old : Array[Array[String]], moments : Array[Double], what : String) -> Array[String] {
  let out = []
  for i, o in old {
    try {
      seg_same(made[i], o, "\{what}, at \{moments[i]}")
    } catch {
      Failure(e) => out.push(e)
      e => out.push(e.to_string())
    }
  }
  out
}

///|
let seg_three : Array[String] = ["不提示", "做完就提示", "按模型判断"]

///|
/// (the third's middle, 390 wide: 12 in, 2 into the track, its share of 362 a third)
let seg_third_x : Double = 12.0 + 2.0 + 362.0 / 3.0 * 2.5

///|
let seg_moments : Array[Double] = [16.0, 50.0, 100.0, 180.0, 300.0, 600.0]

///|
test "a narrow page's choice as nodes, pressed as the old view's: its thumb sliding to the one tapped, and a lens over it while a finger holds it, the same events at the same moments" {
  let unlike = []
  for held in [30.0, 250.0] {
    let steps = [(0.0, Down(seg_third_x)), (held, Up)]
    let (o, old_n, old_at) = seg_run(false, 390.0, seg_three, steps, seg_moments)
    let (m, made_n, made_at) = seg_run(true, 390.0, seg_three, steps, seg_moments)
    assert_eq((made_n, made_at), (old_n, old_at), msg="held \{held}: chosen as often, the same one")
    assert_eq((old_n, old_at), (1, 2), msg="held \{held}: the third chosen once")
    unlike.append(seg_unlike(m, o, seg_moments, "held \{held}"))
  }
  if unlike.length() > 0 {
    fail(unlike.join("\n"))
  }
}

///|
/// Five options of unlike widths: 300 wide fitted (their sides narrower); 360, laid out each its least or more; at 1.3
/// times the words, smaller.
let seg_five : Array[String] = ["全部", "自动", "关闭", "仅工作日", "每天提醒我"]

///|
test "a narrow page's choice as nodes, its thumb going between options of unlike widths as the old view's, the window resized or the words made larger meanwhile, the same events at the same moments" {
  let moments = [30.0, 59.0, 60.0, 80.0, 120.0, 200.0, 400.0, 800.0]
  // (the last one, 8 in from the track's end, tapped)
  let x = 300.0 - 12.0 - 2.0 - 8.0
  let unlike = []
  let changes : Array[(String, (@ui.Tester) -> Unit)] = [
    ("resized", fn(t) { t.resize_next(360.0, 200.0) }),
    ("larger words", fn(t) { t.set_font_scale(1.3) }),
  ]
  for c in changes {
    let (what, change) = c
    let steps = [(0.0, Down(x)), (16.0, Up), (59.0, Change(change))]
    let (o, old_n, old_at) = seg_run(false, 300.0, seg_five, steps, moments)
    let (m, made_n, made_at) = seg_run(true, 300.0, seg_five, steps, moments)
    assert_eq((old_n, old_at), (1, 4), msg="\{what}: the old one's last chosen once")
    assert_eq((made_n, made_at), (1, 4), msg="\{what}: the node's last chosen once")
    unlike.append(seg_unlike(m, o, moments, what))
  }
  if unlike.length() > 0 {
    fail(unlike.join("\n"))
  }
}

///|
test "a narrow page's choice as nodes, side by side, then too narrow (the chosen one alone, a chevron), then side by side again and resized: drawn as the old view's at each" {
  let widths = [390.0, 150.0, 390.0, 300.0, 360.0]
  let seen = fn(node : Bool) {
    let r = seg_rig(node, 390.0, seg_five)
    // (the fourth chosen first: its thumb's place and width the cells' of the strip as it is now)
    r.at.set(3)
    r.t.run_for(@ui.move_most_ms)
    widths.map(fn(w) {
      r.t.resize_next(w, 200.0)
      r.t.run_for(@ui.move_most_ms)
      r.t.run_for(@ui.move_most_ms)
      seg_drawn(r.t)
    })
  }
  let old = seen(false)
  let made = seen(true)
  for i, w in widths {
    seg_same(made[i], old[i], "\{w} wide")
  }
}

///|
test "a narrow page's choice as nodes, chosen by a finger as the old view's: tapped, held and let go, moved off and back, held or not, called off, taken by the list it is in, held or not" {
  // (the second's middle, 390 wide; another option's, the third's; below it, 40 down)
  let second = 12.0 + 2.0 + 362.0 / 3.0 * 1.5
  let y = 20.0 + 17.0
  // (how often each is chosen: the old one's, as it is (-1: not said here), the node's as often)
  let cases : Array[(String, Bool, Array[(Double, SegStep)], Int)] = [
    ("tapped", false, [(0.0, Down(second)), (30.0, Up)], 1),
    ("held still, let go", false, [(0.0, Down(second)), (900.0, Up)], 1),
    ("held, moved to another and back, let go", false, [(0.0, Down(second)), (700.0, Move(seg_third_x, y)), (750.0, Move(second, y)), (900.0, Up)], -1),
    ("moved off and back at once, let go", false, [(0.0, Down(second)), (50.0, Move(seg_third_x, y)), (100.0, Move(second, y)), (150.0, Up)], -1),
    ("called off", false, [(0.0, Down(second)), (100.0, Off)], 0),
    ("in a list, moved down and up", true, [(0.0, Down(second)), (40.0, Move(second, y + 40.0)), (80.0, Move(second, y)), (120.0, Up)], -1),
    ("in a list, moved up and down", true, [(0.0, Down(second)), (40.0, Move(second, y - 30.0)), (80.0, Move(second, y)), (120.0, Up)], -1),
    ("in a list, held, then moved up and down", true, [(0.0, Down(second)), (700.0, Move(second, y + 40.0)), (750.0, Move(second, y)), (900.0, Up)], -1),
  ]
  for c in cases {
    let (what, scrolled, steps, times) = c
    let (_, old_n, old_at) = seg_run(false, 390.0, seg_three, steps, [1000.0], scrolled~)
    let (_, made_n, made_at) = seg_run(true, 390.0, seg_three, steps, [1000.0], scrolled~)
    // (-1: as many as the old one's, whatever: its contract)
    if times >= 0 {
      assert_eq(old_n, times, msg="\{what}: the old one chosen \{old_n} times")
    }
    assert_eq((made_n, made_at), (old_n, old_at), msg="\{what}: as the old one: chosen \{made_n} times, the \{made_at}; the old one \{old_n}, the \{old_at}")
  }
}
