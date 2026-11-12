// A composer's ground changing shape for its cause in the window's tree (moves_for: Moves::reshapes, its send going
// with it, Moves::moves_with) drawn frame for frame where an old view's is (reshape and layout with the same `by`),
// the one way both work out (reshape_way.mbt): its ground's rect and corners and its send's place on the way and at
// the end; opened as a keyboard comes in the same change, from its foot; gone to another page with what it holds, a
// part new to it there carried on its ground; and nothing built or laid out again while it goes, the clock read no
// more at its declared end.

///|
/// The composer's ground's colour, its send's, and a part only another page's composer has.
let composer_ground : Int64 = 0x3366CCFFL

///|
let send_ground : Int64 = 0xCC3333FFL

///|
let extra_ground : Int64 = 0x20A040FFL

///|
/// How a composer is laid out: where across and down in a box 400 by 400, how wide and tall, how round; where its send
/// is in it (from its top left), and whether it has the part only another page's has.
priv struct ComposerLaid {
  x : Double
  y : Double
  w : Double
  h : Double
  r : Double
  send_x : Double
  send_y : Double
  extra : Bool
}

///|
/// The composer as `open`, `page` and the keyboard's height `kb` lay it out: shut a capsule at the foot (40 tall, round
/// as half that), open a box (120 tall, 16 round), on the second page lower and wider with a part of its own, its foot
/// held over the keyboard.
fn composer_laid(open : Bool, page : Int, kb : Double) -> ComposerLaid {
  let (w, h, r) = if open { (360.0, 120.0, 16.0) } else { (240.0, 40.0, 20.0) }
  let x = if page == 0 { 20.0 } else { 10.0 }
  let w = if page == 0 { w } else { w + 20.0 }
  let foot = if page == 0 { 390.0 } else { 370.0 }
  { x, y: foot - kb - h, w, h, r, send_x: w - 30.0, send_y: h - 30.0, extra: page == 1 }
}

///|
/// What each tells (its ground's rect and corners, its send's place, the extra part's place).
priv struct Inputs {
  open : @signals.Signal[Bool]
  page : @signals.Signal[Int]
  kb : @signals.Signal[Double]
}

///|
fn inputs() -> Inputs {
  {
    open: @signals.signal(false, same=fn(a, b) { a == b }),
    page: @signals.signal(0, same=fn(a, b) { a == b }),
    kb: @signals.signal(0.0, same=fn(a, b) { a == b }),
  }
}

///|
/// The cause the composer changes shape for, said as a value (an old view's `by`).
fn cause_of(i : Inputs) -> String {
  "\{i.open.get()}/\{i.page.get()}"
}

///|
/// How a composer goes by what its cause changed from and to (`per_cause`'s, composer): to another page as a Move
/// whose unit is twice as far (slower), carried; opened or shut as a Move, where it is.
fn cause_spec(was : String, now : String) -> Spec {
  if cause_carries(was, now) {
    moved(points=2.0)
  } else {
    moved()
  }
}

///|
fn cause_carries(was : String, now : String) -> Bool {
  was.split("/").to_array()[1] != now.split("/").to_array()[1]
}

