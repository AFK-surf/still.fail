// A new chat while it is made, and as it becomes its chat (NewChat.kt, the web's NewChat.tsx useEnsureChat and
// madeChat.ts): what both frames' new chat pages and the composer that sends its first message keep of it.

///|
/// What the page keeps while it is a new chat, and as it becomes its chat.
pub(all) struct FreshChat {
  /// the chat made for the first message (its key), and what was picked when it was made: picked anew, it is made
  /// anew (until a message went to it)
  mut made : String
  mut made_sig : String
  mut sent : Bool
  /// a message on its way (the create and the send)
  mut starting : Bool
  /// the chat it became (its scene leaving over it: new_leave)
  mut became : ChatRef?
  /// the scene's look as it left: the view it showed; in the wide frame, how tall its composer's place was (what the
  /// scene leaving keeps clear, so nothing of it moves)
  mut scene : Json?
  mut room : Double
}

///|
pub let fresh : FreshChat = {
  made: "",
  made_sig: "",
  sent: false,
  starting: false,
  became: None,
  scene: None,
  room: 0.0,
}

///|
/// A new chat begun: nothing made for it yet (useEnsureChat's, made once a page).
pub fn fresh_reset() -> Unit {
  fresh.made = ""
  fresh.made_sig = ""
  fresh.sent = false
  fresh.starting = false
  fresh.became = None
  fresh.scene = None
  fresh.room = 0.0
}

///|
/// A new chat's scene leaving as it becomes the chat: up out of view as it fades; its choices fading where they are.
pub let new_leave_ms : Double = 140.0

///|
pub let new_fade_ms : Double = 80.0

///|
/// The new chat's scene leaving (0 … 1: up out of view, Arrive), its choices fading (0 … 1).
pub fn new_leave(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/leave", 1.0, global=true)
}

///|
pub fn new_fade(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "new/fade", 1.0, global=true)
}

///|
/// The new chat became the chat: its scene leaves, from now (the web's both on its EASE, madeChat.ts toMadeChat; on a
/// phone its choices fade as Android's LeaveFade).
pub fn became_starts(wide~ : Bool) -> Unit {
  let c = @ui.current()
  let leave = new_leave(c)
  leave.snap(0.0)
  leave.animate(1.0, @motion.tween(new_leave_ms, ease=Arrive))
  let fade = new_fade(c)
  fade.snap(0.0)
  fade.animate(1.0, @motion.tween(new_fade_ms, ease=if wide { Arrive } else { LeaveFade }))
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
  if !fresh.sent && !fresh.starting && picked_sig(v) != fresh.made_sig {
    fresh.made = ""
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
/// Whether chat `r` is the one a new chat just became, its scene still leaving over it (till the end declared as it
/// set out).
pub fn new_chat_leaving_of(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became {
    Some(b) => b == r && !new_leave(c).over()
    None => false
  }
}

///|
/// Whether chat `r` was just made from a new chat, its scene still leaving or its first words still carried: the
/// core's own, its first view not read yet, nothing breathing over it (Chat.kt made).
pub fn new_chat_made(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became {
    Some(b) if b == r => !new_leave(c).over() || flight_carried(r.station + ":" + r.session)
    _ => false
  }
}
