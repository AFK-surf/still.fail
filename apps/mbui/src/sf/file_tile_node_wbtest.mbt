// A file tile keeps its shape while the file, upload and theme change.

///|
test "a file tile node shows each file state in both themes" {
  for dark in [false, true] {
    set_dark(Some(dark))
    for sample in [
      ("README", false, None, false, ""),
      ("file.txt", false, None, false, "TXT"),
      ("file.abcde", false, Some(0.5), false, "ABCDE"),
      ("file.abcdef", false, Some(1.0), false, ""),
      ("failed.pdf", false, Some(0.3), true, "PDF"),
      ("folder", true, Some(0.5), true, ""),
    ] {
      let (name, dir, progress, error, extension) = sample
      let tile : Ref[@view.View?] = Ref(None)
      let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=120.0, h=120.0)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(ui_theme_now)
        root.padding(Is((40.0, 40.0, 0.0, 0.0))) |> ignore
        tile.val = Some(file_tile_node(root, fn() { name }, dir=fn() { dir },
          progress=fn() { progress }, error=fn() { error }))
      })
      t.draw()
      assert_eq(tile.val.unwrap().laid_window_now(), (40.0, 40.0, 30.0, 36.0))
      assert_true(t.drawn_shapes().iter().any(fn(shape) { shape.5 == theme().p.muted }), msg="\{name}: outline")
      if extension != "" {
        assert_true(t.find(extension) is Some(_), msg="\{name}: uppercase extension")
        assert_eq(t.all(Text, label=extension).length(), 1, msg="\{name}: extension read once")
      } else if !dir {
        assert_true(t.shape_cover(50.0, 59.0) > 0.0, msg="\{name}: lines in the sheet")
      }
      if dir {
        assert_false(t.drawn_shapes().iter().any(fn(shape) { shape.5 == alpha(theme().p.accent, tile_fill_share) }), msg="folder has no upload fill")
      } else if progress is Some(_) {
        assert_true(t.drawn_shapes().iter().any(fn(shape) { shape.5 == alpha(theme().p.accent, tile_fill_share) }), msg="\{name}: upload fill")
      }
      assert_true(t.all(Button).is_empty(), msg="the file tile is not a control")
    }
  }
  set_dark(None)
}

///|
test "a file tile node follows its name, progress, failure, folder and theme" {
  set_dark(Some(false))
  let name = @signals.signal("README", same=fn(a, b) { a == b })
  let dir = @signals.signal(false, same=fn(a, b) { a == b })
  let progress : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  let error = @signals.signal(false, same=fn(a, b) { a == b })
  let tile : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=120.0, h=120.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((40.0, 40.0, 0.0, 0.0))) |> ignore
    tile.val = Some(file_tile_node(root, fn() { name.get() }, dir=fn() { dir.get() },
      progress=fn() { progress.get() }, error=fn() { error.get() }))
  })
  t.draw()
  let id = tile.val.unwrap().id()
  assert_eq(tile.val.unwrap().laid_window_now(), (40.0, 40.0, 30.0, 36.0))
  // No extension: two strokes in the sheet; a five-character extension is shown in uppercase.
  assert_true(t.shape_cover(50.0, 59.0) > 0.0)
  assert_true(t.shape_cover(50.0, 63.5) > 0.0)
  name.set("image.abcde")
  t.draw()
  assert_true(t.find("ABCDE") is Some(_))
  assert_eq(t.shape_cover(50.0, 59.0), 0.0)
  // The old tile counts the dot too: six extension characters and a leading dot show the strokes.
  name.set("image.abcdef")
  t.draw()
  assert_true(t.find("ABCDEF") is None)
  assert_true(t.shape_cover(50.0, 59.0) > 0.0)
  name.set(".hidden")
  t.draw()
  assert_true(t.find("HIDDEN") is None)
  assert_true(t.shape_cover(50.0, 59.0) > 0.0)
  name.set("image.png")
  progress.set(Some(0.5))
  t.draw()
  let fill = alpha(theme().p.accent, tile_fill_share)
  assert_true(t.drawn_shapes().iter().any(fn(s) { s.5 == fill }))
  assert_true(t.shape_cover(50.0, 68.0) > 0.9)
  assert_eq(t.shape_cover(50.0, 50.0), 0.0)
  progress.set(Some(-1.0))
  t.draw()
  assert_eq(t.shape_cover(50.0, 68.0), 0.0)
  progress.set(Some(2.0))
  t.draw()
  assert_true(t.shape_cover(50.0, 50.0) > 0.9)
  error.set(true)
  t.draw()
  let words = @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words == "PNG" }).unwrap()
  assert_eq(words.ink, @ui.style_ink(tile_ext_failed))
  set_dark(Some(true))
  t.draw()
  let dark_words = @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.words == "PNG" }).unwrap()
  assert_eq(dark_words.ink, @ui.style_ink(tile_ext_failed))
  assert_true(t.drawn_shapes().iter().any(fn(s) { s.5 == theme().p.muted }))
  dir.set(true)
  t.draw()
  assert_true(t.find("PNG") is None)
  assert_false(t.drawn_shapes().iter().any(fn(s) { s.5 == alpha(theme().p.accent, tile_fill_share) }))
  assert_eq(tile.val.unwrap().id(), id)
  set_dark(None)
}

///|
test "a file tile node scales about its centre without changing its layout and is released with its parent" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let tile : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=160.0, h=160.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((40.0, 40.0, 0.0, 0.0))) |> ignore
    root.show(fn() { shown.get() }, fn(parent) {
      let v = file_tile_node(parent, fn() { "file.txt" })
      tile.val = Some(v)
      v.scale(Is(2.0)) |> ignore
    })
  })
  t.draw()
  let v = tile.val.unwrap()
  let (_, _, w, h) = v.laid_window_now()
  assert_eq((w, h), (30.0, 36.0))
  assert_eq(v.drawn_scale(), 2.0)
  let drawn = @ui.view_tree().unwrap().drawn().iter().find_first(fn(d) { d.id == v.id() }).unwrap()
  assert_eq((drawn.w, drawn.h), (60.0, 72.0))
  assert_false(@ui.view_tree().unwrap().said_order().iter().any(fn(s) {
    s.said.map(fn(said) { said.role == Button }).unwrap_or(false)
  }))
  shown.set(false)
  t.draw()
  assert_false(v.alive())
  shown.set(true)
  t.draw()
  assert_true(tile.val.unwrap().alive())
  assert_true(tile.val.unwrap().id() != v.id())
}
