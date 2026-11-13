// 用量 and 价目表 made once on a large screen (the pane off the tape) and on the tape at its widths: what each holds the
// tree's own, 用量's days and share where its head or its bar has them, with keyboard and mouse and with a finger.

///|
test "用量 and 价目表 made once wide and on the tape: what each holds the tree's own; 用量's days and share once each, at its head's or bar's line" {
  for case in [(0, 1280.0), (2, 1280.0), (0, 1800.0), (2, 600.0), (0, 700.0), (2, 839.0)] {
    let (platform, w) = case
    let t = large_about_tester(true, platform, w~, mode="settings-usage")
    let at = "用量 at \{Repr(case)}"
    assert_true(app.nav.top() == Setting(@settings.Route::Usage), msg=at)
    let own = tree_words_drawn()
    for word in ["$118", "最花钱的对话", "各设备的工作量", "7 天", "30 天"] {
      assert_true(own.iter().any(fn(o) { o.contains(word) }), msg="\{word} not the tree's own at \{at}: \{Repr(own)}")
    }
    let share = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == @sf.t("web-main.stations.shareCard") && !s.hidden })
    assert_eq(share.length(), 1, msg="its share at \{at}")
    guard t.rect_of("7 天") is Some((_, dy, _, dh)) else { fail("no days at \{at}") }
    assert_true((share[0].rect.1 + share[0].rect.3 / 2.0 - (dy + dh / 2.0)).abs() < 4.0, msg="share and days on one line at \{at}")
    let _ = large_about_tester(true, platform, w~, mode="settings-prices")
    let own = tree_words_drawn()
    assert_true(own.iter().any(fn(o) { o.contains("Willow") }), msg="价目表's card the tree's own at \{Repr(case)}: \{Repr(own)}")
  }
}

///|
/// How late the made-up core answers each subscription as a choice of 用量's is pressed (ms): at once, a frame late,
/// and on to well past the 300 ms nothing may look like loading in.
let usage_press_lates : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// The choices of 用量 pressed in turn, each from what the one before left: its label, the days and split the core is
/// then asked for ("" split: the page's own, the core's choice), and words the days' card shows once the page reads
/// them (the fixture's: the cost of those days, a part of that split named).
let usage_press_choices : Array[(String, Int, String, String)] = [
  ("30 天", 30, "", "$486"),
  ("7 天", 7, "", "$118"),
  ("按模型", 7, "models", "GPT-6"),
  ("按人", 7, "people", "Ana"),
]

///|
/// 用量 in screen `s` over the settings' fixture (settings-usage) answering through the app's client of its core, each
/// subscription as late as `pace` says when it is asked (the page opened at once, the test's own setup), as a device's
/// host draws it (check_looks off), at rest: what the client sent and was told, to `heard`.
fn usage_press_tester(s : Screen, pace : Ref[Double], heard : Array[String]) -> @ui.Tester {
  new_run()
  let src = round_trip_again(fixture_app("settings-usage"), 0.0, heard=fn(h) { heard.push(h) }, late=fn(_, _) { pace.val })
  if !(app.nav.top() is Setting(Usage)) {
    app.nav.push(Setting(@settings.Route::Usage))
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.draw()
  t.run_for(@ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// The choice `label` brought into the window's middle by the wheel over the page (the days at its head, 按人 / 按模型
/// on the days' card), at rest after: where it is to be pressed.
fn usage_choice_shown(t : @ui.Tester, s : Screen, label : String) -> (Double, Double) {
  let mut was = -1.0e9
  for _ in 0..<16 {
    let r = match t.query(Radio, label~) {
      Some(r) => r.rect
      // (the page's head scrolled off with its list: up to it)
      None => {
        t.wheel(s.w / 2.0, s.h / 2.0, -300.0)
        t.run_for(@ui.move_most_ms)
        continue
      }
    }
    let mid = r.1 + r.3 / 2.0
    // (in the window's middle, or in the window where the wheel moves it no more: the page's head at its top)
    let shown = r.1 >= 0.0 && r.1 + r.3 <= s.h - 120.0
    if shown && (r.1 >= 100.0 || r.1 == was) {
      t.run_for(@ui.move_most_ms + 1000.0)
      t.ways_set_out() |> ignore
      return match t.query(Radio, label~) {
        Some(r) => (r.rect.0 + r.rect.2 / 2.0, r.rect.1 + r.rect.3 / 2.0)
        None => @halt.saying("\{s.name}: \"\{label}\" gone")
      }
    }
    was = r.1
    t.wheel(s.w / 2.0, s.h / 2.0, @cmp.maximum(-300.0, @cmp.minimum(300.0, mid - s.h / 2.0)))
    t.run_for(@ui.move_most_ms)
  }
  @halt.saying("\{s.name}: \"\{label}\" not brought into view")
}

///|
/// Every word drawn now and where (Tester::words: the old view's and the window's tree's alike, each frame; not
/// text_runs, which has an old view's words only in a frame that painted it: the settings' side list on 大屏 was in the
/// press's frame of one press and in no frame round it), the choices' own words left out (what the pressed control
/// answers with), none faded to nothing.
fn usage_words_placed(t : @ui.Tester) -> Array[String] {
  t
  .words()
  .filter(fn(w) { w.5 > 0.01 && !usage_press_choices.iter().any(fn(c) { c.0 == w.0 }) })
  .map(fn(w) { "\{w.0}@\{(w.1 * 10.0).round() / 10.0},\{(w.2 * 10.0).round() / 10.0}" })
}

///|
/// A frame's words (`now`, at +`ms` from the press) that are not as in `want`, a short line each: what is gone or moved
/// (where it was), what is new or moved (where it is), eight at most of each.
fn usage_words_told(at : String, ms : Double, want : Array[String], now : Array[String]) -> Unit {
  for w in want.filter(fn(w) { !now.contains(w) }).iter().take(8) {
    println("USAGE_WORD \{at} +\{ms.round()} was \{w}")
  }
  for w in now.filter(fn(w) { !want.contains(w) }).iter().take(8) {
    println("USAGE_WORD \{at} +\{ms.round()} now \{w}")
  }
}

///|
/// What the client subscribed to of `usage` in `heard` from its `from`th: each its days, its split ("" none said),
/// whether it said a part or a day seen alone, and whether it was let go after.
fn usage_subscribed(heard : Array[String], from : Int) -> Array[(Double, String, Bool, Bool)] {
  let out : Array[(Int, Double, String, Bool)] = []
  let gone : Map[Int, Bool] = Map([])
  for i in from..<heard.length() {
    let h = heard[i]
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    let id = n.to_int()
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(s)), _) if s.get("topic") == Some(Json::string("usage")) => {
        let days = match s.get("days") {
          Some(Number(d, ..)) => d
          _ => -1.0
        }
        let split = match s.get("split") {
          Some(String(x)) => x
          _ => ""
        }
        out.push((id, days, split, s.contains("only") || s.contains("day")))
      }
      (_, Some(_)) => gone[id] = true
      _ => ()
    }
  }
  out.map(fn(o) { (o.1, o.2, o.3, gone.contains(o.0)) })
}

