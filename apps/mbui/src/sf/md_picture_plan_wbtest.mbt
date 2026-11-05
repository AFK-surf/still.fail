// A message's picture owner plans the same rooms that Markdown gives its pictures.

///|
test "placed pictures use their rows and table cells, not the whole message's width" {
  let tree : Json = [
    ["p", [["img", { "src": "a.png" }], ["img", { "src": "b.png" }], ["img", { "src": "c.png" }]]],
    ["table", [
      ["tr", [["th", ["one"]], ["th", ["two"]]]],
      ["tr", [["td", [["img", { "src": "a.png" }]]], ["td", [["img", { "src": "c.png" }]]]]],
    ]],
  ]
  let ratio = fn(name : String) -> Double? {
    match name { "a.png" => Some(2.0); "b.png" => Some(1.0); "c.png" => Some(0.5); _ => None }
  }
  assert_eq(
    md_picture_places("picture-plan", Some(tree), 300.0, 14.0, ratio, fn(name) { ratio(name) is Some(_) }),
    [("a.png", 300.0, true), ("b.png", 194.0, true), ("c.png", 97.0, true),
     ("a.png", 160.0, true), ("c.png", 120.0, true)],
  )
}

///|
test "a quoted single image uses its narrower room; a mixed table cell is words" {
  let tree : Json = [
    ["quote", [["p", [["img", { "src": "a.png" }]]]]],
    ["table", [["tr", [["td", ["caption", ["img", { "src": "a.png" }]]]]]]],
  ]
  let ratio = fn(name : String) -> Double? { if name == "a.png" { Some(2.0) } else { None } }
  assert_eq(md_picture_places("quoted-picture-plan", Some(tree), 300.0, 14.0, ratio, fn(name) { ratio(name) is Some(_) }), [("a.png", 288.0, false)])
}
