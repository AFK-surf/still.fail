///|
test "the core's tight nested list retains the nested list after its words" {
  let nodes : Array[Json] = [["list", [["li", ["outer", ["list", [["li", ["inner"]]]]]]]]]
  let blocks = core_blocks(nodes, "")
  guard blocks is [List(l)] else { fail("missing list") }
  guard l.items[0].blocks is [Paragraph(words),List(inner)] else { fail("nested list was flattened") }
  assert_eq(md_plain(words), "outer")
  guard inner.items[0].blocks is [Paragraph(words)] else { fail("missing inner words") }
  assert_eq(md_plain(words), "inner")
}

///|
test "a core tree replaces a legacy tree and shares its bounded cache entry" {
  parsed.clear(); parsed_order.clear(); parsed_cost.clear(); parsed_used.val = 0; core_parsed.clear()
  blocks_of("$x$",None) |> ignore
  let tree : Json = [["p", [["code", {"content":"x","math":true,"drawing":null}]]]]
  let blocks = blocks_of("$x$",Some(tree))
  guard blocks is [Paragraph([Formula(source,_)])] else { fail("core tree not used") }
  assert_eq(source,"x")
  assert_eq(parsed_order.length(),1)
  for i in 0..=parsed_most { blocks_of("text\{i}",Some(Json::array([]))) |> ignore }
  assert_false(parsed.contains("$x$"))
  assert_false(core_parsed.contains("$x$"))
}

///|
test "a live renderer leaves syntax to the core and drawing data counts toward its cache" {
  parsed.clear(); parsed_order.clear(); parsed_cost.clear(); parsed_used.val = 0; core_parsed.clear()
  markdown_read.val = Some(fn(_,_) { })
  let pending = blocks_of("**pending**",None)
  markdown_read.val = None
  assert_eq(pending.length(),0)
  let large = "x".repeat(parsed_budget / 2)
  for i in 0..<3 {
    let tree : Json = [["p", [["code", {"content":"x","math":true,"drawing":{"unused":large}}]]]]
    blocks_of("formula\{i}",Some(tree)) |> ignore
  }
  assert_false(parsed.contains("formula0"))
  assert_true(parsed.contains("formula2"))
  assert_true(parsed_used.val <= parsed_budget)
}

///|
test "a core link first appears with its working hit region" {
  let answer : Ref[((Json?) -> Unit)?] = Ref(None)
  let opened : Array[String] = []
  let source = "详见 https://example.com/e2e"
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    markdown(c, source, on_link=fn(href) { opened.push(href) }) |> ignore
  }, w=390.0, h=200.0)
  markdown_read.val = Some(fn(_, done) { answer.val = Some(done) })
  t.draw()
  assert_true(t.find("example.com") is None)
  let tree : Json = [["p", ["详见 ", ["a", ["https://example.com/e2e"], {"href":"https://example.com/e2e"}]]]]
  (answer.val.unwrap())(Some(tree))
  t.draw()
  t.tap_run("example.com")
  assert_eq(opened,["https://example.com/e2e"])
}

///|
test "code colours use the core's runs rather than interpreting its language again" {
  let blocks = core_blocks([["pre", {"code":"const x = 1","lang":"ts","ink":"h6j2c2f"}]], "")
  guard blocks is [CodeBlock("ts",code,Some(ink))] else { fail("core ink lost") }
  let runs = core_ink(code,ink,false)
  assert_eq(runs.map(fn(r) { r.text }),["const ","x ","= ","1"])
  assert_eq(runs[0].color,Scope::Storage.light())
  assert_eq(core_ink("const x = 1","d11",false)[0].color,Scope::Str.light())
}
