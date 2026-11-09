// An image's pixels asked for by a node of the window's tree (tree_image_pixels): none while it decodes, then its
// pixels at the host's word that the decode is done, what follows it told then; another size another decode.

///|
test "a node's image pixels: asked as it is made, none till the decode is done, then its pixels, told as they come; another size another value" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0, images=[("a.jpg", 400, 300)], finish=false)
  let small : Ref[(() -> ImagePixels?)?] = Ref(None)
  let large : Ref[(() -> ImagePixels?)?] = Ref(None)
  let told = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      let p = tree_image_pixels(v, "a.jpg", 100)
      small.val = Some(p)
      large.val = Some(tree_image_pixels(v, "a.jpg", 300))
      v.reacts(fn() { p() }, fn(_) { told.val += 1 })
    })
    |> ignore
  })
  t.draw()
  let small = small.val.unwrap()
  let large = large.val.unwrap()
  // (asked: both decodes started, neither done)
  assert_true(small() is None)
  assert_true(large() is None)
  let before = told.val
  // the smaller decode done: its pixels there, what follows them told; the larger still coming
  t.finish(1, 1)
  t.frame()
  let (sw, sh) = match small() {
    Some(PixelsRead(w, h, px)) => {
      assert_eq(px.length(), w * h * 4)
      (w, h)
    }
    _ => fail("small: not read")
  }
  assert_true(told.val > before)
  assert_true(large() is None)
  // the larger done: another value, another size
  t.finish(1, 2)
  t.frame()
  match large() {
    Some(PixelsRead(w, h, _)) => assert_true(w * h > sw * sh, msg="\{w}x\{h} after \{sw}x\{sh}")
    _ => fail("large: not read")
  }
  // (what was read is kept: the same again, nothing more told)
  let now = told.val
  t.draw()
  assert_eq(told.val, now)
  assert_true(small() is Some(PixelsRead(w, h, _)) && w == sw && h == sh)
}

///|
test "a node's image pixels: a decode that fails says so" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0, images=[("b.jpg", 200, 200)], finish=false)
  let read : Ref[(() -> ImagePixels?)?] = Ref(None)
  set_view_app(fn(root) { root.box(fn(v) { read.val = Some(tree_image_pixels(v, "b.jpg", 100)) }) |> ignore })
  t.draw()
  let read = read.val.unwrap()
  assert_true(read() is None)
  t.finish(1, 1, ok=false)
  t.frame()
  assert_true(read() is Some(PixelsFailed))
}

///|
test "a node's image pixels: bytes still on their way, its decode asked as they come, its pixels as it is done" {
  let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0, finish=false)
  let read : Ref[(() -> ImagePixels?)?] = Ref(None)
  set_view_app(fn(root) { root.box(fn(v) { read.val = Some(tree_image_pixels(v, "mem:late", 100)) }) |> ignore })
  t.draw()
  let read = read.val.unwrap()
  // (nothing to decode yet)
  assert_true(read() is None)
  assert_eq(image_cache.get("mem:late").map(fn(l) { l.length() }).unwrap_or(0), 0)
  // its bytes come: its decode asked then, still coming
  add_image("mem:late", b"\x89PNG not really")
  t.frame()
  assert_eq(image_cache.get("mem:late").map(fn(l) { l.length() }).unwrap_or(0), 1)
  assert_true(read() is None)
  t.finish(1, 1)
  t.frame()
  assert_true(read() is Some(PixelsRead(_, _, _)))
}
