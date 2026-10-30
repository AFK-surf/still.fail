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
// - `invite` (/invite#<token>): what the invitation leads to, before it is accepted, as the frame shows it.
// - `screen` (/w/…/s/…/screen/<id>): the station's screen in the viewer (open_screen).
//
// A link the system opened the app with (@hostapi.system_channel `link`: one of the app's links tapped in another app,
// the manifest's App Links) opens as from outside, once signed in and the workspaces known. What is over the pages,
// the way home and how an invitation shows are the frame's (shell.mbt).

///|
/// What a link opens, as the core's `link.parse` says (LinkTarget).
pub(all) struct LinkTarget {
  opens : String
  token : String
  workspace : String
  station : String
  chat : String
  session : String
  service : String
  history : String
  entry : Int?
  message : Double?
  screen : String
  login : String
}

///|
pub fn link_target(v : Json) -> LinkTarget {
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
    message: match field(j, "message") {
      Some(Number(n, ..)) if n > 0.0 => Some(n)
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
pub let link_src : Ref[Source?] = Ref(None)

///|
/// The links the system opened the app with (@hostapi.system_channel `link`), oldest first, not opened yet: opened once
/// signed in and the workspaces known (an invitation's shows its sheet signed out too).
pub let link_later : Array[String] = []

///|
/// Each frame signed in, the workspace `w` in view: the core and the workspace a link is opened against.
pub fn links_frame(src : Source, w : Workspace) -> Unit {
  link_workspace.val = w.id
  link_src.val = Some(src)
}

///|
/// The links the system opened the app with, opened as from outside (signed in: told once the frame that took them
/// has been built, links_frame's workspace in view).
pub fn links_given(src : Source) -> Unit {
  let given = link_later.copy()
  link_later.clear()
  for url in given {
    @hostapi.log("link opens " + url)
    open_link_in(src, url, outside=true)
  }
}

///|
/// Each frame signed out: the links the system opened the app with; an invitation's shows its sheet (to sign in first,
/// as InviteLinkSheet does), any other waits until signed in.
pub fn signed_out_links(src : Source) -> Unit {
  let given = link_later.copy()
  link_later.clear()
  for url in given {
    @hostapi.log("link opens " + url + " (signed out)")
    (src.call)("link.parse", { "url": Json::string(url) }, fn(r) {
      match r {
        Ok(Object(_) as t) if text(Some(t), "opens") == "invite" && text(Some(t), "token") != "" =>
          (shell.val.open_invite)(text(Some(t), "token"))
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
pub fn open_link_in(
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
        @hostapi.log("link.parse failed: " + text(Some(e), "message"))
        or_else()
      }
    }
  })
}

///|
/// What a link opens, opened (AppState.open): false when it opens nothing here.
pub fn open_target(src : Source, t : LinkTarget, outside : Bool, at : Double?) -> Bool {
  let at = match at { Some(_) => at; None => t.message }
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
      (shell.val.open_invite)(t.token)
    }
    // a reference to another chat (web/src/chatRefs.ts), opened over this one
    "chat" => {
      if t.chat == "" {
        return false
      }
      let r = chat_ref(address, t.chat)
      match at { Some(seq) => go_to(r, seq); None => () }
      match app.nav.top() {
        Chat(top) if top.station == address && top.session == t.chat => ()
        _ =>
          if ws != current {
            open_item(src, ws, address, t.chat, None, None)
          } else {
            (shell.val.close_overlays)()
            open_page_over(Chat(r))
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
      match at { Some(seq) => go_to(chat_ref(address, t.session), seq); None => () }
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
          Some(job) => open_page(Service(address, job))
          None => ()
        }
      } else if ws != current {
        open_item(src, ws, address, t.session, service, None)
      } else {
        (shell.val.close_overlays)()
        open_page_over(Chat(chat_ref(address, t.session)))
        match service {
          Some(job) => open_page(Service(address, job))
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
    // a station's 共享调试, as its agent asks for it (adb_devices): the page, sharing only once its person taps; a login
    // an agent started on a station (docs/remote-login.md): its card on the station's page, marked, brought into view
    "adbShare" | "login" => {
      if t.station == "" || (t.opens == "login" && t.login == "") {
        return false
      }
      let route : @settings.Route = if t.opens == "login" { Station(address) } else { AdbShare(address) }
      if t.opens == "adbShare" && app.nav.top() == Setting(route) {
        return true
      }
      let away = ws != current
      if away {
        pick_workspace(src, ws)
      }
      (shell.val.close_overlays)()
      if outside || away {
        (shell.val.home)()
        if app.nav.top() != Home {
          app.nav.replace(Home)
        }
      }
      if t.opens == "login" {
        @settings.mark_login(address, t.login)
      }
      open_page(Setting(route))
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
pub fn chat_ref(station : String, session : String) -> ChatRef {
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
  let page : Page = History(r, key, entry)
  if app.nav.top() != page {
    open_page(page)
  }
}

///|
/// The workspace `ws` in view from now on (AppState.pickWorkspace): the prefs' `workspace`.
pub fn pick_workspace(src : Source, ws : String) -> Unit {
  if ws == "" || ws == link_workspace.val {
    return
  }
  history_push()
  app.picked = ws
  link_workspace.val = ws
  (src.call)("prefs.set", { "workspace": Json::string(ws) }, fn(_) {  })
}

///|
/// An item's chat from outside (AppState.openItem): its workspace in view, nothing over Home but the chat (and its
/// web service over it), opened at `at` (the message a notification is about).
pub fn open_item(
  src : Source,
  ws : String,
  station : String,
  session : String,
  service : String?,
  at : Double?,
) -> Unit {
  history_push()
  pick_workspace(src, ws)
  (shell.val.home)()
  if app.nav.top() != Home {
    app.nav.replace(Home)
  }
  let r = chat_ref(station, session)
  match at {
    Some(seq) => {
      // (what the end-to-end flows of a notification tapped look for: e2e/flows/40-notice-wait.check)
      @hostapi.log("notice opens \{station}|\{session} at \{seq.to_int()}")
      go_to(r, seq)
    }
    None => ()
  }
  open_page(Chat(r))
  match service {
    Some(job) => open_page(Service(station, job))
    None => ()
  }
}

///|
/// One of a station's screens in the viewer (AppState.openScreen; remote/ScreenActivity.kt): `title`, the row's,
/// until the core says one (screen_view.mbt).
pub fn open_screen(station : String, screen : String, title : String?) -> Unit {
  open_page(Screen({ station, screen, title: title.unwrap_or(""), until_gone: false }))
}

///|
pub fn links_reset() -> Unit {
  link_workspace.val = ""
  link_src.val = None
  link_later.clear()
}

///|
/// A Slack thread opened in Slack: by its link into Slack's app (`app`, slack://) where the system says whether
/// anything took it (macOS: no browser's page first), else by its web link (`web`). Elsewhere the web link alone:
/// iOS's and Android's hosts answer before the system knows, Windows' and Linux's open web links only, and a
/// browser's tab would ask about a slack:// link. False when nothing took it.
pub fn open_slack(app : String, web : String) -> Bool {
  if app != "" && @ui.platform() == 0 && @ui.open_url(app) {
    return true
  }
  web != "" && @ui.open_url(web)
}

///|
/// A link tapped in a message (App.kt's UriHandler, AppState.openLink): one of still.fail's opens here as the core
/// says (open_link_in); any other is handed to the system (its browser, or the app that takes it: mbui's open_url), said
/// when nothing took it.
pub fn open_link(href : String) -> Unit {
  let elsewhere = fn() { if !@ui.open_url(href) { toast_later(@sf.t("android-misc.link.cantOpen")) } }
  match link_src.val {
    Some(src) => open_link_in(src, href, or_else=elsewhere)
    None => elsewhere()
  }
}


