///|
/// The view made once, on the tester's first frame (the fake host is in place by then).
fn once(cell : Ref[@ui.NativeView?], make : () -> @ui.NativeView) -> @ui.NativeView {
  match cell.val {
    Some(v) => v
    None => {
      let v = make()
      cell.val = Some(v)
      v
    }
  }
}

///|
test "a native view shows where it is painted: a hole in the canvas, the host told where, hidden when not painted" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let shown : Ref[Bool] = { val: true }
  let t = @ui.Tester::new(
    fn(c) {
      let v = once(cell, fn() {
        @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
      })
      c.box(w=Fill(1.0), h=Fill(1.0), bg=0x000000FFL, fn() {
        c.box(h=Px(100.0), fn() { () }) |> ignore
        if shown.val {
          // a picture of 300 × 200 at (20, 10) in a box of 390 × 220, over which a bar is painted
          c.native(v, h=Px(220.0), content=Some((20.0, 10.0, 300.0, 200.0))) |> ignore
          c.box(h=Px(40.0), w=Fill(1.0), bg=0x121214D9L, ty=-40.0, fn() { () }) |> ignore
        }
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  let v = cell.val.unwrap()
  assert_true(v.here())
  assert_eq(t.holes(), [(20.0, 110.0, 300.0, 200.0)])
  // the host placed it: its content, its clip (the node), shown
  assert_true(t.views().contains("place 1 20 110 300 200 in 0 100 390 320"))
  // ready at once on the fake host: its picture's size known
  assert_eq(v.state(), 1)
  assert_eq(v.natural(), (640.0, 360.0))
  // not painted: hidden, no hole
  shown.val = false
  t.frame()
  assert_eq(t.holes().length(), 0)
  assert_true(t.views().iter().any(fn(l) { l.has_suffix("hidden") }))
  v.play()
  v.seek(2500.0)
  assert_true(t.views().contains("control 1 1 0"))
  assert_true(t.views().contains("control 1 3 2500"))
  v.close()
  assert_true(t.views().contains("close 1"))
}

///|
test "a native view inside a clip shows only in it: its hole cut to the clip" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(
    fn(c) {
      let v = once(cell, fn() { @ui.NativeView::page("<p>hi</p>") })
      c.box(w=Px(200.0), h=Px(100.0), clip=true, fn() {
        c.native(v, w=Px(300.0), h=Px(300.0)) |> ignore
      })
      |> ignore
    },
    w=390.0,
    h=844.0,
  )
  assert_eq(t.holes(), [(0.0, 0.0, 200.0, 100.0)])
  assert_true(t.views().contains("place 1 0 0 300 300 in 0 0 200 100"))
  cell.val.unwrap().close()
}

///|
test "a PDF's pages are images the host draws at the size they are shown" {
  let cell : Ref[@ui.Pdf?] = { val: None }
  let t = @ui.Tester::new(
    fn(c) {
      let pdf = match cell.val {
        Some(p) => p
        None => {
          let p = @ui.Pdf::open(b"%PDF-1.4")
          cell.val = Some(p)
          p
        }
      }
      c.image(pdf.page_src(1), w=Px(306.0), h=Px(396.0)) |> ignore
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  let pdf = cell.val.unwrap()
  assert_eq(pdf.pages, 3)
  assert_eq(pdf.sizes[0], (612.0, 792.0))
  assert_eq(@ui.image_state(pdf.page_src(1)), 1)
  assert_eq(@ui.image_natural(pdf.page_src(1)), Some((1224.0, 1584.0)))
}

///|
test "a player's reads of the app's bytes come at the next frame, as the test says; what the app gave is told" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let file = Bytes::makei(5000, fn(i) { (i % 251).to_byte() })
  let asked : Array[(Double, Int)] = []
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::video("video/mp4", fn(offset, length, answer) {
        asked.push((offset, length))
        let from = offset.to_int()
        let n = if from + length > file.length() { file.length() - from } else { length }
        answer(Bytes::makei(n, fn(i) { file[from + i] }), file.length().to_double())
      })
    })
    c.native(v, h=Px(220.0)) |> ignore
  })
  let v = cell.val.unwrap()
  let first = t.view_reads(v.id(), 0.0, 4096)
  let second = t.view_reads(v.id(), 4096.0, 4096)
  assert_eq(asked, [])
  t.draw()
  assert_eq(asked, [(0.0, 4096), (4096.0, 4096)])
  assert_eq(t.view_answers(v.id()), [(first, 4096, 5000.0), (second, 904, 5000.0)])
}

