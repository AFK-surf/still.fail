// ⌘F in an open chat on 大屏 (sfpages' find.mbt find_bar, find_ask, find_move; sfbase's chat_list.mbt go_tos): its bar
// over the chat, what is typed looked for 120 ms after the last key (chat.find), where the reader is among what was
// found as the core says (chat.find.go: Enter the next, ⇧Enter and ↑ the one before), 无结果 for nothing; a message
// found out of the chat's window has the window moved about it (chat.around), once.

///|
/// The fixture's chat on 大屏 with a Mac's keys, its calls kept in `calls` and answered as the made-up core answers them;
/// `found`: what chat.find answers instead (None: the made-up core's own finding).
fn find_chat_tester(calls : Array[Made], found? : Json? = None) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match (name, found) {
        ("chat.find", Some(f)) => done(Ok(f))
        _ => (base.call)(name, params, done)
      }
    },
  }
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn find_typed(t : @ui.Tester, words : String) -> Unit {
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.type_text(words)
  t.draw()
}

///|
test "⌘F opens the chat's find bar; what is typed is looked for only 120 ms after the last key (chat.find), in the chat's thread" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  assert_true(t.find("在对话中查找") is None)
  t.key(@ui.key_of_char('f'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("在对话中查找") is Some(_))
  assert_true(@sfpages.find_chat() != "")
  t.type_text("截图")
  t.draw()
  assert_eq(named(calls, "chat.find").length(), 0)
  t.run_for(@sfpages.find_typing_ms)
  t.draw()
  let asked = named(calls, "chat.find")
  assert_true(asked.length() >= 1)
  assert_eq(text(Some(asked[0].params), "query"), "截图")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
}

///|
test "⌘F: what is found counted as the core says where the reader is (n/total); Enter the next (chat.find.go by 1), ⇧Enter the one before (by -1)" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  find_typed(t, "截图")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  let counted = fn() { t.words().filter(fn(w) { w.5 > 0.0 && w.0.contains("/") && w.0.length() <= 5 }).map(fn(w) { w.0 }) }
  assert_true(counted().length() == 1, msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  let was = counted()[0]
  let goes = named(calls, "chat.find.go").length()
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  let moved = named(calls, "chat.find.go")
  assert_eq(moved.length(), goes + 1)
  assert_eq(number(Some(moved[moved.length() - 1].params), "by"), 1.0)
  assert_true(counted()[0] != was, msg="\{was} \{Repr(counted())}")
  t.key(@ui.key_code_enter, mods=@ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  let moved = named(calls, "chat.find.go")
  assert_eq(number(Some(moved[moved.length() - 1].params), "by"), -1.0)
  assert_eq(counted()[0], was)
}

///|
test "⌘F: words no message has say 无结果, and its ways up and down are not pressed" {
  let calls : Array[Made] = []
  let t = find_chat_tester(calls)
  find_typed(t, "没有这个词")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("无结果") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  let goes = named(calls, "chat.find.go").length()
  t.click(Button, label="下一个")
  t.draw()
  assert_eq(named(calls, "chat.find.go").length(), goes)
}

///|
test "⌘F: a message found out of the chat's window has the window moved about it (chat.around by its seq), asked once, no page before asked for it" {
  let calls : Array[Made] = []
  // (found in the page before the chat's first: seq -98)
  let t = find_chat_tester(calls, found=Some({
    "words": ["构建脚本"],
    "hits": [{ "seq": -98, "count": 1 }],
    "held": 30,
    "of": 30,
    "whole": true,
  }))
  find_typed(t, "构建脚本")
  t.run_for(@sfpages.find_typing_ms)
  for _ in 0..<4 {
    t.run_for(@ui.move_most_ms)
  }
  let around = named(calls, "chat.around")
  assert_eq(around.length(), 1, msg="\{Repr(calls.map(fn(m) { m.name }))}")
  assert_eq(number(Some(around[0].params), "seq"), -98.0)
  assert_eq(number(Some(around[0].params), "thread"), 7.0)
  assert_eq(named(calls, "chat.older").length(), 0)
}


// 对话目录 (sfpages' outline.mbt): the long chat of two people (sffixture's outline_fixture.mbt), the list away from its
// end at 昨天's 09:40 (Ana's, seq 22: the one the reader is at); its rail at the right of a wide page, else a round
// button over the way to the newest; the outline beside what opened it, a sheet on Small; going to a row; what is found;
// back with ↓; its keys.

///|
/// The long chat in `mode` in a window `w`×`h` (`platform`: 0 a Mac's, 2 a phone's), its calls kept in `calls` and
/// answered as the made-up core answers them; `outline`: what the core's chatOutline says in place of the fixture's.
fn outline_tester(
  calls : Array[Made],
  mode? : String = "chat-outline-away",
  w? : Double = 1280.0,
  h? : Double = 800.0,
  platform? : Int = 0,
  pointing? : @ui.Pointing,
  outline? : @signals.Signal[Json?] = @signals.signal(None),
  newer? : Bool = false,
  top? : Double = -1.0,
  asks? : Bool = true,
  held? : OutlineHeld = { on: false, answers: [] },
  heard? : Array[(String, Json)] = [],
) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    asks_outline: fn() { asks },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      // (`held`: the outline's rows answered only as the test lets them go)
      // (`heard`: what the core answered, each by its call's name)
      let done = fn(res : Result[Json, Json]) {
        match res {
          Ok(j) => heard.push((name, j))
          Err(_) => ()
        }
        done(res)
      }
      if held.on && name == "chat.outline.rows" {
        held.answers.push(fn() { (base.call)(name, params, done) })
      } else {
        (base.call)(name, params, done)
      }
    },
    topic_read: fn(name, params) {
      match (name, outline.get()) {
        ("chatOutline", Some(o)) => { value: Some(o), error: None, version: 1 }
        // (`newer`: the chat's window short of its end, as the core says it of an older page)
        ("chat", _) if newer =>
          match (base.topic_read)(name, params) {
            { value: Some(Object(m)), .. } as r => {
              let o = m.copy()
              o["newer"] = true
              { ..r, value: Some(Json::object(o)) }
            }
            r => r
          }
        _ => (base.topic_read)(name, params)
      }
    },
  }
  open_fixture_over(mode, src)
  // (`top`: the list away at that message in place of the mode's)
  if top >= 0.0 {
    @sfbase.kept_places["ws1/st1\u{1}s-c1"] = { top, offset: 0.0, bottom: -1.0 }
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, pointing?)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The outline's rows' answers held back while `on` (what was asked, to answer as the test says: outline_let_go).
priv struct OutlineHeld {
  mut on : Bool
  answers : Array[() -> Unit]
}

///|
/// The rows' answers held so far given.
fn outline_let_go(held : OutlineHeld) -> Unit {
  let now = held.answers.copy()
  held.answers.clear()
  for f in now {
    f()
  }
}

