// Words of three lines sent from the composer of a chat's page made as nodes (sfbase's chat_page_nodes on), in a chat
// and as a new chat's first: nothing there lets go of a flight (its list is no old list: flight_frame, flight_placed),
// so none is started there till the flights' step, and nothing holds the composer as tall as the words took in it.
// It is back at its one line's height in the press's frame, its ground and room down by move_most_ms; the list takes
// that as its foot giving back room in the change its sent key comes (View::scrolls_window's), so what is over the
// sent message goes up only, by the sent row's height less what the composer gave back, and the room from the sent
// message to the composer's hint opens and never closes again. On main the composer stayed three lines tall for good
// (144.25 where its one line is 94.75, words 1).

///|
/// The draft of the fixture's chat s-c1.
let sent_nodes_draft : String = "ws1/st1:s-c1"

///|
/// How far apart the looks round a send are (on the test's clock, not a frame's: CI runs the rates).
let sent_nodes_look_ms : Double = 10.0

///|
/// The composer's box as laid out (composer/content): its top and height.
fn sent_nodes_box(t : @ui.Tester) -> (Double, Double) {
  match @motion.measured_rect(t.ctx(), "composer/content") {
    Some((_, y, _, h)) => (y, h)
    None => @halt.saying("the composer's box not measured at \{t.time()}")
  }
}

///|
/// Where words `s` are drawn: their top and their foot.
fn sent_nodes_words(t : @ui.Tester, s : String) -> (Double, Double) {
  match t.rect_of(s) {
    Some((_, y, _, h)) => (y, y + h)
    None => @halt.saying("「\{s}」 not drawn at \{t.time()}")
  }
}

///|
/// What the last key of the page's list takes in it, as its blocks are laid out: its block's height and the room
/// between it and the block before.
fn sent_nodes_last_block(t : @ui.Tester, at : String) -> Double {
  let rows = match t.list_row_boxes() {
    [.., rows] => rows
    [] => @halt.saying("\{at}: no list's rows seen")
  }
  guard rows.length() >= 2 else { @halt.saying("\{at}: \{rows.length()} rows seen") }
  let (_, y, _, h) = rows[rows.length() - 1]
  let (_, py, _, ph) = rows[rows.length() - 2]
  h + (y - (py + ph))
}

///|
/// The composer's room under the list (what the list leaves it at its foot).
fn sent_nodes_room(t : @ui.Tester, draft : String) -> Double {
  @sfpages.composer_room(t.ctx(), draft)
}

///|
/// From the press of send: every 10 ms till move_most_ms, the composer's height, the room from the sent message's foot
/// to the composer's hint, and where words `over` are drawn (0 where none are named).
fn sent_nodes_frames(t : @ui.Tester, over : String?) -> Array[(Double, Double, Double, Double)] {
  let press = t.time()
  let seen : Array[(Double, Double, Double, Double)] = []
  while true {
    let ms = t.time() - press
    let gap = sent_nodes_words(t, "发消息").0 - sent_nodes_words(t, "第一行").1
    let y = match over {
      Some(s) => sent_nodes_words(t, s).0
      None => 0.0
    }
    seen.push((ms, sent_nodes_box(t).1, gap, y))
    if ms >= @ui.move_most_ms {
      break
    }
    t.run_for(sent_nodes_look_ms)
  }
  seen
}

///|
/// What `sent_nodes_frames` saw, held: the composer `one` tall from the press's frame on, the room over it never
/// narrower once it has opened, what is over the message never lower than the frame before. Each fault said with what
/// it found.
fn sent_nodes_held(at : String, seen : Array[(Double, Double, Double, Double)], one : Double) -> Unit raise {
  let mut opened = false
  for i, f in seen {
    let (ms, h, gap, y) = f
    assert_true((h - one).abs() < 0.01, msg="\{at}, \{ms} ms after the press: the composer \{h} tall, its one line \{one}")
    if i > 0 {
      let (_, _, was, above) = seen[i - 1]
      if opened {
        assert_true(gap >= was - 0.01, msg="\{at}, \{ms} ms: the room over the composer closing again, \{was} to \{gap}")
      }
      if gap > was + 0.01 {
        opened = true
      }
      assert_true(y <= above + 0.01, msg="\{at}, \{ms} ms: what is over the message down from \{above} to \{y}")
    }
  }
}

