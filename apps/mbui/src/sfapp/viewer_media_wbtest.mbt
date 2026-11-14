// A film's or a song's viewer round its player, as main's does it, its old views wherever the window's tree hosts them
// (the chat an old view, the viewer its node beside it, as the shells have it): closed into its thumbnail with the
// frame it shows, the grab's answer late or empty; the desktop's Escape leaving the player's speeds before the viewer;
// none of its still drawn twice as it flies.

///|
/// The chat's video 演示录屏.mp4 alone in a column, an old view the window's tree hosts, the viewer its node beside it,
/// `w` wide (`platform`'s); over the chat, under the viewer, a button of the tree's at the window's foot (按下 said in
/// `pressed` each time it is pressed).
fn media_tree(w? : Double = 390.0, platform? : Int = 0, pressed? : Array[Int] = [], sent? : (Double, Double) = (1280.0, 720.0)) -> @ui.Tester {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, name) { fixture_file(name) } }
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: sent.0,
    height: sent.1,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.box(fn(v) {
        v.grow(Is(1.0)) |> ignore
        @ui.old(v, fn(c) {
          c.box(style=@ui.style(w=Full, h=Full), fn() { chat_file(c, src, a) }) |> ignore
        })
        .over(Is(true))
        |> ignore
        v.box(fn(f) {
          f.over(Is(true)).padding(Is((0.0, 760.0, 0.0, 0.0))) |> ignore
          @sf.button_node(f, fn() { "树按钮" }, fn() { pressed.push(1) }) |> ignore
        })
        |> ignore
        @sfbase.viewer_node(v, src, fn() { v.window() })
      })
      |> ignore
    },
    w~,
    h=844.0,
    platform~,
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  t
}

///|
/// 演示录屏.mp4 opened from its thumbnail and in, its player 4 s in.
fn media_opened(t : @ui.Tester) -> Unit raise {
  tap_video(t, "演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  t.set_player(1, position=4000.0)
  t.draw()
}

///|
/// Where picture `src` is drawn now, seen (its alpha above nothing): each instance's (x, y, w, h).
fn media_drawn(t : @ui.Tester, src : String) -> Array[(Double, Double, Double, Double)] {
  t.drawn_instances().filter_map(fn(i) {
    if i[5] == 4.0 && i[11] > 0.0 && t.image_src(i[20].to_int()) == src {
      Some((i[0], i[1], i[2], i[3]))
    } else {
      None
    }
  })
}

///|
/// Whether `a` and `b` are the same box, to half a point.
fn media_near(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  (a.0 - b.0).abs() < 0.5 && (a.1 - b.1).abs() < 0.5 && (a.2 - b.2).abs() < 0.5 && (a.3 - b.3).abs() < 0.5
}

///|
/// How many times its player was closed.
fn media_closed(t : @ui.Tester) -> Int {
  t.views().filter(fn(l) { l == "close 1" }).length()
}

///|
test "a video closed, the frame it shows grabbed and its answer late (past a whole flight's time): its player's picture held where it was, nothing let go, till then (a button of the tree's under it pressed meanwhile, its own); answered, back with that frame from there, then gone, its player closed once" {
  let pressed : Array[Int] = []
  let t = media_tree(pressed~)
  media_opened(t)
  let v = viewer.get().unwrap()
  let m = v.media
  guard t.holes() is [hole] else { fail("its player's picture: \{Repr(t.holes())}") }
  t.back()
  assert_true(t.views().contains("control 1 22 640"), msg="its frame asked for")
  for _ in 0..<4 {
    t.run_for(@ui.move_most_ms / 2.0)
    assert_true(viewer.get() is None && pv_leaving.get().map(fn(l) { physical_equal(l, v) }) == Some(true), msg="going, the same viewer")
    assert_true(physical_equal(v.media, m), msg="its player the same")
    assert_true(t.holes() is [h] && media_near(h, hole), msg="its player's picture where it was: \{Repr(t.holes())}, was \{Repr(hole)}")
    assert_eq(media_closed(t), 0, msg="its player not closed")
  }
  // (going, nothing of it takes a press: the button under it its own, the player not closed by it)
  match t.all(@ui.Role::Button, label="树按钮") {
    [b] => {
      let (x, y, w, h) = b.rect
      t.tap(x + w / 2.0, y + h / 2.0)
    }
    other => fail("the tree's button: \{Repr(other)}")
  }
  t.run_for(@ui.frame_period_default)
  assert_eq((pressed, media_closed(t)), ([1], 0), msg="the button under it pressed, its player not closed")
  let frame = fixture_file_png("演示录屏.mp4")
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\{hex_bytes(frame)}\"}"))
  t.draw()
  assert_eq(t.holes().length(), 0, msg="answered: flown back")
  let kept = match pv_frames.get("ws1/st1/s-c1/uploads/fx/演示录屏.mp4") {
    Some((key, ms)) => {
      assert_eq(ms, 4000.0, msg="its frame kept with where it was")
      key
    }
    None => fail("no frame kept")
  }
  assert_true(media_drawn(t, kept) is [r] && media_near(r, hole), msg="its frame flying from where its picture was: \{Repr(media_drawn(t, kept))}, was \{Repr(hole)}")
  t.run_for(@ui.move_most_ms)
  assert_true(pv_leaving.get() is None && media_closed(t) == 1, msg="landed: gone, its player closed once (\{media_closed(t)})")
}

