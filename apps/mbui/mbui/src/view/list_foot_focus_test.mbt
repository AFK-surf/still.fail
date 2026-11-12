// A page's list at its foot whose foot holds a field the app gives the focus (not a press): what is pinned is in sight
// by being pinned, so bringing it into sight asks nothing of the list, which stays at its foot. The foot growing after,
// and the room it shows in shrinking (a keyboard come up), the last block stays on the foot's top at every moment. In one
// jump and at 60, 120, 24 and 7 a second.

///|
/// How tall each block is, the room the list shows in before and after a keyboard, and the foot before and after it
/// grows a line.
let ff_tall : Double = 40.0

///|
let ff_room : Double = 400.0

///|
let ff_room_kb : Double = 200.0

///|
let ff_foot : Double = 60.0

///|
let ff_foot_more : Double = 92.0

///|
priv struct FfCase {
  tree : @view.Tree
  scroll : @view.Scroll
  count : @signals.Signal[Int]
  room : @signals.Signal[Double]
  foot : @signals.Signal[Double]
  field : Ref[@view.NodeId?]
}

///|
/// A page's list 300 wide, as tall as `room`, of `count` blocks 40 tall (30 at first; words 行k at each one's top),
/// following its foot where `follows` (else at its top), its foot as tall as `foot` holding a field that takes the
/// focus, or block `block_field` taking it instead; what floats over its top `top_cover` tall (its bar kept clear of
/// it). Drawn once, at 0.
fn ff_case(follows? : Bool = true, block_field? : Int = -1, top_cover? : Double = 0.0) -> FfCase {
  let scroll = @view.Scroll::list()
  let room = @signals.signal(ff_room, same=fn(a, b) { a == b })
  let foot = @signals.signal(ff_foot, same=fn(a, b) { a == b })
  let field : Ref[@view.NodeId?] = Ref(None)
  let count = @signals.signal(30, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(room.get()) })) |> ignore
      o.scrolls_window(
        scroll,
        fn() { Array::makei(count.get(), fn(i) { i }) },
        est=ff_tall,
        follows=fn() { follows },
        bar_clear=fn() { (top_cover, 0.0) },
        foot=fn(f) {
          f.box(fn(b) {
            if block_field < 0 {
              field.val = Some(b.id())
            }
            b.height(By(fn() { Some(foot.get()) })).focusable(Is(true)) |> ignore
          })
          |> ignore
        },
        fn(b, k) {
          b.height(Is(Some(ff_tall))).words(Is("行\{k}")) |> ignore
          if k == block_field {
            field.val = Some(b.id())
            b.focusable(Is(true)) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, count, room, foot, field }
}

///|
/// How far the last block's foot is over the foot's top, as drawn (0: on it).
fn ff_gap(c : FfCase) -> Double {
  let y = rc_y(c.tree, "行\{c.count.untracked() - 1}")
  c.room.untracked() - c.foot.untracked() - (y + ff_tall)
}

///|
test "a page's list at its foot, its foot's field given the focus by the app, then the foot grown and the room shrunk: the last block on the foot's top at every moment, at every rate" {
  for rate in rc_rates {
    let c = ff_case()
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    let events = [
      (at, fn() { c.tree.focus_to(Some(id)) |> ignore }),
      (at + 400.0, fn() { c.foot.set(ff_foot_more) }),
      (at + 800.0, fn() { c.room.set(ff_room_kb) }),
    ]
    let looks = rc_looks(at + 1200.0)
    let gaps = rc_walk(c.tree, events, looks, rate, fn() { ff_gap(c) })
    for i, g in gaps {
      assert_true(g.abs() < 0.5, msg="at \{rate} a second, at \{looks[i]}: the last block \{g} over the foot's top")
    }
  }
}
