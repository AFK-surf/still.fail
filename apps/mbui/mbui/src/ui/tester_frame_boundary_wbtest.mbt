///|
test "host frame records keep both post-frame callbacks' layout between frames exactly once" {
  let height = @signals.signal(40.0)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(100.0))).height(By(fn() { Some(height.get()) })).ground(Is(0x336699FFL)) |> ignore
    }) |> ignore
  })
  t.draw()
  t.measure_as_host()
  let tree = view_tree().unwrap()
  let laid = Ref(0)
  t.record_host()
  t.each_frame(Some(fn() {
    let before = tree.work().laid
    height.set(80.0)
    tree.bring_to(t.time())
    laid.val += tree.work().laid - before
  }))
  t.between_frames(fn() {
    let before = tree.work().laid
    height.set(100.0)
    tree.bring_to(t.time())
    laid.val += tree.work().laid - before
  })
  t.frame_at(t.time() + 20.0)
  let first = t.host_frames()[0]
  assert_eq(first.laid, 0)
  assert_true(laid.val > 0)
  t.each_frame(None)
  t.between_frames(fn() { })
  t.frame_at(t.time() + 20.0)
  let next = t.host_frames()[0]
  assert_eq(next.laid, 0)
  assert_eq(next.between.iter().find_first(fn(c) { c.0 == "laid" }), Some(("laid", laid.val)))
  t.frame_at(t.time() + 20.0)
  let last = t.host_frames()[0]
  assert_eq(last.laid, 0)
  assert_eq(last.between.iter().find_first(fn(c) { c.0 == "laid" }), Some(("laid", 0)))
}

///|
test "post-frame observers see the completed record before their work is counted between frames" {
  let work = Ref(0)
  let order : Array[String] = []
  let observed : Array[HostFrame] = []
  let counts : Array[Int] = []
  let before_counts : Array[Int] = []
  let before_records : Array[Int] = []
  let setup : Ref[Tester?] = Ref(None)
  let t = Tester::new(fn(c) { c.text("frame") |> ignore }, before=fn() {
    match setup.val {
      Some(t) => {
        order.push("before")
        before_counts.push(t.frames)
        before_records.push(t.host_frames().length())
        work.val += 1
      }
      None => ()
    }
  })
  setup.val = Some(t)
  t.measure_as_host()
  t.count_between("callback", fn() { work.val })
  t.record_host()
  t.each_frame(Some(fn() {
    order.push("each")
    observed.append(t.host_frames())
    counts.push(t.frames)
    work.val += 1
  }))
  t.between_frames(fn() {
    order.push("between")
    work.val += 1
  })
  let before = t.frames
  t.frame_at(t.time() + 20.0)
  assert_eq(order, ["before", "each", "between"])
  assert_eq(before_counts, [before])
  assert_eq(before_records, [0])
  assert_eq(counts, [before + 1])
  assert_eq(observed.length(), 1)
  assert_eq(observed[0].between.iter().find_first(fn(c) { c.0 == "callback" }), Some(("callback", 1)))
  setup.val = None
  t.each_frame(None)
  t.between_frames(fn() { })
  t.frame_at(t.time() + 20.0)
  let next = t.host_frames()
  assert_eq(next.length(), 1)
  assert_eq(next[0].between.iter().find_first(fn(c) { c.0 == "callback" }), Some(("callback", 2)))
  t.frame_at(t.time() + 20.0)
  assert_eq(t.host_frames()[0].between.iter().find_first(fn(c) { c.0 == "callback" }), Some(("callback", 0)))
}

///|
test "an automatic host reply before on_frame is counted between frames as an explicit reply is" {
  for automatic in [false, true] {
    let height = @signals.signal(40.0)
    let t = Tester::new(fn(_) { }, images=[("boundary.jpg", 400, 300)], finish=false, tree=fn(root) {
      root.box(fn(v) {
        v.width(Is(Some(100.0))).height(By(fn() { Some(height.get()) })).ground(Is(0x336699FFL)) |> ignore
      }) |> ignore
      root.box(fn(v) {
        v.width(Is(Some(100.0))).height(Is(Some(100.0))).image(Is(Some(("boundary.jpg", "", 4096)))) |> ignore
      }) |> ignore
    })
    t.draw()
    t.measure_as_host()
    let pending = t.pending()
    assert_eq(pending.length(), 1)
    let tree = view_tree().unwrap()
    let replied = Ref(0)
    let laid = Ref(0)
    let off = @signals.effect(fn() {
      if image_state("boundary.jpg") == 1 {
        replied.val += 1
        let before = tree.work().laid
        height.set(80.0)
        tree.bring_to(t.time())
        laid.val += tree.work().laid - before
      }
    })
    t.count_between("reply", fn() { replied.val })
    t.record_host()
    t.fake.auto_finish = automatic
    let at = t.time() + 20.0
    if !automatic {
      t.fake.time = at
      t.finish(pending[0].0, pending[0].1)
    }
    t.frame_at(at)
    let frame = t.host_frames()[0]
    assert_eq(replied.val, 1)
    assert_true(laid.val > 0)
    assert_eq(frame.between.iter().find_first(fn(c) { c.0 == "reply" }), Some(("reply", 1)))
    assert_eq(frame.between.iter().find_first(fn(c) { c.0 == "laid" }), Some(("laid", laid.val)))
    assert_eq(frame.laid, 0)
    assert_eq(image_state("boundary.jpg"), 1)
    t.frame_at(at + 20.0)
    let next = t.host_frames()[0]
    assert_eq(next.between.iter().find_first(fn(c) { c.0 == "reply" }), Some(("reply", 0)))
    assert_eq(next.between.iter().find_first(fn(c) { c.0 == "laid" }), Some(("laid", 0)))
    off()
  }
}
