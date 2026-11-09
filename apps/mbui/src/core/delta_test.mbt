// The applier against core-ts's own (vectors_test.mbt, made by core/delta-vectors.ts), and a few by hand.

///|
fn check_vector(text : String) -> Unit raise {
  guard @json.parse(text) is Object(v) else { fail("not a vector") }
  guard v.get("ops") is Some(Array(ops)) else { fail("no ops") }
  let old = v.get("old").unwrap()
  let before = old.stringify()
  let got = @core.apply_delta(old, ops)
  assert_eq(got.stringify(), v.get("want").unwrap().stringify())
  // The old value is not changed: a view may still hold it.
  assert_eq(old.stringify(), before)
}

///|
test "set, append and remove at a path, copying only along it" {
  let old : Json = { "a": { "b": [1, 2] }, "c": { "d": true } }
  let ops : Array[Json] = [
    { "path": ["a", "b"], "append": [3] },
    { "path": ["a", "b", 0], "set": "one" },
    { "path": ["c", "d"], "remove": true },
  ]
  let got = @core.apply_delta(old, ops)
  assert_eq(got.stringify(), "{\"a\":{\"b\":[\"one\",2,3]},\"c\":{}}")
  assert_eq(old.stringify(), "{\"a\":{\"b\":[1,2]},\"c\":{\"d\":true}}")
}

///|
test "keyed ops find items by their key" {
  let old : Json = {
    "items": [{ "id": "a", "n": 1 }, { "id": "b", "n": 2 }, { "id": "c", "n": 3 }],
  }
  let ops : Array[Json] = [
    { "path": ["items"], "key": ["id"], "drop": "b" },
    { "path": ["items"], "key": ["id"], "move": "c", "before": "a" },
    { "path": ["items"], "key": ["id"], "put": { "id": "d", "n": 4 }, "before": null },
    {
      "path": ["items"],
      "key": ["id"],
      "patch": "a",
      "ops": [{ "path": ["n"], "set": 10 }],
    },
  ]
  assert_eq(
    @core.apply_delta(old, ops).stringify(),
    "{\"items\":[{\"id\":\"c\",\"n\":3},{\"id\":\"a\",\"n\":10},{\"id\":\"d\",\"n\":4}]}",
  )
}

///|
test "a run of patches on one list is as each applied alone" {
  let old : Json = {
    "days": [
      {
        "daysAgo": 0,
        "items": [
          { "station": "s", "id": "a", "n": 1 },
          { "station": "s", "id": "b", "n": 2 },
          { "station": "s", "id": "b", "n": 3 },
          { "station": "t", "id": "a", "n": 4 },
        ],
      },
    ],
  }
  let key : Json = ["station", "id"]
  let patch = fn(k : Json, ops : Json) -> Json {
    { "path": ["items"], "key": key, "patch": k, "ops": ops }
  }
  let inner : Array[Json] = [
    patch(["s", "b"], [{ "path": ["n"], "set": 20 }]),
    patch(["t", "a"], [{ "path": ["id"], "set": "b" }]),
    patch(["s", "missing"], [{ "path": ["n"], "set": 0 }]),
    patch(["t", "b"], [{ "path": ["n"], "set": 40 }]),
    patch(["s", "a"], [{ "path": ["gone"], "set": true }, { "path": ["n"], "remove": true }]),
  ]
  let ops : Array[Json] = [{ "path": ["days"], "key": ["daysAgo"], "patch": 0, "ops": Json::array(inner) }]
  let one_by_one = inner.fold(init=old, fn(v, op) {
    @core.apply_delta(v, [{ "path": ["days"], "key": ["daysAgo"], "patch": 0, "ops": [op] }])
  })
  let before = old.stringify()
  assert_eq(@core.apply_delta(old, ops).stringify(), one_by_one.stringify())
  assert_eq(
    one_by_one.stringify(),
    "{\"days\":[{\"daysAgo\":0,\"items\":[{\"station\":\"s\",\"id\":\"a\",\"gone\":true},{\"station\":\"s\",\"id\":\"b\",\"n\":20},{\"station\":\"s\",\"id\":\"b\",\"n\":3},{\"station\":\"t\",\"id\":\"b\",\"n\":40}]}]}",
  )
  assert_eq(old.stringify(), before)
}
