// A chat's talk on the desktop (ember web/src/Chat.tsx ChatShown): its list (sfpages chat_list.mbt) over the pane, the
// bar over it, the composer at its foot, what is picked and dropped over them.

///|
/// Chat `r`'s pane (ChatShown): its list running on under the composer (or, before its view is read, what waits for
/// it), `over` it (the bar), and the composer at its foot (composer.mbt chat_composer: the room it takes the list's
/// foot, among what is drawn over the list, with what is let go over the pane, `pane`);
/// the words sent, as typed, till their row is in the list, and the files sent with them, over all of it.
pub fn chat_talk(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, pane : Int, over : () -> Unit) -> Unit {
  let (view, read, error) = view_of_chat(src, r)
  let draft = r.station + ":" + r.session
  let room = @sfpages.composer_room(c, draft)
  match view {
    Some(v) => {
      latest_key(c, src, r, v)
      chat_list(c, src, r, v, read, room, settings_core(src, w))
    }
    None => {
      // (a chat just made from a new chat is the core's own: nothing breathing while its first view comes)
      if error is Some(_) || !new_chat_made(c, r) {
        @sf.waiting(c, shape=Messages, error=match error {
          Some(e) => @sf.t("android-chat.chat.unreadable", args=[("error", text(Some(e), "message"))])
          None => ""
        })
      }
      flight_frame(c, draft)
    }
  }
  over()
  // come to from a new chat: what it showed fading under the composer (switch.mbt)
  if view is Some(_) {
    switch_veil(c)
  }
  // a row of the 文件 tab carried over the pane: frosted under the composer (chat_layers.mbt)
  if view is Some(_) {
    drop_hint(c, pane)
  }
  c.layer(fn() {
    c.spacer()
    @sfpages.chat_composer(c, src, w, r, view, apart=wide.tape)
  })
  |> ignore
  // over it, what is picked in the messages; a row let go over the pane, into the draft
  if view is Some(_) {
    chat_layers(c, src, r, draft, pane, room)
  }
  chat_drop(c, src, r.station, draft, pane)
  flight_waiting(c, draft)
  flight_files(c, draft)
}

///|
/// Whether chat `r` was just made from a new chat, its page still leaving or its first words still carried.
fn new_chat_made(c : @ui.Ctx, r : ChatRef) -> Bool {
  match fresh.became {
    Some(b) if b == r => new_leave(c).moving() || flight_carried(r.station + ":" + r.session)
    _ => false
  }
}

///|
/// ⌘↓ (chat.latest): the list to its end, following it again; short of the chat's end, its latest page.
fn latest_key(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  if @settings.action_pressed(c, prefs, "chat.latest") {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) => {
          let station = r.station
          c.tell("chat.latest", fn() {
            (src.call)("chat.latest", { "station": Json::string(station), "thread": Json::number(th) }, fn(_) {  })
          })
        }
        None => ()
      }
    }
  }
}
