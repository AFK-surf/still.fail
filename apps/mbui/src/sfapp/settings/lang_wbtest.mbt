///|
test "every word of the settings' table has its English (scripts/strings)" {
  let lacking = []
  for k in zh.keys() {
    if k.contains(".") && !en.contains(k) {
      lacking.push(k)
    }
  }
  assert_eq(lacking, [])
}
