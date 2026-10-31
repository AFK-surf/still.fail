// A new chat while it is made, and as it becomes its chat (NewChat.kt, the web's NewChat.tsx useEnsureChat and
// madeChat.ts): what both frames' new chat pages and the composer that sends its first message keep of it.

///|
/// What the page keeps while it is a new chat, and as it becomes its chat.
pub(all) struct FreshChat {
  /// the chat made for the first message (its key), and what was picked when it was made: picked anew, it is made
  /// anew (until a message went to it)
  made : @signals.Signal[String]
  made_sig : @signals.Signal[String]
  sent : @signals.Signal[Bool]
  /// a message on its way (the create and the send)
  starting : @signals.Signal[Bool]
  /// its first words sent from the page (its scene leaving from then; back again as the page is the new chat again,
  /// the chat not made: new_sending)
  sending : @signals.Signal[Bool]
  /// the chat it became (its scene leaving over it: new_leave)
  became : @signals.Signal[ChatRef?]
  /// the scene's look as it left: the view it showed; in the wide frame, how tall its composer's place was (what the
  /// scene leaving keeps clear, so nothing of it moves)
  scene : @signals.Signal[Json?]
  room : @signals.Signal[Double]
  /// narrow, how tall its foot was (the band, the choices, the composer): what of the scene leaving is not seen, as it
  /// was not
  foot : @signals.Signal[Double]
}

///|
pub let fresh : FreshChat = {
  made: @signals.signal("", same=fn(a, b) { a == b }),
  made_sig: @signals.signal("", same=fn(a, b) { a == b }),
  sent: @signals.signal(false, same=fn(a, b) { a == b }),
  starting: @signals.signal(false, same=fn(a, b) { a == b }),
  sending: @signals.signal(false, same=fn(a, b) { a == b }),
  became: @signals.signal(None),
  scene: @signals.signal(None),
  room: @signals.signal(0.0, same=fn(a, b) { a == b }),
  foot: @signals.signal(0.0, same=fn(a, b) { a == b }),
}

///|
/// A new chat begun: nothing made for it yet (useEnsureChat's, made once a page).
pub fn fresh_reset() -> Unit {
  fresh.made.set("")
  fresh.made_sig.set("")
  fresh.sent.set(false)
  fresh.starting.set(false)
  fresh.sending.set(false)
  fresh.became.set(None)
  fresh.scene.set(None)
  fresh.room.set(0.0)
  fresh.foot.set(0.0)
}

///|
/// A new chat's scene leaving as it becomes the chat, fading where it is; its choices fading where they are, sooner.
pub let new_leave_ms : Double = 140.0

///|
pub let new_fade_ms : Double = 80.0

///|
/// The new chat's scene fading (0 … 1), its choices fading (0 … 1).
pub fn new_leave(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/leave", 1.0, global=true)
}

///|
pub fn new_fade(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/fade", 1.0, global=true)
}

///|
/// The new chat's first words sent, or the new chat left for a chat: its scene leaves, from now, and its choices fade
/// (on a phone as Android's LeaveFade), over the chat it became (new_chat_leaving_of): as the words go, not once the
/// core has made the chat and taken them in.
pub fn became_starts(wide~ : Bool) -> Unit {
  let c = @ui.current()
  let leave = new_leave(c)
  leave.snap(0.0)
  leave.animate(1.0, @motion.tween(new_leave_ms, ease=Leave))
  let fade = new_fade(c)
  fade.snap(0.0)
  fade.animate(1.0, @motion.tween(new_fade_ms, ease=Leave))
}

///|
/// The new chat's first words not sent after all (the chat not made, or the message refused): its scene and choices
/// back as they were, from where they had gone.
pub fn leaving_back() -> Unit {
  let c = @ui.current()
  new_leave(c).animate(0.0, @motion.tween(new_leave_ms, ease=Out))
  new_fade(c).animate(0.0, @motion.tween(new_fade_ms, ease=Out))
}

///|
/// How far the new chat's scene and its choices have gone (0 … 1 each) while it is the new chat after its first words
/// were sent: the page the new chat again, the chat not made, they coming back from where they had got to (none
/// while it is the chat: the frame draws it leaving over the chat).
pub fn new_sending(c : @ui.Ctx) -> (Double, Double) {
  if fresh.sending.get() && fresh.became.get() is None {
    (new_leave(c).get(), new_fade(c).get())
  } else {
    (0.0, 0.0)
  }
}

///|
/// What was picked, as one string: a pick changed makes the chat anew (until a message went to it).
pub fn picked_sig(v : Json?) -> String {
  text(field(v, "model"), "model") +
  "|" +
  text(v, "runtime") +
  "|" +
  text(v, "effort") +
  "|" +
  text(v, "profile") +
  "|" +
  (match field(v, "fast") {
    Some(True) => "fast"
    Some(False) => "standard"
    _ => ""
  })
}

///|
/// What is picked now (`v`, the newChat view): the chat made for it before is let go if it was made with other picks
/// and nothing was sent to it yet.
pub fn fresh_picked(v : Json?) -> Unit {
  if !fresh.sent.get() && !fresh.starting.get() && picked_sig(v) != fresh.made_sig.get() {
    fresh.made.set("")
  }
}

///|
/// Picks for a new chat in the workspace (`newChat.pick`, the core keeps them): each given changes only that.
pub fn pick_new(src : Source, ws : String, fill : Map[String, Json]) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  fill["scope"] = Json::string(ws)
  (src.call)("newChat.pick", Json::object(fill), fn(res) {
    match res {
      Err(e) => {
        toast_later(@sf.t("android-chat.pick.failed", args=[("error", text(Some(e), "message"))]))
      }
      _ => ()
    }
  })
}

///|
/// The view of the chat a new chat became (`r`), as it is till the core's is read: made with nothing in it but its
/// title (what the page was, 新对话, as the core calls it) and what was sent from here, never said to be empty, as the
/// core's first view of it has its first message in its outbox (views.ts pendingChat); kept for the chat so each frame
/// reads the same (None for any other chat).
pub fn fresh_view(r : ChatRef) -> (ChatView, Array[Entry])? {
  match fresh.became.get() {
    Some(b) if b == r =>
      match fresh_views.val {
        Some((k, v, list)) if k == r => Some((v, list))
        _ => {
          let v = chat_view_made({
            "title": Json::string(r.title),
            "pending": Json::boolean(true),
            "key": Json::string(r.session),
          })
          // (never empty: its first message is in it from the frame it was sent, sent_local)
          let list = entries_of(v).filter(fn(e) { !(e is Empty) })
          fresh_views.val = Some((r, v, list))
          Some((v, list))
        }
      }
    _ => None
  }
}

///|
// kept across runs: one chat's, made again for another (fresh_view)
let fresh_views : Ref[(ChatRef, ChatView, Array[Entry])?] = Ref(None)

///|
/// Whether chat `r` is the one a new chat just became, its scene still leaving over it (till the end declared as it
/// set out).
pub fn new_chat_leaving_of(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became.get() {
    Some(b) => b == r && !new_leave(c).over()
    None => false
  }
}

///|
/// Whether chat `r` was just made from a new chat, its scene still leaving or its first words still carried: the
/// core's own, its first view not read yet, nothing breathing over it (Chat.kt made).
pub fn new_chat_made(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became.get() {
    Some(b) if b == r => !new_leave(c).over() || flight_carried(r.station + ":" + r.session)
    _ => false
  }
}
