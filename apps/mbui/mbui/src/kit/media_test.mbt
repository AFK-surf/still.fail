// A player's ways (media.mbt) over the fake host (every view there ready, 10 s long, 640 × 360, paused): a double tap's
// third and its note said a moment, the speed stepped, the timeline dragged: the player paused and sent along with the
// finger, its seeks one after another until let go.

///|
test "a player: a double tap on the right third jumps on, said a moment; the speed steps; a drag on the timeline seeks as it goes" {
  let m = @kit.Media::new()
  let last : Ref[@kit.MediaFrame?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      let f = m.frame(c)
      last.val = Some(f)
      let stage = c.id("stage")
      m.stage(c, stage, c.width)
      c.box(w=Fill(1.0), h=Fill(1.0), id=stage, fn() {
        let line = c.id("timeline")
        m.timeline(c, line, f.on)
        c.box(w=Fill(1.0), h=Px(40.0), id=line, fn() {  }) |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  m.open({ name: "a.mp4", mime: "video/mp4", audio: false, read: fn(_, _, _) { fn() {  } }, direct: "" })
  t.draw()
  assert_true(m.started())
  // the right third, twice: 15 s on (the fake is 10 s long: to its end), about there at once (the nearest key frame)
  t.tap(350.0, 400.0)
  t.tap(350.0, 400.0)
  assert_eq(last.val.unwrap().note, Some(Ahead(15000.0)))
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" 11 10000") }))
  t.run_for(@kit.media_note_ms)
  assert_eq(last.val.unwrap().note, None)
  // the speed after 1×
  m.step_speed()
  assert_eq(m.speed(), 1.25)
  // dragged to the timeline's middle: paused, its seeks one after another, sent there as it goes; let go, as before
  let told = fn(said : String) { t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(said) }) }
  t.press_at(10.0, 20.0)
  t.move(195.0, 20.0)
  assert_true(m.scrubbing() is Some(ms) && (ms - 5000.0).abs() < 100.0)
  assert_true(told(" 2 0"))
  assert_true(told(" 9 1"))
  assert_true(told(" 3 5000"))
  t.release(195.0, 20.0)
  t.draw()
  assert_true(m.scrubbing() is None)
  assert_true(told(" 9 0"))
}
