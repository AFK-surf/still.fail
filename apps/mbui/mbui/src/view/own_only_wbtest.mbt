// What the tree draws otherwise than by itself (an old view hosted, glass, a native view's anchor), known of each node
// and all it holds as each is said (Tree::holds_own_only): what the scene draws in the window's terms.

///|
test "what holds something drawn otherwise than by the tree knows so as it is said, and no more once it is let go or unsaid" {
  let glass = @signals.signal(false)
  let anchor = @signals.signal("")
  let shown = @signals.signal(true)
  let ids : Map[String, NodeId] = {}
  let tree = Tree::new(
    fn(root) {
      root.box(fn(page) {
        ids["page"] = page.id()
        page.box(fn(card) {
          ids["card"] = card.id()
          card
          .width(Is(Some(40.0)))
          .height(Is(Some(20.0)))
          .glass(By(fn() {
            if glass.get() {
              Some(@paint.Glass::frosted(blur=10.0, tint=0L, solid=0L))
            } else {
              None
            }
          }))
          .native_anchor(By(fn() { anchor.get() }))
          |> ignore
        })
        |> ignore
        page.show(fn() { shown.get() }, fn(slot) {
          slot.box(fn(old) {
            ids["old"] = old.id()
            old.hosted() |> ignore
          })
          |> ignore
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(200.0, 100.0, now=0.0) |> ignore
  let holds = fn(name : String) { tree.holds_own_only(ids[name]) }
  // (an old view hosted under the page: the page holds it, the card does not)
  assert_eq((holds("page"), holds("card")), (true, false))
  // (its glass said, then a native view's anchor, then both unsaid: the card as each is)
  glass.set(true)
  tree.frame(200.0, 100.0, now=16.0) |> ignore
  assert_eq(holds("card"), true)
  anchor.set("map")
  glass.set(false)
  tree.frame(200.0, 100.0, now=32.0) |> ignore
  assert_eq(holds("card"), true)
  anchor.set("")
  tree.frame(200.0, 100.0, now=48.0) |> ignore
  assert_eq(holds("card"), false)
  // (the old view let go: the page holds nothing drawn otherwise; shown again, it does)
  shown.set(false)
  tree.frame(200.0, 100.0, now=64.0) |> ignore
  assert_eq(holds("page"), false)
  shown.set(true)
  tree.frame(200.0, 100.0, now=80.0) |> ignore
  assert_eq(holds("page"), true)
}
