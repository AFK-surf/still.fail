// A quote's own file shown in its card, not among its message's files (Chat.tsx fileOf, besideQuotes).

///|
test "a message's quote naming one of its files: that file in the quote's card, the rest as they were" {
  let a = fn(name : String) -> Attachment {
    { name, path: "/w/" + name, size: 1.0, width: 0.0, height: 0.0, thumbhash: "", owner: "", upload: "", duration: 0.0, frames: 0, held: false }
  }
  let files = [a("shot.png"), a("notes.txt")]
  let quotes : Array[Quote] = [
    { author: "你", text: "shot.png", comment: "", ts: "1", role: "person", file: "shot.png" },
    { author: "Ana", text: "一段话", comment: "", ts: "2", role: "person", file: "" },
  ]
  assert_eq(beside_quotes(quotes, files).map(fn(x) { x.name }), ["notes.txt"])
  assert_eq(quote_file(quotes[0], files).map(fn(x) { x.name }), Some("shot.png"))
  assert_true(quote_file(quotes[1], files) is None)
  // none naming a file: all of them
  assert_eq(beside_quotes([quotes[1]], files).length(), 2)
}
