// What was posted from outside and left for the frame (a message whose channel takes none as it comes:
// on_message_said) is handed to its handler as the frame begins, outside the frame's reading (take_messages): what the
// handler reads is not the frame's to follow, what it changes is drawn by that frame, an effect it makes is its own.
// So for files let go on what takes them (drop.mbt's "mbui.drop": Ctx::on_files' take, run in that handler). Each
// case with the Tester's looks compared no more (check_looks(false)): that frame read again over the frame's watch
// would leave it following what it read itself (tester_looks.mbt), which is not a device's way.

///|
/// How long a Tester runs before the message is posted, and how long after it the signal its handler read is set.
let take_untracked_before_ms : Double = 100.0

///|
let take_untracked_after_ms : Double = 400.0

///|
/// A Tester (the window's tree, or an old view) given a message on `channel`, whose handler reads `s`; then `s` set:
/// why the frame after it was built whole ("" none), and whether the handler ran.
fn take_read_then_set(channel : String, nodes : Bool) -> (String, Bool) {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let done = Ref(false)
  on_message(channel, fn(_json, _bytes) {
    s.get() |> ignore
    done.val = true
  })
  let t = if nodes {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    set_view_app(fn(root) { root.box(fn(b) { b.words(Is("x")) |> ignore }) |> ignore })
    t.draw()
    t
  } else {
    Tester::new(fn(c) { c.text("x", wrap=false) |> ignore }, w=200.0, h=200.0)
  }
  t.check_looks(false)
  t.run_for(take_untracked_before_ms)
  t.post(channel, "{}")
  t.run_for(take_untracked_after_ms)
  s.set(1)
  t.frame()
  (t.built_why(), done.val)
}

///|
test "a signal read by the handler of a message left for the frame, set later: no frame built whole for it" {
  assert_eq(take_read_then_set("take.untracked.read.tree", true), ("", true))
  assert_eq(take_read_then_set("take.untracked.read.old", false), ("", true))
}

///|
/// An effect made by the handler of a message left for the frame is the handler's, never the frame's: the frames
/// after it built whole (by what the old view's build reads, `k`), it is still there, run again as what it reads (`s`)
/// changes; never told as made in a watch (@signals.effect_in_watch).
test "an effect made by the handler of a message left for the frame lives past the frames built whole after it" {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let k : @signals.Signal[Int] = @signals.signal(0)
  let seen : Array[Int] = []
  let told : Array[String] = []
  let stop : Ref[() -> Unit] = Ref(fn() {  })
  on_message("take.untracked.effect", fn(_json, _bytes) {
    stop.val = @signals.effect(fn() { seen.push(s.get()) })
  })
  let was = @signals.effect_in_watch.val
  @signals.effect_in_watch.val = Some(fn(loc) { told.push(loc.to_string()) })
  let t = Tester::new(fn(c) { c.text("k \{k.get()}", wrap=false) |> ignore }, w=200.0, h=200.0)
  t.check_looks(false)
  t.run_for(take_untracked_before_ms)
  t.post("take.untracked.effect", "{}")
  t.run_for(take_untracked_after_ms)
  k.set(1)
  t.frame()
  let why = t.built_why()
  s.set(5)
  (stop.val)()
  s.set(6)
  @signals.effect_in_watch.val = was
  assert_true(why.contains("what it read changed"), msg=why)
  assert_eq(told, [])
  // (made, run at once; run again for 5; stopped by its maker before 6)
  assert_eq(seen, [0, 5])
}

///|
/// What the handler of a message left for the frame sets is drawn by the frame that hands it on, the view reading it
/// after (the window's tree's binding, an old view's build): the words of each frame from the message's on.
fn take_set_drawn_at_once(channel : String, nodes : Bool) -> Array[String] {
  let label : @signals.Signal[String] = @signals.signal("before")
  let handed = Ref(false)
  on_message(channel, fn(_json, _bytes) {
    label.set("after")
    handed.val = true
  })
  let t = if nodes {
    let t = Tester::new(fn(_c) {  }, w=200.0, h=200.0)
    set_view_app(fn(root) {
      root.box(fn(b) { b.words(By(fn() { label.get() })) |> ignore }) |> ignore
    })
    t.draw()
    t
  } else {
    Tester::new(fn(c) { c.text(label.get(), wrap=false) |> ignore }, w=200.0, h=200.0)
  }
  t.check_looks(false)
  t.run_for(take_untracked_before_ms)
  let drawn : Array[String] = []
  t.each_frame(
    Some(fn() {
      if handed.val {
        drawn.push(t.words().map(fn(w) { w.0 }).join(" "))
      }
    }),
  )
  t.post(channel, "{}")
  t.run_for(take_untracked_after_ms)
  t.each_frame(None)
  drawn
}

///|
test "what the handler of a message left for the frame sets is drawn by the frame that hands it on" {
  let tree = take_set_drawn_at_once("take.untracked.drawn.tree", true)
  assert_true(tree.length() > 0)
  assert_eq(tree[0], "after")
  let old = take_set_drawn_at_once("take.untracked.drawn.old", false)
  assert_true(old.length() > 0)
  assert_eq(old[0], "after")
}

///|
/// Files let go on a box that takes them (Ctx::on_files): its take makes an effect that waits on what it reads (`s`,
/// as sfdesk's fdrag_when waits for the files' reading), with no @signals.untracked and no owner of its own. The
/// frames after it built whole (`k`), it is still there and runs as `s` changes; never told as made in a watch.
test "an effect made as files let go are taken lives past the frames built whole after it, made with nothing of its own around it" {
  let s : @signals.Signal[Int] = @signals.signal(0)
  let k : @signals.Signal[Int] = @signals.signal(0)
  let seen : Array[Int] = []
  let told : Array[String] = []
  let stop : Ref[() -> Unit] = Ref(fn() {  })
  let took = Ref(0)
  let was = @signals.effect_in_watch.val
  @signals.effect_in_watch.val = Some(fn(loc) { told.push(loc.to_string()) })
  let t = Tester::new(
    fn(c) {
      let folder = c.id("folder")
      c.takes_presses(folder)
      c.on_files(folder, held=fn(_) {  }, take=fn(_, _) {
        Some(fn(_pick) {
          took.val += 1
          stop.val = @signals.effect(fn() { seen.push(s.get()) })
        })
      })
      c.box(id=folder, fn() { c.text("a folder k \{k.get()}") |> ignore }) |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.check_looks(false)
  t.run_for(take_untracked_before_ms)
  let (x, y) = t.find("a folder k 0").unwrap()
  t.drop_files(x, y, [("a.txt", b"a")])
  t.run_for(take_untracked_after_ms)
  k.set(1)
  t.frame()
  let why = t.built_why()
  s.set(5)
  (stop.val)()
  s.set(6)
  @signals.effect_in_watch.val = was
  assert_eq(took.val, 1)
  assert_true(why.contains("what it read changed"), msg=why)
  assert_eq(told, [])
  // (made, run at once; run again for 5; stopped by its maker before 6)
  assert_eq(seen, [0, 5])
}
