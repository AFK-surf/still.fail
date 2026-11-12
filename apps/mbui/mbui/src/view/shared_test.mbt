// Shared elements (View::shared, shared.mbt): paired by the change that lets one go and makes the other, flown from
// where the old one was drawn then, each moment's picture a function of that moment alone.

///|
/// A flight 200 ms long whatever its length, straight along.
let straight : @view.Flight = { way: fn(_) { (200.0, fn(ms) { ms / 200.0 }) } }

///|
/// None at all: there at once (motion reduced).
let at_once : @view.Flight = { way: fn(_) { (0.0, fn(_) { 1.0 }) } }

///|
let red : Int64 = 0xFF0000FFL

///|
let blue : Int64 = 0x0000FFFFL

///|
let green : Int64 = 0x00FF00FFL

///|
/// A page: a list 100 tall (cut to itself) holding a thumbnail 40 square at (10, 10) while `open` is not, then a detail
/// 200 tall holding one 100 tall as wide as it is (less 10 each side) while `open` is, then a bar 50 tall: the
/// thumbnail by `thumb_id`, the detail's by `big_id`, as `flight` flies them; the thumbnail leaving over `leave`. What
/// each made last is kept, and how many times each was pressed.
priv struct Scene {
  tree : @view.Tree
  open : @signals.Signal[Bool]
  thumb : Ref[@view.View?]
  big : Ref[@view.View?]
  detail : Ref[@view.View?]
  bar : Ref[@view.View?]
  thumb_pressed : Ref[Int]
  big_pressed : Ref[Int]
}

///|
fn scene(
  thumb_id? : String = "a",
  big_id? : String = "a",
  flight? : @view.Flight = straight,
  leave? : Double = 0.0,
) -> Scene {
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let thumb : Ref[@view.View?] = Ref(None)
  let big : Ref[@view.View?] = Ref(None)
  let detail : Ref[@view.View?] = Ref(None)
  let bar : Ref[@view.View?] = Ref(None)
  let thumb_pressed = Ref(0)
  let big_pressed = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(list) {
        list.height(Is(Some(100.0))).padding(Is((10.0, 10.0, 10.0, 10.0))).clips(Is(true)) |> ignore
        list.show(
          fn() { !open.get() },
          fn(t) {
            thumb.val = Some(t)
            t
            .width(Is(Some(40.0)))
            .height(Is(Some(40.0)))
            .ground(Is(red))
            .shared(Is(thumb_id), flight)
            .on_press(fn() { thumb_pressed.val = thumb_pressed.val + 1 })
            |> ignore
          },
          leave~,
        )
      })
      |> ignore
      p.box(fn(d) {
        detail.val = Some(d)
        d.height(Is(Some(200.0))).padding(Is((10.0, 10.0, 10.0, 10.0))).clips(Is(true)) |> ignore
        d.show(fn() { open.get() }, fn(b) {
          big.val = Some(b)
          b
          .height(Is(Some(100.0)))
          .ground(Is(blue))
          .shared(Is(big_id), flight)
          .on_press(fn() { big_pressed.val = big_pressed.val + 1 })
          |> ignore
        })
      })
      |> ignore
      p.box(fn(b) {
        bar.val = Some(b)
        b.height(Is(Some(50.0))).ground(Is(green)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  { tree, open, thumb, big, detail, bar, thumb_pressed, big_pressed }
}

///|
/// Node `v` as drawn now: where, how big, how opaque, its ground.
fn drawn_as(t : @view.Tree, v : @view.View) -> (Double, Double, Double, Double, Double, Int64)? {
  // (to a millionth of a point: what is worked out in steps comes out a hair off)
  let r = fn(x : Double) { (x * 1.0e6).round() / 1.0e6 }
  t
  .drawn()
  .iter()
  .find_first(fn(d) { d.id == v.id() })
  .map(fn(d) { (r(d.x), r(d.y), r(d.w), r(d.h), r(d.alpha), d.ground) })
}

///|
/// Where node `v` is in what is drawn (its index), -1 nowhere.
fn drawn_index(t : @view.Tree, v : @view.View) -> Int {
  t.drawn().search_by(fn(d) { d.id == v.id() }).unwrap_or(-1)
}

///|
test "the detail flies from where the thumbnail was drawn as it opened to where it is laid out, the thumbnail on the same way under it" {
  let p = scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let thumb = p.thumb.val.unwrap()
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_true(big.flies())
  // (at its cause: both where the thumbnail was, as it looked; the detail not in yet)
  assert_eq(drawn_as(p.tree, big), Some((10.0, 10.0, 40.0, 40.0, 0.0, red)))
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
  // (half way: half way there, as big, its ground half way; the detail in, the thumbnail not yet out, under it)
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  assert_eq(drawn_as(p.tree, big), Some((10.0, 60.0, 210.0, 70.0, 1.0, 0xB400B4FFL)))
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 60.0, 210.0, 70.0, 1.0, 0xB400B4FFL)))
  assert_true(drawn_index(p.tree, thumb) < drawn_index(p.tree, big))
  // (there: where it is laid out, as it looks; the thumbnail let go of)
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_false(big.flies())
  assert_false(thumb.alive())
  assert_eq(drawn_as(p.tree, big), Some((10.0, 110.0, 380.0, 100.0, 1.0, blue)))
}

