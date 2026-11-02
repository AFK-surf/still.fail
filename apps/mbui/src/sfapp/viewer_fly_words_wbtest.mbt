// A picture too big to show opened from its thumbnail in its chat, the chat's words under where it tells of it: none of
// its words over them as it comes (words_over.mbt), its ground and its words both as far in as its flight's share of
// its way times its fade (Viewer::in_at). Main's (acb0068613) showed them so, its ground the flight's and its words
// whole; in a file of its own, as a fault of it ends its program.

///|
test "a picture too big to show, in its chat with its picture there and words under where it tells of it: opened by a tap, its stage told of from its first frame, its thumbnail hidden as long as its flight would take and back then, none of its words over the chat's as it comes" {
  new_run()
  let photo : Attachment = {
    name: "photo.jpg",
    path: "uploads/fx/photo.jpg",
    size: big_file * 2.0,
    width: 1200.0,
    height: 900.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  @sfbase.sent_pictures[@sfbase.sent_key("ws1/st1", photo.path)] = "sent-key"
  let src = fixture("chat")
  // (the chat an old view the window's tree hosts, the viewer beside it as the shells have it)
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(root) {
      root.box(fn(v) {
        v.grow(Is(1.0)) |> ignore
        @ui.old(v, fn(c) {
          c.box(style=@ui.style(w=Full, h=Full), fn() {
            chat_file(c, src, photo)
            // (the chat's words under where it tells of the picture: none of its words over them as it comes)
            for i in 0..<24 {
              c.text("聊天里的一行字，在文件信息底下 \{i}") |> ignore
            }
          })
          |> ignore
          preview(c, src)
        })
        .over(Is(true))
        |> ignore
        @sfbase.viewer_node(v, src, fn() { v.window() })
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
    images=[("sent-key", 1200, 900)],
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  let at = t.locate("img:sent-key")
  guard at is [(x, y), ..] else { fail("no thumbnail") }
  t.tap(x, y)
  let v = viewer.get().unwrap()
  assert_true(v.told_of() && v.flies, msg="told of, set out as a flight")
  t.draw()
  assert_true(t.find("文件过大，无法在此显示，下载后可打开") is Some(_), msg="its stage told of from its first frame")
  assert_eq(drawn_of(t, "sent-key").length(), 0, msg="its thumbnail hidden as it would fly")
  t.run_for(v.fly.end() - t.ctx().moment() + @ui.frame_period_default)
  assert_true(!v.flies, msg="its flight's time over")
  assert_eq(drawn_of(t, "sent-key").length(), 1, msg="its thumbnail back")
}
