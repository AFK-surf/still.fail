// The relay with keyboard and mouse (sfpages relay.mbt, Relay.tsx RelayDialog: the presenters' dialog): from a row's menu, the places the station's
// bots are in as the core offers them, one picked with its note, relayed there.

///|
/// 「那里由 … 回复」 at the right under the place picked: its end in line with the place's note's (更换), right of its name.
fn relay_via_at_right(t : @ui.Tester) -> Unit raise {
  let (name_x, _, _, _) = t.rect_of("#dev").unwrap()
  let (via_x, _, _, _) = t.rect_of("那里由").unwrap()
  let (end_x, _, end_w, _) = t.rect_of("回复").unwrap()
  let change = match t.rect_of("更换") {
    Some(r) => r
    None => t.rect_of("新 thread · 更换").unwrap()
  }
  assert_true(via_x > name_x)
  assert_eq(end_x + end_w, change.0 + change.2)
}

///|
test "wide: 接力到频道… from a row's menu: the dialog lists the bot's places, one picked shows who replies there, 接力 relays it (chat.relay)" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.right_click(x, y)
  t.frame()
  t.tap_text("接力到频道…")
  t.frame()
  assert_eq(named(calls, "chat.relayPlaces").length(), 1)
  t.frame()
  assert_true(t.find("接力到频道") is Some(_))
  // its search typed into at once: the keyboard's focus there as it opens (the presenters' `field`)
  assert_true(t.ctx().field_focused(), msg="the search not focused as the relay opened with keyboard and mouse")
  assert_true(t.find("#dev") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("🔒 #ops") is Some(_))
  // relayed to before: first
  let (_, dev_y) = t.find("#dev").unwrap()
  let (_, ops_y) = t.find("🔒 #ops").unwrap()
  assert_true(dev_y < ops_y)
  t.tap_text("#dev")
  t.frame()
  assert_true(t.find("接力到 #dev") is Some(_))
  assert_true(t.find("开头附一句（可选）") is Some(_))
  // who replies there, under the place at its right: its end in line with the place's 更换
  relay_via_at_right(t)
  t.tap_text("接力到 #dev")
  t.frame()
  let relayed = named(calls, "chat.relay")
  assert_eq(relayed.length(), 1)
  assert_eq(text(Some(relayed[0].params), "connect"), "slack-1")
  assert_eq(text(Some(relayed[0].params), "channel"), "C1")
  // the dialog gone, where it went said
  assert_true(t.find("开头附一句（可选）") is None)
  assert_true(t.find("已接力到 #dev") is Some(_))
}

///|
test "wide: an @ typed in the relay's note offers the people there in a popover (chat.relayPeople, chat.relayMentions); ↓ and Enter, or a press, put the one chosen in; Escape closes it for that @, the dialog staying" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let people : Json = [{ "id": "U1", "name": "pengxiao", "aka": "Peng Xiao" }, { "id": "U2", "name": "peter" }]
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "chat.relayPeople" => done(Ok({ "people": people }))
        // (whom it finds, the core's: relay-pick.ts mentionView, tested there)
        "chat.relayMentions" => {
          let note = text(Some(params), "note")
          let (at, rows) : (Int, Array[Json]) = if note.has_suffix("@p") {
            let before = note.view(end_offset=note.length() - 2).to_string()
            (note.length() - 2, [
              { "id": "U1", "name": "pengxiao", "aka": "Peng Xiao", "note": before + "@pengxiao " },
              { "id": "U2", "name": "peter", "note": before + "@peter " },
            ])
          } else {
            (-1, [])
          }
          done(Ok({ "query": if at < 0 { Json::null() } else { Json::string("p") }, "at": Json::number(at.to_double()), "rows": Json::array(rows) }))
        }
        _ => (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.right_click(x, y)
  t.frame()
  t.tap_text("接力到频道…")
  t.frame()
  t.frame()
  t.tap_text("#dev")
  t.frame()
  // nobody asked for till an @ is typed
  t.type_text("看下 ")
  t.frame()
  assert_eq(named(calls, "chat.relayPeople").length(), 0)
  t.type_text("@p")
  t.frame()
  t.frame()
  let asked = named(calls, "chat.relayPeople")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "connect"), "slack-1")
  assert_eq(text(Some(asked[0].params), "channel"), "C1")
  t.frame()
  assert_true(t.find("可以 @ 的人") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("Peng Xiao") is Some(_))
  // under the note (open only while the note has the focus: it keeps the keys)
  let (_, label_y, _, label_h) = t.rect_of("开头附一句（可选）").unwrap()
  let (_, menu_y, _, _) = t.rect_of("pengxiao").unwrap()
  assert_true(menu_y > label_y + label_h + 36.0, msg="the menu over the note")
  // ↓ chooses the next, Enter puts it in (not relaying)
  t.key(@ui.key_code_down)
  t.enter()
  t.frame()
  assert_eq(relaying.note.text(), "看下 @peter ")
  assert_eq(named(calls, "chat.relay").length(), 0)
  // (gone once its way out is over)
  t.run_for(@kit.pop_out_ms)
  assert_true(t.find("可以 @ 的人") is None, msg="still offered once picked")
  // another @: Escape closes the menu for it, and the dialog stays
  t.type_text("@p")
  t.frame()
  t.frame()
  assert_true(t.find("可以 @ 的人") is Some(_))
  t.key(@ui.key_escape)
  t.run_for(@kit.pop_out_ms)
  assert_true(t.find("可以 @ 的人") is None)
  assert_true(t.find("开头附一句（可选）") is Some(_), msg="the dialog went with the menu")
  assert_eq(relaying.note.text(), "看下 @peter @p")
  // a third: a press puts one in
  t.type_text(" @p")
  t.frame()
  t.frame()
  t.tap_text("pengxiao")
  t.frame()
  assert_eq(relaying.note.text(), "看下 @peter @p @pengxiao ")
  assert_eq(named(calls, "chat.relayPeople").length(), 1, msg="read once for the place")
  t.tap_text("接力到 #dev")
  t.frame()
  let relayed = named(calls, "chat.relay")
  assert_eq(text(Some(relayed[0].params), "note"), "看下 @peter @p @pengxiao ")
}
