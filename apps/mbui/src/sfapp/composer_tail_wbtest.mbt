// A chat's composer opened with where its draft is copied said beside send (抄送, each thread ticked): its row under
// the words keeps ＋ at its start and send at its end however long those names are, as its row did before the page
// moved to the retained tree (723b5ba19c^: a row that never wrapped). The box's row wraps the words above the
// controls; the controls going on to a line of their own put send at the box's left. Closed, the capsule's one line
// held the names whole, pushing send past its edge and leaving the words no room.

///|
/// The chat's retained composer in a window `w` wide, both its threads ticked; opened to write where `opened`.
fn tail_tester(w : Double, opened? : Bool = true) -> @ui.Tester {
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
      fn() { @sfpages.composer_side() }, (root, fn(_, _) { 600.0 }), fn(_) { @sfpages.composer_foot_in(w) },
      fn() { @sfpages.composer_alone }, fn(_) { }))
  })
  t.draw()
  if opened {
    made.val.unwrap().composer.writing.field.focus()
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat's composer copied to two threads keeps send at the end of ＋'s row, opened or not, at a phone's width as at a desktop's" {
  let out : Array[String] = []
  for at in [(390.0, true), (740.0, true), (1280.0, true), (390.0, false), (740.0, false), (1280.0, false)] {
    let (w, opened) = at
    let t = tail_tester(w, opened~)
    let plus = t.query(Button, label=@sf.t("web-main.composer.attach"))
    let send = t.query(Button, label=@sf.t("web-main.composer.send"))
    match (plus, send) {
      (Some(p), Some(s)) => {
        let py = p.rect.1 + p.rect.3 / 2.0
        let sy = s.rect.1 + s.rect.3 / 2.0
        if (py - sy).abs() > 1.0 || s.rect.0 < p.rect.0 + p.rect.2 || s.rect.0 + s.rect.2 > w {
          out.push("at \{w}\{if opened { " opened" } else { "" }}: ＋ \{p.rect}, send \{s.rect}")
        }
      }
      _ => out.push("at \{w}\{if opened { " opened" } else { "" }}: no ＋ or send")
    }
  }
  assert_eq(out, [])
}
