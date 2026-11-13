// A shared end that stays (View::shared's `stays`, shared.mbt): a thumbnail that stays in its list while the picture it
// opens comes over everything, flown from it and back to it, drawn nowhere while the picture lives.

///|
/// A page: a list 100 tall (cut to itself, 10 in) holding thumbnails 40 square side by side by ids `ids`, each staying
/// (View::shared's `stays`), covering its picture; over all of it while `open` is said, a picture 300 by 200 at (50, 300)
/// by the id `open` says, as `flight` flies it. The thumbnails made, by id; the picture made last.
priv struct StaysScene {
  tree : @view.Tree
  open : @signals.Signal[String]
  thumbs : Map[String, @view.View]
  big : Ref[@view.View?]
}

///|
fn stays_scene(ids? : Array[String] = ["a"], flight? : @view.Flight = straight, list_top? : Double = 0.0) -> StaysScene {
  let open = @signals.signal("", same=fn(a, b) { a == b })
  let thumbs : Map[String, @view.View] = Map([])
  let big : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(list) {
        list
        .height(Is(Some(100.0)))
        .offset(Is((0.0, list_top)))
        .row(Is(true))
        .padding(Is((10.0, 10.0, 10.0, 10.0)))
        .clips(Is(true))
        |> ignore
        for id in ids {
          list.box(fn(t) {
            thumbs[id] = t
            t
            .width(Is(Some(40.0)))
            .height(Is(Some(40.0)))
            .ground(Is(red))
            .radius(Is(8.0))
            .image_covers(Is(true))
            .shared(Is(id), flight, stays=true)
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      p.show(fn() { open.get() != "" }, fn(o) {
        o.over(Is(true)) |> ignore
        o.box(fn(b) {
          big.val = Some(b)
          b
          .offset(Is((50.0, 300.0)))
          .width(Is(Some(300.0)))
          .height(Is(Some(200.0)))
          .ground(Is(blue))
          .shared(By(fn() { open.get() }), flight)
          |> ignore
        })
        |> ignore
      })
    })
    |> ignore
  })
  { tree, open, thumbs, big }
}

///|
/// How opaque node `v` is drawn now (0 where it is not drawn).
fn alpha_of(t : @view.Tree, v : @view.View) -> Double {
  match t.drawn().iter().find_first(fn(d) { d.id == v.id() }) {
    Some(d) => d.alpha
    None => 0.0
  }
}

///|
test "a picture opened from a thumbnail that stays: flown from where the thumbnail was drawn, as it looked, not faded; the thumbnail kept in its room, drawn nowhere while the picture lives" {
  let p = stays_scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let thumb = p.thumbs["a"]
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_true(big.flies())
  // (at its cause: where the thumbnail was, as it looked, seen whole; the thumbnail there still, drawn nowhere)
  assert_eq(drawn_as(p.tree, big), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
  assert_true(thumb.alive())
  assert_eq(alpha_of(p.tree, thumb), 0.0)
  assert_eq(p.tree.flight_drawn("a").map(fn(f) { f.1 }), Some((8.0, 8.0, 8.0, 8.0)))
  // (half way: half way there, its corners half way)
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  assert_eq(drawn_as(p.tree, big).map(fn(d) { (d.0, d.1, d.2, d.3, d.4) }), Some((30.0, 155.0, 170.0, 120.0, 1.0)))
  assert_eq(p.tree.flight_drawn("a").map(fn(f) { f.1 }), Some((4.0, 4.0, 4.0, 4.0)))
  // (a picture in it drawn on the way as the thumbnail draws its own: covering its box)
  assert_eq(p.tree.drawn().iter().find_first(fn(d) { d.id == big.id() }).map(fn(d) { d.image_cover }), Some(true))
  // (there: where it is laid out; the thumbnail still drawn nowhere)
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_false(big.flies())
  assert_eq(drawn_as(p.tree, big), Some((50.0, 300.0, 300.0, 200.0, 1.0, blue)))
  assert_eq(p.tree.drawn().iter().find_first(fn(d) { d.id == big.id() }).map(fn(d) { d.image_cover }), Some(false))
  assert_eq(alpha_of(p.tree, thumb), 0.0)
  assert_eq(p.tree.flight_drawn("a"), None)
}

///|
test "the picture closed: the thumbnail flies back from where the picture was drawn to its room, drawn as it sets out; the picture drawn no more" {
  let p = stays_scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1500.0) |> ignore
  let big = p.big.val.unwrap()
  let thumb = p.thumbs["a"]
  p.tree.event(2000.0, fn() { p.open.set("") })
  p.tree.frame(400.0, 800.0, now=2000.0) |> ignore
  assert_false(big.alive())
  assert_true(thumb.flies())
  assert_eq(drawn_as(p.tree, thumb), Some((50.0, 300.0, 300.0, 200.0, 1.0, blue)))
  p.tree.frame(400.0, 800.0, now=2100.0) |> ignore
  assert_eq(drawn_as(p.tree, thumb).map(fn(d) { (d.0, d.1, d.2, d.3, d.4) }), Some((30.0, 155.0, 170.0, 120.0, 1.0)))
  p.tree.frame(400.0, 800.0, now=2200.0) |> ignore
  assert_false(thumb.flies())
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
}

