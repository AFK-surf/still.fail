// The shared switch row: its default switch-only reach and its optional whole-row reach, settings look, work mark and
// response to changes while it is mounted.

///|
fn switch_row_case(
  look : Look,
  platform : Int,
  row_press : Bool,
  settings : Bool,
  on : @signals.Signal[Bool],
  disabled : @signals.Signal[Bool],
  marked : @signals.Signal[Bool],
  turns : Array[Bool],
  built : Ref[Int],
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=if look == Wide { 700.0 } else { 320.0 }, h=300.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.lends(part_at, { look, section: false, list: false }) |> ignore
    group_node(root, fn(g) {
      switch_row_node(
        g,
        fn() { "Sharing" },
        fn() { on.get() },
        fn(value) { turns.push(value); on.set(value) },
        note=fn() { "Allow sharing" },
        disabled=fn() { disabled.get() },
        row_press~,
        settings~,
        before_switch=fn(end) {
          built.val += 1
          end.show(fn() { marked.get() }, fn(mark) { spinner_node(mark) |> ignore })
        },
      )
    })
  })
  t.draw()
  t
}

///|
fn switch_track(t : @ui.Tester, w : Double, h : Double) -> (Double, Double, Double, Double, Int64) raise {
  let tracks = t.drawn_rects().filter(fn(r) { r.2 == w && r.3 == h })
  assert_eq(tracks.length(), 1, msg="switch track: \{tracks}")
  tracks[0]
}

