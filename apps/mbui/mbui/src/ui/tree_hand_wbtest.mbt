// What a mouse points at across the window's tree and the old views in it (view_host.mbt view_pointed): the one
// topmost target under it lit, whichever side it is, the other no longer, as it comes; a still pointer's target again
// as what it hits changes (a node moved under it, one taking presses no more, a layer over it), nothing on frames that
// change none of it; gone from the window, or the hand a finger, nothing.

///|
let hand_old_lit : Int64 = 0x33AA55FFL

///|
let hand_tree_lit : Int64 = 0xCC3333FFL

///|
let hand_off : Int64 = 0x777777FFL

///|
priv struct Hands {
  t : Tester
  /// where the tree's button is across, whether it takes presses, whether a modal layer of the tree's and one of the
  /// old frame's over all of it are open
  at : @signals.Signal[Double]
  takes : @signals.Signal[Bool]
  tree_modal : @signals.Signal[Bool]
  old_layer : @signals.Signal[Bool]
  /// whether the tree's button takes a press where it is (what its View::takes reads)
  enabled : @signals.Signal[Bool]
  /// a layer of the old frame's, not modal: 0 none, 1 over all of the window passing the pointer on (Ctx::passes), 2
  /// over its left 150 alone, 3 the one of 1 passing nothing on
  layer : @signals.Signal[Int]
}

///|
/// An old view's button in the left half (lit as hovered) and a button of the tree's (lit as pointed) at `at`, 80 by 40
/// at y 20, on a mouse.
fn hands(platform? : Int = 0) -> Hands {
  let at = @signals.signal(200.0, same=fn(a, b) { a == b })
  let takes = @signals.signal(true, same=fn(a, b) { a == b })
  let tree_modal = @signals.signal(false, same=fn(a, b) { a == b })
  let old_layer = @signals.signal(false, same=fn(a, b) { a == b })
  let enabled = @signals.signal(true, same=fn(a, b) { a == b })
  let layer = @signals.signal(0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform~)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(150.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        let id = c.id("old-button")
        c.box(w=Px(80.0), h=Px(40.0), id~, bg=if c.hovered(id) { hand_old_lit } else { hand_off }, fn() {  }) |> ignore
        if old_layer.get() {
          c.overlay("over-all", modal=true, fn() { c.box(w=Px(400.0), h=Px(200.0), bg=0xFFFFFF01L, fn() {  }) |> ignore }) |> ignore
        }
        match layer.get() {
          1 | 3 => {
            let o = c.overlay("passing", fn() {
              c.box(w=Px(400.0), h=Px(200.0), id=c.id("passing-box"), bg=0xFFFFFF01L, fn() {  }) |> ignore
            })
            if layer.get() == 1 {
              c.passes(o.node)
            }
          }
          2 =>
            c.overlay("left", fn() {
              c.box(w=Px(150.0), h=Px(200.0), id=c.id("left-box"), bg=0xFFFFFF01L, fn() {  }) |> ignore
            })
            |> ignore
          _ => ()
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(By(fn() { (at.get(), 20.0) }))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { takes.get() }))
      .on_press(fn() {  })
      .takes(fn(_, _, _) { enabled.get() })
      .ground(By(fn() { if n.pointed() { hand_tree_lit } else { hand_off } }))
      |> ignore
    })
    |> ignore
    root.show(fn() { tree_modal.get() }, fn(m) {
      m.over(Is(true)).modal(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
    })
  })
  t.draw()
  { t, at, takes, tree_modal, old_layer, enabled, layer }
}

///|
/// What is lit in the next frame: the old view's button, the tree's.
fn Hands::lit(self : Hands) -> (Bool, Bool) {
  self.t.frame_at(self.t.time() + frame_period_default)
  let rects = self.t.drawn_rects()
  (rects.iter().any(fn(r) { r.4 == hand_old_lit }), rects.iter().any(fn(r) { r.4 == hand_tree_lit }))
}

///|
test "a mouse from an old view's button to a tree's and back: the one under it lit, the other no longer, at once" {
  let h = hands()
  h.t.move(40.0, 20.0)
  assert_eq(h.lit(), (true, false))
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, true))
  h.t.move(40.0, 20.0)
  assert_eq(h.lit(), (true, false))
  // (between them, over neither)
  h.t.move(170.0, 150.0)
  assert_eq(h.lit(), (false, false))
}

