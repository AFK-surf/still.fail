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
/// Whether the composer's hint (发消息) is seen now: drawn in its colour where it is.
fn hint_seen(t : @ui.Tester) -> Bool {
  match t.words().iter().find_first(fn(w) { w.0 == "发消息" }) {
    Some((_, x, y, w, h, _)) =>
      t
      .drawn_glyphs()
      .iter()
      .any(fn(g) { g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 <= y + h + 1.0 && g.2 == @sf.theme().p.subtle })
    None => false
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
  t.run_for(composer_morph_ms)
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
  match send_flight.val {
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
  assert_true(send_flight.val is None)
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
  assert_true(send_flight.val is None)
  let (_, qy) = quote_once(t)
  match t.drawn_of("先上屏") {
    Some((_, wy)) => assert_true(qy < wy, msg="the quote at \{qy}, the words at \{wy}")
    None => fail("the words not drawn")
  }
}
