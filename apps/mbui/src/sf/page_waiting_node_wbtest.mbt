// A page read for the first time keeps its real frame while each of its own parts becomes a non-interactive skeleton.

///|
test "a waiting page keeps its title and back, skeletonizes every block and changes to its real content" {
  for look in [Narrow, Wide] {
    let reading = @signals.signal(true)
    let error = @signals.signal("")
    let pressed = Ref(0)
    let back = Ref(0)
    let rooms : Map[String, @view.View] = {}
    let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0, platform=0)
    @ui.set_view_app(fn(root) {
      root.box(fn(holder) {
        holder.height(Is(Some(700.0))) |> ignore
        holder.pick(fn() { reading.get() }, fn(p, waiting) {
          let page = fn(v : @view.View) {
            page_node(v, fn() { "Sample workspace" }, fn() { ["one", "two", "three", "four"] }, fn(b, key) {
              b.box(fn(row) {
                rooms[key] = row
                row.height(Is(Some(70.0))).words(Is("Sample " + key))
                .says(Is(Some(@view.said(Button, label="Sample " + key)))) |> ignore
                presses_node(row, fn() { pressed.val += 1 })
              }) |> ignore
            }, on_back=fn() { back.val += 1 }, frame=fn() { { ..no_frame, back: Some("Back") } },
              lead=fn() { "Sample description" }, look=fn() { Some(look) },
              actions=fn(a) {
                a.box(fn(button) {
                  button.width(Is(Some(40.0))).height(Is(Some(40.0))).words(Is("Sample action")) |> ignore
                  presses_node(button, fn() { pressed.val += 1 })
                }) |> ignore
              })
          }
          if waiting {
            page_waiting_node(p, fn() { "Workspace" }, page, text=fn() { "Reading workspace" }, error=fn() { error.get() })
          } else {
            page(p)
          }
        })
      }) |> ignore
    })
    t.draw()
    assert_true(t.find("Workspace") is Some(_))
    assert_true(t.find("Sample workspace") is None)
    assert_true(t.find("Sample description") is None)
    assert_true(t.find("Sample one") is None)
    assert_true(t.all(Button, label="Sample one").is_empty())
    assert_true(t.all(Status, label="Reading workspace").length() == 1)
    let (x, y, w, h) = rooms["one"].rect()
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq(pressed.val, 0)
    let second_before = rooms["two"].rect().1
    error.set("Could not read")
    t.draw()
    assert_true(t.find("Could not read") is Some(_))
    assert_true(t.all(Status, label="Reading workspace").is_empty())
    assert_true(rooms["two"].rect().1 > second_before)
    t.tap_text("Back")
    assert_eq(back.val, 1)
    reading.set(false)
    t.draw()
    assert_true(t.find("Could not read") is None)
    assert_true(t.find("Sample one") is Some(_))
    t.act(Button, Activate, label="Sample one")
    assert_eq(pressed.val, 1)
  }
}

///|
test "a failed waiting page keeps its first block still while its other bones breathe" {
  let rows : Map[String, @view.View] = {}
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
  @ui.set_view_app(fn(root) {
    page_waiting_node(root, fn() { "Page" }, fn(p) {
      page_node(p, fn() { "Sample" }, fn() { ["first", "second"] }, fn(b, key) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is(key)) |> ignore
          rows[key] = row
        }) |> ignore
      }, on_back=fn() {  }, width=fn() { 400.0 })
    }, error=fn() { "Could not read" })
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let at = t.time()
  t.frame_at(at + breath_ms / 4.0)
  let first = tree.drawn_of(rows["first"].id()).unwrap().alpha
  let second = tree.drawn_of(rows["second"].id()).unwrap().alpha
  t.frame_at(at + breath_ms / 2.0)
  assert_eq(tree.drawn_of(rows["first"].id()).unwrap().alpha, first)
  assert_eq(first, 1.0)
  assert_true(tree.drawn_of(rows["second"].id()).unwrap().alpha != second)
}
