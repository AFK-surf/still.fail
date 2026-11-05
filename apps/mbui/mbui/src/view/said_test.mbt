// What a screen reader is told of a control turned off (View::turned_off): it read out as turned off and its press
// refused, what it holds that takes presses of its own read and pressed as ever.

///|
test "turned off: read out as turned off, a screen reader's press of it refused; a retry it holds read and pressed" {
  let pressed : Array[String] = []
  let ids : Map[String, @view.NodeId] = {}
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(card) {
        ids["card"] = card.id()
        card
        .width(Is(Some(200.0)))
        .height(Is(Some(80.0)))
        .presses(Is(true))
        .turned_off(Is(true))
        .says(Is(Some(@view.said(Button, label="文件"))))
        .on_press(fn() { pressed.push("card") })
        |> ignore
        card.box(fn(retry) {
          ids["retry"] = retry.id()
          retry
          .width(Is(Some(40.0)))
          .height(Is(Some(40.0)))
          .presses(Is(true))
          .says(Is(Some(@view.said(Button, label="重试"))))
          .on_press(fn() { pressed.push("retry") })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let disabled = fn(k : String) {
    tree.said_order().iter().find_first(fn(s) { s.id == ids[k] }).map(fn(s) { s.disabled })
  }
  let card = tree.activate_at(ids["card"], 10.0)
  let retry = tree.activate_at(ids["retry"], 20.0)
  assert_eq((disabled("card"), disabled("retry"), card, retry, pressed), (Some(true), Some(false), false, true, ["retry"]))
  tree.dispose()
}
