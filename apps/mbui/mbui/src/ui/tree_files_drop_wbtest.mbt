// External files on ordinary retained nodes: targets are hit where the tree draws them, not by press handlers.

///|
test "external files: deepest node hovers and takes each drop; its pick tells a reactive reader when ready" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let outer_over : Ref[() -> Bool] = Ref(fn() { false })
  let inner_over : Ref[() -> Bool] = Ref(fn() { false })
  let pending : @signals.Signal[Pick?] = @signals.signal(None)
  let drops : Array[String] = []
  let read : Array[String] = []
  let presses = Ref(0)
  let stop = @signals.effect(fn() {
    match pending.get() {
      Some(p) =>
        match p.files() {
          Some(files) => {
            pending.set(None)
            for f in files { read.push(f.name) }
          }
          None => ()
        }
      None => ()
    }
  })
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      outer_over.val = files_into_node(page, fn(p) { drops.push("outer"); pending.set(Some(p)) })
      page.box(fn(folder) {
        folder.width(Is(Some(100.0))).height(Is(Some(80.0))).words(Is("folder")).on_press(fn() { presses.val += 1 }) |> ignore
        inner_over.val = files_into_node(folder, fn(p) { drops.push("folder"); pending.set(Some(p)) })
        folder.ground(By(fn() { if (inner_over.val)() { 0x123456FFL } else { 0xABCDEFffL } })) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.tap(20.0, 20.0)
  assert_eq(presses.val, 1)
  t.hold_files(Some((20.0, 20.0)))
  t.frame()
  assert_false((outer_over.val)())
  assert_true((inner_over.val)())
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x123456FFL }))
  t.drop_files(20.0, 20.0, [("a.txt", b"a")])
  t.frame()
  assert_eq(drops, ["folder"])
  assert_false((inner_over.val)())
  assert_eq(read, [])
  assert_false(t.drawn_rects().iter().any(fn(r) { r.4 == 0x123456FFL }))
  t.draw()
  assert_eq(read, ["a.txt"])
  t.draw()
  assert_eq(drops, ["folder"])
  assert_eq(read, ["a.txt"])
  t.hold_files(Some((180.0, 150.0)))
  t.frame()
  assert_true((outer_over.val)())
  assert_false((inner_over.val)())
  t.hold_files(None)
  t.frame()
  assert_false((outer_over.val)())
  stop()
}

///|
test "external files: a stationary drag follows visibility, availability, clipping and a modal" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let visible = @signals.signal(true)
  let writable = @signals.signal(true)
  let modal = @signals.signal(false)
  let outer_over : Ref[() -> Bool] = Ref(fn() { false })
  let inner_over : Ref[() -> Bool] = Ref(fn() { false })
  let drops : Array[String] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      outer_over.val = files_into_node(page, fn(_) { drops.push("outer") })
      page.box(fn(cut) {
        cut.width(Is(Some(50.0))).height(Is(Some(60.0))).bounds_input(Is(true)) |> ignore
        cut.show(fn() { visible.get() }, fn(folder) {
          folder.width(Is(Some(100.0))).height(Is(Some(60.0))) |> ignore
          inner_over.val = files_into_node(folder, fn(_) { drops.push("folder") }, when=fn() { writable.get() })
        })
      }) |> ignore
    }) |> ignore
    root.show(fn() { modal.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)).width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
    })
  })
  t.draw()
  t.hold_files(Some((20.0, 20.0)))
  t.frame()
  assert_true((inner_over.val)())
  writable.set(false)
  t.draw()
  assert_false((inner_over.val)())
  assert_true((outer_over.val)())
  writable.set(true)
  t.draw()
  assert_true((inner_over.val)())
  visible.set(false)
  t.draw()
  assert_false((inner_over.val)())
  assert_true((outer_over.val)())
  visible.set(true)
  t.draw()
  t.hold_files(Some((80.0, 20.0)))
  t.frame()
  assert_false((inner_over.val)())
  assert_true((outer_over.val)())
  modal.set(true)
  t.draw()
  assert_false((outer_over.val)())
  t.drop_files(80.0, 20.0, [("blocked", b"")])
  t.frame()
  assert_eq(drops, [])
}

