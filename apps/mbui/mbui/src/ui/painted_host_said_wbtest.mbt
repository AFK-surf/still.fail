// A place worked out as the frame is painted (Painted) while the host hands something on (on_host_said) and that lays
// the tree out (laid_size): what it reads of another node laid out, as told (laid_size_told) and as laid out now
// (Laid::size), worked out with no fault, the last read the one it is drawn by; read by the hand-off itself, it aborts.

///|
/// A node `a` as wide as `wide`, and one placed across by how wide `a` is laid out as it is painted, both reads of `a`
/// kept (`seen`: as told, as laid out now); `host`'s hand-off setting `wide` to 160 and laying `a` out, then `after`.
/// `frames` drawn before it is handed on, two after: where the second is drawn across.
fn painted_said(frames : Int, after? : (@view.View) -> Unit = fn(_) {  }) -> (Double, Array[((Double, Double)?, (Double, Double)?)]) {
  let host = OnceHad::new()
  let wide = @signals.signal(100.0, same=fn(a, b) { a == b })
  let seen : Array[((Double, Double)?, (Double, Double)?)] = []
  let placed : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    let a : Ref[@view.View?] = Ref(None)
    root.box(fn(b) {
      a.val = Some(b)
      b.width(By(fn() { Some(wide.get()) })).height(Is(Some(40.0))) |> ignore
    })
    |> ignore
    root.box(fn(c) {
      placed.val = Some(c)
      c
      .width(Is(Some(10.0)))
      .height(Is(Some(10.0)))
      .offset(@view.Painted(fn(laid) {
        let told = a.val.unwrap().laid_size_told()
        let now = laid.size(a.val.unwrap())
        seen.push((told, now))
        (now.map(fn(z) { z.0 }).unwrap_or(0.0), 0.0)
      }))
      |> ignore
    })
    |> ignore
    on_host_said(root, kind="resize-asked", fn() { host.said() }, fn(_) {
      wide.set(160.0)
      a.val.unwrap().laid_size() |> ignore
      after(a.val.unwrap())
    })
  })
  for _ in 0..<frames {
    t.draw()
  }
  host.had.val = Some("asked")
  t.draw()
  t.draw()
  let x = placed.val.unwrap().shown_rect().map(fn(r) { r.0 }).unwrap_or(-1.0)
  (x, seen)
}

///|
test "handed on, laid out there: a place painted reads another node laid out with no fault, drawn by it as laid out now, a frame before or none" {
  let (x2, seen2) = painted_said(2)
  let (x1, seen1) = painted_said(1)
  println("two frames before: at \{x2}, read \{seen2}; one: at \{x1}, read \{seen1}")
  assert_eq(x2, 160.0)
  assert_eq(x1, 160.0)
  assert_eq(seen2.last().map(fn(s) { s.1 }), Some(Some((160.0, 40.0))), msg="as laid out now, last")
}

///|
test "panic: handed on and laid out there, what is laid out read by the hand-off itself after it aborts" {
  painted_said(1, after=fn(a) { a.laid_size_told() |> ignore }) |> ignore
}