///|
test "a video closed, its frame's grab answered with nothing: back into its thumbnail with its still from where its picture was, nothing kept, then gone" {
  let t = media_tree()
  media_opened(t)
  let v = viewer.get().unwrap()
  guard t.holes() is [hole] else { fail("its player's picture: \{Repr(t.holes())}") }
  t.back()
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\"}"))
  t.draw()
  assert_eq(t.holes().length(), 0, msg="flown back")
  assert_true(pv_frames.is_empty(), msg="nothing kept")
  assert_true(v.fly_pic != "" && media_drawn(t, v.fly_pic) is [r] && media_near(r, hole), msg="its still \{v.fly_pic} flying from where its picture was: \{Repr(media_drawn(t, v.fly_pic))}, was \{Repr(hole)}")
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None && media_closed(t) == 1, msg="gone, its player closed once")
}

///|
test "a video opened from its thumbnail: at each of four moments of its flight in, its still drawn once (the thumbnail hidden), never twice" {
  let t = media_tree()
  tap_video(t, "演示录屏.mp4")
  let v = viewer.get().unwrap()
  let (from, to) = (v.fly.starts_at(), v.fly.ends_at())
  assert_true(v.flies && !v.fly_back && to > from, msg="set out as a flight in")
  for k in 1..=4 {
    let at = from + (to - from) * k.to_double() / 5.0
    t.run_for(at - t.ctx().moment())
    assert_true(v.flies && !v.fly_back && v.fly.goes_at(t.ctx().moment()), msg="at \{k}/5: still flying in")
    let still = if v.fly_pic != "" { v.fly_pic } else { v.still(fixture("chat")) }
    let drawn = media_drawn(t, still)
    assert_eq(drawn.length(), 1, msg="at \{k}/5: its still \{still} drawn \{Repr(drawn)}")
  }
}

///|
test "a desktop's video over its chat, its speeds opened: Escape closes them, the viewer still up; Escape again closes the viewer" {
  new_run()
  let src = fixture("chat-preview-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="up")
  t.click(@ui.Role::Button, label="播放速度")
  t.draw()
  assert_true(t.find("0.25×") is Some(_), msg="its speeds shown")
  t.key(@ui.key_escape)
  t.draw()
  assert_true(t.find("0.25×") is None && viewer.get() is Some(_), msg="its speeds closed, the viewer up")
  t.key(@ui.key_escape)
  t.draw()
  assert_true(viewer.get() is None, msg="the viewer closing")
}

///|
test "a film played on an iPhone Duo, the window from wide to Small with its actions in the system's bars: 全屏 there then turns it sideways (a phone's), the window not filled" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-preview-video")
  t.run_for(@ui.move_most_ms)
  assert_true(t.nav_said().contains("over/full"), msg="wide: its 全屏 there: \{t.nav_said()}")
  // (laid out Small now: its 全屏 a phone's, turning it sideways)
  t.resize(390.0, 844.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.nav_said().contains("over/full"), msg="Small: its 全屏 there: \{t.nav_said()}")
  t.post(@hostapi.system_channel, "{\"nav\":\"over/full\"}")
  t.run_for(@ui.move_most_ms)
  let m = viewer.get().unwrap().media.unwrap()
  assert_true(m.is_sideways() && !@sf.player_full_native(), msg="turned sideways, the window not filled")
  m.upright()
}

///|
test "a video sent with no size, its still's known: opened from its thumbnail, its flight sets out at once from the thumbnail with its still, as big as it is there, in the very frame it opens" {
  let t = media_tree(sent=(0.0, 0.0))
  guard t.reachable("演示录屏.mp4") is [(x, y), ..] else { fail("no video") }
  // (where the thumbnail is: its still as the chat draws it)
  let thumbs = t.drawn_images().filter(fn(i) { i[2] > 100.0 })
  guard thumbs is [th] else { fail("its thumbnail: \{Repr(thumbs)}") }
  // (each frame drawn from the press on, as it is drawn: whether the viewer is up, and where its still is)
  let seen : Array[(Bool, Array[(Double, Double, Double, Double)])] = []
  t.each_frame(
    Some(fn() {
      match viewer.get() {
        Some(v) => seen.push((v.flies && !v.fly_back, media_drawn(t, v.still(fixture("chat")))))
        None => ()
      }
    }),
  )
  t.tap(x, y)
  t.each_frame(None)
  let v = viewer.get().unwrap()
  let still = v.still(fixture("chat"))
  assert_true(v.file.width == 0.0 && @ui.image_natural(still) is Some((sw, sh)) && sw > 0.0 && sh > 0.0, msg="sent with no size, its still's known: \{Repr(@ui.image_natural(still))}")
  // (the first frame it is up in: flying, its still once, where its thumbnail was, as big)
  guard seen.get(0) is Some((flying, drawn)) else { fail("no frame drawn with it up") }
  assert_true(flying, msg="set out as a flight in its first frame")
  assert_true(
    drawn is [r] && (r.0 - th[0]).abs() < 1.0 && (r.1 - th[1]).abs() < 1.0 && (r.2 - th[2]).abs() < 1.0 && (r.3 - th[3]).abs() < 1.0,
    msg="its still where its thumbnail was, in its first frame: \{Repr(drawn)}, the thumbnail \{Repr(th)} (frames: \{seen.length()})",
  )
}
