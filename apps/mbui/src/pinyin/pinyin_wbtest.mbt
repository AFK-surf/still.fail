///|
/// A few words, costs made up to say what each test turns on.
let few : String =
  #|zhong	中 50	种 60	重 65
  #|zhong guo	中国 40
  #|guo	国 55	过 52
  #|ren	人 45
  #|zhong guo ren	中国人 48
  #|ren min	人民 50
  #|xi	西 60	系 58
  #|an	安 60
  #|xi an	西安 70
  #|xian	先 50	现 52
  #|ni	你 40
  #|hao	好 42
  #|ni hao	你好 38
  #|wo	我 35
  #|men	们 50
  #|wo men	我们 30
  #|lv	绿 50
  #|lve	略 50
  #|jue	觉 50
  #|ang	昂 50
  #|e	饿 50
  #|er	二 50

///|
fn firsts(scheme : Scheme, typed : String, n? : Int = 1) -> Array[String] {
  let d = Dict::parse(few)
  let sp = Speller::new(d, scheme).spell(typed)
  let c = d.candidates(sp, Learned::new())
  c[:if c.length() < n { c.length() } else { n }].to_array().map(fn(x) { x.text })
}

///|
test "full pinyin: a word typed whole" {
  assert_eq(firsts(Full, "zhongguoren"), ["中国人"])
  assert_eq(firsts(Full, "nihao"), ["你好"])
}

///|
test "full pinyin: the cheapest of the ways letters part into syllables" {
  // xian one syllable (先 50) before xi an (西安 70); a ' parts it
  assert_eq(firsts(Full, "xian"), ["先"])
  assert_eq(firsts(Full, "xi'an"), ["西安"])
}

///|
test "full pinyin: a sentence of several words first" {
  assert_eq(firsts(Full, "zhongguorenmin"), ["中国人民"])
  assert_eq(firsts(Full, "womennihao"), ["我们你好"])
}

///|
test "full pinyin: initials alone, and the last syllable begun" {
  assert_eq(firsts(Full, "zg"), ["中国"])
  assert_eq(firsts(Full, "nih"), ["你好"])
  assert_eq(firsts(Full, "zhongguor"), ["中国人"])
}

///|
test "full pinyin: words using fewer of the keys after the ones using all" {
  let all = firsts(Full, "zhongguo", n=4)
  assert_eq(all, ["中国", "中", "种", "重"])
}

///|
test "xiaohe: two keys a syllable" {
  // 中 v+s (zh ong), 国 g+o (uo), 你 n+i, 好 h+c (ao), 我 w+o, 们 m+f (en)
  assert_eq(firsts(Xiaohe, "vsgo"), ["中国"])
  assert_eq(firsts(Xiaohe, "nihc"), ["你好"])
  assert_eq(firsts(Xiaohe, "womf"), ["我们"])
  // 先 x+m (ian); 西安 xi + an
  assert_eq(firsts(Xiaohe, "xm"), ["先"])
  assert_eq(firsts(Xiaohe, "xian"), ["西安"])
}

///|
test "xiaohe: syllables without an initial, and ü" {
  // a lone vowel twice, ang as a+h, er as its letters
  assert_eq(firsts(Xiaohe, "ah"), ["昂"])
  assert_eq(firsts(Xiaohe, "ee"), ["饿"])
  assert_eq(firsts(Xiaohe, "er"), ["二"])
  // lü l+v, lüe l+t, jue j+t
  assert_eq(firsts(Xiaohe, "lv"), ["绿"])
  assert_eq(firsts(Xiaohe, "lt"), ["略"])
  assert_eq(firsts(Xiaohe, "jt"), ["觉"])
}

///|
test "xiaohe: a last key alone is its initial" {
  assert_eq(firsts(Xiaohe, "vsg"), ["中国"])
  assert_eq(firsts(Xiaohe, "n"), ["你"])
}

///|
test "composing: picking the keys' start, then the rest" {
  let c = Composer::new(Dict::parse(few), Full)
  for k in "zhongguoren" {
    c.press(k)
  }
  let at = c.candidates().search_by(fn(x) { x.text == "中国" }).unwrap()
  assert_eq(c.pick(at), None)
  assert_eq(c.preedit(), "中国ren")
  assert_eq(c.candidates()[0].text, "人")
  // taken back: 中国's keys offered again
  assert_true(c.back())
  assert_eq(c.candidates()[0].text, "中国人")
  assert_eq(c.pick(c.candidates().search_by(fn(x) { x.text == "中国" }).unwrap()), None)
  assert_eq(c.pick(0), Some("中国人"))
  assert_false(c.active())
  assert_false(c.back())
}

///|
test "composing: what is picked comes earlier next time" {
  let c = Composer::new(Dict::parse(few), Full)
  for k in "xian" {
    c.press(k)
  }
  assert_eq(c.candidates()[0].text, "先")
  let at = c.candidates().search_by(fn(x) { x.text == "现" }).unwrap()
  assert_eq(c.pick(at), Some("现"))
  for k in "xian" {
    c.press(k)
  }
  assert_eq(c.candidates()[0].text, "现")
}

///|
test "composing: a phrase of several picks is a word after" {
  let d = Dict::parse(few)
  let c = Composer::new(d, Xiaohe)
  for k in "nihcwomf" {
    c.press(k)
  }
  // 你好 then 我们, each picked alone
  let first = c.candidates().search_by(fn(x) { x.text == "你好" }).unwrap()
  assert_eq(c.pick(first), None)
  assert_eq(c.pick(c.candidates().search_by(fn(x) { x.text == "我们" }).unwrap()), Some("你好我们"))
  for k in "nihcwomf" {
    c.press(k)
  }
  assert_eq(c.candidates()[0].text, "你好我们")
  // kept and read again
  let again = Learned::parse(c.learned.to_text(d), d)
  let c2 = Composer::new(d, Full, learned=again)
  for k in "nihaowomen" {
    c2.press(k)
  }
  assert_eq(c2.candidates()[0].text, "你好我们")
}

///|
test "composing: Enter's letters as typed" {
  let c = Composer::new(Dict::parse(few), Full)
  for k in "xi'an" {
    c.press(k)
  }
  assert_eq(c.as_typed(), "xian")
  assert_eq(c.preedit(), "xi'an")
}
