// The viewer's way in from a picture of the chat and back into it (sfbase viewer.mbt draw_flight, shown_picture): it
// sets out as the chat draws its thumbnail, lands where the chat has the thumbnail then, and never shows a frame of
// nothing as one picture of it takes another's place.

///|
/// A photo the station keeps for chat s-c1, its size sent with it.
fn flight_photo() -> Attachment {
  {
    name: "photo.jpg",
    path: "uploads/fx/photo.jpg",
    size: 4096.0,
    width: 1200.0,
    height: 900.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
}

///|
/// The photo's message `shift` down the window with the viewer over it; sent from here (its message drawing the picture
/// picked, `sent-key`), the station's thumbnail never coming; its whole, asked of the station, held until `held` is
/// called.
fn photo_sent(
  shift : Ref[Double],
  held : Ref[(() -> Unit)?],
  bar? : Bool = false,
  cut? : Double = 0.0,
  listed? : Bool = false,
  head? : Bool = false,
) -> @ui.Tester {
  new_run()
  let a = flight_photo()
  @sfbase.sent_pictures[@sfbase.sent_key("ws1/st1", a.path)] = "sent-key"
  let base = fixture("chat")
  let src : Source = {
    ..base,
    file: fn(_, _, _) { "" },
    read_bytes: fn(name, params, done) {
      if name == "station.file" {
        held.val = Some(fn() { done(Ok((Json::object({}), b"photo"))) })
      } else {
        (base.read_bytes)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(
    fn(c) {
      // (in a card `cut` tall, its foot cutting the picture, where one is)
      let card = if cut > 0.0 { @ui.style(w=Full, h=Fixed(cut), clip=true) } else { @ui.style(w=Full, h=Full) }
      // (in a chat's list, the composer's room at its foot, where it is one)
      let list = c.box(style=card, fn() {
        c.box(style=@ui.style(h=Fixed(shift.val)), fn() {  }) |> ignore
        chat_file(c, src, a, list=if listed { "test-list" } else { "" })
      })
      if listed {
        note_list(c, list, "test-list", if head { flight_bar_h } else { 0.0 }, if bar { flight_bar_h } else { 0.0 })
      }
      // (a chat's bar over its top, as a chat's page has it)
      if head {
        let top = c.layer(fn() { c.box(style=flight_bar, fn() {  }) |> ignore })
        over_flight(c, top)
      }
      // (a composer over the chat's foot, as a chat's page has it)
      if bar {
        let foot = c.layer(fn() {
          c.spacer()
          c.box(style=flight_bar, fn() {  }) |> ignore
        })
        over_flight(c, foot)
      }
      preview(c, src)
    },
    w=390.0,
    h=844.0,
    images=[("sent-key", 1200, 900), ("mem:preview/ws1/st1/s-c1/uploads/fx/photo.jpg", 1200, 900)],
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  t
}

///|
/// The composer standing in over the photo's chat's foot: how tall, its look.
let flight_bar_h : Double = 120.0

///|
let flight_bar : @ui.Style = @ui.style(w=Full, h=Fixed(flight_bar_h), bg=Data(0x334455FFL))

///|
/// Whether a picture shows at (x, y, w, h), to half a point.
fn drawn_at(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Bool {
  let (x, y, w, h) = r
  t
  .drawn_images()
  .iter()
  .any(fn(i) {
    (i[0] - x).abs() < 0.5 && (i[1] - y).abs() < 0.5 && (i[2] - w).abs() < 0.5 && (i[3] - h).abs() < 0.5 && i[8] > 0.5
  })
}

///|
test "a picture sent from here flies out as its message shows it: the picture picked, not its likeness or nothing" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  assert_eq(th.picture, "sent-key")
  let at = t.locate("img:sent-key")
  assert_true(at.length() > 0)
  t.tap(at[0].0, at[0].1)
  let v = viewer.get().unwrap()
  assert_true(v.flies && !v.fly_back)
  assert_eq(pv_hidden.val, id)
  // halfway: the same picture (the message's hidden under it), on its way to its place on the stage
  t.run_for(@ui.move_most_ms / 2.0)
  let to = v.zoom.rect().unwrap()
  assert_true(t.locate("img:sent-key").length() > 0)
  let on_way = t
    .drawn_images()
    .filter(fn(i) { i[8] > 0.5 && i[2] > th.w + 0.5 && i[2] < to.2 - 0.5 && (i[3] / i[2] - to.3 / to.2).abs() < 0.01 })
  assert_eq(on_way.length(), 1, msg="\{t.drawn_images()}")
  let mid = on_way[0]
  let (cx, cy) = (mid[0] + mid[2] / 2.0, mid[1] + mid[3] / 2.0)
  assert_true(cx > dmin(th.x + th.w / 2.0, to.0 + to.2 / 2.0) - 0.5 && cx < dmax(th.x + th.w / 2.0, to.0 + to.2 / 2.0) + 0.5)
  assert_true(cy > dmin(th.y + th.h / 2.0, to.1 + to.3 / 2.0) - 0.5 && cy < dmax(th.y + th.h / 2.0, to.1 + to.3 / 2.0) + 0.5)
  t.run_for(@ui.move_most_ms)
  assert_true(drawn_at(t, to))
}

///|
test "a picture's whole come once it is in takes its stand-in's place once decoded: never a frame of nothing there" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held)
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  let v = viewer.get().unwrap()
  t.run_for(@ui.move_most_ms)
  assert_true(!v.flies)
  let to = v.zoom.rect().unwrap()
  assert_true(drawn_at(t, to))
  // its whole comes: in the frame it is here and not yet decoded, what stood in for it is still drawn there
  match held.val {
    Some(give) => give()
    None => fail("its whole was not asked for")
  }
  t.frame()
  assert_true(drawn_at(t, to), msg="\{t.drawn_images()}")
  // (the message's under the viewer, and the one standing in for its whole)
  assert_eq(t.locate("img:sent-key").length(), 2)
  // decoded: the whole there in its place
  t.frame()
  assert_true(drawn_at(t, to))
  assert_eq(t.locate("img:mem:preview/ws1/st1/s-c1/uploads/fx/photo.jpg").length(), 1)
  assert_eq(t.locate("img:sent-key").length(), 1)
}

///|
test "the chat moved under the viewer: the picture flies back to where its thumbnail is now, and lands there" {
  let shift = Ref(0.0)
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(shift, held)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  t.run_for(@ui.move_most_ms)
  let was = thumb_of(t.ctx(), id).unwrap()
  // under the viewer the message goes down (a keyboard let go, the list moved)
  shift.val = 120.0
  t.draw()
  let now = thumb_of(t.ctx(), id).unwrap()
  assert_true((now.y - was.y - 120.0).abs() < 0.5)
  t.back()
  // landed: drawn this once where the thumbnail is now, then the thumbnail itself
  t.run_for(@ui.move_most_ms)
  assert_true(drawn_at(t, (now.x, now.y, now.w, now.h)), msg="\{t.drawn_images()}")
  assert_true(pv_leaving.get() is None)
  assert_eq(pv_hidden.val, "")
  t.draw()
  assert_true(drawn_at(t, (now.x, now.y, now.w, now.h)))
  assert_eq(t.locate("img:sent-key").length(), 1)
}

///|
test "the chat's bars under the viewer's ground while the picture is grown, the page's as the rest of it: the picture over them, landed whole under them" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held, bar=true)
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  t.run_for(@ui.move_most_ms)
  t.back()
  // on its way back, grown still: the bar the page's, drawn under the picture (and under the ground over the page)
  t.run_for(@ui.move_most_ms / 4.0)
  let v = pv_leaving.get().unwrap()
  assert_true(v.flies && v.flying() > 0.0 && v.flying() < 1.0)
  let order = t.drawn_order()
  let picture = order.search_by(fn(i) { i.0 == 4 && i.5 > 0.5 }).unwrap()
  let bar = order.search_by(fn(i) { i.0 == 0 && (i.4 - flight_bar_h).abs() < 0.5 && i.2 > 844.0 - flight_bar_h - 0.5 })
  assert_true(bar is Some(b) && b < picture, msg="\{order}")
  // landed: the bar whole, in its place over the list
  t.run_for(@ui.move_most_ms)
  assert_true(pv_leaving.get() is None)
  let order = t.drawn_order()
  let bar = order.search_by(fn(i) { i.0 == 0 && (i.4 - flight_bar_h).abs() < 0.5 && i.2 > 844.0 - flight_bar_h - 0.5 })
  assert_true(bar is Some(b) && order[b].5 > 0.99, msg="\{order}")
}

///|
test "the way back is a move of its own: most of it as it sets out, at rest as it lands, never the way in run backwards" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held, bar=true)
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  t.run_for(@ui.move_most_ms)
  t.back()
  let v = pv_leaving.get().unwrap()
  let back = t.time()
  // a quarter of its time out: over half of its way back, the bars over it as much
  t.run_for(@ui.move_most_ms / 4.0)
  assert_true(v.flying() < 0.5, msg="\{v.flying()}")
  // its last tenth: hardly any of the way left, so the thumbnail and the bars come back by nothing at the end
  t.run_for(back + @ui.move_most_ms * 0.9 - t.time())
  assert_true(v.flying() < 0.02, msg="\{v.flying()}")
  t.run_for(back + @ui.move_most_ms - t.time())
  assert_true(pv_leaving.get() is None)
}

