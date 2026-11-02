// A film's or a song's viewer round its player, as main's does it, its old views wherever the window's tree hosts them
// (the chat an old view, the viewer its node beside it, as the shells have it): closed into its thumbnail with the
// frame it shows, the grab's answer late or empty; the desktop's Escape leaving the player's speeds before the viewer;
// none of its still drawn twice as it flies.

///|
/// The chat's video 演示录屏.mp4 alone in a column, an old view the window's tree hosts, the viewer its node beside it,
/// `w` wide (`platform`'s).
fn media_tree(w? : Double = 390.0, platform? : Int = 0) -> @ui.Tester {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, name) { fixture_file(name) } }
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
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
          preview(c, src)
        })
        .over(Is(true))
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
test "a video closed, the frame it shows grabbed and its answer late (past a whole flight's time): its player's picture held where it was, nothing let go, till then; answered, back with that frame from there, then gone, its player closed once" {
  let t = media_tree()
  media_opened(t)
  let v = viewer.get().unwrap()
  let m = v.media
  guard t.holes() is [hole] else { fail("its player's picture: \{t.holes()}") }
  t.back()
  assert_true(t.views().contains("control 1 22 640"), msg="its frame asked for")
  for _ in 0..<4 {
    t.run_for(@ui.move_most_ms / 2.0)
    assert_true(viewer.get() is None && pv_leaving.get().map(fn(l) { physical_equal(l, v) }) == Some(true), msg="going, the same viewer")
    assert_true(physical_equal(v.media, m), msg="its player the same")
    assert_true(t.holes() is [h] && media_near(h, hole), msg="its player's picture where it was: \{t.holes()}, was \{hole}")
    assert_eq(media_closed(t), 0, msg="its player not closed")
  }
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
  assert_true(media_drawn(t, kept) is [r] && media_near(r, hole), msg="its frame flying from where its picture was: \{media_drawn(t, kept)}, was \{hole}")
  t.run_for(@ui.move_most_ms)
  assert_true(pv_leaving.get() is None && media_closed(t) == 1, msg="landed: gone, its player closed once (\{media_closed(t)})")
}

///|
test "a video closed, its frame's grab answered with nothing: back into its thumbnail with its still from where its picture was, nothing kept, then gone" {
  let t = media_tree()
  media_opened(t)
  let v = viewer.get().unwrap()
  guard t.holes() is [hole] else { fail("its player's picture: \{t.holes()}") }
  t.back()
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\"}"))
  t.draw()
  assert_eq(t.holes().length(), 0, msg="flown back")
  assert_true(pv_frames.is_empty(), msg="nothing kept")
  assert_true(v.fly_pic != "" && media_drawn(t, v.fly_pic) is [r] && media_near(r, hole), msg="its still \{v.fly_pic} flying from where its picture was: \{media_drawn(t, v.fly_pic)}, was \{hole}")
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
    assert_eq(drawn.length(), 1, msg="at \{k}/5: its still \{still} drawn \{drawn}")
  }
}

///|
test "a desktop's video over its chat, its speeds opened: Escape closes them, the viewer still up; Escape again closes the viewer" {
  new_run()
  let src = fixture("chat-preview-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
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
