// stream_feed.mbt's decoder driven through every order its host's callbacks can come in: what it tells the host and
// what it says for the app, event by event.

///|
let feed_avcc : Bytes = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"

///|
/// A feed configured, its first surface there (as the host makes it with the first config).
fn feed_up() -> Feed {
  let f = Feed::new()
  f.surface = 1
  f.configure(feed_avcc, 640, 360)
  f
}

///|
/// What it said and told since the last look, as lines: "say …" and "do …".
fn feed_look(f : Feed) -> Array[String] {
  let out = []
  for e in f.said {
    out.push("say " + e)
  }
  for d in f.todo {
    out.push("do " + d.cmd)
  }
  f.said.clear()
  f.todo.clear()
  out
}

///|
fn feed_ev(f : Feed, e : String) -> Array[String] {
  f.event(e.split(" ").map(fn(x) { x.to_string() }).to_array())
  feed_look(f)
}

///|
fn feed_frame(f : Feed, ts : Double, key : Bool) -> Array[String] {
  f.frame(b"\x00\x00\x00\x01\x65", key, ts)
  feed_look(f)
}

///|
fn feed_latch(f : Feed, ts : Double) -> Array[String] {
  f.latch(ts)
  feed_look(f)
}

///|
test "a frame goes into a free input buffer, out onto the surface, told once it arrived, the next released once latched" {
  let f = feed_up()
  assert_eq(feed_look(f), ["do start 1"])
  // frames before the decoder gives a buffer wait for one
  assert_eq(feed_frame(f, 100.0, true), [])
  assert_eq(feed_ev(f, "up 1"), [])
  assert_eq(feed_ev(f, "in 1 0"), ["do queue 1 0 100 1"])
  assert_eq(feed_ev(f, "in 1 1"), [])
  // two inside: the older counts as taken
  assert_eq(feed_frame(f, 200.0, false), ["say d 100", "do queue 1 1 200 0"])
  assert_eq(f.inside, [200.0])
  assert_eq(feed_ev(f, "out 1 0 100 1"), ["do release 1 0 100"])
  assert_eq(feed_ev(f, "out 1 1 200 1"), [])
  assert_eq(feed_ev(f, "arr 1"), ["say f 100 640 360"])
  assert_eq(feed_latch(f, 100.0), ["do latch 100 1 640 360", "do release 1 1 200"])
  assert_eq(feed_ev(f, "arr 1"), ["say f 200 640 360"])
  assert_eq(feed_latch(f, 200.0), ["do latch 200 1 640 360"])
}

///|
test "two frames inside: the older said taken, so a decoder that holds one back never holds the sender" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_ev(f, "in 1 1") |> ignore
  assert_eq(feed_frame(f, 100.0, true), ["do queue 1 0 100 1"])
  assert_eq(feed_frame(f, 200.0, false), ["say d 100", "do queue 1 1 200 0"])
}

///|
test "the decoder fails with its frame on the surface arrived first: told, latched, the new decoder from a key frame" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  feed_ev(f, "out 1 0 100 1") |> ignore
  assert_eq(feed_ev(f, "arr 1"), ["say f 100 640 360"])
  assert_eq(feed_ev(f, "err 1"), ["say b", "do stop 1", "do start 2"])
  assert_eq(feed_latch(f, 100.0), ["do latch 100 1 640 360"])
  feed_ev(f, "up 2") |> ignore
  feed_ev(f, "in 2 0") |> ignore
  assert_eq(feed_frame(f, 200.0, false), ["say d 200"])
  assert_eq(feed_frame(f, 300.0, true), ["do queue 2 0 300 1"])
  assert_eq(feed_ev(f, "out 2 0 300 1"), ["do release 2 0 300"])
  assert_eq(feed_ev(f, "arr 1"), ["say f 300 640 360"])
}

///|
test "the decoder fails before its frame on the surface arrived: the frame let go, its late arrival latched away first" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  feed_ev(f, "out 1 0 100 1") |> ignore
  // released, not arrived: let go with the decoder
  assert_eq(feed_ev(f, "err 1"), ["say d 100", "say b", "do stop 1", "do start 2"])
  // it arrives after: no one told of it
  assert_eq(feed_ev(f, "arr 1"), [])
  feed_ev(f, "up 2") |> ignore
  feed_ev(f, "in 2 0") |> ignore
  assert_eq(feed_frame(f, 300.0, true), ["do queue 2 0 300 1"])
  // the stray latched away before the next is released: else that one takes its place unarrived, the surface busy
  // for good (android-streams.sh input-failed)
  assert_eq(feed_ev(f, "out 2 0 300 1"), ["do drop 1", "do release 2 0 300"])
  assert_eq(feed_ev(f, "arr 1"), ["say f 300 640 360"])
  assert_eq(feed_latch(f, 300.0), ["do latch 300 1 640 360"])
}

