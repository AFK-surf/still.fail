// Runs the generated conformance cases (see scripts/gen_unicode.py): each
// line of `cases` is a string of code points in hex, each preceded by '/'
// (a boundary) or '.' (none), with the end of text's mark last.

///|
fn hex_digit(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 70 {
    c - 55
  } else {
    c - 87
  }
}

///|
/// One case: the text, the offsets of its boundaries, and a readable form.
fn parse_case(line : String) -> (String, Array[Int], String) {
  let sb = StringBuilder()
  let marks = []
  let shown = StringBuilder()
  let mut off = 0
  let mut i = 0
  let n = line.length()
  while i < n {
    let m = line.at(i).to_int()
    i = i + 1
    if m == 47 {
      marks.push(off)
      shown.write_string("÷ ")
    } else {
      shown.write_string("× ")
    }
    if i >= n {
      break
    }
    let mut cp = 0
    let start = i
    while i < n && line.at(i).to_int() != 47 && line.at(i).to_int() != 46 {
      cp = cp * 16 + hex_digit(line.at(i).to_int())
      i = i + 1
    }
    shown.write_string(line.unsafe_substring(start~, end=i))
    shown.write_string(" ")
    sb.write_char(cp.unsafe_to_char())
    off = off + (if cp >= 0x10000 { 2 } else { 1 })
  }
  (sb.to_string(), marks, shown.to_string())
}

///|
fn show(xs : Array[Int]) -> String {
  xs.map(fn(x) { x.to_string() }).join(",")
}

///|
fn run_conformance(name : String, chunks : Array[String]) -> Unit raise {
  let mut total = 0
  let mut fails = 0
  for chunk in chunks {
    for line in chunk.split("\n") {
      let line = line.to_owned()
      if line.length() == 0 {
        continue
      }
      total = total + 1
      let (s, expected, shown) = parse_case(line)
      let (got, got2) = if name == "grapheme" {
        // forwards, and backwards from the end
        let back = []
        let mut i = s.length()
        back.push(i)
        while i > 0 {
          i = @text.prev_grapheme(s, i)
          back.push(i)
        }
        back.rev_in_place()
        (@text.graphemes(s), back)
      } else {
        let b = @text.break_opportunities(s).map(fn(p) { p.0 })
        (b, b)
      }
      let expected = if name == "grapheme" {
        expected
      } else {
        expected.filter(fn(x) { x > 0 })
      }
      if got != expected || got2 != expected {
        fails = fails + 1
        if fails <= 30 {
          println(
            "\{name} case \{total}: \{shown}: expected \{show(expected)}, got \{show(got)} / \{show(got2)}",
          )
        }
      }
    }
  }
  println(
    "\{name} conformance (Unicode \{@text.unicode_version}): \{total - fails}/\{total} pass",
  )
  assert_eq(fails, 0)
}

///|
test "grapheme API" {
  let s = "e\u{301}👩\u{200D}👩\u{200D}👧🇨🇳🇯"
  assert_eq(@text.graphemes(s), [0, 2, 10, 14, 16])
  assert_eq(@text.next_grapheme(s, 2), 10)
  // from inside a cluster, back to its start
  assert_eq(@text.prev_grapheme(s, 5), 2)
  assert_eq(@text.prev_grapheme(s, 16), 14)
  assert_eq(@text.prev_grapheme(s, 0), 0)
  assert_eq(@text.graphemes(""), [])
  // GB9c: Devanagari KA + VIRAMA + SSA is one cluster
  assert_eq(@text.graphemes("\u{915}\u{94D}\u{937}"), [0, 3])
}

///|
test "line break API" {
  let s = "Hello, world (test).\n你好，世界。"
  let b = @text.break_opportunities(s)
  assert_eq(b, [
    (7, false),
    (13, false),
    (21, true),
    (22, false),
    (24, false),
    (25, false),
    (27, true),
  ])
}