///|
test "a picture under the composer goes out from under it at its own size first, then grows; back the same way" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(640.0), held, bar=true, listed=true)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  let foot = 844.0 - flight_bar_h
  assert_true(th.y + th.h > foot + 20.0, msg="\{th.y} \{th.h}")
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, (th.y + foot) / 2.0)
  let v = viewer.get().unwrap()
  // one move, on one curve: out from under the composer first (its own size, the composer whole over the list
  // meanwhile), then grown, nothing still between; the going out is the curve's first `lift` of its way
  let lift = v.fly_lift
  assert_true(lift > 0.0)
  let open_ms = fly_ms_of(t, v)
  let out = way_at(lift)
  let start = t.time()
  // (a hair each side of where the going out ends: a fortieth of its time)
  let near = out * open_ms / 40.0
  t.run_for(out * open_ms - near)
  assert_eq(v.flying(), 0.0)
  assert_true(v.lifted() > 0.95, msg="\{v.lifted()}")
  assert_true(composer_over_picture(t))
  t.run_for(near * 2.0)
  assert_true(v.flying() > 0.0 && v.lifted() == 1.0)
  // growing: the composer the page's, under the ground and the picture
  assert_true(!composer_over_picture(t))
  // then grown to its place on the stage
  t.run_for(start + open_ms - t.time())
  let to = v.zoom.rect().unwrap()
  assert_true(drawn_at(t, to))
  // back: shrunk, then in under the composer to its thumbnail, one move of its own on the same curve
  t.back()
  let back = t.time()
  let lift = v.fly_lift
  let close_ms = fly_ms_of(t, v)
  t.run_for(way_at(1.0 - lift) * close_ms - near)
  assert_true(v.flying() > 0.0 && v.lifted() == 1.0)
  assert_true(!composer_over_picture(t))
  t.run_for(near * 2.0)
  assert_eq(v.flying(), 0.0)
  assert_true(v.lifted() < 1.0)
  assert_true(composer_over_picture(t))
  t.run_for(back + close_ms - t.time())
  assert_true(pv_leaving.get() is None)
  assert_true(drawn_at(t, (th.x, th.y, th.w, th.h)))
}