///|
test "external files: the deepest target receives a drop in its control's press room" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=3)
  let folder_id : Ref[@view.NodeId?] = Ref(None)
  let outer_over : Ref[() -> Bool] = Ref(fn() { false })
  let inner_over : Ref[() -> Bool] = Ref(fn() { false })
  let drops : Array[String] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      outer_over.val = files_into_node(page, fn(_) { drops.push("outer") })
      page.box(fn(folder) {
        folder.offset(Is((80.0, 80.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).on_press(fn() {}) |> ignore
        folder_id.val = Some(folder.id())
        inner_over.val = files_into_node(folder, fn(_) { drops.push("folder") })
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(match view_app.val {
    Some(tree) => match tree.target_at(75.0, 90.0) { Pressed(id) => Some(id) == folder_id.val; _ => false }
    None => false
  })
  t.hold_files(Some((75.0, 90.0)))
  t.frame()
  assert_true((inner_over.val)())
  assert_false((outer_over.val)())
  t.drop_files(75.0, 90.0, [("file", b"x")])
  t.frame()
  assert_eq(drops, ["folder"])
}

///|
test "external files: a retained editor keeps Finder paths before its enclosing file target" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let draft = Field::new(text="draft")
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      files_into_node(page, fn(p) { drops.push(p) }) |> ignore
      field(page, draft, placeholder="editor") |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, _, h) = t.rect_of("editor").unwrap()
  t.drop_files(x + 1.0, y + h / 2.0, [("file", b"x")], paths=["/tmp/file"])
  t.frame()
  assert_eq(drops.length(), 0)
  assert_true(draft.text().contains("/tmp/file"))
  // A host that gives no paths has nothing to paste, as with the old take_drop contract.
  t.drop_files(x + 1.0, y + h / 2.0, [("no-path", b"z")])
  t.frame()
  assert_eq(drops.length(), 1)
  t.draw()
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["no-path"]))
  t.drop_files(200.0, 180.0, [("next", b"y")], paths=["/tmp/next"])
  t.frame()
  assert_eq(drops.length(), 2)
  t.draw()
  assert_eq(drops[1].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["next"]))
}

///|
test "external files: a moving old island updates a stationary drag's target" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let island_x = @signals.signal(100.0)
  let over : Ref[() -> Bool] = Ref(fn() { false })
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      over.val = files_into_node(page, fn(_) {})
      old(page, fn(c) {
        let id = c.id("moving-old-target")
        c.clicked(id) |> ignore
        c.box(id~, w=Px(50.0), h=Px(50.0), points=true, fn() {}) |> ignore
      }).offset(By(fn() { (island_x.get(), 0.0) })).width(Is(Some(50.0))).height(Is(Some(50.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  t.hold_files(Some((20.0, 20.0)))
  t.frame()
  assert_true((over.val)())
  island_x.set(0.0)
  t.draw()
  assert_false((over.val)())
  island_x.set(100.0)
  t.draw()
  assert_true((over.val)())
}

///|
test "external files: an old island takes its own drop before its enclosing retained target" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let over : Ref[() -> Bool] = Ref(fn() { false })
  let old_drops : Array[Pick] = []
  let new_drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      over.val = files_into_node(page, fn(p) { new_drops.push(p) })
      old(page, fn(c) {
        let id = c.id("old-file-target")
        c.clicked(id) |> ignore
        c.box(id~, w=Px(100.0), h=Px(80.0), points=true, fn() {
          c.text("old target") |> ignore
        }) |> ignore
        match take_drop(over=fn(x, y) { x < 50.0 && y < 80.0 }) {
          Some((_, _, p)) => old_drops.push(p)
          None => ()
        }
      }).width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  t.hold_files(Some((20.0, 20.0)))
  t.frame()
  assert_false((over.val)())
  t.drop_files(20.0, 20.0, [("old", b"x")], paths=["/tmp/old"])
  t.frame()
  assert_eq(old_drops.length(), 1)
  assert_eq(new_drops.length(), 0)
  t.draw()
  assert_eq(old_drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["old"]))
  // The old island has first chance on this point too, but does not accept it: the parent can still take it.
  t.drop_files(80.0, 20.0, [("fallback", b"z")], paths=["/tmp/fallback"])
  t.frame()
  assert_eq(old_drops.length(), 1)
  assert_eq(new_drops.length(), 1)
  t.draw()
  assert_eq(new_drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["fallback"]))
  t.drop_files(200.0, 180.0, [("new", b"y")], paths=["/tmp/new"])
  t.frame()
  assert_eq(old_drops.length(), 1)
  assert_eq(new_drops.length(), 2)
  t.draw()
  assert_eq(new_drops[1].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["new"]))
}

