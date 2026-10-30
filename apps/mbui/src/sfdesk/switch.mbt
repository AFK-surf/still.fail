// Between a chat and a new chat in the wide frame, by the sidebar's 新建对话 or a chat's row (ember web/src/dock.tsx
// useComposerMove): the composer goes from its place on the one to its place on the other (340 ms, the ease out: its
// own reshape, composer.mbt), a new chat left leaves by its own way (its scene fading where it is, its choices
// fading where they are: fresh.mbt, as a new chat become its chat does), and what comes in is there at once. No page
// crossfades whole (docs/motion.md: what is swapped does not move; the web's root view transition is not taken).
// Between two chats nothing moves; a new chat become its chat has its own (newchat.mbt new_chat_after).

///|
/// The page the pane showed as the last frame was built (what a switch is from), whether the switch is away from a new
/// chat, and that new chat's view as it last showed (what leaves as it is left).
priv struct WideSwitch {
  was : @signals.Signal[Page?]
  from_new : @signals.Signal[Bool]
  new_view : @signals.Signal[Json?]
}

///|
let page_switch : WideSwitch = { was: @signals.signal(None), from_new: @signals.signal(false, same=fn(a, b) { a == b }), new_view: @signals.signal(None )}

///|
fn page_switch_reset() -> Unit {
  page_switch.was.set(None)
  page_switch.from_new.set(false)
  page_switch.new_view.set(None)
}

///|
/// As the pane's page is built: a switch between a chat and a new chat begins, from now.
fn page_switch_frame(c : @ui.Ctx) -> Unit {
  let top = app.nav.top()
  let switched = match (page_switch.was.get(), top) {
    (Some(NewChat), Chat(r)) =>
      match fresh.became.get() {
        Some(b) if b == r => false
        _ => true
      }
    (Some(Chat(_)), NewChat) => true
    _ => false
  }
  if switched && !@ui.reduced_motion() {
    page_switch.from_new.set(page_switch.was.get() == Some(NewChat))
    if page_switch.from_new.get() {
      fresh.room.set(@motion.measured(c, "new/composer").unwrap_or(0.0))
      // the new chat left: its scene leaves by its own way, from now
      became_starts(wide=true)
    }
  }
  // a new chat come to: nothing made for it yet (NewChat.tsx useEnsureChat: once a page)
  if top == NewChat && page_switch.was.get() != Some(NewChat) {
    fresh_reset()
  }
  page_switch.was.set(Some(top))
}

///|
/// The new chat left for a chat, leaving over it by its own way (its scene fading where it is, its choices
/// fading where they are: fresh.mbt), drawn only, its composer gone to the chat's.
fn switch_new_out(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let gone = new_leave(c).get()
  if gone >= 1.0 || !page_switch.from_new.get() || fresh.became.get() is Some(_) {
    return
  }
  let v = page_switch.new_view.get()
  let l = c.layer(fn() { new_left(c, src, w, v, gone, new_fade(c).get()) })
  c.draw_only(l)
}
