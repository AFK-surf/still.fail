// The shared picker embedded in a tree: reading, changing folders and stations, filtering, and letting go of an ask.

///|
fn picker_answer(path : String, entries : Array[Json]) -> Json {
  {
    "path": Json::string(path),
    "home": Json::string("/home"),
    "crumbs": Json::array(if path == "/home" {
      [{ "name": Json::string("Home"), "path": Json::string("/home") }]
    } else {
      [
        { "name": Json::string("Home"), "path": Json::string("/home") },
        { "name": Json::string("Selected"), "path": Json::string(path) },
      ]
    }),
    "places": Json::array([
      { "name": Json::string("Home"), "path": Json::string("/home") },
      { "name": Json::string("Disk"), "path": Json::string("/disk"), "disk": Json::boolean(true) },
    ]),
    "entries": Json::array(entries),
  }
}

///|
fn picker_folder(name : String, path : String) -> Json {
  { "name": Json::string(name), "path": Json::string(path) }
}

///|
test "shared folder picker nodes keep layout, filtering and navigation on each arrangement and input" {
  for (width, platform, look) in [(390.0, 2, @sf.Look::Narrow), (800.0, 0, @sf.Look::Wide)] {
    new_run()
    let calls : Array[(String, Json, (Result[Json, Json]) -> Unit)] = []
    let base = fixture("home")
    let src : Source = { ..base, call: fn(name, params, done) { calls.push((name, params, done)) } }
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=width, h=800.0, platform~)
    @sfdesk.folder_browse_open("one")
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      @sf.look_lent(root, look)
      @sfdesk.folder_browse_node(root, src, "one")
    })
    t.draw()
    assert_eq(calls.length(), 1)
    assert_eq((calls[0].0, text(Some(calls[0].1), "station")), ("drive.folders", "one"))
    (calls[0].2)(Ok(picker_answer("/home", [
      picker_folder("Home", "/home"), picker_folder("Projects", "/home/projects"), picker_folder("Reports", "/home/reports"),
    ])))
    t.draw()
    assert_eq(@sfdesk.folder_browse_here(), "/home")
    let (disk_x, disk_y) = t.find("Disk").unwrap()
    let (folder_x, folder_y) = t.find("Projects").unwrap()
    if look is Narrow { assert_true(disk_y < folder_y) } else { assert_true(disk_x < folder_x) }
    // Places are not repeated in the home list until a filter is entered.
    assert_eq(t.all(Button, label="Home").length(), 1)
    let label = @sf.t("web-pages.drive.pickFilter")
    let (x, y, w, h) = t.get(TextField, label~).rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.type_text("repo")
    t.draw()
    assert_true(t.find("Reports") is Some(_))
    assert_true(t.find("Projects") is None)
    if platform == 0 {
      t.key(@ui.key_tab)
      assert_eq(t.focused().map(fn(s) { s.label }), Some("Home"))
      t.key(@ui.key_tab)
      assert_eq(t.focused().map(fn(s) { s.label }), Some("Disk"))
      t.key_named("enter") |> ignore
    } else {
      let (x, y, w, h) = t.get(Button, label="Disk").rect
      t.tap(x + w / 2.0, y + h / 2.0)
    }
    t.draw()
    assert_eq(text(Some(calls[1].1), "path"), "/disk")
    assert_eq(@sfdesk.folder_browse_here(), "")
    (calls[1].2)(Ok(picker_answer("/disk", [picker_folder("Photos", "/disk/photos")])))
    t.draw()
    assert_true(t.find("Photos") is Some(_), msg="navigation clears the filter")
    t.click(Link, label="Home")
    t.draw()
    assert_eq(text(Some(calls[2].1), "path"), "/home")
    @sfdesk.folder_browse_close()
  }
}

