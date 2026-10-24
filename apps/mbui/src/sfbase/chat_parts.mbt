// What a chat's messages draw that is not the desktop's own yet (src/sfdesk/message.mbt): a visualization drawn where its message places
// it; a link opened, and its menu; a station's screens as their cards. Given by the app as it starts
// (src/sfapp/app.mbt), each moving into sfdesk on its own without the messages changing but for the line that calls it.

///|
/// What a chat's messages draw that is the app's (above).
pub(all) struct ChatParts {
  /// an HTML file a message (its ts) of chat `session` on `station` places, kept by `owner`, drawn there as a
  /// visualization (`failed` drawn in its place when it cannot be), and opened over the whole window; a Mermaid block
  /// drawn (its place's key)
  viz : (@ui.Ctx, Source, String, String, String, String, Attachment, () -> Unit) -> Unit
  viz_open : (String, String, String, Attachment) -> Unit
  mermaid : (@ui.Ctx, String, String) -> Unit
  /// a station's screens' links as their cards (by the message's key)
  screens : (@ui.Ctx, Source, String) -> @sf.Screens?
  /// a link pressed in a message: one of still.fail's opened here as the core says, any other by the system
  open_link : (String) -> Unit
  /// whether the app is shown (what is said in a chat then is watched: its messages come in)
  in_front : () -> Bool
}

///|
// kept across runs: given once as the app starts (src/sfapp/app.mbt)
pub let chat_parts : Ref[ChatParts] = Ref({
  viz: fn(_, _, _, _, _, _, _, failed) { failed() },
  viz_open: fn(_, _, _, _) {  },
  mermaid: fn(_, _, _) {  },
  screens: fn(_, _, _) { None },
  open_link: fn(_) {  },
  in_front: fn() { true },
})