///|
/// The seqs each `chat.outline.rows` asked for.
fn outline_rows_asked(calls : Array[Made]) -> Array[Array[Double]] {
  named(calls, "chat.outline.rows").map(fn(m) {
    items(Some(m.params), "seqs").map(fn(q) { (if q is Number(n, ..) { Some(n) } else { None }).unwrap_or(-1.0) })
  })
}

///|
/// The buttons named 对话目录 (the rail's, the round button's) and the outline's panel (its dialog), where they are.
fn outline_buttons(t : @ui.Tester) -> Array[(Double, Double, Double, Double)] {
  t.semantics().filter(fn(s) { s.role == Button && s.label == "对话目录" }).map(fn(s) { s.rect })
}

///|
fn outline_panel(t : @ui.Tester) -> (Double, Double, Double, Double)? {
  t.semantics().iter().find_first(fn(s) { s.role == Dialog && s.label == "对话目录" }).map(fn(s) { s.rect })
}

///|
/// The faults `t.audit()` finds in what the outline adds (its rail, its button, its panel), none of the page's others.
fn outline_faults(t : @ui.Tester) -> Array[String] {
  t.audit().filter(fn(f) { f.contains("对话目录") || f.contains("outline") || f.contains("panel_parts_node") })
}

///|
/// The chat's reading (where its reader is, what flashes).
fn outline_reading() -> @sfbase.Reading {
  @sfbase.reading_of("ws1/st1\u{1}s-c1")
}

///|
/// The first words of what people said in the long chat that the tests go to, by seq (outline_fixture's outline_said:
/// seq i + 1 its ith): Ana's 09:40 the first day, 林's 09:02 昨天, Ana's 09:40 (the reader's), 林's 10:35 after it.
let said_3 : String = "签名证书下周三过期"

///|
let said_20 : String = "早，昨晚的构建用新证书签名成功了吗"

///|
let said_22 : String = "截图初稿我看了，iPad 那几张字还是小"

///|
let said_23 : String = "引导页第二屏的插画可以换成新的那版了"

///|
test "对话目录: the reader's message, and the one before and after it, among what people said" {
  let said = [2.0, 5.0, 9.0, 14.0]
  // (at the chat's end: the last; else the last at or before the top of what shows, the first where none is)
  assert_eq(@sfpages.outline_current(said, 30.0, true), 14.0)
  assert_eq(@sfpages.outline_current(said, 10.0, false), 9.0)
  assert_eq(@sfpages.outline_current(said, 9.0, false), 9.0)
  assert_eq(@sfpages.outline_current(said, 1.0, false), 2.0)
  assert_eq(@sfpages.outline_current([], 1.0, false), -1.0)
  assert_eq(@sfpages.said_step(said, 10.0, false, -1), Some(5.0))
  assert_eq(@sfpages.said_step(said, 10.0, false, 1), Some(14.0))
  assert_eq(@sfpages.said_step(said, 1.0, false, -1), None)
  assert_eq(@sfpages.said_step(said, 30.0, true, 1), None)
  // (the rail where the column leaves it room at its right: never at 700 or narrower, nor where the rows' words come
  // within 24 of its press)
  assert_false(@sfpages.rail_fits(700.0))
  assert_false(@sfpages.rail_fits(880.0))
  assert_true(@sfpages.rail_fits(984.0))
}

///|
test "对话目录: a wide page's rail at the list's right, 44 wide, clear of the scroll bar; none with fewer than three said, none on a narrow page" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let rail = outline_buttons(t)
  assert_eq(rail.length(), 1, msg="\{Repr(rail)}")
  let (x, _, w, _) = rail[0]
  assert_true(w >= 44.0, msg="\{Repr(rail)}")
  assert_true(x + w <= 1280.0 - @ui.scroll_bar_room + 0.5 && x + w >= 1280.0 - 20.0, msg="\{Repr(rail)}")
  // (the outline subscribed while it shows; nothing asked of the core by it)
  assert_eq(named(calls, "chat.bring").length(), 0)
  assert_eq(outline_faults(t), [])
  // two said: no rail
  let few : Json = {
    "days": [{ "date": "2026-11-10", "day": "今天", "seqs": [2, 4] }],
    "count": 2,
    "others": true,
    "held": 2,
    "of": 2,
    "whole": true,
  }
  let t = outline_tester(calls, outline=@signals.signal(Some(few)))
  assert_eq(outline_buttons(t), [])
  // a phone's window: the round button over the way to the newest, 32 round, no rail
  let t = outline_tester(calls, w=390.0, h=844.0, platform=2)
  let floats = outline_buttons(t)
  assert_eq(floats.length(), 1, msg="\{Repr(floats)}")
  let jump = t.semantics().iter().find_first(fn(s) { s.role == Button && s.label == "跳到最新" }).map(fn(s) { s.rect })
  match jump {
    Some((jx, jy, jw, _)) => {
      let (fx, fy, fw, fh) = floats[0]
      // (directly over it, as wide, the same column)
      assert_eq(fx + fw, jx + jw)
      assert_true(fy + fh < jy, msg="\{Repr(floats[0])} \{Repr(jump)}")
      assert_eq(fw, jw)
    }
    None => fail("no way to the newest")
  }
  assert_eq(outline_faults(t), [])
  // at the end of the chat (no way to the newest): no round button either
  let t = outline_tester(calls, mode="chat", w=390.0, h=844.0, platform=2)
  assert_eq(outline_buttons(t), [])
}

