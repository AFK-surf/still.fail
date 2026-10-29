// What is quoted, sent (sfpages composer.mbt flying_quotes, sfbase's flight.mbt): in the list with its message from the
// frame it is sent, as the core's row will have it; its card flying there from its card in the composer, its words
// setting out from where they were.

///|
/// A passage no message of the made-up chat has.
let quote_passage : String = "表头先对齐第三列"

///|
/// Where the quote's words are seen now under the bar (each copy of its card's words, not see-through): their top left.
fn quote_seen(t : @ui.Tester) -> Array[(Double, Double)] {
  t.words().filter(fn(w) { w.0.contains(quote_passage) && w.5 > 0.5 && w.2 > 60.0 }).map(fn(w) { (w.1, w.2) })
}

///|
/// Where the quote's words are seen now: once (copies drawn over each other count as one), else the test fails.
fn quote_once(t : @ui.Tester) -> (Double, Double) raise {
  let at = quote_seen(t)
  guard at.length() > 0 else { fail("the quote not seen at \{t.time()}") }
  for p in at {
    if (p.0 - at[0].0).abs() > 0.5 || (p.1 - at[0].1).abs() > 0.5 {
      fail("the quote seen twice apart at \{t.time()}: \{at}")
    }
  }
  at[0]
}

///|
/// The quote's card as drawn now: the least of what is drawn round its words (x, y, w, h).
fn quote_ground(t : @ui.Tester) -> (Double, Double, Double, Double) raise {
  let (x, y) = quote_once(t)
  let mut least : (Double, Double, Double, Double)? = None
  for r in t.drawn_rects() {
    let (rx, ry, rw, rh, colour) = r
    if (colour & 0xFFL) != 0L && rx <= x + 1.0 && ry <= y + 1.0 && rx + rw >= x + 1.0 && ry + rh >= y + 1.0 {
      match least {
        Some((_, _, lw, lh)) if lw * lh <= rw * rh => ()
        _ => least = Some((rx, ry, rw, rh))
      }
    }
  }
  match least {
    Some(g) => g
    None => fail("nothing drawn round the quote at \{t.time()}")
  }
}

///|
/// Whether the composer's hint (发消息; a new chat's, 做任何事) is seen now: drawn in its colour where it is.
fn hint_seen(t : @ui.Tester, hint? : String = "发消息") -> Bool {
  match t.words().iter().find_first(fn(w) { w.0 == hint }) {
    Some((_, x, y, w, h, _)) =>
      t
      .drawn_glyphs()
      .iter()
      .any(fn(g) { g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 <= y + h + 1.0 && g.2 == @sf.theme().p.subtle })
    None => false
  }
}

///|
/// How much of a quote's ✕ is seen now (its round, 20 across, in the ink): 0 none.
fn x_seen(t : @ui.Tester) -> Double {
  let ink = @sf.theme().p.text
  let mut most = 0.0
  for r in t.drawn_rects() {
    let (_, _, w, h, colour) = r
    if w >= 16.0 && w <= 21.0 && (h - w).abs() < 0.5 && colour >> 8 == ink >> 8 {
      let a = (colour & 0xFFL).to_double() / 255.0
      if a > most {
        most = a
      }
    }
  }
  most
}

///|
/// Whether a quote's ✕ seen now is drawn over its card (after the card's ground), where both are drawn.
fn x_over_card(t : @ui.Tester) -> Bool raise {
  let ink = @sf.theme().p.text
  let rects = t.drawn_rects()
  let (gx, gy, gw, gh) = quote_ground(t)
  let mut card = -1
  let mut x = -1
  for k, r in rects {
    let (rx, ry, rw, rh, colour) = r
    if (rx - gx).abs() < 0.5 && (ry - gy).abs() < 0.5 && (rw - gw).abs() < 0.5 && (rh - gh).abs() < 0.5 {
      card = k
    }
    if rw >= 16.0 && rw <= 21.0 && (rh - rw).abs() < 0.5 && colour >> 8 == ink >> 8 && (colour & 0xFFL) != 0L {
      x = k
    }
  }
  card < 0 || x < 0 || x > card
}

///|
/// The send button's ground as drawn now: its round.
fn send_ground(t : @ui.Tester) -> Int64 raise {
  let (x, y, w, h) = match t.query(Button, label=@sf.t("web-main.composer.send")) {
    Some(b) => b.rect
    None => fail("no send button")
  }
  // (its round: the largest round about its middle, what it is pressed in reaching past it; drawn on its way as the
  // composer changes shape, its place in the capsule's end and in the opened box's corner 1.13 apart: smooth.mbt
  // round_like)
  let (mx, my) = (x + w / 2.0, y + h / 2.0)
  let mut round : (Double, Double, Double, Double, Int64)? = None
  for r in t.drawn_rects() {
    if (r.0 + r.2 / 2.0 - mx).abs() < 1.5 && (r.1 + r.3 / 2.0 - my).abs() < 1.5 && (r.2 - r.3).abs() < 0.5 {
      match round {
        Some(b) if b.2 >= r.2 => ()
        _ => round = Some(r)
      }
    }
  }
  match round {
    Some(r) => r.4
    None => {
      let near = t.drawn_rects().filter(fn(r) { r.0 < x + w && r.0 + r.2 > x && r.1 < y + h && r.1 + r.3 > y })
      fail("nothing drawn as the send button at \{(x, y, w, h)}: \{near}")
    }
  }
}

