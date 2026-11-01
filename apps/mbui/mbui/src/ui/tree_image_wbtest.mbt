// A node of the window's tree's picture (View::image): drawn as the frame composes it, where it is drawn and as big,
// each frame, as an old view's picture is (draw_image): its decode the one for that size, asked for as one is, kept as
// one shown; drawn again as the host says one is decoded, with nothing else of it said.

///|
/// The pictures the frame just drawn has `w` × `h` (each instance's numbers, all of them).
fn pictures_sized(w : Double, h : Double) -> Array[Array[Double]] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let at = k * inst_size
    if c.inst[at + 5] == 4.0 && (c.inst[at + 2] - w).abs() < 1.0e-9 && (c.inst[at + 3] - h).abs() < 1.0e-9 {
      out.push(Array::makei(inst_size, fn(i) { c.inst[at + i] }))
    }
  }
  out
}

///|
/// The picture "pic" (600 by 400) 60 by 40 at (100, 100), seen at `alpha`: by an old view (Ctx::picture), else by a node
/// of the window's tree (View::image); decoded as the host says it is: the pictures 60 by 40 drawn.
fn picture_drawn(old : Bool, alpha : Double) -> Array[Array[Double]] {
  let t = if old {
    Tester::new(
      fn(c) {
        c.box(opacity=alpha, w=Fill(1.0), h=Fill(1.0), fn() {
          c.picture("pic", x=100.0, y=100.0, w=60.0, h=40.0, max_px=4096) |> ignore
        })
        |> ignore
      },
      images=[("pic", 600, 400)],
    )
  } else {
    let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)])
    set_view_app(fn(root) {
      root.box(fn(h) {
        h.alpha(Is(alpha)) |> ignore
        h.box(fn(n) {
          n.offset(Is((100.0, 100.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some(("pic", "", 4096)))) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    t
  }
  t.draw()
  t.run_for(image_fade_ms)
  pictures_sized(60.0, 40.0)
}

///|
test "a node's picture: the instances an old view's picture draws, whole and half seen" {
  for alpha in [1.0, 0.5] {
    let old = picture_drawn(true, alpha)
    assert_eq(old.length(), 1, msg="\{alpha}: the old view's picture drawn")
    assert_eq(picture_drawn(false, alpha), old, msg="\{alpha}: the node's the same")
  }
}

///|
test "a node's picture drawn frame after frame with nothing changed, the pictures kept past their budget: another's not shown let go, its own kept and drawn the same; its instance the node's" {
  let node : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)])
  set_view_app(fn(root) {
    root.box(fn(n) {
      node.val = Some(n.id())
      n.offset(Is((100.0, 100.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some(("pic", "", 4096)))) |> ignore
    })
    |> ignore
  })
  inst_owners.track = true
  t.draw()
  t.run_for(image_fade_ms)
  let shown = pictures_sized(60.0, 40.0)
  assert_eq(shown.length(), 1, msg="drawn")
  // (its instance the node's)
  let c = g()
  let mut owned = false
  for k in 0..<c.ninst {
    if c.inst[k * inst_size + 5] == 4.0 {
      owned = inst_owners.tree.get(k).unwrap_or(None) == Some(node.val.unwrap())
    }
  }
  assert_true(owned, msg="its picture's instance the node's")
  // (another picture decoded, big, shown by nothing: the pictures kept past their budget)
  image_cache["big"] = [
    {
      id: 999999,
      px: 8192,
      state: 1,
      w: 8192.0,
      h: 8192.0,
      ow: 8192.0,
      oh: 8192.0,
      used: 0,
      ready_at: 0.0,
      follows: None,
      mover: Mover::new(),
      fade_told: false,
    },
  ]
  let mut total = 0.0
  for _, list in image_cache {
    for e in list {
      total = total + e.w * e.h * 4.0
    }
  }
  assert_true(total > image_budget, msg="past the budget: \{total}")
  for _ in 0..<5 {
    t.frame_at(t.time() + frame_period_default)
  }
  g().trim_images()
  assert_true(!image_cache.contains("big"), msg="the one shown by nothing let go")
  assert_eq(image_state("pic"), 1, msg="its own kept")
  assert_eq(pictures_sized(60.0, 40.0), shown, msg="drawn the same")
}

///|
/// The picture "pic" 60 by 40 at (100, 100) by a node drawn at `own` its size, in one drawn at `holder` its: the pictures
/// drawn, where and how big.
fn picture_scaled(own : Double, holder : Double) -> Array[(Double, Double, Double, Double)] {
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)])
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.scale(Is(holder), about=@view.At(0.0, 0.0)) |> ignore
      h.box(fn(n) {
        n
        .offset(Is((100.0, 100.0)))
        .width(Is(Some(60.0)))
        .height(Is(Some(40.0)))
        .scale(Is(own), about=@view.At(0.0, 0.0))
        .image(Is(Some(("pic", "", 4096))))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(image_fade_ms)
  t.drawn_images().map(fn(i) { (i[0], i[1], i[2], i[3]) })
}

///|
test "a node's picture drawn smaller, by itself or by what holds it: where it is drawn and as big, once" {
  assert_eq(picture_scaled(1.0, 1.0), [(100.0, 100.0, 60.0, 40.0)])
  assert_eq(picture_scaled(0.5, 1.0), [(100.0, 100.0, 30.0, 20.0)], msg="itself")
  assert_eq(picture_scaled(1.0, 0.5), [(50.0, 50.0, 30.0, 20.0)], msg="what holds it")
}

///|
/// A node 60 by 40 at (100, 100) drawing a line down its left (from (0, 0) to (10, 40)) and the picture "pic", turned
/// about the middle of what it draws: where it turns about, its picture not decoded yet (the line alone drawn), and once
/// it is (the line and the picture).
fn turned_about() -> ((Double, Double), (Double, Double)) raise {
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)], finish=false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .offset(Is((100.0, 100.0)))
      .width(Is(Some(60.0)))
      .height(Is(Some(40.0)))
      .lines(Is([@paint.line([(0.0, 0.0), (10.0, 40.0)], width=2.0, color=0x336699FFL)]))
      .image(Is(Some(("pic", "", 4096))))
      .turn(Is(0.3), drawn=true)
      |> ignore
    })
    |> ignore
  })
  let about = fn() {
    let c = g()
    let mut at = (0.0, 0.0)
    for k in 0..<c.ninst {
      let b = k * inst_size
      if c.inst[b + 32] != 0.0 {
        at = (c.inst[b + 33], c.inst[b + 34])
      }
    }
    at
  }
  t.draw()
  let before = about()
  for p in t.pending() {
    if p.0 == 1 {
      t.finish(1, p.1)
    }
  }
  t.draw()
  t.run_for(image_fade_ms)
  (before, about())
}

