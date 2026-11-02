// Absolute Windows paths identify the same favorite regardless of separators or case.

///|
test "a Windows folder is named by its final path component" {
  assert_eq(@sfbase.dv_name("C:\\Users\\Lin\\项目"), "项目")
  assert_eq(@sfbase.dv_name("\\\\Studio\\Files\\项目"), "项目")
  assert_eq(@sfbase.dv_name("/Users/lin/a\\b"), "a\\b")
}

///|
test "a Windows folder has one favorite regardless of path spelling" {
  let f : @sfdesk.Favorite = { station: "ws1/st1", root: "C:\\Users\\Lin", path: "项目", name: "项目" }
  assert_true(@sfdesk.favorite_has([f], "ws1/st1", "c:/users/lin/项目", ""))
}

///|
test "a backslash at the end of a Unix folder's name keeps favorites distinct" {
  let f : @sfdesk.Favorite = { station: "ws1/st1", root: "/Users/lin/project\\", path: "notes", name: "notes" }
  assert_true(@sfdesk.favorite_has([f], "ws1/st1", "/Users/lin/project\\/notes", ""))
  assert_false(@sfdesk.favorite_has([f], "ws1/st1", "/Users/lin/project", "notes"))
}

///|
test "a Unix folder's title keeps a trailing backslash" {
  let st = @sfbase.dv_station({ "station": "ws1/st1", "overview": { "drive": { "anywhere": true, "home": "/Users/lin" } } })
  let at : @sfbase.DriveAt = { station: "ws1/st1", root: Some("/Users/lin/project\\"), path: "" }
  assert_eq(@sfdesk.folder_name(st, at), "project\\")
}
