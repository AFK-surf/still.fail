// The archive policy's dialogs (automatic_decisions.mbt policy_dialog: what they hold and their buttons nodes, through
// @sf.panel_nodes), a sheet on 小屏 and in the middle of the window on 大屏: each of their words, the choice's track and
// thumb and 保存 where the old bodies drew them (recorded from those, before they were made nodes, on the made-up
// policy: its first option, 已完成, and its words); 不推荐 pressed where it is drawn: the option's draft told so, the
// thumb gone to it.

///|
/// What the old option's dialog showed of 已完成 (its words, the choice's track, its thumb, 保存's box), on a phone and on
/// a wide window.
fn pol_option_was(w : Double) -> (Array[(String, Double, Double, Double, Double)], (Double, Double, Double, Double), (Double, Double, Double, Double), (Double, Double, Double, Double)) {
  if w < pol_wide {
    (
    [
      ("已完成", 24.0, 412.8, 48.0, 24.0),
      ("名称", 24.0, 446.8, 30.0, 20.0),
      ("判定为此项的情况", 24.0, 526.8, 120.0, 20.0),
      ("是否推荐归档", 24.0, 646.0, 90.0, 20.0),
      ("推荐归档", 82.5, 679.2, 56.0, 19.6),
      ("不推荐", 258.5, 679.2, 42.0, 19.6),
      ("最近 7 天判定为此项的 chat", 24.0, 724.0, 342.0, 18.0),
      ("夜里的构建又失败了", 24.0, 748.0, 342.0, 20.0),
      ("还有 11 个", 24.0, 774.0, 342.0, 18.0),
      ("删除", 49.75, 847.0, 30.0, 22.0),
      ("取消", 212.75, 847.0, 30.0, 22.0),
      ("保存", 310.25, 847.0, 30.0, 22.0),
    ],
    (24.0, 672.0, 342.0, 34.0),
    (26.0, 674.0, 169.0, 30.0),
    (280.5, 840.0, 89.5, 36.0),
    )
  } else {
    (
    [
      ("已完成", 404.0, 217.9, 66.0, 30.0),
      ("名称", 404.0, 266.9, 26.0, 20.0),
      ("判定为此项的情况", 404.0, 344.9, 104.0, 20.0),
      ("是否推荐归档", 404.0, 470.1, 78.0, 20.0),
      ("推荐归档", 419.0, 505.0, 52.0, 18.2),
      ("不推荐", 503.5, 505.0, 39.0, 18.2),
      ("最近 7 天判定为此项的 chat", 404.0, 556.1, 472.0, 18.0),
      ("夜里的构建又失败了", 404.0, 580.1, 472.0, 20.0),
      ("还有 11 个", 404.0, 606.1, 472.0, 18.0),
      ("删除", 420.0, 656.1, 26.0, 20.0),
      ("取消", 768.0, 656.1, 26.0, 20.0),
      ("保存", 834.0, 656.1, 26.0, 20.0),
    ],
    (404.0, 496.1, 160.0, 36.0),
    (407.0, 499.1, 76.0, 30.0),
    (818.0, 648.1, 58.0, 36.0),
    )
  }
}

///|
/// Past what width the page is the wide window's here.
let pol_wide : Double = 1000.0

///|
/// What the old words' dialog showed (its words), on a phone and on a wide window.
fn pol_text_was(w : Double) -> Array[(String, Double, Double, Double, Double)] {
  if w < pol_wide {
    [
    ("归档策略", 24.0, 542.8, 64.0, 24.0),
    ("决策模型判断 chat 时先读取这段说明；选项逐项列在下方", 24.0, 576.8, 342.0, 20.0),
    ("取消", 164.0, 847.0, 30.0, 22.0),
    ("保存", 294.0, 847.0, 30.0, 22.0),
    ]
  } else {
    [
    ("归档策略", 344.0, 285.9, 88.0, 30.0),
    ("决策模型判断 chat 时先读取这段说明；选项逐项列在下方", 344.0, 322.9, 592.0, 20.0),
    ("取消", 828.0, 588.1, 26.0, 20.0),
    ("保存", 894.0, 588.1, 26.0, 20.0),
    ]
  }
}

///|
/// How far apart what is drawn may be from where the old body drew it (its layout's rounding).
let pol_near : Double = 0.3

///|
/// Whether `a` and `b` are drawn alike: the same words, each where the other is.
fn pol_words_near(a : Array[(String, Double, Double, Double, Double)], b : Array[(String, Double, Double, Double, Double)]) -> Bool {
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(fn(p) {
    let (x, y) = p
    x.0 == y.0 &&
    (x.1 - y.1).abs() <= pol_near &&
    (x.2 - y.2).abs() <= pol_near &&
    (x.3 - y.3).abs() <= pol_near &&
    (x.4 - y.4).abs() <= pol_near
  })
}