///|
test "a node's picture turned about the middle of what it draws: what it drew, the picture once drawn, not before" {
  let (before, after) = turned_about()
  // (the line's instance 98 … 112 by 98 … 142: its width and the edge round it, line.mbt's; the picture 100 … 160 by
  // 100 … 140)
  assert_eq(before, (105.0, 120.0), msg="the line alone: about its middle")
  assert_eq(after, (129.0, 120.0), msg="the line and the picture: about the middle of both")
}

///|
test "a node's picture drawn at no size (scaled to 0) and turned about what it draws: where it turns about a point, never not a number" {
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)])
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .offset(Is((100.0, 100.0)))
      .width(Is(Some(60.0)))
      .height(Is(Some(40.0)))
      .lines(Is([@paint.line([(0.0, 0.0), (10.0, 40.0)], width=2.0, color=0x336699FFL)]))
      .image(Is(Some(("pic", "", 4096))))
      .scale(Is(0.0))
      .turn(Is(0.3), drawn=true)
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let c = g()
  let mut turned = 0
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 32] != 0.0 {
      turned += 1
      let (px, py) = (c.inst[b + 33], c.inst[b + 34])
      assert_true(px == px && py == py, msg="about (\{px}, \{py})")
    }
  }
  assert_true(turned > 0, msg="what it drew turned")
}

///|
test "a node's picture nothing of which is seen yet (what holds it at no alpha): its decode asked for all the same, none drawn; seen, drawn from it" {
  let seen = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, images=[("pic", 600, 400)], finish=false)
  set_view_app(fn(root) {
    root.box(fn(h) {
      h.alpha(By(fn() { seen.get() })) |> ignore
      h.box(fn(n) {
        n.offset(Is((100.0, 100.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some(("pic", "", 4096)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let asked = t.pending().filter(fn(p) { p.0 == 1 })
  assert_eq(asked.length(), 1, msg="asked for unseen")
  assert_eq(pictures_sized(60.0, 40.0).length(), 0, msg="none drawn unseen")
  t.finish(1, asked[0].1)
  seen.set(1.0)
  t.draw()
  assert_eq(pictures_sized(60.0, 40.0).length(), 1, msg="seen: drawn")
}
