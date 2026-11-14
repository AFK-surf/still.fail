// What a chat's page made as nodes tells the core of a message come at the list's foot while the list is at rest at its
// end is fact once it is so (the chat's seventh principle: read-up-to is the last message seen whole): said while the
// chat shows, it makes its way in, and the core is told the end not seen in the change that brings it, never told it
// seen before its words are drawn whole, and told the end seen and it read once, at the moment its way ends; caught up
// on (not said), it is simply there, seen and at the end in that change. On 小屏 and 大屏, its rows on the host's
// pixels, every frame a device draws (Tester::run_shown) (the coordinator of the migration, 2026-11-14; mbui's
// src/view/list_sight_coming_test.mbt).

///|
/// The words of the message come.
let sw_words : String = "我也来看看"

///|
/// What the core was told of the chat as it shows (`client.focus {chat}`): when, its end, the message read.
priv struct SwTold {
  at : Double
  end : Bool
  seen : Double
}

///|
/// The message's words where they are drawn in a frame: when, how opaque, their top and height (none: not drawn).
priv struct SwDrawn {
  at : Double
  words : (Double, Double, Double)?
}

///|
/// The words `w` of the window's tree where they are drawn: how opaque, top, height.
fn sw_drawn_now(w : String) -> (Double, Double, Double)? {
  for d in @ui.view_tree().unwrap().drawn() {
    if d.bones == 0L && d.words.contains(w) {
      return Some((d.alpha, d.y, d.h))
    }
  }
  None
}

///|
/// The fixture's chat s-c1 as nodes on `screen` at rest at its end, then message 171 come at its foot, said (`said`) or
/// caught up on: what the core was told of the chat from then, the moment of the change, when the ways it set off end
/// (the window's tree's, -1: none), and each frame drawn for 600 ms after it.
fn sw_run(screen : (String, Double, Double, Int), said : Bool) -> (Array[SwTold], Double, Double, Array[SwDrawn]) {
  let (_, w, h, platform) = screen
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  let told : Array[SwTold] = []
  let now : Ref[() -> Double] = Ref(fn() { -1.0 })
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "client.focus" {
        match field(Some(params), "chat") {
          Some(chat) =>
            told.push({
              at: (now.val)(),
              end: field(Some(chat), "end") is Some(True),
              seen: @sfbase.number(Some(chat), "seen"),
            })
          None => ()
        }
      }
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  now.val = fn() { t.time() }
  t.set_rows_on_pixels(true)
  t.run_for(@ui.move_most_ms)
  let from = told.length()
  let frames : Array[SwDrawn] = []
  t.each_frame(Some(fn() { frames.push({ at: t.time(), words: sw_drawn_now(sw_words) }) }))
  fix_later(fix_said_ms, fn() {
    let extra : Map[String, Json] = if said {
      { "ts": Json::string("ana171"), "said": Json::boolean(true) }
    } else {
      { "ts": Json::string("ana171") }
    }
    fix_chat("s-c1").sent.push(msg(171, "person", by_person("安娜"), sw_words, "刚刚", extra))
  })
  fix_clock_set(clock, clock.val + fix_said_ms)
  let cause = t.time()
  t.draw()
  let ends = @ui.view_tree().unwrap().ways_end()
  t.run_shown(600.0)
  t.each_frame(None)
  fix_clock.val = None
  (told[from:].to_owned(), cause, ends, frames)
}

///|
/// The first frame from which the words are drawn whole (opaque, where and as tall as they rest, in the last frame) on;
/// none where they never are.
fn sw_whole_at(frames : Array[SwDrawn]) -> Double? {
  guard frames.last() is Some({ words: Some((_, ry, rh)), .. }) else { return None }
  let mut at : Double? = None
  for f in frames {
    match f.words {
      Some((a, y, h)) if a >= 1.0 && (y - ry).abs() < 1.0e-6 && (h - rh).abs() < 1.0e-6 =>
        if at is None {
          at = Some(f.at)
        }
      _ => at = None
    }
  }
  at
}

///|
test "chat as nodes, a message said at its foot at its end: the end told not seen at the change, the message never told read before its words are drawn whole, told the end seen and it read once, as its way ends, on 小屏 and 大屏" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (told, cause, ends, frames) = sw_run(screen, true)
    let name = screen.0
    guard sw_whole_at(frames) is Some(whole) else { fail("\{name}: its words never drawn whole") }
    assert_true(whole > cause, msg="\{name}: its words whole at \{whole}, the change at \{cause}")
    let s = told.map(fn(x) { "\{x.at} end=\{x.end} seen=\{x.seen}" }).join("; ")
    // (at the change: the end not seen)
    guard told is [first, ..] else { fail("\{name}: nothing told") }
    assert_true(first.at == cause && !first.end && first.seen < 171.0, msg="\{name}: \{s}")
    // (never told read before its words are drawn whole)
    for x in told {
      assert_true(x.seen < 171.0 || x.at >= whole, msg="\{name}: told it read at \{x.at}, its words whole at \{whole}: \{s}")
      assert_true(!x.end || x.at >= whole, msg="\{name}: told the end seen at \{x.at}, its words whole at \{whole}: \{s}")
    }
    // (told the end seen and it read once, at its way's end, its words whole by then (on the host's pixels its row is
    // at its rest a frame or so before its way ends: mbui's rows_on_way))
    let read = told.filter(fn(x) { x.end && x.seen == 171.0 })
    assert_eq(read.length(), 1, msg="\{name}: \{s}")
    assert_true(ends > cause && read[0].at == ends, msg="\{name}: its way ends at \{ends}, its words whole at \{whole}: \{s}")
    assert_eq(told.length(), 2, msg="\{name}: \{s}")
  }
}

///|
test "chat as nodes, a message caught up on at its foot at its end: simply there, the end seen and it read told in the change, once, on 小屏 and 大屏" {
  for screen in [("小屏", 390.0, 844.0, 2), ("大屏", 1280.0, 800.0, 0)] {
    let (told, cause, _, frames) = sw_run(screen, false)
    let name = screen.0
    let s = told.map(fn(x) { "\{x.at} end=\{x.end} seen=\{x.seen}" }).join("; ")
    assert_eq(sw_whole_at(frames), Some(cause), msg="\{name}: its words whole in the change's frame")
    assert_eq(told.length(), 1, msg="\{name}: \{s}")
    assert_true(told[0].at == cause && told[0].end && told[0].seen == 171.0, msg="\{name}: \{s}")
  }
}
