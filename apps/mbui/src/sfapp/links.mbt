// still.fail's own links, opened in the app (ember apps/android shared/AppState.kt openLink, open, openItem;
// app/MainActivity.kt handle): the core says what a link opens (`link.parse`, its LinkTarget: client/core-ts
// src/shapes/schema.ts), which opens here as pages over the one in view; any other link goes to the caller's
// `or_else` (the system's browser for a link tapped in a message).
//
// - `item` (an item's link, a session's in Slack: /o/<workspace>/<station>/<session>, maybe `?service=<job>`): its
//   chat, with its web service over it; tapped in the chat it is about (or in one whose agent it is), only the
//   service over this chat; from outside the app (a notification, another app), the chat over its workspace's Home.
// - `chat` (a chat's reference, /w/<workspace>/s/<station>/chats/<key>): that chat over this one; another
//   workspace's, the workspace switched to and the chat over its Home.
// - `history` (`?history=<key>`, maybe with `entry`): that agent's execution history over the chat it is in, at the
//   entry; alone, over the chat the link is in.
// - `invite` (/invite#<token>): what the invitation leads to, in a sheet, before it is accepted (links_sheet.mbt).
// - `screen` (/w/…/s/…/screen/<id>): the station's screen in the viewer (open_screen).
//
// A link the system opened the app with (@host.system_channel `link`: one of the app's links tapped in another app,
// the manifest's App Links) opens as from outside, once signed in and the workspaces known.

///|
/// What a link opens, as the core's `link.parse` says (LinkTarget).
priv struct LinkTarget {
  opens : String
  token : String
  workspace : String
  station : String
  chat : String
  session : String
  service : String
  history : String
  entry : Int?
  screen : String
  login : String
}

///|
fn link_target(v : Json) -> LinkTarget {
  let j = Some(v)
  {
    opens: text(j, "opens"),
    token: text(j, "token"),
    workspace: text(j, "workspace"),
    station: text(j, "station"),
    chat: text(j, "chat"),
    session: text(j, "session"),
    service: text(j, "service"),
    history: text(j, "history"),
    entry: match field(j, "entry") {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    },
    screen: text(j, "screen"),
    login: text(j, "login"),
  }
}

///|
/// The workspace in view as last drawn: where a link's answer finds the app (it may have moved since it was asked).
let link_workspace : Ref[String] = Ref("")

///|
/// The core as last drawn, for a link tapped in a message (messages.mbt open_link).
let link_src : Ref[Source?] = Ref(None)

///|
/// The links the system opened the app with (@host.system_channel `link`), oldest first, not opened yet: opened once
/// signed in and the workspaces known (an invitation's shows its sheet signed out too).
let link_later : Array[String] = []

///|
/// Each frame signed in, the workspace `w` in view: the core and the workspace a link is opened against.
fn links_frame(src : Source, w : Workspace) -> Unit {
  link_workspace.val = w.id
  link_src.val = Some(src)
}

///|
/// The links the system opened the app with, opened as from outside (signed in: told once the frame that took them
/// has been built, links_frame's workspace in view).
fn links_given(src : Source) -> Unit {
  let given = link_later.copy()
  link_later.clear()
  for url in given {
    @host.log("link opens " + url)
    open_link_in(src, url, outside=true)
  }
}

///|
/// Each frame signed out: the links the system opened the app with; an invitation's shows its sheet (to sign in first,
/// as InviteLinkSheet does), any other waits until signed in.
fn signed_out_links(src : Source) -> Unit {
  let given = link_later.copy()
  link_later.clear()
  for url in given {
    @host.log("link opens " + url + " (signed out)")
    (src.call)("link.parse", { "url": Json::string(url) }, fn(r) {
      match r {
        Ok(Object(_) as t) if text(Some(t), "opens") == "invite" && text(Some(t), "token") != "" =>
          open_invite(text(Some(t), "token"))
        Ok(Object(_)) => link_later.push(url)
        _ => ()
      }
    })
  }
}

///|
/// Opens one of still.fail's links (AppState.openLink): what the core says it opens (`link.parse`), else `or_else`.
/// `outside`: a link from outside the app (a notification, another app), whose item opens over the list; `at`: the
/// message a notification is about, its chat opened there.
fn open_link_in(
  src : Source,
  url : String,
  outside? : Bool = false,
  at? : Double? = None,
  or_else? : () -> Unit = fn() {  },
) -> Unit {
  (src.call)("link.parse", { "url": Json::string(url) }, fn(r) {
    match r {
      Ok(Object(_) as t) => if !open_target(src, link_target(t), outside, at) { or_else() }
      Ok(_) => or_else()
      Err(e) => {
        @host.log("link.parse failed: " + text(Some(e), "message"))
        or_else()
      }
    }
  })
}