///|
test "a picture going back in under the composer keeps its corners round: what it shows is cut with it, not behind it" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(640.0), held, bar=true, listed=true)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  let foot = 844.0 - flight_bar_h
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, (th.y + foot) / 2.0)
  t.run_for(@ui.move_most_ms + @ui.move_most_ms)
  // back, halfway in under the composer: its box moved half the way, its corners round as the thumbnail's
  t.back()
  let v = pv_leaving.get().unwrap()
  let lift = v.fly_lift
  t.run_for(way_at(1.0 - lift / 2.0) * fly_ms_of(t, v))
  assert_eq(v.flying(), 0.0)
  assert_true(v.lifted() > 0.2 && v.lifted() < 0.8, msg="\{v.lifted()}")
  let clips = t.drawn_image_clips()
  let flying = t.drawn_images().mapi(fn(k, i) { (i, clips[k]) }).filter(fn(p) { p.0[8] > 0.5 && p.0[2] > 0.0 })
  assert_true(flying.length() > 0)
  for p in flying {
    let (_, (r0, r1, r2, r3)) = p.1
    assert_true(r0 > 0.0 && r1 > 0.0 && r2 > 0.0 && r3 > 0.0, msg="\{p.1}")
  }
}

///|
/// Whether the composer over the chat's foot is drawn after the picture in flight (over it).
fn composer_over_picture(t : @ui.Tester) -> Bool {
  let order = t.drawn_order()
  let picture = order.search_by(fn(i) { i.0 == 4 && i.5 > 0.5 })
  let bar = order.search_by(fn(i) { i.0 == 0 && (i.4 - flight_bar_h).abs() < 0.5 && i.2 > 844.0 - flight_bar_h - 0.5 })
  match (picture, bar) {
    (Some(p), Some(b)) => b > p
    _ => false
  }
}

