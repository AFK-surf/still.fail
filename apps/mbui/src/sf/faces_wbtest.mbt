///|
test "the code face the app carries: JetBrains Mono's file whole (a TrueType font, its size)" {
  let b = @codec.from_base64(code_face_b64)
  // the file as the Android app has it: 300144 bytes, a TrueType font's first four
  assert_eq(b.length(), 300144)
  assert_eq((b[0], b[1], b[2], b[3]), (b'\x00', b'\x01', b'\x00', b'\x00'))
}
