// A picture's decode is ready at the host's word that it is, at that word's moment: its fade from then, its size told
// then, to what reads that picture's size alone; what is said of the pictures let go with them.

///|
/// A.jpg asked for, a frame drawn at `last` after the start, the host's word that it is decoded at 100, its size read
/// at once (as a node following it would): when it is ready, from that word's moment.
fn ready_after(last : Double) -> Double {
  let t = Tester::new(
    fn(c) { c.image("a.jpg", w=Px(100.0), h=Px(100.0)) |> ignore },
    images=[("a.jpg", 400, 300)],
    finish=false,
  )
  t.draw()
  let t0 = t.time()
  if last > 0.0 {
    t.frame_at(t0 + last)
  }
  t.advance(t0 + 100.0 - t.time())
  let word = t.time()
  t.finish(1, 1)
  ignore(image_size("a.jpg"))
  t.frame_at(t0 + 200.0)
  image_cache.get("a.jpg").unwrap()[0].ready_at - word
}

///|
test "a picture is ready at the host's word that it is decoded: its fade from then, whichever frame was drawn last before it" {
  assert_eq(ready_after(0.0), 0.0)
  assert_eq(ready_after(80.0), 0.0)
}

///|
test "a picture's size told at its decode to what reads that picture's size alone; another decode of the same size tells nothing" {
  let px = Ref(100.0)
  let t = Tester::new(
    fn(c) {
      c.image("a.jpg", w=Px(px.val), h=Px(px.val)) |> ignore
      c.image("b.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
    },
    images=[("a.jpg", 400, 300), ("b.jpg", 200, 200)],
    finish=false,
  )
  let (a_read, b_read) = (Ref(0), Ref(0))
  let off_a = @signals.effect(fn() {
    ignore(image_size("a.jpg"))
    a_read.val += 1
  })
  let off_b = @signals.effect(fn() {
    ignore(image_size("b.jpg"))
    b_read.val += 1
  })
  t.draw()
  assert_eq((a_read.val, b_read.val), (1, 1))
  // a.jpg's decode: what reads a.jpg's size told, b.jpg's not
  t.finish(1, 1)
  assert_eq((a_read.val, b_read.val), (2, 1))
  assert_eq(image_size("a.jpg"), Some((400.0, 300.0)))
  // shown larger: a sharper decode of it, of the same picture: nothing new said of its size
  px.val = 300.0
  t.draw()
  let sharper = t.pending().filter(fn(p) { p.0 == 1 && p.1 != 2 })
  assert_eq(sharper.length(), 1)
  t.finish(1, sharper[0].1)
  assert_eq((a_read.val, b_read.val), (2, 1))
  off_a()
  off_b()
}

///|
test "what is said of a picture is let go with it, unless something still follows it: then the same, never another in its place" {
  let t = Tester::new(fn(_c) {  }, finish=false)
  t.draw()
  // read once each and followed by nothing, never decoded: let go as the frame trims what it keeps
  for i in 0..<100 {
    ignore(image_size("p\{i}.jpg"))
  }
  let followed : Ref[Int] = Ref(0)
  let off = @signals.effect(fn() {
    ignore(image_size("kept.jpg"))
    followed.val += 1
  })
  let kept = images_said.get("kept.jpg").unwrap()
  t.draw()
  t.draw()
  assert_eq(images_said.length(), 1)
  assert_true(physical_equal(images_said.get("kept.jpg").unwrap(), kept))
  // followed no more: gone too
  off()
  t.draw()
  assert_eq(images_said.length(), 0)
  ignore(followed)
}

///|
test "a picture's decode tells what draws that picture alone: another's decode builds none of it again; its own failing, it is told" {
  let t = Tester::new(
    fn(c) {
      c.image("a.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
      c.image("b.jpg", w=Px(100.0), h=Px(100.0)) |> ignore
    },
    images=[("a.jpg", 400, 300), ("b.jpg", 200, 200)],
    finish=false,
  )
  let (a_seen, b_seen) = (Ref(0), Ref(0))
  let off_a = @signals.effect(fn() {
    ignore(image_state("a.jpg"))
    a_seen.val += 1
  })
  let off_b = @signals.effect(fn() {
    ignore(image_state("b.jpg"))
    b_seen.val += 1
  })
  t.draw()
  let (a0, b0) = (a_seen.val, b_seen.val)
  // b's decode failing: what reads b told, a's not
  t.finish(1, 2, ok=false)
  assert_eq((a_seen.val - a0, b_seen.val - b0), (0, 1))
  assert_eq(image_state("b.jpg"), -1)
  // a's ready
  t.finish(1, 1)
  assert_eq((a_seen.val - a0, b_seen.val - b0), (1, 1))
  assert_eq(image_state("a.jpg"), 1)
  off_a()
  off_b()
}

///|
test "a picture the host fails to decode as it is asked for: so at once, and what reads its state told, no frame of anything else's" {
  let shown = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tester::new(fn(c) {
    if shown.get() {
      c.image("nowhere.png", w=Px(100.0), h=Px(100.0)) |> ignore
    }
  })
  let seen : Array[Int] = []
  let off = @signals.effect(fn() { seen.push(image_state("nowhere.png")) })
  t.draw()
  // (shown: its decode asked for as the frame builds, the host knowing no such picture)
  shown.set(true)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(image_state("nowhere.png"), -1)
  assert_eq(seen.last(), Some(-1))
  off()
}
