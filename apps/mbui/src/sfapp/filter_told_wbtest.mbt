// The filter over 连接's list on 大屏 (sfpages' connects.mbt mine_filter: all of them or the viewer's) dismissed by the
// hand: Escape, a press on the page, at that input's moment; its button pressed again with it open, then Escape at
// once, closed and staying closed.

///|
/// 大屏, a mouse's, 连接 open (its settings page).
fn connects_tester() -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  open_setting("connects")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The filter's button as it is read out now (its words: what it shows).
fn connects_filter_label() -> String {
  @sf.t("web-main.filter.connects.named", args=[("named", @sf.t("web-main.filter.all"))])
}

///|
/// The filter's menu opened from its button, dismissed by `how` (as the host hands it on, no frame after it): whether
/// it is open then, once a frame is drawn, as the button opens it again and a frame after.
fn filter_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = connects_tester()
  guard t.query(Button, label=connects_filter_label()) is Some(s) else {
    fail("no filter: \{t.semantics().map(fn(s) { s.label }).filter(fn(l) { l != "" }).join("|")}")
  }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @sfpages.mine_filter_shown("connects-filter") }
  t.tap(x, y)
  t.frame()
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  t.tap(x, y)
  t.frame()
  seen.push(open())
  t.draw()
  seen.push(open())
  seen
}

///|
test "大屏: 连接's filter dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(filter_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: 连接's filter dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = filter_dismissed(fn(t) {
    t.touch_at(0, 1200.0, 760.0, t.time())
    down.push(@sfpages.mine_filter_shown("connects-filter"))
    t.touch_at(2, 1200.0, 760.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: 连接's filter pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(connects_tester(), connects_filter_label(), fn() { @sfpages.mine_filter_shown("connects-filter") }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}

///|
/// How late the made-up core answers each subscription as 连接's filter is pressed (ms): at once, a frame late, and on
/// to well past the 300 ms nothing may look like loading in.
let connects_press_lates : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// 连接 in screen `s` over the settings' fixture (settings-connects) answering through the app's client of its core,
/// each subscription as late as `pace` says when it is asked (the page opened at once, the test's own setup), as a
/// device's host draws it (check_looks off), at rest: what the client sent and was told, to `heard`.
fn connects_press_tester(s : Screen, pace : Ref[Double], heard : Array[String]) -> @ui.Tester {
  new_run()
  let src = round_trip_again(fixture_app("settings-connects"), 0.0, heard=fn(h) { heard.push(h) }, late=fn(_, _) { pace.val })
  if !(app.nav.top() is Setting(Connects(""))) {
    app.nav.push(Setting(@settings.Route::Connects("")))
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  t.draw()
  t.run_for(@ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// Every word drawn now and where (to a tenth of a point), but the filter's own (what it shows, its menu's), none faded
/// to nothing.
fn connects_press_words(t : @ui.Tester) -> Array[String] {
  let own = ["全部", "我的", "全部连接", "筛选连接"]
  t
  .words()
  .filter(fn(w) { w.5 > 0.01 && !own.contains(w.0) })
  .map(fn(w) { "\{w.0} @\{(w.1 * 10.0).round() / 10.0},\{(w.2 * 10.0).round() / 10.0}" })
}

///|
/// 连接's filter (sfpages connects.mbt, by sfbase's switch_answered) pressed to 我的, then back to 全部, 小屏 by touch,
/// 中屏 and 大屏, the page opened over a core answering at once and each press over one answering 0 to 700 ms late:
/// from the press till what the page reads for it comes, in every frame as a host draws it, every word but the
/// filter's own where it was at the press and no bones drawn; from the frame it comes in, every word where it is at
/// rest; nothing sets out after the press's own moment; the filter names what was pressed from the press; what the
/// press asked (the connects for that filter) asked once and held by the page at rest.
test "连接's filter pressed: the list as it was till the connects for it come, then whole" {
  for s in [daily_small, daily_medium, daily_large] {
    for ms in connects_press_lates {
      let heard : Array[String] = []
      let pace = Ref(0.0)
      let t = connects_press_tester(s, pace, heard)
      for pick in [(true, "我的", "我的"), (false, "全部连接", "全部")] {
        let (mine, item, named) = pick
        let at = "\{s.name}, \{ms} ms, \{item}"
        let shown_label = @sf.t("web-main.filter.connects.named", args=[("named", if mine { "全部" } else { "我的" })])
        guard t.query(Button, label=shown_label) is Some(f) else {
          fail("\{at}: no filter \{shown_label}: \{t.semantics().map(fn(s) { s.label }).filter(fn(l) { l != "" }).join("|")}")
        }
        t.tap(f.rect.0 + f.rect.2 / 2.0, f.rect.1 + f.rect.3 / 2.0)
        t.run_for(@ui.move_most_ms)
        let items = t.words().filter(fn(w) { w.0 == item && w.5 > 0.5 })
        guard items.length() > 0 else { fail("\{at}: no \{item} in the menu") }
        let target = items[items.length() - 1]
        t.ways_set_out() |> ignore
        let before = connects_press_words(t)
        let bones_before = t.bones_drawn()
        let asked_from = heard.length()
        pace.val = ms
        let from = t.time()
        t.tap(target.1 + target.3 / 2.0, target.2 + target.4 / 2.0)
        let frames : Array[(Double, Array[String])] = []
        let faults : Array[String] = []
        let ways : Array[String] = []
        let want_label = @sf.t("web-main.filter.connects.named", args=[("named", named)])
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
          if t.query(Button, label=want_label) is None {
            faults.push("+\{now.round()} ms: the filter not naming \{named}")
          }
          frames.push((now, connects_press_words(t)))
        }
        let rest = connects_press_words(t)
        let mut came = -1.0
        for f in frames {
          if came < 0.0 && f.1 == rest {
            came = f.0
          } else if came < 0.0 && f.1 != before {
            faults.push(
              "+\{f.0.round()} ms: not as at the press: gone \{before.filter(fn(w) { !f.1.contains(w) }).iter().take(6).collect().join(" | ")}, new \{f.1.filter(fn(w) { !before.contains(w) }).iter().take(6).collect().join(" | ")}",
            )
          } else if came >= 0.0 && f.1 != rest {
            faults.push(
              "+\{f.0.round()} ms: not as at rest after it came: gone \{rest.filter(fn(w) { !f.1.contains(w) }).iter().take(6).collect().join(" | ")}, new \{f.1.filter(fn(w) { !rest.contains(w) }).iter().take(6).collect().join(" | ")}",
            )
          }
        }
        for f in faults.iter().take(6) {
          println("CONNECTS_FAULT \{at} \{f}")
        }
        println("CONNECTS_PRESS \{at}: come at +\{came.round()} ms, ways after the press \{Repr(ways)}")
        assert_eq(faults, [], msg="\{at}: every frame from the press")
        assert_eq(ways, [], msg="\{at}: ways set out after the press")
        assert_eq(@settings.connects_mine.val, mine, msg="\{at}: the page reads it at rest")
        assert_true(t.find("星火助手") is Some(_), msg="\{at}: its connects at rest")
        // (all of them: asked again where the client let them go as 我的 came, else held still)
        let (asked, let_go) = asked_held(heard[asked_from:].to_owned(), "connects", { "scope": Json::string("ws1"), "mine": Json::boolean(mine) })
        assert_true(let_go == 0 && (asked == 1 || (!mine && asked == 0)), msg="\{at}: the connects for it asked \{asked}, let go \{let_go}")
        pace.val = 0.0
      }
    }
  }
}
