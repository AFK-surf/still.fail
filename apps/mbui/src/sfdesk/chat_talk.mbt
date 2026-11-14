// A chat's talk on the desktop (still.fail web/src/Chat.tsx ChatShown): its list (sfpages chat_list.mbt) over the pane, the
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
      // (a picture flying from it drawn under the bar in the page's slot while it is under it (sfbase's
      // viewer_flight_slot, chat_page_made's): the bar is the page's nodes (chat_bar_wide_node), which the viewer's
      // layer is over, so the old view's lifting it over the flight (over_flight) lifts none of it)
      chat_list(c, src, r, v, read, room, settings_core(src, w), top=chat_bar_room() + list_head_gap, bar=chat_bar_room(), slotted=true)
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
    chat_layers(c, src, r, draft, room)
  }
  chat_drop(c, src, r.station, draft, pane)
  // words dragged in from another app and let go anywhere on the pane but a field (a field takes them where they
  // were let go: ⌘F's, the composer's): into the composer's field at its caret, as a paste's
  // files from this machine's Finder let go anywhere on it but another field, where it is a station: into the draft by
  // their station and path, as a row of the 文件 tab let go there (chat_drop); elsewhere as words, as above
  if @sfbase.finder_by_station() {
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
  c.words_into(pane, @sfpages.composer_field_key)
}

///|
/// ⌘↓ (chat.latest), an action of the chat's as it is built, done at its key's moment: the list to its end, following
/// it again; short of the chat's end, its latest page.
fn latest_key(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView) -> Unit {
  c.on_action("chat.latest", fn() {
    if !v.newer {
      // (asked of the list where it is built, as a row's way to the end asks it: the action runs outside the scope
      // the list is built in, where its key names no list and the key did nothing, chat_keys_wbtest.mbt)
      reading_of(r.station + "\u{1}" + r.session).end_asked = true
    } else {
      match v.thread {
        Some(th) =>
          (src.call)("chat.latest", { "station": Json::string(r.station), "thread": Json::number(th) }, @sfbase.answer_unread)
        None => ()
      }
    }
    true
  })
}

///|
/// How tall the chat's bar over the list is (pageBar: 45; in a panel of its own as much taller as puts its buttons in
/// the panel's corner concentric with it: chat_bar_box_tape; `in_pane` as the page built now is), and the list's room
/// under it over its first row (24).
fn chat_bar_room(in_pane? : Bool = @sf.in_pane()) -> Double {
  @sf.wide_bar_h + (if in_pane { @sf.tape_bar_over() } else { 0.0 })
}

///|
let list_head_gap : Double = 24.0

///|
/// Chat `r`'s messages where its page is made with its inside nodes (sfbase's chat_page_nodes: chat_page_made's
/// `body`, `shows` whether it is drawn), in `v`, as wide as it is given: under the bar's room, `in_pane` the page a
/// panel of its own (chat_bar_room); its composer made by `composer` in the list's foot. What the page's old view
/// hands the system's bars said here as nodes (chat_bar_handed_node); ⌘F its find, in its bar.
fn chat_body_nodes(
  v : @view.View,
  src : Source,
  r : ChatRef,
  tips : @sf.TipLayer,
  stint : () -> Int,
  composer : (@view.View) -> Unit,
  shows : () -> Bool,
  in_pane? : Bool = false,
) -> Unit {
  // (the composer's node: what is carried over it is its own to show, chat_drop_node)
  let held : Ref[@view.View?] = Ref(None)
  // (what covers its top is the bar as it is drawn; its room under it, room)
  @sfpages.chat_page_body_node(
    v,
    src,
    r,
    tips~,
    stint~,
    shows~,
    cover=fn() { chat_bar_room(in_pane~) },
    room=list_head_gap,
    composer=fn(n) {
      held.val = Some(n)
      composer(n)
    },
  )
  // ⌘F (chat.find, the keymap's Chat, taken while the tree gives the page keys): the chat's find opened in its bar
  // (wide_bar_of's), as the old page's chat_page took it, but in a chat not made yet
  v.on_action("chat.find", fn(_) {
    guard view_of_chat(src, r).0 is Some({ thread: Some(_), .. }) else { return false }
    chat_find_open(r)
    true
  })
  |> ignore
  // the rest of the chat's own keys that act beyond its list, as the old page's chat_keys took them and by what it
  // did: ⌘⇧E into the archive, ⌘⇧H its first agent's history beside it, ⌘. its agents at work stopped, ⌘⇧J its
  // services and jobs, ⌘⇧D its station's own display; what it cannot do now passes the key on
  let chat_view = fn() { view_of_chat(src, r).0 }
  v.on_action("chat.archive", fn(_) {
    guard chat_view() is Some(cv) && !cv.archived && !cv.offline else { return false }
    guard @sfbase.workspace_in_view(src).0 is Some(w) else { return false }
    archive_asked(src, w, r, cv, src.topic("chat", chat_params(r)).get().value)
    true
  })
  .on_action("chat.history", fn(_) {
    guard chat_view() is Some(cv) && cv.agents.length() > 0 else { return false }
    history_toggle(src, r, cv)
    true
  })
  .on_action("chat.stop", fn(_) {
    guard chat_view() is Some(cv) else { return false }
    stop_agents(src, r, cv)
    true
  })
  .on_action("chat.jobs", fn(_) {
    guard chat_view() is Some(_) else { return false }
    toggle_jobs_pop()
    true
  })
  .on_action("chat.screen", fn(_) {
    guard chat_view() is Some(cv) else { return false }
    chat_screen_first(r, cv.screens)
    true
  })
  |> ignore
  // (another chat's find let go as this one's page is made, as chat_page did as it was built: closed, what it looked
  // for forgotten, nothing left to go to there)
  v.reacts(fn() { () }, fn(_) {
    if find_chat() != "" && find_chat() != chat_key(r) {
      find_forget()
    }
  })
  chat_bar_handed_node(v, src, r)
  chat_drop_node(v, src, r, fn() { held.val }, shows)
}

