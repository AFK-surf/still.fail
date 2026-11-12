// What a message's row offers of itself and of its agent, as nodes of the window's tree (the old row's pickable and
// share_turn_tool, agent_hover): its own items (@sfbase.message_items: its words, its link, its turn shared) right
// clicked into the window's menu as the old row's are (@sfbase.share_offer); an agent's card over its picture and its
// name (hover.mbt's agent_hover: @sf.hover_card_node, its card agent_card_node), a finger's hold on its name too.
// Not here yet: touch's way to what the ⋯ offers (@sf.more_held: the bar over words held, pick_layer's, the chat's
// overlays' to come; a hold on the row itself is not taken in the chat's list as made now).

///|
/// Row `row` of a message offering `s`: right clicked, its items offered to the window's menu at the click (its link,
/// the words picked there with them: share_offer).
fn message_menu_node(row : @view.View, s : MessageShare) -> Unit {
  row.on_menu(fn(m) {
    @sfbase.share_offer(m.wx, m.wy, s.go, @signals.untracked(s.link), @signals.untracked(s.words), s.key)
  })
  |> ignore
}

///|
/// Agent `agent`'s card (agent_hover's: agent_card_node, in a tile) over `trigger` while a mouse's pointer rests on it,
/// to a finger as it holds it (not `pointed`), in the chat `here` is; kept open while what was opened from it is.
/// `words_along`: a trigger that is words (its name), the card's words starting where they start. `press`: what a press
/// on `trigger` does (its name's: its history), which the card's hand then takes (one gesture a node); none, the
/// trigger's presses what holds it's. `pointed`: under a mouse's pointer alone (the pointer within it, whatever is over
/// it), nothing of the hand put on it: a picture, smaller than a press's room, which a finger's hold would make a press
/// of 18 (or 24) in under 44 (t.audit()'s `room`); a finger's is the hold on its name, a press's room at least.
fn message_agent_card_node(
  trigger : @view.View,
  src : Source,
  here : MessageNodeHere,
  agent : String,
  words_along? : Bool = false,
  press? : () -> Unit,
  pointed? : Bool = false,
) -> Unit {
  let hand : Ref[@sf.HoverHand?] = Ref(None)
  let held : Ref[() -> Bool] = Ref(fn() { false })
  let card = fn() {
    match hand.val {
      Some(h) => (h.card)()
      None => None
    }
  }
  hand.val = Some(
    @sf.hover_card_node(
      here.tips,
      trigger,
      fn(c) { held.val = agent_card_node(c, src, message_node_ref(here), agent, here.tips, card) },
      tile=true,
      along_offset=if words_along { -@sf.panel_pad - hover_words_in } else { 0.0 },
      held=fn() { (held.val)() },
      press?,
      pointed?=if pointed { Some(fn() { trigger.pointer_within() }) } else { None },
    ),
  )
}