///|
test "the same moments drawn with no frame between them: the same pictures" {
  let p = scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set(true) })
  // (no frame at its cause: the first at half way)
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  let big = p.big.val.unwrap()
  assert_eq(drawn_as(p.tree, big), Some((10.0, 60.0, 210.0, 70.0, 1.0, 0xB400B4FFL)))
}

///|
test "on its way it is drawn over the rest of its page, cut by nothing that holds it, and pressed where it is drawn" {
  let p = scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  let big = p.big.val.unwrap()
  let detail = p.detail.val.unwrap()
  let bar = p.bar.val.unwrap()
  // (after the bar, out of the detail that cuts it)
  assert_true(drawn_index(p.tree, big) > drawn_index(p.tree, bar))
  assert_false(p.tree.holds_in_order(detail.id(), big.id()))
  // (pressed where it is drawn, over the list it is drawn on; its old copy takes nothing)
  assert_true(p.tree.press(115.0, 95.0))
  assert_eq(p.big_pressed.val, 1)
  assert_eq(p.thumb_pressed.val, 0)
  // (there: in its place among the rest again)
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_true(drawn_index(p.tree, big) < drawn_index(p.tree, bar))
  assert_true(p.tree.holds_in_order(detail.id(), big.id()))
}

///|
test "closed on its way: back from where it is drawn then, the first flight's old copy let go of at once" {
  let p = scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let first = p.thumb.val.unwrap()
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1050.0) |> ignore
  p.tree.event(1100.0, fn() { p.open.set(false) })
  p.tree.frame(400.0, 800.0, now=1100.0) |> ignore
  assert_false(first.alive())
  let thumb = p.thumb.val.unwrap()
  assert_true(thumb.flies())
  assert_eq(drawn_as(p.tree, thumb).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((10.0, 60.0, 210.0, 70.0)))
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_eq(drawn_as(p.tree, thumb).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((10.0, 35.0, 125.0, 55.0)))
  p.tree.frame(400.0, 800.0, now=1300.0) |> ignore
  assert_false(thumb.flies())
  assert_eq(drawn_as(p.tree, thumb), Some((10.0, 10.0, 40.0, 40.0, 1.0, red)))
}

///|
test "the window made narrower on its way: it goes on to where it is laid out now, not set off again" {
  let p = scene()
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  p.tree.frame(300.0, 800.0, now=1100.0) |> ignore
  let big = p.big.val.unwrap()
  // (as far off its place as half of how far it set out from: its place 280 wide now)
  assert_eq(drawn_as(p.tree, big).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((10.0, 60.0, 110.0, 70.0)))
  p.tree.frame(300.0, 800.0, now=1200.0) |> ignore
  assert_false(big.flies())
  assert_eq(drawn_as(p.tree, big).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((10.0, 110.0, 280.0, 100.0)))
}

