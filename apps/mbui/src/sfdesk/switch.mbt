// Between a chat and a new chat in the wide frame, by the sidebar's 新建对话 or a chat's row (still.fail web/src/dock.tsx
// useComposerMove): the composer goes from its place on the one to its place on the other (340 ms, the ease out: its
// own reshape, composer.mbt), a new chat left leaves by its own way (its scene fading where it is, its choices
// fading where they are: fresh.mbt, as a new chat become its chat does), and what comes in is there at once. No page
// crossfades whole (sf/motion.mbt: what is swapped does not move; the web's root view transition is not taken).
// Between two chats nothing moves; a new chat become its chat has its own (newchat.mbt new_chat_after).

///|
/// The page the pane showed as the last frame was built (what a switch is from), whether the switch is away from a new
/// chat, and that new chat's view as it last showed (what leaves as it is left).
priv struct WideSwitch {
  mut was : Page?
  mut from_new : Bool
  mut new_view : Json?
}

///|
let page_switch : WideSwitch = { was: None, from_new: false, new_view: None }

///|
fn page_switch_reset() -> Unit {
  page_switch.was = None
  page_switch.from_new = false
  page_switch.new_view = None
}

///|
/// The page on top become `top` (as the stack is told it: page_switch_said, before any page of it is built): a switch
/// between a chat and a new chat begins, from now, the new chat left as it was last laid out (its composer and its foot
/// as measured then: what was drawn, not what is to be). Once for each page come on top, none for the one it was
/// already; a new chat become its chat in place (fresh.became) none of it, its own way.
fn page_switch_to(top : Page) -> Unit {
  let switched = match (page_switch.was, top) {
    (Some(NewChat), Chat(r)) =>
      match @signals.untracked(fn() { fresh.became.get() }) {
        Some(b) if b == r => false
        _ => true
      }
    (Some(Chat(_)), NewChat) => true
    _ => false
  }
  if switched && !@ui.reduced_motion() {
    page_switch.from_new = page_switch.was == Some(NewChat)
    if page_switch.from_new {
      // (the new chat as it was laid out last: measured as the frame before drew it, read once, followed by nothing)
      let measured = fn(key : String) {
        @signals.untracked(fn() { @motion.measured(@ui.current(), key) }).unwrap_or(0.0)
      }
      fresh.room.set(measured("new/composer"))
      fresh.foot.set(measured("new/foot"))
      // the new chat left: its scene leaves by its own way, from now
      became_starts(wide=true)
    }
  }
  // a new chat come to: nothing made for it yet (NewChat.tsx useEnsureChat: once a page)
  if top == NewChat && page_switch.was != Some(NewChat) {
    fresh_reset()
  }
  page_switch.was = Some(top)
}

///|
/// The page on top followed in node `v` (the wide frame's page's panel, its pane) while `holds` says (the workspace in
/// view, not waiting in its safe mode): each page come on top told page_switch_to as the stack is told it; none while
/// it does not hold, the page on top as it holds again told then.
fn page_switch_said(v : @view.View, holds : () -> Bool) -> Unit {
  v.reacts(fn() { if holds() { Some(app.nav.top()) } else { None } }, fn(top) {
    match top {
      Some(p) => page_switch_to(p)
      None => ()
    }
  })
}

///|
/// The new chat left for a chat, leaving over it by its own way (its scene fading where it is, its choices
/// fading where they are: fresh.mbt), drawn only, its composer gone to the chat's.
fn switch_new_out(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let gone = new_leave(c).get()
  if gone >= 1.0 || !page_switch.from_new || fresh.became.get() is Some(_) {
    return
  }
  let v = page_switch.new_view
  let l = c.layer(fn() { new_left(c, src, w, v, gone, new_fade(c).get()) })
  c.draw_only(l)
}
