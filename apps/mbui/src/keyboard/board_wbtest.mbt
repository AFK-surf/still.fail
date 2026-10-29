///|
let few : String =
  #|ni	你 40	泥 60
  #|hao	好 42
  #|ni hao	你好 38
  #|wo	我 35
  #|men	们 50
  #|wo men	我们 30

///|
fn board(scheme : @pinyin.Scheme) -> Board {
  Board::new(Some(@pinyin.Composer::new(@pinyin.Dict::parse(few), scheme)))
}

///|
fn typed(b : Board, keys : String) -> Array[Out] {
  let out : Array[Out] = []
  for k in keys {
    for o in b.tap(Letter(k), 0.0) {
      out.push(o)
    }
  }
  out
}

///|
test "pinyin: letters go to the composer, Space puts the best words in" {
  let b = board(Xiaohe)
  assert_eq(typed(b, "nihc"), [])
  assert_true(b.composing())
  assert_eq(b.tap(Space, 0.0), [Commit("你好")])
  assert_false(b.composing())
  assert_eq(b.tap(Space, 0.0), [Commit(" ")])
}

///|
test "pinyin: a sign puts the best words in before it; Enter the letters as typed" {
  let b = board(Full)
  typed(b, "nihao") |> ignore
  assert_eq(b.tap(Words("，"), 0.0), [Commit("你好"), Commit("，")])
  typed(b, "women") |> ignore
  assert_eq(b.tap(EnterKey, 0.0), [Commit("women")])
  assert_eq(b.tap(EnterKey, 0.0), [Enter])
}

///|
test "pinyin: Back takes a key back while typing, else deletes" {
  let b = board(Full)
  typed(b, "ni") |> ignore
  assert_eq(b.tap(Back, 0.0), [])
  assert_eq(b.tap(Back, 0.0), [])
  assert_false(b.composing())
  assert_eq(b.tap(Back, 0.0), [Delete])
}

///|
test "a candidate picked; a part of the keys picked waits for the rest" {
  let b = board(Xiaohe)
  typed(b, "womf") |> ignore
  assert_eq(b.pick(0), [Commit("我们")])
  typed(b, "nihc") |> ignore
  // 你 (for ni alone) first among the shorter
  let c = b.composer.unwrap().candidates()
  let ni = c.search_by(fn(x) { x.text == "你" }).unwrap()
  assert_eq(b.pick(ni), [])
  assert_eq(b.pick(0), [Commit("你好")])
}

///|
test "Shift: once for one capital, twice close together for all" {
  let b = board(Full)
  b.chinese = false
  assert_eq(b.tap(ShiftKey, 0.0), [])
  assert_eq(typed(b, "ab"), [Commit("A"), Commit("b")])
  b.tap(ShiftKey, 1000.0) |> ignore
  b.tap(ShiftKey, 1100.0) |> ignore
  assert_eq(b.shift, Locked)
  assert_eq(typed(b, "ab"), [Commit("A"), Commit("B")])
  b.tap(ShiftKey, 5000.0) |> ignore
  assert_eq(b.shift, Off)
}

///|
test "Chinese or letters: what is being typed goes in as typed" {
  let b = board(Full)
  typed(b, "ni") |> ignore
  assert_eq(b.tap(Lang, 0.0), [Commit("ni")])
  assert_false(b.chinese)
  assert_eq(typed(b, "ni"), [Commit("n"), Commit("i")])
}

///|
test "a field for a password or a number" {
  let b = board(Full)
  b.start("password", "done")
  assert_eq(typed(b, "ni"), [Commit("n"), Commit("i")])
  b.start("number", "done")
  assert_eq(b.page, Signs)
}

///|
test "the keys: WeChat's places; a finger between two keys has one, the bar none" {
  let b = board(Xiaohe)
  let cs = caps(b)
  assert_eq(cs.length(), 10 + 9 + 9 + 5)
  // q's cell from the keyboard's left edge, a's too though its row is set in
  assert_eq(cs[cap_at(cs, 0.0, 200.0)].key, Letter('q'))
  assert_eq(cs[cap_at(cs, 1.0, 380.0)].key, Letter('a'))
  // between q and w: the nearer
  assert_eq(cs[cap_at(cs, 110.0, 200.0)].key, Letter('q'))
  assert_eq(cs[cap_at(cs, 114.0, 200.0)].key, Letter('w'))
  assert_eq(cap_at(cs, 500.0, 40.0), -1)
  // Enter green for the field's action, grey while typing
  b.start("text", "send")
  let enter = cs.length() - 1
  assert_eq(caps(b)[enter].look, Green)
  typed(b, "ni") |> ignore
  assert_eq(caps(b)[enter].label, "确定")
}
