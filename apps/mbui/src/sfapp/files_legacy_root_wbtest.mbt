// An old station can still list its configured folders, without offering a second kind of shortcut to manage.

///|
test "a station without a home still opens its folders without a pin management action" {
  let t = drive_tester("drive-roots")
  assert_true(t.find("文档") is Some(_), msg="the old folder remains reachable")
  for label in ["管理 pin 的文件夹", "管理文件夹", "Pin 文件夹"] {
    assert_true(t.all(Button, label~).is_empty(), msg=label)
  }
}