///|
test "a switch row's whole reach answers once at its title and at its switch, for a finger and a mouse at either page width" {
  for look in [Narrow, Wide] {
    for platform in [0, 2] {
      let on = @signals.signal(false)
      let disabled = @signals.signal(false)
      let marked = @signals.signal(false)
      let turns = []
      let t = switch_row_case(look, platform, true, true, on, disabled, marked, turns, Ref(0))
      let switches = t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" })
      assert_eq(switches.length(), 1)
      assert_eq(switches[0].check, Some(@ui.Check::Off))
      t.tap_text("Sharing")
      t.draw()
      assert_eq(turns, [true], msg="title, \{look}, \{platform}")
      let (x, y, w, h, _) = switch_track(t, 44.0, 26.0)
      t.tap(x + w / 2.0, y + h / 2.0)
      t.draw()
      assert_eq(turns, [true, false], msg="switch, \{look}, \{platform}")
      assert_eq(t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" }).length(), 1)
    }
  }
}

///|
test "the default row keeps its switch-only reach; a work mark can appear without disabling or rebuilding its switch" {
  let on = @signals.signal(false)
  let disabled = @signals.signal(false)
  let marked = @signals.signal(false)
  let turns = []
  let built = Ref(0)
  let t = switch_row_case(Wide, 0, false, false, on, disabled, marked, turns, built)
  let first = t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" })[0].id
  let strokes = fn() { t.drawn_instances().filter(fn(i) { i[5] == 10.0 }).length() }
  assert_eq(strokes(), 0)
  t.tap_text("Sharing")
  assert_eq(turns, [])
  marked.set(true)
  t.draw()
  assert_true(strokes() > 0, msg="the work mark is drawn")
  assert_eq(built.val, 1)
  assert_eq(t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" })[0].id, first)
  t.click(Switch, label="Sharing")
  assert_eq(turns, [true])
  marked.set(false)
  t.draw()
  assert_eq(strokes(), 0, msg="the work mark has left")
  assert_eq(built.val, 1)
  assert_eq(t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" })[0].id, first)
}

///|
test "the whole switch row has one keyboard and accessibility action, disabled while its caller says so" {
  let on = @signals.signal(false)
  let disabled = @signals.signal(false)
  let marked = @signals.signal(false)
  let turns = []
  let t = switch_row_case(Narrow, 0, true, true, on, disabled, marked, turns, Ref(0))
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Sharing"))
  t.enter()
  t.key(@ui.key_space)
  t.act(Switch, Activate, label="Sharing")
  assert_eq(turns, [true, false, true])
  disabled.set(true)
  marked.set(true)
  t.draw()
  let said = t.semantics().filter(fn(s) { s.role == Switch && s.label == "Sharing" })
  assert_eq(said.length(), 1)
  assert_true(said[0].disabled)
  assert_true(t.focused().map(fn(s) { s.label }) != Some("Sharing"))
  t.tap_text("Sharing")
  let (x, y, w, h, _) = switch_track(t, 44.0, 26.0)
  t.tap(x + w / 2.0, y + h / 2.0)
  t.act(Switch, Activate, label="Sharing")
  assert_eq(turns, [true, false, true])
  disabled.set(false)
  t.draw()
  t.tap_text("Sharing")
  assert_eq(turns, [true, false, true, false])
}

///|
test "a whole switch row held by a finger turns once on release, and disabling it while held cancels the press" {
  let on = @signals.signal(false)
  let disabled = @signals.signal(false)
  let turns = []
  let t = switch_row_case(Narrow, 2, true, true, on, disabled, @signals.signal(false), turns, Ref(0))
  let (x, y, w, h, _) = switch_track(t, 44.0, 26.0)
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.long_press_ms * 2.0)
  assert_true(t.drawn_shadows().length() > 0, msg="the held row shows its ripple")
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(turns, [true])
  assert_eq(t.haptics(), [@ui.TextHandleMove])
  t.press_at(x + w / 2.0, y + h / 2.0)
  disabled.set(true)
  t.draw()
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(turns, [true])
}

///|
test "settings switch: 44 by 26, a 20 point white knob inset 3, the settings colours and switch motion" {
  for platform in [0, 2] {
    let on = @signals.signal(false)
    let t = switch_row_case(Narrow, platform, true, true, on, @signals.signal(false), @signals.signal(false), [], Ref(0))
    let off = switch_track(t, 44.0, 26.0)
    assert_eq(off.4, theme().p.line)
    let knobs = fn() { t.drawn_rects().filter(fn(r) { r.2 == 20.0 && r.3 == 20.0 && r.4 == 0xFFFFFFFFL }) }
    assert_eq(knobs().length(), 1)
    assert_eq((knobs()[0].0 - off.0, knobs()[0].1 - off.1), (3.0, 3.0))
    assert_eq(t.drawn_shadows().length(), 0)
    on.set(true)
    t.draw()
    t.run_for(@kit.switch_ms / 2.0)
    let middle = knobs()[0].0 - off.0
    assert_true(middle > 3.0 && middle < 21.0, msg="knob halfway: \{middle}")
    t.run_for(@kit.switch_ms / 2.0)
    assert_eq(knobs()[0].0 - off.0, 21.0)
    assert_eq(switch_track(t, 44.0, 26.0).4, theme().p.green)
  }
}

///|
test "settings switch with reduced motion: the knob and track are at their new value in the frame of the change" {
  let on = @signals.signal(false)
  let t = switch_row_case(Narrow, 0, true, true, on, @signals.signal(false), @signals.signal(false), [], Ref(0))
  t.set_reduce_motion(true)
  on.set(true)
  t.draw()
  let track = switch_track(t, 44.0, 26.0)
  let knobs = t.drawn_rects().filter(fn(r) { r.2 == 20.0 && r.3 == 20.0 && r.4 == 0xFFFFFFFFL })
  assert_eq(knobs.length(), 1)
  assert_eq((knobs[0].0 - track.0, track.4), (21.0, theme().p.green))
}

///|
test "a settings switch with a request under way is disabled without fading its on colour or white knob" {
  let t = switch_row_case(Narrow, 2, true, true, @signals.signal(true), @signals.signal(true), @signals.signal(true), [], Ref(0))
  assert_eq(switch_track(t, 44.0, 26.0).4, theme().p.green)
  let knobs = t.drawn_rects().filter(fn(r) { r.2 == 20.0 && r.3 == 20.0 && r.4 == 0xFFFFFFFFL })
  assert_eq(knobs.length(), 1)
  assert_true(t.get(Switch, label="Sharing").disabled)
}

///|
test "settings switch row words keep the settings sizes, regular weight and balanced notes at both widths" {
  let title = "A long sharing title with enough words to need several lines"
  let note = "A longer explanation of sharing which also needs room to wrap beside the switch"
  for look in [Narrow, Wide] {
    for wrap_title in [true, false] {
      for in_words in [true, false] {
        let t = @ui.Tester::new(fn(_c) {  }, w=320.0, h=400.0)
        t.check_looks(false)
        @ui.set_view_app(fn(root) {
          root.lends(part_at, { look, section: false, list: false }) |> ignore
          group_node(root, fn(g) {
            switch_row_node(g, fn() { title }, fn() { false }, fn(_) {  }, note=fn() { note }, settings=true, wrap_title~, in_words~)
          })
        })
        t.draw()
        let drawn = @ui.view_tree().unwrap().drawn()
        let titles = drawn.filter(fn(d) { d.words == title })
        let notes = drawn.filter(fn(d) { d.words == note })
        assert_eq(titles.length(), 1)
        assert_eq(notes.length(), 1)
        let tw = titles[0].words_look
        let nw = notes[0].words_look
        let th = @ui.tree_theme()
        let (title_size, _) = th.text_size(if look is Wide && !wrap_title { Ui } else { Body })
        let (note_size, _) = th.text_size(if look is Wide { Caption } else { Meta })
        assert_eq((tw.size, tw.weight, tw.wrap), (title_size, 400, wrap_title))
        assert_eq((nw.size, nw.weight, nw.wrap, nw.balance), (note_size, 400, true, true))
        assert_eq(notes[0].ink, th.color(Muted))
        if wrap_title {
          assert_true(titles[0].h > tw.line, msg="long title wraps at \{look}")
        }
        assert_true(notes[0].h > nw.line, msg="long note wraps at \{look}")
        let (x, _, _, _, _) = switch_track(t, 44.0, 26.0)
        assert_true(titles[0].x + titles[0].w <= x, msg="title stays clear of switch at \{look}")
      }
    }
  }
}
