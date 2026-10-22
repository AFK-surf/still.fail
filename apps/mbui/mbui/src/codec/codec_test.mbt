// Base64, hex, a link's parts, text's bytes, CSV and JSON written out: each against what JavaScript, RFC 4648 and
// RFC 4180 say of the same.

///|
test "base64 written and read back, both alphabets" {
  assert_eq(@codec.base64(b""), "")
  assert_eq(@codec.base64(b"f"), "Zg==")
  assert_eq(@codec.base64(b"fo"), "Zm8=")
  assert_eq(@codec.base64(b"foo"), "Zm9v")
  assert_eq(@codec.base64(b"foobar"), "Zm9vYmFy")
  assert_eq(@codec.from_base64("Zm9vYmFy"), b"foobar")
  assert_eq(@codec.from_base64("Zm9v\nYmFy=="), b"foobar")
  // URL-safe: - and _ for + and /
  assert_eq(@codec.base64(b"\xfb\xff"), "+/8=")
  assert_eq(@codec.from_base64("-_8"), b"\xfb\xff")
  assert_eq(@codec.from_base64("+/8="), b"\xfb\xff")
}

///|
test "base64 read exactly: padding and white space passed over, anything else refused" {
  assert_eq(@codec.from_base64_exact("Zm9v\r\nYmFy"), Some(b"foobar"))
  assert_eq(@codec.from_base64_exact("Zm8="), Some(b"fo"))
  assert_eq(@codec.from_base64_exact("-_8"), None)
  assert_eq(@codec.from_base64_exact("Zm9v!"), None)
}

///|
test "hex" {
  assert_eq(@codec.hex(b"\x00\x9f\xff"), "009fff")
  assert_eq(@codec.from_hex("009fFF"), b"\x00\x9f\xff")
  assert_eq(@codec.from_hex("abc"), b"\xab")
}

///|
test "a link's part as encodeURIComponent and decodeURIComponent have it" {
  assert_eq(@codec.encode_uri_component("a b/会?x=1&y=(2)"), "a%20b%2F%E4%BC%9A%3Fx%3D1%26y%3D(2)")
  assert_eq(@codec.decode_uri_component("a%20b%2F%E4%BC%9A"), Some("a b/会"))
  assert_eq(@codec.decode_uri_component("100%"), None)
  assert_eq(@codec.decode_uri_component("%zz"), None)
  assert_eq(@codec.decode_uri_component("%E4%BC"), None)
  // leniently: what makes no character kept as written
  assert_eq(@codec.percent_decoded("50%25 off %zz"), "50% off %zz")
  assert_eq(@codec.percent_decoded("%E4%BC"), "%E4%BC")
  assert_eq(@codec.percent_decoded("plain"), "plain")
}

///|
test "text's bytes" {
  assert_true(@codec.looks_like_text(@utf8.encode("纯文本 plain")))
  assert_true(!@codec.looks_like_text(b"\x00\x01\x02"))
  assert_true(!@codec.looks_like_text(b"\xff\xfe"))
  assert_eq(@codec.utf8_text(@utf8.encode("会议"), 100), "会议")
  // a character the cut splits, and a byte of none
  assert_eq(@codec.utf8_text(@utf8.encode("会议"), 4), "会\u{FFFD}")
  assert_eq(@codec.utf8_text(b"a\xffb", 100), "a\u{FFFD}b")
  let half = @utf8.encode("ab会")
  assert_eq(@codec.utf8_end(half, 0, 4, true), 2)
  assert_eq(@codec.utf8_end(half, 0, 4, false), 4)
  assert_eq(@codec.utf8_end(half, 0, 5, true), 5)
  assert_eq(@codec.utf16_text(b"\xff\xfea\x00\x1aO", 2, true), "a会")
  assert_eq(@codec.utf16_text(b"\x00a\x4f\x1a\xd8\x00", 0, false), "a会\u{FFFD}")
}

///|
test "CSV and TSV" {
  let rows = @codec.parse_csv("a,\"b,c\",\"d \"\"e\"\"\"\r\n1,2\n\n3", ',', 10)
  assert_eq(rows, [["a", "b,c", "d \"e\""], ["1", "2"], [""], ["3"]])
  assert_eq(@codec.parse_csv("x\ty\n1\t2\n3\t4", '\t', 2), [["x", "y"], ["1", "2"]])
}

///|
test "JSON written out" {
  let v : Json = { "a": 1, "b": [true, null], "c": {}, "d": [] }
  assert_eq(@codec.pretty_json(v), "{\n  \"a\": 1,\n  \"b\": [\n    true,\n    null\n  ],\n  \"c\": {},\n  \"d\": []\n}")
}
