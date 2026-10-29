// A remote screen's frames and sound taken by the host straight from the app's engine (ScreenSess::route, @ui's
// Stream::route) where its shell reads the view itself and numbers what it says (`n`): while that changes nothing the
// app draws.

///|
/// What the stream's host was asked of its route, oldest first.
fn routes_told(r : ScreenRig, st : @ui.Stream) -> Array[String] {
  r.t.stream_fed(st.id()).filter(fn(l) { l.has_prefix("route") })
}

///|
test "a layered screen's frames and sound go to the host by their route once a frame shows, and come back here while a part shows" {
  let r = screen_rig(h264=true)
  let st = r.layered()
  let call = r.sess().call
  // as the core says them (no number): nothing routed
  r.say({ "frame": { "key": false, "ts": 1001.0 } }, bytes=b"\x00\x00\x00\x01\x41")
  assert_eq(routes_told(r, st), [])
  // as the engine's shell says them: its frames from the next on, its picture on its layer
  r.say({ "frame": { "key": false, "ts": 1002.0, "n": 41.0 } }, bytes=b"\x00\x00\x00\x01\x41")
  assert_eq(routes_told(r, st), ["route \{call} after=41 video=true audio=false"])
  // its sound too, once it plays
  r.say({ "audioConfig": { "codec": "pcm_s16le", "sampleRate": 48000.0, "channels": 2.0 } })
  r.say({ "audio": { "ts": 1003.0, "n": 43.0 } }, bytes=Bytes::make(3840, b'\x00'))
  assert_eq(routes_told(r, st).last(), Some("route \{call} after=43 video=true audio=true"))
  // what the host took: counted for 控制中心, shown from
  assert_true(r.t.view_said("{\"stream\":{\"id\":\{st.id()},\"e\":\"D 1100 5 50000\"}}"))
  r.t.draw()
  assert_eq(st.shown_at(), Some(1100.0))
  let (frames, bytes) = r.sess().came()
  assert_eq((frames - r.sess().frames, bytes - r.sess().bytes), (5, 50000))
  // muted: its sound no longer
  r.sess().toggle_audio()
  r.say({ "frame": { "key": false, "ts": 1101.0, "n": 60.0 } }, bytes=b"\x00\x00\x00\x01\x41")
  assert_eq(routes_told(r, st).last(), Some("route \{call} after=60 video=true audio=false"))
  // zoomed: a part's frames come, drawn over the whole by the app's say: the whole's frames its own
  r.say({ "config": { "codec": "h264", "width": 640.0, "height": 360.0, "region": { "x": 0.0, "y": 0.0, "w": 0.5, "h": 0.5 } } }, bytes=b"avcc")
  r.say({ "frame": { "key": true, "ts": 1200.0, "n": 62.0 } }, bytes=b"\x00\x00\x00\x01\x65")
  assert_eq(routes_told(r, st).last(), Some("route 0 after=62 video=false audio=false"))
  // the part's: not before one of it shows, then by the route to it
  let part = r.sess().part.unwrap()
  assert_eq(routes_told(r, part), [])
  r.t.stream_shows(part.id(), 1200.0, 640, 360)
  r.t.draw()
  r.say({ "frame": { "key": false, "ts": 1201.0, "n": 63.0 } }, bytes=b"\x00\x00\x00\x01\x41")
  let told = routes_told(r, part)
  assert_eq(told, ["route \{call} after=63 video=true audio=false"])
  // (the frames handed here: their fate said)
  r.t.stream_drops(st.id(), 1101.0)
  r.t.stream_drops(part.id(), 1201.0)
  r.t.draw()
  screen_done(r.t)
}
