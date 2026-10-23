///|
test "a file's size as the web says it (fileSize.ts)" {
  assert_eq(@sf.file_size(512.0), "512 B")
  assert_eq(@sf.file_size(18432.0), "18 KB")
  assert_eq(@sf.file_size(812000.0), "793 KB")
  assert_eq(@sf.file_size(4.5 * 1048576.0), "4.5 MB")
  assert_eq(@sf.file_size(4.0 * 1048576.0), "4.0 MB")
  assert_eq(@sf.file_size(1.25 * 1073741824.0), "1.25 GB")
}
