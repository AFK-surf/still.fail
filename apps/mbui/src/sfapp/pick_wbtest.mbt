// Picking a passage of a message with a finger, over the made-up chat, on whichever page the chat is made: the old
// page's own pick and bar (pick.mbt) or the window's tree's words picked (mbui's finger_select.mbt, the system's text
// menu with the page's own items: sfpages' chat_quote_node). What is picked is read as the last frame painted it
// (Tester::picking); the bar is the items drawn over it or the system's text menu offering them (bar_offers). The fake
// host has no word boundaries of its own: a Han character is a word, letters and digits together are one.

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
    t.move_to(x0 + (x1 - x0) * k, y0 + (y1 - y0) * k)
  }
}

///|
/// Whether the bar over a passage a finger picked offers `item`, on a page of either kind: drawn (the old page's own
/// bar), or in the system's text menu over it (its copy and select all; else one of the page's own items there).
fn bar_offers(t : @ui.Tester, item : String) -> Bool {
  if t.find(item) is Some(_) {
    return true
  }
  let (shown, _, _, _, _, can) = t.text_menu()
  shown &&
  (match item {
    "复制" => (can & @hostapi.text_menu_copy) != 0
    "全选" => (can & @hostapi.text_menu_select_all) != 0
    _ => t.text_menu_own().contains(item)
  })
}

///|
/// `item` chosen on the bar over a passage a finger picked, where bar_offers finds it.
fn bar_choose(t : @ui.Tester, item : String) -> Unit raise {
  if t.find(item) is Some(_) {
    t.tap_text(item)
    return
  }
  match item {
    "复制" => t.key(@ui.key_code_copy)
    "全选" => t.key(@ui.key_code_select_all)
    _ => {
      let own = t.text_menu_own()
      for k, w in own {
        if w == item {
          t.key(@hostapi.key_menu_own + k)
          return
        }
      }
      fail("no \{item} on the bar: \{Repr(own)}")
    }
  }
}

///|
/// What is picked now, as the last frame painted it: failing where nothing is.
fn picking_now(t : @ui.Tester) -> @ui.Picking raise {
  match t.picking() {
    Some(p) => p
    None => fail("nothing picked")
  }
}

///|
test "held still on a message's words: the word under the finger is picked, the bar over it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  // (a word: a Han character; its handles at its ends)
  guard t.picking() is Some(p) && p.finger && p.ends.get(0) is Some(Some((sx, sy))) else {
    fail("no handles over what the finger picked: \{Repr(t.picking())}")
  }
  assert_eq(p.text.length(), 1)
  // felt as it picked, once
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  assert_true(bar_offers(t, "引用"))
  assert_true(bar_offers(t, "复制"))
  assert_true(bar_offers(t, "全选"))
  // the passage drawn behind the words (translucent, a line's height), from its start's handle
  let grounds = t.drawn_rects().filter(fn(r) { (r.4 & 0xFFL) < 0xFFL && r.3 > 8.0 && r.3 < 60.0 })
  assert_true(
    grounds.iter().any(fn(r) { (r.0 - sx).abs() < 1.5 && sy > r.1 - 30.0 && sy < r.1 + r.3 + 30.0 }),
    msg="no passage drawn from its start's handle at \{sx},\{sy}",
  )
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
  let first = picking_now(t)
  slide(t, x, y, x + 60.0, y, 6)
  t.release(x + 60.0, y)
  let now = picking_now(t)
  assert_true(now.text.has_prefix(first.text) && now.text.length() > first.text.length() + 2, msg="\{Repr((first, now))}")
  assert_eq(t.list_offset(), before)
  // lifting it tapped nothing: still picked
  t.run_for(pick_bar_in_ms)
  assert_eq(picking_now(t).text, now.text)
  t.assert_idle()
}

