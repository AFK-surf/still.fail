///|
test "inline styles nest, and CJK sits next to them" {
  let xs = @md.parse_inline("先看**粗体里有 *斜体* 的字**，再看 `code` 和 ~~划掉~~。")
  assert_eq(xs, [
    Text("先看"),
    Strong([Text("粗体里有 "), Emph([Text("斜体")]), Text(" 的字")]),
    Text("，再看 "),
    Code("code"),
    Text(" 和 "),
    Strike([Text("划掉")]),
    Text("。"),
  ])
}

///|
test "triple stars are strong and emphasis; an underscore inside a word is not" {
  assert_eq(@md.parse_inline("***both*** snake_case_name"), [
    Emph([Strong([Text("both")])]),
    Text(" snake_case_name"),
  ])
  assert_eq(@md.parse_inline("a * b * c"), [Text("a * b * c")])
}

///|
test "links, images, autolinks and bare addresses" {
  assert_eq(@md.parse_inline("see [the **docs**](https://example.com/a_(b)) now"), [
    Text("see "),
    Link("https://example.com/a_(b)", [Text("the "), Strong([Text("docs")])]),
    Text(" now"),
  ])
  assert_eq(@md.parse_inline("![a chart](chart.png)"), [Image("chart.png", "a chart")])
  assert_eq(@md.parse_inline("<https://still.fail>"), [
    Link("https://still.fail", [Text("https://still.fail")]),
  ])
  // a bare address ends at Chinese, and the full stop after it is the sentence's
  assert_eq(@md.parse_inline("打开 https://example.com/x?y=1。然后（https://a.b/c）已改"), [
    Text("打开 "),
    Link("https://example.com/x?y=1", [Text("https://example.com/x?y=1")]),
    Text("。然后（"),
    Link("https://a.b/c", [Text("https://a.b/c")]),
    Text("）已改"),
  ])
  // brackets that lead nowhere stay as written
  assert_eq(@md.parse_inline("[not a link] and [x]"), [Text("[not a link] and [x]")])
}

///|
test "escapes, code spans and line breaks" {
  assert_eq(@md.parse_inline("\\*not\\* `` a ` b `` x  \ny\nz"), [
    Text("*not* "),
    Code("a ` b"),
    Text(" x"),
    HardBreak,
    Text("y"),
    SoftBreak,
    Text("z"),
  ])
}

///|
test "blocks: headings, paragraphs, quotes, rules, code" {
  let doc = @md.parse(
    (
      #|# Title
      #|
      #|A paragraph
      #|on two lines.
      #|
      #|> quoted *words*
      #|lazily continued
      #|
      #|---
      #|
      #|```moonbit
      #|fn main {
      #|  println("hi")
      #|}
      #|```
      #|
      #|Setext
      #|===
    ),
  )
  assert_eq(doc, [
    Heading(1, [Text("Title")]),
    Paragraph([Text("A paragraph"), SoftBreak, Text("on two lines.")]),
    Quote([
      Paragraph([
        Text("quoted "),
        Emph([Text("words")]),
        SoftBreak,
        Text("lazily continued"),
      ]),
    ]),
    Rule,
    CodeBlock("moonbit", "fn main {\n  println(\"hi\")\n}"),
    Heading(1, [Text("Setext")]),
  ])
}

///|
test "lists: tight and loose, numbered, nested, tasks" {
  let doc = @md.parse(
    (
      #|- one
      #|- two
      #|  - nested
      #|- [x] done
      #|- [ ] to do
      #|
      #|3. three
      #|
      #|4. four
    ),
  )
  assert_eq(doc, [
    List({
      ordered: false,
      start: 1,
      tight: true,
      items: [
        { task: None, blocks: [Paragraph([Text("one")])] },
        {
          task: None,
          blocks: [
            Paragraph([Text("two")]),
            List({
              ordered: false,
              start: 1,
              tight: true,
              items: [{ task: None, blocks: [Paragraph([Text("nested")])] }],
            }),
          ],
        },
        { task: Some(true), blocks: [Paragraph([Text("done")])] },
        { task: Some(false), blocks: [Paragraph([Text("to do")])] },
      ],
    }),
    List({
      ordered: true,
      start: 3,
      tight: false,
      items: [
        { task: None, blocks: [Paragraph([Text("three")])] },
        { task: None, blocks: [Paragraph([Text("four")])] },
      ],
    }),
  ])
}

///|
test "a list item's text keeps going under it, and a list ends at a heading" {
  let doc = @md.parse("1. first line\nsecond line\n# After")
  assert_eq(doc, [
    List({
      ordered: true,
      start: 1,
      tight: true,
      items: [
        {
          task: None,
          blocks: [Paragraph([Text("first line"), SoftBreak, Text("second line")])],
        },
      ],
    }),
    Heading(1, [Text("After")]),
  ])
}