///|
/// What a link opens, opened (AppState.open): false when it opens nothing here.
fn open_target(src : Source, t : LinkTarget, outside : Bool, at : Double?) -> Bool {
  let ws = t.workspace
  let address = ws + "/" + t.station
  let current = link_workspace.val
  match t.opens {
    // `?history=…` alone, as a chat's notes link to it: in the chat it is in
    "history" =>
      match app.nav.top() {
        Chat(top) if t.history != "" => push_history(top, t.history, t.entry)
        _ => return false
      }
    // an invitation's link: what it leads to, in a sheet, before it is accepted
    "invite" => {
      if t.token == "" {
        return false
      }
      open_invite(t.token)
    }
    // a reference to another chat (web/src/chatRefs.ts), opened over this one
    "chat" => {
      if t.chat == "" {
        return false
      }
      let r = chat_ref(address, t.chat)
      match app.nav.top() {
        Chat(top) if top.station == address && top.session == t.chat => ()
        _ =>
          if ws != current {
            open_item(src, ws, address, t.chat, None, None)
          } else {
            close_overlays()
            app.nav.push(Chat(r))
          }
      }
      if t.history != "" {
        push_history(r, t.history, t.entry)
      }
    }
    "item" => {
      if t.session == "" {
        return false
      }
      let service = if t.service == "" { None } else { Some(t.service) }
      let top = app.nav.top()
      let here = match top {
        Chat(r) => r.station == address && (r.session == t.session || works_in(src, r, t.session))
        _ => false
      }
      if outside {
        open_item(src, ws, address, t.session, service, at)
      } else if here {
        match service {
          Some(job) => app.nav.push(Service(address, job))
          None => ()
        }
      } else if ws != current {
        open_item(src, ws, address, t.session, service, None)
      } else {
        close_overlays()
        app.nav.push(Chat(chat_ref(address, t.session)))
        match service {
          Some(job) => app.nav.push(Service(address, job))
          None => ()
        }
      }
      // here: over this chat, whose agent it is
      if t.history != "" {
        match (here, top) {
          (true, Chat(r)) => push_history(r, t.history, t.entry)
          _ => push_history(chat_ref(address, t.session), t.history, t.entry)
        }
      }
    }
    // one of a station's screens, as its agent asks a person to take over (docs/remote-screens.md): the viewer over
    // whatever page is open (back comes back to it)
    "screen" => {
      if t.screen == "" || t.station == "" {
        return false
      }
      open_screen(address, t.screen, None)
    }
    _ => return false
  }
  true
}

///|
/// A chat by its station's address and session, its title and station's name the chat's own once it shows.
fn chat_ref(station : String, session : String) -> ChatRef {
  { station, session, title: "", station_name: "" }
}

///|
/// Whether `session` is one of the agents of the chat `r` shows (AppState.chatAgents): a link to an agent's own item
/// tapped in the chat it works in.
fn works_in(src : Source, r : ChatRef, session : String) -> Bool {
  agent_json((src.topic)("chat", chat_params(r)).value, session) is Some(_)
}

///|
/// An agent's execution history, over the chat it is in (at `entry`, else its newest): not twice over itself.
fn push_history(r : ChatRef, key : String, entry : Int?) -> Unit {
  let page = History(r, key, entry)
  if app.nav.top() != page {
    app.nav.push(page)
  }
}

///|
/// The sheets and the menus over the pages closed, as a page opens from a link (AppState: sheet, menu null).
fn close_overlays() -> Unit {
  lower_sheet()
  app.menu = false
  match dui.sheet {
    Some(s) => dui.leaving = Some(s)
    None => ()
  }
  dui.sheet = None
}

///|
/// The workspace `ws` in view from now on (AppState.pickWorkspace): the prefs' `workspace`.
fn pick_workspace(src : Source, ws : String) -> Unit {
  if ws == "" || ws == link_workspace.val {
    return
  }
  app.picked = ws
  link_workspace.val = ws
  (src.call)("prefs.set", { "workspace": Json::string(ws) }, fn(_) {  })
}

///|
/// An item's chat from outside (AppState.openItem): its workspace in view, nothing over Home but the chat (and its
/// web service over it), opened at `at` (the message a notification is about).
fn open_item(
  src : Source,
  ws : String,
  station : String,
  session : String,
  service : String?,
  at : Double?,
) -> Unit {
  pick_workspace(src, ws)
  home()
  if app.nav.top() != Home {
    app.nav.replace(Home)
  }
  let r = chat_ref(station, session)
  match at {
    Some(seq) => {
      // (what the end-to-end flows of a notification tapped look for: e2e/flows/40-notice-wait.check)
      @host.log("notice opens \{station}|\{session} at \{seq.to_int()}")
      go_to(r, seq)
    }
    None => ()
  }
  app.nav.push(Chat(r))
  match service {
    Some(job) => app.nav.push(Service(station, job))
    None => ()
  }
}

///|
/// One of a station's screens in the viewer (AppState.openScreen; remote/ScreenActivity.kt): `title`, the row's,
/// until the core says one (screen_view.mbt).
fn open_screen(station : String, screen : String, title : String?) -> Unit {
  app.nav.push(Screen({ station, screen, title: title.unwrap_or("") }))
}

///|
fn links_reset() -> Unit {
  link_workspace.val = ""
  link_src.val = None
  link_later.clear()
  invite_reset()
}
