// A message's pictures in one box whatever they are doing: waiting, shown, flying in from the composer (sfpages
// message_files.mbt, sfbase flight.mbt; the web's imageBox.ts, madeChat.ts landsAt).

///|
/// A strip far wider than tall (a 2000 × 40 screenshot of a line): in the chat 360 × 7.2, thinner than 16, so in a
/// box 16 thick, letterboxed.
fn strip(name : String) -> Attachment {
  {
    name,
    path: "uploads/fx/" + name,
    size: 4096.0,
    width: 2000.0,
    height: 40.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
}

///|
test "a strip too thin for its box takes its own share of it, centred; any other picture all of its box" {
  assert_eq(@sfpages.image_box(strip("line.png"), @sfpages.image_least), (360.0, 16.0, true))
  let (sw, sh) = @sfpages.picture_share(strip("line.png"), @sfpages.image_least)
  assert_true((sw - 1.0).abs() < 1.0e-9 && (sh - 0.45).abs() < 1.0e-9)
  let photo = { ..strip("photo.jpg"), width: 3024.0, height: 4032.0 }
  assert_eq(@sfpages.picture_share(photo, @sfpages.image_least), (1.0, 1.0))
}

///|
test "a letterboxed strip waiting to load: what it waits on is its share of its box, not the whole box" {
  new_run()
  // (a picture the station never answers: waited on the whole run)
  let src : Source = { ..fixture("chat"), file: fn(_, _, _) { "never/line.png" } }
  let m = message_of({
    "seq": 3,
    "ts": "3",
    "authorKind": "person",
    "author": "Mia",
    "text": "",
    "attachments": [attachment_json(strip("line.png"), "s-c1")],
  })
  let t = @ui.Tester::new(
    fn(c) {
      let here : @sfpages.MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view: chat_view_made(Json::object({})),
        go: None,
        inline: true,
        gutter: 0.0,
        list: None,
        core: None,
      }
      @sfpages.message_row(c, src, here, m)
    },
    w=760.0,
    h=600.0,
  )
  t.draw()
  let ground = t.drawn_rects().filter(fn(r) { (r.2 - 360.0).abs() < 0.5 })
  // its own proportions (2000 : 40), 360 × 7.2 in the middle of its 360 × 16
  assert_true(ground.iter().any(fn(r) { (r.3 - 7.2).abs() < 0.5 }), msg="\{ground}")
  assert_false(ground.iter().any(fn(r) { (r.3 - 16.0).abs() < 0.5 }), msg="\{ground}")
}

///|
test "a strip sent flies to its picture's place in the message, letterboxed there, on no ground" {
  new_run()
  let path = "uploads/fx/line.png"
  let f : SendFlight = {
    chat: "ws1/st1:s-c1",
    turns: "ws1/st1:s-c1",
    text: "",
    from_x: 16.0,
    from_y: 700.0,
    field_x: 16.0,
    field_y: 700.0,
    field_w: 300.0,
    field_h: 40.0,
    room: 0.0,
    hold: fn(_) {  },
    desk: false,
    lines: None,
    lead: 0,
    marks: [],
    files: [{ key: path, from: (16.0, 640.0, 56.0, 56.0), picture: "strip", face: fn() {  }, ground: 0L }],
    key: "o:1",
    placed: false,
    placed_frame: -1,
    way: @motion.Anim::new(0.0),
    gone: @motion.Anim::new(1.0),
    carried: false,
    from_top: 640.0,
    ms: @sfbase.flight_len(false),
    timed: false,
    set_out: -1.0,
    after: 0.0,
  }
  send_flight.set(Some(f))
  let t = @ui.Tester::new(
    fn(c) {
      // its box in the message, 360 × 16, the picture's share of it its own proportions'
      let item = c.box(style=@ui.style(w=Fixed(360.0), h=Fixed(16.0)), fn() {  })
      flight_landing(c, f, item, path, share=@sfpages.picture_share(strip("line.png"), @sfpages.image_least))
      flight_placed(c, f)
      flight_files(c, f.chat)
    },
    w=390.0,
    h=844.0,
  )
  t.add_image("strip", 2000, 40)
  t.draw()
  t.draw()
  // flown all the way (the phone's: over its first part, then settling)
  t.run_for(flight_ms * @sfbase.fly_share(false))
  let drawn = t.drawn_images()
  assert_true(drawn.iter().any(fn(i) { (i[2] - 360.0).abs() < 0.5 && (i[3] - 7.2).abs() < 0.5 }), msg="\{drawn}")
  // no ground under it: the message shows the picture on none
  let neutral = @sf.theme().p.neutral_bg
  assert_false(t.drawn_rects().iter().any(fn(r) { r.4 == neutral }))
  send_flight.set(None)
}

///|
test "an image sent while it goes up flies on to its place once it is up: its message knows it by its upload, before and after" {
  new_run()
  // the message's file: going up (its path its upload's), then up (the station's), the same upload throughout (the
  // core's views.ts goingUp, uploadOf)
  let shot : Ref[Attachment] = {
    val: {
      name: "shot.png",
      path: @sfbase.upload_path("u1"),
      size: 300.0,
      width: 1200.0,
      height: 800.0,
      thumbhash: "",
      owner: "",
      upload: "u1",
      duration: 0.0,
      frames: 0,
      held: false,
    },
  }
  let faced = Ref(0)
  let f : SendFlight = {
    chat: "ws1/st1:s-c1",
    turns: "ws1/st1:s-c1",
    text: "",
    from_x: 16.0,
    from_y: 700.0,
    field_x: 16.0,
    field_y: 700.0,
    field_w: 300.0,
    field_h: 40.0,
    room: 0.0,
    hold: fn(_) {  },
    desk: true,
    lines: None,
    lead: 0,
    marks: [],
    files: [{ key: @sfbase.upload_path("u1"), from: (16.0, 640.0, 56.0, 56.0), picture: "shot", face: fn() { faced.val += 1 }, ground: 0L }],
    key: "o:1",
    placed: false,
    placed_frame: -1,
    way: @motion.Anim::new(0.0),
    gone: @motion.Anim::new(1.0),
    carried: false,
    from_top: 640.0,
    ms: @sfbase.flight_len(false),
    timed: false,
    set_out: -1.0,
    after: 0.0,
  }
  send_flight.set(Some(f))
  let t = @ui.Tester::new(
    fn(c) {
      let item = c.box(style=@ui.style(w=Fixed(240.0), h=Fixed(160.0)), fn() {  })
      flight_landing(c, f, item, @sfbase.file_key(shot.val))
      flight_placed(c, f)
      flight_files(c, f.chat)
    },
    w=390.0,
    h=844.0,
  )
  t.add_image("shot", 1200, 800)
  t.draw()
  t.draw()
  // a fifth of its way: up now, at the station's path; on to more than half of it
  t.run_for(@sfbase.flight_len(true) * 0.2)
  faced.val = 0
  shot.val = { ..shot.val, path: "uploads/fx/shot.png" }
  t.run_for(@sfbase.flight_len(true) * 0.4)
  // still the picture flying to its place, never drawn back where its tile was
  assert_eq(faced.val, 0)
  let drawn = t.drawn_images()
  assert_true(drawn.iter().any(fn(i) { i[2] > 56.0 && i[2] < 240.0 }), msg="\{drawn}")
  send_flight.set(None)
}