///|
test "a flight with an end that stays drawn within that end's room as what held it cut it, opening to the window as it leaves" {
  // (the list moved up 30: the thumbnail's top 20 cut off by it)
  let p = stays_scene(list_top=-30.0)
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_eq(p.tree.lift_cut(big.id()), Some((0.0, 0.0, 400.0, 70.0)))
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  assert_eq(p.tree.lift_cut(big.id()), Some((0.0, 0.0, 400.0, 435.0)))
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_eq(p.tree.lift_cut(big.id()), None)
}

///|
test "the picture's id changed to another thumbnail's while it is open: none flies; the first drawn again at once, the other drawn nowhere; closed, back to the other" {
  let p = stays_scene(ids=["a", "b"])
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1500.0) |> ignore
  let (a, b) = (p.thumbs["a"], p.thumbs["b"])
  assert_eq((alpha_of(p.tree, a), alpha_of(p.tree, b)), (0.0, 1.0))
  p.tree.event(2000.0, fn() { p.open.set("b") })
  p.tree.frame(400.0, 800.0, now=2000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_false(big.flies() || a.flies() || b.flies())
  assert_eq((alpha_of(p.tree, a), alpha_of(p.tree, b)), (1.0, 0.0))
  p.tree.event(3000.0, fn() { p.open.set("") })
  p.tree.frame(400.0, 800.0, now=3000.0) |> ignore
  assert_true(b.flies())
  assert_false(a.flies())
}

///|
test "a thumbnail cut to nothing by what holds it: none flies, the picture comes and goes as it would; nor where none of its id stays" {
  // (the list moved up past the thumbnail)
  let p = stays_scene(list_top=-60.0)
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  assert_false(p.big.val.unwrap().flies())
  p.tree.event(2000.0, fn() { p.open.set("z") })
  p.tree.event(2100.0, fn() { p.open.set("") })
  p.tree.frame(400.0, 800.0, now=2100.0) |> ignore
  assert_false(p.thumbs["a"].flies())
}

///|
test "motion reduced: the picture there at once, the thumbnail drawn nowhere; closed, the thumbnail there again at once" {
  let p = stays_scene(flight=at_once)
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set("a") })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  let thumb = p.thumbs["a"]
  assert_false(big.flies())
  assert_eq(drawn_as(p.tree, big), Some((50.0, 300.0, 300.0, 200.0, 1.0, blue)))
  assert_eq(alpha_of(p.tree, thumb), 0.0)
  p.tree.event(2000.0, fn() { p.open.set("") })
  p.tree.frame(400.0, 800.0, now=2000.0) |> ignore
  assert_false(thumb.flies())
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
}