///|
/// 用量's days (30 天, 7 天) and its split (按模型, 按人) pressed in turn, 小屏 by touch and 大屏 with a mouse, the page opened
/// over a core answering at once and each press over one answering 0 to 700 ms late (sfpages usage_node's press,
/// sfbase's switch_answered): from the press till what the page reads for it comes, in every frame as a host draws it,
/// every word but the choice's own where it was at the press and no bones drawn; from the frame it comes in, every word
/// where it is at rest; nothing sets out after the press's own moment; the choice shows what was pressed from the press;
/// what the press asked (the view of those days and split; its chart's, nothing seen alone, the same) asked once and held
/// by the page at rest.
test "用量's days and split pressed: the page as it was till what it reads for them comes, then whole" {
  for s in [daily_small, daily_large] {
    for ms in usage_press_lates {
      let heard : Array[String] = []
      let pace = Ref(0.0)
      let t = usage_press_tester(s, pace, heard)
      pace.val = ms
      for choice in usage_press_choices {
        let (label, days, split, read_anew) = choice
        let at = "\{s.name}, \{ms} ms, \{label}"
        let (x, y) = usage_choice_shown(t, s, label)
        let before = usage_words_placed(t)
        let bones_before = t.bones_drawn()
        let asked_from = heard.length()
        let from = t.time()
        t.tap(x, y)
        let frames : Array[(Double, Array[String])] = []
        let faults : Array[String] = []
        let ways : Array[String] = []
        let n = ((ms * 2.0 + @ui.move_most_ms * 2.0) / @ui.frame_period_default).ceil().to_int()
        for i in 0..=n {
          if i > 0 {
            t.run_for(@ui.frame_period_default)
          }
          let now = t.time() - from
          for w in t.ways_set_out() {
            if w.at > from + 0.5 {
              ways.push("\{w.kind} +\{(w.at - from).round()} ms \{w.made} \{w.part}")
            }
          }
          if t.bones_drawn() > bones_before {
            faults.push("+\{now.round()} ms: \{t.bones_drawn()} bones drawn, \{bones_before} before the press")
          }
          if t.query(Radio, label~, checked=On) is None {
            faults.push("+\{now.round()} ms: \{label} not shown chosen")
          }
          frames.push((now, usage_words_placed(t)))
        }
        let rest = usage_words_placed(t)
        // (as at the press till what it reads comes, then as at rest from that frame on)
        let mut came = -1.0
        for f in frames {
          if came < 0.0 && f.1 == rest {
            came = f.0
          } else if came < 0.0 && f.1 != before {
            usage_words_told(at, f.0, before, f.1)
            faults.push("+\{f.0.round()} ms: words not where they were at the press")
          } else if came >= 0.0 && f.1 != rest {
            usage_words_told(at, f.0, rest, f.1)
            faults.push("+\{f.0.round()} ms: words not where they rest, after it came")
          }
        }
        for f in faults {
          println("USAGE_FAULT \{at} \{f}")
        }
        let asked = usage_subscribed(heard, asked_from)
        let said = asked.map(fn(a) { "days \{a.0} split \{a.1}\{if a.2 { " narrowed" } else { "" }}\{if a.3 { " let go" } else { "" }}" })
        println("USAGE_PRESS \{at}: read anew at +\{came.round()} ms, asked after the press \{Repr(said)}, ways \{Repr(ways)}")
        assert_eq(faults, [], msg="\{at}: every frame from the press")
        assert_eq(ways, [], msg="\{at}: ways set out after the press")
        // (the view of those days and split, its chart's the same: once, held)
        // (what it reads for them at rest: on the days' card, brought into view)
        usage_choice_shown(t, s, "按人") |> ignore
        assert_true(t.find(read_anew) is Some(_), msg="\{at}: \{read_anew} on the days' card at rest")
        // (nothing seen alone: the view and its chart one ask, the same topic and params)
        assert_eq(asked.length(), 1, msg="\{at}: asked \{Repr(said)}")
        for a in asked {
          assert_true(a.0 == days.to_double() && a.1 == split && !a.2 && !a.3, msg="\{at}: \{Repr(said)} asked and held")
        }
      }
    }
  }
}
