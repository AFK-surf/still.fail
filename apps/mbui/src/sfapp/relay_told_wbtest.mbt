// The relay's note's @ menu (sfpages' relay_mention_menu: the people there to mention) dismissed by the hand: Escape,
// a press beside it, closed for that @ at that input's moment; the frame after closing nothing more.

///|
/// 大屏, a mouse's: the relay dialog to #dev open from a chat's row, "看下 @p" typed in its note, its @ menu shown.
fn relay_mentions_tester(calls? : Array[Made] = []) -> @ui.Tester raise {
  new_run()
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
          // (an aka with a space in it: Peng Xiao's, as the core's mentionQuery takes it)
          let (at, rows) : (Int, Array[Json]) = if note.has_suffix("@Peng X") {
            let before = note.view(end_offset=note.length() - 7).to_string()
            (note.length() - 7, [{ "id": "U1", "name": "pengxiao", "aka": "Peng Xiao", "note": before + "@pengxiao " }])
          } else if note.has_suffix("@p") {
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
  t.type_text("看下 @p")
  t.frame()
  t.frame()
  t.frame()
  assert_true(t.find("可以 @ 的人") is Some(_), msg="its menu shown: " + t.words().map(fn(w) { w.0 }).join("|"))
  t
}

///|
/// Whether the @ menu is closed for the @ it was open for.
fn mentions_closed() -> Bool {
  relaying.mention_closed.get() >= 0 && relaying.mention_closed.get() == number(relaying.mentions.get(), "at").to_int()
}

///|
test "wide: the relay's @ menu dismissed by Escape: closed for that @ as the key is taken; the frame after closes nothing more, the dialog staying" {
  let t = relay_mentions_tester()
  let seen = [mentions_closed()]
  t.key_told(@ui.key_escape, 0, t.time())
  seen.push(mentions_closed())
  t.draw()
  seen.push(mentions_closed())
  t.run_for(@kit.pop_out_ms)
  assert_eq(seen, [false, true, true])
  assert_true(t.find("可以 @ 的人") is None)
  assert_true(t.find("开头附一句（可选）") is Some(_), msg="the dialog went with the menu")
}

///|
test "wide: the relay's @ menu dismissed by a press beside it in the dialog: closed for that @ as it goes down; the frame after closes nothing more" {
  let t = relay_mentions_tester()
  let (lx, ly, lw, lh) = t.rect_of("开头附一句（可选）").unwrap()
  let seen = [mentions_closed()]
  t.touch_at(0, lx + lw / 2.0, ly + lh / 2.0, t.time())
  seen.push(mentions_closed())
  t.touch_at(2, lx + lw / 2.0, ly + lh / 2.0, t.time())
  t.draw()
  seen.push(mentions_closed())
  assert_eq(seen, [false, true, true])
  assert_true(t.find("开头附一句（可选）") is Some(_), msg="the dialog went with the menu")
}

///|
/// A person in the @ menu pressed (as the host hands it on), then Escape at once, a frame between or none: the note
/// then, and whether it was relayed.
fn relay_picked_then_escape(frames : Bool) -> (String, Int, Bool) raise {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  let (px, py, pw, ph) = t.rect_of("pengxiao").unwrap()
  t.touch_at(0, px + pw / 2.0, py + ph / 2.0, t.time())
  t.touch_at(2, px + pw / 2.0, py + ph / 2.0, t.time())
  if frames {
    t.frame()
  }
  // (what the press put in, as the Escape after it comes, and whether the dialog is there once it is taken)
  let note = relaying.note.text()
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  t.run_for(@kit.pop_out_ms)
  (note, named(calls, "chat.relay").length(), t.find("开头附一句（可选）") is Some(_))
}

///|
test "wide: a person pressed in the relay's @ menu, then Escape at once: put in once, not relayed, the Escape the dialog's (the menu done with as it is chosen), a frame between or none" {
  // (the menu's opening over as the one is chosen: Escape after it the dialog's, a frame between or none)
  assert_eq((relay_picked_then_escape(false), relay_picked_then_escape(true)), (("看下 @pengxiao ", 0, false), ("看下 @pengxiao ", 0, false)))
}

///|
/// ↓ to the second person in the @ menu (a frame drawn), then `key` (Enter or Tab) and Escape at once as the host
/// hands them on, a frame between or none: the note then, and whether it was relayed.
fn relay_keyed_then_escape(key : Int, frames : Bool) -> (String, Int, Bool) raise {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  t.key(@ui.key_code_down)
  t.frame()
  t.key_told(key, 0, t.time())
  if frames {
    t.frame()
  }
  // (what the key put in, as the Escape after it comes, and whether the dialog is there once it is taken)
  let note = relaying.note.text()
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  t.run_for(@kit.pop_out_ms)
  (note, named(calls, "chat.relay").length(), t.find("开头附一句（可选）") is Some(_))
}

///|
test "wide: the relay's @ menu, ↓ then Enter and Escape at once: the one chosen put in once, not relayed, a frame between or none" {
  assert_eq((relay_keyed_then_escape(@ui.key_code_enter, false), relay_keyed_then_escape(@ui.key_code_enter, true)), (("看下 @peter ", 0, false), ("看下 @peter ", 0, false)))
}

///|
test "wide: the relay's @ menu, ↓ then Tab and Escape at once: Tab puts the one chosen in, once, a frame between or none" {
  assert_eq((relay_keyed_then_escape(@ui.key_tab, false), relay_keyed_then_escape(@ui.key_tab, true)), (("看下 @peter ", 0, false), ("看下 @peter ", 0, false)))
}

///|
/// The @ menu shown, then `first` (as the host hands it on, no frame after it) and Enter at once, a frame drawn once
/// both are told: the note then, and whether it was relayed.
fn relay_then_enter(first : (@ui.Tester) -> Unit) -> (String, Int) raise {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  first(t)
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.draw()
  t.run_for(@kit.pop_out_ms)
  (relaying.note.text(), named(calls, "chat.relay").length())
}

///|
test "wide: the relay's @ menu closed by Escape, then Enter before a frame: nothing put in from the menu it closed" {
  let (note, _) = relay_then_enter(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) })
  assert_true(note.has_prefix("看下 @p") && !note.contains("@pengxiao") && !note.contains("@peter"), msg=note)
}