///|
test "a player stands as the test sets it: ready, its first frame shown, two seconds in, playing" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() { @ui.NativeView::video("video/mp4", fn(_o, _l, answer) { answer(b"", -1.0) }) })
    c.native(v, h=Px(220.0)) |> ignore
    c.text("\{(v.position() / 1000.0).to_int()} s of \{(v.duration() / 1000.0).to_int()} s", wrap=false) |> ignore
  })
  let v = cell.val.unwrap()
  assert_eq(v.state(), 1)
  t.set_player(v.id(), shown=false)
  t.draw()
  assert_eq(v.shown(), false)
  t.set_player(v.id(), duration=60000.0, position=2000.0, playing=true, shown=true)
  t.draw()
  assert_true(v.playing() && v.shown())
  assert_true(t.find("2 s of 60 s") is Some(_))
  t.set_player(v.id(), playing=false, position=60000.0, ended=true)
  t.draw()
  assert_true(v.ended() && !v.playing())
}

///|
test "what another app shares in is said at the next frame, once; its files taken once" {
  let said : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    let s = @ui.shared_in()
    if s != "" {
      said.push(s)
    }
    c.text("share", wrap=false) |> ignore
  })
  t.share_in("look at these", title="from Photos", files=[("a.png", b"\x89PNG"), ("notes.txt", b"hello")])
  assert_eq(said, [])
  t.draw()
  assert_eq(said.length(), 1)
  let j = @json.parse(said[0]) catch { _ => Json::null() }
  assert_eq(
    j,
    {
      "text": "look at these",
      "title": "from Photos",
      "files": [
        { "name": "a.png", "type": "image/png", "size": 4 },
        { "name": "notes.txt", "type": "text/plain", "size": 5 },
      ],
    },
  )
  assert_eq(@ui.shared_in_file(1), b"hello")
  assert_eq(@ui.shared_in_file(1), b"")
  t.draw()
  assert_eq(said.length(), 1)
}

///|
test "marks drawn onto an image are kept for the test, a PNG made by the next frame" {
  let made : Ref[Bytes?] = { val: None }
  let marking : Ref[@ui.MarkedImage?] = { val: None }
  let marks = "{\"w\":100,\"h\":80,\"marks\":[{\"kind\":\"box\",\"color\":4278190335,\"halo\":4294967295,\"w\":3,\"pts\":[10,10,50,40],\"text\":\"\",\"n\":1}]}"
  let t = @ui.Tester::new(fn(c) {
    match marking.val {
      Some(m) =>
        match m.made() {
          Some(png) => made.val = Some(png)
          None => ()
        }
      None => ()
    }
    c.text("marks", wrap=false) |> ignore
  })
  marking.val = @ui.draw_marks(b"\x89PNG not decoded here", marks)
  assert_eq(t.marks_drawn(), [marks])
  t.draw()
  match made.val {
    Some(png) => {
      assert_true(png.length() > 8)
      assert_eq(png[0:8].to_bytes(), b"\x89PNG\r\n\x1A\n")
    }
    None => fail("no PNG made")
  }
}

///|
test "what the app shares out is handed to the system's sheet, kept for the test" {
  let t = @ui.Tester::new(fn(c) { c.text("share", wrap=false) |> ignore })
  assert_eq(@ui.share("", "a.png", "image/png", b"\x89PNG"), true)
  assert_eq(@ui.share("a link: https://example.test", "", "", b""), true)
  assert_eq(t.shared_out(), [("", "a.png", "image/png", b"\x89PNG"), ("a link: https://example.test", "", "", b"")])
}

