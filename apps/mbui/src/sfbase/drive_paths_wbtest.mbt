///|
test "a Unix folder ending in a backslash keeps that character" {
  assert_eq(dv_absolute("/Users/lin/project\\", "notes"), "/Users/lin/project\\/notes")
  assert_eq(dv_root_label([], "/Users/lin/project\\"), "project\\")
}

///|
test "a Windows folder's trailing backslash remains a separator" {
  assert_eq(dv_absolute("C:\\Users\\Lin\\", "notes"), "C:\\Users\\Lin/notes")
  assert_eq(dv_root_label([], "C:\\Users\\Lin\\"), "Lin")
}
