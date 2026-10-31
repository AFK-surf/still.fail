// A link's card reads what it shows while it is pointed at and let go of once it has gone, so the next time it shows
// it is read again (peeks.mbt peek_read): a pull request's card said the checks it first read for as long as the app
// ran.

///|
test "a link's card is read as the pointer comes onto it and let go of once it has gone, read again the next time" {
  @sfbase.reset()
  let href = "https://github.com/AFK-surf/Cue/pull/4466"
  let read : Array[String] = []
  let left : Array[String] = []
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic: fn(name, params) {
      if name == "linkPreview" && read.last() != Some(name) {
        read.push(name)
      }
      (made.topic)(name, params)
    },
    leave: fn(name, _) {
      left.push(name)
      read.push("left")
    },
  }
  let build = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      build.val += 1
      @sfbase.held_build(build.val)
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.column(pad=40.0, fn() {
          let link = @kit.button(c, "PR #4466", key="pr", variant=Ghost)
          web_peek(c, src, "st", href, "PR #4466", link.id)
        })
        |> ignore
      })
    },
    w=800.0,
    h=800.0,
    native=Mouse,
    pointing=Mouse,
  )
  t.draw()
  assert_eq(read, [])
  let (x, y, w, h) = t.get(@ui.Role::Button, label="PR #4466").rect
  // pointed at: read, and its card opens over it
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_eq(read, ["linkPreview"])
  assert_eq(left, [])
  // the pointer gone, the card goes; once it has, what it read is let go of, once
  t.move(700.0, 700.0)
  t.run_for((hover_close_ms + hover_out_ms) * 2.0)
  assert_eq(left, ["linkPreview"])
  t.run_for((hover_close_ms + hover_out_ms) * 2.0)
  assert_eq(left, ["linkPreview"])
  // pointed at again: read again
  t.move(x + w / 2.0, y + h / 2.0)
  t.run_for(hover_open_ms * 2.0)
  assert_eq(read, ["linkPreview", "left", "linkPreview"])
}
