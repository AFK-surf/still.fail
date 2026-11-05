///|
test "a share card's measured width does not escape its hosted view" {
  let t = screen_in("share-card-senren-chibi", ("tablet", 840.0, 900.0, 2, "expanded"), "en")
  assert_eq(t.squeeze_faults(), [])
}
