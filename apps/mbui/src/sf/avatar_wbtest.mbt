///|
test "a person's colour as Android's avatarColor picks it: Java's hashCode of their id lowered, floorMod" {
  // "a": 97, the second
  assert_eq(avatar_color("a"), 0x2F8F5BFFL)
  assert_eq(avatar_color("A"), avatar_color("a"))
  // Java's int wraps to -2147483648 here: floorMod 6 is 4, the fifth
  assert_eq(avatar_color("polygenelubricants"), 0x3F8C99FFL)
}

///|
test "a name's initial: its first letter upper case, ? for none" {
  assert_eq(initial("  lin"), "L")
  assert_eq(initial("林"), "林")
  assert_eq(initial(" "), "?")
}

///|
test "a person's picture: their initial while it decodes, then the picture whole at once; the initial for good when it cannot be decoded" {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(fn() { avatar(c, "lin@example.com", "lin", "lin.jpg", 18.0) }) |> ignore
      c.box(fn() { avatar(c, "mo@example.com", "mo", "mo.jpg", 18.0) }) |> ignore
    },
    images=[("lin.jpg", 96, 96), ("mo.jpg", 96, 96)],
    finish=false,
  )
  // each decoded at the size it is shown: 18 at 2x, 64
  assert_eq(t.image_loads(), [("lin.jpg", 64), ("mo.jpg", 64)])
  assert_true(t.find("L") is Some(_))
  assert_true(t.find("M") is Some(_))
  assert_eq(t.drawn_images().length(), 0)
  let decoding = t.pending()
  assert_eq(decoding.length(), 2)
  t.finish(1, decoding[0].1)
  t.finish(1, decoding[1].1, ok=false)
  t.frame()
  // Lin's: the picture, not faded in (Compose draws the bitmap it was handed), the letter gone
  let shown = t.drawn_images()
  assert_eq(shown.length(), 1)
  assert_eq((shown[0][2], shown[0][3], shown[0][8]), (18.0, 18.0, 1.0))
  assert_true(t.find("L") is None)
  // Mo's could not be: their initial still
  assert_true(t.find("M") is Some(_))
}
