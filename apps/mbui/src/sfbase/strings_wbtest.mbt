// The app's words: a count's, and every key in both languages (scripts/strings writes both from the catalog).

///|
test "a count's words: one, and more than one" {
  @sf.set_language(Some("en"))
  assert_eq(fill("web-pages.drive.trashed", [("n", "1")]), "Moved to the station's Trash")
  assert_eq(fill("web-pages.drive.trashed", [("n", "3")]), "3 items moved to the station's Trash")
  @sf.set_language(None)
}

///|
test "every key the app says has its words in Chinese and in English (scripts/strings); a count's one (`.one`) a language's own, beside its key in both" {
  let lacking = []
  for k, _ in zh {
    if !en.contains(k) {
      lacking.push(k)
    }
  }
  for k, _ in en {
    // (a count's words for one: written where the catalog says them apart (its one and other: English's), its key
    // itself in both; Chinese says one as it says more)
    let base = if k.has_suffix(".one") { Some(k.view(end_offset=k.length() - 4).to_string()) } else { None }
    let one_of_key = match base {
      Some(b) => en.contains(b) && zh.contains(b)
      None => false
    }
    if !zh.contains(k) && !one_of_key {
      lacking.push(k)
    }
  }
  assert_eq(lacking, [])
}
