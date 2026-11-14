// A chat's Farview tab drawn here (farview_tab.mbt), over a core made up for it: `farview.view` asked as it is shown,
// the stage's Hello said as it goes live, the host's bytes drawn as tiles of the page, a tap said to the host, and the
// view let go as the tab goes.

///|
priv struct FarviewRig {
  t : @ui.Tester
  /// what was sent by `farview.send`, in order
  sent : Array[Bytes]
  /// the views asked (`farview.view`): what each is told, and how many were let go
  views : Array[(Json, (Json, Bytes?) -> Unit)]
  cancelled : Array[Int]
  shown : @signals.Signal[Bool]
}

///|
fn farview_rig() -> FarviewRig {
  @sfbase.reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  @sf.set_dark(Some(false))
  let sent : Array[Bytes] = []
  let views : Array[(Json, (Json, Bytes?) -> Unit)] = []
  let cancelled : Array[Int] = []
  let base = @sfbase.made_source(topic=fn(name, _) { if name == "prefs" { Some(Json::object({})) } else { None } })
  let src : Source = {
    ..base,
    call_bytes: fn(name, _, bytes, done) {
      if name == "farview.send" {
        sent.push(bytes)
      }
      done(Ok(Json::null()))
    },
    stream: fn(name, params, bytes, on_value, done) {
      if name != "farview.view" {
        return (base.stream)(name, params, bytes, on_value, done)
      }
      views.push((params, on_value))
      views.length()
    },
    cancel: fn(id) { cancelled.push(id) },
  }
  let shown = @signals.signal(true)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() { @ui.old_views_here(c) })
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.show(fn() { shown.get() }, fn(p) {
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        farview_tab_node(p, src, "ws-1/st-1", "browser:fv_t1")
      })
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  { t, sent, views, cancelled, shown }
}

///|
/// What the host says of a page 390 wide and 1000 tall: its address, then a frame of one piece, red with a white box.
fn farview_page_bytes() -> Bytes {
  let ops : Array[@proto.Op] = [Rect(0.0, 0.0, 390.0, 1000.0, 0xFF0000FF), Rect(20.0, 20.0, 100.0, 40.0, 0xFFFFFFFF)]
  let out = Buffer()
  out.write_bytes(@proto.encode(Page("https://example.test/")))
  out.write_bytes(@proto.encode(Frame(390.0, 1000.0, [(1, 1000.0)], [(1, ops)])))
  out.to_bytes()
}

///|
/// What `bytes` say, as messages.
fn farview_said(bytes : Bytes) -> Array[@proto.Message] {
  let framer = @proto.Framer::new()
  framer.push(bytes)
  let out = []
  while framer.next() is Some(body) {
    out.push(@proto.decode(body))
  }
  out
}

///|
test "a Farview tab: asked as shown, Hello as it goes live, the page drawn in tiles, a tap the host's, let go as it goes" {
  let r = farview_rig()
  // asked as it is shown, of its station and its tab
  assert_eq(r.views.length(), 1)
  let (params, tell) = r.views[0]
  guard params is Object(p) else { fail("no params") }
  assert_eq((p.get("station"), p.get("screen")), (Some(Json::string("ws-1/st-1")), Some(Json::string("browser:fv_t1"))))
  // live: its viewport said to the host (the stage's room, the window's scale)
  tell(Json::object({ "state": Json::object({ "phase": "live", "opens": Json::number(1.0) }) }), None)
  r.t.draw()
  let hello = r.sent.map(fn(b) { farview_said(b) }).flatten()
  guard hello is [Hello(w, h, scale), ..] else { fail("no Hello: \{hello.length()} said") }
  assert_eq((w, scale), (390.0, 2.0))
  assert_true(h > 600.0 && h < 844.0)
  // the page: its tiles drawn (1000 tall: three of 400)
  tell(Json::object({ "data": Json::boolean(true) }), Some(farview_page_bytes()))
  r.t.draw()
  let tiles = r.t.drawlist_images().filter(fn(i) { i.1.has_prefix("farview-") })
  assert_true(tiles.length() >= 2)
  // a tap on the page: the host's, at that point of the page
  r.sent.clear()
  r.t.tap(60.0, h / 2.0 + (844.0 - h))
  r.t.draw()
  let taps = r.sent.map(fn(b) { farview_said(b) }).flatten().filter(fn(m) { m is Tap(_, _) })
  assert_eq(taps.length(), 1)
  // gone: the view let go
  r.shown.set(false)
  r.t.draw()
  assert_eq(r.cancelled.length(), 1)
}
