///|
test "recording paths do not include the recording machine's directories" {
  let text = #|{"env":{"MBUI_DOWNLOADS_DIR":"/Users/example/work/repo/apps/mbui/out/downloads"},"in":{"path":"/Users/example/work/repo/apps/e2e-local/file","home":"/Users/example/other/file"}}
  let expected = #|{"env":{"MBUI_DOWNLOADS_DIR":"/test-worktree/apps/mbui/out/downloads"},"in":{"path":"/test-worktree/apps/e2e-local/file","home":"/test-home/other/file"}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/work/repo", "/Users/example")
  assert_eq(compact(out), expected)
}
