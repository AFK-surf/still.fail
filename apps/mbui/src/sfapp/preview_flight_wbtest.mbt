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
fn photo_sent(shift : Ref[Double], held : Ref[(() -> Unit)?]) -> @ui.Tester {
  reset()
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
      c.box(w=Fill(1.0), h=Fill(1.0), fn() {
        c.box(style=@ui.style(h=Fixed(shift.val)), fn() {  }) |> ignore
        chat_file(c, src, a)
      })
      |> ignore
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
  let v = viewer.val.unwrap()
  assert_true(v.flies && !v.fly_back)
  assert_eq(pv_hidden.val, id)
  // halfway: the same picture (the message's hidden under it), on its way to its place on the stage
  t.run_for(fly_open_ms / 2.0)
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
  t.run_for(fly_open_ms)
  assert_true(drawn_at(t, to))
}

///|
test "a picture's whole come once it is in takes its stand-in's place once decoded: never a frame of nothing there" {
  let held : Ref[(() -> Unit)?] = Ref(None)
  let t = photo_sent(Ref(0.0), held)
  let at = t.locate("img:sent-key")
  t.tap(at[0].0, at[0].1)
  let v = viewer.val.unwrap()
  t.run_for(fly_open_ms)
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
  t.run_for(fly_open_ms)
  let was = thumb_of(t.ctx(), id).unwrap()
  // under the viewer the message goes down (a keyboard let go, the list moved)
  shift.val = 120.0
  t.draw()
  let now = thumb_of(t.ctx(), id).unwrap()
  assert_true((now.y - was.y - 120.0).abs() < 0.5)
  t.back()
  // landed: drawn this once where the thumbnail is now, then the thumbnail itself
  t.run_for(fly_close_ms)
  assert_true(drawn_at(t, (now.x, now.y, now.w, now.h)), msg="\{t.drawn_images()}")
  assert_true(pv_leaving.val is None)
  assert_eq(pv_hidden.val, "")
  t.draw()
  assert_true(drawn_at(t, (now.x, now.y, now.w, now.h)))
  assert_eq(t.locate("img:sent-key").length(), 1)
}

///|
test "a video taken down and let go goes from where the finger left it: its picture stays there, then flies back from there" {
  let t = video_in_chat()
  t.tap_text("演示录屏.mp4")
  t.run_for(fly_open_ms)
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
  assert_true(viewer.val is None)
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
