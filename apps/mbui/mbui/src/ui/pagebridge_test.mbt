// A page's view and the app (native.mbt: `said`, NativeView::script, NativeView::touch; a site's late and slow
// answers), under a Tester (pagebridge.mbt).

///|
fn page_once(cell : Ref[@ui.NativeView?], make : () -> @ui.NativeView) -> @ui.NativeView {
  match cell.val {
    Some(v) => v
    None => {
      let v = make()
      cell.val = Some(v)
      v
    }
  }
}

///|
test "a script sent before its page has loaded runs once it has, after the ones sent before it" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(
    fn(c) {
      let v = page_once(cell, fn() { @ui.NativeView::page("<p>hi</p>") })
      c.native(v, h=Px(200.0)) |> ignore
    },
    finish=false,
  )
  let v = cell.val.unwrap()
  v.script("one()")
  v.script("two()")
  t.frame()
  // not loaded: none run
  assert_eq(t.view_scripts(v.id()), [])
  t.finish(2, v.id())
  t.frame()
  assert_eq(t.view_scripts(v.id()), ["one()", "two()"])
  // loaded: at once
  v.script("three()")
  assert_eq(t.view_scripts(v.id()), ["one()", "two()", "three()"])
  v.close()
}

///|
test "a page that says something is there for scripts, loaded or not" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let heard : Array[String] = []
  let t = @ui.Tester::new(
    fn(c) {
      let v = page_once(cell, fn() { @ui.NativeView::page("<p>hi</p>", said=fn(w) { heard.push(w) }) })
      c.native(v, h=Px(200.0)) |> ignore
    },
    finish=false,
  )
  let v = cell.val.unwrap()
  v.script("answer()")
  t.frame()
  assert_eq(t.view_scripts(v.id()), [])
  t.view_says(v.id(), "hello")
  t.frame()
  assert_eq(heard, ["hello"])
  assert_eq(t.view_scripts(v.id()), ["answer()"])
  v.close()
}

///|
test "what a page says in one frame is heard in the order it said it, as the next frame begins" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let heard : Array[String] = []
  let t = @ui.Tester::new(fn(c) {
    let v = page_once(cell, fn() { @ui.NativeView::page("<p>hi</p>", said=fn(w) { heard.push(w) }) })
    c.native(v, h=Px(200.0)) |> ignore
  })
  let v = cell.val.unwrap()
  t.view_says(v.id(), "a")
  t.view_says(v.id(), "b")
  t.view_says(v.id(), "{\"c\":1}")
  assert_eq(heard, [])
  t.frame()
  assert_eq(heard, ["a", "b", "{\"c\":1}"])
  v.close()
}

///|
/// A list of rows with a page's view in row 3, `mode` its touch.
fn page_list(cell : Ref[@ui.NativeView?], mode : @ui.Touch) -> (@ui.Ctx) -> Unit {
  fn(c) {
    let v = page_once(cell, fn() {
      let v = @ui.NativeView::page("<p>chart</p>")
      v.touch(mode)
      v
    })
    c.list("list", 40, 80.0, fn(i) {
      if i == 3 {
        c.native(v, h=Px(300.0)) |> ignore
      } else {
        c.box(h=Px(80.0), fn() { c.text("Row \{i}", wrap=false) |> ignore }) |> ignore
      }
    })
    |> ignore
  }
}

///|
test "a page that gives the list its upright drags: dragged up on it, the list scrolls and the page's touch is called off" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(page_list(cell, @ui.Touch::VerticalOut), w=390.0, h=844.0)
  let id = cell.val.unwrap().id()
  // (the slop the canvas's own drags start at, told with it)
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("touch \{id} vertical ") }))
  let before = t.list_offset()
  // on the page (rows 0-2 are 240 high: it is at 240 to 540)
  t.drag(200.0, 450.0, 200.0, 250.0)
  assert_true(t.views().contains("finger \{id} down 200 450"))
  assert_true(t.views().contains("finger \{id} cancel"))
  assert_true(t.list_offset() > before + 100.0)
  cell.val.unwrap().close()
}

///|
test "a page that keeps its touches: dragged on, the list stays and the page has the drag" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(page_list(cell, @ui.Touch::All), w=390.0, h=844.0)
  let id = cell.val.unwrap().id()
  let before = t.list_offset()
  t.drag(200.0, 450.0, 200.0, 250.0)
  assert_eq(t.list_offset(), before)
  assert_true(t.views().contains("finger \{id} down 200 450"))
  assert_true(t.views().contains("finger \{id} up 200 250"))
  assert_false(t.views().contains("finger \{id} cancel"))
  // dragged on a row that is no page: the list's
  t.drag(200.0, 700.0, 200.0, 600.0)
  assert_true(t.list_offset() > before)
  cell.val.unwrap().close()
}

///|
test "a page that gives a sideways drag nothing: it stays the page's, the list still" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(page_list(cell, @ui.Touch::VerticalOut), w=390.0, h=844.0)
  let id = cell.val.unwrap().id()
  let before = t.list_offset()
  t.drag(100.0, 450.0, 300.0, 460.0)
  assert_eq(t.list_offset(), before)
  assert_false(t.views().contains("finger \{id} cancel"))
  cell.val.unwrap().close()
}

///|
test "a page that gives the list its upright drags, dragged sideways past the slop first: it keeps the drag, the list still" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let t = @ui.Tester::new(page_list(cell, @ui.Touch::VerticalOut), w=390.0, h=844.0)
  let id = cell.val.unwrap().id()
  let before = t.list_offset()
  t.touch(0, 100.0, 450.0)
  t.touch(1, 150.0, 452.0)
  t.frame()
  t.touch(1, 150.0, 300.0)
  t.frame()
  t.touch(2, 150.0, 250.0)
  t.frame()
  assert_eq(t.list_offset(), before)
  assert_false(t.views().contains("finger \{id} cancel"))
  assert_true(t.views().contains("finger \{id} move 150 300"))
  assert_true(t.views().contains("finger \{id} up 150 250"))
  cell.val.unwrap().close()
}

