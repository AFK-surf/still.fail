// Picking a passage of a message (pick.mbt), over the made-up chat. The fake host has no word
// boundaries of its own: a Han character is a word, letters and digits together are one.

///|
/// The finger held still on `words` a long press's time (and a little more), then let go there; where it was.
fn hold_on(t : @ui.Tester, words : String) -> (Double, Double) {
  // near the start of its first line (the message's words run on past it)
  let (rx, ry, _, _) = t.rect_of(words).unwrap()
  let (x, y) = (rx + 24.0, ry + 8.0)
  t.press_at(x, y)
  t.run_for(long_press_ms)
  t.release(x, y)
  // (its bar come in: @sfbase.pick_bar_in_ms)
  t.run_for(pick_bar_in_ms)
  (x, y)
}

///|
/// A finger already down moved from (x0, y0) to (x1, y1) in `steps` moves, a frame apart.
fn slide(t : @ui.Tester, x0 : Double, y0 : Double, x1 : Double, y1 : Double, steps : Int) -> Unit {
  for i in 1..=steps {
    let k = i.to_double() / steps.to_double()
    t.move(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
  }
}

///|
test "held still on a message's words: the word under the finger is picked, the bar over it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(pk.ts != "")
  assert_eq(pk.sel.b - pk.sel.a, 1)
  // felt as it picked, once
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  assert_true(t.find("引用") is Some(_))
  assert_true(t.find("复制") is Some(_))
  assert_true(t.find("全选") is Some(_))
  // the passage drawn behind the words, in the accent at 26%
  let ground = @sf.alpha(@sf.theme().p.accent, 0.26)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == ground }))
  t.assert_idle()
}

///|
test "a finger sliding on widens it by words, from the word first held; the list holds still" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let (rx, ry, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  let (x, y) = (rx + 24.0, ry + 8.0)
  let before = t.list_offset()
  t.press_at(x, y)
  t.run_for(long_press_ms)
  let first = (pk.sel.a, pk.sel.b)
  slide(t, x, y, x + 60.0, y, 6)
  t.release(x + 60.0, y)
  assert_eq(pk.sel.a, first.0)
  assert_true(pk.sel.b > first.1 + 2)
  assert_eq(t.list_offset(), before)
  // lifting it tapped nothing: still picked
  assert_true(pk.ts != "")
  t.run_for(pick_bar_in_ms)
  t.assert_idle()
}

///|
test "复制 puts the passage on the clipboard and lets go; 全选 takes all of the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let one = t.ctx().words_of(pk.sel.key).unwrap().slice(pk.sel.a, pk.sel.b)
  t.tap_text("复制")
  assert_eq(t.clipboard(), one)
  assert_eq(pk.ts, "")
  // (said at once, read out: seen as it has come in, toast_said)
  assert_true(toast_said(t, "已复制"))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已复制") is Some(_))
  // (its toast gone: it says 已复制 over the composer, where the bar of the next passage picked stands)
  t.run_for(@sf.toast_ms)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.tap_text("全选")
  assert_true(t.find("全选") is None)
  t.tap_text("复制")
  assert_true(t.clipboard().has_prefix("做完了：列表、跳到最新的按钮"))
}

///|
test "a message that did not go: a finger can select and copy its words" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("chat-failed")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let words = "好，就按这个改，顺便把深色模式的截图也换掉"
  assert_true(t.find("未发送") is Some(_))
  hold_on(t, words) |> ignore
  assert_true(pk.ts != "")
  assert_true(t.find("复制") is Some(_))
  // The passage can be quoted too; there is no message at the station to link to or share yet.
  assert_true(t.find("引用") is Some(_))
  assert_true(t.query(Button, label="复制消息链接") is None)
  assert_true(t.query(Button, label="多选") is None)
  let one = t.ctx().words_of(pk.sel.key).unwrap().slice(pk.sel.a, pk.sel.b)
  t.tap_text("复制")
  assert_eq(t.clipboard(), one)
  t.run_for(@sf.toast_ms)
  hold_on(t, words) |> ignore
  t.tap_text("全选")
  t.tap_text("复制")
  assert_eq(t.clipboard(), words)
  assert_true(t.find("未发送") is Some(_))
  t.run_for(@sf.toast_ms)
  hold_on(t, words) |> ignore
  t.tap_text("全选")
  t.tap_text("引用")
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  let q = field(Some(quoted[0].params), "quote")
  assert_eq(text(q, "text"), words)
  assert_eq(text(q, "ts"), "")
}

///|
test "a message on its way: a finger can select and copy its words" {
  new_run()
  let src = fixture("chat-sending")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let words = "好，就按这个改，顺便把深色模式的截图也换掉"
  hold_on(t, words) |> ignore
  assert_true(t.find("引用") is Some(_))
  t.tap_text("全选")
  t.tap_text("复制")
  assert_eq(t.clipboard(), words)
}

