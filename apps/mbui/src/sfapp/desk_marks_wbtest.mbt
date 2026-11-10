// What was marked for a chat (a service's page, an image viewed: sfbase's marked_into) taken into its desktop
// composer's draft: each picture going up as a file, a quote per mark.

///|
test "desk: a page's marks waiting for the chat go into its composer's draft, each with its quote and what is said of it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.frame()
  marked_into["ws1/st1:s-c1"] = [("首页-标注1-120000.png", b"\x89PNG", [("网页 首页 标注 1", "按钮「发送」", "颜色太浅")], "page")]
  t.frame()
  t.frame()
  assert_true(marked_into.get("ws1/st1:s-c1") is None, msg="taken once")
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  let q = field(Some(quoted[0].params), "quote")
  assert_eq(text(q, "comment"), "颜色太浅")
  assert_eq(text(Some(quoted[0].params), "key"), "ws1/st1:s-c1")
  // its screenshot the quote's own picture, not among the files
  t.frame()
  let w = @sfbase.writings.get("ws1/st1:s-c1").unwrap()
  assert_eq(text(field(Some(w.quotes.get()[0]), "own"), "name"), "首页-标注1-120000.png")
  assert_eq(w.files.get().length(), 0)
}
