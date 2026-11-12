// A scripted run's `answered CALL` where the app's conversation with its core is kept (drive_heard): the core's answer
// counted as it comes, whether the app reads it or not.

///|
test "answered counts the core's answer to a call nobody reads, heard as the conversation is kept, a frame after it" {
  let log = outside_run("timeout 3000\nanswered download.done\nexit", fn(n) {
    if n == 5 {
      drive_heard("{\"out\":{\"id\":7,\"call\":\"download.done\",\"params\":{}},\"w\":1}")
    }
    if n == 20 {
      drive_heard("{\"in\":{\"id\":7,\"ok\":null},\"w\":2}")
    }
  })
  heard_on.val = false
  let ok = log.search_by(fn(l) { l.has_prefix("DRIVE ok answered download.done") })
  assert_true(ok is Some(_), msg=log.join("\n"))
  assert_true(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
}

///|
test "answered waits for that call's answer: none come, another call's answered, the call only sent, it is not so" {
  let log = outside_run("timeout 1000\nanswered download.done\nexit", fn(n) {
    if n == 5 {
      drive_heard("{\"out\":{\"id\":7,\"call\":\"download.done\",\"params\":{}},\"w\":1}")
      drive_heard("{\"out\":{\"id\":8,\"call\":\"paste.info\",\"params\":{}},\"w\":1}")
    }
    if n == 20 {
      drive_heard("{\"in\":{\"id\":8,\"ok\":null},\"w\":2}")
    }
  })
  heard_on.val = false
  assert_false(log.iter().any(fn(l) { l.contains("DRIVE PASS") }), msg=log.join("\n"))
  assert_true(
    log.iter().any(fn(l) { l.contains("DRIVE FAIL") && l.contains("answered download.done") }),
    msg=log.join("\n"),
  )
}
