///|
/// A widget of `html` drawn on HTML's own sheet in a window 400 wide, from moment 0.
fn widget_case(html : String) -> @ui.Tester {
  let hooks : @widget.Hooks = {
    defaults: @html.parse_sheet(@html.ua_css),
    tokens: fn() { [] },
    size: fn() { 15.0 },
    dark: fn() { false },
    element: fn(_, _, _) { false },
    expand: fn(_, _) { None },
    on_link: fn(_) {  },
  }
  let t = @ui.Tester::new(fn(_c) {  }, time=0.0, w=400.0, h=600.0, tree=fn(root : @view.View) {
    @widget.widget_node(root, fn() { html }, hooks) |> ignore
  })
  t.draw()
  t
}

///|
fn tap_on(t : @ui.Tester, n : @ui.SemNode) -> Unit {
  let (x, y, w, h) = n.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
}

///|
test "a tab shows its panel and hides the others', as the design system's tabs" {
  let t = widget_case(
    #|<style>.active { font-weight: 700 }</style>
    #|<div class="nav" role="tablist">
    #|  <button class="nav-link active" role="tab" aria-controls="w" aria-selected="true">Week</button>
    #|  <button class="nav-link" role="tab" aria-controls="m" aria-selected="false">Month</button>
    #|</div>
    #|<div id="w" role="tabpanel">seven days</div>
    #|<div id="m" role="tabpanel" hidden>thirty days</div>
    ,
  )
  assert_true(t.find("seven days") is Some(_))
  assert_true(t.find("thirty days") is None)
  assert_eq(t.get(Tab, label="Week").selected, Some(true))
  tap_on(t, t.get(Tab, label="Month"))
  assert_true(t.find("seven days") is None)
  assert_true(t.find("thirty days") is Some(_))
  assert_eq(t.get(Tab, label="Month").selected, Some(true))
  assert_eq(t.get(Tab, label="Week").selected, Some(false))
}

///|
test "a summary opens its details, a label ticks its box" {
  let t = widget_case(
    #|<details><summary>More</summary><p>hidden words</p></details>
    #|<label><input type="checkbox"> Flaky</label>
    ,
  )
  assert_true(t.find("hidden words") is None)
  tap_on(t, t.get(Button, label="More"))
  assert_true(t.find("hidden words") is Some(_))
  assert_eq(t.get(Checkbox, label="Flaky").check, Some(Off))
  tap_on(t, t.get(Checkbox, label="Flaky"))
  assert_eq(t.get(Checkbox, label="Flaky").check, Some(On))
}

///|
test "words, blocks and a flex row laid out" {
  let t = widget_case(
    #|<style>.row { display: flex; gap: 10px } .a { width: 100px; height: 20px; background: red }</style>
    #|<h1>Title</h1><p>Some <b>bold</b> words</p>
    #|<div class="row"><div class="a"></div><div class="a"></div></div>
    ,
  )
  assert_true(t.find("Title") is Some(_))
  assert_true(t.find("bold") is Some(_))
}
