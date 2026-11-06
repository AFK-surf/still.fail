// The same model ordering and filtering feed both panel implementations.

///|
fn triple_models_fixture() -> Json {
  {
    "options": [
      { "model": "alpha", "name": "Alpha", "ids": ["vendor/a-1"], "family": "A", "maker": { "id": "one" } },
      { "model": "beta", "name": "Beta", "ids": ["vendor/b-2"], "family": "B", "maker": { "id": "two" } },
      { "model": "beta-small", "name": "Beta Small", "ids": ["vendor/b-3"], "family": "B", "maker": { "id": "two" } },
    ],
    "makers": [{ "id": "one" }, { "id": "two" }],
    "near": ["beta", "missing", "alpha"],
    "liked": ["beta-small"],
    "option": "beta",
  }
}

///|
test "model panel: recent and liked models follow the core and selected maker" {
  let v = Some(triple_models_fixture())
  let m = triple_models(v, "", false, "", true)
  assert_false(m.all)
  assert_false(m.kind_open)
  assert_eq(m.kind, "two")
  assert_eq(m.near.map(fn(o) { text(Some(o), "model") }), ["beta", "alpha"])
  assert_eq(m.liked.map(fn(o) { text(Some(o), "model") }), ["beta-small"])
  assert_eq(m.series.length(), 1)
  assert_eq(m.series[0].0, "B")
  assert_eq(m.series[0].1.length(), 2)
  let another = triple_models(v, "", true, "one", false)
  assert_true(another.all)
  assert_true(another.kind_open)
  assert_eq(another.series[0].0, "A")
}

///|
test "model panel: search matches aliases across makers" {
  let m = triple_models(Some(triple_models_fixture()), " B-3 ", false, "one", true)
  assert_true(m.searching)
  assert_true(m.all)
  assert_eq(m.listed.map(fn(o) { text(Some(o), "model") }), ["beta-small"])
  assert_eq(m.series[0].1.map(fn(o) { text(Some(o), "model") }), ["beta-small"])
}
