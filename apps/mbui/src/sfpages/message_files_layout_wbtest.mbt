// A 4:3 picture entering a narrow list was first laid out against the window, then against its row's inset width.
// When this happened at the top edge, recycling the row could repeat the two layouts within one frame.

///|
test "a picture row entering at the list edge fits its own room in every layout" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture("chat-many-images")
  let chat = (src.topic)("chat", { "station": "ws1/st1", "session": "s-c1" }).value.unwrap()
  let view = @sfbase.chat_view_made(chat)
  let a = view.messages[view.messages.length() - 1].attachments[0]
  let here : MessageHere = { station: "ws1/st1", session: "s-c1", view, go: None, inline: true, gutter: 0.0, list: None, core: None }
  let width = 350.76922607421875
  let inside = width - 32.0
  let scroll = @view.Scroll::list()
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(None)
  let places : Array[(Double, Double, Double, Double)] = []
  let faults : Array[String] = []
  let stopped = @view.faults_stop.val
  let told = @view.fault_told.val
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(s) { faults.push(s) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=width, h=804.923, platform=2, scale=3.25)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.scrolls_anchored(scroll, fn() { [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] }, est=334.4615349402794, ahead=0.0, put~, fn(row, _) {
      row.padding(Is((16.0, 20.0, 16.0, 0.0))) |> ignore
      row.box(fn(head) { head.height(Is(Some(51.3846153846154))) |> ignore }) |> ignore
      message_files_node(row, src, fn() { here }, fn() { [a] }, false, landed=fn(_, landing) {
        match landing {
          Some(l) => l.view.reacts(fn() { l.view.laid_window_told() }, fn(r) {
            match r { Some(rect) => places.push(rect); None => () }
          })
          None => ()
        }
      })
    }) |> ignore
  })
  // The next row's top is held in place, leaving the picture row's foot just inside the viewport.
  put.set(Some((4, 2.76922724797087)))
  t.draw()
  @view.faults_stop.val = stopped
  @view.fault_told.val = told
  println("FILESLAYOUT places=\{places} faults=\{faults}")
  assert_false(places.is_empty(), msg="the picture row was laid out")
  assert_true(places.iter().any(fn(p) { p.1 < 0.0 && p.1 + p.3 > 0.0 }), msg="a picture straddles the list's top edge")
  assert_true(faults.is_empty(), msg="the list settles in one frame: \{faults}")
  assert_true(places.iter().all(fn(p) { p.2 <= inside + 0.01 }), msg="the picture always fits its inset row: \{places}")
}
