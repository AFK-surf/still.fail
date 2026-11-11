// A card that asks (ask.mbt's: an agent's ask in a chat, settings' rig_ask, phone_ask, vault_ask) as nodes of the
// window's tree, made once: the card of words (card's), its title and the one line the answer turns on (ask_words'),
// its answer's buttons out in its foot corners (ask_buttons'), a choice there (chooser's at a card's foot). Their
// measures the old ones'. Not here: the night's words and buttons (a player's ask, on_the_night): no node asks so yet.

///|
/// A card of words in `parent` (card's, as nodes): card_pad in from every side, what is on it 14 apart, the card's
/// corner and ground. `body` makes what is on it. The node.
#callsite(autofill(loc))
pub fn ask_card_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> @view.View {
  parent.box(made_for=loc, fn(k) {
    k
    .padding(Is((card_pad, card_pad, card_pad, card_pad)))
    .gap(Is(ask_card_gap))
    .radius(Is(card_corner))
    .ground(By(fn() { theme().p.card }))
    |> ignore
    body(k)
  })
}

///|
/// An ask's `title` and under it the one line the answer turns on (`note`; none while it says none), 12 and quiet, in
/// `parent` (ask_words', as nodes), as they say it now. The node.
#callsite(autofill(loc))
pub fn ask_words_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(w) {
    style_node(w, fn() { ask_what })
    w.box(fn(t) {
      t
      .words_runs(By(fn() { [@ui.span(title(), weight=600, color=theme().p.text)] }))
      .words_look(By(fn() { @ui.style_words(ask_title) }))
      .ink(By(fn() { @ui.style_ink(ask_title) }))
      |> ignore
    })
    |> ignore
    w.show(fn() { note() != "" }, fn(n) { words_node(n, note, fn() { ask_note }) |> ignore })
  })
}

///|
/// Its answer's buttons in `parent` (ask_buttons', as nodes), made by `body` in a row 10 apart, out in the card's foot
/// corners (foot_reach), going on to another line where it has not the room (ask_foot_lines apart). Its buttons say
/// `card_words` (button_node's), as each in the old one's is. Where they go on to another line, the old one's later
/// lines go above its first (its flow_reverse); here under it: the window's tree has no such wrapping yet. The node.
#callsite(autofill(loc))
pub fn ask_buttons_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> @view.View {
  parent.box(made_for=loc, fn(f) {
    style_node(f, fn() { ask_foot.then(foot_reach(button_height())) })
    f.wraps(By(fn() { Some(ask_foot_lines()) })) |> ignore
    body(f)
  })
}

///|
/// A choice at a card's foot (chooser's there, as nodes) in `parent`: chooser_node's, round as a capsule, its words as
/// far in as the card's foot corner leaves them, in a line as high as a button where its capsule meets that corner as
/// the buttons' do. The choice's node.
#callsite(autofill(loc))
pub fn foot_chooser_node(
  parent : @view.View,
  words : () -> String,
  choices : () -> Array[(String, String)],
  chosen : () -> String,
  choose : (String) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(made_for=loc, fn(h) {
    h
    .row(Is(true))
    .height(By(fn() { Some(button_height()) }))
    .padding(By(fn() { (card_foot_in(chooser_h) - card_foot_in(button_height()), 0.0, 0.0, 0.0) }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    made.val = Some(chooser_by(loc~, h, words, choices, chosen, choose, true))
  })
  |> ignore
  made.val.unwrap()
}

///|
/// What is on an ask's card, apart (card's gap).
let ask_card_gap : Double = 14.0
