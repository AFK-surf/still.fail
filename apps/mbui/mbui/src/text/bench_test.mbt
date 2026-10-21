///|
/// About 10,000 UTF-16 code units of mixed Chinese, English, punctuation
/// and emoji, like a long chat message.
fn mixed_text() -> String {
  let parts = [
    "MoonBit 是一门为云计算和边缘计算设计的编程语言，", "it compiles to WebAssembly, JavaScript and native code. ",
    "「排版」需要遵守禁则：句号。逗号，不能出现在行首！", "Line-breaking (UAX #14) and grapheme clusters 👨‍👩‍👧 🇨🇳 matter. ",
  ]
  let sb = StringBuilder()
  let mut i = 0
  while sb.to_string().length() < 10000 {
    sb.write_string(parts[i % parts.length()])
    i = i + 1
  }
  sb.to_string()
}

///|
test "bench: line breaks of 10k mixed CJK/English" (b : @bench.T) {
  let s = mixed_text()
  b.bench(name="line_breaks", fn() { b.keep(@text.line_breaks(s)) })
}

///|
test "bench: graphemes of 10k mixed CJK/English" (b : @bench.T) {
  let s = mixed_text()
  b.bench(name="graphemes", fn() { b.keep(@text.graphemes(s)) })
}
