///|
test "stable_hash: FNV-1a over UTF-8, the same constants on every target and in every run" {
  // (Python's: h = 0xcbf29ce484222325; for b in s.encode(): h = ((h ^ b) * 0x100000001b3) % 2**64, signed)
  assert_eq(@ui.stable_hash(""), -3750763034362895579L)
  assert_eq(@ui.stable_hash("a"), -5808556873153909620L)
  assert_eq(@ui.stable_hash("foobar"), -8821353812377114648L)
  assert_eq(@ui.stable_hash("端到端测试"), -6671401052097675784L)
  assert_eq(@ui.stable_hash("e2e-photo.jpg"), 6392625609610872309L)
  assert_eq(@ui.stable_hash("😀"), -72331129952009592L)
  assert_eq(@ui.stable_hash_bytes(b"foobar"), -8821353812377114648L)
  assert_eq(@ui.stable_hash_bytes(b""), -3750763034362895579L)
}
