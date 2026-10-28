// What can be done with a chat, one list wherever it is offered (pengxiao, 2026-10-28: a row's menu and the chat's info
// had each their own, the same chat pinned only from one and shared only from the other): its row's menu (chat_row.mbt
// row_menu), its info beside the chat's bar (sfdesk chat_info) and its sheet (sfapp chat_info_body). Each shows them
// its own way, the groups apart (a menu's rule, the info's line, the sheet's cards); what a place has besides (the
// chat's files, its letters) is that place's.

///|
/// A chat as what can be done with it needs it: where it is, its thread (none: an agent with no chat yet), its name,
/// whether pinned (None: a station from before pins) and kept, its agents' sessions, whether it can be relayed and
/// archived now, where it is in Slack or Feishu, its sharing with other workspaces (shown: where it is shared, and its
/// sharing's session; may: the viewer may change it) and whether they may make a public picture of it.
pub(all) struct ChatActs {
  station : String
  station_name : String
  session : String
  thread : Double?
  title : String
  pinned : Bool?
  kept : Bool
  agents : Array[String]
  relayable : Bool
  archivable : Bool
  slack : String
  slack_app : String
  feishu : String
  xshare : Bool
  xshare_may : Bool
  xshare_text : String
  xshare_session : String
  publish : Bool
}

///|
/// One of them: its key (what a test or a place finds it by), its icon and words, what it says at its end (where it is
/// shared), whether it is under way, whether it is the viewer's to do (shown all the same: where a chat is shared, to
/// one who may not change it), what doing it does.
pub(all) struct ChatAction {
  key : String
  icon : String
  label : String
  end : String
  busy : Bool
  may : Bool
  run : () -> Unit
}

///|
/// A row's (chat_row.mbt): what its list knows of it.
pub fn chat_acts_of_row(item : ChatItem) -> ChatActs {
  {
    station: item.station,
    station_name: item.station_name,
    session: item.session,
    thread: item.thread,
    title: item.title,
    pinned: item.pinned,
    kept: item.kept,
    agents: item.agents.map(fn(a) { a.key }).filter(fn(k) { k != "" }),
    relayable: item.thread is Some(_) && item.agents.length() > 0,
    archivable: true,
    slack: "",
    slack_app: "",
    feishu: "",
    xshare: item.xshare_may,
    xshare_may: item.xshare_may,
    xshare_text: "",
    xshare_session: "",
    publish: item.publish_may,
  }
}

///|
/// An open chat's (its info, its sheet): what its page knows of it, `v` its view (None: not read yet) and `chat` the
/// core's `chat` as it is. Archived or its station away, it is only read: nothing that changes it.
pub fn chat_acts_of_chat(r : ChatRef, v : ChatView?, chat : Json?) -> ChatActs {
  let (archived, offline, agents) = match v {
    Some(view) => (view.archived, view.offline, view.agents.map(fn(a) { a.key }).filter(fn(k) { k != "" }))
    None => (true, false, [])
  }
  let open = !archived && !offline
  let thread = opt_number(field(chat, "thread"), "id")
  let share = field(chat, "xshare")
  let publish = field(chat, "publish")
  {
    station: r.station,
    station_name: r.station_name,
    session: r.session,
    thread,
    title: match v {
      Some(view) => view.title
      None => r.title
    },
    pinned: match field(chat, "pinned") {
      Some(True) if open => Some(true)
      Some(False) if open => Some(false)
      _ => None
    },
    kept: flag(chat, "kept"),
    agents,
    relayable: open && thread is Some(_) && agents.length() > 0,
    archivable: open,
    slack: text(chat, "slackUrl"),
    slack_app: text(chat, "slackApp"),
    feishu: text(chat, "feishuUrl"),
    xshare: thread is Some(_) && share is Some(Object(_)),
    xshare_may: flag(share, "may"),
    xshare_text: text(share, "text"),
    xshare_session: text(share, "session"),
    publish: thread is Some(_) && publish is Some(Object(_)) && flag(publish, "may"),
  }
}

