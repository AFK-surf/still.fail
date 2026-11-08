///|
test "what comes or goes by its size: unseen at half of it or less, whole at its size" {
  assert_eq(@sf.seen_at(0.0), 0.0)
  assert_eq(@sf.seen_at(0.4), 0.0)
  assert_eq(@sf.seen_at(0.5), 0.0)
  assert_eq(@sf.seen_at(0.75), 0.5)
  assert_eq(@sf.seen_at(1.0), 1.0)
  assert_eq(@sf.seen_at(1.3), 1.0)
}
