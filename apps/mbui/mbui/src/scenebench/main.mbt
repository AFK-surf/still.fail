// What a frame of the window's tree costs, in milliseconds, natively (docs/retained.md rule 14; matklad's "Benchmark
// In Milliseconds"): a Tester's window drawn as a host draws it (Tester::measure_as_host: none of a test's checks; its
// frames the display's, none a step of a test's), each scene's frames timed together, five runs each, every run said in
// whole ms, and how many layers were moved by an offset as they were.
//
//   spinner-3000: a spinner turning on the resident clock over a chat's list of 3000 messages, 30000 of its steps
//   spinner-empty: the same spinner over an empty page, 30000 steps
//   row-3000: a row of a list of 3000 told new words (as many letters), 6000 times, a frame each

///|
let steps : Int = 30000

///|
/// How many frames a row of the list told new words is drawn.
let rows_frames : Int = 6000

///|
let spin_period_ms : Double = 800.0

///|
/// A spinner over a list of `n` messages (none: an empty page), drawn once.
fn spinner(n : Int) -> @ui.Tester {
  // (no check of a test's run on its frames: what a host draws, alone)
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=600.0, corners_held=false, words_over_held=false)
  t.measure_as_host()
  @ui.set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(400.0))).height(Is(Some(600.0))).ground(Is(0xFFFFFFFFL)) |> ignore
      page.box(fn(s) {
        s
        .offset(Is((360.0, 0.0)))
        .width(Is(Some(24.0)))
        .height(Is(Some(24.0)))
        .radius(Is(6.0))
        .ground(Is(0x1559C4FFL))
        .turn(By(fn() { s.cycle_resident(spin_period_ms) * 2.0 * 3.141592653589793 }))
        |> ignore
      })
      |> ignore
      if n > 0 {
        page.box(fn(list) {
          list.width(Is(Some(400.0))).height(Is(Some(540.0)))
          .scrolls_window(@view.Scroll::list(), fn() { Array::makei(n, fn(i) { i }) }, est=48.0, from_end=true, fn(
            row,
            k,
          ) {
            row.height(Is(Some(48.0))).ground(Is(if k % 2 == 0 { 0xF2F2F2FFL } else { 0xFFFFFFFFL })) |> ignore
            row.box(fn(w) { w.words(Is("message")) |> ignore }) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// A list of 3000 messages, its last row's words those `words` says, drawn once.
fn rows(words : @signals.Signal[String]) -> @ui.Tester {
  let n = 3000
  // (no check of a test's run on its frames: what a host draws, alone)
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=600.0, corners_held=false, words_over_held=false)
  t.measure_as_host()
  @ui.set_view_app(fn(root) {
    root
    .width(Is(Some(400.0)))
    .height(Is(Some(600.0)))
    .scrolls_window(@view.Scroll::list(), fn() { Array::makei(n, fn(i) { i }) }, est=48.0, from_end=true, fn(row, k) {
      row.height(Is(Some(48.0))) |> ignore
      row.box(fn(w) { w.words(By(fn() { if k == n - 1 { words.get() } else { "message" } })) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn main {
  // (`long`: the spinner over the list alone, ten times as long: for a sampler to see where its frames go)
  if @env.args().contains("long") || @env.args().contains("long-empty") {
    let t = spinner(if @env.args().contains("long-empty") { 0 } else { 3000 })
    t.set_frame_period(@view.resident_step_ms)
    t.run_for(@view.resident_step_ms * (steps * (if @env.args().contains("long-empty") { 100 } else { 10 })).to_double())
    return
  }
  let said = []
  let spin = fn(name : String, n : Int) {
    let t = spinner(n)
    // (a frame each of the display's, a step of the resident clock's apart, as a host draws them: none of them a step
    // of a test's, which builds the frame after it whole, Tester::run_for)
    t.set_frame_period(@view.resident_step_ms)
    t.run_for(@view.resident_step_ms * 30.0)
    let runs = []
    let w0 = @ui.scene_done()
    for _ in 0..<5 {
      let t0 = now_ms()
      t.run_for(@view.resident_step_ms * steps.to_double())
      runs.push((now_ms() - t0).round().to_int())
    }
    let w1 = @ui.scene_done()
    said.push("\{name}: \{steps} steps, ms \{runs} (layers moved by an offset \{w1.moved - w0.moved}, painted \{w1.full - w0.full})")
  }
  spin("spinner-3000", 3000)
  spin("spinner-empty", 0)
  let words = @signals.signal("first")
  let t = rows(words)
  let runs = []
  for _ in 0..<5 {
    let t0 = now_ms()
    for _ in 0..<rows_frames {
      words.set(if words.get() == "first" { "fresh" } else { "first" })
      t.draw()
    }
    runs.push((now_ms() - t0).round().to_int())
  }
  said.push("row-3000: \{rows_frames} frames, ms \{runs}")
  for s in said {
    println("SCENEBENCH " + s)
  }
}
