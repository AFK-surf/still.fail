// A node's code follows the shared answer, without a request until a real reader exists or after it goes.

///|
fn ink_test_node(v : @view.View, code : () -> String, lang : () -> String, dark : () -> Bool) -> Unit {
  let ink = code_ink_node(v, code, lang)
  v.words_runs(By(fn() {
    match ink() {
      Some(Some(value)) => ink_runs(code(), value, dark())
      _ => [@ui.span(code(), mono=true)]
    }
  })) |> ignore
}

///|
test "code ink nodes share one late answer, even when the first reader goes, and recolour with the theme" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String, String, (String?) -> Unit)] = []
  ink_read.val = Some(fn(code, lang, done) { asked.push((code, lang, done)) })
  let first = @signals.signal(false)
  let second = @signals.signal(false)
  let dark = @signals.signal(false)
  let code = "let x = 1"
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { first.get() }, fn(v) { ink_test_node(v, fn() { code }, fn() { "ts" }, fn() { dark.get() }) })
    root.show(fn() { second.get() }, fn(v) { ink_test_node(v, fn() { code }, fn() { "ts" }, fn() { dark.get() }) })
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 0)
  first.set(true)
  second.set(true)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 1)
  assert_eq((asked[0].0, asked[0].1), (code, "ts"))
  let plain = tree.drawn().filter(fn(d) { d.words == code })
  assert_eq(plain.length(), 2)
  assert_eq(plain[0].runs, [@ui.span(code, mono=true)])
  first.set(false)
  tree.frame(390.0, 844.0) |> ignore
  (asked[0].2)(Some("g3a6"))
  tree.frame(390.0, 844.0) |> ignore
  let light = tree.drawn().filter(fn(d) { d.words == code })
  assert_eq(light.length(), 1)
  assert_eq(light[0].runs, ink_runs(code, "g3a6", false))
  dark.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let night = tree.drawn().filter(fn(d) { d.words == code })
  assert_eq(night[0].runs, ink_runs(code, "g3a6", true))
  assert_true(light[0].runs != night[0].runs)
  assert_eq(asked.length(), 1)
  tree.dispose()
  assert_true(ink_readers.is_empty())
  assert_true(ink_answered.is_empty())
  kept_call.val = saved
}

///|
test "code ink keeps a late answer after every reader is gone for the next node" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String?) -> Unit] = []
  ink_read.val = Some(fn(_, _, done) { asked.push(done) })
  let shown = @signals.signal(true)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { shown.get() }, fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) })
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 1)
  shown.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_true(ink_readers.is_empty())
  (asked[0])(Some("g4"))
  shown.set(true)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 1)
  assert_eq(tree.drawn().filter(fn(d) { d.words == "code" })[0].runs, ink_runs("code", "g4", false))
  tree.dispose()
  kept_call.val = saved
}

///|
test "code ink waits for a skeleton node to become real even if its code does not change" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String, String)] = []
  ink_read.val = Some(fn(code, lang, _) { asked.push((code, lang)) })
  let bones = @signals.signal(true)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.bones(By(fn() { if bones.get() { 1L } else { 0L } })) |> ignore
      parent.box(fn(v) { ink_test_node(v, fn() { "real code" }, fn() { "js" }, fn() { false }) }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked, [])
  bones.set(false)
  assert_eq(asked, [("real code", "js")])
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked, [("real code", "js")])
  tree.dispose()
  kept_call.val = saved
}

///|
test "code ink waits until neither the node nor its holder is in bones, and asks only once" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String?) -> Unit] = []
  ink_read.val = Some(fn(_, _, done) { asked.push(done) })
  let outer = @signals.signal(true)
  let own = @signals.signal(true)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(parent) {
      parent.bones(By(fn() { if outer.get() { 1L } else { 0L } })) |> ignore
      parent.box(fn(v) {
        v.bones(By(fn() { if own.get() { 1L } else { 0L } })) |> ignore
        ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false })
      }) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  outer.set(false)
  assert_eq(asked.length(), 0)
  own.set(false)
  assert_eq(asked.length(), 1)
  outer.set(true)
  own.set(true)
  outer.set(false)
  own.set(false)
  assert_eq(asked.length(), 1)
  (asked[0])(Some("g4"))
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn().filter(fn(d) { d.words == "code" })[0].runs, ink_runs("code", "g4", false))
  tree.dispose()
  assert_true(ink_readers.is_empty())
  kept_call.val = saved
}

