// Pictures as Android's has them (Parts.kt rememberPicture, PeopleStack; RowPicture.kt Faces): one that could not be
// had asked again when its page is put up anew; people stacked with the first over the rest, a row's starter over the others.

///|
test "a picture that could not be had is asked for again when its page is put up anew, not while it stays up" {
  let asked : Array[(Bytes?) -> Unit] = []
  let picture = core_pictures(fn(_, done) { asked.push(done) })
  let url = "https://pictures.example/lin.jpg"
  // asked once, nothing while it comes
  assert_eq(picture(url, 1), "")
  assert_eq(picture(url, 1), "")
  assert_eq(asked.length(), 1)
  // the network down: not asked again while its page stays up (Compose's produceState runs once it comes in),
  // however many frames
  (asked[0])(None)
  assert_eq(picture(url, 1), "")
  assert_eq(picture(url, 1), "")
  assert_eq(asked.length(), 1)
  // its page put up again (left and come back to: another page put on top since): asked again (the core says it
  // could not until its own while is over, then fetches it)
  assert_eq(picture(url, 3), "")
  assert_eq(asked.length(), 2)
  // shown on two pages at once (a sheet's and the page under it): asked again once for each, not each time it goes
  // from one to the other
  (asked[1])(None)
  assert_eq(picture(url, 3), "")
  assert_eq(picture(url, 4), "")
  assert_eq(asked.length(), 3)
  (asked[2])(None)
  assert_eq(picture(url, 3), "")
  assert_eq(picture(url, 4), "")
  assert_eq(picture(url, 3), "")
  assert_eq(asked.length(), 3)
  // its page put up again: asked again
  assert_eq(picture(url, 5), "")
  assert_eq(asked.length(), 4)
  // had: its image, kept for good, never asked again
  (asked[3])(Some(b"\x89PNG"))
  let key = picture(url, 5)
  assert_true(key.has_prefix("mem:picture/"))
  assert_eq(picture(url, 9), key)
  assert_eq(asked.length(), 4)
}

///|
/// The plain rectangles drawn in the last frame in colour `colour`: their places in the draw order and their boxes.
fn drawn_in(t : @ui.Tester, colour : Int64) -> Array[(Int, Double, Double, Double)] {
  let out = []
  for i, r in t.drawn_rects() {
    if r.4 == colour {
      out.push((i, r.0, r.1, r.2))
    }
  }
  out
}

///|
fn someone(id : String, name : String) -> Person {
  { id, email: "", name, display: name, picture: "", mine: false }
}

///|
test "people stacked: side by side 5 over the one before, the first drawn over them all, ringed in their ground" {
  new_run()
  let src = fixture("home")
  // (their colours: Lin's the sixth, Mo's the fifth)
  let people = [someone("lin", "Lin"), someone("mo", "Mo")]
  let ring = 0x123456FFL
  let t = @ui.Tester::new(fn(c) { c.box(fn() { people_stack(c, src, people, 16.0, ring~) }) |> ignore }, platform=2)
  let lin = drawn_in(t, @sf.avatar_color("lin"))
  let mo = drawn_in(t, @sf.avatar_color("mo"))
  assert_eq(lin.length(), 1)
  assert_eq(mo.length(), 1)
  // 16 in a ring 3 wider, the next 19 - 5 on
  assert_eq((lin[0].1, lin[0].3), (1.5, 16.0))
  assert_eq(mo[0].1, 15.5)
  // the first over the second (Parts.kt PeopleStack: zIndex(-i))
  assert_true(lin[0].0 > mo[0].0)
  // each ringed in the ground said
  let rings = drawn_in(t, ring)
  assert_eq(rings.map(fn(r) { (r.1, r.3) }), [(14.0, 19.0), (0.0, 19.0)])
}

///|
test "a row's people (sfpages' RowAside, a finger's 18): each 3 over the one before, the one who started the chat drawn over the rest, a pixel of the row's ground round each" {
  new_run()
  let src = fixture("home")
  let person = fn(id : String, name : String) -> Json {
    { "id": id.to_json(), "shown": { "name": name.to_json(), "display": name.to_json(), "mine": false.to_json() } }
  }
  let item = chat_item({
    "id": "c1",
    "people": [person("lin", "Lin"), person("mo", "Mo"), person("kai", "Kai")],
    "creator": { "id": "mo" },
  })
  let ground = 0x123456FFL
  // (touch's theme, as the app's frame begins it: its chats' list's faces)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.box(fn() { @sfpages.row_aside(c, src, item, "people", ground) }) |> ignore
    },
    platform=2,
  )
  let lin = drawn_in(t, @sf.avatar_color("lin"))
  let mo = drawn_in(t, @sf.avatar_color("mo"))
  let kai = drawn_in(t, @sf.avatar_color("kai"))
  // 18 each, 2 in, 3 over the one before; a pixel more after who started it (RowPicture.css.ts)
  assert_eq([lin[0].1, mo[0].1, kai[0].1], [2.0, 17.0, 33.0])
  assert_eq([lin[0].3, mo[0].3, kai[0].3], [18.0, 18.0, 18.0])
  // Mo started it: over Lin and Kai
  assert_true(mo[0].0 > lin[0].0 && mo[0].0 > kai[0].0)
  // the row's ground a pixel round each face
  let rings = drawn_in(t, ground)
  assert_eq(rings.length(), 3)
  assert_true(rings.iter().all(fn(r) { r.3 == 20.0 }))
}