///|
test "shared folder picker drops superseded and closed requests and shows read errors" {
  new_run()
  let calls : Array[(String, Json, (Result[Json, Json]) -> Unit)] = []
  let base = fixture("home")
  let src : Source = { ..base, call: fn(name, params, done) { calls.push((name, params, done)) } }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=800.0, platform=0)
  let station = @signals.signal("one")
  @sfdesk.folder_browse_open("one")
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    @sf.look_lent(root, Wide)
    root.pick(fn() { station.get() }, fn(part, at) { @sfdesk.folder_browse_node(part, src, at) })
  })
  t.draw()
  (calls[0].2)(Ok(picker_answer("/home", [picker_folder("Projects", "/home/projects")])))
  t.draw()
  t.click(Button, label="Projects")
  t.draw()
  t.click(Button, label="Disk")
  t.draw()
  assert_eq(calls.length(), 3)
  (calls[1].2)(Ok(picker_answer("/home/projects", [picker_folder("Stale", "/home/projects/stale")])))
  t.draw()
  assert_eq(@sfdesk.folder_browse_here(), "")
  assert_true(t.find("Stale") is None)
  (calls[2].2)(Err({ "code": Json::string("permission") }))
  t.draw()
  assert_eq(@sfdesk.folder_browse_here(), "")
  assert_true(t.find(@sf.t("web-pages.drive.pickNeedsAccess")) is Some(_))
  assert_true(t.query(TextField, label=@sf.t("web-pages.drive.pickFilter")) is None)
  t.click(Button, label="Home")
  t.draw()
  assert_eq(calls.length(), 4)
  (calls[3].2)(Err({ "message": Json::string("Station unavailable") }))
  t.draw()
  assert_true(t.find("Station unavailable") is Some(_))
  assert_eq(@sfdesk.folder_browse_here(), "")
  // Switching stations invalidates the previous one, including a callback that arrives after close.
  t.click(Button, label="Disk")
  t.draw()
  assert_eq(calls.length(), 5)
  @sfdesk.folder_browse_open("two")
  station.set("two")
  t.draw()
  assert_eq(calls.length(), 6)
  assert_eq(text(Some(calls[5].1), "station"), "two")
  (calls[4].2)(Ok(picker_answer("/old", [])))
  assert_eq(@sfdesk.folder_browse_here(), "")
  @sfdesk.folder_browse_close()
  (calls[5].2)(Ok(picker_answer("/late", [])))
  t.draw()
  assert_eq(@sfdesk.folder_browse_here(), "")
}

///|
test "shared folder picker favorite dialog disables a kept folder and returns the chosen folder once" {
  for (width, height, platform) in [(390.0, 844.0, 2), (1280.0, 800.0, 0)] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=height, platform~)
    let station = @sfdesk.favorite_stations(src, "ws1").iter().find_first(fn(s) { s.station == "ws1/st1" }).unwrap()
    let picked : Array[@sfdesk.Favorite] = []
    @sfdesk.add_favorite_folder(src, "ws1", [station], picked=fn(f) { picked.push(f) })
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="文档")
    t.draw()
    assert_true(t.get(Button, label=@sf.t("web-pages.files.alreadyFavorite")).disabled)
    assert_eq(picked.length(), 0)
    t.click(Button, label="项目")
    t.draw()
    let pick = @sf.t("web-pages.files.pickFavorite")
    assert_false(t.get(Button, label=pick).disabled)
    t.click(Button, label=pick)
    t.draw()
    assert_eq(picked.length(), 1)
    assert_eq((picked[0].station, picked[0].root, picked[0].path), ("ws1/st1", "/Users/lin/项目", ""))
    assert_true(@sfdesk.favorite_has(@sfdesk.favorites(src, "ws1"), "ws1/st1", "/Users/lin/项目", ""))
    assert_false(@sf.presenting())
  }
}