///|
test "the stray arrives after the new decoder's frame is out: still latched away before that one goes on" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  feed_ev(f, "out 1 0 100 1") |> ignore
  feed_ev(f, "err 1") |> ignore
  feed_ev(f, "up 2") |> ignore
  feed_ev(f, "in 2 0") |> ignore
  feed_frame(f, 300.0, true) |> ignore
  // the new decoder's frame out first: released at once (nothing on the surface yet)
  assert_eq(feed_ev(f, "out 2 0 300 1"), ["do release 2 0 300"])
  // the stray arrives now, taken for the one released: told
  assert_eq(feed_ev(f, "arr 1"), ["say f 300 640 360"])
  // latched with all that arrived; whichever the surface holds, nothing is left busy
  assert_eq(feed_latch(f, 300.0), ["do latch 300 1 640 360"])
  // the frame released arrives after: no one told of it, latched away before the next
  assert_eq(feed_ev(f, "arr 1"), [])
  feed_ev(f, "in 2 1") |> ignore
  feed_frame(f, 400.0, false) |> ignore
  assert_eq(feed_ev(f, "out 2 1 400 1"), ["do drop 1", "do release 2 1 400"])
}

///|
test "a decoder that could not start is made again for the next key frame, as after a failure" {
  let f = feed_up()
  feed_look(f) |> ignore
  assert_eq(feed_frame(f, 100.0, true), [])
  assert_eq(feed_ev(f, "nostart 1"), ["say d 100", "say b"])
  // frames let go until a key frame, which has a decoder made for it
  assert_eq(feed_frame(f, 200.0, false), ["say d 200"])
  assert_eq(feed_frame(f, 300.0, true), ["do start 2"])
  feed_ev(f, "up 2") |> ignore
  assert_eq(feed_ev(f, "in 2 0"), ["do queue 2 0 300 1"])
}

///|
test "a new surface: the frame told on the old one let go, the decoder anew, the old one's arrivals not counted" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  feed_ev(f, "out 1 0 100 1") |> ignore
  assert_eq(feed_ev(f, "arr 1"), ["say f 100 640 360"])
  assert_eq(feed_ev(f, "surf 2"), ["say b", "do stop 1", "do start 2"])
  // its "f" taken after: nothing latched from the old surface
  assert_eq(feed_latch(f, 100.0), [])
  assert_eq(feed_ev(f, "arr 1"), [])
  assert_eq(f.arrived, 0)
}

///|
test "what a stopped decoder says after is not taken" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "err 1") |> ignore
  assert_eq(feed_ev(f, "in 1 0"), [])
  assert_eq(feed_ev(f, "out 1 0 100 1"), [])
  assert_eq(feed_ev(f, "err 1"), [])
  assert_eq(feed_ev(f, "nostart 1"), [])
}

///|
test "a frame the decoder cannot take: its buffer given back empty, let go, a key frame asked for" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  assert_eq(feed_ev(f, "rej 1 0 100"), ["say d 100", "say b", "do empty 1 0 100"])
  assert_eq(f.inside, [])
  feed_ev(f, "in 1 1") |> ignore
  assert_eq(feed_frame(f, 200.0, false), ["say d 200"])
}

///|
test "a frame that could not go on the surface is let go, the next released" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  feed_ev(f, "in 1 0") |> ignore
  feed_ev(f, "in 1 1") |> ignore
  feed_frame(f, 100.0, true) |> ignore
  feed_frame(f, 200.0, false) |> ignore
  feed_ev(f, "out 1 0 100 1") |> ignore
  feed_ev(f, "out 1 1 200 1") |> ignore
  assert_eq(feed_ev(f, "lost 1 100"), ["say d 100", "do release 1 1 200"])
}

///|
test "a config's output and an empty one are given back, not shown" {
  let f = feed_up()
  feed_look(f) |> ignore
  feed_ev(f, "up 1") |> ignore
  assert_eq(feed_ev(f, "out 1 3 0 0"), ["do discard 1 3"])
}

///|
test "an avcC that is not one stops the decoder; frames let go until a sound one" {
  let f = feed_up()
  feed_look(f) |> ignore
  f.configure(b"\x02\x00", 640, 360)
  assert_eq(feed_look(f), ["do stop 1"])
  assert_eq(feed_frame(f, 100.0, true), ["say d 100"])
  f.configure(feed_avcc, 640, 360)
  assert_eq(feed_look(f), ["do start 2"])
}
