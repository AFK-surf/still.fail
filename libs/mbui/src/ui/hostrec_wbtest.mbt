///|
test "a picture handed over as bytes decodes as the host kept it, and a PDF's pages are the host's" {
  let data = b"\x89PNG not really"
  let pdf = b"%PDF-1.7 not really"
  // (asked at the bucket a 100 point box at scale 2 needs)
  let px = 256
  let kept =
    #|{"m":[15,400,0],"r":[12,3,18]}
  let lines = kept +
    "\n" +
    ({ "ib": [Json::string(bytes_name(data)), Json::number(data.length().to_double()), Json::number(px.to_double())], "r": [300, 200, 1200, 800] } : Json).stringify() +
    "\n" +
    ({ "pn": [Json::string(bytes_name(pdf)), Json::number(pdf.length().to_double())], "r": 2 } : Json).stringify() +
    "\n" +
    ({ "ps": [Json::string(bytes_name(pdf)), Json::number(pdf.length().to_double()), Json::number(1)], "r": [595, 842] } : Json).stringify()
  let t = Tester::new(
    fn(c) {
      c.image_bytes("mem:a", data)
      c.image("mem:a", w=Px(100.0), h=Px(100.0)) |> ignore
    },
    text=lines,
  )
  t.draw()
  t.draw()
  let out = FixedArray::make(4, 0.0)
  // the one picture asked: decoded as the host had it
  assert_eq(h_image_info(1, out), 1)
  assert_eq((out[0], out[1], out[2], out[3]), (300.0, 200.0, 1200.0, 800.0))
  let doc = h_pdf_open(pdf)
  assert_eq(h_pdf_pages(doc), 2)
  let size = FixedArray::make(2, 0.0)
  h_pdf_page_size(doc, 1, size)
  assert_eq((size[0], size[1]), (595.0, 842.0))
  // a page the host was not asked of: the fake's, and said as missing
  h_pdf_page_size(doc, 0, size)
  assert_eq((size[0], size[1]), (612.0, 792.0))
  assert_true(t.text_missing().iter().any(fn(m) { m.has_prefix("host ps|") }))
}

///|
test "a frame's pictures are compared by the order they are drawn in, not the host's ids" {
  let first = Ref("b.png")
  let t = Tester::new(fn(c) { c.image(first.val, w=Px(50.0), h=Px(50.0)) |> ignore }, images=[
    ("a.png", 10, 10),
    ("b.png", 10, 10),
  ])
  t.draw()
  t.draw()
  // (each frame on the display's clock: both run on to where b has faded in, the same picture)
  t.run_for(image_fade_ms)
  let straight = t.frame_hash()
  let u = Tester::new(fn(c) { c.image(first.val, w=Px(50.0), h=Px(50.0)) |> ignore }, images=[
    ("a.png", 10, 10),
    ("b.png", 10, 10),
  ])
  // another picture decoded first: b another id
  first.val = "a.png"
  u.draw()
  u.draw()
  first.val = "b.png"
  u.draw()
  u.draw()
  u.run_for(image_fade_ms)
  assert_eq(u.frame_hash(), straight)
}
