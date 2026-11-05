// A chat's pending picture can be seen at more than one size before its data arrives.

///|
test "a pending picture keeps each decode size once through continuous resizing" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let base = @sffixture.fixture("chat-many-images")
  let value = (base.topic)("chat", { "station": "ws1/st1", "session": "s-c1" }).value.unwrap()
  let view = @sfbase.chat_view_made(value)
  let a : Attachment = {
    name: "resizing.png", path: "work/s-c1/resizing.png", owner: "s-c1", size: 1.0,
    width: 640.0, height: 480.0, thumbhash: "", upload: "", duration: 0.0, frames: 0, held: false,
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "Chat", station_name: "Studio" }
  let here : MessageHere = { station: r.station, session: r.session, view, go: None, inline: true, gutter: 0.0, list: None, core: None }
  let key = @signals.signal("")
  let src = { ..base, file: fn(_, _, _) { key.get() } }
  let pictures : Ref[ChatPictures?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=400.0, scale=1.0,
    images=[("resizing.png", 640, 480)])
  @ui.set_view_app(fn(root) {
    pictures.val = Some(ChatPictures::new(root, src, r, fn() { Some(view) }))
  })
  t.draw()
  let held = pictures.val.unwrap()
  // All widths in each group fall into the same host decode size, although every width is distinct.
  for i in 0..<64 {
    held.want(here, a, 192.0 + i.to_double() / 2.0, false)
  }
  for i in 0..<64 {
    held.want(here, a, 300.0 + i.to_double() / 2.0, false)
  }
  let picture = held.picture(chat_picture_id(r.station, a.owner, a))
  key.set("resizing.png")
  assert_eq(t.image_loads().filter(fn(load) { load.0 == "resizing.png" }),
    [("resizing.png", 256), ("resizing.png", 512)],
    msg="the late answer is decoded for both the small and large placements")
  assert_eq(picture.pixels.length(), 2, msg="resizing keeps two decode sizes, not 128 past widths")
}
