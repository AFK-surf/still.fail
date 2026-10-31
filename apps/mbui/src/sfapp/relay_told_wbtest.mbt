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
fn relay_picked_then_escape(frames : Bool) -> (String, Int) raise {
  let calls : Array[Made] = []
  let t = relay_mentions_tester(calls~)
  let (px, py, pw, ph) = t.rect_of("pengxiao").unwrap()
  t.touch_at(0, px + pw / 2.0, py + ph / 2.0, t.time())
  t.touch_at(2, px + pw / 2.0, py + ph / 2.0, t.time())
  if frames {
    t.frame()
  }
  t.key_told(@ui.key_escape, 0, t.time())
  t.draw()
  t.run_for(@kit.pop_out_ms)
  (relaying.note.text(), named(calls, "chat.relay").length())
}

///|
test "wide: a person pressed in the relay's @ menu, then Escape at once: put in once, not relayed, a frame between or none" {
  assert_eq((relay_picked_then_escape(false), relay_picked_then_escape(true)), (("看下 @pengxiao ", 0), ("看下 @pengxiao ", 0)))
}