///|
test "code ink follows code and language changes, ignoring old answers until their pair is read again" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String, String, (String?) -> Unit)] = []
  ink_read.val = Some(fn(code, lang, done) { asked.push((code, lang, done)) })
  let code = @signals.signal("alpha")
  let lang = @signals.signal("js")
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) { ink_test_node(v, fn() { code.get() }, fn() { lang.get() }, fn() { false }) }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  code.set("beta")
  tree.frame(390.0, 844.0) |> ignore
  lang.set("ts")
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.map(fn(x) { (x.0, x.1) }), [("alpha", "js"), ("beta", "js"), ("beta", "ts")])
  (asked[0].2)(Some("g5"))
  (asked[1].2)(Some("b4"))
  tree.frame(390.0, 844.0) |> ignore
  let pending = tree.drawn().filter(fn(d) { d.words == "beta" })
  assert_eq(pending[0].runs, [@ui.span("beta", mono=true)])
  (asked[2].2)(Some("d4"))
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn().filter(fn(d) { d.words == "beta" })[0].runs, ink_runs("beta", "d4", false))
  lang.set("js")
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(tree.drawn().filter(fn(d) { d.words == "beta" })[0].runs, ink_runs("beta", "b4", false))
  assert_eq(asked.length(), 3)
  tree.dispose()
  kept_call.val = saved
}

///|
test "code ink also shares a live core's synchronous answer" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked = Ref(0)
  ink_read.val = Some(fn(_, _, done) {
    asked.val += 1
    done(Some("g4"))
  })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) }) |> ignore
    root.box(fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  let both = tree.drawn().filter(fn(d) { d.words == "code" })
  assert_eq(asked.val, 1)
  assert_eq(both.length(), 2)
  assert_eq(both[0].runs, ink_runs("code", "g4", false))
  assert_eq(both[1].runs, ink_runs("code", "g4", false))
  tree.dispose()
  kept_call.val = saved
}

///|
test "a synchronous code ink request may dispose its node without retaining the reader" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let node : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    node.val = Some(root.box(fn(_) {  }))
  })
  let code = @signals.signal("code")
  let asked = Ref(0)
  ink_read.val = Some(fn(_, _, done) {
    asked.val += 1
    tree.dispose()
    done(Some("g4"))
  })
  let read = code_ink_node(node.val.unwrap(), fn() { code.get() }, fn() { "js" })
  assert_eq(asked.val, 1)
  assert_true(ink_readers.is_empty())
  assert_true(ink_answered.is_empty())
  assert_eq(read(), Some(None))
  code.set("other")
  assert_eq(asked.val, 1)
  kept_call.val = saved
}

///|
test "code ink retains an evicted answer while a node reads it, then lets it go with the last reader" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String, String, (String?) -> Unit)] = []
  ink_read.val = Some(fn(code, lang, done) { asked.push((code, lang, done)) })
  let first = @signals.signal(true)
  let second = @signals.signal(false)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { first.get() }, fn(v) { ink_test_node(v, fn() { "held" }, fn() { "js" }, fn() { false }) })
    root.show(fn() { second.get() }, fn(v) { ink_test_node(v, fn() { "held" }, fn() { "js" }, fn() { false }) })
  })
  tree.frame(390.0, 844.0) |> ignore
  (asked[0].2)(Some("g4"))
  ink_keep(ink_key("x".repeat(inks_budget + 1), "large"), Some("a"))
  assert_false(inks.contains(ink_key("held", "js")))
  second.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let both = tree.drawn().filter(fn(d) { d.words == "held" })
  assert_eq(both.length(), 2)
  assert_eq(both[1].runs, ink_runs("held", "g4", false))
  assert_eq(asked.length(), 1)
  first.set(false)
  second.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_false(ink_held.contains(ink_key("held", "js")))
  first.set(true)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 2)
  tree.dispose()
  kept_call.val = saved
}

