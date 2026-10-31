// The system's back as a node of the window's tree follows it (View::follows_back), through the host's way in (on_back):
// a gesture held by the node it began on, done as the system decides as that gesture's end (Tree::back_done), a back
// with no gesture one Back; a gesture's end never taken for a back of its own.

///|
/// A node following back over the whole window (told in `told` by which saying of it: `name`), taking presses while
/// `on`; the node, to say anew.
fn back_tester(on : @signals.Signal[Bool], told : Array[String]) -> (Tester, Ref[@view.View?]) {
  let v : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(n) {
      v.val = Some(n)
      n.over(Is(true)).presses(By(fn() { on.get() })).follows_back(fn(s) { told.push("first \{s}") }) |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, v)
}

///|
test "the system's back gesture done as it decides: the node holding it told Back, once; a back with no gesture, Back, once" {
  let told : Array[String] = []
  let (t, _v) = back_tester(@signals.signal(true), told)
  on_back(0, 0.0, 0.0, 0)
  on_back(1, 50.0, 0.3, 0)
  on_back(2, 50.0, 1.0, 0)
  t.frames_owed()
  on_back(2, 0.0, 1.0, 0)
  t.frames_owed()
  assert_eq(told.length(), 4, msg="\{told}")
  assert_eq([told[2], told[3]], ["first Back", "first Back"])
}

///|
test "a gesture held by a node said anew to follow back, the system then deciding it done: the new saying told nothing of that gesture's end" {
  let told : Array[String] = []
  let (t, v) = back_tester(@signals.signal(true), told)
  on_back(0, 0.0, 0.0, 0)
  v.val.unwrap().follows_back(fn(s) { told.push("second \{s}") }) |> ignore
  on_back(2, 50.0, 1.0, 0)
  t.frames_owed()
  assert_false(told.contains("second Back"), msg="the gesture's end, taken for a back of its own: \{told}")
  // (a back with no gesture after it: the new saying's)
  on_back(2, 0.0, 1.0, 0)
  t.frames_owed()
  assert_true(told.contains("second Back"), msg="\{told}")
}

///|
test "a gesture done as the system decides, then the node taking no press: no gesture held, nothing called off" {
  let told : Array[String] = []
  let on = @signals.signal(true)
  let (t, _v) = back_tester(on, told)
  on_back(0, 0.0, 0.0, 0)
  on_back(2, 50.0, 1.0, 0)
  t.frames_owed()
  let tree = view_app.val.unwrap()
  tree.event(view_moment(), fn() { on.set(false) })
  assert_false(told.contains("first CalledOff"), msg="\{told}")
}

///|
test "back begun on a node moved and widened since it was drawn, no frame between: x in its terms as it is at back's moment, as with a frame drawn between; held, in those terms as it goes, whatever is laid out meanwhile" {
  let run = fn(frame : Bool) {
    let told : Array[String] = []
    let dx = @signals.signal(20.0, same=fn(a, b) { a == b })
    let w = @signals.signal(100.0, same=fn(a, b) { a == b })
    let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
    t.check_looks(false)
    set_view_app(fn(root) {
      root.box(fn(n) {
        n
        .over(Is(true))
        .width(By(fn() { Some(w.get()) }))
        .height(Is(Some(200.0)))
        .offset(By(fn() { (dx.get(), 0.0) }))
        .follows_back(fn(s) {
          told.push(
            match s {
              Began(x, _) => "Began \{x}"
              Moved(x, _) => "Moved \{x}"
              other => "\{other}"
            },
          )
        })
        |> ignore
      })
      |> ignore
    })
    t.draw()
    let tree = view_app.val.unwrap()
    tree.event(view_moment(), fn() {
      dx.set(100.0)
      w.set(250.0)
    })
    if frame {
      t.frames_owed()
    }
    on_back(0, 150.0, 0.0, 0)
    // (laid out anew as it goes: its terms the ones it began in)
    tree.event(view_moment(), fn() { dx.set(200.0) })
    t.frames_owed()
    on_back(1, 180.0, 0.3, 0)
    told
  }
  let want = ["Began 50", "Moved 80"]
  assert_eq(run(false), want, msg="no frame between")
  assert_eq(run(true), want, msg="a frame between")
}
