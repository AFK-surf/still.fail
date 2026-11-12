// A new chat's page draws its model control of what the core's `newChat` says of it closed (NewChatPick); what its
// panel shows is the `pick` topic, asked as the hand comes to the control (a pointer resting over it, a finger or a
// pointer going down on it) and opened once that is answered: over a core answering it late, the panel opens whole the
// frame it is, on 小屏, 中屏 and 大屏, never in its bones, never half, never filled after; nothing of it asked with the
// page; and not at all once what it was pressed in is gone (the page left, the workspace switched, something else put
// up), what it asked let go of.

///|
/// The app on a new chat's page (made-up core `newchat`) in a window `w` by `h` on `platform`'s hand, the panel's own
/// pick answered `late` ms after it is asked and the rest at once, what the client sends told to `sent`; at rest, with
/// nothing of the panel asked with the page (what 中屏's first press asked let go of and forgotten).
fn late_pick_tester(sent : Array[String], w : Double, h : Double, platform : Int, late : Double) -> (@ui.Tester, Source) raise {
  new_run()
  let base = fixture("newchat")
  let src = round_trip_again(base, 0.0, heard=fn(m) { if m.has_prefix("out ") { sent.push(m) } }, late=fn(name, _) {
    if name == "pick" {
      late
    } else {
      0.0
    }
  })
  // (on a new chat's page, as the made-up core's mode opens it)
  open_fixture_over("newchat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_false(pick_asked(sent), msg="\{w}: asked with the page")
  // (on 中屏's tape the page is beside the sidebar: a press on it brings it over first, as it does there; what its
  // going down asked let go of as it leaves)
  if w > 600.0 && w < 1000.0 {
    let (x, y) = model_control_at(t)
    t.press_at(x, y)
    t.release(x, y)
    t.move_to(1.0, 1.0)
    t.run_for(late + @ui.move_most_ms)
    assert_true(pick_let_go(sent), msg="\{w}: what the press that brought it over asked")
    assert_true(t.query(@ui.Role::Dialog) is None, msg="\{w}: brought over, nothing opened")
    sent.clear()
  }
  (t, src)
}

///|
/// The ids the client asked the core for a model control's panel (`pick`) by, in `sent`.
fn pick_asks(sent : Array[String]) -> Array[Int] {
  sent.filter_map(fn(m) {
    let j = @json.parse(m[4:].to_owned()) catch { _ => return None }
    match j {
      Object(o) =>
        match (o.get("id"), o.get("subscribe")) {
          (Some(Number(n, ..)), Some(Object(t))) if t.get("topic") == Some(Json::string("pick")) => Some(n.to_int())
          _ => None
        }
      _ => None
    }
  })
}

///|
/// Whether the client asked the core for a model control's panel in `sent`.
fn pick_asked(sent : Array[String]) -> Bool {
  pick_asks(sent).length() > 0
}

///|
/// Whether the client let go of each panel it asked for in `sent`.
fn pick_let_go(sent : Array[String]) -> Bool {
  let gone : Array[Int] = sent.filter_map(fn(m) {
    let j = @json.parse(m[4:].to_owned()) catch { _ => return None }
    match j {
      Object(o) =>
        match (o.get("id"), o.get("unsubscribe")) {
          (Some(Number(n, ..)), Some(True)) => Some(n.to_int())
          _ => None
        }
      _ => None
    }
  })
  pick_asks(sent).iter().all(fn(id) { gone.contains(id) })
}

///|
/// Where the control is pressed: on its model's name, at its start (the name cut short where its row is short).
fn model_control_at(t : @ui.Tester) -> (Double, Double) {
  let w = t.words().filter(fn(w) { w.0 == "Opus 5.5" })[0]
  (w.1 + 4.0, w.2 + w.4 / 2.0)
}

///|
/// The panel's words the page has none of: the models it does not run on.
let pick_panel_words : Array[String] = ["GPT-6", "Sonnet 5"]

///|
test "a new chat's model control pressed over a core answering its panel 1 s late: on 小屏, 中屏 and 大屏 the panel opens whole as that is answered, nothing of it before, all of it from then; nothing of it asked with the page" {
  let late = 1000.0
  for s in switch_screens {
    let (name, w, h, platform) = s
    let sent : Array[String] = []
    let (t, _) = late_pick_tester(sent, w, h, platform, late)
    let (x, y) = model_control_at(t)
    let start = t.time()
    t.press_at(x, y)
    t.release(x, y)
    t.frame()
    assert_true(pick_asked(sent), msg="\{name}: asked by the press")
    whole_from(words_over(t, start, late + 400.0, pick_panel_words), pick_panel_words, late, late, name)
    assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="\{name}: its panel")
  }
}