///|
test "the picture made anew for another thumbnail's in one change (stepped to the one beside it): none flies; the first drawn again at once, the other drawn nowhere" {
  let open = @signals.signal("", same=fn(a, b) { a == b })
  let thumbs : Map[String, @view.View] = Map([])
  let big : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(list) {
        list.height(Is(Some(100.0))).row(Is(true)).padding(Is((10.0, 10.0, 10.0, 10.0))).clips(Is(true)) |> ignore
        for id in ["a", "b"] {
          list.box(fn(t) {
            thumbs[id] = t
            t.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(red)).shared(Is(id), straight, stays=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      // (a picture a key, made anew as it steps)
      p.pick(at_once=true, fn() { open.get() }, fn(o, id) {
        if id != "" {
          o.over(Is(true)) |> ignore
          o.box(fn(b) {
            big.val = Some(b)
            b
            .offset(Is((50.0, 300.0)))
            .width(Is(Some(300.0)))
            .height(Is(Some(200.0)))
            .ground(Is(blue))
            .shared(Is(id), straight)
            |> ignore
          })
          |> ignore
        }
      })
    })
    |> ignore
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  tree.event(1000.0, fn() { open.set("a") })
  tree.frame(400.0, 800.0, now=1500.0) |> ignore
  let (a, b) = (thumbs["a"], thumbs["b"])
  assert_eq((alpha_of(tree, a), alpha_of(tree, b)), (0.0, 1.0))
  tree.event(2000.0, fn() { open.set("b") })
  tree.frame(400.0, 800.0, now=2000.0) |> ignore
  assert_false(big.val.unwrap().flies() || a.flies() || b.flies())
  assert_eq((alpha_of(tree, a), alpha_of(tree, b)), (1.0, 0.0))
  // (closed then: back to the one it shows)
  tree.event(3000.0, fn() { open.set("") })
  tree.frame(400.0, 800.0, now=3000.0) |> ignore
  assert_true(b.flies())
  assert_false(a.flies())
}

///|
/// A thumbnail "a" that stays (none where `thumb` is false) and over all of it, while `open` is said, a picture by id "a"
/// said `with_stays`, made anew where `tier` changes (as a viewer's layer is for another tier of the window): 300 by
/// 200 at (50, 300), or 200 by 100 at (20, 100) at tier 1. The tree, open, tier, the thumbnail, the picture made last.
fn with_stays_scene(
  thumb : Bool,
) -> (@view.Tree, @signals.Signal[Bool], @signals.Signal[Int], Ref[@view.View?], Ref[@view.View?]) {
  let open = @signals.signal(false)
  let tier = @signals.signal(0)
  let th : Ref[@view.View?] = Ref(None)
  let big : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(list) {
        list.height(Is(Some(100.0))).row(Is(true)).padding(Is((10.0, 10.0, 10.0, 10.0))) |> ignore
        if thumb {
          list.box(fn(t) {
            th.val = Some(t)
            t.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(red)).shared(Is("a"), straight, stays=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      p.pick(at_once=true, fn() { if open.get() { tier.get() } else { -1 } }, fn(o, k) {
        if k >= 0 {
          o.over(Is(true)) |> ignore
          o.box(fn(b) {
            big.val = Some(b)
            let (x, y, w, h) = if k == 0 { (50.0, 300.0, 300.0, 200.0) } else { (20.0, 100.0, 200.0, 100.0) }
            b
            .offset(Is((x, y)))
            .width(Is(Some(w)))
            .height(Is(Some(h)))
            .ground(Is(blue))
            .shared(Is("a"), straight, with_stays=true)
            |> ignore
          })
          |> ignore
        }
      })
    })
    |> ignore
  })
  (tree, open, tier, th, big)
}

///|
test "one that moves said with_stays made anew in the place of another of its id (a viewer's layer for another tier): there at once, no flight between; the thumbnail drawn nowhere still; closed, back to it" {
  let (tree, open, tier, th, big) = with_stays_scene(true)
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  tree.event(1000.0, fn() { open.set(true) })
  tree.frame(400.0, 800.0, now=1000.0) |> ignore
  assert_true(big.val.unwrap().flies(), msg="flown from the thumbnail")
  tree.frame(400.0, 800.0, now=2000.0) |> ignore
  let first = big.val.unwrap()
  assert_eq(drawn_as(tree, first), Some((50.0, 300.0, 300.0, 200.0, 1.0, blue)))
  tree.event(3000.0, fn() { tier.set(1) })
  tree.frame(400.0, 800.0, now=3000.0) |> ignore
  let again = big.val.unwrap()
  assert_true(!physical_equal(again, first) && !first.alive(), msg="made anew, the other let go of")
  assert_true(!again.flies(), msg="no flight between the two")
  assert_eq(drawn_as(tree, again), Some((20.0, 100.0, 200.0, 100.0, 1.0, blue)))
  assert_eq(alpha_of(tree, th.val.unwrap()), 0.0, msg="the thumbnail drawn nowhere still")
  tree.event(4000.0, fn() { open.set(false) })
  tree.frame(400.0, 800.0, now=4000.0) |> ignore
  assert_true(th.val.unwrap().flies(), msg="closed: the thumbnail flown back to")
  tree.frame(400.0, 800.0, now=5000.0) |> ignore
  assert_eq(drawn_as(tree, th.val.unwrap()), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
}

///|
test "one said with_stays, none of its id staying: made anew in the place of another, there at once, as without an id" {
  let (tree, open, tier, _, big) = with_stays_scene(false)
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  tree.event(1000.0, fn() { open.set(true) })
  tree.frame(400.0, 800.0, now=1000.0) |> ignore
  assert_true(!big.val.unwrap().flies())
  tree.event(2000.0, fn() { tier.set(1) })
  tree.frame(400.0, 800.0, now=2000.0) |> ignore
  assert_true(!big.val.unwrap().flies(), msg="no flight between the two")
  assert_eq(drawn_as(tree, big.val.unwrap()), Some((20.0, 100.0, 200.0, 100.0, 1.0, blue)))
}
