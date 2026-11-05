// A card that asks (ask.mbt's) as nodes of the window's tree, made once: its room under a post (ask_card_room: as
// wide as what it says, 320 at least where there is room, 560 at most), the card (card's: card_pad in, its gap, the
// card's ground and corner), its title the question and the line the answer turns on, its buttons in its foot corners.

///|
/// The room of a card that asks under a post (ask_card_room's) in `parent`: as wide as what it says, `least` at least
/// where there is the room, 560 at most (`least` 560: as wide as it may be whatever it says, ask_card_room_most's).
/// `body` makes what it holds.
pub fn ask_card_room_node(parent : @view.View, body : (@view.View) -> Unit, least? : Double = 320.0) -> @view.View {
  parent.box(fn(room) {
    room
    .min_width_within(Is(Some(least)))
    // (never wider than what holds it)
    .max_width_within(Is(Some(560.0)))
    |> ignore
    body(room)
  })
}

///|
/// A card (card's) in `parent`: card_pad in, `gap` between what it holds, on the card's ground, round as a card;
/// `fill` as wide as what holds it. `body` makes what it holds.
pub fn card_node(parent : @view.View, body : (@view.View) -> Unit, gap? : Double = 14.0, fill? : Bool = false) -> @view.View {
  parent.box(fn(k) {
    k
    .padding(Is((card_pad, card_pad, card_pad, card_pad)))
    .gap(Is(gap))
    .radius(Is(card_corner))
    .ground(By(fn() { theme().p.card }))
    .grow(Is(if fill { 1.0 } else { 0.0 }))
    |> ignore
    body(k)
  })
}

///|
/// An ask's title and under it the one line the answer turns on ("" none), 12 and quiet (ask_words'), in `parent`:
/// the title's words heavier, in the text's ink; 2 between them.
pub fn ask_words_node(parent : @view.View, title : () -> String, note : () -> String) -> @view.View {
  parent.box(fn(w) {
    w.gap(Is(2.0)) |> ignore
    w.box(fn(t) {
      t
      .words_runs(By(fn() { [@ui.span(title(), weight=600)] }))
      .words_look(By(fn() { @ui.style_words(ask_title) }))
      .ink(By(fn() { theme().p.text }))
      |> ignore
    })
    |> ignore
    w.show(fn() { note() != "" }, fn(n) {
      n.words(By(note)).words_look(By(fn() { @ui.style_words(ask_note) })).ink(By(fn() { @ui.style_ink(ask_note) })) |> ignore
    })
  })
}

///|
/// An answer's buttons out in a card's foot corners (ask_buttons'): 10 apart, on lines ask_foot_lines apart where
/// they do not fit (above the first, which stays in the card's bottom corner), the first and the last concentric with
/// the card's foot corners. `body` makes them, each `at_foot`.
pub fn ask_buttons_node(parent : @view.View, body : (@view.View) -> Unit) -> @view.View {
  parent.box(fn(f) {
    let out = card_foot_in(button_height()) - card_pad
    f
    .row(Is(true))
    .gap(Is(10.0))
    .lines_up(Is(Some(Middle)))
    .wraps(By(fn() { Some(ask_foot_lines()) }))
    .wraps_up(Is(true))
    .margin(Is((out, 0.0, out, out)))
    |> ignore
    body(f)
  })
}

///|
/// What is typed in just over a card's foot (over_foot_reach's) in `parent`: out to its corners as the buttons under it
/// are, `gap` between what it holds, each `at_foot` (its words on the card's line). `body` makes it.
pub fn over_foot_node(parent : @view.View, body : (@view.View) -> Unit, gap? : Double = 8.0) -> @view.View {
  parent.box(fn(o) {
    let out = card_foot_in(button_height()) - card_pad
    o.gap(Is(gap)).margin(Is((out, 0.0, out, 0.0))) |> ignore
    body(o)
  })
}
