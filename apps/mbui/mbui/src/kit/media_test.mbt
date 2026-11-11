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
  t.move_to(195.0, 20.0)
  assert_true(m.scrubbing() is Some(ms) && (ms - 5000.0).abs() < 100.0)
  assert_true(told(" 2 0"))
  assert_true(told(" 9 1"))
  assert_true(told(" 3 5000"))
  t.release(195.0, 20.0)
  t.draw()
  assert_true(m.scrubbing() is None)
  assert_true(told(" 9 0"))
}

///|
test "a player waits for the decoder only after all bytes arrived, and retry starts a new wait" {
  let m = @kit.Media::new()
  let last : Ref[@kit.MediaFrame?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { last.val = Some(m.frame(c)) }, finish=false)
  let wait = @kit.media_decode_wait_ms
  let margin = wait / 40.0
  let track : @kit.MediaTrack = {
    name: "a.webm",
    mime: "video/webm",
    audio: false,
    read: fn(_, _, _) { fn() {  } },
    direct: "",
  }
  m.open(track)
  let id = m.native().unwrap().id()
  t.draw()
  t.run_for(wait * 1.5)
  assert_eq(last.val.unwrap().status.state, 0, msg="a slow read is not a decoder timeout")
  assert_true(t.view_said("{\"info\":{\"view\":\{id},\"state\":2,\"at\":[-1,0,0,0,0,100,0,0,0,0]}}"))
  // No frames at all between the host's event and this observation.
  t.advance(wait - margin)
  t.frame_at(t.time())
  assert_eq(last.val.unwrap().status.state, 0)
  t.advance(margin * 2.0)
  t.frame_at(t.time())
  assert_eq(last.val.unwrap().status.state, -4)
  assert_eq(m.status().state, -4)
  m.retry()
  let next = m.native().unwrap().id()
  assert_true(next != id)
  assert_true(t.view_said("{\"info\":{\"view\":\{next},\"state\":2,\"at\":[-1,0,0,0,0,100,0,0,0,0]}}"))
  t.advance(wait - margin)
  t.frame_at(t.time())
  assert_eq(last.val.unwrap().status.state, 0, msg="retry gets its own wait")
  assert_true(t.view_said("{\"info\":{\"view\":\{next},\"state\":1,\"at\":[10000,0,0,640,360,100,1,0,0,0]}}"))
  t.draw()
  t.run_for(margin * 2.0)
  assert_eq(last.val.unwrap().status.state, 1)
}

///|
test "a frame asked of a player is waited for only so long, and another can be asked then" {
  let m = @kit.Media::new()
  let stalled = Ref(false)
  let t = @ui.Tester::new(
    fn(c) {
      m.frame(c) |> ignore
      if m.native() is Some(n) && @kit.media_grab_stalled(c, n) {
        stalled.val = true
      }
    },
    finish=false,
  )
  let wait = @kit.media_grab_wait_ms
  let margin = wait / 40.0
  let track : @kit.MediaTrack = {
    name: "a.mp4",
    mime: "video/mp4",
    audio: false,
    read: fn(_, _, _) { fn() {  } },
    direct: "",
  }
  m.open(track)
  let n = m.native().unwrap()
  t.draw()
  n.grab_frame(1000.0)
  t.draw()
  t.advance(wait - margin)
  t.frame_at(t.time())
  assert_false(stalled.val)
  assert_true(n.grabbing())
  t.advance(margin * 2.0)
  t.frame_at(t.time())
  assert_true(stalled.val)
  n.give_up_grab()
  assert_false(n.grabbing())
  assert_eq(n.grab_since(), -1.0)
  n.grab_frame(2000.0)
  assert_true(n.grabbing())
}

///|
test "a player opened not to play: there at its place, paused, its frame shown, until it is played" {
  let m = @kit.Media::new()
  let t = @ui.Tester::new(fn(c) { m.frame(c) |> ignore }, w=390.0, h=844.0)
  let track : @kit.MediaTrack = {
    name: "a.mp4",
    mime: "video/mp4",
    audio: false,
    read: fn(_, _, _) { fn() {  } },
    direct: "",
  }
  m.open(track, start=4000.0, play=false)
  t.draw()
  let id = m.native().unwrap().id()
  assert_true(t.views().contains("control \{id} 3 4000"), msg="sent to its place")
  assert_true(!t.views().contains("control \{id} 1 0"), msg="not played")
  m.play_pause()
  assert_true(t.views().contains("control \{id} 1 0"), msg="played from its key")
  // (by default it plays as it opens, as ever)
  m.open(track)
  let next = m.native().unwrap().id()
  assert_true(t.views().contains("control \{next} 1 0"))
}
