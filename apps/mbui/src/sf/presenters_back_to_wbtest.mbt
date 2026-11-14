// Two steps further in from a panel of nodes, each a panel of nodes its button opens as its panel closes (a preset's
// dialog, its 添加目录, the folder picker): back to the first in one change (panel_back's `to`), on a phone's sheet (its
// pages) and in a desk's dialogs (each a step further in from the one before), what the steps held let go of, the first
// not; the first's back closes it as ever.

///|
/// 第一 with its 往里 opening 第二, whose 再往里 opens 第三, whose 回到第一 goes back to the first; each one's going said.
fn panels_three_deep(said : Array[String]) -> (Anchor) -> Unit {
  fn(_) {
    let step = fn(title : String, words : String, button : String, press : () -> Unit, gone : String) {
      panel_nodes(
        title,
        fn(v, close) {
          words_node(v, fn() { words }, fn() { panel_note_words }) |> ignore
          button_node(v, fn() { button }, fn() {
            if button == "回到第一" {
              press()
            } else {
              close()
              press()
            }
          })
          |> ignore
        },
        from=Unanchored,
        gone=fn() { said.push(gone) },
      )
    }
    step(
      "第一",
      "第一的内容",
      "往里",
      fn() {
        step(
          "第二",
          "第二的内容",
          "再往里",
          fn() {
            step("第三", "第三的内容", "回到第一", fn() { panel_back(to=1) |> ignore }, "third gone")
          },
          "second gone",
        )
      },
      "first gone",
    )
  }
}

///|
fn back_to_first(at : (Int, Double, Double)) -> Unit raise {
  let said : Array[String] = []
  let t = presenting_tester(at, panels_three_deep(said))
  open_it(t)
  t.tap_text("往里")
  t.run_for(@ui.move_most_ms)
  t.tap_text("再往里")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第三的内容") is Some(_) && t.find("第一的内容") is None, msg="\{Repr(t.text_runs().map(fn(r) { r.text }))}")
  t.tap_text("回到第一")
  t.run_for(@ui.move_most_ms)
  assert_true(presenting())
  assert_true(t.find("第一的内容") is Some(_), msg="\{Repr(t.text_runs().map(fn(r) { r.text }))}")
  assert_true(t.find("第二的内容") is None && t.find("第三的内容") is None, msg="\{Repr(t.text_runs().map(fn(r) { r.text }))}")
  assert_eq(said, ["third gone", "second gone"])
  // (on the first: back closes it, nothing before it)
  if at.0 == 2 {
    t.back()
  } else {
    assert_true(t.key_named("esc"))
  }
  t.run_for(@ui.move_most_ms)
  assert_true(!presenting())
  assert_eq(said, ["third gone", "second gone", "first gone"])
}

///|
test "two steps further in, with a finger at Small: back to the first of the same sheet in one change" {
  back_to_first(phone)
}

///|
test "two steps further in, with a mouse at Large: back to the first dialog in one change" {
  back_to_first(desk)
}
