// A page leaving in an input event captures the composer's current size before its retained field is removed.

///|
test "a retained composer is measured after its draft grows in the event that removes its page" {
  for width in [390.0, 700.0, 1280.0] {
    @sfbase.reset()
    composing_reset()
    @sf.set_words(@sfbase.fill)
    let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
    let shown = @signals.signal(true)
    let node : Ref[ComposerNode?] = Ref(None)
    let read : Ref[(Double, Double)] = Ref((0.0, 0.0))
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=width, h=800.0, platform=0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.show(fn() { shown.get() }, fn(page) {
        page.width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
        node.val = Some(composer_node(page, src, "event-draft", fn() {
          { station: "ws/st", draft: "event-draft", session: "chat", placeholder: "Write",
            toolbar: None, toolbar_node: None, note: [], tail: None, roomy: false, locked: false, offline: false, warm_agent: false }
        }, fn(_) {  }, (page, fn(_, h) { h }), fn(_, _, _, _) {  }))
      })
    })
    t.draw()
    let n = node.val.unwrap()
    n.writing.field.focus()
    t.draw()
    let before = (n.field.laid_size().1, n.cap.laid_size().1)
    @ui.view_tree().unwrap().event(t.time(), fn() {
      n.writing.field.set("one\ntwo\nthree\nfour\nfive\nsix")
      read.val = (n.field.laid_size().1, n.cap.laid_size().1)
      shown.set(false)
    })
    assert_true(read.val.0 > before.0 && read.val.1 > before.1,
      msg="the field and its composer include the edit at \{width}: \{before} -> \{read.val}")
  }
}
