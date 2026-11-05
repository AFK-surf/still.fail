///|
test "a retained composer at the page's foot starts a newly available video's ground from its visible place" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=2, stable=false)
  let made : Ref[ChatComposerNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lies_along(Is(End)) |> ignore
    made.val = Some(chat_composer_node(root, src,
      { station: "ws/st", session: "chat", title: "Chat", station_name: "Studio" },
      fn() { Some(@sfbase.chat_view_made({})) }, fn() { 10.0 }, fn() { 900.0 }, fn() { 12.0 }, fn() { composer_alone }, fn(_) {  }))
  })
  t.draw()
  let n = made.val.unwrap().composer
  n.writing.files.set([{ "id": "video", "name": "video.mov", "size": 100 }, { "id": "log", "name": "log.txt", "size": 30 }])
  t.run_for(@ui.move_most_ms)
  let ground = fn() { let gs = t.drawn_glass_corners(); gs.sort_by(fn(a, b) { a.1.compare(b.1) }); gs[gs.length() - 1].1 }
  let before = ground()
  @sfbase.writing_pictures["video"] = "mem:fixture/video-still.png"
  t.draw()
  let first = ground()
  let offset = (n.ground)()
  t.run_for(composer_shape_ms / 6.0)
  let mid = ground()
  assert_true((first - before).abs() < 1.0, msg="before=\{before}, first=\{first}, mid=\{mid}, offset=\{offset}")
  assert_true((mid - before).abs() > 1.0)
}
