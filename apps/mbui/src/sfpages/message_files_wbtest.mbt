///|
test "a chat attachment uses its stored filename on Windows and Unix" {
  let name = "2026-11-14T04-39-37-effdf0-报告.mp4"
  for path in ["C:\\Users\\lin\\uploads\\" + name, "/Users/lin/uploads/" + name, name] {
    assert_eq(stored_name(path), name)
    assert_eq(@sfbase.base_name(path), name)
    assert_eq(@sfbase.viz_base_name(path), name)
  }
  assert_eq(@sfbase.base_name("/Users/lin/a\\b.txt"), "a\\b.txt")
}

///|
test "a staged file flies to its message after the station moves it" {
  let staged = "/station/uploads/2026-11-08-12-00-00-123abc-report.txt"
  let sent = "/station/session/uploads/2026-11-08-12-00-00-123abc-report.txt"
  assert_eq(file_flight_key(sent, [sent], [staged]), staged)
  assert_eq(file_flight_key(staged, [staged], [staged]), staged)
  // Windows stations keep the same name when they move it too.
  let win_staged = "C:\\station\\uploads\\2026-11-08-12-00-00-123abc-report.txt"
  let win_sent = "C:\\station\\session\\uploads\\2026-11-08-12-00-00-123abc-report.txt"
  assert_eq(file_flight_key(win_sent, [win_sent], [win_staged]), win_staged)
}

///|
test "a file flight does not guess when the stored name is ambiguous or outside uploads" {
  let staged = "/station/uploads/unique-report.txt"
  let sent = "/station/session/uploads/unique-report.txt"
  let another = "/other/uploads/unique-report.txt"
  assert_eq(file_flight_key(sent, [sent], [staged, another]), sent)
  assert_eq(file_flight_key(sent, [sent, another], [staged]), sent)
  assert_eq(file_flight_key("/other/unique-report.txt", ["/other/unique-report.txt"], [staged]), "/other/unique-report.txt")
  assert_eq(file_flight_key(sent, [sent], ["upload:unique-report.txt"]), sent)
  assert_eq(file_flight_key(sent, [sent], ["quote:0"]), sent)
}

///|
test "a waiting picture is held off the page: a light screenshot's the neutral ground, a photograph's its own colours" {
  let near = fn(got : Byte, want : Double) { (got.to_int().to_double() - want).abs() <= 1.0 }
  for theme in [@ui.Theme::narrow_light(), @ui.Theme::narrow_dark()] {
    let (ground, under) = (theme.neutral, theme.bg)
    let ga = (ground & 0xFFL).to_double() / 255.0
    let of = fn(colour : Int64, c : Int) { ((colour >> (24 - 8 * c)) & 0xFFL).to_double() }
    // (what a picture with no likeness waits on: the ground over the page)
    let plain = fn(c : Int) { of(ground, c) * ga + of(under, c) * (1.0 - ga) }
    let darker = fn(c : Int) { plain(c) <= of(under, c) }
    // the report's adb-chats.png, 780 × 2600: its field one colour, the light page's (246,242,240 on 245,243,239)
    let shot = "PAgCAgBQN4aJy7s3lnBcKvU="
    let field = image_wait_pixels(shot, 10, 32, 0L, under).unwrap()
    let held = image_wait_pixels(shot, 10, 32, ground, under).unwrap()
    assert_eq(held.length(), field.length())
    for i = 0; i < held.length(); i = i + 4 {
      assert_eq(held[i + 3], b'\xFF', msg="alpha at \{i / 4}")
      for c in 0..<3 {
        if darker(c) {
          // (light: all of it the page's colour, so all of it the ground)
          assert_true(near(held[i + c], plain(c)), msg="channel \{c} at \{i / 4}: \{held[i + c]}, \{plain(c)}")
        } else {
          // (dark: lighter than the ground already, its own)
          assert_eq(held[i + c], field[i + c], msg="channel \{c} at \{i / 4}")
        }
      }
    }
    // a photograph (image_wait_wbtest's): each channel its own where that is past the ground, the ground where not,
    // and more than half of it its own
    let photo = "1QcSHQRnh493V4dIh4eXh1h4kJUI"
    let field = image_wait_pixels(photo, 32, 21, 0L, under).unwrap()
    let held = image_wait_pixels(photo, 32, 21, ground, under).unwrap()
    let mut own = 0
    for i = 0; i < held.length(); i = i + 4 {
      assert_eq(held[i + 3], b'\xFF', msg="alpha at \{i / 4}")
      let mut whole = true
      for c in 0..<3 {
        let f = field[i + c].to_int().to_double()
        let past = if darker(c) { f <= plain(c) } else { f >= plain(c) }
        if past {
          assert_eq(held[i + c], field[i + c], msg="channel \{c} at \{i / 4}")
        } else {
          whole = false
          assert_true(near(held[i + c], plain(c)), msg="channel \{c} at \{i / 4}: \{held[i + c]}, \{plain(c)}")
        }
      }
      if whole { own += 1 }
    }
    assert_true(own * 2 > held.length() / 4, msg="a photograph's likeness kept as it is at \{own} of \{held.length() / 4}")
  }
  // what is clear of a picture: the ground itself, translucent as it is
  let theme = @ui.Theme::narrow_light()
  let clear : FixedArray[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  @gallery.held_off(clear, theme.neutral, theme.bg)
  assert_eq(clear, [b'\x32', b'\x2D', b'\x24', b'\x13'])
}
