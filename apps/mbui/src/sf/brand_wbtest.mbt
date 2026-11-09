///|
test "another product's words say its name, still.fail's hosts kept" {
  set_product("monoid")
  assert_eq(
    branded("still.fail cloud 在 app.still.fail，装 still.fail.app 或 https://still.fail/en；用 still.fail。"),
    "monoid cloud 在 app.still.fail，装 still.fail.app 或 https://still.fail/en；用 monoid。",
  )
  assert_eq(branded("noreply@still.fail (still.fail)"), "noreply@still.fail (monoid)")
  set_product("still.fail")
  assert_eq(branded("用 still.fail。"), "用 still.fail。")
  set_product("")
}
