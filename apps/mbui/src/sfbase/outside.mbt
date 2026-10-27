// What a draft refers to, shared before it goes (web OutsideShare.tsx; docs/chat-share.md), for every composer: words
// with a reference to another chat in them (a mark, as the core read them: refs.mbt) are asked of the core before
// they go: the chats of the viewer's other workspaces they name that are not shared with this workspace yet, and
// which of them the viewer may share (`chat.outsideRefs`). With none (or a core that cannot say) they go at once; else
// a page asks (the phone's sheet, the desktop's dialog), and its yes shares those the viewer may with this workspace
// (the core's `chat.outsideShare`), then sends; with none they may share, the yes sends as it is. A share failing is
// said, nothing sent. A second send while the core is asked does nothing.

///|
/// A chat of another workspace that what is sent refers to (OutsideShare.tsx Outside): its station and id, its title,
/// its workspace and that's name, whether the viewer may share it (its starter, or an owner or admin there).
pub(all) struct OutsideRef {
  station : String
  id : String
  title : String
  workspace : String
  workspace_name : String
  may : Bool
}

///|
/// A draft's send waiting on what it refers to: asked of the core (`checking`), asked of the viewer (`open`, its
/// chats, sharing them: `busy`, why that failed: `error`), or to go with the composer's next build (`go`: the core said
/// nothing is outside, or it was shared).
pub(all) struct OutsideAsk {
  /// the draft's key, the station it is written on, the words it sends
  key : String
  station : String
  words : String
  /// sends it (the composer's send, as it was pressed)
  send : () -> Unit
  chats : @sf.LiveArray[OutsideRef]
  checking : @signals.Signal[Bool]
  go : @signals.Signal[Bool]
  open : @signals.Signal[Bool]
  busy : @signals.Signal[Bool]
  error : @signals.Signal[String]
}

///|
pub let outside_ask : Ref[OutsideAsk?] = { val: None }

///|
fn outside_reset() -> Unit {
  outside_ask.val = None
}

///|
/// Sends what draft `key` holds (`words`, written on `station`) by `send`, once this workspace's agents can read what
/// it refers to: no mark in it (as the core read its field: refs.mbt), at once; else the core is asked first. Nothing
/// is asked on a read-only run, whose send says it sends nothing.
pub fn send_sharing(src : Source, key : String, station : String, words : String, send : () -> Unit) -> Unit {
  if refs_marked(key) is Some(false) || src.read_only || !station.contains("/") {
    send()
    return
  }
  match outside_ask.val {
    // asked already, or asking: a second send does nothing meanwhile
    Some(s) if s.key == key && (s.checking.get() || s.open.get() || s.go.get()) => return
    _ => ()
  }
  let s : OutsideAsk = {
    key,
    station,
    words,
    send,
    chats: @sf.LiveArray::from([]),
    checking: @signals.signal(true),
    go: @signals.signal(false),
    open: @signals.signal(false),
    busy: @signals.signal(false),
    error: @signals.signal(""),
  }
  outside_ask.val = Some(s)
  (src.call)("chat.outsideRefs", { "station": Json::string(station), "text": Json::string(words) }, fn(res) {
    s.checking.set(false)
    // a core that cannot say (one before sharing) leaves it as before: sent as it is
    let chats = match res {
      Ok(v) => outside_refs_of(v)
      Err(_) => []
    }
    if chats.length() == 0 {
      s.go.set(true)
    } else {
      s.chats.replace(chats)
      s.open.set(true)
    }
  })
}

///|
/// The chats the core's `chat.outsideRefs` answers.
fn outside_refs_of(v : Json) -> Array[OutsideRef] {
  items(Some(v), "chats").map(fn(c) {
    let s = Some(c)
    {
      station: text(s, "station"),
      id: text(s, "id"),
      title: text(s, "title"),
      workspace: text(s, "workspace"),
      workspace_name: text(s, "workspaceName"),
      may: flag(s, "may"),
    }
  })
}

///|
/// Each build of draft `key`'s composer: what was cleared to go goes (said by the core's answer or a share's, which
/// bring this frame), as it would have when pressed.
pub fn sharing_go(key : String) -> Unit {
  match outside_ask.val {
    Some(s) if s.key == key && s.go.get() => {
      s.go.set(false)
      // (one asked about lets go as its page's asking has gone: outside_gone)
      if s.chats.is_empty() {
        outside_ask.val = None
      }
      (s.send)()
    }
    _ => ()
  }
}

///|
/// What draft `key`'s send is asking the viewer, while it is (or while its asking is still shown going: `outside_gone`
/// once it has).
pub fn outside_asking(key : String) -> OutsideAsk? {
  match outside_ask.val {
    Some(s) if s.key == key && (s.open.get() || !s.chats.is_empty()) => Some(s)
    _ => None
  }
}

///|
/// Whether the viewer may share any of what it asks about (its yes shares them; else it sends as it is).
pub fn outside_sharable(s : OutsideAsk) -> Bool {
  s.chats.iter().any(fn(x) { x.may })
}

///|
/// The asking's yes (分享并发送, or 仍然发送 with none to share): those the viewer may share shared with this workspace
/// by the core (`chat.outsideShare`), then it goes with the composer's next build; failing, why is said and nothing
/// goes. With none to share, it goes as it is.
pub fn outside_yes(src : Source, s : OutsideAsk) -> Unit {
  if s.busy.get() {
    return
  }
  if !outside_sharable(s) {
    s.open.set(false)
    s.go.set(true)
    return
  }
  s.busy.set(true)
  s.error.set("")
  (src.call)("chat.outsideShare", { "station": Json::string(s.station), "text": Json::string(s.words) }, fn(res) {
    s.busy.set(false)
    match res {
      Ok(_) => {
        s.open.set(false)
        s.go.set(true)
      }
      Err(e) => s.error.set(@sf.t("web-main.outside.failed", args=[("error", error_words(e))]))
    }
  })
}

///|
/// The asking's no (取消, or closed): nothing goes, the words as they were.
pub fn outside_no(s : OutsideAsk) -> Unit {
  s.open.set(false)
}

///|
/// Its page's asking has gone (closed and shown no more): let go of it.
pub fn outside_gone(s : OutsideAsk) -> Unit {
  match outside_ask.val {
    Some(now) if physical_equal(now, s) && !s.open.get() && !s.go.get() => outside_ask.val = None
    _ => ()
  }
}