///|
/// What can be done with chat `a`, in its groups: pin, rename, keep; its link, its sessions' files; relay it, open it
/// in Slack or Feishu; share it with other workspaces, as a picture; archive it. Each where the chat has it: kept only
/// for a chat of its own not pinned (a pin keeps it out of the archive already). `rename` and `archive` are the place's
/// own (a row renamed in place, a chat archived and left); `from` what a panel opened from it opens from.
pub fn chat_actions(
  src : Source,
  a : ChatActs,
  rename~ : () -> Unit,
  archive~ : () -> Unit,
  from? : @sf.Anchor = Unanchored,
) -> Array[Array[ChatAction]] {
  let r : ChatRef = { station: a.station, session: a.session, title: a.title, station_name: a.station_name }
  let mine : Array[ChatAction] = []
  match a.pinned {
    Some(p) => {
      let key = "pin/" + a.station + "/" + a.session
      mine.push(
        { ..action_of("pin", "pin", @sf.t(if p { "web-main.chat.unpin" } else { "web-main.chat.pin" }), busy=doing(key)), run: fn() {
          act(
            src,
            @sf.t(if p { "android-chat.unpin.verb" } else { "android-chat.pin.verb" }),
            key,
            "chat.pin",
            { "station": Json::string(a.station), "session": Json::string(a.session), "pinned": Json::boolean(!p) },
          )
        } },
      )
    }
    None => ()
  }
  if a.archivable {
    mine.push({ ..action_of("rename", "edit", @sf.t("web-main.chat.rename")), run: rename })
  }
  match a.thread {
    Some(th) if a.archivable && a.pinned != Some(true) =>
      mine.push(
        { ..action_of("keep", "shield-check", @sf.t(if a.kept { "web-main.chat.unkeep" } else { "web-main.chat.keep" })), run: fn() {
          act(
            src,
            @sf.t(if a.kept { "web-main.chat.unkeep.what" } else { "web-main.chat.keep.what" }),
            "",
            "chat.keep",
            { "station": Json::string(a.station), "thread": Json::number(th), "kept": Json::boolean(!a.kept) },
            done=@sf.t(if a.kept { "web-main.chat.unkeep.done" } else { "web-main.chat.keep.done" }),
          )
        } },
      )
    _ => ()
  }
  let copies : Array[ChatAction] = []
  let link = @sfbase.chat_link(a.station, a.session)
  if link != "" {
    copies.push({ ..action_of("link", "copy", @sf.t("web-main.chat.copyLink")), run: fn() {
      @sfbase.copy_chat_link(@ui.current(), a.title, link)
    } })
  }
  copies.push(
    { ..action_of("transcript", "file", @sf.t("web-main.chat.copyTranscript")), run: fn() {
      let keys = if a.agents.is_empty() { [a.session] } else { a.agents }
      // (asked of its station once the frame it was chosen in is built)
      let c = @ui.current()
      c.after_build("chat/transcripts", fn() { copy_transcripts(c, src, a.station, keys) })
    } },
  )
  let elsewhere : Array[ChatAction] = []
  // relayed to a channel (docs/relay.md): a chat with an agent to go on there
  match a.thread {
    Some(th) if a.relayable =>
      elsewhere.push({ ..action_of("relay", "arrow-up-right", @sf.t("web-main.relay.action")), run: fn() {
        open_relay(src, r, th, from~)
      } })
    _ => ()
  }
  if a.slack != "" {
    elsewhere.push(
      { ..action_of("slack", "external", @sf.t("web-pages.chat.openInSlack")), run: fn() {
        if !@sfbase.open_slack(a.slack_app, a.slack) {
          @sfbase.toast_later(@sf.t("android-chat.link.failed"))
        }
      } },
    )
  }
  if a.feishu != "" {
    elsewhere.push(
      { ..action_of("feishu", "external", @sf.t("web-pages.chat.openInFeishu")), run: fn() {
        if !@ui.open_url(a.feishu) {
          @sfbase.toast_later(@sf.t("android-chat.link.failed"))
        }
      } },
    )
  }
  let shares : Array[ChatAction] = []
  match a.thread {
    Some(th) => {
      if a.xshare {
        shares.push(
          {
            ..action_of(
              "xshare",
              "users",
              @sf.t("web-pages.chat.xshare"),
              end=a.xshare_text,
              busy=a.xshare_session != "" && doing(xshare_key(a.station, a.xshare_session)),
              may=a.xshare_may,
            ),
            run: fn() { open_xshare(src, r, Some(th), from~) },
          },
        )
      }
      if a.publish {
        shares.push({ ..action_of("publish", "photo", @sf.t("web-pages.chat.shareImage")), run: fn() {
          open_publish(src, r, th)
        } })
      }
    }
    None => ()
  }
  let last : Array[ChatAction] = []
  if a.archivable {
    last.push({ ..action_of("archive", "archive", @sf.t("web-main.chat.archive")), run: archive })
  }
  [mine, copies, elsewhere, shares, last].filter(fn(g) { !g.is_empty() })
}

///|
/// The groups as a menu's items, a rule between each two (@sf.menu).
pub fn chat_menu_items(groups : Array[Array[ChatAction]]) -> Array[@sf.MenuItem?] {
  let items : Array[@sf.MenuItem?] = []
  for i, g in groups {
    if i > 0 {
      items.push(None)
    }
    for x in g {
      items.push(Some(@sf.menu_item_of(x.label, icon=x.icon, disabled=x.busy || !x.may, x.run)))
    }
  }
  items
}

///|
/// One of them, what doing it does given beside it (`{ ..action_of(…), run }`: a callback handed to a function would
/// be taken for one run as the menu builds, detlint's build-effect).
fn action_of(key : String, icon : String, label : String, end? : String = "", busy? : Bool = false, may? : Bool = true) -> ChatAction {
  { key, icon, label, end, busy, may, run: fn() {  } }
}

///|
/// A chat renamed `title` (`chat.rename`): nothing when it is no different.
pub fn rename_chat(src : Source, a : ChatActs, title : String) -> Unit {
  let words = title.trim(chars=" \n\t").to_string()
  if words == "" || words == a.title {
    return
  }
  let p : Map[String, Json] = {
    "station": Json::string(a.station),
    "session": Json::string(a.session),
    "title": Json::string(words),
  }
  match a.thread {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  act(src, @sf.t("android-chat.rename.verb"), "", "chat.rename", Json::object(p))
}

///|
/// Its new name asked over the page (an open chat's: its row is not where it is), from `from`.
pub fn ask_rename(src : Source, a : ChatActs, from? : @sf.Anchor = Unanchored) -> Unit {
  @sf.ask(
    @sf.t("android-chat.rename.title"),
    @sf.t("common.save"),
    fn(title) { rename_chat(src, a, title) },
    value=a.title,
    placeholder=@sf.t("android-chat.rename.field"),
    hint=@sf.t("android-chat.rename.note"),
    from~,
  )
}