///|
test "复制 puts the passage on the clipboard and lets go; 全选 takes all of the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  let one = picking_now(t).text
  // (the old page's bar its own, which says 已复制; the system's text menu's copy is the system's)
  let own_bar = t.find("复制") is Some(_)
  bar_choose(t, "复制")
  t.frame()
  assert_eq(t.clipboard(), one)
  assert_true(t.picking() is None, msg="still picked: \{Repr(t.picking())}")
  if own_bar {
    // (said at once, read out: seen as it has come in, toast_said)
    assert_true(toast_said(t, "已复制"))
    t.run_for(@kit.presence_in_ms)
    assert_true(t.find("已复制") is Some(_))
    // (its toast gone: it says 已复制 over the composer, where the bar of the next passage picked stands)
    t.run_for(@sf.toast_ms)
  }
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  bar_choose(t, "全选")
  t.frame()
  assert_true(picking_now(t).text.has_prefix("做完了：列表、跳到最新的按钮"), msg="\{Repr(t.picking())}")
  bar_choose(t, "复制")
  t.frame()
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
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let words = "好，就按这个改，顺便把深色模式的截图也换掉"
  assert_true(t.find("未发送") is Some(_))
  hold_on(t, words) |> ignore
  let one = picking_now(t).text
  assert_true(bar_offers(t, "复制"))
  // The passage can be quoted too; there is no message at the station to link to or share yet.
  assert_true(bar_offers(t, "引用"))
  assert_true(t.query(Button, label="复制消息链接") is None)
  assert_true(t.query(Button, label="多选") is None)
  assert_false(bar_offers(t, "多选"))
  assert_false(bar_offers(t, "复制链接"))
  bar_choose(t, "复制")
  assert_eq(t.clipboard(), one)
  t.run_for(@sf.toast_ms)
  hold_on(t, words) |> ignore
  bar_choose(t, "全选")
  bar_choose(t, "复制")
  assert_eq(t.clipboard(), words)
  assert_true(t.find("未发送") is Some(_))
  t.run_for(@sf.toast_ms)
  hold_on(t, words) |> ignore
  // (each chosen on the bar as it stands: no frame between)
  bar_choose(t, "全选")
  bar_choose(t, "引用")
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
  assert_true(bar_offers(t, "引用"))
  bar_choose(t, "全选")
  t.frame()
  bar_choose(t, "复制")
  t.frame()
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
      calls.push({ name, params, bytes: None, done })
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
  let picked = picking_now(t)
  fix_clock_set(clock, fix_deliver_ms)
  t.draw()
  assert_eq(t.picking().map(fn(p) { p.text }), Some(picked.text))
  assert_true(bar_offers(t, "引用"))
  bar_choose(t, "全选")
  t.frame()
  bar_choose(t, "引用")
  t.frame()
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
  match t.query(Button, label="多选") {
    Some(_) => t.click(Button, label="多选")
    None => bar_choose(t, "多选")
  }
  t.frame()
  assert_true(t.picking() is None, msg="still picked: \{Repr(t.picking())}")
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
  // (its end's handle, where a finger takes it)
  guard t.picking() is Some(first) && first.ends.get(1) is Some(Some((kx, ky))) else {
    fail("no end's handle: \{Repr(t.picking())}")
  }
  t.press_at(kx, ky)
  slide(t, kx, ky, kx + 50.0, ky, 5)
  t.release(kx + 50.0, ky)
  let now = picking_now(t)
  assert_true(now.text.has_prefix(first.text) && now.text.length() > first.text.length() + 2, msg="\{Repr((first, now))}")
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
  // (in the last message's first paragraph, its end's handle where a finger takes it)
  guard t.picking() is Some(first) && first.ends.get(1) is Some(Some((kx, ky))) else {
    fail("no end's handle: \{Repr(t.picking())}")
  }
  assert_true(long_answer[0].contains(first.text), msg="\{Repr(first)}")
  // the first paragraph runs over several lines
  assert_true(t.run_rects(long_answer[0]).length() > 3, msg="\{Repr(t.run_rects(long_answer[0]))}")
  // the short one: its line ends well short of the screen's right
  guard t.run_rects(long_answer[1]) is [line, ..] else { fail("the short paragraph not drawn") }
  assert_true(line.0 + line.2 + 60.0 < 390.0)
  // the end's handle taken down to the short line, the finger past its end (as far from the line's middle as it took
  // the handle from its first line's): the end at the line's end, away from the finger
  guard t.run_rects(long_answer[0]) is [held, ..] else { fail("the first paragraph not drawn") }
  let off = ky - (held.1 + held.3 / 2.0)
  let (tx, ty) = (line.0 + line.2 + 60.0, line.1 + line.3 / 2.0 + off)
  t.press_at(kx, ky)
  slide(t, kx, ky, tx, ty, 8)
  let now = picking_now(t)
  assert_true(now.text.has_prefix(first.text) && now.text.has_suffix(long_answer[1]), msg="\{Repr(now)}")
  t.release(tx, ty)
  // let go: no tap away from it, the passage kept and its bar back over it
  assert_eq(t.picking().map(fn(p) { p.text }), Some(now.text))
  t.frame()
  assert_true(bar_offers(t, "复制"))
  t.assert_idle()
}

///|
test "a tap anywhere else lets go of it, as back does" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(t.picking() is Some(_))
  t.tap(195.0, 300.0)
  t.frame()
  assert_true(t.picking() is None, msg="still picked: \{Repr(t.picking())}")
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  assert_true(t.picking() is Some(_))
  t.back()
  t.frame()
  assert_true(t.picking() is None, msg="still picked: \{Repr(t.picking())}")
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

///|
/// How long a finger is held still for a long press (ViewConfiguration's long press timeout, as Compose has it).
let long_press_ms : Double = @ui.long_press_ms
