// Pixel requests complete on host input, independent of which frames are drawn.

///|
test "a pixel request completes at decode and an already decoded request completes immediately, each once" {
  let t = Tester::new(fn(_) { }, finish=false)
  let rgba = FixedArray::make(16, b'\xff')
  t.add_pixels("pic", 2, 2, rgba)
  let seen : Array[ImagePixels] = []
  t.record_host()
  let stop = read_image_pixels("pic", 64, fn(p) { seen.push(p) })
  assert_eq(seen.length(), 0)
  t.finish_all()
  assert_true(seen == [PixelsRead(2, 2, rgba)])
  let again = read_image_pixels("pic", 64, fn(p) { seen.push(p) })
  assert_true(seen == [PixelsRead(2, 2, rgba), PixelsRead(2, 2, rgba)])
  stop()
  again()
  t.finish_all()
  assert_eq(seen.length(), 2)
  assert_eq(t.host_frames().length(), 0)
  assert_false(image_said("pic").decodes.watched())
}

///|
test "a failed pixel decode completes once without a drawn frame" {
  let t = Tester::new(fn(_) { }, images=[("pic", 2, 2)], finish=false)
  let seen : Array[ImagePixels] = []
  t.record_host()
  let stop = read_image_pixels("pic", 64, fn(p) { seen.push(p) })
  let (kind, id) = t.pending()[0]
  t.finish(kind, id, ok=false)
  assert_true(seen == [PixelsFailed])
  stop()
  assert_eq(t.host_frames().length(), 0)
  assert_false(image_said("pic").decodes.watched())
}

///|
test "a cancelled pixel request or a request whose scope ended delivers nothing on later decode" {
  for by_scope in [false, true] {
    let t = Tester::new(fn(_) { }, finish=false)
    t.add_pixels("pic", 2, 2, FixedArray::make(16, b'\xff'))
    let seen : Array[ImagePixels] = []
    let cancel : Ref[() -> Unit] = Ref(fn() { })
    let scope = @signals.effect_scope(fn() {
      cancel.val = read_image_pixels("pic", 64, fn(p) { seen.push(p) })
    })
    t.record_host()
    if by_scope { scope() } else { (cancel.val)() }
    t.finish_all()
    assert_eq(seen.length(), 0)
    assert_eq(t.host_frames().length(), 0)
    assert_false(image_said("pic").decodes.watched())
    (cancel.val)()
    scope()
  }
}

///|
test "a pixel request waiting behind another resolution follows its own later decode too" {
  let t = Tester::new(fn(_) { }, finish=false)
  t.add_pixels("pic", 2, 2, FixedArray::make(16, b'\xff'))
  let seen : Array[Int] = []
  t.record_host()
  let large = read_image_pixels("pic", 128, fn(_) { seen.push(128) })
  let small = read_image_pixels("pic", 64, fn(_) { seen.push(64) })
  t.finish_all()
  assert_eq(seen, [128])
  t.finish_all()
  assert_eq(seen, [128, 64])
  assert_eq(t.host_frames().length(), 0)
  assert_false(image_said("pic").decodes.watched())
  large()
  small()
}

///|
test "a larger pixel request after a failed decode completes as failed instead of waiting for a decode never requested" {
  let t = Tester::new(fn(_) { }, images=[("pic", 2, 2)], finish=false)
  t.record_host()
  let small : Array[ImagePixels] = []
  let stop_small = read_image_pixels("pic", 64, fn(p) { small.push(p) })
  let (kind, id) = t.pending()[0]
  t.finish(kind, id, ok=false)
  assert_true(small == [PixelsFailed])
  let large : Array[ImagePixels] = []
  let stop_large = read_image_pixels("pic", 128, fn(p) { large.push(p) })
  assert_true(large == [PixelsFailed], msg="no new decode can complete this request after the source failed")
  assert_eq(t.pending().length(), 0)
  assert_eq(t.host_frames().length(), 0)
  stop_small()
  stop_large()
}

///|
test "a failed smaller decode does not cancel a larger decode already on its way" {
  let t = Tester::new(fn(_) { }, finish=false)
  let rgba = FixedArray::make(16, b'\xff')
  t.add_pixels("pic", 2, 2, rgba)
  let stop_small = read_image_pixels("pic", 64, fn(_) { })
  let small = t.pending()[0]
  let seen : Array[ImagePixels] = []
  let stop_large = read_image_pixels("pic", 128, fn(p) { seen.push(p) })
  t.record_host()
  t.finish(small.0, small.1, ok=false)
  assert_eq(seen.length(), 0)
  t.finish_all()
  assert_true(seen == [PixelsRead(2, 2, rgba)])
  assert_eq(t.host_frames().length(), 0)
  stop_small()
  stop_large()
}
