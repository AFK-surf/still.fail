///|
/// The words the keyboard has (words.txt), read as it reads them: from the package's directory or the module's, as
/// the test is run.
fn words() -> Dict {
  for p in ["words.txt", "src/pinyin/words.txt", "apps/mbui/src/pinyin/words.txt"] {
    match Dict::load(p) {
      Some(d) => return d
      None => ()
    }
  }
  abort("words.txt not found")
}

///|
fn first(d : Dict, scheme : Scheme, typed : String) -> String {
  let c = d.candidates(Speller::new(d, scheme).spell(typed), Learned::new(), most=1)
  if c.length() == 0 {
    ""
  } else {
    c[0].text
  }
}

///|
test "the keyboard's words: everyday words and sentences first" {
  let d = words()
  let full = [
    ("nihao", "你好"),
    ("women", "我们"),
    ("zhongguo", "中国"),
    ("yinhang", "银行"),
    ("zhangda", "长大"),
    ("xian", "先"),
    ("xi'an", "西安"),
    ("zg", "中国"),
    ("jintiantianqihenhao", "今天天气很好"),
    ("womenyiqiquchifan", "我们一起去吃饭"),
    ("shurufa", "输入法"),
    ("xihuan", "喜欢"),
    ("shenme", "什么"),
    ("meiyou", "没有"),
    ("zhege", "这个"),
  ]
  let xiaohe = [
    ("nihc", "你好"),
    ("womf", "我们"),
    ("vsgo", "中国"),
    ("ybhh", "银行"),
    ("jbtmtmqihfhc", "今天天气很好"),
    ("uurufa", "输入法"),
    ("ufme", "什么"),
    ("mwyz", "没有"),
  ]
  let wrong : Array[String] = []
  for t in full {
    let got = first(d, Full, t.0)
    if got != t.1 {
      wrong.push("full \{t.0}: \{got}, not \{t.1}")
    }
  }
  for t in xiaohe {
    let got = first(d, Xiaohe, t.0)
    if got != t.1 {
      wrong.push("xiaohe \{t.0}: \{got}, not \{t.1}")
    }
  }
  assert_eq(wrong, [])
}
