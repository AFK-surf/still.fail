///|
/// An image's zoom 400 by 300 over a picture 1600 by 1200, its tools as an old view draws them (viewer_zoom, after
/// Zoom::step as the old viewer draws the picture: its per cent read of the field step copies the glide into) at the
/// window's top left, and as nodes (zoom_tools_node) 100 down, in a window 700 wide (wider than a phone: the zoom shown).
fn zoom_pair() -> (@ui.Tester, @kit.Zoom) {
  let tt = @ui.Tester::new(fn(_c) {  }, w=700.0, h=300.0)
  tt.check_looks(false)
  let z = @kit.Zoom::new()
  z.boxed(400.0, 300.0)
  z.natural(1600.0, 1200.0)
  @ui.set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(700.0))).height(Is(Some(100.0))) |> ignore
      @ui.old(h, fn(c) {
        z.step()
        viewer_zoom(c, "old", z, page_viewer_ink())
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    zoom_tools_node(root, z, fn() { page_viewer_ink() }, Is(tool_side / 2.0), tip=tips) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  tt.draw()
  (tt, z)
}

///|
/// The tool read out as `label`, the old view's (above 100) or the node's.
fn zoom_tool(tt : @ui.Tester, label : String, node : Bool) -> @ui.SemNode raise {
  let found = tt.all(Button, label~).filter(fn(b) { (b.rect.1 >= 100.0) == node })
  assert_eq(found.length(), 1, msg="\{label} (node \{node}): \{found.length()}")
  found[0]
}

///|
/// The zoom's four tools' words (read out).
fn zoom_labels() -> Array[String] {
  [t("web-main.preview.zoomOutKey"), t("web-main.preview.fitKey"), t("web-main.preview.zoomInKey"), t("web-main.preview.actualKey")]
}

///|
/// What each of the zoom's tools draws, the old view's and the node's, each within its own box.
fn zoom_drawn(tt : @ui.Tester) -> (Array[Array[String]], Array[Array[String]]) raise {
  let old = []
  let new = []
  for l in zoom_labels() {
    old.push(drawn_within(tt, zoom_tool(tt, l, false).rect))
    new.push(drawn_within(tt, zoom_tool(tt, l, true).rect))
  }
  (old, new)
}

///|
test "an image's zoom as nodes drawn as the old bar's: at rest, each with the pointer over it, the keyboard's focus as the pointer over it; through a glide at the frames' moments its per cent as the old one's, the clock read no more once it is there" {
  let (tt, z) = zoom_pair()
  tt.leave()
  let (old, new) = zoom_drawn(tt)
  assert_eq(new, old, msg="at rest")
  for l in zoom_labels() {
    let o = zoom_tool(tt, l, false)
    tt.move(o.rect.0 + o.rect.2 / 2.0, o.rect.1 + o.rect.3 / 2.0)
    let old_hovered = drawn_within(tt, o.rect)
    let n = zoom_tool(tt, l, true)
    tt.move(n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
    let new_hovered = drawn_within(tt, n.rect)
    assert_eq(new_hovered, old_hovered, msg="\{l}: the pointer over it")
    // (the keyboard's focus on it, the pointer away: drawn as the pointer over it, the user's)
    tt.leave()
    let mut tabs = 0
    while tt.ctx().focused_id() != n.id && tabs < 20 {
      tt.tab()
      tabs += 1
    }
    assert_eq(tt.ctx().focused_id(), n.id, msg="\{l}: the focus by Tab")
    assert_eq(drawn_within(tt, n.rect), new_hovered, msg="\{l}: the focus as the pointer over it")
    tt.tap(690.0, 290.0)
  }
  tt.leave()
  // (in a quarter, gliding: the per cent at a few of the frames' moments, the node's as the old one's)
  let fit = z.fit()
  z.zoom_to(fit * viewer_zoom_step, 200.0, 150.0, true, at=tt.time())
  let end = z.glide_ends()
  let start = tt.time()
  let seen : Array[String] = []
  for k in [1, 2, 3] {
    tt.run_for(start + (end - start) * k.to_double() / 4.0 - tt.time())
    let (old, new) = zoom_drawn(tt)
    assert_eq(new[1], old[1], msg="its per cent at \{k}/4 of the glide")
    // (its words, as the glyphs drawn say nothing of which they are)
    let mut said = ""
    for d in @ui.view_tree().unwrap().drawn() {
      if d.y >= 100.0 && d.alpha > 0.0 && d.words.has_suffix("%") {
        said = d.words
      }
    }
    assert_eq(said, "\{(z.scale_at(tt.time()) * 100.0).round().to_int()}%", msg="its per cent at \{k}/4: as shown then")
    seen.push(said)
  }
  assert_true(seen[0] != seen[2], msg="counting through: \{seen}")
  let tree = @ui.view_tree().unwrap()
  tt.run_for(end - tt.time() + 1.0)
  let (old, new) = zoom_drawn(tt)
  assert_eq(new, old, msg="there")
  assert_true(!tree.clock_read(), msg="there: the clock read no more")
}

///|
/// + pressed by a finger at `first`, then again `apart` ms after with no frame drawn between (`frames`: the frames
/// drawn between, at the display's pace): where the second sends it (the scale the glide it sets out goes to).
fn twice_in(frames : Bool, apart : Double) -> Double raise {
  let (tt, z) = zoom_pair()
  let n = zoom_tool(tt, t("web-main.preview.zoomInKey"), true)
  let (x, y) = (n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
  let first = tt.time()
  tt.touch_raw(0, 1, x, y, first)
  tt.touch_raw(2, 1, x, y, first)
  if frames {
    tt.run_for(apart)
  } else {
    tt.advance(apart)
  }
  tt.touch_raw(0, 1, x, y, first + apart)
  tt.touch_raw(2, 1, x, y, first + apart)
  let end = z.glide_ends()
  z.scale_at(end)
}

///|
test "an image's zoom as nodes: a press from how big it is shown at its own moment, the frames drawn between or none; unable at its ends as soon as it is told, no frame drawn" {
  let apart = 60.0
  let drawn = twice_in(true, apart)
  let none = twice_in(false, apart)
  assert_eq(none, drawn, msg="the second + from where the first's glide has it then, whatever frames came")
  let (tt, z) = zoom_pair()
  assert_true(drawn > z.fit() * viewer_zoom_step * 1.01 && drawn < z.fit() * viewer_zoom_step * viewer_zoom_step * 0.99, msg="from part way: \{drawn}")
  // (at the most, told between frames: + unable at once, taking no press; − able)
  z.zoom_to(z.max_scale(), 200.0, 150.0, false, at=tt.time())
  assert_true(zoom_tool(tt, t("web-main.preview.zoomInKey"), true).disabled, msg="at the most: + unable, no frame drawn")
  assert_true(!zoom_tool(tt, t("web-main.preview.zoomOutKey"), true).disabled, msg="− able")
  z.zoom_to(z.min_scale(), 200.0, 150.0, false, at=tt.time())
  assert_true(zoom_tool(tt, t("web-main.preview.zoomOutKey"), true).disabled, msg="at the least: − unable, no frame drawn")
  assert_true(!zoom_tool(tt, t("web-main.preview.zoomInKey"), true).disabled, msg="+ able")
}
