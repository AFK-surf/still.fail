// A chat's talk on the desktop (ember web/src/Chat.tsx ChatShown): its list (sfpages chat_list.mbt) over the pane, the
// bar over it, the composer at its foot, what is picked and dropped over them.

///|
/// Chat `r`'s pane (ChatShown): its list running on under the composer (or, before its view is read, what waits for
/// it), `over` it (the bar), and the composer at its foot (composer.mbt chat_composer: the room it takes the list's
/// foot, among what is drawn over the list, with what is let go over the pane, `pane`);
/// the words sent, as typed, till their row is in the list, and the files sent with them, over the composer and under
/// the bar (@ui.Stratum).
pub fn chat_talk(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, pane : Int, over : () -> Unit) -> Unit {
  let (view, read, error) = view_of_chat(src, r)
  let draft = r.station + ":" + r.session
  let room = @sfpages.composer_room(c, draft, settled=@sfbase.new_chat_made(c, r))
  match view {
    Some(v) => {
      latest_key(c, src, r, v)
      chat_list(c, src, r, v, read, room, settings_core(src, w), top=chat_bar_room() + list_head_gap, bar=chat_bar_room())
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
  // the composer, over the cover a row carried over the pane puts up (@ui.Stratum's OverCover: what it is let go into)
  let composer = c.layer(fn() {
    c.spacer()
    @sfpages.chat_composer(c, src, w, r, view, apart=wide.tape.get())
  })
  c.stratum(composer, OverCover)
  // (over the viewer's picture as it flies from the list or back into it)
  over_flight(c, composer)
  // the words sent, as typed, till their row is in the list, and the files sent with them, over the composer
  flight_waiting(c, draft)
  flight_files(c, draft)
  // the bar, over what flies (its Bar)
  over()
  // a row of the 文件 tab carried over the pane: frosted over all of it but the composer (chat_layers.mbt)
  if view is Some(_) {
    drop_hint(c, pane)
  }
  // over it, what is picked in the messages; a row let go over the pane, into the draft
  if view is Some(_) {
    chat_layers(c, src, r, draft, pane, room)
  }
  chat_drop(c, src, r.station, draft, pane)
  // words dragged in from another app and let go anywhere on the pane but a field (a field takes them where they
  // were let go: ⌘F's, the composer's): into the composer's field at its caret, as a paste's; not an archived chat's,
  // whose composer a press does not open either
  // files from this machine's Finder let go anywhere on it but another field, where it is a station: into the draft by
  // their station and path, as a row of the 文件 tab let go there (chat_drop); elsewhere as words, as above
  if !(view is Some({ archived: true, .. })) && @sfbase.finder_by_station() {
    match c.paths_into(pane, @sfpages.composer_field_key) {
      Some(paths) => {
        let dragged = @sfbase.finder_dragged(src, paths)
        c.tell("chat-drop/" + draft, fn() {
          writing_drop(src, writing(src, draft), r.station, dragged.map(@sfpages.dropped_of), @sfpages.drops_as_files(src, draft))
        })
      }
      None => ()
    }
  }
  if !(view is Some({ archived: true, .. })) {
    c.words_into(pane, @sfpages.composer_field_key)
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

///|
/// How tall the chat's bar over the list is (pageBar: 45; in a panel of its own as much taller as puts its buttons in
/// the panel's corner concentric with it: chat_bar_box_tape), and the list's room under it over its first row (24).
fn chat_bar_room() -> Double {
  @sf.wide_bar_h + (if @sf.in_pane() { @sf.tape_bar_over() } else { 0.0 })
}

///|
let list_head_gap : Double = 24.0