///|
/// A row of the 文件 tab carried over chat `r`'s page made with its inside nodes (`v`; chat_body_nodes), as the old pane
/// had it (drop_hint, chat_drop): while it is over the page but the composer (`composer`'s node, which marks itself
/// then), frosted over all of it with 松开以添加到消息 under the row's mark, drawn only; let go on the page, into the
/// chat's draft (composer.add), named by its path or sent as a file as the chat takes what is dragged in. Where it was
/// let go is the page's as a drop from outside is (mbui's Tree::drop_at): the node drawn there, the page's node holding
/// it (what is drawn over the page there, a panel or another page, keeps it).
fn chat_drop_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  composer : () -> @view.View?,
  shows : () -> Bool,
) -> Unit {
  let draft = r.station + ":" + r.session
  v.box(fn(h) {
    h.over(Is(true)).presses(Is(false)) |> ignore
    h.show(
      fn() {
        dragged() is Some(_) &&
        v.pointed_in() &&
        !(match composer() {
          Some(n) => n.pointed_in()
          None => false
        })
      },
      fn(o) {
        o.grow(Is(1.0)).glass(By(fn() { Some(@sf.glass_floating()) })) |> ignore
        @sf.style_node(o, fn() { drop_hint_box })
        @sf.icon_node(
          o,
          "file",
          drop_folder * 2.0,
          By(fn() { @sf.theme().p.muted }),
          name_now=fn() { if dragged().map(fn(i) { i.dir }).unwrap_or(false) { "folder" } else { "file" } },
        )
        |> ignore
        o.box(fn(s) {
          s
          .words(By(fn() { @sf.t("web-main.composer.dropHere") }))
          .words_look(By(fn() { @ui.style_words(drop_hint_words) }))
          .ink(By(fn() { @sf.theme().p.text }))
          |> ignore
        })
        |> ignore
      },
      at_once=true,
    )
  })
  |> ignore
  // (let go off the tab: where, tab_take_drop's; on a node of the page's, its messages or its composer's old view)
  v.reacts(
    fn() { dragged() is Some(_) },
    fn(carried) {
      guard !carried && shows() && ftab.let_go is Some((item, x, y)) else { return }
      let on = match v.tree.drop_at(x, y) {
        Some(OnNode(id)) | Some(OnOld(id)) => v.tree.holds(v.id(), id)
        _ => false
      }
      guard on else { return }
      ftab.let_go = None
      writing_drop(src, writing(src, draft), r.station, [@sfpages.dropped_of(item)], @sfpages.drops_as_files(src, draft))
    },
    at_start=false,
  )
}

///|
/// Chat `r`'s composer in its messages' list's foot where its page is made with its inside nodes (sfbase's
/// chat_page_nodes: chat_page_made's `foot`), at its own height, never less than it takes opened with one line (its
/// being opened or let go moves none of the messages: composer_open_room, as chat_talk's room keeps), `apart` as
/// chat_composer's; nothing over it or let go into it yet (chat_talk's layers).
fn chat_composer_nodes(c : @ui.Ctx, src : Source, r : ChatRef, apart : Bool) -> Unit {
  guard @sfbase.workspace_in_view(src).0 is Some(w) else { return }
  let foot = c.box(style=@ui.style(w=Full, min_h=Fixed(@sfpages.composer_open_room(c, c.width))), fn() {
    c.spacer()
    @sfpages.chat_composer(c, src, w, r, view_of_chat(src, r).0, apart~)
  })
  @motion.scope(c, foot, bottom=true)
}
