///|
/// Where a device meets it: 小屏's Home with 设置 opened over it. Telling Home's nodes whether each takes input, one cell
/// told ran what laid the tree out at its moment; that layout left Home's page out of its row, and that page's own
/// telling said all of it takes none; the walk then went on into the page with what it had found above before, and
/// told a chat row's agents' marks under it they take input. Here so: a node `y` in a page that a row leaves out once
/// `narrow` is said, read by what says it as `y` comes to take input and lays the tree out at once (View::shown_across,
/// Tree::laid_now); `n` beside it in the page, walked after it.
test "a layout run as one node is told it takes input, leaving out of its row the page that holds it: what that page holds after it told it takes none" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let narrow = @signals.signal(false, same=fn(a, b) { a == b })
  let page : Ref[View?] = Ref(None)
  let below : Ref[View?] = Ref(None)
  let stops : Array[() -> Unit] = []
  let t = Tree::new(
    fn(root) {
      root.box(fn(w) {
        w.presses(By(fn() { on.get() })) |> ignore
        w.box(fn(row) {
          row
          .row(Is(true))
          .fits(Is(true))
          .width(By(fn() { Some(if narrow.get() { 120.0 } else { 300.0 }) }))
          .height(Is(Some(20.0)))
          |> ignore
          row.box(fn(k) { k.width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore }) |> ignore
          page.val = Some(
            row.box(fn(p) {
              p.width(Is(Some(150.0))).height(Is(Some(20.0))).drops(Is(1)) |> ignore
              p.box(fn(y) {
                y.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
                stops.push(
                  @signals.effect(fn() {
                    if y.takes_input() {
                      narrow.set(true)
                      @signals.untracked(fn() { y.shown_across() }) |> ignore
                    }
                  }),
                )
              })
              |> ignore
              below.val = Some(
                p.box(fn(n) {
                  n.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
                  @signals.untracked(fn() { n.takes_input() }) |> ignore
                }),
              )
            }),
          )
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let n = below.val.unwrap()
  assert_false(@signals.untracked(fn() { n.takes_input() }))
  on.set(true)
  t.frame(390.0, 844.0) |> ignore
  assert_true(page.val.unwrap().left_out())
  assert_false(@signals.untracked(fn() { n.takes_input() }), msg="told it takes input, in a page left out of its row")
  for s in stops {
    s()
  }
}
