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
    bridge: { state: fn() { None }, keep: fn(_) {  }, follow_up: fn(_) {  } },
    failed: fn(_) {  },
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

///|
test "a script's listener hears a press and what it changes is drawn" {
  let t = widget_case(
    #|<div id="n">0</div>
    #|<button id="b">Add</button>
    #|<script>
    #|  let n = 0
    #|  document.getElementById('b').addEventListener('click', () => {
    #|    n += 1
    #|    document.getElementById('n').textContent = `count ${n}`
    #|    document.querySelector('#n').classList.toggle('on', n > 1)
    #|  })
    #|</script>
    ,
  )
  assert_true(t.find("count 1") is None)
  tap_on(t, t.get(Button, label="Add"))
  assert_true(t.find("count 1") is Some(_))
  tap_on(t, t.get(Button, label="Add"))
  assert_true(t.find("count 2") is Some(_))
}

///|
test "a script builds what is drawn as it loads" {
  let t = widget_case(
    #|<ul id="list"></ul>
    #|<script>
    #|  const items = ['alpha', 'beta', 'gamma']
    #|  const ul = document.getElementById('list')
    #|  ul.innerHTML = items.map((x, i) => `<li data-i="${i}">${x.toUpperCase()}</li>`).join('')
    #|  for (const li of document.querySelectorAll('li')) li.style.fontWeight = li.dataset.i === '1' ? '700' : '400'
    #|</script>
    ,
  )
  assert_true(t.find("ALPHA") is Some(_))
  assert_true(t.find("GAMMA") is Some(_))
}

///|
test "a handler written in place runs, and what the widget keeps reaches the app" {
  let kept = []
  let hooks : @widget.Hooks = {
    defaults: @html.parse_sheet(@html.ua_css),
    tokens: fn() { [] },
    size: fn() { 15.0 },
    dark: fn() { false },
    element: fn(_, _, _) { false },
    expand: fn(_, _) { None },
    on_link: fn(_) {  },
    bridge: { state: fn() { Some("{\"n\":4}") }, keep: fn(s) { kept.push(s) }, follow_up: fn(_) {  } },
    failed: fn(_) {  },
  }
  let t = @ui.Tester::new(fn(_c) {  }, time=0.0, w=400.0, h=600.0, tree=fn(root : @view.View) {
    @widget.widget_node(
      root,
      fn() {
        #|<p id="o"></p><button onclick="n++; document.getElementById('o').textContent = 'n=' + n; openai.setWidgetState({n})">Go</button>
        #|<script>let n = openai.widgetState.n</script>
      },
      hooks,
    )
    |> ignore
  })
  t.draw()
  tap_on(t, t.get(Button, label="Go"))
  assert_true(t.find("n=5") is Some(_))
  assert_eq(kept, ["{\"n\":5}"])
}

///|
test "a pre keeps its lines, each on its own" {
  let t = widget_case(
    #|<pre><code>- old line
    #|+ new line</code></pre>
    ,
  )
  guard t.find("- old line") is Some((_, y1)) && t.find("+ new line") is Some((_, y2)) else {
    fail("a line of the pre is not drawn whole")
  }
  assert_true(y2 > y1)
}

///|
test "an inline element in a flex row is an item of its own, its width held" {
  let t = widget_case(
    #|<div style="display:flex"><span style="width:48px">10 人</span><span>noon</span></div>
    #|<div style="display:flex"><span style="width:48px">5</span><span>onno</span></div>
    ,
  )
  guard t.find("noon") is Some((x1, _)) && t.find("onno") is Some((x2, _)) else { fail("not drawn") }
  // (the words' middles: the same letters as wide, after the same 48 points)
  assert_eq(x1, x2)
  assert_true(x1 > 48.0)
}
