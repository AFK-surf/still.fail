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
      chat_list(c, src, r, v, read, room, settings_core(src, w), top=chat_bar_room() + list_head_gap)
    }
    None => {
      // (a chat just made from a new chat is the core's own: nothing breathing while its first view comes)
      // (under the bar, as the list's first row is)
      if error is Some(_) || !@sfbase.new_chat_made(c, r) {
        // (its messages to come in their bones, the first where the list's first row will be)
        let under = @sf.under_bar_room().px()
        c.box(style=@ui.style(w=Full, pt=@sf.under_bar_room()), fn() {
          @sf.waiting(c, fn() { @sfpages.chat_messages_sample(c, chat_bar_room() + list_head_gap - under) }, error=match error {
            Some(e) => @sf.t("android-chat.chat.unreadable", args=[("error", text(Some(e), "message"))])
            None => ""
          })
        })
        |> ignore
      }
      flight_frame(c, draft)
    }
  }
  over()
  // a row of the 文件 tab carried over the pane: frosted under the composer (chat_layers.mbt)
  if view is Some(_) && !@sfbase.motion_demo.val {
    drop_hint(c, pane)
  }
  c.layer(fn() {
    c.spacer()
    @sfpages.chat_composer(c, src, w, r, view, apart=wide.tape)
  })
  |> ignore
  if view is Some(_) && @sfbase.motion_demo.val {
    drop_hint(c, pane)
  }
  // over it, what is picked in the messages; a row let go over the pane, into the draft
  if view is Some(_) {
    chat_layers(c, src, r, draft, pane, room)
  }
  chat_drop(c, src, r.station, draft, pane)
  flight_waiting(c, draft)
  flight_files(c, draft)
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

///|
/// How tall the chat's bar over the list is (pageBar: 45; in a panel of its own as much taller as puts its buttons in
/// the panel's corner concentric with it: chat_bar_box_tape), and the list's room under it over its first row (24).
fn chat_bar_room() -> Double {
  @sf.wide_bar_h + (if @sf.in_pane() { @sf.tape_bar_over() } else { 0.0 })
}

///|
let list_head_gap : Double = 24.0