///|
test "a page that gives two fingers to the canvas: the canvas has the first where it is now, then the second" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let seen : Ref[((Double, Double, Bool), (Double, Double)?)] = { val: ((0.0, 0.0, false), None) }
  let t = @ui.Tester::new(fn(c) {
    let v = page_once(cell, fn() {
      let v = @ui.NativeView::page("<p>chart</p>")
      v.touch(@ui.Touch::PinchOut)
      v
    })
    seen.val = (c.pointer(), c.second_pointer())
    c.box(w=Fill(1.0), h=Px(300.0), fn() { c.native(v) |> ignore }) |> ignore
  })
  let id = cell.val.unwrap().id()
  t.touch(0, 100.0, 100.0)
  t.touch(1, 120.0, 130.0)
  assert_true(t.views().contains("finger \{id} move 120 130"))
  t.touch(4, 200.0, 200.0)
  t.frame()
  assert_true(t.views().contains("finger \{id} cancel"))
  assert_eq(seen.val, ((120.0, 130.0, true), Some((200.0, 200.0))))
  t.touch(6, 200.0, 200.0)
  t.touch(2, 120.0, 130.0)
  cell.val.unwrap().close()
}

///|
test "a page that takes no touch: the canvas has it, the page never does" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let tapped : Ref[Int] = { val: 0 }
  let t = @ui.Tester::new(fn(c) {
    let v = page_once(cell, fn() {
      let v = @ui.NativeView::page("<p>hi</p>")
      v.touch(@ui.Touch::Through)
      v
    })
    let id = c.id("over")
    if c.clicked(id) {
      tapped.val += 1
    }
    c.box(w=Fill(1.0), h=Px(300.0), id~, fn() { c.native(v) |> ignore }) |> ignore
  })
  let id = cell.val.unwrap().id()
  t.tap(100.0, 100.0)
  assert_eq(tapped.val, 1)
  assert_false(t.views().iter().any(fn(l) { l.has_prefix("finger \{id}") }))
  cell.val.unwrap().close()
}

///|
test "a site's request with no head in time is answered with the app's words, and let go" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let gone : Ref[Bool] = { val: false }
  let t = @ui.Tester::new(fn(c) {
    let v = page_once(cell, fn() {
      @ui.NativeView::site("/", fn(_req, reply) { reply.when_gone(fn() { gone.val = true }) }, no_answer="station 60 秒内未响应")
    })
    c.native(v, h=Px(300.0)) |> ignore
  })
  let id = cell.val.unwrap().id()
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("settings \{id} ") && l.contains("\"head_wait_ms\":60000") }))
  t.site_says("{\"req\":3,\"method\":\"GET\",\"path\":\"/slow\",\"headers\":[],\"page\":false}")
  t.frame()
  assert_false(gone.val)
  t.site_no_answer(id, 3)
  t.frame()
  assert_true(gone.val)
  let words = @utf8.encode("station 60 秒内未响应").length()
  assert_true(t.views().contains("site head \{id} 3 502 [[\"Content-Type\",\"text/plain; charset=utf-8\"]]"))
  assert_true(t.views().contains("site chunk \{id} 3 \{words}"))
  assert_true(t.views().contains("site end \{id} 3 "))
  cell.val.unwrap().close()
}

///|
test "a site's answer read too slowly is stopped with the app's words, and let go" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let gone : Ref[Bool] = { val: false }
  let t = @ui.Tester::new(fn(c) {
    let v = page_once(cell, fn() {
      @ui.NativeView::site(
        "/",
        fn(_req, reply) {
          reply.head(200, [])
          reply.chunk(b"part")
          reply.when_gone(fn() { gone.val = true })
        },
        too_slow="网页读得太慢，已停止",
      )
    })
    c.native(v, h=Px(300.0)) |> ignore
  })
  let id = cell.val.unwrap().id()
  t.site_says("{\"req\":4,\"method\":\"GET\",\"path\":\"/big\",\"headers\":[],\"page\":false}")
  t.frame()
  t.site_too_slow(id, 4)
  t.frame()
  assert_true(gone.val)
  assert_true(t.views().contains("site end \{id} 4 网页读得太慢，已停止"))
  cell.val.unwrap().close()
}

///|
test "a run replayed that sends its page another script parts there" {
  let cell : Ref[@ui.NativeView?] = { val: None }
  let which : Ref[String] = { val: "a()" }
  let make = fn() {
    @ui.Tester::new(fn(c) {
      let v = page_once(cell, fn() { @ui.NativeView::page("<p>hi</p>") })
      c.native(v, h=Px(200.0)) |> ignore
      if c.clicked(c.id("go")) {
        v.script(which.val)
      }
      c.box(w=Px(100.0), h=Px(50.0), id=c.id("go"), fn() {  }) |> ignore
    })
  }
  // the run: its tape, with its script
  let t = make()
  t.start_tape()
  t.tap(50.0, 225.0)
  t.frame()
  let tape = t.tape()
  assert_true(tape.contains("VIEWSCRIPT 1 3 "))
  cell.val = None
  // the same again: no frame parts
  let same = make()
  for f in same.replay_frames(tape) {
    assert_eq(f.1, f.2)
  }
  // another script: it parts
  cell.val = None
  which.val = "b()"
  let other = make()
  assert_true(other.replay_frames(tape).iter().any(fn(f) { f.1.has_prefix("VIEWSCRIPT") && f.1 != f.2 }))
}