///|
test "a still mouse: the tree's button moved under it lit, moved off it not, taking presses no more not; a layer over it, the tree's or the old frame's, not" {
  let h = hands()
  h.t.move(100.0, 40.0)
  assert_eq(h.lit(), (false, false))
  h.at.set(60.0)
  assert_eq(h.lit(), (false, true))
  h.takes.set(false)
  assert_eq(h.lit(), (false, false))
  h.takes.set(true)
  assert_eq(h.lit(), (false, true))
  h.tree_modal.set(true)
  assert_eq(h.lit(), (false, false))
  h.tree_modal.set(false)
  assert_eq(h.lit(), (false, true))
  h.old_layer.set(true)
  assert_eq(h.lit(), (false, false), msg="under the old frame's layer")
  h.old_layer.set(false)
  assert_eq(h.lit(), (false, true))
  h.at.set(200.0)
  assert_eq(h.lit(), (false, false))
}

///|
test "the mouse gone from the window: nothing of the tree's lit; a finger's tap leaves nothing lit" {
  let h = hands()
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, true))
  h.t.leave()
  assert_eq(h.lit(), (false, false))
  let f = hands(platform=2)
  f.t.tap(240.0, 40.0)
  assert_eq(f.lit(), (false, false))
}

///|
test "a still mouse on an old view's button: the tree's button moved over it lit and the old one not, in that frame; moved off it, the old one again" {
  let h = hands()
  h.t.move(40.0, 30.0)
  assert_eq(h.lit(), (true, false))
  h.at.set(0.0)
  assert_eq(h.lit(), (false, true))
  h.at.set(200.0)
  assert_eq(h.lit(), (true, false), msg="the old one again")
}

///|
test "a still mouse on the tree's button: what its takes reads said otherwise, it is not pointed at, and is again" {
  let h = hands()
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, true))
  h.enabled.set(false)
  assert_eq(h.lit(), (false, false), msg="takes nothing there")
  h.enabled.set(true)
  assert_eq(h.lit(), (false, true))
}

///|
test "a still mouse where the tree's button takes nothing at first: lit as it comes to take it; over an old view's button, that one lit as it takes nothing there" {
  let h = hands()
  h.enabled.set(false)
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, false))
  h.enabled.set(true)
  assert_eq(h.lit(), (false, true), msg="taking it from now")
  // (over the old view's button: the old one lit where the tree's takes nothing, the tree's where it does)
  h.t.move(40.0, 30.0)
  h.at.set(0.0)
  assert_eq(h.lit(), (false, true))
  h.enabled.set(false)
  assert_eq(h.lit(), (true, false), msg="the old one under it")
  h.enabled.set(true)
  assert_eq(h.lit(), (false, true))
}

///|
test "the window's tree let go: what followed where the pointer is (what its takes read) followed no more, at once" {
  let h = hands()
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, true))
  assert_true(h.enabled.watched())
  view_tree().unwrap().dispose()
  assert_false(h.enabled.watched())
}

///|
test "a still mouse and a layer of the old frame's, not modal: one passing the pointer on leaves the tree's button lit, one beside it too; one over the old button, that one not lit" {
  let h = hands()
  h.t.move(240.0, 40.0)
  assert_eq(h.lit(), (false, true))
  h.layer.set(1)
  assert_eq(h.lit(), (false, true), msg="passed on")
  h.layer.set(2)
  assert_eq(h.lit(), (false, true), msg="beside it")
  h.t.move(40.0, 30.0)
  assert_eq(h.lit(), (false, false), msg="the old button under the layer")
  // (the old views light what is under the pointer as their frame ends, by its targets, and draw it so the next: their
  // own way, as ever, desktop.mbt; the tree's nothing either way)
  h.layer.set(0)
  assert_eq(h.lit(), (false, false), msg="the old views' frame the layer went in")
  assert_eq(h.lit(), (true, false), msg="the old views' next")
}