///|
test "one gone and another come by other ids: none flies, what went let go of as the change ends" {
  let p = scene(thumb_id="a", big_id="b")
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let thumb = p.thumb.val.unwrap()
  p.tree.event(1000.0, fn() { p.open.set(true) })
  assert_false(thumb.alive())
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_false(big.flies())
  assert_eq(drawn_as(p.tree, big), Some((10.0, 110.0, 380.0, 100.0, 1.0, blue)))
}

///|
test "what leaves by itself flies instead where it pairs, its leaving none" {
  let p = scene(leave=300.0)
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let thumb = p.thumb.val.unwrap()
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  assert_true(thumb.alive())
  assert_false(thumb.leaving())
  assert_true(thumb.flies())
  p.tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_false(thumb.alive())
}

///|
test "motion reduced: there at once, the old one let go of" {
  let p = scene(flight=at_once)
  p.tree.frame(400.0, 800.0, now=0.0) |> ignore
  let thumb = p.thumb.val.unwrap()
  p.tree.event(1000.0, fn() { p.open.set(true) })
  p.tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let big = p.big.val.unwrap()
  assert_false(big.flies())
  assert_false(thumb.alive())
  assert_eq(drawn_as(p.tree, big), Some((10.0, 110.0, 380.0, 100.0, 1.0, blue)))
}

///|
test "a row of a list flies to the detail as it is picked, from its own place" {
  let picked : @signals.Signal[Int?] = @signals.signal(None, same=fn(a, b) { a == b })
  let rows : Map[Int, @view.View] = Map([])
  let big : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.grow(Is(1.0)) |> ignore
      p.box(fn(list) {
        list.each(fn() { [1, 2, 3] }, fn(k) { k }, fn(r, item) {
          r.height(Is(Some(50.0))).padding(Is((10.0, 5.0, 10.0, 5.0))) |> ignore
          let k = item.get()
          r.show(fn() { picked.get() != Some(k) }, fn(t) {
            rows[k] = t
            t.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(red)).shared(Is("row \{k}"), straight) |> ignore
          })
        })
      })
      |> ignore
      p.box(fn(d) {
        d.pick(fn() { picked.get() }, fn(b, k) {
          match k {
            Some(k) => {
              big.val = Some(b)
              b.height(Is(Some(100.0))).ground(Is(blue)).shared(Is("row \{k}"), straight) |> ignore
            }
            None => ()
          }
        })
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(400.0, 800.0, now=0.0) |> ignore
  let row = rows[2]
  assert_eq(drawn_as(tree, row).map(fn(d) { (d.0, d.1) }), Some((10.0, 55.0)))
  tree.event(1000.0, fn() { picked.set(Some(2)) })
  tree.frame(400.0, 800.0, now=1000.0) |> ignore
  let b = big.val.unwrap()
  assert_true(b.flies())
  assert_eq(drawn_as(tree, b).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((10.0, 55.0, 40.0, 40.0)))
  // (the other rows none of it)
  assert_true(rows[1].alive() && !rows[1].flies())
  tree.frame(400.0, 800.0, now=1200.0) |> ignore
  assert_eq(drawn_as(tree, b).map(fn(d) { (d.0, d.1, d.2, d.3) }), Some((0.0, 150.0, 400.0, 100.0)))
}

///|
test "two of an id made at once: a fault, told, the change still ended whole" {
  // (told, not stopped (boundary_test's faults_kept): a test that stopped here stopped in the middle of the change, its
  // batch never ended, and every test after it in the process ran on a graph that told nothing: 185 of view's 435 on
  // wasm-gc, 2026-11-11)
  let told = faults_kept(fn() {
    let tree = @view.Tree::new(fn(root) {
      root.show(fn() { true }, fn(s) {
        s.box(fn(a) { a.shared(Is("x"), straight) |> ignore }) |> ignore
        s.box(fn(b) { b.shared(Is("x"), straight) |> ignore }) |> ignore
      })
    })
    tree.frame(400.0, 800.0, now=0.0) |> ignore
  })
  assert_eq(told, ["shared: x let go of or made more than once in one change"])
  assert_eq(@signals.batch_depth(), 0, msg="the change it faulted in ended")
}
