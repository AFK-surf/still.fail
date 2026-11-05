// The offer of a station's machine's own sessions as a node (settings' machine_sessions_offer_node), as its old view
// draws it (machine_sessions_offer): asked once for its station, shown once the station says it kept any, each drawn
// instance the same; pressed, their dialog.

///|
/// What the window draws, each instance's numbers rounded to a hundredth, in one order.
fn offer_drawn(t : @ui.Tester) -> Array[String] {
  let all = t.drawn_instances().map(fn(a) { a.map(fn(x) { ((x * 100.0).round() / 100.0).to_string() }).join(",") })
  all.sort()
  all
}

///|
/// The offer for ws/st (Willow) drawn by an old view (`node` false) or as a node, the station answering at once with
/// one session; what was asked of it.
fn offer_tester(node : Bool, asked : Array[String]) -> @ui.Tester {
  new_run()
  let base = @sfbase.made_source(call=fn(name, _, done) {
    asked.push(name)
    if name == "machineSessions.list" {
      done(Ok({ "sessions": [{ "id": "m1", "runtime": "claude", "title": "整理构建脚本", "meta": "Claude Code" }] }))
    } else {
      done(Ok({}))
    }
  })
  let w : Workspace = { id: "ws", name: "工作区", emoji: "", icon: "", email: "" }
  let core = @sfbase.settings_core(base, w)
  if !node {
    // (the old view as an old frame draws it, in a row from the window's corner)
    let t = @ui.Tester::new(
      fn(c) {
        @sf.begin(c) |> ignore
        c.with_theme(@sf.ui_theme(), fn() {
          c.box(style=@ui.css("row align=AStart"), fn() { @settings.machine_sessions_offer(c, core, "ws/st", "Willow") })
          |> ignore
        })
      },
      w=600.0,
      h=200.0,
      platform=0,
    )
    t.draw()
    t.draw()
    t.draw()
    return t
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(r) {
      r.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
      @settings.machine_sessions_offer_node(r, core, fn() { "ws/st" }, fn() { "Willow" })
    })
    |> ignore
  })
  t.draw()
  t.draw()
  t.draw()
  t
}

///|
test "the machine's sessions offered as a node: asked once, shown once it kept some, drawn as the old view's" {
  let old_asked = []
  let old = offer_drawn(offer_tester(false, old_asked))
  assert_true(old.length() > 0, msg="the old view draws it")
  let asked = []
  let t = offer_tester(true, asked)
  assert_eq(asked.filter(fn(a) { a == "machineSessions.list" }).length(), 1, msg="asked once")
  assert_true(t.find("Willow") is Some(_), msg="shown: \{t.words()}")
  assert_eq(offer_drawn(t), old)
}