///|
/// The chat's composer with the passage quoted in it, what is said about it typed in its line.
fn quoting(calls : Array[Made]) -> @ui.Tester {
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  @sfbase.writing_quote(src, @sfbase.writing(src, "ws1/st1:s-c1"), {
    "author": "Claude",
    "text": quote_passage,
    "ts": "ts8",
  })
  t.run_for(@ui.move_most_ms)
  t.type_text("这里要对齐")
  t.draw()
  t
}

///|
test "a quote sent alone is in the list at once, its card flying there from the composer's: seen every frame, from where its words were" {
  let calls : Array[Made] = []
  let t = quoting(calls)
  let was = quote_once(t)
  let (_, _, wide, _) = quote_ground(t)
  tap_send(t)
  // in the list from the frame it is sent, as the core will have it (composer.ts take: what is said about it with it)
  let sent = sending_of("ws1/st1\u{1}s-c1")
  assert_eq(sent.length(), 1)
  assert_eq(sent[0].row.quotes.map(fn(q) { (q.text, q.comment, q.ts) }), [(quote_passage, "这里要对齐", "ts8")])
  match send_flight.get() {
    Some(f) => assert_eq(f.files.map(fn(ff) { ff.key }), [@sfbase.quote_key(0)])
    None => fail("nothing flies")
  }
  // where its words were as it is sent, then every frame till it has landed: never gone, never twice apart
  let at = quote_once(t)
  assert_true((at.0 - was.0).abs() < 0.5 && (at.1 - was.1).abs() < 0.5, msg="sent, seen at \{at}, not \{was}")
  // its card as wide as it was in the composer as it sets out, and narrower only on its way: never all at once
  let widths = [quote_ground(t).2]
  let sent_at = t.time()
  let mut hinted = false
  while t.time() < sent_at + flight_ms + 50.0 {
    t.frame()
    quote_once(t) |> ignore
    widths.push(quote_ground(t).2)
    // the composer's hint away while the card is over it (the field comes up under it as the composer comes down)
    if t.time() < sent_at + flight_ms / 4.0 && hint_seen(t) {
      hinted = true
    }
  }
  assert_false(hinted)
  // and back once it is out of it
  t.run_for(@sf.hint_back_ms)
  assert_true(hint_seen(t))
  assert_true(send_flight.get() is None)
  // landed in its message, over the composer, as wide as it needs
  let (_, y) = quote_once(t)
  assert_true(y < was.1 - 40.0, msg="landed at \{y}, its words were at \{was.1}")
  let landed = widths[widths.length() - 1]
  assert_true(landed < wide - 40.0, msg="landed \{landed} wide, as the composer's \{wide}")
  assert_true((widths[0] - wide).abs() < 0.5, msg="set out \{widths[0]} wide, not \{wide}: \{widths}")
  for k in 1..<widths.length() {
    if widths[k] > widths[k - 1] + 0.5 || widths[k - 1] - widths[k] > (wide - landed) / 2.0 {
      fail("its width went from \{widths[k - 1]} to \{widths[k]} at once: \{widths}")
    }
  }
}

///|
test "words sent with a quote land under its card, which is in their row from the frame they are sent" {
  let calls : Array[Made] = []
  let t = quoting(calls)
  t.tap_text("发消息")
  t.type_text("先上屏")
  tap_send(t)
  assert_eq(sending_of("ws1/st1\u{1}s-c1")[0].row.quotes.length(), 1)
  t.run_for(flight_ms + 50.0)
  assert_true(send_flight.get() is None)
  let (_, qy) = quote_once(t)
  match t.drawn_of("先上屏") {
    Some((_, wy)) => assert_true(qy < wy, msg="the quote at \{qy}, the words at \{wy}")
    None => fail("the words not drawn")
  }
}

///|
test "sent, a quote's ✕ leaves with its card and the send button fades to faint: neither at once" {
  let calls : Array[Made] = []
  let t = quoting(calls)
  // (as it came up when the draft could be sent)
  t.run_for(@sf.dur_ms)
  let ready = send_ground(t)
  assert_true(x_seen(t) > 0.9)
  tap_send(t)
  let xs = [x_seen(t)]
  let grounds = [send_ground(t)]
  let sent_at = t.time()
  while t.time() < sent_at + @sf.leave_ms + 50.0 {
    t.frame()
    xs.push(x_seen(t))
    grounds.push(send_ground(t))
    // over its card all the way, never under it
    assert_true(x_over_card(t), msg="the ✕ under its card at \{t.time()}")
  }
  // the ✕: seen as it sets out, fading on (never back), gone once it has left
  assert_true(xs[0] > 0.9, msg="\{xs}")
  assert_true(xs.iter().any(fn(a) { a > 0.1 && a < 0.9 }), msg="\{xs}")
  assert_eq(xs[xs.length() - 1], 0.0)
  for k in 1..<xs.length() {
    if xs[k] > xs[k - 1] + 0.01 {
      fail("the ✕ came back: \{xs}")
    }
  }
  // the send button: through what lies between its two grounds, not from one to the other at once
  let faint = grounds[grounds.length() - 1]
  assert_true(faint != ready)
  assert_true(grounds.iter().any(fn(g) { g != ready && g != faint }), msg="\{grounds}")
}
