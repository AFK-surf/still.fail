// A path in an agent's words is only opened once the station confirms it is a file.

///|
test "a named path opens only after it is found, never for a missing path or directory" {
  @sfbase.reset()
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let asked : Array[Json] = []
  let names : Array[String] = []
  let src = @sfbase.made_source(call=fn(name, params, done) {
    names.push(name)
    asked.push(params)
    answers.push(done)
  })
  open_named(src, "ws/st", "session", "src/a.ts")
  assert_true(@sfbase.viewer.get() is None, msg="nothing opens while the station is checking")
  assert_eq(names, ["file.peek"])
  assert_eq(asked[0], { "station": "ws/st", "key": "session", "path": "src/a.ts" })
  (answers[0])(Err({ "code": "not_found", "message": "missing" }))
  assert_true(@sfbase.viewer.get() is None, msg="a missing file does not open")
  open_named(src, "ws/st", "session", "src/a.ts")
  (answers[1])(Ok({ "kind": "dir" }))
  assert_true(@sfbase.viewer.get() is None, msg="a directory without a trailing slash does not open")
  open_named(src, "ws/st", "session", "src/a.ts")
  (answers[2])(Ok({ "kind": "text" }))
  let viewer = @sfbase.viewer.get().unwrap()
  assert_true(viewer.named)
  assert_eq(viewer.file.path, "src/a.ts")
}

///|
test "an old file check cannot open after a newer path was chosen" {
  @sfbase.reset()
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let src = @sfbase.made_source(call=fn(_, _, done) { answers.push(done) })
  open_named(src, "ws/st", "session", "first.ts")
  open_named(src, "ws/st", "session", "missing.ts")
  (answers[1])(Err({ "code": "not_found", "message": "missing" }))
  (answers[0])(Ok({ "kind": "text" }))
  assert_true(@sfbase.viewer.get() is None)
}
