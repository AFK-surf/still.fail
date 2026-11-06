// The new chat's pages with nothing to start on as nodes (new_empty_node.mbt), drawn as their old views are
// (new_first_station, new_none_up): each instance the same, at a page's width wide and narrow.

///|
/// What the window draws, each instance's numbers rounded to a hundredth, in one order.
fn empty_drawn(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) { a.map(fn(x) { ((x * 100.0).round() / 100.0).to_string() }).join(",") })
  all.sort()
  all
}

///|
/// Page `which` ("first", "none") `w` by 700, drawn by its old view (`node` false) or as nodes.
fn empty_tester(which : String, w : Double, node : Bool) -> @ui.Tester {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  if !node {
    let t = @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          c.box(style=@ui.css("w=Full h=Full"), fn() { if which == "first" { new_first_station(c) } else { new_none_up(c) } })
          |> ignore
        })
      },
      w~,
      h=700.0,
      platform=0,
    )
    t.draw()
    return t
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w~, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(p) {
      p.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      if which == "first" { new_first_station_node(p) } else { new_none_up_node(p) }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a new chat with no station at all, and with none up, as nodes: drawn as the old views, wide and narrow" {
  for which in ["first", "none"] {
    for w in [1000.0, 390.0] {
      let old = empty_drawn(empty_tester(which, w, false))
      assert_true(old.length() > 0, msg="\{which} \{w}: the old view draws it")
      let made = empty_drawn(empty_tester(which, w, true))
      let only_old = old.filter(fn(x) { !made.contains(x) })
      let only_new = made.filter(fn(x) { !old.contains(x) })
      assert_eq(made, old, msg="\{which} \{w}\nold only: \{only_old}\nnew only: \{only_new}")
    }
  }
}
