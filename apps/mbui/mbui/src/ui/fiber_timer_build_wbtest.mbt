// A fiber's timer come: the fiber runs as the frame begins, and the frame builds again what reads what it changed,
// nothing for a change nothing read (a fiber's moment is no moment the build waits for).

///|
test "a fiber's timer come: the old frame built for none of what nothing read, built for what it read" {
  let unread = @signals.signal(0)
  let read = @signals.signal(0)
  let t = Tester::new(fn(c) { c.text("n \{read.get()}", size=12.0) |> ignore })
  t.draw()
  t.run_for(100.0)
  runtime().after(500, fn() { unread.set(1) })
  runtime().after(1000, fn() { read.set(1) })
  t.record_host()
  t.run_as_host(700.0)
  assert_eq(unread.get(), 1)
  let built = t.host_frames().filter(fn(f) { f.old_built }).map(fn(f) { "\{f.at}: \{f.why}" })
  assert_eq(built, [])
  t.record_host()
  t.run_as_host(500.0)
  assert_true(t.host_frames().any(fn(f) { f.old_built }))
  assert_true(t.find("n 1") is Some(_))
}