///|
test "a message picked on its way and then delivered keeps its selection and quotes the delivered message" {
  new_run()
  let calls : Array[Made] = []
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  t.run_for(@sfbase.flight_ms)
  hold_on(t, "测试一下") |> ignore
  let picked = pk.ts
  let serial = @sfbase.picked.get().serial
  assert_true(picked != "")
  fix_clock_set(clock, fix_deliver_ms)
  t.draw()
  assert_eq(pk.ts, picked)
  assert_eq(@sfbase.picked.get().serial, serial)
  assert_true(t.find("引用") is Some(_))
  t.tap_text("全选")
  t.tap_text("引用")
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  let q = field(Some(quoted[0].params), "quote")
  assert_eq(text(q, "text"), "测试一下")
  assert_true(text(q, "ts").has_prefix("sent"))
  fix_clock.val = None
}

///|
test "多选 on the bar lets go and opens the chat's picture with that message alone ticked (chat.publishPreview of the whole chat)" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.click(Button, label="多选")
  assert_eq(pk.ts, "")
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // (the whole chat asked: the message ticked alone once it is read)
  assert_true(field(Some(asked[0].params), "turn") is None)
}

///|
test "a handle moves its end: the passage's end follows the finger" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let w = t.ctx().words_of(pk.sel.key).unwrap()
  let lines = w.rects(pk.sel.a, pk.sel.b)
  let last = lines[lines.length() - 1]
  // the end's knob is under the line's end
  let (kx, ky) = (last.0 + last.2, last.1 + last.3 + 6.0)
  let was = pk.sel.b
  t.press_at(kx, ky)
  slide(t, kx, ky, kx + 50.0, ky, 5)
  t.release(kx + 50.0, ky)
  assert_true(pk.sel.b > was + 2)
  assert_true(pk.ts != "")
  t.assert_idle()
}

///|
/// The last message's paragraphs in long_answer_core: one that runs over several lines, a short one, one more.
let long_answer : Array[String] = [
  "列表的每一行先按估计的高度占位，滚到附近时再量出真实的高度记下来，下次打开直接用量过的值。这样往上翻早先的消息不会跳，往下拉到最新也不会抖。跳到最新的按钮只在离底部超过一屏时出现，点一下就滚回去。",
  "截图也换了。",
  "深色模式一起看过了，颜色都对。",
]

///|
/// The made-up chat with its last message (ts11) as long_answer's paragraphs, its Markdown tree with it.
fn long_answer_core(calls : Array[Made]) -> @ui.Tester {
  let sb = StringBuilder()
  let tree : Array[Json] = []
  for k, p in long_answer {
    if k > 0 {
      sb.write_string("\n\n")
    }
    let start = sb.to_string().length()
    sb.write_string(p)
    tree.push(["p", [[Json::number(start.to_double()), Json::number((start + p.length()).to_double())]]])
  }
  let text = sb.to_string()
  fake_core(calls, over=fn(name, tp) {
    match (name, tp.value) {
      ("chat", Some(Object(o))) => {
        let all = match o.get("messages") {
          Some(Array(a)) => a.copy()
          _ => []
        }
        match all.last() {
          Some(Object(m)) => {
            let m2 = m.copy()
            m2["text"] = Json::string(text)
            m2["md"] = Json::array(tree)
            all[all.length() - 1] = Json::object(m2)
          }
          _ => ()
        }
        let o2 = o.copy()
        o2["messages"] = Json::array(all)
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
}

///|
test "a handle moved down lines to a short line and let go past its end: still picked, to that line's end" {
  let calls : Array[Made] = []
  let t = long_answer_core(calls)
  hold_on(t, "列表的每一行先按估计的高度占位") |> ignore
  assert_true(pk.ts == "ts11")
  let w = t.ctx().words_of(pk.sel.key).unwrap()
  let lines = w.rects(pk.sel.a, pk.sel.b)
  let last = lines[0]
  // the first paragraph runs over several lines
  let first = w.pieces[0]
  assert_true(first.h > 3.0 * last.3)
  // the short one: its line ends well short of the screen's right
  let short = w.pieces[1]
  let short_end = short.start + long_answer[1].length()
  let line = w.rects(short.start, short_end)[0]
  assert_true(line.0 + line.2 + 60.0 < 390.0)
  // the end's knob (under the line's end) taken down to the short line, the finger past its end: the end at the line's
  // end, its handle there, away from the finger
  let (kx, ky) = (last.0 + last.2, last.1 + last.3 + 6.0)
  let (tx, ty) = (line.0 + line.2 + 60.0, line.1 + line.3 / 2.0 + last.3 / 2.0 + 6.0)
  t.press_at(kx, ky)
  slide(t, kx, ky, tx, ty, 8)
  assert_eq(pk.sel.b, short_end)
  t.release(tx, ty)
  // let go: no tap away from it, the passage kept and its bar back over it
  assert_eq(pk.ts, "ts11")
  assert_eq(pk.sel.b, short_end)
  t.frame()
  assert_true(t.find("复制") is Some(_))
  t.assert_idle()
}

///|
test "a tap anywhere else lets go of it, as back does" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.tap(195.0, 300.0)
  assert_eq(pk.ts, "")
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.back()
  assert_eq(pk.ts, "")
  // the chat is still the page shown (back let go of the pick only)
  assert_eq(app.nav.depth(), 2)
}

///|
test "its words no longer laid out: what was picked goes in that very frame, not frames later" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(pk.ts != "")
  // (as if its message scrolled far off: no box laid out holds its words now)
  pk.sel.key = "gone"
  t.frame()
  assert_eq(pk.ts, "")
  t.assert_idle()
}
