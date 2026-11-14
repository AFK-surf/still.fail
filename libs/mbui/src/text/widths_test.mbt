///|
test "width_runs: marks among Latin letters narrow, beside CJK full width" {
  // ASCII alone: as it is
  assert_eq(@text.width_runs("it's really you"), [(0, 15, false)])
  // no CJK: the whole line narrow
  assert_eq(@text.width_runs("confirm it\u{2019}s really you"), [(0, 23, true)])
  assert_eq(@text.width_runs("Loading\u{2026}"), [(0, 8, true)])
  // CJK only, its marks beside it: as it is
  assert_eq(@text.width_runs("他说\u{201C}你好\u{201D}"), [(0, 6, false)])
  // quotes round Latin words inside Chinese: full width, as Chinese sets them
  assert_eq(@text.width_runs("我喜欢\u{201C}Hello\u{201D}这个词"), [(0, 13, false)])
  assert_eq(@text.width_runs("加载中\u{2026}"), [(0, 4, false)])
  // a closing quote as its opening one, an apostrophe as its neighbours
  assert_eq(@text.width_runs("你\u{201C}A\u{201D} ok"), [(0, 7, false)])
  assert_eq(@text.width_runs("\u{2018}好\u{2019} it\u{2019}s"), [(0, 4, false), (4, 8, true)])
  // both in one line: cut where it changes
  assert_eq(@text.width_runs("通行密钥 it\u{2019}s ok"), [(0, 5, false), (5, 12, true)])
  assert_eq(@text.width_runs("it\u{2019}s 好"), [(0, 4, true), (4, 6, false)])
}

///|
test "width_runs: Han beyond the first plane is CJK, emoji neutral" {
  // 𠀀 (U+20000) after a quote: the quote full width
  assert_eq(@text.width_runs("\u{2019}\u{20000}"), [(0, 3, false)])
  // an emoji is neither: the quote among Latin letters narrow
  assert_eq(@text.width_runs("a\u{2019}\u{1F600}b"), [(0, 5, true)])
}
