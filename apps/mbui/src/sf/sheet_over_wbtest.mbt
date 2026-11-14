// One sheet over another on a phone's window (Small, a finger): the old frame's (panel) and the window's tree's
// (panel_nodes), each over each.

///|
/// A phone's window with a sheet (`under_node`: the tree's, else the old frame's) opened by 打开 and come to rest, then
/// another over it (`over_node`), come to rest; what each let go of as it closed unsaid, and what was pressed, in `said`.
/// The sheet under it holds `under_lines` lines; the one over it three and 按我 at its foot.
fn sheets_over(under_node : Bool, over_node : Bool, said : Array[String], under_lines? : Int = 8) -> @ui.Tester {
  let t = presenting_tester(phone, fn(_) {
    if under_node {
      panel_nodes("下面", from=Unanchored, gone=fn() { said.push("under gone") }, fn(v, _) {
        for i in 0..<under_lines {
          words_node(v, fn() { "下面第\{i + 1}行" }, fn() { paragraph }) |> ignore
        }
      })
    } else {
      panel("下面", from=Unanchored, gone=fn() { said.push("under gone") }, fn(c, _) {
        for i in 0..<under_lines {
          c.text("下面第\{i + 1}行", style=paragraph) |> ignore
        }
      })
    }
  })
  open_it(t)
  t.run_for(@ui.move_most_ms)
  if over_node {
    panel_nodes("上面", from=Unanchored, gone=fn() { said.push("over gone") }, fn(v, _) {
      for i in 0..<3 {
        words_node(v, fn() { "上面第\{i + 1}行" }, fn() { paragraph }) |> ignore
      }
      button_node(v, fn() { "按我" }, fn() { said.push("pressed") }) |> ignore
    })
  } else {
    panel("上面", from=Unanchored, gone=fn() { said.push("over gone") }, fn(c, _) {
      for i in 0..<3 {
        c.text("上面第\{i + 1}行", style=paragraph) |> ignore
      }
      button(c, "按我", key="press-me", on_press=fn() { said.push("pressed") }) |> ignore
    })
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "one sheet over another, each the old frame's or the window's tree's: one scrim dims what is under them" {
  for combo in [(false, false), (true, false), (false, true), (true, true)] {
    let (under_node, over_node) = combo
    let said : Array[String] = []
    let t = sheets_over(under_node, over_node, said)
    assert_eq(scrims_drawn(t, phone), 1, msg="under the tree's \{under_node}, over it the tree's \{over_node}")
  }
}

