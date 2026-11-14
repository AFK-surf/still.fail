// The cards over a node's links (link_cards_node): each link's own, made as its link comes and let go as it goes; opened
// as a mouse's pointer rests on that link's piece hover_card_open_ms and not on the rest of the words, beside that piece
// (under it, at its start), closed hover_card_close_ms after the pointer has left it and the card; a finger's hold and a
// right click the words' links' own (their menu), no card; what a card reads read from the moment the pointer comes
// onto its link while it or its card is there. At 60, 120, 24 and 7 frames a second the same.

///|
/// What a link_rig made: its Tester; the hands of the cards made, by their links' first runs; how many times each link
/// was held (its hold, a finger's or a right click); each link's reading as it turned (its link, on or off); the runs.
struct LinkRig {
  t : @ui.Tester
  hands : Map[Int, HoverHand]
  held : Map[String, Int]
  reads : Array[(String, Bool)]
  runs : @signals.Signal[Array[@ui.Run]]
}

///|
/// Links 甲 (to a) and 乙 (to b) in words in pieces, 40 in, 60 down, in a window 800 by 500 (`platform` 0 a mouse's, 2 a
/// touch screen's): each link's card holding its link's words in a card; 乙's none where `bare_b`.
fn link_rig(platform? : Int = 0, bare_b? : Bool = false) -> LinkRig {
  set_words(fn(key, _) { key })
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=500.0, platform~)
  t.check_looks(false)
  let held : Map[String, Int] = Map([])
  let reads : Array[(String, Bool)] = []
  let runs : @signals.Signal[Array[@ui.Run]] = @signals.signal([
    @ui.plain("先看 "),
    { ..@ui.plain("甲的链接"), link: "a" },
    @ui.plain("，再看 "),
    { ..@ui.plain("乙的链接"), link: "b" },
    @ui.plain("，就这些。"),
  ])
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(col) {
      col.padding(Is((60.0, 40.0, 0.0, 40.0))) |> ignore
      let shown : @signals.Signal[Array[(String, String, Int)]] = @signals.signal([])
      let links : Ref[@ui.RunsLinks?] = Ref(None)
      let words = col.box(fn(w) {
        w.words_runs(By(fn() { runs.get() })).width(Is(Some(400.0))) |> ignore
        links.val = Some(
          @ui.runs_links(
            w,
            fn() { runs.get() },
            fn(_) {  },
            hold=fn(href, _) { held[href] = held.get(href).unwrap_or(0) + 1 },
            shown=fn(now) { shown.set(now) },
          ),
        )
      })
      let made = link_cards_node(col, tips, words, links.val.unwrap(), fn() { shown.get() }, fn(l) {
        guard !(bare_b && l.href == "b") else { return None }
        l.node.reacts(l.reading, at_start=false, fn(on) { reads.push((l.href, on)) })
        Some({
          tile: false,
          body: fn(b) {
            b.box(fn(x) { x.words(By(fn() { (l.words)() + "的卡" })).says(Is(Some(@view.said(Text, label=l.href + "的卡")))) |> ignore })
            |> ignore
          },
        })
      })
      hands_of.val = made
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)).over_all(Is(true)) |> ignore }))
  })
  t.draw()
  { t, hands: hands_of.val, held, reads, runs }
}

///|
// kept across runs: the last rig's hands, handed out as it is made (each rig sets it as its tree is made)
let hands_of : Ref[Map[Int, HoverHand]] = Ref({})

///|
/// Where the words `s` of the rig's paragraph are drawn (its first line's piece), and its middle.
fn LinkRig::piece(self : LinkRig, s : String) -> (Double, Double, Double, Double) raise {
  match self.t.run_rects(s) {
    [r, ..] => r
    [] => fail("no words drawn holding \{s}")
  }
}

