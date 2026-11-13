// View::image_ask said in a change (env.mbt): asked of what hosts the tree as that change ends (Tree::change_ended), and
// only where the node that said it still stands then: one made and let go of in the change asks for nothing. The two
// ways a change makes and lets go of a node before anything draws it, as shared_test has them: a change told in two
// parts (Tree::event_said), and a room given two widths in one layout (View::by_room); and a change told outside every
// event, by a signal set between frames, ending as where things stand is settled after it (Tree::settle_now).

///|
/// The moment the scenes' changes are told at, after the tree's first frame.
let ask_at : Double = 100.0

///|
/// A tree made by `make` (on the clock `time`, where one is said: what is told carries its moment, as a host's does), the
/// pictures it asks of its host kept in `asked`, at its first frame.
fn ask_tree(
  make : (@view.View) -> Unit,
  asked : Array[String],
  before? : () -> Unit = fn() {  },
  time? : () -> Double,
) -> @view.Tree {
  let tree = @view.Tree::new(make, time?)
  tree.drawn_by(image_ask=fn(src, _) { asked.push(src) })
  before()
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  tree
}

///|
/// A box of its own in `parent`, shown while `on` says, asking for the picture `src` as it is made.
fn ask_shown(parent : @view.View, on : @signals.Signal[Bool], src : String, made : Ref[Int]) -> Unit {
  parent.show(fn() { on.get() }, fn(a) {
    made.val = made.val + 1
    a.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
    a.image_ask(src, 40.0)
  })
}

///|
test "a node made and let go of in one change told in two parts asks for nothing; one made in it that stands is asked as it is committed" {
  for stands in [false, true] {
    let first = @signals.signal(false, same=fn(a, b) { a == b })
    let second = @signals.signal(false, same=fn(a, b) { a == b })
    let (first_made, second_made) = (Ref(0), Ref(0))
    let asked : Array[String] = []
    let tree = ask_tree(
      fn(root) {
        root.box(fn(p) {
          ask_shown(p, first, "first.png", first_made)
          ask_shown(p, second, "second.png", second_made)
        })
        |> ignore
      },
      asked,
    )
    // (one change, told in two parts: the first made as its first part is told, let go of in its second, the second made
    // then where it `stands`; no layout between)
    tree.event_said(ask_at, fn() { first.set(true) }, fn() {
      first.set(false)
      second.set(stands)
    })
    // (that the scene is what it says: the first was made in that change)
    assert_eq(first_made.val, 1)
    // (asked by the end of that change, before any frame: as when it was asked as the node was made)
    assert_eq(asked, if stands { ["second.png"] } else { [] }, msg="stands \{stands}")
  }
}

///|
test "a node made at a room's first width and let go of at its share in the same layout asks for nothing; the one made at its share is asked" {
  let (wide_made, narrow_made) = (Ref(0), Ref(0))
  let made_before = Ref((-1, -1))
  let asked : Array[String] = []
  let _ = ask_tree(
    fn(root) {
      root.box(fn(row) {
        row.row(Is(true)).width(Is(Some(300.0))) |> ignore
        row.box(fn(side) { side.width(Is(Some(200.0))).height(Is(Some(10.0))).shrink(Is(0.0)) |> ignore }) |> ignore
        row.box(fn(cell) {
          cell.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          cell.by_room(fn(held, room) {
            held.show(fn() { room.width() >= 200.0 }, fn(a) {
              wide_made.val = wide_made.val + 1
              a.height(Is(Some(40.0))) |> ignore
              a.image_ask("wide.png", 40.0)
            })
            held.show(fn() { room.width() < 200.0 }, fn(b) {
              narrow_made.val = narrow_made.val + 1
              b.height(Is(Some(60.0))) |> ignore
              b.image_ask("narrow.png", 40.0)
            })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    asked,
    before=fn() { made_before.val = (wide_made.val, narrow_made.val) },
  )
  // (that the scene is what it says: the wide one was made in that layout, the narrow one stands)
  let said = "made before the first frame \{Repr(made_before.val)}; wide made \{wide_made.val}, narrow made \{narrow_made.val}, asked \{Repr(asked)}"
  assert_true(wide_made.val > 0 && narrow_made.val > 0, msg=said)
  assert_eq(asked, ["narrow.png"], msg=said)
}

///|
test "a node made by its room as a signal is set between frames, outside every event (a picture's bytes coming), asking for its picture: asked at that moment, as where things stand is settled, before the next frame" {
  let key = @signals.signal("", same=fn(a, b) { a == b })
  let asked : Array[String] = []
  // (the host's clock: what a binding is told carries its moment, as a host's tree's does)
  let clock = Ref(0.0)
  let tree = ask_tree(
    fn(root) {
      // (where things stand settled as each change is told, as a page that reads where it was laid out asks)
      root.laid_before_causes()
      // (made once its picture's key is here, by the room it is given, asking for its picture as it is made, as a file's
      // card's picture is: in the layout that settles where things stand after the change)
      root.show(fn() { key.get() != "" }, fn(s) {
        s.by_room(fn(n, _) {
          n.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
          n.image_ask(@signals.untracked(fn() { key.get() }), 40.0)
        })
        |> ignore
      })
    },
    asked,
    time=fn() { clock.val },
  )
  // (between frames, outside every event: no frame drawn after it)
  clock.val = ask_at
  key.set("bytes.png")
  assert_eq(asked, ["bytes.png"])
  // (and once: the next frame asks nothing more)
  tree.frame(390.0, 844.0, now=ask_at) |> ignore
  assert_eq(asked, ["bytes.png"])
}