///|
test "shared folder picker favorite dialog cancels an in-flight read before it is opened again" {
  new_run()
  let pending : Array[(Result[Json, Json]) -> Unit] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "drive.folders" { pending.push(done) } else { (base.call)(name, params, done) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let station = @sfdesk.favorite_stations(src, "ws1").iter().find_first(fn(s) { s.station == "ws1/st1" }).unwrap()
  @sfdesk.add_favorite_folder(src, "ws1", [station])
  t.run_for(@kit.dialog_ms)
  assert_eq(pending.length(), 1)
  let pick = @sf.t("web-pages.files.pickFavorite")
  assert_true(t.get(Button, label=pick).disabled)
  t.click(Button, label=@sf.t("common.cancel"))
  t.draw()
  @sfdesk.add_favorite_folder(src, "ws1", [station])
  t.run_for(@kit.dialog_ms)
  assert_eq(pending.length(), 2)
  (pending[0])(Ok(picker_answer("/old", [])))
  t.draw()
  assert_true(t.get(Button, label=pick).disabled)
  assert_eq(@sfdesk.folder_browse_here(), "")
  (pending[1])(Ok(picker_answer("/new", [])))
  t.draw()
  assert_false(t.get(Button, label=pick).disabled)
  t.key(@ui.key_escape)
  t.draw()
  assert_eq(@sfdesk.folder_browse_here(), "")
  assert_false(@sf.presenting())
}

///|
/// The places and folders' relation at the same width, from either the old or the tree body.
fn picker_places_beside(width : Double, tree : Bool) -> Bool {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    if !tree {
      c.with_theme(@sf.ui_theme(), fn() { @sfdesk.folder_browse_body(c, src, "ws1/st1") })
    }
  }, w=width, h=800.0, platform=0)
  @sfdesk.folder_browse_open("ws1/st1")
  if tree {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      // The body follows the old presenter's window width, even when its parent lends another look.
      @sf.look_lent(root, Wide)
      @sfdesk.folder_browse_node(root, src, "ws1/st1")
    })
  }
  t.draw()
  t.draw()
  let (x, y, _, _) = t.get(Button, label="外接硬盘").rect
  let (fx, fy, _, _) = t.get(Button, label="项目").rect
  @sfdesk.folder_browse_close()
  x < fx && y > fy - 40.0
}

///|
test "shared folder picker keeps the old arrangement at the window-width boundary" {
  for width in [390.0, 620.0, 639.0, 640.0, 700.0, 900.0] {
    assert_eq(picker_places_beside(width, true), picker_places_beside(width, false), msg="width \{width}")
  }
}

///|
test "shared folder picker in a narrow dialog follows the window as the old picker did" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=800.0, platform=0)
  @sfdesk.folder_browse_open("ws1/st1")
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(parent) {
      parent.width(Is(Some(500.0))) |> ignore
      @sfdesk.folder_browse_node(parent, src, "ws1/st1")
    }) |> ignore
  })
  t.draw()
  t.draw()
  let (x, y, _, _) = t.get(Button, label="外接硬盘").rect
  let (fx, fy, _, _) = t.get(Button, label="项目").rect
  assert_true(x < fx && y > fy - 40.0)
  @sfdesk.folder_browse_close()
}

///|
test "shared folder picker keeps the filter focus and words as the window crosses the layout boundary" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=900.0, h=800.0, platform=0)
  @sfdesk.folder_browse_open("ws1/st1")
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    @sf.look_lent(root, Wide)
    @sfdesk.folder_browse_node(root, src, "ws1/st1")
  })
  t.draw()
  t.draw()
  let label = @sf.t("web-pages.drive.pickFilter")
  let (x, y, w, h) = t.get(TextField, label~).rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.type_text("项目")
  assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
  t.resize(390.0, 800.0)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
  assert_eq(t.get(TextField, label~).value, "项目")
  let (_, disk_y, _, _) = t.get(Button, label="外接硬盘").rect
  let (_, folder_y, _, _) = t.get(Button, label="项目").rect
  assert_true(disk_y < folder_y)
  @sfdesk.folder_browse_close()
}
