///|
test "recording paths do not include the recording machine's directories" {
  let text = #|{"env":{"MBUI_DOWNLOADS_DIR":"/Users/example/work/repo/apps/mbui/out/downloads"},"in":{"path":"/Users/example/work/repo/apps/e2e-local/file","home":"/Users/example/other/file"}}
  let expected = #|{"env":{"MBUI_DOWNLOADS_DIR":"/test-worktree/apps/mbui/out/downloads"},"in":{"path":"/test-worktree/apps/e2e-local/file","home":"/test-home/other/file"}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/work/repo", "", "/Users/example", "", "", "", "", [], [])
  assert_eq(compact(out), expected)
}

///|
test "recording paths hide the separate test work directory in update notes" {
  let text = #|{"in":{"value":[{"overview":{"updates":[{"note":"Installed in /Users/example/private-run/station/agent, update manually"}]}}]}}
  let expected = #|{"in":{"value":[{"overview":{"updates":[{"note":"Installed in /test-e2e/station/agent, update manually"}]}}]}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/repo", "/Users/example/private-run", "/Users/example", "", "", "", "", [], [])
  assert_eq(compact(out), expected)
}

///|
test "recording paths hide sibling directories in the private checkout parent" {
  let text = #|{"in":{"value":{"command":"serve /Users/example/private-run/tools/server","text":"at /Users/example/private-run/results"}}}
  let expected = #|{"in":{"value":{"command":"serve /test-workspace/tools/server","text":"at /test-workspace/results"}}}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/private-run/repo", "/Users/example/private-run/e2e", "/Users/example", "", "", "", "", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a checkout directly under home does not turn home into a workspace" {
  let text = #|{"path":"/Users/example/other/file"}
  let expected = #|{"path":"/test-home/other/file"}
  let input = parse(text).unwrap()
  let out = recording_paths(input, "/Users/example/repo", "", "/Users/example", "", "", "", "", [], [])
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
  assert_true(recording_text(shape, "/Users/example/repo", "", "/Users/example", "", "", "", "", [], []) is None)
  assert_true(recording_text(key, "/Users/example/repo", "", "/Users/example", "", "", "", "", [], []) is None)
  assert_eq(compact(recording_text(ordinary, "/Users/example/repo", "", "/Users/example", "", "", "", "", [], []).unwrap()), compact(ordinary))
  let picture = parse(picture_text).unwrap()
  assert_eq(compact(recording_text(picture, "/Users/example/repo", "", "/Users/example", "", "", "", "", [], []).unwrap()), picture_expected)
}

///|
test "a station through a work symlink and the real work directory keep the same paths" {
  let text = #|{"paths":["/tmp/short/work/s/home","/Users/example/run/s/home","/tmp/short/work/other"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home","/test-e2e/other"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/repo", "/Users/example/run", "/Users/example", "/tmp/short/work/s", "/tmp/short/work", "", "/Users/example/run/s", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a work directory inside the checkout maps its real path and short alias alike" {
  let text = #|{"paths":["/Users/example/repo/apps/e2e-local/s/home","/tmp/short/work/s/home","/Users/example/repo/other"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home","/test-worktree/other"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/repo", "/Users/example/repo/apps/e2e-local", "/Users/example", "/tmp/short/work/s", "/tmp/short/work", "", "/Users/example/repo/apps/e2e-local/s", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a checkout inside work keeps its more specific name" {
  let text = #|{"paths":["/Users/example/run/repo/file","/Users/example/run/other","/tmp/short/work/repo/file","/Users/example/run/repo/s/home","/tmp/short/work/repo/s/home"]}
  let expected = #|{"paths":["/test-worktree/file","/test-e2e/other","/test-worktree/file","/test-station/home","/test-station/home"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/run/repo", "/Users/example/run", "/Users/example", "/tmp/short/work/repo/s", "/tmp/short/work", "", "/Users/example/run/repo/s", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a station parent link into work and a work link use the physical path's identity" {
  let text = #|{"paths":["/tmp/work-link/sub/s/home","/tmp/station-parent/s/home","/Users/example/run/sub/s/home"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home","/test-station/home"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/repo", "/tmp/work-link", "/Users/example", "/tmp/station-parent/s", "", "/Users/example/run", "/Users/example/run/sub/s", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a physical checkout under a work link has the same name through each work spelling" {
  let text = #|{"paths":["/Users/example/run/repo/s/home","/tmp/work-link/repo/s/home","/tmp/station-parent/s/home"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home","/test-station/home"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/run/repo", "/tmp/work-link", "/Users/example", "/tmp/station-parent/s", "", "/Users/example/run", "/Users/example/run/repo/s", [], [])
  assert_eq(compact(out), expected)
}

///|
test "a station below the private checkout parent does not retain its local directory name" {
  let text = #|{"paths":["/Users/example/session/station-name/home","/Users/example/session/other"]}
  let expected = #|{"paths":["/test-station/home","/test-workspace/other"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/session/repo", "/Users/example/run", "/Users/example", "/Users/example/session/station-name", "", "", "/Users/example/session/station-name", [], [])
  assert_eq(compact(out), expected)
}

///|
test "intermediate work link spellings also give the station one name" {
  let text = #|{"paths":["/tmp/work-link/s/home","/var/run-place/s/home","/private/var/run-place/s/home"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home","/test-station/home"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/repo", "/tmp/work-link", "/Users/example", "/tmp/work-link/s", "", "/private/var/run-place", "/private/var/run-place/s", ["/var/run-place"], [])
  assert_eq(compact(out), expected)
}

///|
test "a path with dot segments and its normalized spelling are both hidden" {
  let text = #|{"paths":["/tmp/run/unused/../station/home","/tmp/run/station/home"]}
  let expected = #|{"paths":["/test-station/home","/test-station/home"]}
  let out = recording_paths(parse(text).unwrap(), "/Users/example/repo", "/tmp/run", "/Users/example", "/tmp/run/station", "", "/tmp/run", "/tmp/run/station", [], ["/tmp/run/unused/../station"])
  assert_eq(compact(out), expected)
}

///|
test "an independent station path is hidden and a changed text shape is not kept" {
  let text = #|{"path":"/tmp/mbui-e2e-123/s/home"}
  let expected = #|{"path":"/test-station/s/home"}
  let station = "/tmp/mbui-e2e-123"
  assert_eq(compact(recording_paths(parse(text).unwrap(), "/Users/example/repo", "/Users/example/run", "/Users/example", station, "", "", "", [], [])), expected)
  let shape_text = #|{"s":[13,400,0,"/tmp/mbui-e2e-123/home"],"r":[0,1,7]}
  let shape = parse(shape_text).unwrap()
  assert_true(recording_text(shape, "/Users/example/repo", "/Users/example/run", "/Users/example", station, "", "", "", [], []) is None)
}
