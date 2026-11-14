// A dialog in the middle of the window a share of it tall whose body is nodes (panel_nodes' `tall`, not `hugs`) beside
// the old one: a list filling it (panel_list_node's `fills` and panel_list's) and a button at its foot, on windows 600,
// 800 and 1000 tall; the dialog's top, its height, its foot's button and the list's first row where the old one's
// are, at rest and at each moment of its way in. The list's rows are link_row_node's beside link_row's: where the first
// row's words stand across at rest is theirs, the rows' rule in a panel's body (panel_row_at, panel_parts_node.mbt), not
// the dialog's; a change to how far in a row's words stand there fails this too.

///|
/// What the dialog stood as on a window 1200 by `h`, opened by nothing: the old one (`old`) or the node one, its
/// dialog's place and size, its button's, its first row's words, at each of `moments` after 打开 is pressed (its way
/// in) and at rest.
fn tall_dialog_stood(h : Double, old : Bool) -> Array[String] {
  let n = 40
  let open = fn(_from : Anchor) {
    if old {
      panel(
        "很长的单子",
        from=Unanchored,
        tall=0.86,
        foot=fn(c, _) { button(c, "完成", key="tall/done", tone=Primary, on_press=fn() {  }) |> ignore },
        fn(c, _) {
          panel_list(c, "tall/rows", n, 60.0, fills=true, fn(i) {
            link_row(c, "tall/row/\{i}", "第 \{i} 行", note="说明", on_press=fn() {  }) |> ignore
          })
          |> ignore
        },
      )
    } else {
      panel_nodes(
        "很长的单子",
        from=Unanchored,
        tall=0.86,
        foot=fn(v, _) { button_node(v, fn() { "完成" }, fn() {  }, tone=Primary) |> ignore },
        fn(v, _) {
          panel_list_node(
            v,
            fn() { Array::makei(n, fn(i) { i }) },
            fn(b, i) { link_row_node(b, fn() { "第 \{i} 行" }, fn() {  }, note=fn() { "说明" }) },
            est=60.0,
            fills=true,
          )
          |> ignore
        },
      )
    }
  }
  presenters_reset()
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w=1200.0,
    h~,
    platform=0,
  )
  t.check_looks(false)
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let rect = fn(r : (Double, Double, Double, Double)) { "\{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)}" }
  let stood : Array[String] = []
  let at = fn(when : String) {
    let dialog = t.all(Dialog, label="很长的单子").map(fn(s) { rect(s.rect) })
    let done = t.all(Button, label="完成").map(fn(s) { rect(s.rect) })
    let first = t.words().filter(fn(w) { w.0 == "第 0 行" }).map(fn(w) { "\{k(w.1)},\{k(w.2)} a\{k(w.5)}" })
    stood.push("\{when}: dialog \{@ui.list_text(dialog)} 完成 \{@ui.list_text(done)} first row \{@ui.list_text(first)}")
  }
  t.tap_text("打开")
  let from = t.time()
  for ms in [0.0, 40.0, 80.0, 120.0, 160.0, 200.0, 280.0, 360.0] {
    t.run_for(from + ms - t.time())
    at("\{ms}")
  }
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  at("at rest")
  stood
}

///|
test "a dialog in the middle of the window a share of it tall, holding nodes: as tall as the old one, its foot where the old one's is, on windows 600, 800 and 1000 tall, at rest and on its way in" {
  for h in [600.0, 800.0, 1000.0] {
    let old = tall_dialog_stood(h, true)
    let new = tall_dialog_stood(h, false)
    // (at rest: all of it the same)
    assert_eq(new[new.length() - 1], old[old.length() - 1], msg="\{h} tall, at rest: new \{new[new.length() - 1]} old \{old[old.length() - 1]}")
    // (on its way in: where the dialog and its foot are at each moment; its words' alpha is the tree's own reading, as
    // the other dialogs of nodes have it, not compared)
    let place = fn(s : String) {
      match s.find(" first row ") {
        Some(i) => s.exact_view(end=i).to_owned()
        None => s
      }
    }
    let (n, o) = (new.map(place), old.map(place))
    let differs = n.mapi(fn(i, x) { if x == o[i] { "" } else { "\n  new \{x}\n  old \{o[i]}" } }).join("")
    assert_eq(n, o, msg="\{h} tall, on its way in:\{differs}")
  }
}