///|
test "marks drawn onto an image give the PNG the test says, the next one a clear pixel again" {
  let made : Array[Bytes] = []
  let marking : Array[@ui.MarkedImage] = []
  let t = @ui.Tester::new(fn(c) {
    for m in marking {
      match m.made() {
        Some(png) => if !made.iter().any(fn(b) { physical_equal(b, png) }) { made.push(png) }
        None => ()
      }
    }
    c.text("marks", wrap=false) |> ignore
  })
  let given = Bytes::makei(10957, fn(i) { if i < 8 { b"\x89PNG\r\n\x1A\n"[i] } else { b'\x00' } })
  t.marks_make(given)
  marking.push(@ui.draw_marks(b"image", "{}").unwrap())
  t.draw()
  marking.push(@ui.draw_marks(b"image", "{}").unwrap())
  t.draw()
  assert_eq(made.length(), 2)
  assert_eq(made[0].length(), 10957)
  assert_true(made[1].length() < 100)
}

///|
test "a player's state is read before the frame is built: set, one frame shows it" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() { @ui.NativeView::video("video/mp4", fn(_o, _l, answer) { answer(b"", -1.0) }) })
    c.native(v, h=Px(220.0)) |> ignore
    c.text("at \{(v.position() / 1000.0).to_int()} s", wrap=false) |> ignore
  })
  let v = cell.val.unwrap()
  t.set_player(v.id(), position=2000.0)
  let before = t.frames
  t.draw()
  assert_eq(t.frames - before, 1)
  assert_true(t.find("at 2 s") is Some(_))
}

///|
test "a video's frames' times and a frame grabbed are what the run said the host said: not known until said" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
    })
    c.native(v, h=Px(220.0)) |> ignore
  })
  let v = cell.val.unwrap()
  // nothing said of its frames yet: not known
  assert_eq(v.frames(), None)
  assert_true(t.view_said("{\"view\":{\"view\":1,\"what\":1,\"text\":\"0,40,80.5\"}}"))
  t.draw()
  assert_eq(v.frames(), Some([0.0, 40.0, 80.5]))
  // a grab: none until the run's host had it, then its bytes once
  v.grab_frame(40.0)
  t.draw()
  assert_eq(v.grabbed(), None)
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"89504e47\"}"))
  t.draw()
  assert_eq(v.grabbed(), Some(b"\x89PNG"))
  assert_eq(v.grabbed(), None)
  // a grab that failed, as said
  assert_true(t.view_said("{\"view\":{\"view\":1,\"what\":2,\"text\":\"-1\"}}"))
  assert_eq(v.grabbed(), Some(b""))
  assert_false(t.view_said("{\"in\":{\"id\":1}}"))
}

///|
test "how a view stands is what the run said the host said: still opening, then ready at its length" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
    })
    c.native(v, h=Px(220.0)) |> ignore
  })
  let v = cell.val.unwrap()
  assert_true(t.view_said("{\"info\":{\"view\":1,\"state\":0,\"at\":[-1,0,0,0,0,0,0,0,0,0]}}"))
  t.draw()
  assert_eq(v.state(), 0)
  assert_true(t.view_said("{\"info\":{\"view\":1,\"state\":1,\"at\":[4000,1500,0,1920,1080,1,1,0,0,0]}}"))
  t.draw()
  assert_eq(v.state(), 1)
  assert_eq(v.duration(), 4000.0)
  assert_eq(v.natural(), (1920.0, 1080.0))
}

