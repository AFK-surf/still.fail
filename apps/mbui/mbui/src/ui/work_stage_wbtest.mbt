///|
test "a frame and nested events leave no stale work phase after returning" {
  let built : Array[Int] = []
  let t = Tester::new(fn(c) {
    built.push(fake.val.unwrap().work_stage)
    c.text("stage") |> ignore
  })
  t.frame()
  assert_true(built.contains(@hostapi.work_build), msg=built.to_string())
  assert_eq(t.fake.work_stage, 0)
  let seen : Array[Int] = []
  view_event(fn() {
    seen.push(t.fake.work_stage)
    view_event(fn() { seen.push(t.fake.work_stage) })
    seen.push(t.fake.work_stage)
  })
  assert_eq(seen, [@hostapi.work_event, @hostapi.work_event, @hostapi.work_event])
  assert_eq(t.fake.work_stage, 0)
  t.frame()
  assert_eq(t.fake.work_stage, 0)
}
