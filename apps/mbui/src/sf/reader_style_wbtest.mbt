///|
test "the reader's line spacing stays proportional when system text is larger" {
  let words = "第一行的小说正文\n第二行的小说正文"
  let book : Book = {
    title: "小说",
    id: 1,
    text: words,
    chunks: [words],
    starts: [0],
    parts: [],
    length: words.length(),
    chapters: [],
    heads: Map([]),
    encoding: "UTF-8",
    truncated: false,
    markdown: false,
  }
  let r = reading_for("reader-system-text")
  let style = { ..reader_style_default, indent: false }
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    reader_column(c, r, book, style, reader_paper("white"), left=0.0, right=0.0, top=0.0, foot=0.0)
  }, w=390.0, h=200.0, platform=2)
  t.set_font_scale(1.5)
  t.draw()
  let lines = t.text_runs().filter(fn(line) { line.text.contains("小说正文") })
  assert_eq(lines.length(), 2)
  let spacing = lines[1].top - lines[0].top
  let expected = @ui.sp_at(1.5, style.size.to_double()) * style.line
  assert_true((spacing - expected).abs() < 0.01, msg="spacing \{spacing}, expected \{expected}")
  reader_let_go("reader-system-text")
}

///|
test "a Markdown document's line spacing follows the larger system text too" {
  let words = "第一行的小说正文\n第二行的小说正文"
  let nodes : Array[Json] = [["p", ["第一行的小说正文", ["br", []], "第二行的小说正文"]]]
  let style = reader_style_default
  let t = @ui.Tester::new(fn(c) {
    begin(c) |> ignore
    markdown_part(c, words, nodes, "reader-system-text-md", size=style.size.to_double(), line=style.line, document=true)
  }, w=390.0, h=200.0, platform=2)
  t.set_font_scale(1.5)
  t.draw()
  let lines = t.text_runs().filter(fn(line) { line.text.contains("小说正文") })
  assert_eq(lines.length(), 2)
  let spacing = lines[1].top - lines[0].top
  let expected = @ui.sp_at(1.5, style.size.to_double()) * style.line
  assert_true((spacing - expected).abs() < 0.01, msg="spacing \{spacing}, expected \{expected}")
}