///|
fn LinkRig::middle(self : LinkRig, s : String) -> (Double, Double) raise {
  let r = self.piece(s)
  (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
}

///|
/// Whether the card of the link starting at run `first` is open.
fn LinkRig::open(self : LinkRig, first : Int) -> Bool {
  match self.hands.get(first) {
    Some(h) => @signals.untracked(h.open)
    None => false
  }
}

///|
/// Where the card holding `words` is drawn (its words' place), if it is.
fn LinkRig::card_at(self : LinkRig, words : String) -> (Double, Double)? {
  match self.t.rect_of(words) {
    Some((x, y, _, _)) => Some((x, y))
    None => None
  }
}

///|
test "a mouse resting on a link: its own card after hover_card_open_ms, beside that link (under it, at its start), not the other's; off it and the card, gone hover_card_close_ms after" {
  let r = link_rig()
  let short = 20.0
  r.t.move_to(r.middle("甲的链接").0, r.middle("甲的链接").1)
  r.t.run_for(hover_card_open_ms - short)
  assert_false(r.open(1), msg="not yet")
  r.t.run_for(short + hover_card_in_ms + short)
  assert_true(r.open(1), msg="甲's open")
  assert_false(r.open(3), msg="乙's not")
  let (px, py, _, ph) = r.piece("甲的链接")
  match r.card_at("甲的链接的卡") {
    // (its words 10 in from the card's padding 8 (a small panel's): the card at the piece's start, 6 under it)
    Some((x, y)) => assert_true(x > px && x < px + 40.0 && y > py + ph + hover_card_offset, msg="\{Repr((x, y, px, py, ph))}")
    None => fail("甲's card not drawn")
  }
  assert_true(r.card_at("乙的链接的卡") is None)
  // (off both: gone a while after)
  r.t.move_to(760.0, 480.0)
  r.t.run_for(hover_card_close_ms - short)
  assert_true(r.open(1), msg="still, a while")
  r.t.run_for(short + hover_card_out_ms + short)
  assert_false(r.open(1), msg="gone")
  assert_true(r.card_at("甲的链接的卡") is None)
  // (onto 乙: its own, beside it)
  r.t.move_to(r.middle("乙的链接").0, r.middle("乙的链接").1)
  r.t.run_for(hover_card_open_ms + hover_card_in_ms + short)
  assert_true(r.open(3) && !r.open(1))
  let (bx, _, _, _) = r.piece("乙的链接")
  match r.card_at("乙的链接的卡") {
    Some((x, _)) => assert_true(x > bx && x < bx + 40.0, msg="\{Repr((x, bx))}")
    None => fail("乙's card not drawn")
  }
  let faults = r.t.audit()
  assert_true(faults.is_empty(), msg=faults.join(" | "))
}

///|
test "a mouse resting on the words between links opens none; one resting on a link with no card opens none" {
  let r = link_rig(bare_b=true)
  r.t.move_to(r.middle("先看").0, r.middle("先看").1)
  r.t.run_for(hover_card_open_ms + hover_card_in_ms + 20.0)
  assert_false(r.open(1) || r.open(3))
  assert_true(r.hands.get(3) is None, msg="乙 has no card")
  r.t.move_to(r.middle("乙的链接").0, r.middle("乙的链接").1)
  r.t.run_for(hover_card_open_ms + hover_card_in_ms + 20.0)
  assert_true(r.card_at("乙的链接的卡") is None)
  assert_false(r.open(1))
}

///|
test "a finger's long press on a link is its hold (its menu), no card; a right click the same" {
  let r = link_rig(platform=2)
  let (x, y) = r.middle("甲的链接")
  r.t.touch(0, x, y)
  r.t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  r.t.touch(2, x, y)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(r.held.get("a"), Some(1))
  assert_false(r.open(1), msg="no card by a finger")
  assert_true(r.card_at("甲的链接的卡") is None)
  let m = link_rig()
  let (x, y) = m.middle("乙的链接")
  m.t.right_click(x, y)
  m.t.run_for(@ui.move_most_ms)
  assert_eq(m.held.get("b"), Some(1))
}

///|
test "what a card reads is read from the moment the pointer comes onto its link, while it or its card is there; let go once neither" {
  let r = link_rig()
  let (x, y) = r.middle("甲的链接")
  r.t.move_to(x, y)
  r.t.frame()
  assert_eq(r.reads, [("a", true)], msg="read as the pointer comes onto it")
  r.t.run_for(hover_card_open_ms + hover_card_in_ms + 20.0)
  // (onto its card: still read)
  match r.card_at("甲的链接的卡") {
    Some((cx, cy)) => r.t.move_to(cx + 4.0, cy + 4.0)
    None => fail("甲's card not drawn")
  }
  r.t.run_for(hover_card_close_ms + 20.0)
  assert_eq(r.reads, [("a", true)], msg="on its card: still read")
  // (off both: let go once its card is gone)
  r.t.move_to(760.0, 480.0)
  r.t.run_for(hover_card_close_ms + hover_card_out_ms + 40.0)
  assert_eq(r.reads, [("a", true), ("a", false)])
}

///|
test "a link said again without it: its card let go, its hand gone; the other's kept" {
  let r = link_rig()
  assert_true(r.hands.contains(1) && r.hands.contains(3))
  let (x, y) = r.middle("乙的链接")
  r.t.move_to(x, y)
  r.t.run_for(hover_card_open_ms + hover_card_in_ms + 20.0)
  assert_true(r.open(3))
  r.runs.set([@ui.plain("先看 "), { ..@ui.plain("甲的链接"), link: "a" }, @ui.plain("，就这些。")])
  r.t.run_for(hover_card_out_ms + 20.0)
  assert_true(r.hands.contains(1), msg="甲's kept")
  assert_false(r.hands.contains(3), msg="乙's let go")
  assert_true(r.card_at("乙的链接的卡") is None)
}