///|
test "a native view between pixels is placed on whole device pixels, its hole and clip on the same ones, at any scale" {
  for scale in [1.0, 2.0, 3.0, 2.625] {
    let cell : Ref[@ui.NativeView?] = { val: None }
    let t = @ui.Tester::new(
      fn(c) {
        let v = once(cell, fn() {
          @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
        })
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(h=Px(100.3), fn() { () }) |> ignore
          // a picture fitted between pixels (a 16:9 one in 366 across: 205.875 down)
          c.native(v, h=Px(300.0), content=Some((12.0, 47.0625, 366.0, 205.875))) |> ignore
        })
        |> ignore
      },
      scale~,
    )
    let on_px = fn(p : Double) { ((p * scale).round() - p * scale).abs() < 1.0e-6 }
    let (hx, hy, hw, hh) = t.holes()[0]
    assert_true(on_px(hx) && on_px(hy) && on_px(hx + hw) && on_px(hy + hh), msg="hole at \{scale}")
    // what the host was told (place ID X Y W H in CX0 CY0 CX1 CY1): its content's edges the hole's, its clip on
    // whole device pixels too
    let place = t.views().filter(fn(l) { l.has_prefix("place 1 ") }).last().unwrap()
    let n = place
      .split(" ")
      .to_array()
      .filter_map(fn(p) {
        match (try Some(@json.parse(p.to_string())) catch { _ => None }) {
          Some(Number(d, ..)) => Some(d)
          _ => None
        }
      })
    // (1, x, y, w, h, cx0, cy0, cx1, cy1)
    assert_eq(n.length(), 9, msg=place)
    assert_eq((n[1], n[2], n[1] + n[3], n[2] + n[4]), (hx, hy, hx + hw, hy + hh), msg=place)
    for i in 5..<9 {
      assert_true(on_px(n[i]), msg=place)
    }
  }
}

///|
test "a frame grab is waited on until its PNG is taken; then the view may grab again" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
    })
    c.native(v, h=Px(220.0)) |> ignore
  })
  let v = cell.val.unwrap()
  v.grab_frame(40.0)
  assert_true(@ui.runtime().awaited().iter().any(fn(a) { a.0.contains("a frame of view 1 grabbed") }))
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"89504e47\"}"))
  t.draw()
  assert_eq(v.grabbed(), Some(b"\x89PNG"))
  assert_false(@ui.runtime().awaited().iter().any(fn(a) { a.0.contains("grabbed") }))
  // taken: another may be asked
  v.grab_frame(80.0)
  assert_true(@ui.runtime().awaited().iter().any(fn(a) { a.0.contains("a frame of view 1 grabbed") }))
}

///|
test "panic a second frame grab of a view before the first is taken" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let _ = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::video("video/mp4", fn(_offset, _length, answer) { answer(b"", -1.0) })
    })
    c.native(v, h=Px(220.0)) |> ignore
  })
  let v = cell.val.unwrap()
  v.grab_frame(40.0)
  v.grab_frame(80.0)
}

///|
test "what a site's page asked of its host, as a run recorded it, is asked again: its request, its body, where it is" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let asked : Array[(String, String, Array[(String, String)], Bool, Bytes)] = []
  let t = @ui.Tester::new(fn(c) {
    let v = once(cell, fn() {
      @ui.NativeView::site("/", fn(req, reply) {
        asked.push((req.verb, req.path, req.headers, req.page, req.body))
        reply.end()
      })
    })
    c.native(v, h=Px(300.0)) |> ignore
  })
  let v = cell.val.unwrap()
  let id = v.id()
  // (the lines a run's record has: @ui.trace_views', in the order the host said them)
  assert_true(
    t.view_said(
      "{\"sitestate\":{\"view\":\{id},\"state\":{\"path\":\"/svc\",\"back\":true,\"forward\":false,\"loading\":false,\"title\":\"Service\"}}}",
    ),
  )
  assert_true(t.view_said("{\"sitebody\":{\"view\":\{id},\"req\":7},\"b\":\"6869\"}"))
  assert_true(
    t.view_said(
      "{\"site\":{\"view\":\{id},\"event\":{\"req\":7,\"method\":\"POST\",\"path\":\"/api\",\"page\":false,\"headers\":[[\"User-Agent\",\"WebKit\"]]}}}",
    ),
  )
  t.draw()
  assert_eq(asked, [("POST", "/api", [("User-Agent", "WebKit")], false, b"hi")])
  assert_eq(v.page_at(), ("/svc", true, false, false, "Service"))
}