///|
test "对话目录: opened, the rail's outline beside it at its left, its days and rows from the view, the reader's in the accent, the rest of the chat read" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let (rx, _, _, _) = outline_buttons(t)[0]
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let panel = outline_panel(t).unwrap()
  let (px, _, pw, _) = panel
  assert_true(px + pw <= rx, msg="\{Repr(panel)} rail at \{rx}")
  // its days as the core heads them, its rows' first lines and times; the reader's (Ana's 09:40 昨天) among them
  assert_true(t.find("昨天") is Some(_))
  assert_true(t.find_last("截图初稿我看了，iPad 那几张字还是小，第三张的状态栏也没隐藏，我标出来发你") is Some(_))
  assert_true(t.find("设计说头图周一给，到时候我直接换上去，不用再走一遍审核流程了吧？") is Some(_))
  // (the rest of the chat read onto the device as it opens, by its station and thread)
  let bring = named(calls, "chat.bring")
  assert_eq(bring.length(), 1)
  assert_eq(text(Some(bring[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(bring[0].params), "thread"), 7.0)
  // its field takes the keys: what is typed looked for
  t.type_text("签名")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  let asked = named(calls, "chat.outline.find")
  assert_eq(asked.length() >= 1, true, msg="\{asked.length()}")
  assert_eq(text(Some(asked[0].params), "query"), "签名")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: on a phone a sheet from the foot titled 对话目录, from the round button; a row pressed closes it and the list goes to its message, which flashes" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, w=390.0, h=844.0, platform=2)
  t.click(Button, label="对话目录")
  t.run_for(@ui.move_most_ms)
  let (px, _, pw, ph) = outline_panel(t).unwrap()
  assert_eq(px, 0.0)
  assert_eq(pw, 390.0)
  assert_true(ph > 300.0)
  assert_eq(outline_faults(t), [])
  // a row above the reader's: 设计说头图周一给 (Ana's, 星期日 17:30, seq 18), not in the list now
  let row = "设计说头图周一给，到时候我直接换上去，不用再走一遍审核流程了吧？"
  t.tap_text(row)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
  assert_true(gone_lit(t, "设计说头图周一给"), msg="ts18 flashing")
  assert_true(t.find(row) is Some(_))
}

///|
test "对话目录: words typed find in all of the chat (chat.outline.find, 120 ms after the last key, its thread's); the rows found, their count; one gone to marks the words in its message" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is Some(_))
  t.type_text("签名")
  t.draw()
  assert_eq(named(calls, "chat.outline.find").length(), 0)
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  let asked = named(calls, "chat.outline.find")
  assert_true(asked.length() >= 1)
  assert_eq(text(Some(asked[0].params), "query"), "签名")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // (who said each and when, over the line with the words; agents' too)
  assert_true(t.find("Claude · 09:05") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find("8 条") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_eq(outline_faults(t), [])
  // none found: said so at the field's end
  t.type_text("没有这个词")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("没有找到") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  // a found row gone to: the words marked in its message (as a search's), nothing flashing
  for _ in "没有这个词" {
    t.backspace()
  }
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  t.tap_text("签名证书下周三过期，我建议这次发布前就换新证书，不然商店那边会拒…")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
  assert_true(search_stroke_under(t, said_3, @sf.theme().p.accent, @sf.message_stroke.width), msg="ts3 marked")
}

///|
test "对话目录: while not all of the chat is on the device, 正在读取其余消息 over its rows" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline-bringing")
  assert_true(t.find("正在读取其余消息") is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: ↓ ↑ from its field move the row the keys are at, one lit at a time; Enter goes there; Escape closes it" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let hover = @sf.theme().p.hover
  let lit = fn() {
    let (px, py, pw, ph) = outline_panel(t).unwrap()
    t.drawn_rects().filter(fn(r) { r.4 == hover && r.0 >= px && r.0 + r.2 <= px + pw + 0.5 && r.1 >= py && r.1 + r.3 <= py + ph + 0.5 }).length()
  }
  assert_eq(lit(), 1)
  t.key(@ui.key_code_down)
  t.run_for(@ui.move_most_ms)
  assert_eq(lit(), 1)
  // (the reader's is Ana's 09:40 (seq 22); the next said 林's 10:35, seq 23)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
  assert_true(gone_lit(t, said_23), msg="ts23 flashing")
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is Some(_))
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
}

///|
test "对话目录: the pointer moved onto a row takes the keys there, one ground, never the keys' and the pointer's both; Enter goes to it" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let hover = @sf.theme().p.hover
  let grounds = fn() {
    let (px, py, pw, ph) = outline_panel(t).unwrap()
    t.drawn_rects().filter(fn(r) { r.4 == hover && r.0 >= px && r.0 + r.2 <= px + pw + 0.5 && r.1 >= py && r.1 + r.3 <= py + ph + 0.5 })
  }
  let at_first = grounds()
  assert_eq(at_first.length(), 1, msg="\{Repr(at_first)}")
  // (onto the row under the reader's: 林's 10:35, seq 23)
  let (gx, gy, gw, gh, _) = at_first[0]
  t.move_to(gx + gw / 2.0, gy + gh * 1.5)
  t.run_for(@ui.move_most_ms)
  let after = grounds()
  assert_eq(after.length(), 1, msg="\{Repr(after)}")
  assert_eq(after[0].1, gy + gh)
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(gone_lit(t, said_23), msg="ts23 flashing")
}

///|
test "对话目录: ⌥⇧↑ and ⌥⇧↓ go to the message a person said before and after the reader's, flashing" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  // (the reader's: Ana's, seq 22; before it 林's 09:02, seq 20; after it 林's 10:35, seq 23)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_true(gone_lit(t, said_20), msg="ts20 flashing")
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_down, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_true(gone_lit(t, said_22), msg="ts22 flashing")
}

///|
test "对话目录: a go-to in the chat far from its end keeps where the reader was; ↓ goes back there first (no flash), the place then forgotten" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let back = fn() { t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" }) }
  assert_false(back())
  // a row far up: 签名证书下周三过期 (seq 3)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(back(), msg="\{Repr(t.semantics().filter(fn(s) { s.role == Button }).map(fn(s) { s.label }))}")
  assert_true(gone_lit(t, said_20), msg="ts20 flashing")
  // ↓: back at 22, its top as it was, nothing flashing anew
  t.click(Button, label="回到刚才的位置")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_eq(outline_reading().top_seq, 22.0)
  assert_false(gone_lit(t, said_22), msg="ts22 flashing")
  assert_false(back())
  // (↓ pressed again, gliding to the end, and sending: chat_wbtest.mbt's, where the glide is that file's motion)
}

///|
/// What the last frame drew of `kind` (rect, glyphs…) as frame_export has it: where (x y w h), its colour, its words.
fn outline_drawn(t : @ui.Tester, kind : String) -> Array[(Double, Double, Double, Double, String, String)] {
  t
  .frame_export()
  .filter_map(fn(l) {
    let p = l.split(" ").map(fn(s) { s.to_owned() }).collect()
    guard p.length() > 5 && p[0] == kind else { return None }
    let n = fn(s : String) {
      let j = try Some(@json.parse(s)) catch { _ => None }
      match j {
        Some(j) => (if j is Number(n, ..) { Some(n) } else { None }).unwrap_or(-1.0)
        None => -1.0
      }
    }
    let words = match l.find("\"") {
      Some(i) => l.exact_view(start=i + 1).to_owned().trim_end(chars="\"").to_owned()
      None => ""
    }
    Some((n(p[1]), n(p[2]), n(p[3]), n(p[4]), p[5], words))
  })
}

