///|
fn picture_node_frames(retained : Bool, layered? : Bool = false) -> Array[Array[Array[Double]]] raise {
  let readied : Ref[ScreenPicture?] = Ref(None)
  let revision = @signals.signal(0)
  let read = fn() { revision.get() |> ignore; readied.val.unwrap() }
  let t = @ui.Tester::new(fn(c) {
    if !retained && readied.val is Some(_) {
      let p = read()
      c.box(style=@ui.style(w=Fixed(p.rect.w), h=Fixed(p.rect.h), opacity=if p.faded { O40 } else { O100 }), tx=p.rect.x, ty=p.rect.y, fn() {
        match p.whole {
          Some(s) => c.stream(s, w=Fill(1.0), h=Fill(1.0), layer=p.layer) |> ignore
          None => ()
        }
        match p.part {
          Some((s, crop)) => c.layer(fn() {
            c.stream(s, at=Some((crop.x*p.rect.w, crop.y*p.rect.h, crop.w*p.rect.w, crop.h*p.rect.h)), layer=p.layer) |> ignore
          }) |> ignore
          None => ()
        }
      }) |> ignore
    }
  }, w=500.0, h=400.0, h264=layered)
  t.set_stream_layers(layered)
  let whole = @ui.Stream::new(shown=fn(_) { }, broken=fn() { }, layer=layered)
  let part = @ui.Stream::new(shown=fn(_) { }, broken=fn() { }, layer=layered)
  readied.val = Some({whole:Some(whole), part:None, rect:{x:20.0,y:30.0,w:320.0,h:180.0}, faded:false,layer:layered})
  if retained { @ui.set_view_app(fn(root) { screen_picture_node(root, read) |> ignore }) }
  if layered {
    let avcc = b"\x01\x42\xc0\x1f\xff\xe1\x00\x06\x67\x42\xc0\x1f\xda\x01\x01\x00\x04\x68\xce\x3c\x80"
    whole.h264(avcc, 1280, 720)
    part.h264(avcc, 640, 360)
    whole.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
    part.frame(b"\x00\x00\x00\x01\x65", true, 1.0)
  } else {
    whole.jpeg(b"", 1.0)
    part.jpeg(b"", 1.0)
  }
  t.stream_shows(whole.id(), 1.0, 1280, 720)
  t.stream_shows(part.id(), 1.0, 640, 360)
  let pictures = []
  for step in 0..<4 {
    let p = read()
    readied.val = Some({ ..p,
      part: if step == 0 || step == 3 { None } else { Some((part, {x:0.25,y:0.2,w:0.5,h:0.5})) },
      faded: step == 2,
      layer: layered && step != 2,
      rect: if step == 2 { {x:-20.0,y:10.0,w:400.0,h:225.0} } else { p.rect },
    })
    revision.set(step + 1)
    t.draw()
    let images = t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_eq(images.length(), if layered && step != 2 { 0 } else if step == 0 || step == 3 { 1 } else { 2 })
    if layered {
      for id in [1, 2] {
        let placed = t.views().filter(fn(line) { line.has_prefix("place \{id} ") })
        if placed.last() is Some(last) {
          assert_eq(last.contains("hidden"), if id == 1 { step == 2 } else { step != 1 }, msg=last)
        } else {
          assert_true(id == 2 && step == 0)
        }
      }
    }
    pictures.push(images)
  }
  whole.close()
  part.close()
  pictures
}

///|
test "retained screen picture preserves full and cropped frames through zoom fade and region removal" {
  assert_eq(picture_node_frames(true), picture_node_frames(false))
}

///|
test "retained screen pictures move from system video layers to faded textures and back" {
  assert_eq(picture_node_frames(true, layered=true), picture_node_frames(false, layered=true))
}
