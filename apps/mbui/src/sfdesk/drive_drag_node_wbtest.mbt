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
test "folder drag keeps each drop while a destination is unread" {
  let ready = @signals.signal(false)
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(ready, calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Child").unwrap()
  t.drag(sx, sy, dx, dy, steps=3)
  t.drag(sx, sy, dx, dy, steps=3)
  assert_eq(drive_node_pending.length(), 2)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 0)
  ready.set(true)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 2)
  assert_eq(drive_node_pending.length(), 0)
  t.draw()
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 2)
}

///|
test "folder drag uses the modifiers at release even if the destination arrives later" {
  let ready = @signals.signal(false)
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(ready, calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Child").unwrap()
  t.press_at(sx, sy)
  t.move(dx, dy)
  t.hold_mods(@ui.mod_cmd)
  t.release(dx, dy)
  t.hold_mods(0)
  ready.set(true)
  let transfers = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(transfers.length(), 1)
  assert_eq(field(Some(transfers[0].1), "move"), Some(Json::boolean(true)))
  t.press_at(sx, sy)
  t.move(dx, dy)
  t.hold_mods(@ui.mod_cmd)
  t.hold_mods(0)
  t.release(dx, dy)
  let transfers = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(transfers.length(), 2)
  assert_eq(field(Some(transfers[1].1), "move"), Some(Json::boolean(false)))
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
test "folder drag gives an old folder inside chat priority over the chat" {
  drag_reset()
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let shown : Ref[() -> Bool] = Ref(fn() { false })
  let writable = @signals.signal(true)
  let src = @sfbase.made_source(topic=fn(name, _) {
    match name { "drive" => Some({ "entries": [] }); "stations" => Some([]); _ => None }
  }, call=fn(name, params, done) { calls.push((name, params)); done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let entry = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(source) {
      source.width(Is(Some(200.0))).height(Is(Some(70.0))) |> ignore
      @sf.words_node(source, fn() { "Source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, entry, d) }) |> ignore
    }) |> ignore
    root.box(fn(chat) {
      chat.width(Is(Some(220.0))).height(Is(Some(100.0))) |> ignore
      @ui.takes_let_go(chat, fn(_, _) {
        match drag_taken() { Some(item) => { taken.push(item.name); true }; None => false }
      })
      shown.val = chat_drop_hint_active(chat, fn() { true })
      @ui.old(chat, fn(c) {
        drag_frame(c, src, "ws", outside=false)
        let id = c.id("old-folder-in-chat")
        fdrag_target(c, id, "old-folder", Some({ station: "ws/other", root: Some("/dst"), path: "nested" }),
          "Folder", writable.get(), true, 1, outside=false) |> ignore
        c.interact(id) |> ignore
        c.box(id~, w=Px(180.0), h=Px(70.0), fn() { c.text("Old folder") |> ignore }) |> ignore
      }).over(Is(true)) |> @ui.old_takes_own |> ignore
    }) |> ignore
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  t.draw()
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Old folder").unwrap()
  t.press_at(sx, sy)
  t.move(dx, dy)
  t.draw()
  assert_false((shown.val)())
  t.release(dx, dy)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 1)
  assert_eq(taken, [])
  writable.set(false)
  t.draw()
  t.press_at(sx, sy)
  t.move(dx, dy)
  t.draw()
  assert_true((shown.val)())
  t.release(dx, dy)
  assert_eq(taken, ["Source.txt"])
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 1)
}

///|
test "folder drag chat hint follows the actual target without taking the drop" {
  drag_reset()
  let src = @sfbase.made_source(topic=fn(_, _) { None }, call=fn(_, _, done) { done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let entry = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let enabled = @signals.signal(true)
  let writable = @signals.signal(true)
  let covered = @signals.signal(false)
  let hint_mounted = @signals.signal(true)
  let shown : Ref[() -> Bool] = Ref(fn() { false })
  let taken : Array[String] = []
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(source) {
      source.width(Is(Some(180.0))).height(Is(Some(70.0))).presses(Is(true)) |> ignore
      @sf.words_node(source, fn() { "Source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, entry, d) }) |> ignore
    }) |> ignore
    root.box(fn(chat) {
      chat.width(Is(Some(260.0))).height(Is(Some(120.0))) |> ignore
      @sf.words_node(chat, fn() { "Chat" }, fn() { @sf.theme().items.name }) |> ignore
      chat.box(fn(folder) {
        folder.width(Is(Some(120.0))).height(Is(Some(40.0))) |> ignore
        @sf.words_node(folder, fn() { "Folder" }, fn() { @sf.theme().items.name }) |> ignore
        drive_side_target_node(folder, src, fn() { "ws" },
          fn() { Some({ station: "ws/other", root: Some("/dst"), path: "" }) },
          fn() { "Folder" }, fn() { writable.get() }, fn() { true }) |> ignore
      }) |> ignore
      @ui.takes_let_go(chat, fn(_, _) {
        if !enabled.get() { return false }
        match drag_taken() { Some(item) => { taken.push(item.name); true }; None => false }
      })
      shown.val = chat_drop_hint_active(chat, fn() { enabled.get() })
      chat.show(fn() { hint_mounted.get() }, fn(hint) {
        hint.over(Is(true)).presses(Is(false)).hides(Is(true)) |> ignore
        chat_drop_hint_node(hint, shown.val)
      })
    }) |> ignore
    root.show(fn() { covered.get() }, fn(cover) {
      cover.over(Is(true)).offset(Is((0.0, 70.0))).width(Is(Some(260.0))).height(Is(Some(120.0)))
      .on_press(fn() {  }) |> ignore
    })
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  let (sx, sy) = t.find("Source").unwrap()
  let (fx, fy) = t.find("Folder").unwrap()
  t.press_at(sx, sy)
  t.move(220.0, 150.0)
  t.draw()
  assert_true((shown.val)())
  assert_true(t.find(@sf.t("web-main.composer.dropHere")) is Some(_))
  assert_false(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the chat hint covers the drag chip")
  hint_mounted.set(false)
  t.draw()
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="removing the hint restores the chip")
  hint_mounted.set(true)
  t.draw()
  assert_false(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="a remounted hint covers the chip")
  t.move(fx, fy)
  t.draw()
  assert_false((shown.val)())
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the chip returns over an eligible folder")
  writable.set(false)
  t.draw()
  assert_true((shown.val)())
  covered.set(true)
  t.draw()
  assert_false((shown.val)())
  covered.set(false)
  enabled.set(false)
  t.draw()
  assert_false((shown.val)())
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the chip returns when the chat cannot receive")
  enabled.set(true)
  t.move(220.0, 150.0)
  t.draw()
  assert_true((shown.val)())
  t.release(220.0, 150.0)
  assert_eq(taken, ["Source.txt"])
  assert_false((shown.val)())
}

///|
test "folder drag chip stays under an old chat hint" {
  drag_reset()
  let mounted = @signals.signal(true)
  let available = @signals.signal(true)
  let src = @sfbase.made_source(topic=fn(_, _) { None }, call=fn(_, _, done) { done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let entry = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(source) {
      source.width(Is(Some(180.0))).height(Is(Some(70.0))).presses(Is(true)) |> ignore
      @sf.words_node(source, fn() { "Source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, entry, d) }) |> ignore
    }) |> ignore
    root.show(fn() { mounted.get() }, fn(chat) {
      chat.width(Is(Some(260.0))).height(Is(Some(120.0))) |> ignore
      @ui.old(chat, fn(c) {
        let pane = c.id("old-chat-hint-pane")
        c.box(id=pane, w=Px(260.0), h=Px(120.0), fn() { c.text("Old chat") |> ignore }) |> ignore
        if available.get() { drop_hint(c, pane) } else { old_chat_drop_hint_forget(pane) }
      }).over(Is(true)) |> @ui.old_takes_own |> ignore
    })
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  t.draw()
  let (sx, sy) = t.find("Source").unwrap()
  t.press_at(sx, sy)
  t.move(220.0, 150.0)
  t.draw()
  assert_true(t.drawn_text().contains(@sf.t("web-main.composer.dropHere")), msg="the old chat hint is drawn")
  assert_false(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the old chat hint covers the drag chip")
  available.set(false)
  t.draw()
  assert_false(t.drawn_text().contains(@sf.t("web-main.composer.dropHere")))
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="losing the chat view restores the chip")
  available.set(true)
  t.draw()
  assert_true(t.drawn_text().contains(@sf.t("web-main.composer.dropHere")))
  assert_false(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the restored chat hint covers the chip")
  mounted.set(false)
  t.draw()
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="removing the old chat restores the chip")
  mounted.set(true)
  t.draw()
  // The old hint uses the previous frame's pane rectangle. On the first frame of a new island it has not drawn yet.
  assert_false(t.drawn_text().contains(@sf.t("web-main.composer.dropHere")))
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }))
  t.move(219.0, 150.0)
  t.draw()
  assert_true(t.drawn_text().contains(@sf.t("web-main.composer.dropHere")))
  assert_false(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="a remounted old hint covers the chip")
  t.move(350.0, 250.0)
  t.draw()
  assert_true(t.drawn_words_found().iter().any(fn(w) { w.3 == "Source.txt" }), msg="the chip returns outside the old chat")
  t.release(350.0, 250.0)
  assert_true(old_chat_drop_hints.is_empty())
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
  let effects : Array[String?] = []
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
        inner.reacts(fn() { (folder.val)() }, fn(effect) { effects.push(effect) })
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
  assert_eq((folder.val)(), Some("copy"))
  assert_eq(effects.last(), Some(Some("copy")))
  into.set(Some({ station: "ws/source", root: Some("/src"), path: "carried/child" }))
  assert_true((folder.val)() is None)
  into.set(Some({ station: "ws/other", root: Some("/dst"), path: "three" }))
  transfers.set(true)
  t.hold_mods(@ui.mod_cmd)
  assert_eq((folder.val)(), Some("move"))
  assert_eq(effects.last(), Some(Some("move")))
  into.set(Some({ station: "ws/source", root: Some("/dst"), path: "two" }))
  t.hold_mods(@ui.mod_alt)
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
        let effect = fdrag_target(c, dest, "old-dest", Some({ station: "ws/other", root: Some("/dest"), path: "old" }),
          "old", true, true, 1, outside=false)
        c.interact(source) |> ignore
        c.box(id=source, w=Px(180.0), h=Px(50.0), fn() { c.text("Old source") |> ignore }) |> ignore
        c.interact(dest) |> ignore
        c.box(id=dest, w=Px(180.0), h=Px(50.0), fn() {
          c.text("Old destination") |> ignore
          match effect { Some(e) => c.text("effect: " + e) |> ignore; None => () }
        }) |> ignore
      }).over(Is(true)) |> @ui.old_takes_own |> ignore
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
      .on_press(fn() { }) |> ignore
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
  t.press_at(sx, sy)
  t.move(dx, dy)
  t.draw()
  assert_eq(fdrag.over, "old-dest")
  assert_true(t.find("effect: copy") is Some(_))
  // No pointer movement or forced draw: the old island must repaint for the current modifier too.
  t.hold_mods(@ui.mod_cmd)
  t.frames_owed()
  assert_true(t.find("effect: move") is Some(_))
  t.hold_mods(0)
  t.frames_owed()
  assert_true(t.find("effect: copy") is Some(_))
  t.release(dx, dy)
  let moves = calls.filter(fn(c) { c.0 == "drive.transfer" })
  assert_eq(moves.length(), 2)
  assert_eq(text(field(Some(moves[1].1), "to"), "path"), "old")
  assert_true(dragged() is None)
  // A new view over the old destination must block the old rectangle beneath it.
  covered.set(true)
  t.draw()
  assert_true(@ui.old_drop_within(dx, dy).is_empty())
  t.drag(sx, sy, dx, dy, steps=3)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 2)
  assert_true(dragged() is None)
  // A drag started by an old view is also cancelled if the window loses focus before release.
  covered.set(false)
  t.app_state(true, true)
  t.press_at(ox, oy)
  t.move(nx, ny)
  t.draw()
  assert_true(dragged() is Some(_))
  t.app_state(true, false)
  assert_true(dragged() is None)
  assert_eq(calls.filter(fn(c) { c.0 == "drive.transfer" }).length(), 2)
  t.app_state(true, true)
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

///|
test "folder drag chip follows the pointer and leaves with the drag" {
  let calls : Array[(String, Json)] = []
  let taken : Array[String] = []
  let t = drag_tree_case(@signals.signal(true), calls, taken)
  let (sx, sy) = t.find("Source").unwrap()
  t.press_at(sx, sy)
  t.move(sx + 40.0, sy)
  t.draw()
  let (x1, y1) = t.find("Source.txt").unwrap()
  assert_true(t.words_said().iter().all(fn(w) { !w.0.contains("Source.txt") }))
  t.move(sx + 70.0, sy + 10.0)
  t.draw()
  let (x2, y2) = t.find("Source.txt").unwrap()
  assert_eq((x2 - x1, y2 - y1), (30.0, 10.0))
  t.release(sx + 70.0, sy + 10.0)
  assert_true(t.find("Source.txt") is None)
}

///|
test "folder drag reaches an old new-chat composer once" {
  @sfbase.reset()
  app.nav.push(NewChat)
  drag_reset()
  tab_reset()
  let accepted : Array[String] = []
  let src = @sfbase.made_source(topic=fn(_, _) { None }, call=fn(_, _, done) { done(Ok({})) })
  let from : DriveAt = { station: "ws/source", root: Some("/src"), path: "" }
  let entry = @sfbase.dv_entry({ "name": "Source.txt", "kind": "text", "size": 2 })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(source) {
      source.width(Is(Some(200.0))).height(Is(Some(70.0))).presses(Is(true)) |> ignore
      @sf.words_node(source, fn() { "Source" }, fn() { @sf.theme().items.name }) |> ignore
      source.gesture(fdrag_slop, drag=fn(d) { drive_node_drag(src, from, entry, d) }) |> ignore
    }) |> ignore
    root.box(fn(chat) {
      chat.width(Is(Some(200.0))).height(Is(Some(100.0))) |> ignore
      @ui.old(chat, fn(c) {
        let id = c.id("old-new-chat")
        c.interact(id) |> ignore
        c.box(id~, w=Px(200.0), h=Px(100.0), fn() { c.text("Old new chat") |> ignore }) |> ignore
        match tab_take_drop(c) {
          Some((item, x, y)) if inside(c.rect_of(id), x, y) => accepted.push(item.name)
          _ => ()
        }
      }).over(Is(true)) |> @ui.old_takes_own |> ignore
    }) |> ignore
    drive_drag_window_node(root, src, fn() { "ws" })
  })
  t.draw()
  t.draw()
  let (sx, sy) = t.find("Source").unwrap()
  let (dx, dy) = t.find("Old new chat").unwrap()
  t.drag(sx, sy, dx, dy, steps=3)
  assert_eq(accepted, ["Source.txt"])
  t.draw()
  assert_eq(accepted, ["Source.txt"])
  assert_true(dragged() is None)
  app.nav.pop() |> ignore
}