///|
/// A colour of the palette as frame_export writes it (#rrggbb).
fn outline_hex(c : Int64) -> String {
  let v = ((c >> 8) & 0xffffffL).to_int()
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  out.write_char('#')
  for i in 0..<6 {
    out.write_char(digits[(v >> ((5 - i) * 4)) & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
/// The rail's ticks drawn (in its press `rail`), top to bottom: how long each is and its colour.
fn outline_ticks(t : @ui.Tester, rail : (Double, Double, Double, Double)) -> Array[(Double, String)] {
  let (rx, ry, rw, rh) = rail
  let ticks = outline_drawn(t, "rect").filter(fn(r) {
    r.0 >= rx && r.0 + r.2 <= rx + rw + 0.5 && r.1 >= ry && r.1 + r.3 <= ry + rh + 0.5 && r.3 <= 2.5
  })
  ticks.sort_by(fn(a, b) { a.1.compare(b.1) })
  ticks.map(fn(r) { (r.2, r.4) })
}

///|
test "对话目录: the rail's ticks, one for each said, the reader's (the 16th: Ana's 昨天 09:40) longer and in the ink, the rest in the line's colour; its press 44 by 44 at least with three" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let rail = outline_buttons(t)[0]
  let ticks = outline_ticks(t, rail)
  // (31 said by people in the long chat, all of them in half the list's height)
  assert_eq(ticks.length(), 31, msg="\{Repr(ticks)}")
  let p = @sf.theme().p
  let long = ticks.mapi(fn(i, k) { (i, k) }).filter(fn(k) { k.1.1 == outline_hex(p.text) })
  assert_eq(long.map(fn(k) { k.0 }), [15], msg="\{Repr(ticks)}")
  assert_eq(long[0].1.0, 16.0)
  // (the rest one colour, quieter than the ink, each as long as its turn: shorter than the reader's, 4 for one message,
  // longer as more answered it: 林's first (Claude answering, then Ana) longer than Ana's next (林 straight after))
  let short = ticks.filter(fn(k) { k.1 != long[0].1.1 })
  assert_true(short.iter().all(fn(k) { k.1 == short[0].1 && k.0 >= 4.0 && k.0 <= 12.0 }), msg="\{Repr(ticks)}")
  assert_true(ticks[0].0 > ticks[1].0 && ticks[1].0 == 4.0, msg="\{Repr(ticks)}")
  // three said: the rail as tall as a press at least, its ticks in its middle
  let three : Json = {
    "days": [{ "date": "2026-11-10", "day": "今天", "seqs": [2, 4, 6] }],
    "count": 3,
    "others": true,
    "held": 3,
    "of": 3,
    "whole": true,
  }
  let t = outline_tester(calls, outline=@signals.signal(Some(three)))
  let rails = outline_buttons(t)
  assert_eq(rails.length(), 1)
  let (_, ry, rw, rh) = rails[0]
  assert_true(rw >= 44.0 && rh >= 44.0, msg="\{Repr(rails)}")
  let drawn = outline_ticks(t, rails[0])
  assert_eq(drawn.length(), 3)
  let ys = outline_drawn(t, "rect").filter(fn(r) { r.3 <= 2.5 && r.0 >= rails[0].0 && r.0 <= rails[0].0 + rw })
  let top = ys.fold(init=1.0e9, fn(a, r) { if r.1 < a { r.1 } else { a } })
  let foot = ys.fold(init=-1.0e9, fn(a, r) { if r.1 + r.3 > a { r.1 + r.3 } else { a } })
  // (as far over them as under them)
  assert_true((top - ry - (ry + rh - foot)).abs() < 1.0, msg="\{top} \{foot} in \{Repr(rails[0])}")
  assert_eq(outline_faults(t), [])
}

///|
/// The narrowest window (a Mac's, 800 tall) whose chat page shows the rail, between `from` (none) and `to` (one): the
/// round button below it.
fn outline_rail_from(from : Int, to : Int) -> Int {
  let calls : Array[Made] = []
  let mut lo = from
  let mut hi = to
  while hi - lo > 1 {
    let mid = (lo + hi) / 2
    // (the rail's press, 44 wide; not the round button, 32)
    if outline_buttons(outline_tester(calls, w=mid.to_double())).iter().any(fn(b) { b.2 >= 44.0 }) {
      hi = mid
    } else {
      lo = mid
    }
  }
  hi
}

///|
test "对话目录: the rail over the list takes no wheel nor press beside its own; at the narrowest window it shows in, clear of the scroll bar and the rows' words" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let (rx, ry, rw, rh) = outline_buttons(t)[0]
  // a wheel over the rail's column, above it and on it: the list scrolls as anywhere
  let row = "把新证书切到 CI 上吧，今晚的构建就用它签名，旧证书先留着回滚"
  let y_of = fn() {
    outline_drawn(t, "glyphs").iter().find_first(fn(g) { g.5 == row && g.0 < rx }).map(fn(g) { g.1 }).unwrap_or(-1.0)
  }
  let y0 = y_of()
  t.wheel(rx + rw / 2.0, ry - 40.0, 60.0)
  t.run_for(@ui.move_most_ms)
  let y1 = y_of()
  assert_true(y1 < y0 - 30.0, msg="\{y0} \{y1}")
  t.wheel(rx + rw / 2.0, ry + rh / 2.0, 60.0)
  t.run_for(@ui.move_most_ms)
  let y2 = y_of()
  assert_true(y2 < y1 - 30.0, msg="\{y1} \{y2}")
  // the narrowest window the rail shows in: its press clear of the scroll bar, and S6 at least from the rows' words
  // (the pointer over the rail's press: the hand; over its column above it, at its left: the list's)
  let (rx, ry, rw, rh) = outline_buttons(t)[0]
  assert_true(t.probe_at(rx + rw / 2.0, ry + rh / 2.0).contains("cursor=Hand"))
  assert_false(t.probe_at(rx + rw / 2.0, ry - 40.0).contains("cursor=Hand"))
  assert_false(t.probe_at(rx - 2.0, ry + rh / 2.0).contains("cursor=Hand"))
  let w = outline_rail_from(900, 1280)
  let t = outline_tester(calls, w=w.to_double())
  let (rx, ry, rw, rh) = outline_buttons(t)[0]
  assert_true(rx + rw <= w.to_double() - @ui.scroll_bar_room + 0.5, msg="\{w}: \{Repr((rx, rw))}")
  let words = t.text_runs().filter(fn(r) { r.x0 > w.to_double() / 2.0 && r.top < ry + rh && r.bottom > ry - 200.0 })
  let right = words.fold(init=0.0, fn(a, r) { if r.x1 > a && r.x0 < rx { r.x1 } else { a } })
  // (1206 as this was written: the press at 1155..1199, the rows' words ending at 1131, 24 clear; 7 to the window's
  // right for the scroll bar)
  assert_true(rx - right >= @ui.Space::px(S6) - 0.5, msg="\{w}: words end \{right}, rail at \{rx}")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: on a page too narrow for the rail (a 1200 wide window) the round button, its outline a panel beside it, not a sheet" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, w=1200.0, h=800.0)
  let floats = outline_buttons(t)
  assert_eq(floats.length(), 1, msg="\{Repr(floats)}")
  let (fx, fy, fw, fh) = floats[0]
  // (the round button over the way to the newest, not the rail at the list's right, 20 in from the window's at most)
  assert_true(fx + fw < 1200.0 - 20.0, msg="\{Repr(floats)}")
  t.click(Button, label="对话目录")
  t.run_for(@ui.move_most_ms)
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  // (at its left, their feet together)
  assert_true(pw < 600.0 && px + pw <= fx + 0.5, msg="panel \{Repr((px, pw))} float at \{fx}")
  assert_true((py + ph - (fy + fh)).abs() < 12.0, msg="panel \{Repr((py, ph))} float \{Repr((fy, fh))}")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: beside what opened it, clear of the system's bars over the window (an iPhone Duo's actions over its top, its tabs at its foot or its column down its side), a share of the room they leave" {
  // (top, right, foot: the Duo's upright bars across the top and foot; its column down the side; a status bar alone)
  for bars in [(200.0, 0.0, 90.0), (24.0, 84.0, 20.0), (40.0, 0.0, 0.0)] {
    let (top, right, foot) = bars
    let calls : Array[Made] = []
    let t = outline_tester(calls, w=1200.0, h=800.0)
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":\{foot},\"left\":0,\"right\":\{right}}}")
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="对话目录")
    t.run_for(@ui.move_most_ms)
    let (px, py, pw, ph) = outline_panel(t).unwrap()
    let msg = "bars \{Repr(bars)}: panel \{Repr((px, py, pw, ph))}"
    assert_true(py >= top + 8.0 - 0.5, msg~)
    assert_true(py + ph <= 800.0 - foot - 8.0 + 0.5, msg~)
    assert_true(px + pw <= 1200.0 - right - 8.0 + 0.5, msg~)
    // (its share of the room left, not of the whole window: outline_tall's)
    assert_true(ph <= 0.7 * (800.0 - top - foot) + 0.5, msg~)
  }
}

