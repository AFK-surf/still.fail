// A carried file goes to the innermost eligible tree target or a chat, and a late folder answer completes a drop once.

///|
fn drag_tree_target(path : String) -> FTarget {
  { id: 0, key: path, into: Some({ station: "ws/other", root: Some("/dest"), path }), name: path,
    write: true, transfers: true, depth: 2, outside: true }
}

///|
fn drag_tree_case(ready : @signals.Signal[Bool], calls : Array[(String, Json)], taken : Array[String]) -> @ui.Tester {
  drag_reset()
  let src = @sfbase.made_source(topic=fn(name, _) {
    match name {
      "drive" if ready.get() => Some({ "entries": [] })
      "stations" => Some([])
      _ => None
    }
  }, call=fn(name, params, done) { calls.push((name, params)); done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let file = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=400.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(source) {
      source.width(Is(Some(180.0))).height(Is(Some(70.0))).presses(Is(true)) |> ignore
      @sf.words_node(source, fn() { "Source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, file, d) }) |> ignore
    }) |> ignore
    root.box(fn(outer) {
      outer.width(Is(Some(250.0))).height(Is(Some(120.0))).presses(Is(true)) |> ignore
      drive_drop_target_node(outer, src, fn() { "ws" }, fn() { drag_tree_target("outer") }) |> ignore
      @sf.words_node(outer, fn() { "Outer" }, fn() { @sf.theme().items.name }) |> ignore
      outer.box(fn(inner) {
        inner.width(Is(Some(180.0))).height(Is(Some(60.0))).presses(Is(true)) |> ignore
        drive_drop_target_node(inner, src, fn() { "ws" }, fn() { drag_tree_target("outer/child") }) |> ignore
        @sf.words_node(inner, fn() { "Child" }, fn() { @sf.theme().items.name }) |> ignore
      }) |> ignore
    }) |> ignore
    root.box(fn(chat) {
      chat.width(Is(Some(180.0))).height(Is(Some(60.0))).presses(Is(true)) |> ignore
      @sf.words_node(chat, fn() { "Chat" }, fn() { @sf.theme().items.name }) |> ignore
      @ui.takes_let_go(chat, fn(_, _) {
        match drag_taken() { Some(d) => { taken.push(d.name); true }; None => false }
      })
    }) |> ignore
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  t
}

///|
test "folder drag takes its deepest target and waits for its names once" {
  let ready = @signals.signal(false)
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(ready, calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Child").unwrap()
  t.drag(sx, sy, dx, dy, steps=3)
  assert_true(dragged() is None)
  assert_eq(drive_node_pending.length(), 1)
  assert_true(calls.iter().all(fn(c) { c.0 != "drive.transfer" }))
  ready.set(true)
  let moves = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(moves.length(), 1)
  assert_eq(text(field(Some(moves[0].1), "to"), "path"), "outer/child")
  assert_eq(drive_node_pending.length(), 0)
  t.draw()
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 1)
}

///|
test "folder drag reaches the chat and clears when released in blank space" {
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(@signals.signal(true), calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  let (cx, cy) = t.find("Chat").unwrap()
  t.drag(sx, sy, cx, cy, steps=3)
  assert_eq(taken, ["Source.txt"])
  assert_true(dragged() is None)
  t.drag(sx, sy, 350.0, 350.0, steps=3)
  assert_true(dragged() is None)
  assert_true(drive_node_position.get() is None)
}

///|
fn side_drag_item(dir : Bool) -> Dragged {
  { station: "ws/source", station_name: "Source", root: "/src", path: "carried", abs: "/src/carried",
    name: "carried", size: 2.0, dir }
}

///|
test "folder drag sidebar tracks permissions, destination, effects and node lifetime" {
  drag_reset()
  let calls : Array[(String, Json)] = []
  let src = @sfbase.made_source(topic=fn(_, _) { None }, call=fn(name, params, done) {
    calls.push((name, params))
    done(Ok({}))
  })
  let shown = @signals.signal(true)
  let into : @signals.Signal[DriveAt?] = @signals.signal(Some({ station: "ws/other", root: Some("/dst"), path: "one" }))
  let writable = @signals.signal(true)
  let transfers = @signals.signal(true)
  let keep : Ref[() -> String?] = Ref(fn() { None })
  let folder : Ref[() -> String?] = Ref(fn() { None })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=400.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(outer) {
      outer.width(Is(Some(250.0))).height(Is(Some(160.0))).presses(Is(true)) |> ignore
      keep.val = drive_side_target_node(outer, src, fn() { "ws" }, fn() { None }, fn() { "" },
        fn() { true }, fn() { true })
      @sf.words_node(outer, fn() { "Keep" }, fn() { @sf.theme().items.name }) |> ignore
      outer.show(fn() { shown.get() }, fn(inner) {
        inner.width(Is(Some(180.0))).height(Is(Some(70.0))).presses(Is(true)) |> ignore
        folder.val = drive_side_target_node(inner, src, fn() { "ws" }, fn() { into.get() }, fn() { "Folder" },
          fn() { writable.get() }, fn() { transfers.get() })
        @sf.words_node(inner, fn() { "Folder" }, fn() { @sf.theme().items.name }) |> ignore
      })
    }) |> ignore
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  let (x, y) = t.find("Folder").unwrap()
  t.press_at(350.0, 350.0)
  t.move(x, y)
  assert_true((folder.val)() is None)
  fdrag.item.set(Some(side_drag_item(false)))
  assert_eq((folder.val)(), Some("copy"))
  assert_true((keep.val)() is None)
  transfers.set(false)
  assert_true((folder.val)() is None)
  assert_true((keep.val)() is None)
  into.set(Some({ station: "ws/source", root: Some("/dst"), path: "two" }))
  assert_eq((folder.val)(), Some("move"))
  t.hold_mods(@ui.mod_alt)
  t.move(x + 1.0, y)
  assert_eq((folder.val)(), Some("copy"))
  writable.set(false)
  assert_true((folder.val)() is None)
  t.release(x, y)
  assert_true(dragged() is None)
  assert_true(calls.iter().all(fn(c) { c.0 != "prefs.set" }))
  t.press_at(350.0, 350.0)
  t.move(x, y)
  fdrag.item.set(Some(side_drag_item(true)))
  assert_eq((keep.val)(), Some("keep"))
  writable.set(true)
  assert_eq((folder.val)(), Some("copy"))
  assert_true((keep.val)() is None)
  shown.set(false)
  t.draw()
  assert_eq(drive_node_targets.length(), 1)
  assert_true((folder.val)() is None)
  assert_eq((keep.val)(), Some("keep"))
  t.release(x, y)
  assert_true(dragged() is None)
  assert_eq(calls.filter(fn(c) { c.0 == "prefs.set" }).length(), 1)
}

///|
test "folder drag crosses between old and new targets once in either direction" {
  drag_reset()
  let calls : Array[(String, Json)] = []
  let covered = @signals.signal(false)
  let src = @sfbase.made_source(topic=fn(name, _) {
    match name {
      "drive" => Some({ "entries": [] })
      "stations" => Some([])
      _ => None
    }
  }, call=fn(name, params, done) { calls.push((name, params)); done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let entry = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=400.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(old) {
      old.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      @ui.old(old, fn(c) {
        drag_frame(c, src, "ws", outside=false)
        let source = c.id("old-source")
        let dest = c.id("old-dest")
        if c.pressed(source) { drag_press(c, src, from, entry) }
        fdrag_target(c, dest, "old-dest", Some({ station: "ws/other", root: Some("/dest"), path: "old" }),
          "old", true, true, 1, outside=false) |> ignore
        c.interact(source) |> ignore
        c.box(id=source, w=Px(180.0), h=Px(50.0), fn() { c.text("Old source") |> ignore }) |> ignore
        c.interact(dest) |> ignore
        c.box(id=dest, w=Px(180.0), h=Px(50.0), fn() { c.text("Old destination") |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
    root.box(fn(source) {
      source.width(Is(Some(200.0))).height(Is(Some(60.0))).presses(Is(true)) |> ignore
      @sf.words_node(source, fn() { "New source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, entry, d) }) |> ignore
    }) |> ignore
    root.box(fn(dest) {
      dest.width(Is(Some(200.0))).height(Is(Some(60.0))).presses(Is(true)) |> ignore
      @sf.words_node(dest, fn() { "New destination" }, fn() { @sf.theme().items.name }) |> ignore
      drive_side_target_node(dest, src, fn() { "ws" },
        fn() { Some({ station: "ws/other", root: Some("/dest"), path: "new" }) }, fn() { "new" },
        fn() { true }, fn() { true }) |> ignore
    }) |> ignore
    root.show(fn() { covered.get() }, fn(cover) {
      cover.over(Is(true)).offset(Is((0.0, 50.0))).width(Is(Some(180.0))).height(Is(Some(50.0)))
      .presses(Is(true)) |> ignore
    })
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  t.draw()
  let (ox, oy) = t.find("Old source").unwrap()
  let (nx, ny) = t.find("New destination").unwrap()
  t.drag(ox, oy, nx, ny, steps=3)
  let moves = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(moves.length(), 1)
  assert_eq(text(field(Some(moves[0].1), "to"), "path"), "new")
  assert_true(dragged() is None)
  let (sx, sy) = t.find("New source").unwrap()
  let (dx, dy) = t.find("Old destination").unwrap()
  t.drag(sx, sy, dx, dy, steps=3)
  let moves = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(moves.length(), 2)
  assert_eq(text(field(Some(moves[1].1), "to"), "path"), "old")
  assert_true(dragged() is None)
  // A new view over the old destination must block the old rectangle beneath it.
  covered.set(true)
  t.draw()
  t.drag(sx, sy, dx, dy, steps=3)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 2)
  assert_true(dragged() is None)
}

///|
test "folder drag cancels when its press is called off" {
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(@signals.signal(true), calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Child").unwrap()
  t.press_at(sx, sy)
  t.move(dx, dy)
  assert_true(dragged() is Some(_))
  t.touch(3, dx, dy)
  t.draw()
  assert_true(dragged() is None)
  assert_true(drive_node_position.get() is None)
  assert_true(calls.iter().all(fn(c) { c.0 != "drive.transfer" }))
}
