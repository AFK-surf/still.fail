// A chat's messages made whole as nodes (sfpages message_node.mbt), each where an old view's message_row draws it: the
// same words at the same places, at a phone's width (their pictures at their heads' start) and a wide one's.

///|
/// The words drawn now, each with where it is to a hundredth, in one order.
fn mm_words(t : @ui.Tester) -> Array[String] {
  let all = t.words().map(fn(w) { "\{w.0} at \{(w.1 * 100.0).round() / 100.0},\{(w.2 * 100.0).round() / 100.0}" })
  all.sort()
  all
}

///|
test "a chat's messages of words alone, as nodes, where an old view's message_row draws them" {
  for case in [(390.0, true, 2), (800.0, false, 0)] {
    let (w, inline, platform) = case
    new_run()
    let src = fixture("chat")
    let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
    let (view, entries, _) = view_of_chat(src, r)
    let v = view.unwrap()
    let here : @sfpages.MessageHere = {
      station: r.station,
      session: r.session,
      view: v,
      go: None,
      inline,
      gutter: 0.0,
      list: None,
      core: None,
    }
    for e in entries {
      guard e is Said(r) && @sfpages.message_made_whole_now(r.message()) > 0 else { continue }
      let m = r.message()
      let old = @ui.Tester::new(
        fn(c) {
          @sf.begin(c) |> ignore
          c.with_theme(@sf.ui_theme(), fn() {
            c.column(w=Fill(1.0), pad=16.0, fn() {
              @sfpages.message_row(c, src, here, m)
              c.text("the next message", style=@sf.theme().t.words) |> ignore
            }) |> ignore
          })
        },
        w~,
        h=900.0,
        platform~,
      )
      old.run_for(@ui.move_most_ms)
      let old_words = mm_words(old)
      let made = @ui.Tester::new(fn(_c) {  }, w~, h=900.0, platform~)
      @ui.set_view_app(fn(root) {
        @ui.set_tree_theme(@sf.ui_theme_now)
        root.box(fn(b) {
          b.padding(Is((16.0, 16.0, 16.0, 16.0))).lines_up(Is(None)) |> ignore
          b.box(fn(message) {
            @sfpages.message_row_node(message, src, fn() { here }, fn() { m }, fn() { w })
          }) |> ignore
          // The room left under it matters too: a time hidden by the next joined message leaves no empty slot.
          @sf.words_node(b, fn() { "the next message" }, fn() { @sf.theme().t.words }) |> ignore
        })
        |> ignore
      })
      made.run_for(@ui.move_most_ms)
      let made_words = mm_words(made)
      let only_made = made_words.filter(fn(x) { !old_words.contains(x) })
      let only_old = old_words.filter(fn(x) { !made_words.contains(x) })
      assert_eq(made_words, old_words, msg="\{w} \{m.ts}:\nonly made \{only_made}\nonly old  \{only_old}")
    }
  }
}