///|
test "对话目录: the reader's row in the accent's ink, it alone; each row's words drawn once" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  let accent = outline_hex(@sf.theme().p.accent_text)
  let inked = outline_drawn(t, "glyphs").filter(fn(g) {
    g.4 == accent && g.0 >= px && g.0 < px + pw && g.1 >= py && g.1 < py + ph
  })
  // (its words as the core cuts a row's, 64 columns: views.ts OUTLINE_WORDS)
  assert_eq(inked.map(fn(g) { g.5 }), ["截图初稿我看了，iPad 那几张字还是小，第三张的状态栏也没隐藏，我…"])
  // (and each row's words drawn once: its label read out, not drawn beside them)
  let drawn = outline_drawn(t, "glyphs").filter(fn(g) {
    g.5.contains("截图初稿我看了") && g.0 >= px && g.0 < px + pw && g.1 >= py && g.1 < py + ph
  })
  assert_eq(drawn.length(), 1, msg="\{Repr(drawn)}")
}

///|
test "对话目录: within a list's height of the chat's end a go-to keeps no place; with the window short of the chat's end it does" {
  let calls : Array[Made] = []
  let back = fn(t : @ui.Tester) { t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" }) }
  // (near the end, less than the list's height from it: Claude's 今天 09:05, seq 32)
  let t = outline_tester(calls, top=32.0)
  assert_false(outline_reading().at_end)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  // (to what 林 said before: 21:40 昨天, seq 30)
  assert_true(gone_lit(t, "查看器的关闭按钮我今晚修好"), msg="ts30 flashing")
  assert_false(back(t))
  // the same with the window an older page of the chat (newer after it): kept
  let t = outline_tester(calls, top=32.0, newer=true)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(back(t))
}

///|
test "对话目录: a found row gone to marks its words in its message, nothing flashing, and keeps where the reader was" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.type_text("签名")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  t.tap_text("签名证书下周三过期，我建议这次发布前就换新证书，不然商店那边会拒…")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(search_stroke_under(t, said_3, @sf.theme().p.accent, @sf.message_stroke.width), msg="ts3 marked")
  assert_false(gone_lit(t, said_3), msg="ts3 flashing")
  assert_true(t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" }))
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: in the sheet its day headings on the title's line, the rows' grounds in from its sides as a sheet's rows are, the faces round in their corners" {
  let calls : Array[Made] = []
  // (a pointer's hand, where the row the keys are at is lit)
  let t = outline_tester(calls, mode="chat-outline", w=390.0, h=844.0, platform=2, pointing=Mouse)
  let glyph = fn(words : String) {
    outline_drawn(t, "glyphs").iter().find_first(fn(g) { g.5 == words }).map(fn(g) { g.0 }).unwrap_or(-1.0)
  }
  let title = glyph("对话目录")
  assert_true(title > 0.0)
  assert_eq(glyph("昨天"), title)
  // (the reader's row, lit as the keys are at it: its ground panel_card_in from the sheet's sides, its words on after
  // the face's column)
  let hover = outline_hex(@sf.theme().p.hover)
  let grounds = outline_drawn(t, "rect").filter(fn(r) { r.4 == hover && r.2 > 200.0 })
  assert_eq(grounds.length(), 1, msg="\{Repr(grounds)}")
  let (gx, _, gw, _, _, _) = grounds[0]
  assert_eq(gx, @sf.panel_card_in)
  assert_eq(gx + gw, 390.0 - @sf.panel_card_in)
  // (round as a pick's rows are, row_corner, not a card's corner that made a capsule of it)
  let r = @sf.row_corner.to_int()
  let lines = t.frame_export().filter(fn(l) { l.has_prefix("rect ") && l.contains(" " + hover + " ") })
  assert_true(lines.iter().any(fn(l) { l.contains(" r=\{r},\{r},\{r},\{r}") }), msg="\{Repr(lines)}")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: in the sheet to a finger no row has a ground at rest, the reader's in the accent's ink alone, as a pick's chosen choice" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline", w=390.0, h=844.0, platform=2)
  let hover = outline_hex(@sf.theme().p.hover)
  let grounds = outline_drawn(t, "rect").filter(fn(r) { r.4 == hover && r.2 > 200.0 })
  assert_eq(grounds.length(), 0, msg="\{Repr(grounds)}")
  let accent = outline_hex(@sf.theme().p.accent_text)
  assert_true(outline_drawn(t, "glyphs").iter().any(fn(g) { g.4 == accent }), msg="\{Repr(outline_drawn(t, "glyphs"))}")
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: the rail and the steps from the outline's index alone: no row asked for while only the rail shows" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  assert_eq(outline_buttons(t).length(), 1)
  t.key(@ui.key_code_up, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_true(gone_lit(t, said_20), msg="ts20 flashing")
  assert_eq(named(calls, "chat.outline.rows").length(), 0)
}

///|
test "对话目录: opened, its rows filled from the chunk the reader's is in, asked once, the reader's row in view, no bones at rest" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let asked = outline_rows_asked(calls)
  assert_eq(asked.length(), 1, msg="\{Repr(asked)}")
  // (the long chat's 31 said, one chunk: all of them, the reader's among them, by its station and thread)
  assert_eq(asked[0].length(), 31)
  assert_true(asked[0].contains(22.0))
  let rows = named(calls, "chat.outline.rows")
  assert_eq(text(Some(rows[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(rows[0].params), "thread"), 7.0)
  assert_eq(t.bones_drawn(), 0)
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  let reader = outline_drawn(t, "glyphs").filter(fn(g) {
    g.5 == "截图初稿我看了，iPad 那几张字还是小，第三张的状态栏也没隐藏，我…" && g.0 >= px && g.0 < px + pw && g.1 >= py && g.1 < py + ph
  })
  assert_eq(reader.length(), 1, msg="\{Repr(reader)}")
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.outline.rows").length(), 1)
}

///|
test "对话目录: a long outline (240 said) asks only the chunk shown; scrolled to its start, that chunk once, bones till it comes, the rows as tall after" {
  let calls : Array[Made] = []
  let held : OutlineHeld = { on: false, answers: [] }
  let t = outline_tester(calls, mode="chat-outline-long", held~)
  let asked = outline_rows_asked(calls)
  // (the reader's, 283, among the last of the 240 said: the fifth chunk, its 200th to 239th)
  assert_eq(asked.length(), 1, msg="\{Repr(asked)}")
  assert_eq(asked[0].length(), 40)
  assert_true(asked[0].contains(@sffixture.outline_long_away_seq))
  assert_eq(t.bones_drawn(), 0)
  // to its start at once, the answer held
  held.on = true
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  t.wheel(px + pw / 2.0, py + ph / 2.0, -100000.0)
  t.run_for(@ui.move_most_ms)
  let asked = outline_rows_asked(calls)
  assert_eq(asked.length(), 2, msg="\{Repr(asked.map(fn(a) { a.get(0) }))}")
  assert_eq(asked[1].length(), 50)
  assert_eq(asked[1][0], 1.0)
  assert_true(t.bones_drawn() > 0)
  let heading = fn(day : String) {
    outline_drawn(t, "glyphs").iter().find_first(fn(g) { g.5 == day }).map(fn(g) { g.1 }).unwrap_or(-1.0)
  }
  let first = heading("10月30日")
  assert_true(first > 0.0, msg="\{first}")
  // (where each row stands and how tall it is, in the panel: the bones' boxes and the rows' alike)
  let boxes = fn() {
    t.drawn_rects().filter(fn(r) { r.0 >= px && r.0 + r.2 <= px + pw + 0.5 && r.1 >= py + 60.0 && r.1 + r.3 <= py + ph && r.3 >= 30.0 && r.3 <= 60.0 }).map(fn(r) { (r.1, r.3) })
  }
  let rows_at = fn() { t.semantics().filter(fn(s) { s.role == Button && s.rect.0 >= px && s.rect.1 > py + 60.0 && s.rect.1 < py + ph }).map(fn(s) { (s.rect.1, s.rect.3) }) }
  let before = rows_at()
  let bones_before = boxes()
  t.run_for(@ui.move_most_ms)
  // (asked once while it is asked)
  assert_eq(outline_rows_asked(calls).length(), 2)
  held.on = false
  outline_let_go(held)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.bones_drawn(), 0)
  assert_eq(heading("10月30日"), first)
  let after = rows_at()
  assert_true(after.length() >= 8, msg="\{Repr(after)}")
  assert_eq(before, after, msg="bones \{Repr(bones_before)} rows \{Repr(after)}")
  assert_eq(outline_rows_asked(calls).length(), 2)
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: a person's message said while it is open adds its row, asking only its chunk" {
  let calls : Array[Made] = []
  // (the long chat's index without its last said, 林's 今天 14:40, seq 40; then with it)
  let full = ((fixture("chat-outline").topic_read)("chatOutline", {
    "station": Json::string("ws1/st1"),
    "thread": Json::number(7.0),
  })).value.unwrap()
  let short = match full {
    Object(m) => {
      let o = m.copy()
      let days = items(Some(full), "days")
      let last = days[days.length() - 1]
      let seqs = items(Some(last), "seqs")
      let cut : Json = {
        "date": field(Some(last), "date").unwrap(),
        "day": field(Some(last), "day").unwrap(),
        "seqs": Json::array(seqs[:seqs.length() - 1].to_owned()),
      }
      o["days"] = Json::array(days[:days.length() - 1].to_owned() + [cut])
      Json::object(o)
    }
    _ => full
  }
  let live = @signals.signal(Some(short))
  let t = outline_tester(calls, outline=live)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(outline_rows_asked(calls).length(), 1)
  let row = "还有深色模式也看一下，启动画面那张图在深色模式下边缘有一圈白，挺显眼的"
  // (its words in the panel, as the core cuts a row's: they begin as it does)
  let shows = fn() {
    let (px, _, _, _) = outline_panel(t).unwrap()
    outline_drawn(t, "glyphs").filter(fn(g) { g.0 >= px && g.5.has_prefix(row.exact_view(end=20).to_owned()) }).length()
  }
  assert_eq(shows(), 0)
  live.set(Some(full))
  t.run_for(@ui.move_most_ms)
  // (its row made as it shows, at the outline's end: its chunk asked again for it, the one thing of it not held)
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  t.wheel(px + pw / 2.0, py + ph / 2.0, 100000.0)
  t.run_for(@ui.move_most_ms)
  let asked = outline_rows_asked(calls)
  assert_eq(asked.length(), 2, msg="\{Repr(asked)}")
  assert_true(asked[1].contains(40.0))
  assert_eq(shows(), 1)
}

///|
test "对话目录: more found than it lists: the newest fifty, how many older not listed said over the rows" {
  let calls : Array[Made] = []
  let heard : Array[(String, Json)] = []
  let t = outline_tester(calls, mode="chat-outline-long", heard~)
  t.type_text("的")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  let found = named(calls, "chat.outline.find")
  assert_true(found.length() >= 1)
  let (total, more) = match heard.iter().filter(fn(h) { h.0 == "chat.outline.find" }).last() {
    Some((_, j)) => (number(Some(j), "total").to_int(), number(Some(j), "more").to_int())
    None => (0, 0)
  }
  assert_true(more > 0 && total == more + 50, msg="\{Repr((total, more))}")
  let note = @sf.t("web-main.outline.more", args=[("n", more.to_string())])
  assert_true(t.find(note) is Some(_), msg="\{note} \{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find(@sf.t("web-main.outline.count", args=[("n", total.to_string())])) is Some(_))
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: words found stand at the list's start, the first found whole and lit under its day; emptied, back at the reader's" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline-long")
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  let accent = outline_hex(@sf.theme().p.accent_text)
  let reader = fn() {
    outline_drawn(t, "glyphs").filter(fn(g) { g.4 == accent && g.0 >= px && g.1 >= py && g.1 < py + ph }).length()
  }
  assert_eq(reader(), 1)
  t.type_text("的")
  t.run_for(@sfpages.find_typing_ms)
  t.run_for(@ui.move_most_ms)
  // (the note over the rows, then the first day's heading, then the first found, lit, whole)
  let glyphs = outline_drawn(t, "glyphs").filter(fn(g) { g.0 >= px && g.0 < px + pw && g.1 >= py && g.1 < py + ph })
  let note = glyphs.iter().find_first(fn(g) { g.5.has_prefix("更早的") }).unwrap()
  let hover = outline_hex(@sf.theme().p.hover)
  let lit = outline_drawn(t, "rect").filter(fn(r) { r.4 == hover && r.0 >= px && r.0 + r.2 <= px + pw + 0.5 && r.2 > 200.0 })
  assert_eq(lit.length(), 1, msg="\{Repr(lit)}")
  let heading = glyphs.filter(fn(g) { g.1 > note.1 + note.3 && g.1 < lit[0].1 })
  assert_true(heading.length() >= 1, msg="no day over the first found: \{Repr(glyphs.map(fn(g) { (g.5, g.1) }))}")
  assert_true(lit[0].1 >= note.1 + note.3, msg="first found at \{Repr(lit[0])}, note \{Repr((note.1, note.3))}")
  let faces = outline_drawn(t, "glyphs").filter(fn(g) { g.0 >= px && g.1 >= lit[0].1 && g.1 + g.3 <= lit[0].1 + lit[0].3 + 0.5 && g.3 < 12.0 })
  assert_true(faces.length() >= 1, msg="its face whole in it")
  assert_eq(outline_faults(t), [])
  // emptied: the outline again, the reader's row in view
  t.backspace()
  t.run_for(@ui.move_most_ms)
  assert_eq(reader(), 1)
}

///|
test "对话目录: a go-to on a wide page as the bell's runs, with the outline off and on: far, flashing; then ↓ back (on) or to the end (off)" {
  for asks in [false, true] {
    let calls : Array[Made] = []
    let t = outline_tester(calls, asks~)
    t.click(Button, label="跳转到待决策的消息")
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    // (what waits to be decided first: the post at seq 8, not laid out from 22)
    assert_true(gone_lit(t, "复现了，是图片还没量好高度就当成了锚点"), msg="ts8 flashing, asks \{asks}")
    let back = t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" })
    assert_eq(back, asks)
    if asks {
      t.click(Button, label="回到刚才的位置")
      t.run_for(@ui.move_most_ms)
      t.run_for(@ui.move_most_ms)
      assert_eq(outline_reading().top_seq, 22.0)
    } else {
      t.click(Button, label="跳到最新")
      t.run_for(@ui.move_most_ms)
      t.run_for(@ui.move_most_ms)
      assert_true(outline_reading().at_end)
    }
  }
}

///|
test "对话目录: a go-to to a message of an older page, read first: the longer chat's first said, from its outline" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline-long")
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  t.wheel(px + pw / 2.0, py + ph / 2.0, -100000.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("早，今天想把发布清单从头到尾过一遍：签名、更新日志、商店截图、深…")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  // (the page before asked for (chat.older, or round it: chat.around), then gone to: flashing, the panel closed)
  assert_true(named(calls, "chat.older").length() + named(calls, "chat.around").length() >= 1, msg="\{Repr(calls.map(fn(m) { m.name }))}")
  assert_true(outline_panel(t) is None)
  assert_true(gone_lit(t, "早，今天想把发布清单从头到尾过一遍"), msg="ts1 flashing")
}

///|
/// The rail's ticks (in its press `rail`), top to bottom: where each stands and whether it is the long one.
fn outline_tick_places(t : @ui.Tester) -> Array[(Double, Bool)] {
  let rail = outline_buttons(t).filter(fn(b) { b.2 >= 44.0 })
  guard rail.length() == 1 else { return [] }
  let (rx, ry, rw, rh) = rail[0]
  let ticks = outline_drawn(t, "rect").filter(fn(r) {
    r.0 >= rx && r.0 + r.2 <= rx + rw + 0.5 && r.1 >= ry && r.1 + r.3 <= ry + rh + 0.5 && r.3 <= 2.5
  })
  ticks.sort_by(fn(a, b) { a.1.compare(b.1) })
  ticks.map(fn(r) { (r.1, r.2 > 12.5) })
}

///|
/// Which of `m` ticks of the longer chat's map stands for its message `seq` (the reader's), its index's seqs as the
/// fixture says them.
fn outline_long_tick(m : Int, seq : Double) -> Int {
  let index = ((fixture("chat-outline-long").topic_read)("chatOutline", {
    "station": Json::string("ws1/st1"),
    "thread": Json::number(7.0),
  })).value
  let seqs : Array[Double] = []
  for d in items(index, "days") {
    for q in items(Some(d), "seqs") {
      seqs.push((if q is Number(n, ..) { Some(n) } else { None }).unwrap_or(-1.0))
    }
  }
  seqs.search(seq).unwrap_or(-1) * m / seqs.length()
}

///|
test "对话目录: the longer chat's rail a steady map, its ticks where they were as the reader steps, scrolls or goes far; the long one the reader's part" {
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline-long")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let first = outline_tick_places(t)
  let m = first.length()
  // (240 said, more than fit: as many as fit in half the list's height)
  assert_true(m > 10 && m < 240, msg="\{m}")
  let ys = fn(p : Array[(Double, Bool)]) { p.map(fn(x) { x.0 }) }
  let long = fn(p : Array[(Double, Bool)]) { p.mapi(fn(i, x) { (i, x.1) }).filter(fn(x) { x.1 }).map(fn(x) { x.0 }) }
  // (the reader's: the message the list stands at, 283; then the one ⌥⇧↓ goes to, flashing)
  assert_eq(long(first), [outline_long_tick(m, @sffixture.outline_long_away_seq)])
  t.key(@ui.key_code_down, mods=@ui.mod_alt | @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  let p = outline_tick_places(t)
  assert_eq(ys(p), ys(first))
  // (the next said after 283: 284, 林's and Ana's in turn, Claude's every fifth after the first of a day)
  let went = @sffixture.outline_long_away_seq + 1.0
  assert_eq(long(p), [outline_long_tick(m, went)])
  // scrolled up through some messages by the hand: one long, all where they were
  t.wheel(800.0, 400.0, -600.0)
  t.run_for(@ui.move_most_ms)
  let p = outline_tick_places(t)
  assert_eq(ys(p), ys(first))
  assert_eq(long(p).length(), 1)
  // far: to the chat's first said, from its outline (its page before read first)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let (px, py, pw, ph) = outline_panel(t).unwrap()
  t.wheel(px + pw / 2.0, py + ph / 2.0, -100000.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("早，今天想把发布清单从头到尾过一遍：签名、更新日志、商店截图、深…")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let p = outline_tick_places(t)
  assert_eq(ys(p), ys(first))
  assert_eq(long(p), [0])
  // to its end by the hand: the last
  t.wheel(800.0, 400.0, 1000000.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let p = outline_tick_places(t)
  assert_eq(ys(p), ys(first))
  assert_eq(long(p), [m - 1])
  assert_eq(outline_faults(t), [])
}

///|
test "对话目录: scrolled to its end, its last row whole in the panel, over its foot" {
  // (the panel a share of the window: what holds its list grown from none under its head, not as tall as its rows,
  // which stood past the panel's foot and cut its last row there)
  for h in [800.0, 1080.0] {
    let calls : Array[Made] = []
    let t = outline_tester(calls, mode="chat-outline-long", h~)
    let (px, py, pw, ph) = outline_panel(t).unwrap()
    t.wheel(px + pw / 2.0, py + ph / 2.0, 100000.0)
    t.run_for(@ui.move_most_ms)
    let rows = t.semantics().filter(fn(s) { s.role == Button && s.rect.0 >= px && s.rect.2 > pw / 2.0 && s.rect.1 > py + 60.0 && s.rect.1 < py + ph })
    let last = rows.iter().fold(init=0.0, fn(m, s) { if s.rect.1 + s.rect.3 > m { s.rect.1 + s.rect.3 } else { m } })
    assert_true(rows.length() > 5, msg="h \{h}: \{rows.length()} rows")
    assert_true(last <= py + ph - @sf.panel_pad + 0.5, msg="h \{h}: last row's foot \{last}, panel's \{py + ph}")
    assert_eq(outline_faults(t), [])
  }
}

///|
test "对话目录: a tick of the rail pointed at says its message's first line and time, its chunk asked for then, once; pressed, it goes to that message, which flashes" {
  let calls : Array[Made] = []
  let t = outline_tester(calls)
  let rail = outline_buttons(t)[0]
  let (rx, ry, rw, rh) = rail
  let ticks = outline_drawn(t, "rect").filter(fn(r) {
    r.0 >= rx && r.0 + r.2 <= rx + rw + 0.5 && r.1 >= ry && r.1 + r.3 <= ry + rh + 0.5 && r.3 <= 2.5
  })
  ticks.sort_by(fn(a, b) { a.1.compare(b.1) })
  let asked = outline_rows_asked(calls).length()
  // (the first tick: 林's 星期六 09:12; pointed at beside it, in its room across the press)
  t.move_to(rx + rw / 2.0, ticks[0].1 + 1.0)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_eq(outline_rows_asked(calls).length(), asked + 1)
  let tip = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
  assert_eq(tip.length(), 1, msg="\{Repr(tip)}")
  assert_true(tip[0].has_prefix("早，今天想把发布清单") && tip[0].has_suffix("09:12"), msg="\{Repr(tip)}")
  // (the next: Ana's 09:40, its words held already, nothing asked)
  t.move_to(rx + rw / 2.0, ticks[1].1 + 1.0)
  t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
  assert_eq(outline_rows_asked(calls).length(), asked + 1)
  let tip = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
  assert_true(tip.length() == 1 && tip[0].has_prefix("签名证书下周三过期") && tip[0].has_suffix("09:40"), msg="\{Repr(tip)}")
  // (pressed there, it goes to that tick's message, which flashes, without opening the outline panel)
  t.tap(rx + rw / 2.0, ticks[1].1 + 1.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
  assert_true(gone_lit(t, said_3), msg="ts3 flashing")
  assert_true(t.semantics().iter().any(fn(s) { s.role == Button && s.label == "回到刚才的位置" }))
  assert_eq(outline_faults(t), [])
  // (on the longer chat's map: a press on its first tick reads the page before and goes to the chat's first said)
  let calls : Array[Made] = []
  let t = outline_tester(calls, mode="chat-outline-long")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let (rx, _, rw, _) = outline_buttons(t)[0]
  let first = outline_tick_places(t)
  t.tap(rx + rw / 2.0, first[0].0 + 1.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(outline_panel(t) is None)
  assert_true(gone_lit(t, "早，今天想把发布清单从头到尾过一遍"), msg="map tick 0 -> ts1 flashing")
  assert_eq(outline_faults(t), [])
}

///|
/// A phone's chat as it shows, a finger down at (x, y): what the window's tree holds it by, the finger then called off.
fn bar_key_held(x : Double, y : Double) -> @view.NodeId? {
  let t = screen_in("chat", corner_windows[0], "zh")
  t.press_at(x, y)
  let held = @ui.view_tree().unwrap().holder()
  t.touch(3, x, y)
  t.draw()
  held
}

///|
test "a phone's chat: each key of its bar, over the messages scrolled under the bar's glass, holds a finger down past its foot in its room; past the bar, a message's words held long are picked" {
  let t = screen_in("chat", corner_windows[0], "zh")
  let tree = @ui.view_tree().unwrap()
  // (the bar: frosted glass over the messages from the window's top)
  let bars = tree.drawn().filter(fn(d) { d.glass is Some(_) && d.y <= 0.0 && d.w >= 300.0 })
  assert_true(bars.length() == 1, msg="the bar's glass: \{bars.length()}")
  let foot = bars[0].y + bars[0].h
  // (its keys: back, 40 across, and the three round ones, 34)
  let keys = tree
    .press_boxes()
    .filter(fn(b) { b.1.1 < foot && b.1.3 - b.1.1 >= 34.0 && b.1.2 - b.1.0 <= 40.0 })
    .map(fn(b) { (tree.said_of(b.0).map(fn(s) { s.label }).unwrap_or(""), b.0, b.1) })
  assert_eq(keys.map(fn(k) { k.0 }), ["返回", "归档", "对话信息", "更多"])
  // (the messages' words under the bar there: the old view's own, were it seen)
  let runs = t.text_runs()
  assert_true(runs.iter().any(fn(r) { r.top < foot }), msg="no message's words under the bar")
  let past = match runs.search_by(fn(r) { r.top >= foot + 10.0 && r.x1 - r.x0 >= 30.0 }) {
    Some(i) => runs[i]
    None => @halt.saying("no message's words past the bar")
  }
  for k in keys {
    let (label, id, (x0, _, x1, y1)) = k
    // (past its foot in a finger's room (44): 4 below one 34 high, 1.5 below the back key, 40 high)
    let d = if 44.0 - (y1 - k.2.1) >= 10.0 { 4.0 } else { (44.0 - (y1 - k.2.1)) / 2.0 - 0.5 }
    assert_true(y1 + d < foot, msg="\{label}: \{d} below it is under the bar")
    assert_true(bar_key_held((x0 + x1) / 2.0, y1 + d) == Some(id), msg="\{label}: \{d} below it")
  }
  // (past the bar, on a message's words: a long press picks them, the old view's)
  let u = screen_in("chat", corner_windows[0], "zh")
  let (x, y) = (past.x0 + 24.0, (past.top + past.bottom) / 2.0)
  u.press_at(x, y)
  u.run_for(@ui.long_press_ms)
  u.release(x, y)
  u.run_for(@sfbase.pick_bar_in_ms)
  let p = @sfbase.picked.get()
  assert_true(p.ts != "" && p.b > p.a, msg="held long on \{past.text} at (\{x}, \{y}): \{Repr(p)}")
}
