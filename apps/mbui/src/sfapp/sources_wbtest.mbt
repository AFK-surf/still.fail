// Where in the source what a screen shows was made (mbui's view/source.mbt, Tester::sources_at): words drawn by the
// window's tree found back to the app's lines that made them, a library's part to the line that asked for it; the
// rules held at once (Tester::audit), each fault naming where what it names was made.

///|
test "sources: a screen's words found back to the app's lines, the library's parts to where they were asked for" {
  let t = screen_in("home", corner_windows[0], "zh")
  // (each line of words the window's tree draws, where its sources are said)
  let said : Array[String] = []
  for w in t.words() {
    let s = t.sources_at(w.1 + w.3 / 2.0, w.2 + w.4 / 2.0)
    if s.contains("node ") {
      said.push(s)
    }
  }
  assert_true(said.length() > 0)
  // (made in the app's pages, or in the library asked for by them)
  assert_true(said.any(fn(s) { s.contains(": made at stillfail/src/") }))
  let asked = said.filter(fn(s) { s.has_prefix("asked for at: stillfail/src/") })
  assert_true(asked.length() > 0)
  // (the innermost node's look said with where each of it was)
  assert_true(said.any(fn(s) { s.contains("\n  box ") && s.contains("(said at stillfail/src/") }))
  println(asked[0])
}

///|
test "sources: a fault a check finds names where the node it names was made" {
  let t = screen_in("home", corner_windows[0], "zh")
  let faults = t.audit()
  for f in faults {
    if f.contains("window's tree") || f.contains("window tree") {
      assert_true(f.contains("made at stillfail/src/") || f.contains("made at mbui/src/"))
    }
  }
}