///|
/// How long `v`'s flight told now takes (as long as its way is far: its going out and its growing, or back).
fn fly_ms_of(t : @ui.Tester, v : @sfbase.Viewer) -> Double {
  v.fly.ends_at() - t.time()
}

///|
/// Where along its time a move's curve has gone `share` of its way.
fn way_at(share : Double) -> Double {
  let mut lo = 0.0
  let mut hi = 1.0
  for _ in 0..<60 {
    let m = (lo + hi) / 2.0
    if @ui.Ease::Move.at(m) < share {
      lo = m
    } else {
      hi = m
    }
  }
  (lo + hi) / 2.0
}

///|
test "a picture cut by its card's foot: what shows of it said as where it shows, the flight cut there as it lands" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held, cut=150.0)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  assert_true(th.h > 150.0, msg="\{th.h}")
  // its box whole, what shows of it cut at the card's foot
  match th.seen {
    Some((_, y, _, h)) => assert_true((y + h - 150.0).abs() < 0.5, msg="\{th.seen}")
    None => fail("nothing said of what shows of it")
  }
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  t.run_for(@ui.move_most_ms)
  t.back()
  // (what showed of it, hidden while the picture is out, kept from before)
  t.run_for(@ui.move_most_ms / 2.0)
  match pv_leaving.get().unwrap().fly_from {
    Some({ seen: Some((_, y, _, h)), .. }) => assert_true((y + h - 150.0).abs() < 0.5)
    other => fail("\{other.map(fn(f) { f.seen })}")
  }
}

///|
test "a video taken down and let go goes from where the finger left it: its picture stays there, then flies back from there" {
  let t = video_in_chat()
  t.tap_text("演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  t.set_player(1, position=4000.0)
  t.draw()
  let (x, y, w, h) = t.holes()[0]
  // taken down past the line, the picture with the finger
  t.press_at(195.0, 300.0)
  t.move(195.0, 380.0)
  t.move(195.0, 460.0)
  t.move(195.0, 500.0)
  let down = t.holes()[0].1
  assert_true(down > y + 120.0, msg="\{down} from \{y}")
  // let go: closing, the frame it shows grabbed first, its picture where the finger left it meanwhile
  t.release(195.0, 500.0)
  assert_true(viewer.get() is None)
  let left = t.holes()
  assert_eq(left.length(), 1)
  assert_true((left[0].1 - down).abs() < 0.5, msg="\{left} taken down to \{down}")
  // grabbed: flown back from there, on the black its box has
  let frame = fixture_file_png("演示录屏.mp4")
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\{hex_bytes(frame)}\"}"))
  t.draw()
  assert_eq(t.holes().length(), 0)
  let black = t
    .drawn_rects()
    .filter(fn(r) { r.4 == 0x000000FFL && (r.0 - x).abs() < 0.5 && (r.2 - w).abs() < 0.5 && (r.3 - h).abs() < 0.5 })
  assert_true(black.iter().any(fn(r) { (r.1 - down).abs() < 0.5 }), msg="\{t.drawn_rects()}")
}

