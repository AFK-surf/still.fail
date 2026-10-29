// The composer's hint (its placeholder) shows only on a composer at rest without the cursor: gone as its field takes
// the cursor, and never carried along as the composer changes shape (the user, 2026-10-30: 「focus 的时候不再显示
// placeholder」「placeholder 不再根据 composer 变高移动位置」).

///|
/// Where the composer's hint `hint` is drawn now, if any of it shows (its glyphs in its ink, at any strength).
fn hint_shown_at(t : @ui.Tester, hint : String) -> (Double, Double)? {
  let ink = @sf.theme().p.subtle >> 8
  match t.words().iter().find_first(fn(w) { w.0 == hint }) {
    Some((_, x, y, w, h, _)) => {
      let shown = t
        .drawn_glyphs()
        .iter()
        .any(fn(g) {
          g.0 >= x - 1.0 &&
          g.0 <= x + w + 1.0 &&
          g.1 >= y - 1.0 &&
          g.1 <= y + h + 1.0 &&
          g.2 >> 8 == ink &&
          (g.2 & 0xFFL) > 0L
        })
      if shown {
        Some((x, y))
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Frames for `ms`: where the hint showed in each it showed in.
fn hint_watch(t : @ui.Tester, hint : String, ms : Double) -> Array[(Double, Double)] {
  let seen = []
  let until = t.time() + ms
  while t.time() < until {
    t.frame()
    match hint_shown_at(t, hint) {
      Some(at) => seen.push(at)
      None => ()
    }
  }
  seen
}

///|
/// The hint shown from where it was before it was hidden only: nowhere else in any frame, and there at the end.
fn assert_hint_still(seen : Array[(Double, Double)], at : (Double, Double)) -> Unit raise {
  assert_true(seen.length() > 0, msg="the hint never came back")
  for s in seen {
    assert_true((s.0 - at.0).abs() < 0.5 && (s.1 - at.1).abs() < 0.5, msg="the hint at \{s}, not \{at}: \{seen}")
  }
}

///|
test "desk composer: its hint gone as its field takes the cursor, back once it is let go of where it was, never moving with the composer's shape" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls)
  t.draw()
  // (the cursor in it as it is first drawn, the keyboard at hand): not shown; let go of, a capsule, it is (saying
  // which key brings the cursor back: what it says then, the only words in it)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  assert_eq(hint_shown_at(t, "发消息"), None)
  t.ctx().blur()
  let rest = @sfpages.let_go_ms + @sfpages.morph_ms + @sf.hint_back_ms
  hint_watch(t, "发消息", rest) |> ignore
  let hint = t.words()[0].0
  let at = hint_shown_at(t, hint).unwrap()
  let (x, y) = t.find(hint).unwrap()
  t.tap(x, y)
  assert_true(t.ctx().editor_focused(@sfpages.composer_field_key))
  // opened to a box with the cursor in it: not shown at all, in any frame
  let opened = hint_watch(t, "发消息", @sfpages.morph_ms + @sf.hint_back_ms)
  assert_eq(opened, [])
  // let go of: a box a moment longer, then a capsule again; the hint only once it is one, where it was
  t.ctx().blur()
  let shut = hint_watch(t, hint, rest)
  assert_hint_still(shut, at)
  assert_true(hint_shown_at(t, hint) is Some(_))
}

///|
test "a phone's composer: its hint gone as its field takes the cursor, back once it is let go of where it was, never moving with the composer's shape" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.draw()
  let at = hint_shown_at(t, "发消息").unwrap()
  t.tap_text("发消息")
  let opened = hint_watch(t, "发消息", @sfpages.morph_ms + @sf.hint_back_ms)
  assert_eq(opened, [])
  t.ctx().blur()
  // (a box a moment longer, then a capsule again, as on a computer)
  let shut = hint_watch(t, "发消息", @sfpages.let_go_ms + @sfpages.morph_ms + @sf.hint_back_ms)
  assert_hint_still(shut, at)
}

///|
/// Whether what is drawn about (`x`, `y`) (an icon, a button's round: within `r` of it) is drawn whole, nothing of it
/// cut off.
fn drawn_whole_at(t : @ui.Tester, x : Double, y : Double, r : Double) -> Bool {
  let near = t
    .drawn_cut()
    .filter(fn(d) { d.1 >= x - r && d.1 + d.3 <= x + r && d.2 >= y - r && d.2 + d.4 <= y + r })
  near.length() > 0 &&
  near.iter().all(fn(d) {
    let (x0, y0, x1, y1) = d.5
    d.1 >= x0 - 0.5 && d.2 >= y0 - 0.5 && d.1 + d.3 <= x1 + 0.5 && d.2 + d.4 <= y1 + 0.5
  })
}

///|
test "a phone's composer opened by a tap keeps its ＋ and send whole on their way, its field beside them covering neither (the user, 2026-10-30: 「输入框盖住了加号和发送」)" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.draw()
  let side = @sf.theme().round.side
  t.tap_text("发消息")
  let until = t.time() + @sfpages.morph_ms
  while t.time() < until {
    let (px, py) = t.locate("icon:plus")[0]
    let (sx, sy) = t.locate("icon:arrow-up")[0]
    assert_true(drawn_whole_at(t, px, py, side / 2.0), msg="＋ cut at \{t.time()}")
    assert_true(drawn_whole_at(t, sx, sy, side / 2.0 + 1.0), msg="send cut at \{t.time()}")
    t.frame()
  }
}
