///|
test "what a value weighs is its JSON's bytes; its heaviest paths, a list's items as one, with what is under each" {
  let v : Json = {
    "me": { "id": "u1" },
    "days": [
      { "label": "今天", "items": [{ "id": "a", "people": [{ "name": "Lina" }, { "name": "小王" }] }, { "id": "b", "people": [] }] },
      { "label": "昨天", "items": [{ "id": "c", "people": [{ "name": "Lina" }] }] },
    ],
  }
  let (n, paths) = @core.weights(v)
  // (as its text is long in UTF-8)
  let text = v.stringify()
  let mut bytes = 0
  for ch in text {
    let u = ch.to_int()
    bytes += if u < 0x80 { 1 } else if u < 0x800 { 2 } else if u < 0x10000 { 3 } else { 4 }
  }
  assert_eq(n, bytes)
  let by : Map[String, Int] = Map([])
  for p in paths {
    by[p.0] = p.1
  }
  // a path has what is under it: the days all but `me` and the braces
  assert_eq(by.get("days").unwrap() + by.get("me").unwrap() + "{\"me\":,\"days\":}".length(), n)
  assert_true(by.get("days").unwrap() > by.get("days[].items").unwrap())
  assert_true(by.get("days[].items").unwrap() > by.get("days[].items[].people").unwrap())
  // the three lists of people, their items' names: `[{"name":"Lina"},{"name":"小王"}]`, `[]`, `[{"name":"Lina"}]`
  assert_eq(by.get("days[].items[].people").unwrap(), 35 + 2 + 17)
  assert_eq(by.get("days[].items[].people[].name").unwrap(), 6 + 8 + 6)
  // the heaviest first
  assert_eq(paths[0].0, "days")
  // no more than asked
  assert_eq(@core.weights(v, most=2).1.map(fn(p) { p.0 }), ["days", "days[].items"])
}

///|
test "weights: a key that is no field's name is one of a map's, never said" {
  let v : Json = {
    "byStation": { "ws-1/a1b2": { "name": "Maple", "running": 2 }, "ws-1/c3d4": { "name": "Willow", "running": 0 } },
    "time": { "lastActiveAt": { "ago": "3 分钟前" } },
  }
  let (_, paths) = @core.weights(v)
  let names = paths.map(fn(p) { p.0 })
  assert_true(names.contains("byStation{}"))
  assert_true(names.contains("byStation{}.name"))
  assert_true(names.contains("time.lastActiveAt.ago"))
  assert_false(names.iter().any(fn(p) { p.contains("ws-1") || p.contains("a1b2") }))
}

///|
test "weights: no deeper than four fields" {
  let v : Json = { "a": { "b": { "c": { "d": { "e": { "f": 1 } } } } } }
  assert_eq(@core.weights(v).1.map(fn(p) { p.0 }), ["a", "a.b", "a.b.c", "a.b.c.d"])
}
