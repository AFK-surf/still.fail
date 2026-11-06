///|
fn plan_item(words : String, status : String) -> Json {
  { "text": Json::string(words), "status": Json::string(status) }
}

///|
fn plan_drawn(t : @ui.Tester, words : String) -> @view.Drawn {
  t.drawn_words_found().filter(fn(d) { d.3 == words })[0].0
}

///|
test "plan list nodes follow changing items, keep their marks and styles, and leave with their parent" {
  for platform in [0, 2] {
    @sf.set_dark(Some(false))
    let values : @signals.Signal[Array[Json]] = @signals.signal(
      [plan_item("Finished", "completed"), plan_item("Working", "in_progress"), plan_item("Later", "pending")],
      same=fn(a, b) { a == b },
    )
    let shown = @signals.signal(true)
    let made = Ref(0)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=240.0, h=500.0, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.show(fn() { shown.get() }, fn(p) {
        made.val += 1
        p.width_share(Is(1.0)).lines_up(Is(Some(Start))) |> ignore
        plan_list_node(p, fn() { values.get() })
      })
    })
    t.draw()
    assert_eq(plan_drawn(t, "✓").runs[0].color, @sf.theme().p.green)
    assert_eq(plan_drawn(t, "›").runs[0].color, @sf.theme().p.accent)
    assert_eq(plan_drawn(t, "·").runs[0].color, @sf.theme().p.subtle)
    assert_true(t.tree_runs_of("Finished").unwrap()[0].strike)
    assert_true(!t.tree_runs_of("Working").unwrap()[0].strike)
    assert_eq(plan_drawn(t, "Finished").ink, @sf.theme().p.muted)
    assert_eq(plan_drawn(t, "Working").words_look.weight, 600)
    assert_eq(plan_drawn(t, "Later").words_look.weight, 400)
    assert_eq(plan_drawn(t, "Finished").x - plan_drawn(t, "✓").x, 16.0)
    assert_eq(plan_drawn(t, "Finished").w, 220.0)
    assert_true(plan_drawn(t, "Working").y > plan_drawn(t, "Finished").y)
    assert_true(plan_drawn(t, "Later").y > plan_drawn(t, "Working").y)
    assert_true(!t.drawn_words_found().iter().any(fn(d) { d.2 }), msg="a plan has no actions")
    assert_true(t.semantics().iter().any(fn(s) { s.label == "Finished" && !s.hidden }))
    assert_true(t.semantics().iter().any(fn(s) { s.label == "✓" && !s.hidden }))
    @sf.set_dark(Some(true))
    t.draw()
    assert_eq(plan_drawn(t, "✓").runs[0].color, @sf.theme().p.green)
    assert_eq(plan_drawn(t, "Finished").ink, @sf.theme().p.muted)
    @sf.set_dark(Some(false))
    t.draw()

    // Replace and reorder values at existing positions, add and remove rows, and change a status in place.
    values.set([plan_item("Later", "in_progress"), plan_item("Finished", "pending"), plan_item("Added", "completed"), plan_item("Added", "unknown")])
    t.draw()
    assert_eq(made.val, 1)
    assert_true(t.find("Working") is None)
    assert_true(!t.tree_runs_of("Finished").unwrap()[0].strike)
    assert_eq(plan_drawn(t, "Later").words_look.weight, 600)
    assert_true(t.tree_runs_of("Added").unwrap()[0].strike)
    assert_true(plan_drawn(t, "Later").y < plan_drawn(t, "Finished").y)
    assert_eq(t.drawn_words_found().filter(fn(d) { d.3 == "Added" }).length(), 2)
    values.set([])
    t.draw()
    assert_true(t.find("Added") is None && t.find("Later") is None)
    values.set([plan_item("A long plan item wraps within the available width without hiding its marker", "completed")])
    t.draw()
    assert_true(t.lines_of("A long plan item wraps within the available width without hiding its marker").length() > 1)
    assert_true(t.tree_runs_of("A long plan item").unwrap()[0].strike)
    t.resize(400.0, 500.0)
    t.draw()
    assert_true(t.find("A long plan item") is Some(_))
    shown.set(false)
    t.draw()
    assert_true(t.find("A long plan item") is None)
    shown.set(true)
    t.draw()
    assert_eq(made.val, 2)
    assert_true(t.find("A long plan item") is Some(_))
  }
  @sf.set_dark(None)
}