///|
test "the frame's targets found before the tree is drawn are found once: an old view with a list and words to pick, a layer of the old frame's over it, each said once a frame" {
  let field = Field::new()
  field.set("words to pick")
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      old(b, fn(c) {
        c.list("rows", 30, 40.0, fn(k) {
          c.box(w=Fill(1.0), h=Px(40.0), id=c.id("row \{k}"), fn() { c.text("row \{k}", size=12.0) |> ignore }) |> ignore
        })
        |> ignore
        c.overlay("over-all", fn() { c.editor("field", font_size=16.0, field~) |> ignore }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move(100.0, 100.0)
  t.frame_at(t.time() + frame_period_default)
  let c = g()
  let once = fn(ids : Array[Int]) { Set::from_array(ids).length() == ids.length() }
  assert_true(once(c.hit_ids), msg="targets \{c.hit_ids}")
  assert_true(once(c.scroll_ids), msg="what scrolls \{c.scroll_ids}")
  assert_true(c.hit_ids.length() > 0 && c.scroll_ids.length() > 0)
}

///|
test "an old view's link in the window's tree: pressed where its words are, as the frame's targets found them" {
  let opened : Array[String] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        c.box(w=Px(80.0), fn() {
          c.rich([{ ..plain("the notes"), link: "notes" }], size=16.0, on_link=fn(l) { opened.push(l) }) |> ignore
        })
        |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (its words the whole of a box narrower than they are wide: its middle on them)
  let (x, y) = t.find("the notes").unwrap()
  t.tap(x, y)
  t.draw()
  assert_eq(opened, ["notes"])
}

///|
test "a still mouse and a layer of the old frame's passing the pointer on, then not, then again (the same layer, the same targets): the tree's button lit, not, lit, each in its frame" {
  let h = hands()
  h.t.move(240.0, 40.0)
  h.layer.set(1)
  assert_eq(h.lit(), (false, true))
  h.layer.set(3)
  assert_eq(h.lit(), (false, false), msg="passing nothing on now")
  h.layer.set(1)
  assert_eq(h.lit(), (false, true), msg="passing it on again")
}

///|
test "an old view's list drawn moved by a look of its own, in the window's tree: what scrolls there found where it is laid out, once, and the wheel scrolls it" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let list = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
      old(b, fn(c) {
        let l = c.list("rows", 30, 40.0, fn(k) {
          c.box(w=Fill(1.0), h=Px(40.0), id=c.id("row \{k}"), fn() { c.text("row \{k}", size=12.0) |> ignore }) |> ignore
        })
        list.val = l
        // (drawn moved, taken where it is laid out)
        c.look(l, look(dx=20.0))
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  let id = c.nodes[list.val].id
  let at = c.scroll_ids.search(id)
  assert_true(at is Some(_) && c.scroll_ids.filter(fn(s) { s == id }).length() == 1, msg="\{c.scroll_ids}")
  let k = at.unwrap() * 4
  assert_eq((c.scroll_rects[k], c.scroll_rects[k + 1]), (c.nodes[list.val].x, c.nodes[list.val].y))
  let before = t.list_offset()
  t.wheel(200.0, 150.0, 120.0)
  t.draw()
  assert_true(t.list_offset() > before, msg="\{t.list_offset()} from \{before}")
}

///|
test "the frame's targets found again only as what they are found from changes: an old view's colour painted anew alone, none; its button moved, once" {
  let ink = @signals.signal(0x777777FFL, same=fn(a, b) { a == b })
  let wide = @signals.signal(80.0, same=fn(a, b) { a == b })
  let button = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  // (a frame painted alone as it is, not built again whole to be compared with: what the Tester checks a frame by)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        let id = c.id("button")
        button.val = id
        c.clicked(id) |> ignore
        let i = c.box(w=Px(wide.get()), h=Px(40.0), id~, fn() {  })
        c.bg_by(i, fn() { ink.get() })
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (the frame after the first: built again, the one before it laid out otherwise)
  t.frame_at(t.time() + frame_period_default)
  let found = targets_finds.val
  ink.set(0x3366CCFFL)
  t.frame_at(t.time() + frame_period_default)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x3366CCFFL }))
  assert_eq(targets_finds.val, found, msg="painted anew alone")
  wide.set(120.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(targets_finds.val, found + 1)
  // (and pressed where it is now)
  match g().hit_ids.search(button.val) {
    Some(k) => assert_eq(g().hit_rects[k * 4 + 2] - g().hit_rects[k * 4], 120.0)
    None => fail("no target")
  }
}

///|
test "each old view's place among the frame's targets given out with them: one let go as a layer over the pointer goes, the other's still its own" {
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let layer = @signals.signal(true, same=fn(a, b) { a == b })
  let b_button = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.show(fn() { a_on.get() }, fn(v) {
      v.width(Is(Some(150.0))) |> ignore
      old(v, fn(c) {
        for k in 0..<3 {
          let id = c.id("a \{k}")
          c.clicked(id) |> ignore
          c.box(w=Px(40.0), h=Px(40.0), id~, fn() {  }) |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      old(v, fn(c) {
        let id = c.id("b")
        b_button.val = id
        c.clicked(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
        if layer.get() {
          c.overlay("over-all", modal=true, fn() { c.box(w=Px(400.0), h=Px(200.0), fn() {  }) |> ignore }) |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.move(180.0, 20.0)
  t.draw()
  a_on.set(false)
  layer.set(false)
  t.frame_at(t.time() + frame_period_default)
  // (between frames: each old view's range among the targets given out, its own ids in it)
  let c = g()
  for h in old_hits {
    assert_true(h.to <= c.hit_ids.length(), msg="\{h.from}..\{h.to} of \{c.hit_ids.length()}")
  }
  match c.hit_ids.search(b_button.val) {
    Some(k) => assert_true(old_hits.iter().any(fn(h) { k >= h.from && k < h.to }), msg="the button at \{k}")
    None => fail("the button no target")
  }
}
