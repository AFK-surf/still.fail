// Between a chat and a new chat in the wide frame, by the sidebar's 新建对话 or a chat's row (still.fail web/src/dock.tsx
// useComposerMove): the composer goes from its place on the one to its place on the other (340 ms, the ease out: its
// own reshape, composer.mbt), and the rest of the page is the other's at once, what was there gone in that frame. A new
// chat left for a chat it did not become is another thing looked at: its scene does not fade over the chat (it did till
// 2026-11-14, its words seen over the chat's own as it went: the coordinator of the migration's ruling, 「整页当帧换
// 掉」). No page crossfades whole (sf/motion.mbt: what is swapped does not move; the web's root view transition is not
// taken). Between two chats nothing moves; a new chat become its chat has its own (newchat.mbt new_chat_after).

///|
/// The page the pane showed as the last frame was built (what a switch is from).
priv struct WideSwitch {
  mut was : Page?
}

///|
let page_switch : WideSwitch = { was: None }

///|
fn page_switch_reset() -> Unit {
  page_switch.was = None
}

///|
/// The page on top become `top` (as the stack is told it: page_switch_said, before any page of it is built): a new
/// chat come to from another page begins with nothing made for it yet. Once for each page come on top, none for the
/// one it was already.
fn page_switch_to(top : Page) -> Unit {
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
