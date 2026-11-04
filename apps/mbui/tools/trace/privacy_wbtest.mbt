///|
test "recording paths do not include the recording machine's directories" {
  let text = #|{"env":{"MBUI_DOWNLOADS_DIR":"/Users/example/work/repo/apps/mbui/out/downloads"},"in":{"path":"/Users/example/work/repo/apps/e2e-local/file","home":"/Users/example/other/file"}}
  let expected = #|{"env":{"MBUI_DOWNLOADS_DIR":"/test-worktree/apps/mbui/out/downloads"},"in":{"path":"/test-worktree/apps/e2e-local/file","home":"/test-home/other/file"}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/work/repo", "", "/Users/example")
  assert_eq(compact(out), expected)
}

///|
test "recording paths hide the separate test work directory in update notes" {
  let text = #|{"in":{"value":[{"overview":{"updates":[{"note":"Installed in /Users/example/private-run/station/agent, update manually"}]}}]}}
  let expected = #|{"in":{"value":[{"overview":{"updates":[{"note":"Installed in /test-e2e/station/agent, update manually"}]}}]}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/repo", "/Users/example/private-run", "/Users/example")
  assert_eq(compact(out), expected)
}

///|
test "recording paths hide sibling directories in the private checkout parent" {
  let text = #|{"in":{"value":{"command":"serve /Users/example/private-run/tools/server","text":"at /Users/example/private-run/results"}}}
  let expected = #|{"in":{"value":{"command":"serve /test-workspace/tools/server","text":"at /test-workspace/results"}}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/private-run/repo", "/Users/example/private-run/e2e", "/Users/example")
  assert_eq(compact(out), expected)
}

///|
test "a checkout directly under home does not turn home into a workspace" {
  let text = #|{"path":"/Users/example/other/file"}
  let expected = #|{"path":"/test-home/other/file"}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/repo", "", "/Users/example")
  assert_eq(compact(out), expected)
}

///|
test "a recorded text shape or key whose text changes is not kept" {
  let shape_text = #|{"s":[13,400,0,"/Users/example/private/file"],"r":[0,1,7,47,25,1,7,101]}
  let key_text = #|{"k":[13,400,0,"/Users/example/private/file"],"r":42}
  let ordinary_text = #|{"s":[13,400,0,"ordinary words"],"r":[0,1,7,111]}
  let picture_text = #|{"picture":"/Users/example/private/file","r":[640,320]}
  let picture_expected = #|{"picture":"/test-home/private/file","r":[640,320]}
  let shape = parse(shape_text).unwrap()
  let key = parse(key_text).unwrap()
  let ordinary = parse(ordinary_text).unwrap()
  assert_true(recording_text(shape, "/Users/example/repo", "", "/Users/example") is None)
  assert_true(recording_text(key, "/Users/example/repo", "", "/Users/example") is None)
  assert_eq(compact(recording_text(ordinary, "/Users/example/repo", "", "/Users/example").unwrap()), compact(ordinary))
  let picture = parse(picture_text).unwrap()
  assert_eq(compact(recording_text(picture, "/Users/example/repo", "", "/Users/example").unwrap()), picture_expected)
}