///|
fn pol_box_near(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  (a.0 - b.0).abs() <= pol_near && (a.1 - b.1).abs() <= pol_near && (a.2 - b.2).abs() <= pol_near && (a.3 - b.3).abs() <= pol_near
}

///|
/// The words drawn now but not in `under` (what the page drew with no dialog over it), in the order of where they are.
fn pol_words_over(seen : Array[(String, Double, Double, Double, Double)], under : Array[(String, Double, Double, Double, Double)]) -> Array[(String, Double, Double, Double, Double)] {
  let out = seen.filter(fn(w) { !under.contains(w) })
  out.sort_by(fn(a, b) { if (a.2 - b.2).abs() > pol_near { a.2.compare(b.2) } else { a.1.compare(b.1) } })
  out
}

///|
/// The words the Tester draws now (whole: none faded out).
fn pol_words_drawn(t : @ui.Tester) -> Array[(String, Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.5 > 0.0 }).map(fn(w) { (w.0, w.1, w.2, w.3, w.4) })
}

///|
/// How long a dialog takes to come in and go at most here (a sheet's way as far as the window, its scrim's fade).
fn pol_way_ms() -> Double {
  @ui.move_most_ms * 2.0
}

///|
/// The policy's page `w` wide with `which` of its dialogs put up (fx_policy_up's: "option" its first option's, "text"
/// its words'), the core's calls recorded.
fn pol_tester(w : Double, platform : Int, which : String, calls : Array[(String, String)]) -> @ui.Tester {
  setting_tester(AutoPolicy("ws1/st1"), w, platform~, ready=fn() { fx_policy_up.val = which }, over=fn(s) {
    {
      ..s,
      call: fn(name, params, done) {
        calls.push((name, params.stringify()))
        (s.call)(name, params, done)
      },
    }
  })
}

///|
test "归档策略's option's dialog, its body nodes, on a phone and on a wide window: its words, its choice and 保存 where the old body's were; 不推荐 pressed where it is drawn: the draft told, the thumb on it" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let at = "\{w}"
    let calls = []
    let t = pol_tester(w, platform, "option", calls)
    t.run_for(pol_way_ms())
    let seen = pol_words_drawn(t)
    let (words_was, track_was, thumb_was, save_was) = pol_option_was(w)
    let boxes = t.drawn_rects().map(fn(r) { (r.0, r.1, r.2, r.3) })
    assert_true(boxes.iter().any(fn(b) { pol_box_near(b, track_was) }), msg="\{at}: its choice's track")
    assert_true(boxes.iter().any(fn(b) { pol_box_near(b, thumb_was) }), msg="\{at}: its thumb under 推荐归档")
    assert_true(boxes.iter().any(fn(b) { pol_box_near(b, save_was) }), msg="\{at}: 保存")
    // 不推荐 pressed where it is drawn: the option's draft told it is kept, the thumb gone to it
    let keep = words_was.iter().find_first(fn(x) { x.0 == "不推荐" }).unwrap()
    t.tap(keep.1 + keep.3 / 2.0, keep.2 + keep.4 / 2.0)
    t.run_for(pol_way_ms())
    assert_true(
      calls.iter().any(fn(c) { c.0 == "automaticDecisions.policy.edit" && c.1.contains("\"archive\":false") }),
      msg="\{at}: told \{Repr(calls)}",
    )
    let moved = (track_was.0 + track_was.2 - (thumb_was.0 - track_was.0) - thumb_was.2, thumb_was.1, thumb_was.2, thumb_was.3)
    let boxes = t.drawn_rects().map(fn(r) { (r.0, r.1, r.2, r.3) })
    assert_true(boxes.iter().any(fn(b) { pol_box_near(b, moved) }), msg="\{at}: its thumb under 不推荐")
    t.key(@ui.key_escape)
    t.run_for(pol_way_ms())
    assert_false(@sf.presenting(), msg="\{at}: closed")
    let over = pol_words_over(seen, pol_words_drawn(t))
    assert_true(pol_words_near(over, words_was), msg="\{at}: \{Repr(over)}")
  }
}

///|
test "归档策略's words' dialog, its body nodes, on a phone and on a wide window: its words and its buttons where the old body's were" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let t = pol_tester(w, platform, "text", [])
    t.run_for(pol_way_ms())
    let seen = pol_words_drawn(t)
    t.key(@ui.key_escape)
    t.run_for(pol_way_ms())
    let over = pol_words_over(seen, pol_words_drawn(t))
    assert_true(pol_words_near(over, pol_text_was(w)), msg="\{w}: \{Repr(over)}")
  }
}
