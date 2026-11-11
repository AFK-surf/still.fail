///|
fn shape(nodes : Array[@html.Node]) -> String {
  let b = StringBuilder()
  fn go(n : @html.Node) {
    match n {
      Text(t) => b.write_string("\"" + t + "\"")
      Elem(e) => {
        b.write_string(e.tag)
        if !e.kids.is_empty() {
          b.write_string("(")
          for i, k in e.kids {
            if i > 0 {
              b.write_string(" ")
            }
            go(k)
          }
          b.write_string(")")
        }
      }
    }
  }
  for i, n in nodes {
    if i > 0 {
      b.write_string(" ")
    }
    go(n)
  }
  b.to_string()
}

///|
test "a fragment read as a browser reads it" {
  inspect(shape(@html.parse("<p>a<p>b<ul><li>x<li>y</ul>")), content="p(\"a\") p(\"b\") ul(li(\"x\") li(\"y\"))")
  inspect(shape(@html.parse("<div>1 &amp; 2 &lt;3&gt; &#x41;&#66;</div>")), content="div(\"1 & 2 <3> AB\")")
  inspect(
    shape(@html.parse("<style>p > a { color: red }</style><br><img src=x>t")),
    content="style(\"p > a { color: red }\") br img \"t\"",
  )
  inspect(
    shape(@html.parse("<svg viewBox='0 0 1 1'><linearGradient id='g'/><rect/></svg>")),
    content="svg(linearGradient rect)",
  )
  inspect(shape(@html.parse("<!doctype html><html><body><b>x</b></body></html>")), content="b(\"x\")")
  inspect(
    shape(@html.parse("<table><tr><td>1<td>2<tr><td>3</table>")),
    content="table(tr(td(\"1\") td(\"2\")) tr(td(\"3\")))",
  )
}

///|
let test_env : @html.Env = { width: 400.0, dark: false, reduced_motion: false, root_size: 16.0, tokens: [] }

///|
fn styled(css : String, html : String) -> Array[@html.Cascaded] {
  // (the sheet first: its <style> is the fragment's first element, its own cascade dropped)
  let s = @html.style_widget("<style>" + css + "</style>" + html, @html.parse_sheet(""), test_env, fn(_, _) { false })
  s.styles[1:].to_array()
}

///|
test "the cascade: specificity, order, !important, inheritance, var()" {
  let css =
    #|:root { --ink: #102030; --gap: 6px }
    #|div { color: var(--ink); padding: var(--gap) 2em }
    #|.a { color: red }
    #|#x { color: blue }
    #|p { color: green !important }
    #|.b:is(.c, .d) > span { font-weight: 600; margin: 0 auto }
    #|@media (max-width: 300px) { .a { color: black } }
    #|@media (min-width: 300px) { .wide { display: flex; gap: 4px 8px } }
  let s = styled(css, "<div class='a wide' id=x><p class=a>t</p><div class='b d'><span>s</span></div></div>")
  // #x beats .a
  inspect(s[0].style.color, content="65535")
  // !important beats inline-free id rules
  inspect(s[1].style.color, content="8388863")
  // inherited, through var()
  inspect(s[2].style.color, content="270545151")
  inspect(s[3].style.font_weight, content="600")
  inspect(s[3].style.color, content="270545151")
  inspect(s[0].style.display, content="flex")
  inspect(s[0].style.column_gap, content="Of(8, 0)")
  inspect(s[2].style.padding, content="[Of(6, 0), Of(32, 0), Of(6, 0), Of(32, 0)]")
  inspect(s[3].style.margin, content="[Of(0, 0), Auto, Of(0, 0), Auto]")
}

///|
test "colours" {
  let c = fn(s) { @html.parse_color(s, 0x000000FFL, false) }
  inspect(c("#fff"), content="Some(4294967295)")
  inspect(c("rgb(255 0 0 / 50%)"), content="Some(4278190208)")
  inspect(c("hsl(120, 100%, 50%)"), content="Some(16711935)")
  inspect(c("color-mix(in srgb, #000 50%, #fff)"), content="Some(2155905279)")
  inspect(c("light-dark(#000, #fff)"), content="Some(255)")
  inspect(c("crimson"), content="Some(3692313855)")
}

///|
test "lengths" {
  let b : @html.Basis = { em: 10.0, rem: 16.0, vw: 400.0 }
  inspect(@html.parse_len("calc(100% - 2em)", b), content="Some(Of(-20, 1))")
  inspect(@html.parse_len("min(160px, 100%)", b), content="Some(Of(160, 0))")
  inspect(@html.parse_len("1.5rem", b), content="Some(Of(24, 0))")
  inspect(@html.parse_len("clamp(10px, 5vw, 40px)", b), content="Some(Of(20, 0))")
}