///|
/// The fixture's chat s-c1 on a page made as nodes, 小屏 with a finger, the system's words `scale`, its composer pressed
/// and a line typed in it, at rest.
fn sent_nodes_chat(scale : Double) -> @ui.Tester {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_font_scale(scale)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("第一行")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a chat's page made as nodes, 小屏, a finger's: three lines sent, the composer at its one line's height from the press, what is over the message going up only by its height less what the composer gave back, the system's words 1 and 1.3" {
  let over = "做完了：列表、跳到最新的按钮"
  for scale in [1.0, 1.3] {
    let at = "words \{scale}"
    let t = sent_nodes_chat(scale)
    let one = sent_nodes_box(t).1
    let room = sent_nodes_room(t, sent_nodes_draft)
    t.type_text("\n第二行\n第三行")
    t.run_for(@ui.move_most_ms)
    let three = sent_nodes_box(t).1
    let room_three = sent_nodes_room(t, sent_nodes_draft)
    assert_true(three > one, msg="\{at}: three lines \{three} tall, one \{one}")
    let before = sent_nodes_words(t, over)
    let off = t.list_offset()
    tap_send(t)
    sent_nodes_held(at, sent_nodes_frames(t, Some(over)), one)
    let at_rest = sent_nodes_room(t, sent_nodes_draft)
    assert_true((at_rest - room).abs() < 0.01, msg="\{at}: its room \{at_rest} at rest, \{room} with one line")
    // (at rest: the list up by what the sent key takes in it, its block as laid out (its words and the line under them)
    // and the room between it and the block before, less what the composer gave back; what is over it drawn up as far,
    // on the device's pixels: 82.5 for the list's 82.75 at words 1)
    let rest = sent_nodes_words(t, over)
    let row = sent_nodes_last_block(t, at)
    let up = t.list_offset() - off
    let want = row - (room_three - room)
    assert_true((up - want).abs() < 0.01, msg="\{at}: the list up \{up}, the sent key's \{row} less \{room_three - room}")
    assert_true((before.0 - rest.0 - up).abs() < 0.5, msg="\{at}: what is over it drawn up \{before.0 - rest.0}, the list \{up}")
  }
}

///|
test "a new chat on a page made as nodes, 小屏, a finger's: its first three lines sent, its chat's composer at its one line's height from the press, the room over it opening only, the system's words 1 and 1.3" {
  for scale in [1.0, 1.3] {
    let at = "words \{scale}"
    // (a chat's composer with one line, at rest: what its chat's is to be as its first words are sent)
    let (one, room_one) = {
      let c = sent_nodes_chat(scale)
      (sent_nodes_box(c).1, sent_nodes_room(c, sent_nodes_draft))
    }
    let t = tester("home")
    @sfbase.chat_page_nodes.set(true)
    t.set_font_scale(scale)
    t.draw()
    let (_, y) = bar_places_at()
    t.tap(195.0, y - 28.0 - 4.0)
    t.run_for(@ui.move_most_ms)
    t.tap_text("做任何事")
    t.type_text("第一行\n第二行\n第三行")
    t.run_for(@ui.move_most_ms)
    tap_send(t)
    let draft = match app.nav.top() {
      Chat(r) => r.station + ":" + r.session
      _ => @halt.saying("\{at}: the page not the chat it became")
    }
    let seen = sent_nodes_frames(t, None)
    let room = sent_nodes_room(t, draft)
    sent_nodes_held(at, seen, one)
    assert_true((room - room_one).abs() < 0.01, msg="\{at}: its room \{room} by move_most_ms, \{room_one} with one line")
  }
}