///|
test "wide: the relay's @ menu, Enter twice before a frame: the one chosen put in once, the second Enter the note's" {
  let (note, _) = relay_then_enter(fn(t) { t.key_told(@ui.key_code_enter, 0, t.time()) })
  assert_eq(note, "看下 @pengxiao ")
}

///|
test "wide: the relay's @ menu, a letter typed, Enter and Escape before a frame: the one shown chosen put in for the @ and the letter, as Enter comes, the Escape after it the dialog's" {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  t.text_told("e", t.time())
  t.key_told(@ui.key_code_enter, 0, t.time())
  // (the one the menu shows chosen, put in for the `@` and what was typed after it, as Enter comes; the menu done with
  // then, the Escape after it the dialog's)
  let note = relaying.note.text()
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  t.run_for(@kit.pop_out_ms)
  assert_eq((note, named(calls, "chat.relay").length(), t.find("开头附一句（可选）") is Some(_)), ("看下 @pengxiao ", 0, false))
}

///|
test "wide: the relay's @ menu for an aka with a space in it (@Peng X): Enter puts that one in" {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  t.backspace()
  t.type_text("Peng X")
  t.frame()
  t.frame()
  assert_true(t.find("可以 @ 的人") is Some(_), msg=relaying.note.text())
  t.key(@ui.key_code_enter)
  t.frame()
  assert_eq((relaying.note.text(), named(calls, "chat.relay").length()), ("看下 @pengxiao ", 0))
}
