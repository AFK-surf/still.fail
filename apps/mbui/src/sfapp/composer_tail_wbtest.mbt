// A chat's composer opened with where its draft is copied said beside send (抄送, each thread ticked): its row under
// the words keeps ＋ at its start and send at its end however long those names are, as its row did before the page
// moved to the retained tree (723b5ba19c^: a row that never wrapped). The box's row wraps the words above the
// controls; the controls going on to a line of their own put send at the box's left.

///|
/// The chat's retained composer in a window `w` wide, opened to write, both its threads ticked.
fn tail_tester(w : Double) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let read = fn() {
    chat_view_made({
      "title": "整理发布清单",
      "thread": { "id": 7 },
      "cc": [
        { "thread": 21, "place": "#still-fail-release-notes", "via": "slack", "on": true },
        { "thread": 22, "place": "产品讨论 · 发布清单", "via": "feishu", "on": true },
      ],
    })
  }
  let t = @ui.Tester::new(fn(c) {
    @sf.set_words(fill)
    @sf.begin(c) |> ignore
  }, w~, h=600.0, pointing=Mouse)
  let made : Ref[@sfpages.ChatComposerNode?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lies_along(Is(End)) |> ignore
    made.val = Some(@sfpages.chat_composer_node(root, src, r, fn() { Some(read()) },
      fn() { @sfpages.composer_width(w) }, fn() { 600.0 }, fn() { @sfpages.composer_foot_in(w) },
      fn() { @sfpages.composer_alone }, fn(_) { }))
  })
  t.draw()
  made.val.unwrap().composer.writing.field.focus()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat's composer copied to two threads keeps send at the end of ＋'s row, at a phone's width as at a desktop's" {
  let out : Array[String] = []
  for w in [390.0, 740.0, 1280.0] {
    let t = tail_tester(w)
    let plus = t.query(Button, label=@sf.t("web-main.composer.attach"))
    let send = t.query(Button, label=@sf.t("web-main.composer.send"))
    match (plus, send) {
      (Some(p), Some(s)) => {
        let py = p.rect.1 + p.rect.3 / 2.0
        let sy = s.rect.1 + s.rect.3 / 2.0
        if (py - sy).abs() > 1.0 || s.rect.0 < p.rect.0 + p.rect.2 || s.rect.0 + s.rect.2 > w {
          out.push("at \{w}: ＋ \{p.rect}, send \{s.rect}")
        }
      }
      _ => out.push("at \{w}: no ＋ or send")
    }
  }
  assert_eq(out, [])
}
