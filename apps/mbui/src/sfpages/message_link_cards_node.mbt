// The card each link a message's words draw has (peeks.mbt's link_peek, link_peeks), for the library's link cards
// (@sf.link_cards_node: opened while a mouse rests on that link, beside it): a file's its message's agent names
// (file_card_node), a chat's (chat_card_node: as the message's `chats` say it, one archived), a web link's (link_card_node:
// a page's tile, a pull request's or an issue's card); none from a chat of no station, none for a path with no agent to
// read it in. What each reads is read as peek_read reads it: from the moment the pointer comes onto its link, while
// that or its card is there, let go of once neither, so that it is read again the next time (a file's read again each
// time the pointer comes onto it: file_peek's refresh); the pictures a web link's or a file's card names asked as it
// is read, so that they are mostly here as it opens.

///|
/// The card each link of message `m` has in a chat of station `station`, its agent `agent` ("" none: a person's) whose
/// working directory its paths are read in (link_peek's choice, by the link as its row is made).
fn message_link_card(src : Source, station : String, agent : String, m : () -> Message) -> (@sf.LinkOf) -> @sf.LinkCard? {
  fn(l) {
    guard station != "" else { return None }
    let href = l.href
    match @sf.path_of_link(href) {
      Some((path, line)) => if agent == "" { None } else { Some(file_link_card(l, src, station, agent, path, line)) }
      None => {
        let now = @signals.untracked(m)
        // (a chat's, as the core says of the message's links: its `to`)
        let to = link_to_in(now)(href)
        let linked = now.chats.iter().find_first(fn(c) { c.href == href })
        if linked is Some(_) || to.chat {
          Some(chat_link_card(l, src, station, href, linked))
        } else if href.has_prefix("https://") || href.has_prefix("http://") {
          Some(web_link_card(l, src, station, href, to.peek))
        } else {
          None
        }
      }
    }
  }
}

///|
/// What link `l`'s card shows is read for `scope` (`name` with `params`) as peek_read reads it: from the moment the
/// pointer comes onto it (`warm` then given what it has read, as that changes), let go of once neither it nor its card
/// is there, and as its link goes.
fn link_card_reads(
  l : @sf.LinkOf,
  src : Source,
  scope : String,
  name : String,
  params : Map[String, Json],
  came? : () -> Unit = fn() {  },
  warm? : (Json?) -> Unit = fn(_) {  },
) -> Unit {
  let held : @signals.Signal[@signals.Computed[@sfbase.TopicState]?] = @signals.signal(None, same=fn(a, b) {
    match (a, b) {
      (None, None) => true
      (Some(x), Some(y)) => physical_equal(x, y)
      _ => false
    }
  })
  l.node.reacts(l.pointed, at_start=false, fn(on) {
    if on {
      came()
      held.set(Some(@sfbase.hold(src, scope, name, params)))
    }
  })
  l.node.reacts(
    fn() {
      match held.get() {
        Some(read) => read.get().value
        None => None
      }
    },
    warm,
  )
  l.node.reacts(l.reading, at_start=false, fn(on) {
    if !on {
      held.set(None)
      @sfbase.let_go(src, scope)
    }
  })
  l.node.owns(fn() { @sfbase.let_go(src, scope) }) |> ignore
}

///|
/// A web link's card (web_peek's) of link `l` to `href` as station `station` reads it; `peek` the kind the core says it
/// is (pull, issue: a card 320 wide, its bones that one's while it is read; else a page's tile).
fn web_link_card(l : @sf.LinkOf, src : Source, station : String, href : String, peek : String) -> @sf.LinkCard {
  peek_cards.val = peek_cards.val + 1
  let scope = "link-peek-node/" + peek_cards.val.to_string()
  let params = link_params(station, href)
  link_card_reads(l, src, scope, "linkPreview", params, warm=fn(v) { @sfbase.link_pictures_ask(src, station, href, v) })
  {
    tile: peek == "",
    body: fn(b) {
      let read = @sfbase.hold(src, scope, "linkPreview", params)
      link_card_node(b, src, station, read, fn() { href }, l.words, fn() { peek }, fn(at) {
        link_copy_node(at, fn() { href })
      })
    },
  }
}

///|
/// A file's card (file_peek's) of link `l` to `path` (at `line`) of session `agent` on station `station`: read again
/// each time the pointer comes onto it (the file may have been written since).
fn file_link_card(
  l : @sf.LinkOf,
  src : Source,
  station : String,
  agent : String,
  path : String,
  line : Int?,
) -> @sf.LinkCard {
  peek_cards.val = peek_cards.val + 1
  let scope = "file-peek-node/" + peek_cards.val.to_string()
  let params = file_peek_params(station, agent, path, line)
  link_card_reads(l, src, scope, "filePeek", params, came=fn() { (src.refresh)("filePeek", params) }, warm=fn(v) {
    if v is Some(_) {
      @sfbase.file_peek_picture_ask(src, station, agent, path, line, v)
    }
  })
  {
    tile: false,
    body: fn(b) { file_card_node(b, src, station, agent, path, line, @sfbase.hold(src, scope, "filePeek", params)) },
  }
}

///|
/// A chat's card (chat_peek's) of link `l` to `href`, read in a chat of station `here` (`linked`, the chat as its
/// message says it): the chat it names asked of the core as the pointer comes onto it, and its whole row (when it was
/// last active) held from then where the list has it and not whole.
fn chat_link_card(l : @sf.LinkOf, src : Source, here : String, href : String, linked : LinkedChat?) -> @sf.LinkCard {
  peek_cards.val = peek_cards.val + 1
  let scope = "chat-peek-node/" + peek_cards.val.to_string()
  l.node.reacts(l.pointed, at_start=false, fn(on) { if on { chat_named(src, here, href) |> ignore } })
  // (its whole row's (its station, its session) while the pointer is on it and the list has it, not whole)
  l.node.reacts(
    fn() {
      guard (l.pointed)() else { return None }
      match chats_named.get(here + "\u{1}" + href) {
        Some(Chat(station, key, _, _)) =>
          match peek_listed(src, here, station, key) {
            Some(i) if !@sfbase.whole_already(src, i) => Some((i.station, i.session))
            _ => None
          }
        _ => None
      }
    },
    fn(p) {
      match p {
        Some((station, session)) => @sfbase.hold(src, scope, "chatRow", @sfbase.whole_params(station, session)) |> ignore
        None => ()
      }
    },
  )
  l.node.reacts(l.reading, at_start=false, fn(on) { if !on { @sfbase.let_go(src, scope) } })
  l.node.owns(fn() { @sfbase.let_go(src, scope) }) |> ignore
  { tile: false, body: fn(b) { chat_card_node(b, src, scope, here, fn() { href }, fn() { linked }) } }
}
