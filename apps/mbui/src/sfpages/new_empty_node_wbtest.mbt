// The new chat's pages with nothing to start on as nodes (new_empty_node.mbt), drawn as their old views are
// (new_first_station, new_none_up): each instance the same, at a page's width wide and narrow.

///|
/// What the window draws, each instance's numbers rounded to a hundredth (a border none wide as none), in one order.
fn empty_drawn(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) {
    // (a box's border none wide draws nothing whatever its colour (6 its width, 12-15 its colour): an old view's
    // button says its ground's colour there, a node's none)
    a
    .mapi(fn(j, x) { if a[5] == 0.0 && a[6] == 0.0 && j >= 12 && j <= 15 { 0.0 } else { x } })
    .map(fn(x) { ((x * 100.0).round() / 100.0).to_string() })
    .join(",")
  })
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

///|
/// The page blocked by `blocked` ("profile", "shared", "models") on ws/st, with `several` stations, 1000 by 700,
/// drawn by its old view (`node` false) or as nodes.
fn blocked_tester(blocked : String, several : Bool, node : Bool) -> @ui.Tester {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let w : Workspace = { id: "ws", name: "工作区", emoji: "", icon: "", email: "" }
  let station = Json::object({ "station": "ws/st", "name": "Willow", "emoji": "", "icon": "" })
  let stations : Array[Json] = if several { [station, Json::object({ "station": "ws/s2", "name": "Mo" })] } else { [station] }
  let v = Json::object({ "blocked": Json::string(blocked), "problem": "问管理员共享", "stations": Json::array(stations) })
  if !node {
    let t = @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          c.box(style=@ui.css("w=Full h=Full"), fn() { new_blocked(c, src, w, Some(v), Some(station)) }) |> ignore
        })
      },
      w=1000.0,
      h=700.0,
      platform=0,
    )
    t.draw()
    return t
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(p) {
      p.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
      new_blocked_node(p, src, fn() { Some(w) }, fn() { Some(v) }, fn() { Some(station) })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a new chat with nothing to run it with, as nodes: what to add, whom to ask, where to pick, the station chosen anew: drawn as the old view" {
  for blocked in ["profile", "shared", "models"] {
    for several in [false, true] {
      let old = empty_drawn(blocked_tester(blocked, several, false))
      assert_true(old.length() > 0, msg="\{blocked} \{several}: the old view draws it")
      let made = empty_drawn(blocked_tester(blocked, several, true))
      let only_old = old.filter(fn(x) { !made.contains(x) })
      let only_new = made.filter(fn(x) { !old.contains(x) })
      assert_eq(made, old, msg="\{blocked} \{several}\nold only: \{only_old}\nnew only: \{only_new}")
    }
  }
}