///|
test "code ink uses kept and absent core answers without waiting" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  let asked : Array[String] = []
  kept_call.val = Some(fn(name, _, _) {
    asked.push(name)
    Some(Ok((Json::object({ "ink": Json::string("g4") }), None)))
  })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked, ["code.ink"])
  assert_eq(tree.drawn().filter(fn(d) { d.words == "code" })[0].runs, ink_runs("code", "g4", false))
  tree.dispose()
  let _next = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let result : Ref[(() -> String??)?] = Ref(None)
  let empty = @view.Tree::new(fn(root) {
    root.box(fn(v) { result.val = Some(code_ink_node(v, fn() { "plain" }, fn() { "text" })) }) |> ignore
  })
  empty.frame(390.0, 844.0) |> ignore
  assert_eq((result.val.unwrap())(), Some(None))
  empty.dispose()
  kept_call.val = saved
}

///|
test "old and new code readers share requests in both directions, including a plain answer" {
  let saved = kept_call.val
  let old_code = Ref("")
  let old_value : Ref[String??] = Ref(None)
  let old = @ui.Tester::new(fn(c) {
    if old_code.val != "" {
      old_value.val = code_ink(c, old_code.val, "js")
    }
  })
  kept_call.val = None
  let asked : Array[(String, String, (String?) -> Unit)] = []
  ink_read.val = Some(fn(code, lang, done) { asked.push((code, lang, done)) })
  old_code.val = "old first"
  old.draw()
  assert_eq(asked.length(), 1)
  let code = @signals.signal("old first")
  let current : Ref[(() -> String??)?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(v) {
      let read = code_ink_node(v, fn() { code.get() }, fn() { "js" })
      current.val = Some(read)
      v.words(By(fn() {
        match read() {
          Some(Some(ink)) => ink
          Some(None) => "plain"
          None => "waiting"
        }
      })) |> ignore
    }) |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 1)
  (asked[0].2)(Some("g9"))
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((current.val.unwrap())(), Some(Some("g9")))
  assert_true(tree.drawn().iter().any(fn(d) { d.words == "g9" }))
  code.set("node first")
  tree.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 2)
  old_code.val = "node first"
  old.draw()
  assert_eq(asked.length(), 2)
  assert_eq(old_value.val, None)
  (asked[1].2)(None)
  tree.frame(390.0, 844.0) |> ignore
  old.draw()
  assert_eq((current.val.unwrap())(), Some(None))
  assert_eq(old_value.val, Some(None))
  assert_eq(asked.length(), 2)
  tree.dispose()
  kept_call.val = saved
}

///|
test "a late code ink answer from before reset cannot answer the next run" {
  let saved = kept_call.val
  let _reset = @ui.Tester::new(fn(_) {  })
  kept_call.val = None
  let asked : Array[(String?) -> Unit] = []
  ink_read.val = Some(fn(_, _, done) { asked.push(done) })
  let old = @view.Tree::new(fn(root) {
    root.box(fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) }) |> ignore
  })
  old.frame(390.0, 844.0) |> ignore
  old.dispose()
  let _next = @ui.Tester::new(fn(_) {  })
  ink_read.val = Some(fn(_, _, done) { asked.push(done) })
  let current = @view.Tree::new(fn(root) {
    root.box(fn(v) { ink_test_node(v, fn() { "code" }, fn() { "js" }, fn() { false }) }) |> ignore
  })
  current.frame(390.0, 844.0) |> ignore
  assert_eq(asked.length(), 2)
  (asked[0])(Some("b4"))
  current.frame(390.0, 844.0) |> ignore
  assert_eq(current.drawn().filter(fn(d) { d.words == "code" })[0].runs, [@ui.span("code", mono=true)])
  (asked[1])(Some("g4"))
  current.frame(390.0, 844.0) |> ignore
  assert_eq(current.drawn().filter(fn(d) { d.words == "code" })[0].runs, ink_runs("code", "g4", false))
  current.dispose()
  kept_call.val = saved
}

///|
test "a code and language pair cannot collide when it contains the old separator" {
  assert_true(ink_key("b", "a\u{1}c") != ink_key("c\u{1}b", "a"))
}
