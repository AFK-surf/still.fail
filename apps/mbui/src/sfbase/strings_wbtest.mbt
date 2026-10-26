// The app's words: a count's, and every key in both languages (scripts/strings writes both from the catalog).

///|
test "a count's words: one, and more than one" {
  @sf.set_language(Some("en"))
  assert_eq(fill("web-pages.drive.trashed", [("n", "1")]), "Moved to the station's Trash")
  assert_eq(fill("web-pages.drive.trashed", [("n", "3")]), "3 items moved to the station's Trash")
  @sf.set_language(None)
}

///|
test "every key the app says has its words in Chinese and in English (scripts/strings)" {
  let lacking = []
  for k, _ in zh {
    if !en.contains(k) {
      lacking.push(k)
    }
  }
  for k, _ in en {
    if !zh.contains(k) {
      lacking.push(k)
    }
  }
  assert_eq(lacking, [])
}