///|
/// A composer an old view builds (reshape and layout by the cause, `carry` as it goes to another page, `foot` where
/// said), or the tree's (moves_for); `built` counts the tree's builds of it, `moves` holds what moves. `per_cause`: how
/// it goes and whether it is carried by what its cause changed from and to (cause_spec, cause_carries; the tree's
/// moves_for's spec_of and carry_of, an old view's spec and carry said as it is built). The Tester.
fn composer(
  i : Inputs,
  node : Bool,
  carry? : Bool = false,
  foot? : Bool = false,
  built? : Ref[Int] = Ref(0),
  moves? : Ref[Moves?] = Ref(None),
  old_over? : Ref[Double] = Ref(0.0),
  per_cause? : Bool = false,
) -> @ui.Tester {
  // (the old view's: the cause before the one it is built for now, and that one)
  let causes = Ref((cause_of(i), cause_of(i)))
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        let by = cause_of(i)
        if by != causes.val.1 {
          causes.val = (causes.val.1, by)
        }
        let (was, _) = causes.val
        let spec = if per_cause { cause_spec(was, by) } else { moved() }
        let carries = !per_cause || cause_carries(was, by)
        let l = composer_laid(i.open.get(), i.page.get(), i.kb.get())
        let was_page = i.page.get()
        old_over.val = reshaped_over(c, "t/composer")
        c.box(w=Px(400.0), h=Px(400.0), fn() {
          let mut send = -1
          let mut extra = -1
          let b = c.box(ml=l.x, mt=l.y, w=Px(l.w), h=Px(l.h), bg=composer_ground, radius=l.r, fn() {
            send = c.box(ml=l.send_x, mt=l.send_y, w=Px(20.0), h=Px(20.0), bg=send_ground, fn() {  })
            if l.extra {
              extra = c.box(ml=4.0, mt=-46.0, w=Px(16.0), h=Px(16.0), bg=extra_ground, fn() {  })
            }
          })
          reshape(c, b, "t/composer", by~, spec~, carry=carry && carries && was_page == 1, foot~)
          layout(c, send, "t/send", by~, spec~)
          if extra >= 0 {
            layout(c, extra, "t/extra", by~, spec~)
          }
        })
        |> ignore
      }
    },
    w=400.0,
    h=400.0,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(400.0))).height(Is(Some(400.0))) |> ignore
        o.box(fn(b) {
          built.val = built.val + 1
          let laid = fn() { composer_laid(i.open.get(), i.page.get(), i.kb.get()) }
          b
          .margin(By(fn() { (laid().x, laid().y, 0.0, 0.0) }))
          .width(By(fn() { Some(laid().w) }))
          .height(By(fn() { Some(laid().h) }))
          .ground(Is(composer_ground))
          .radius(By(fn() { laid().r }))
          |> ignore
          let send = b.box(fn(s) {
            s
            .margin(By(fn() { (laid().send_x, laid().send_y, 0.0, 0.0) }))
            .width(Is(Some(20.0)))
            .height(Is(Some(20.0)))
            .ground(Is(send_ground))
            |> ignore
          })
          let m = if per_cause {
            moves_for(b, fn() { cause_of(i) }, spec_of=cause_spec, carry_of=cause_carries)
          } else {
            moves_for(b, fn() { cause_of(i) })
          }
          m.reshapes(b, carry=fn() { carry && i.page.get() == 1 }, foot~)
          m.moves_with(send)
          b.show(fn() { laid().extra }, fn(e) {
            e.margin(Is((4.0, -46.0, 0.0, 0.0))).width(Is(Some(16.0))).height(Is(Some(16.0))).ground(Is(extra_ground)) |> ignore
            m.moves_with(e)
          })
          moves.val = Some(m)
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
/// What is drawn of the composer: its ground's rect and corners, its send's top left, the extra part's top left (-1
/// where none).
fn composer_seen(t : @ui.Tester) -> Array[Double] {
  let rects = t.drawn_rect_corners()
  let out = []
  match rects.iter().find_first(fn(r) { r.4 == composer_ground }) {
    Some(r) => {
      let (a, b, c, d) = r.5
      out.append([r.0, r.1, r.2, r.3, a, b, c, d])
    }
    None => out.append([-1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0, -1.0])
  }
  for k in [send_ground, extra_ground] {
    match rects.iter().find_first(fn(r) { r.4 == k }) {
      Some(r) => out.append([r.0, r.1])
      None => out.append([-1.0, -1.0])
    }
  }
  out
}

///|
/// Whether two things drawn are drawn alike, to a billionth of a point.
fn seen_alike(a : Array[Double], b : Array[Double]) -> Bool {
  a.length() == b.length() && a.iter().zip(b.iter()).all(fn(p) { (p.0 - p.1).abs() <= 1.0e-9 })
}

///|
/// The moments looked at after a change: on the way, and once all of it is over.
let looked_at : Array[Double] = [16.0, 40.0, 100.0, 200.0, 1000.0]

///|
/// The composer made as `start` sets its inputs, then changed by `change` (its inputs set in one batch), looked at each of looked_at: an old view's (its way
/// set off at its first frame after the change, 16 later) or the tree's. What is drawn at each, and (an old view's
/// reshaped_over, the tree's Moves::ground_over) how far over its laid top its ground is drawn then.
fn composer_way(
  node : Bool,
  change : (Inputs) -> Unit,
  start? : (Inputs) -> Unit = fn(_) {  },
  carry? : Bool = false,
  foot? : Bool = false,
  per_cause? : Bool = false,
) -> (Array[Array[Double]], Array[Double]) {
  let i = inputs()
  start(i)
  let moves : Ref[Moves?] = Ref(None)
  let old_over = Ref(0.0)
  let t = composer(i, node, carry~, foot~, moves~, old_over~, per_cause~)
  let lag = if node { 0.0 } else { 16.0 }
  let seen = [composer_seen(t)]
  let over = []
  let t0 = t.time()
  @signals.start_batch()
  change(i)
  @signals.end_batch()
  t.frame_at(t0 + 16.0)
  for at in looked_at {
    t.frame_at(t0 + lag + at)
    seen.push(composer_seen(t))
    over.push(
      match moves.val {
        Some(m) => m.ground_over()
        // (as the frame was built, after its way set off: what the app's composer reads, building it)
        None => old_over.val
      },
    )
  }
  (seen, over)
}

///|
/// Whether the tree's composer goes as an old view's does for `change`: each moment's drawing alike, and how far over
/// its laid top its ground is drawn.
fn goes_alike(
  change : (Inputs) -> Unit,
  start? : (Inputs) -> Unit = fn(_) {  },
  carry? : Bool = false,
  foot? : Bool = false,
  per_cause? : Bool = false,
) -> Unit raise {
  let (old, old_over) = composer_way(false, change, start~, carry~, foot~, per_cause~)
  let (new, new_over) = composer_way(true, change, start~, carry~, foot~, per_cause~)
  let same = Array::makei(old.length(), fn(k) { seen_alike(old[k], new[k]) })
  assert_eq(
    (same, seen_alike(old_over, new_over)),
    (Array::make(old.length(), true), true),
    msg="old \{Repr(old)}\nnode \{Repr(new)}\nover \{Repr(old_over)} \{Repr(new_over)}",
  )
}

///|
test "a composer opened, then shut again: its ground's rect and corners and its send where an old view's go, on the way and at the end" {
  goes_alike(fn(i) { i.open.set(true) })
  // (and shut from open, at rest)
  goes_alike(fn(i) { i.open.set(false) }, start=fn(i) { i.open.set(true) })
}

///|
test "a composer opened from its foot as a keyboard comes in the same change: the keyboard taken at once, its growing up on the way, where an old view's go, and as far over its laid top" {
  goes_alike(fn(i) {
    i.open.set(true)
    i.kb.set(60.0)
  }, foot=true)
}

///|
test "a composer gone to another page with what it holds: from where it was, its send with it, the part only that page has carried on its ground, where an old view's go; drawn over its laid top by nothing" {
  goes_alike(fn(i) { i.page.set(1) }, carry=true)
}

///|
test "a composer going by what its cause changed from and to (spec_of, carry_of): opened on its clock where it is, gone to another page on another carried, both in one change as the page's, opened on that page not carried; where an old view's go" {
  goes_alike(fn(i) { i.open.set(true) }, per_cause=true)
  goes_alike(fn(i) { i.page.set(1) }, carry=true, per_cause=true)
  goes_alike(fn(i) {
    i.open.set(true)
    i.page.set(1)
  }, carry=true, per_cause=true)
  goes_alike(fn(i) { i.open.set(true) }, start=fn(i) { i.page.set(1) }, carry=true, per_cause=true)
}

///|
test "a composer opening: nothing built or laid out again while it goes, the clock alone drawing it; at its declared end over, the clock read no more" {
  let i = inputs()
  let built = Ref(0)
  let moves : Ref[Moves?] = Ref(None)
  let t = composer(i, true, built~, moves~)
  let tree = @ui.view_tree().unwrap()
  let m = moves.val.unwrap()
  let t0 = t.time()
  i.open.set(true)
  t.frame_at(t0 + 16.0)
  let going = m.over()
  let before = tree.work()
  let built_before = built.val
  for at in [40.0, 100.0, 200.0] {
    t.frame_at(t0 + at)
  }
  let after = tree.work()
  let drawn_on = composer_seen(t)
  t.run_for(past_all_ms)
  assert_eq(
    (
      going,
      built.val - built_before,
      after.structure - before.structure,
      after.made - before.made,
      after.computes - before.computes,
      m.over(),
      tree.clock_read(),
    ),
    (false, 0, 0, 0, 0, true, false),
    msg="\{Repr(drawn_on)}",
  )
}