///|
test "a picture under the chat's bar goes out from under it at its own size first, then grows; back the same way" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(40.0), held, head=true, listed=true)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  assert_true(th.y < flight_bar_h - 20.0 && th.y + th.h > flight_bar_h + 20.0, msg="\{th.y} \{th.h}")
  t.tap(th.x + th.w / 2.0, (flight_bar_h + th.y + th.h) / 2.0)
  let v = viewer.get().unwrap()
  let lift = v.fly_lift
  let open_ms = fly_ms_of(t, v)
  let start = t.time()
  // (a hair each side of where the going out ends: a fortieth of its time)
  let near = way_at(lift) * open_ms / 40.0
  // halfway out from under the bar: at its own size, the bar over it, its corners round
  t.run_for(way_at(lift / 2.0) * open_ms)
  assert_eq(v.flying(), 0.0)
  assert_true(v.lifted() > 0.2 && v.lifted() < 0.8, msg="\{v.lifted()}")
  assert_true(head_over_picture(t))
  let clips = t.drawn_image_clips()
  let flying = t.drawn_images().mapi(fn(k, i) { (i, clips[k]) }).filter(fn(p) { p.0[8] > 0.5 && p.0[2] > 0.0 })
  assert_true(flying.length() > 0)
  for p in flying {
    let (i, ((_, top, _, foot), (r0, r1, r2, r3))) = p
    assert_true(r0 > 0.0 && r1 > 0.0 && r2 > 0.0 && r3 > 0.0, msg="\{p.1}")
    // its box whole, moved down
    assert_true(top <= i[1] + 0.5 && foot >= i[1] + i[3] - 0.5 && i[1] > th.y + 0.5, msg="\{p}")
  }
  // out: clear of the bar, at its own size
  t.run_for(start + way_at(lift) * open_ms - near - t.time())
  assert_true(v.lifted() > 0.95, msg="\{v.lifted()}")
  assert_true(drawn_at(t, (th.x, flight_bar_h + 12.0, th.w, th.h)) || v.lifted() < 1.0, msg="\{t.drawn_images()}")
  t.run_for(near * 2.0)
  assert_true(v.flying() > 0.0 && v.lifted() == 1.0)
  assert_true(!head_over_picture(t))
  t.run_for(start + open_ms - t.time())
  let to = v.zoom.rect().unwrap()
  assert_true(drawn_at(t, to))
  // back: shrunk, then in under the bar, its corners round halfway in
  t.back()
  let back = t.time()
  let v = pv_leaving.get().unwrap()
  let lift = v.fly_lift
  let close_ms = fly_ms_of(t, v)
  t.run_for(way_at(1.0 - lift / 2.0) * close_ms)
  assert_eq(v.flying(), 0.0)
  assert_true(v.lifted() > 0.2 && v.lifted() < 0.8, msg="\{v.lifted()}")
  assert_true(head_over_picture(t))
  let clips = t.drawn_image_clips()
  let flying = t.drawn_images().mapi(fn(k, i) { (i, clips[k]) }).filter(fn(p) { p.0[8] > 0.5 && p.0[2] > 0.0 })
  assert_true(flying.length() > 0)
  for p in flying {
    let (_, (_, (r0, r1, r2, r3))) = p
    assert_true(r0 > 0.0 && r1 > 0.0 && r2 > 0.0 && r3 > 0.0, msg="\{p.1}")
  }
  t.run_for(back + close_ms - t.time())
  assert_true(pv_leaving.get() is None)
  assert_true(drawn_at(t, (th.x, th.y, th.w, th.h)))
}

///|
/// Whether the bar over the chat's top is drawn after the picture in flight (over it).
fn head_over_picture(t : @ui.Tester) -> Bool {
  let order = t.drawn_order()
  let picture = order.search_by(fn(i) { i.0 == 4 && i.5 > 0.5 })
  let bar = order.search_by(fn(i) { i.0 == 0 && (i.4 - flight_bar_h).abs() < 0.5 && i.2.abs() < 0.5 })
  match (picture, bar) {
    (Some(p), Some(b)) => b > p
    _ => false
  }
}

///|
test "a picture mostly under the chat's bar goes out from under it as quick as it then grows: no leap where they meet" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held, head=true, listed=true)
  let id = "ws1/st1/s-c1/uploads/fx/photo.jpg"
  let th = thumb_of(t.ctx(), id).unwrap()
  assert_true(@sfbase.lift_of(th) > th.h / 3.0, msg="\{th.y} \{th.h}")
  t.tap(th.x + th.w / 2.0, (flight_bar_h + th.y + th.h) / 2.0)
  let v = viewer.get().unwrap()
  let start = t.time()
  let open_ms = fly_ms_of(t, v)
  // the picture's edges a step before where the going out ends and a step after: as quick each side
  let step = open_ms / 10.0
  let joint = start + way_at(v.fly_lift) * open_ms
  let edges = fn() raise {
    let i = t.drawn_images().filter(fn(i) { i[8] > 0.5 && i[2] > 0.0 })
    assert_eq(i.length(), 1)
    let i = i[0]
    [i[0], i[1], i[0] + i[2], i[1] + i[3]]
  }
  let speed = fn(at : Double) raise {
    t.run_for(at - t.time())
    let a = edges()
    t.run_for(step)
    let b = edges()
    let mut m = 0.0
    for k in 0..<4 {
      m = dmax(m, (b[k] - a[k]).abs())
    }
    m / step
  }
  let out = speed(joint - step * 2.0)
  assert_true(v.flying() == 0.0)
  let grow = speed(joint + step)
  assert_true(v.flying() > 0.0)
  assert_true(out < grow * 1.25 && grow < out * 1.25, msg="going out \{out}, growing \{grow}")
}
