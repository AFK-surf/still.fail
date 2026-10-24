// What a chat's messages draw that is not the desktop's own yet (src/sfdesk/message.mbt): the file preview a file of
// a message opens in, and the thumbnail it flies from and back into; a visualization drawn where its message places
// it; a link opened, and its menu; a station's screens as their cards. Given by the app as it starts
// (src/sfapp/app.mbt), each moving into sfdesk on its own without the messages changing but for the line that calls it.

///|
/// What a chat's messages draw that is the app's (above).
pub(all) struct ChatParts {
  /// file `a` of the chat on `station`, kept by session `owner`, opened over the app; an image steps through the
  /// chat's (by its thread, else its session: the core's `imageNear`)
  open_file : (String, String, Attachment, Double?, String) -> Unit
  /// a thumbnail of a message's file drawn this frame as node `node` (its id, its corners, whether letterboxed): what
  /// the preview flies from; and how much of it shows (none while the preview is its picture)
  thumb : (@ui.Ctx, String, Int, Double, Bool) -> Unit
  thumb_shows : (String) -> Double
  /// a video's still as the preview left it, else the station's (or one drawn here): its image's key ("" none)
  video_still : (@ui.Ctx, Source, String, String, Attachment, String) -> String
  /// the picture a file was sent from here as, which flew in to it
  sent_picture : (String, Attachment) -> String?
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
  open_file: fn(_, _, _, _, _) {  },
  thumb: fn(_, _, _, _, _) {  },
  thumb_shows: fn(_) { 1.0 },
  video_still: fn(_, _, _, _, _, _) { "" },
  sent_picture: fn(_, _) { None },
  viz: fn(_, _, _, _, _, _, _, failed) { failed() },
  viz_open: fn(_, _, _, _) {  },
  mermaid: fn(_, _, _) {  },
  screens: fn(_, _, _) { None },
  open_link: fn(_) {  },
  in_front: fn() { true },
})