///|
test "a new chat's model control with a mouse: its panel asked as the pointer comes to rest over it and let go of as it leaves, nothing pressed; pressed once that is answered, it opens at the press" {
  let late = 300.0
  for s in switch_screens[1:] {
    let (name, w, h, platform) = s
    let sent : Array[String] = []
    let (t, _) = late_pick_tester(sent, w, h, platform, late)
    let (x, y) = model_control_at(t)
    // (come to rest over it and gone, nothing pressed: asked, then let go of)
    t.move_to(x, y)
    t.run_for(@ui.move_most_ms)
    assert_true(pick_asked(sent), msg="\{name}: asked as the pointer rests over it")
    t.move_to(1.0, 1.0)
    t.run_for(@ui.move_most_ms)
    assert_true(pick_let_go(sent), msg="\{name}: let go of as it left")
    // (over it again, answered by then: the press opens it in its own frame)
    t.move_to(x, y)
    t.run_for(late + 100.0)
    t.press_at(x, y)
    t.release(x, y)
    t.frame()
    for word in pick_panel_words {
      assert_true(t.find(word) is Some(_), msg="\{name}: \{word} at the press")
    }
  }
}

///|
test "a finger on a new chat's model control on 小屏: the panel's pick asked as it goes down; let go a few frames later, over a core answering within them, the panel opens in the frame it is let go" {
  let late = 3.0 * @ui.frame_period_default
  let sent : Array[String] = []
  let (t, _) = late_pick_tester(sent, 390.0, 844.0, 2, late)
  let (x, y) = model_control_at(t)
  t.press_at(x, y)
  t.frame()
  assert_true(pick_asked(sent), msg="asked as it went down")
  for word in pick_panel_words {
    assert_true(t.find(word) is None, msg="\{word} while it is down")
  }
  t.run_for(6.0 * @ui.frame_period_default)
  t.release(x, y)
  t.frame()
  for word in pick_panel_words {
    assert_true(t.find(word) is Some(_), msg="\{word} in the frame it was let go")
  }
}

///|
/// What leaves what a press of the model control was pressed in, while its panel's pick is not answered yet: the page
/// left for another, the workspace switched, another control pressed that puts something up (the station's pick).
let left_while_waiting : Array[String] = ["page left", "workspace switched", "another opened"]

///|
test "a new chat's model control pressed over a core answering its panel 1 s late, then the page left, the workspace switched or another control's panel opened: on 小屏, 中屏 and 大屏 no model panel opens when it is answered, and what was asked is let go of" {
  let late = 1000.0
  let faults : Array[String] = []
  for s in switch_screens {
    let (name, w, h, platform) = s
    for what in left_while_waiting {
      let at = "\{name} \{what}"
      let sent : Array[String] = []
      let (t, src) = late_pick_tester(sent, w, h, platform, late)
      let (x, y) = model_control_at(t)
      t.press_at(x, y)
      t.release(x, y)
      t.move_to(1.0, 1.0)
      t.run_for(@ui.move_most_ms)
      if !pick_asked(sent) {
        faults.push(at + ": not asked")
        continue
      }
      match what {
        "page left" => @ui.view_tree().unwrap().event(t.time(), fn() { open_page(Archived) })
        "workspace switched" => @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
        _ => {
          // (the station's control, in the control's row: Willow)
          let st = t.words().filter(fn(w) { w.0 == "Willow" && (w.2 + w.4 / 2.0 - y).abs() < 30.0 })
          guard st.length() > 0 else {
            faults.push(at + ": no station's control")
            continue
          }
          let (sx, sy) = (st[0].1 + 4.0, st[0].2 + st[0].4 / 2.0)
          t.press_at(sx, sy)
          t.release(sx, sy)
        }
      }
      t.run_for(late + 400.0)
      for word in pick_panel_words {
        if t.find(word) is Some(_) {
          faults.push(at + ": \{word} shown")
        }
      }
      if !pick_let_go(sent) {
        faults.push(at + ": not let go of \{Repr(pick_asks(sent))} \{Repr(sent.filter(fn(m) { m.contains("unsubscribe") }))}")
      }
    }
  }
  assert_eq(faults, [])
}
