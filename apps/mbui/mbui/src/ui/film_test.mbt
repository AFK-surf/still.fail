///|
/// A host with text and pictures of its own, unlike the fake's (Latin half an em, glyphs 6 × 10, pictures 400 × 300):
/// each UTF-16 unit a cluster 7 wide and its own glyph, 5 × 9 at an atlas place by its code; every picture 160 × 80,
/// decoded at half that once it has had a turn. What it is given and asked noted.
priv struct FilmHost {
  faces : Array[Int]
  turns : Ref[Int]
  freed : Array[Int]
}

///|
impl @hostapi.Host for FilmHost with font_metrics(_, size, _, _, out) {
  out[0] = size * 0.75
  out[1] = size * 0.25
  out[2] = size * 1.25
}

///|
impl @hostapi.Host for FilmHost with shape(_, text, _, _, _, out) {
  let n = text.length()
  for i in 0..<n {
    out[i * 4] = i.to_double()
    out[i * 4 + 1] = 1.0
    out[i * 4 + 2] = film_advance
    out[i * 4 + 3] = text.at(i).to_int().to_double()
  }
  n
}

///|
impl @hostapi.Host for FilmHost with text_key(_, text, _, _, _) {
  text.at(0).to_int()
}

///|
impl @hostapi.Host for FilmHost with glyph(_, key, out) {
  out[0] = key.to_double() * 5.0
  out[1] = 0.0
  out[2] = 5.0
  out[3] = 9.0
  out[4] = 0.0
  out[5] = -9.0
  out[6] = 0.0
}

///|
impl @hostapi.Host for FilmHost with face_add_bytes(self, face, _, _) {
  self.faces.push(face)
  true
}

///|
impl @hostapi.Host for FilmHost with image_load_bytes(_, _, _) {
  film_picture
}

///|
impl @hostapi.Host for FilmHost with image_info(self, _, out) {
  if self.turns.val == 0 {
    return 0
  }
  out[0] = 80.0
  out[1] = 40.0
  out[2] = 160.0
  out[3] = 80.0
  1
}

///|
impl @hostapi.Host for FilmHost with image_free(self, id) {
  self.freed.push(id)
}

///|
let film_advance : Double = 7.0

///|
/// The live host's id for the picture (FilmHost::image_load_bytes).
let film_picture : Int = 7

///|
test "a Tester over a live host: the words laid out and drawn by its text, the faces given to it, the pictures decoded there" {
  let host = FilmHost::{ faces: [], turns: Ref::new(0), freed: [] }
  let made = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if !made.val {
        made.val = true
        ignore(@ui.face_add_bytes(@hostapi.face_code, b"a face"))
      }
      c.column(fn() {
        c.row(fn() { c.text("abc", wrap=false) |> ignore }) |> ignore
        c.image_bytes("mem:pic", b"a picture")
        c.image("mem:pic", w=Px(80.0), h=Px(40.0), fade=false) |> ignore
      })
      |> ignore
    },
    live={ host, turn: fn() { host.turns.val = host.turns.val + 1 } },
  )
  t.draw()
  // three clusters of the live host's 7 (the fake's: 8 each at the words' size)
  match t.rect_of("abc") {
    Some((_, _, w, _)) => assert_eq(w, 3.0 * film_advance)
    None => fail("abc not laid out")
  }
  assert_eq(host.faces, [@hostapi.face_code])
  // drawn by its glyphs, at its atlas's places; the picture its own, decoded after a turn
  let (inst, n, _) = t.presented()
  let places : Array[Double] = []
  let pictures : Array[Int?] = []
  for k in 0..<n {
    let kind = inst[k * inst_numbers + 5]
    if kind == 1.0 {
      places.push(inst[k * inst_numbers + 12])
    } else if kind == 4.0 {
      pictures.push(t.live_image(inst[k * inst_numbers + 20].to_int()))
    }
  }
  assert_eq(places, ['a'.to_int(), 'b'.to_int(), 'c'.to_int()].map(fn(c) { c.to_double() * 5.0 }))
  assert_eq(pictures, [Some(film_picture)])
  assert_true(host.turns.val > 0)
}

///|
/// The numbers of an instance (scene.mbt).
let inst_numbers = 52

///|
test "a run filmed: every frame of the film once, in order, from the Tester's first, each the last drawn by its moment" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let drawn : Array[Double] = []
  let put : Array[(Int, Double)] = []
  let log = t.film(
    "until go\nwait 100\ntap go\nwait 50\nexit",
    draw=fn(t) { drawn.push(t.time()) },
    put=fn(k) { put.push((k, drawn[drawn.length() - 1])) },
  )
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
  let t0 = drawn[0]
  for i, p in put {
    let (k, picture) = p
    assert_eq(k, i)
    // the last drawn by the frame's moment
    let at = t0 + k.to_double() * @ui.frame_period_default
    assert_true(picture <= at + 1.0e-6, msg="frame \{k}: drawn at \{picture}, after \{at}")
    assert_true(drawn.iter().all(fn(d) { d <= picture || d > at + 1.0e-6 }), msg="frame \{k}")
  }
  // as long as the run: to its last frame
  let last = drawn[drawn.length() - 1]
  assert_eq(put.length() - 1, ((last - t0) / @ui.frame_period_default).round().to_int())
}
