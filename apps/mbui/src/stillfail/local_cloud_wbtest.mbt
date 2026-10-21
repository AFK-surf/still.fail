///|
test "a trace only for a cloud whose host is this machine's" {
  assert_true(local_cloud("http://127.0.0.1:18900"))
  assert_true(local_cloud("http://localhost:8787/"))
  assert_true(local_cloud("http://127.0.0.1"))
  assert_false(local_cloud("http://localhost.example.com"))
  assert_false(local_cloud("http://127.0.0.1.nip.io:18900"))
  assert_false(local_cloud("http://127.0.0.1@cloud.example.com/"))
  assert_false(local_cloud("https://still.fail"))
  assert_false(local_cloud(""))
}
