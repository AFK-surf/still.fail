// The fill chip, an allowance's chips and a tile as nodes (fill_chip_node.mbt, mark_node.mbt's tile_avatar_node)
// drawn as the old views are (fill_chip, quota_chips, tile_avatar), each instance the same.

///|
/// What `old` draws as an old view and `node` as nodes, each in a row from the window's corner, as marks_drawn reads
/// them.
fn drawn_both(old : (@ui.Ctx) -> Unit, node : (@view.View) -> Unit) -> (Array[String], Array[String]) {
  let o = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { c.box(style=@ui.css("row align=AStart"), fn() { old(c) }) |> ignore })
    },
    w=400.0,
    h=200.0,
    platform=0,
  )
  o.draw()
  let a = marks_drawn(o)
  let n = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(r) {
      r.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
      node(r)
    })
    |> ignore
  })
  n.draw()
  (a, marks_drawn(n))
}

///|
test "a fill chip as a node: its ground, its fill as far as it is full in its level's tint, its mark and figure (joined in Chinese): as the old view's" {
  for c in [(62, "ok", "5H", "62%", false), (0, "amber", "W", "0%", true), (100, "red", "", "100%", false), (40, "progress", "每周剩", "95%", true)] {
    let (fill, level, mark, words, small) = c
    let (old, made) = drawn_both(fn(c) { fill_chip(c, fill, level, mark, words, small~) }, fn(r) {
      fill_chip_node(r, fn() { fill }, fn() { level }, fn() { mark }, fn() { words }, small~) |> ignore
    })
    assert_eq(made, old, msg="\{c}\nold=\{old}\nnew=\{made}")
  }
}

///|
test "an allowance's chips as nodes: each window's mark and what is left of it, side by side: as the old view's" {
  let q = Json::object({
    "state": "ok",
    "windows": [
      { "label": "5 小时", "mark": "5H", "left": 62.0, "level": "ok" },
      { "label": "每周", "mark": "W", "left": 15.0, "level": "amber" },
    ],
  })
  let (old, made) = drawn_both(fn(c) { quota_chips(c, Some(q), small=true) }, fn(r) {
    quota_chips_node(r, fn() { Some(q) }, small=true)
  })
  assert_eq(made, old)
}

///|
test "a tile as a node: its initial on its colour round its corner, without a picture: as the old view's" {
  for s in [(14.0, Some(small_corner)), (34.0, None)] {
    let (size, corner) = s
    let (old, made) = drawn_both(fn(c) { tile_avatar(c, "repo/one", "still", "", size, corner?) }, fn(r) {
      tile_avatar_node(r, fn() { "repo/one" }, fn() { "still" }, fn() { "" }, size, corner?)
    })
    assert_eq(made, old, msg="\{s}")
  }
}
