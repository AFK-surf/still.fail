// A picture said to take a while to decode (Tester::decode_after): its host says it is decoded at the moment it was
// asked for and that long after it, on the timeline, at any frame rate.

///|
test "a picture that takes 137 ms to decode: told decoded at the moment it was asked for and 137 after it, the same at any frame rate; another told at once" {
  let shown = @signals.signal(false)
  let told : Map[String, Double] = Map([])
  let t = Tester::new(fn(_c) {  }, images=[("slow", 600, 400), ("quick", 600, 400)])
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(v) {
      for src in ["slow", "quick"] {
        v.box(fn(n) {
          n.width(Is(Some(60.0))).height(Is(Some(40.0))).image(Is(Some((src, "", 4096)))) |> ignore
          n.reacts(fn() { n.image_ready(src, 60.0) }, fn(ready) {
            if ready && !told.contains(src) {
              told[src] = n.cause_at()
            }
          })
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.decode_after("slow", 137.0)
  t.run_for(decode_test_before)
  let asked = t.time()
  shown.set(true)
  t.run_for(decode_test_after)
  let at = fn(src : String) { told.get(src).unwrap_or(-1.0) }
  assert_true((at("quick") - asked).abs() < 1.0e-6, msg="\{Repr(told)} asked \{asked}")
  assert_true((at("slow") - (asked + 137.0)).abs() < 1.0e-6, msg="\{Repr(told)} asked \{asked}")
}

///|
/// How long the test runs before the picture is shown (any while: at rest by then), and after it (past the 137 ms its
/// decode takes, and what follows it).
let decode_test_before : Double = 100.0

///|
let decode_test_after : Double = 500.0
