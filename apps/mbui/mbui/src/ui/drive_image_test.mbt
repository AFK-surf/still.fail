///|
test "a script can require a picture that decoded before the run" {
  let t = @ui.Tester::new(
    fn(c) { c.image("poster.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore },
    images=[("poster.png", 100, 100)],
  )
  t.draw()
  assert_true(t.pending().is_empty())
  let logs = t.drive("image_ready poster.png\nexit")
  assert_true(logs.iter().any(fn(line) { line == "DRIVE PASS" }), msg=logs.join("\n"))
}

///|
test "a script waits for its named picture to decode and rejects a failed decode" {
  let make = fn() {
    @ui.Tester::new(
      fn(c) { c.image("poster.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore },
      images=[("poster.png", 100, 100)],
      finish=false,
    )
  }
  let t = make()
  let pending = t.pending()
  assert_eq(pending.length(), 1)
  let said = Ref::new(false)
  let logs = t.drive("image_ready poster.png\nexit", each=fn(t) {
    if !said.val {
      said.val = true
      t.finish(1, pending[0].1)
    }
  })
  assert_true(logs.iter().any(fn(line) { line == "DRIVE PASS" }), msg=logs.join("\n"))

  let t = make()
  let pending = t.pending()
  assert_eq(pending.length(), 1)
  t.finish(1, pending[0].1, ok=false)
  t.draw()
  let logs = t.drive("image_ready poster.png\nexit")
  assert_true(logs.iter().any(fn(line) { line.has_prefix("DRIVE FAIL") && line.contains("could not be decoded") }), msg=logs.join("\n"))
}

///|
test "a named picture does not wait for another picture and an ambiguous name fails" {
  let t = @ui.Tester::new(
    fn(c) {
      c.image("one/poster.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore
      c.image("other.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore
    },
    images=[("one/poster.png", 100, 100), ("other.png", 100, 100)],
    finish=false,
  )
  let pending = t.pending()
  let said = Ref(false)
  let logs = t.drive("image_ready poster.png\nexit", each=fn(t) {
    if !said.val {
      said.val = true
      for (_, id) in pending {
        if t.image_src(id) == "one/poster.png" {
          t.finish(1, id)
        }
      }
    }
  })
  assert_true(logs.iter().any(fn(line) { line == "DRIVE PASS" }), msg=logs.join("\n"))
  assert_eq(t.pending().length(), 1)

  let t = @ui.Tester::new(
    fn(c) {
      c.image("one/poster.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore
      c.image("two/poster.png", w=Px(100.0), h=Px(100.0), fade=false) |> ignore
    },
    images=[("one/poster.png", 100, 100), ("two/poster.png", 100, 100)],
  )
  let logs = t.drive("image_ready poster.png\nexit")
  assert_true(logs.iter().any(fn(line) { line.has_prefix("DRIVE FAIL") && line.contains("more than one picture") }), msg=logs.join("\n"))
  let logs = t.drive("image_ready one/poster.png\nexit")
  assert_true(logs.iter().any(fn(line) { line == "DRIVE PASS" }), msg=logs.join("\n"))
}
