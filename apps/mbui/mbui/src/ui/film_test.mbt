///|
/// A host with text and pictures of its own, unlike the fake's (Latin half an em, glyphs 6 × 10, pictures 400 × 300):
/// each UTF-16 unit a cluster 7 wide and its own glyph, 5 × 9, put in its atlas 1024 a side where it is told; every
/// picture 160 × 80, decoded at half that once it has had a turn. What it is given and asked noted.
priv struct FilmHost {
  faces : Array[Int]
  turns : Ref[Int]
  freed : Array[Int]
  put : Array[(Int, Int, Int)]
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
  ignore(key)
  out[0] = 0.0
  out[1] = 0.0
  out[2] = 5.0
  out[3] = 9.0
  out[4] = 0.0
  out[5] = -9.0
  out[6] = 0.0
}

///|
impl @hostapi.Host for FilmHost with glyph_put(self, key, x, y) {
  self.put.push((key, x, y))
}

///|
impl @hostapi.Host for FilmHost with atlas_size(_, colour) {
  if colour {
    0
  } else {
    1024
  }
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
  let host = FilmHost::{ faces: [], turns: Ref::new(0), freed: [], put: [] }
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
  // drawn by its glyphs, from where in its atlas each was put; the picture its own, decoded after a turn
  let (inst, n, _) = t.presented()
  let places : Array[(Int, Int, Int)] = []
  let pictures : Array[Int?] = []
  for k in 0..<n {
    let kind = inst[k * inst_numbers + 5]
    if kind == 1.0 {
      places.push((places.length(), inst[k * inst_numbers + 12].to_int(), inst[k * inst_numbers + 13].to_int()))
    } else if kind == 4.0 {
      pictures.push(t.live_image(inst[k * inst_numbers + 20].to_int()))
    }
  }
  // (each where it was put last: the face given as it was first drawn, it was drawn again)
  let last : Map[Int, (Int, Int)] = {}
  for p in host.put {
    last[p.0] = (p.1, p.2)
  }
  assert_eq(
    places,
    ['a', 'b', 'c'].mapi(fn(i, ch) {
      let (x, y) = last.get(ch.to_int()).unwrap_or((-1, -1))
      (i, x, y)
    }),
  )
  assert_eq(pictures, [Some(film_picture)])
  assert_true(host.turns.val > 0)
}

///|
/// The numbers of an instance (scene.mbt).
let inst_numbers = 60

///|
test "a failed drawing must not be written as an old film frame" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let drawn = Ref::new(0)
  let written : Array[Int] = []
  let film = t.film(
    "tap go\ntap go\nexit",
    draw=fn(_) {
      drawn.val = drawn.val + 1
      // The renderer was unable to draw this frame; its previous picture is still in the encoder.
      drawn.val != 3
    },
    put=fn(k) {
      written.push(k)
      true
    },
  )
  assert_eq(film.failure, Some(@ui.FilmFailure::Draw))
  assert_eq(drawn.val, 3)
  assert_eq(written, [0, 1])
}

///|
test "a film stops when a frame cannot be written" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let written : Array[Int] = []
  let drawn = Ref::new(0)
  let film = t.film(
    "tap go\ntap go\nexit",
    draw=fn(_) {
      drawn.val = drawn.val + 1
      true
    },
    put=fn(k) {
      written.push(k)
      k != 1
    },
  )
  assert_eq(film.failure, Some(@ui.FilmFailure::Write(1)))
  assert_eq(written, [0, 1])
  assert_eq(drawn.val, 2)
}

///|
test "a film cannot begin without its first drawing" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let written : Array[Int] = []
  let film = t.film(
    "tap go\nexit",
    draw=fn(_) { false },
    put=fn(k) {
      written.push(k)
      true
    },
  )
  assert_eq(film.failure, Some(@ui.FilmFailure::Draw))
  assert_eq(written, [])
}

///|
test "a film at 120 Hz can draw a different picture for each frame" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  t.set_frame_period(1000.0 / 120.0)
  let shown = Ref::new(0.0)
  let pictures : Array[Double] = []
  let film = t.film(
    "tap go\ntap go\nexit",
    fps=120.0,
    draw=fn(t) {
      shown.val = t.time()
      true
    },
    put=fn(_) {
      pictures.push(shown.val)
      true
    },
  )
  assert_eq(film.failure, None)
  assert_true(film.logs.iter().any(fn(line) { line == "DRIVE PASS" }))
  assert_true(pictures.length() >= 3)
  assert_true(pictures[0] < pictures[1] && pictures[1] < pictures[2])
}

///|
test "a run filmed: every frame of the film once, in order, from the Tester's first, each the last drawn by its moment" {
  let t = @ui.Tester::new(fn(c) { c.text("go", wrap=false) |> ignore })
  let drawn : Array[Double] = []
  let put : Array[(Int, Double)] = []
  let film = t.film(
    "until go\nwait 100\ntap go\nwait 50\nexit",
    draw=fn(t) {
      drawn.push(t.time())
      true
    },
    put=fn(k) {
      put.push((k, drawn[drawn.length() - 1]))
      true
    },
  )
  assert_eq(film.failure, None)
  assert_true(film.logs.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=film.logs.join("\n"))
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