///|
test "external files: consecutive Finder drops preserve an old field's paths and the new target's pick" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let draft = Field::new(text="")
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      files_into_node(page, fn(p) { drops.push(p) }) |> ignore
      old(page, fn(c) {
        c.editor("e", field=draft, placeholder="old editor", font_size=10.0, plain=true, enter_sends=false) |> ignore
      }).width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.rect_of("old editor").unwrap()
  t.drop_files(x + w - 4.0, y + h / 2.0, [("first", b"1")], paths=["/tmp/first"])
  t.drop_files(x + w - 4.0, y + h / 2.0, [("second", b"2")], paths=["/tmp/second"])
  t.drop_files(200.0, 180.0, [("third", b"3")], paths=["/tmp/third"])
  t.frame()
  t.draw()
  assert_true(draft.text().contains("/tmp/first"))
  assert_true(draft.text().contains("/tmp/second"))
  assert_eq(drops.length(), 1)
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["third"]))
}

///|
test "external files: a retained target above an old field takes the drop" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let draft = Field::new(text="draft")
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      old(page, fn(c) {
        c.editor("e", field=draft, placeholder="old editor", font_size=10.0, plain=true, enter_sends=false) |> ignore
      }).width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
    }) |> ignore
    root.box(fn(cover) {
      cover.over(Is(true)).width(Is(Some(250.0))).height(Is(Some(200.0))).ground(Is(0x123456FFL)) |> ignore
      files_into_node(cover, fn(p) { drops.push(p) }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, _, h) = t.rect_of("old editor").unwrap()
  t.drop_files(x + 1.0, y + h / 2.0, [("covered", b"x")], paths=["/tmp/covered"])
  t.frame()
  t.draw()
  assert_eq(draft.text(), "draft")
  assert_eq(drops.length(), 1)
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["covered"]))
}

///|
test "external files: a retained target above a retained field takes Finder paths as files" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=0)
  let draft = Field::new(text="draft")
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      field(page, draft, placeholder="covered editor") |> ignore
    }) |> ignore
    root.box(fn(cover) {
      cover.over(Is(true)).width(Is(Some(250.0))).height(Is(Some(200.0))).ground(Is(0x123456FFL)) |> ignore
      files_into_node(cover, fn(p) { drops.push(p) }) |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, _, h) = t.rect_of("covered editor").unwrap()
  t.drop_files(x + 1.0, y + h / 2.0, [("covered", b"x")], paths=["/tmp/covered"])
  t.frame()
  t.draw()
  assert_eq(draft.text(), "draft")
  assert_eq(drops.length(), 1)
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["covered"]))
}

///|
test "external files: Explorer's pick hovers and lands on a target even over its editor" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=3)
  let over : Ref[() -> Bool] = Ref(fn() { false })
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      over.val = files_into_node(page, fn(p) { drops.push(p) })
      field(page, Field::new(), placeholder="editor") |> ignore
    }) |> ignore
  })
  t.draw()
  let (x, y, _, h) = t.rect_of("editor").unwrap()
  t.hold_files(Some((x + 1.0, y + h / 2.0)))
  t.frame()
  assert_true((over.val)())
  t.drop_files(x + 1.0, y + h / 2.0, [("file", b"x")])
  t.frame()
  assert_eq(drops.length(), 1)
  t.draw()
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["file"]))
}

///|
test "external files: two drops before a frame deliver two distinct asynchronous picks once each" {
  let t = Tester::new(fn(_) {}, w=300.0, h=240.0, platform=3)
  let drops : Array[Pick] = []
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(250.0))).height(Is(Some(200.0))) |> ignore
      files_into_node(page, fn(p) { drops.push(p) }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.drop_files(20.0, 20.0, [("first", b"1")])
  t.drop_files(20.0, 20.0, [("second", b"2")])
  t.frame()
  assert_eq(drops.length(), 2)
  assert_true(drops[0].files() is None)
  assert_true(drops[1].files() is None)
  t.draw()
  assert_eq(drops[0].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["first"]))
  assert_eq(drops[1].files().map(fn(fs) { fs.map(fn(f) { f.name }) }), Some(["second"]))
  t.draw()
  assert_eq(drops.length(), 2)
}
