// Words sent from a composer still on its way to a new shape (a line more just typed): the composer goes on to that
// shape on the way it set out on, and what holds it for the words is said once, by the facts it comes of (their row in
// the list, laid out; their send refused; the chat left), never a moment guessed and told again (close_option,
// agent_reply, answer_option, chinese_enter: the coordinator of the migration, 2026-11-10).

///|
let hold_draft : String = "ws1/st1:s-c1"

///|
/// How long after a line more is typed send is pressed, the composer still growing to it (a quick hand's).
let hold_grow_send_ms : Double = 116.0

///|
/// A chat opened, its composer opened with one line in it, at rest.
fn hold_chat() -> @ui.Tester {
  hold_chat_of().0
}

///|
/// hold_chat's, and the source it reads.
fn hold_chat_of() -> (@ui.Tester, Source) {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("第一行")
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
/// What holds the composer for words sent, as said at this frame: when it is let go and when it is down (+inf: not
/// said).
fn hold_said(t : @ui.Tester) -> (Double, Double) {
  ignore(t)
  match @sfbase.flight_lets_go(hold_draft) {
    Some((go, down)) => (go, go + down)
    None => (@double.infinity, @double.infinity)
  }
}

///|
test "sent while it grows by a line: what holds the composer is said once, as their row is in the list, and stays so" {
  let t = hold_chat()
  t.type_text("\n第二行")
  t.frame(ms=hold_grow_send_ms)
  tap_send(t)
  let mut said : (Double, Double)? = None
  let end = t.time() + @sfbase.flight_most_ms + @ui.move_most_ms
  while t.time() < end {
    let placed = match flight_of(hold_draft) {
      Some(f) => f.placed
      None => true
    }
    let now = hold_said(t)
    match said {
      // (said as their row is in the list, in the frame it is placed: no moment of it said before, none after)
      None if placed => {
        assert_true(flight_of(hold_draft).map(fn(f) { f.timed }).unwrap_or(true), msg="placed, not timed")
        said = Some(now)
      }
      None => assert_true(now.0 == @double.infinity || now.0 < 0.0, msg="said before their row: \{Repr(now)}")
      // (and never again: not when their row is laid out, not as it lets go)
      Some(was) if t.time() < was.1 => assert_eq(now, was)
      Some(_) => ()
    }
    t.frame()
  }
  assert_true(said is Some(_))
}

///|
/// Lines typed into the composer and sent: those over `lines` typed first, at rest; then the last of them typed and,
/// `grow_for` after it (-1: once the composer is at rest), send pressed; `between` frames drawn (each `step` on) from
/// the press to the frame their row is in the list; read up the list by `up` points first (0: at its end). How long
/// the words take to their row, and when the composer is let go and down, from the moment they set out.
fn hold_timed(
  lines : Array[String],
  grow_for : Double,
  between? : Int = 0,
  step? : Double = 0.0,
  up? : Double = 0.0,
) -> (Double, Double, Double) {
  let t = hold_chat()
  t.type_text("\n" + lines[:lines.length() - 1].join("\n"))
  t.run_for(@ui.move_most_ms)
  if up > 0.0 {
    t.move_to(195.0, 400.0)
    t.wheel(195.0, 400.0, -up)
    t.run_for(@ui.move_most_ms)
  }
  t.type_text("\n" + lines[lines.length() - 1])
  if grow_for >= 0.0 {
    t.frame(ms=grow_for)
  } else {
    t.run_for(@ui.move_most_ms)
  }
  tap_send(t)
  for _ in 0..<between {
    match flight_of(hold_draft) {
      Some(f) if !f.placed => t.frame(ms=step)
      _ => ()
    }
  }
  match flight_of(hold_draft) {
    Some(f) => {
      let (go, down) = hold_said(t)
      (@sfbase.flight_ms_of(f), go - f.set_out, down - f.set_out)
    }
    None => @halt.saying("no flight")
  }
}

///|
/// Lines enough that the words' way is past the shortest a flight takes (flight_way_ms of nothing): it is as long as
/// it is far.
let hold_long : Array[String] = ["第二行", "第三行", "第四行"]

///|
test "sent while it grows by a line: the words' way is as long as it is far to where their row stands at rest" {
  let rest = hold_timed(hold_long, -1.0)
  assert_true(rest.0 > @sfbase.flight_way_ms(true, 0.0), msg="\{rest.0}: no further than the shortest way")
  // (the composer on its way to the same shape: their row at rest where it is when sent at rest)
  assert_eq(hold_timed(hold_long, hold_grow_send_ms), rest)
}

///|
test "sent while it grows by a line: the words' way and the composer's letting go are the same however the frames came" {
  let first = hold_timed(hold_long, hold_grow_send_ms)
  for v in [(1, 1.0), (1, 5.0), (2, 3.0), (3, 7.0)] {
    let (between, step) = v
    assert_eq(hold_timed(hold_long, hold_grow_send_ms, between~, step~), first)
  }
}

///|
test "sent read up the list a little: the words' way is as long as it is far to where their row stands once the list is at its end" {
  let rest = hold_timed(hold_long, -1.0)
  assert_eq(hold_timed(hold_long, -1.0, up=60.0), rest)
}

///|
test "sent read up the list past its end's layout: the words' way as long as their usual way, the list gliding to its end" {
  let (ms, go, down) = hold_timed(hold_long, -1.0, up=600.0)
  assert_eq(ms, @sfbase.flight_len(true))
  ignore((go, down))
}

///|
/// Whether words sent from the chat are on their way to a row in the list (None: nothing flies).
fn hold_placed() -> Bool? {
  flight_of(hold_draft).map(fn(f) { f.placed })
}

///|
test "sent: its row is in the list in the frames of the press itself, what holds the composer said there, no moment waited for" {
  let t = hold_chat()
  t.type_text("\n第二行")
  t.run_for(@ui.move_most_ms)
  tap_send(t)
  // (what was sent is the list's own from the press: sent_local, a row by its key)
  assert_eq(hold_placed(), Some(true))
  let (go, down) = hold_said(t)
  let f = flight_of(hold_draft).unwrap()
  assert_true(go < f.set_out + @sfbase.flight_most_ms && down < go + @sfbase.flight_most_ms, msg="\{go} \{down} from \{f.set_out}")
}

///|
test "a new chat's first words: what holds its composer is said as their row is in the new chat's list, not before" {
  let t = tester("home")
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  t.type_text("把发布说明写一下")
  t.draw()
  tap_send(t)
  let mut said_before = false
  let mut said = false
  let end = t.time() + flight_carry_after_ms + flight_carry_ms
  while t.time() < end {
    match send_flight.get() {
      Some(f) if f.carried => {
        let lets_go = @sfbase.flight_lets_go(f.chat)
        if !f.placed && lets_go is Some(_) {
          said_before = true
        }
        if f.placed {
          // (as their row was placed: they set out at once, the composer let go as their list comes up)
          assert_eq(lets_go, Some((f.set_out + f.after, @sfbase.sent_down_ms)))
          said = true
        }
      }
      _ => ()
    }
    t.frame()
  }
  assert_true(!said_before)
  assert_true(said)
}

///|
/// A quote added to the composer and sent: `frames` frames drawn between (-1: once it is at rest; `step` each, 0 the
/// display's next): how tall what was added to it is held as, whether the quote went with the words, and whether its
/// card had been drawn before send was pressed.
fn hold_quoted(frames : Int, step? : Double = 0.0) -> (Double, Bool, Bool) {
  let (t, src) = hold_chat_of()
  let quote = "发布前再看一眼签名"
  @sfbase.writing_quote(src, @sfbase.writing(src, hold_draft), { "author": "Ana", "text": Json::string(quote), "ts": "ts8" })
  if frames < 0 {
    t.run_for(@ui.move_most_ms)
  } else {
    for _ in 0..<frames {
      t.frame(ms=step)
    }
  }
  let drawn = t.find(quote) is Some(_)
  tap_send(t)
  t.frame()
  match flight_of(hold_draft) {
    Some(f) => (f.held_extras, !f.files.is_empty(), drawn)
    None => @halt.saying("no flight")
  }
}

///|
/// How many of the display's frames after a quote is added to the composer its card is first drawn in.
fn hold_quote_frames() -> Int {
  let (t, src) = hold_chat_of()
  let quote = "发布前再看一眼签名"
  @sfbase.writing_quote(src, @sfbase.writing(src, hold_draft), { "author": "Ana", "text": Json::string(quote), "ts": "ts8" })
  let mut n = 0
  while t.find(quote) is None && n < 10 {
    t.frame()
    n += 1
  }
  n
}

///|
test "a quote added and sent the frame after it is first drawn: held as tall as it is laid out with it, as if sent at rest" {
  let (rest, went, _) = hold_quoted(-1)
  assert_true(rest > 0.0 && went, msg="\{rest} \{went}")
  // (sent at the first frame after the one that took it in and drew it: laid out with it once)
  let (held, went, drawn) = hold_quoted(hold_quote_frames())
  assert_true(went && drawn, msg="\{went} \{drawn}")
  assert_eq(held, rest)
}

///|
test "a quote sent as its card comes in: held as tall as it comes to, not as far as it has come" {
  let (rest, _, _) = hold_quoted(-1)
  // (its card a frame and some on its way in)
  let (held, went, drawn) = hold_quoted(hold_quote_frames(), step=30.0)
  assert_true(went && drawn, msg="\{went} \{drawn}")
  assert_eq(held, rest)
}

///|
/// What a composer's room as drawn and the list's room under its rows may differ by as both come down, a reshape's way
/// and the list's two curves to the same end (points): one way, one curve, once the composer is a node.
let hold_cover_slack : Double = 0.5

///|
/// The composer on its way to another shape as send is pressed: `grow`, a line more typed (else the last line taken
/// out), send pressed `after` later; from the press till it is down, at every frame: the composer's room as drawn, how
/// far it covers the list's last row, and where that row is; when the words let go of it, and how far it was carried on
/// from the press, slowing to rest (its room as it was let go of, less as the press found it).
priv struct HoldRun {
  frames : Array[(Double, Double, Double, (Int, Double))]
  go : Double
  carried : Double
}

///|
fn hold_run(grow : Bool, after : Double) -> HoldRun {
  let t = hold_chat()
  if !grow {
    t.type_text("\n第二行")
    t.run_for(@ui.move_most_ms)
  }
  let foot = fn() {
    let rows = t.rows()
    rows[rows.length() - 1]
  }
  let room = fn() { @sfpages.composer_room(t.ctx(), hold_draft) }
  let over = foot().2 - room()
  if grow {
    t.type_text("\n第二行")
  } else {
    // (the last line taken out: its room closing)
    for _ in 0..<4 {
      t.backspace()
    }
  }
  t.frame(ms=after)
  tap_send(t)
  let at_press = room()
  let frames = []
  let end = t.time() + @sfbase.flight_most_ms + @ui.move_most_ms
  let mut go = end
  let mut carried = 0.0
  while t.time() < end {
    match @sfbase.flight_lets_go(hold_draft) {
      Some((at, _)) => go = at
      None => ()
    }
    let rows = t.rows()
    let last = rows[rows.length() - 2]
    frames.push((t.time(), room(), room() + over - foot().2, (last.0, last.1)))
    if t.time() < go {
      carried = room() - at_press
    }
    t.frame()
  }
  { frames, go, carried }
}

///|
/// Sent on its way to another shape: the composer slows to rest from as fast as it went, never back, till the words
/// let go of it (its room one way only, as far as its speed carried it), and down to a line from then, one way; over
/// the list's last row by no more than it was carried on, and less at every frame once let go of, none once down; the
/// last row one way only all along.
fn hold_run_holds(grow : Bool, after : Double) -> Unit raise {
  let run = hold_run(grow, after)
  let way = if grow { 1.0 } else { -1.0 }
  let mut was : (Double, Double, Double, (Int, Double))? = None
  let mut row_way = 0.0
  let mut cover_was = @double.infinity
  for f in run.frames {
    let (at, room, cover, y) = f
    match was {
      Some((_, room0, _, y0)) => {
        let d = (room - room0) * way
        if at < run.go {
          assert_true(d >= -0.001, msg="at \{at}: back \{d}")
        } else {
          assert_true(room - room0 <= 0.001, msg="at \{at}, let go of at \{run.go}: up \{room - room0}")
        }
        // (the same row: the one sent, once it is the last)
        let dy = y.1 - y0.1
        if y.0 == y0.0 && dy.abs() > 0.01 {
          assert_true(row_way == 0.0 || (dy > 0.0) == (row_way > 0.0), msg="at \{at}: the last row \{dy} after \{row_way}")
          row_way = dy
        }
      }
      None => ()
    }
    if at < run.go {
      assert_true(cover <= run.carried.abs() + hold_cover_slack, msg="at \{at}: covers \{cover}, carried \{run.carried}")
    } else {
      assert_true(cover <= cover_was + hold_cover_slack, msg="at \{at}: covers \{cover} after \{cover_was}")
      cover_was = cover
    }
    was = Some(f)
  }
  assert_true(cover_was <= hold_cover_slack, msg="still over it by \{cover_was} once down")
}

///|
test "sent as it begins to grow by a line: slows to rest from as fast as it went, the last row one way" {
  hold_run_holds(true, @ui.first_frame_ms)
}

///|
test "sent while it grows by a line: slows to rest from as fast as it went, the last row one way" {
  hold_run_holds(true, hold_grow_send_ms)
}

///|
test "sent as it has all but grown by a line: slows to rest from as fast as it went, the last row one way" {
  hold_run_holds(true, @ui.move_most_ms - hold_grow_send_ms / 4.0)
}

///|
test "sent as it closes a line: slows to rest from as fast as it went, the last row one way" {
  hold_run_holds(false, hold_grow_send_ms)
}

///|
/// Sent while it grows by a line, `between` frames drawn (each `step` on) after the press: the composer's room as
/// drawn the moment before the words let go of it.
fn hold_rest(between : Int, step : Double) -> Double {
  let t = hold_chat()
  t.type_text("\n第二行")
  t.frame(ms=hold_grow_send_ms)
  tap_send(t)
  for _ in 0..<between {
    t.frame(ms=step)
  }
  let go = @sfbase.flight_lets_go(hold_draft).map(fn(l) { l.0 }).unwrap_or(t.time())
  t.run_for(go - @ui.first_frame_ms / 2.0 - t.time())
  @sfpages.composer_room(t.ctx(), hold_draft)
}

///|
test "sent while it grows by a line: where it comes to rest is the same however the frames came" {
  let first = hold_rest(0, 0.0)
  for v in [(1, 1.0), (1, 5.0), (2, 3.0), (3, 7.0)] {
    let (between, step) = v
    assert_true((hold_rest(between, step) - first).abs() < 0.001, msg="\{between} frames \{step} apart")
  }
}

///|
test "sent with a quote, the composer taller than the message it makes: the last row goes one way only" {
  let (t, src) = hold_chat_of()
  @sfbase.writing_quote(src, @sfbase.writing(src, hold_draft), { "author": "Ana", "text": Json::string("发布前再看一眼签名"), "ts": "ts8" })
  t.run_for(@ui.move_most_ms)
  // (the row over the room under the rows: the last message's, then the one sent)
  let last = fn() {
    let rows = t.rows()
    rows[rows.length() - 2]
  }
  tap_send(t)
  let mut way = 0.0
  let mut was = last()
  let end = t.time() + @sfbase.flight_most_ms + @ui.move_most_ms
  while t.time() < end {
    t.frame()
    let now = last()
    if now.0 == was.0 {
      let d = now.1 - was.1
      if d.abs() > 0.01 {
        assert_true(way == 0.0 || (d > 0.0) == (way > 0.0), msg="at \{t.time()}: \{d} after \{way}")
        way = d
      }
    }
    was = now
  }
}

///|
test "sent at rest with more lines than the field shows: the composer as tall from the press till they let go of it" {
  let t = hold_chat()
  t.type_text("\n" + Array::makei(12, fn(i) { "第\{i + 2}行，一句话写得长一些，让它折成两行再往下" }).join("\n"))
  t.run_for(@ui.move_most_ms)
  let room = @sfpages.composer_room(t.ctx(), hold_draft)
  tap_send(t)
  let go = @sfbase.flight_lets_go(hold_draft).map(fn(l) { l.0 }).unwrap_or(t.time())
  while t.time() < go {
    assert_true((@sfpages.composer_room(t.ctx(), hold_draft) - room).abs() < 0.001, msg="at \{t.time()}: \{@sfpages.composer_room(t.ctx(), hold_draft)} from \{room}")
    t.frame()
  }
}

///|
/// Words sent, and the chat left at the same moment (the system's back), its list built no more: come back to a while
/// after, nothing of them is left on its way. Not a time they waited ends them, but the frames they declared: their
/// row was in the list in the frames of the press (its page drawn on as it goes), their way said there.
test "sent, then the chat left at once and come back to later: no words flying late, the composer not held, the turn over, their row in its place" {
  let t = hold_chat()
  let words = "离开前发出的话"
  t.type_text("\n" + words)
  tap_send(t)
  t.back_raw(2, 0.0, t.time())
  t.frame()
  // (away: the chats' list, well past where they would have landed)
  t.run_for(@ui.nav_rest() - t.time() + @sfbase.flight_most_ms + @ui.move_most_ms)
  t.tap_text("整理发布清单")
  // (the first frame back: nothing flies, the composer as it rests, their row there)
  assert_true(t.find(words) is Some(_), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_eq(flight_of(hold_draft).map(fn(f) { f.way.over(t.ctx()) }).unwrap_or(true), true)
  let (_, down) = hold_said(t)
  assert_true(down <= t.time() || down == @double.infinity, msg="held till \{down} at \{t.time()}")
  assert_eq(@sfpages.composer_room(t.ctx(), hold_draft), @sfpages.composer_room(t.ctx(), hold_draft, settled=true))
  t.run_for(@ui.nav_rest() - t.time())
  assert_true(flight_of(hold_draft) is None)
  assert_true(t.rest_of("a chat's list turns") <= t.time(), msg="\{t.rest_of("a chat's list turns")} at \{t.time()}")
}

///|
/// Words sent, the cursor taken from the field at once (as the chat is left, or anything else takes it): the box it
/// stays a moment after closes to its capsule from that moment on its own clock, not as far on as the time since the
/// words let go of it (sizes_steady judging each frame drawn).
test "sent, then the cursor let go of: the composer closes from the moment it is let go of, not at once" {
  if @ui.test_at_a_rate() {
    return
  }
  let t = hold_chat()
  t.type_text("\n离开前发出的话")
  tap_send(t)
  t.ctx().blur()
  let at = t.time()
  for i in 0..<40 {
    t.frame_at(at + i.to_double() * 1000.0 / 60.0)
  }
}

///|
/// How far the composer's ground is drawn over where it is laid out (its box closing to its capsule), at each of `at`'s
/// moments after `from`.
fn hold_over_at(t : @ui.Tester, from : Double, at : Array[Double]) -> Array[Double] {
  at.map(fn(d) {
    t.run_for(from + d - t.time())
    @motion.reshaped_over(t.ctx(), "composer/box")
  })
}

///|
/// The moments after the box is let go of (let_go_ms after the cursor left) the closing is looked at, the first a frame
/// on.
let hold_over_moments : Array[Double] = [17.0, 60.0, 120.0, 180.0, 240.0, 299.0, 400.0]

///|
/// Words sent, the cursor taken at once: from where the box is let go of, its closing goes all the way down on its own
/// clock, each moment lower than the one before, at every rate the same (a step down at its start would be its
/// clock taken for the words' that let go of it before).
test "sent, then the cursor let go of: the box closes from the moment it is let go of, all the way, lower each moment" {
  let t = hold_chat()
  t.type_text("\n离开前发出的话")
  tap_send(t)
  t.ctx().blur()
  let over = hold_over_at(t, t.time() + @sfpages.let_go_ms, hold_over_moments)
  assert_true(over[0] > 30.0, msg="as far on as it is a frame after it is let go of: \{Repr(over)}")
  for i in 1..<over.length() {
    assert_true(over[i] <= over[i - 1], msg="\{Repr(over)}")
  }
  assert_eq(over[over.length() - 1], 0.0, msg="\{Repr(over)}")
}

///|
/// The box let go of at the very moment words sent from it let go of it: the closing is the box's own, on its own clock
/// from then (as the box let go of with no words on their way closes), not the words' (decided: the cursor's leaving is
/// the cause that changes its shape then).
test "the box let go of at the moment words sent let go of it: closed on its own clock" {
  // (the words' let-go after the press, measured: a run of its own)
  let t = hold_chat()
  t.type_text("\n离开前发出的话")
  let sent_at = t.time()
  tap_send(t)
  guard @sfbase.flight_lets_go(hold_draft) is Some((go, _)) else { fail("no words on their way") }
  let after_send = go - sent_at
  // (the same once more: the cursor taken let_go_ms before the moment they will let go of it)
  let t = hold_chat()
  t.type_text("\n离开前发出的话")
  let blur_at = t.time()
  t.ctx().blur()
  t.run_for(@sfpages.let_go_ms - after_send)
  tap_send(t)
  guard @sfbase.flight_lets_go(hold_draft) is Some((go, _)) else { fail("no words on their way") }
  assert_eq(go, blur_at + @sfpages.let_go_ms, msg="not at the same moment: sent \{t.time()}")
  let both = hold_over_at(t, go, hold_over_moments)
  // (the box alone, nothing in it, no words on their way: its own clock)
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  t.ctx().blur()
  let alone = hold_over_at(t, t.time() + @sfpages.let_go_ms, hold_over_moments)
  // (the same curve: each moment as far down its way, whatever height it closes from)
  let way = fn(o : Array[Double]) { o.map(fn(v) { v / o[0] }) }
  let (a, b) = (way(both), way(alone))
  assert_true(a.iter().zip(b.iter()).all(fn(p) { (p.0 - p.1).abs() < 1.0e-9 }), msg="both \{Repr(both)}, alone \{Repr(alone)}")
}
