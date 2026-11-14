// What a chat's card holds (peeks.mbt's chat_card) as nodes of the window's tree, made once: what is over it, opened
// and shut as the pointer rests on the link to the chat, is the hover card's (sf's), not this; this is what is in it,
// as the core reads the link (`link.parse`, asked once each: chats_named) and the workspace's list says the chat, as
// those change: the chat's mark, title and when it was last active; where it is when another station, and that the
// link is its agent's execution history; the one message the link names (`messagePeek`), else where it stands or the
// last thing said in it. One archived as its message says; one gone; its bones while the link or the list is read.

///|
/// What a chat's card shows (chat_card's): an archived one as its message says it; its bones while the link or the
/// list is read; that it is gone; the chat found.
#derive(Eq)
priv enum ChatShows {
  Archived
  Sample
  Gone
  Found
}

///|
/// What a chat's card holds (chat_card's) in `parent`: the chat `href` names (as it is now), read in a chat of station
/// `here` (chat_named: asked once each, as it is made or its link changes, never as it is drawn); `linked`, the chat as
/// its message says it. The message it names read for `scope` (let go of with it by whoever holds the card).
// a hover card as nodes: held by its tests, not used by the app yet
#warnings("-unused_value")
fn chat_card_node(
  parent : @view.View,
  src : Source,
  scope : String,
  here : String,
  href : () -> String,
  linked : () -> LinkedChat?,
) -> Unit {
  // (asked once the link is known, as it changes: chat_named asks the core only for one it has not)
  parent.reacts(href, fn(h) { chat_named(src, here, h) |> ignore })
  let named = fn() { chats_named.get(here + "\u{1}" + href()).unwrap_or(Asking) }
  // (the chat found in the workspace's list, as its whole row says it, where the link names one: None while the list
  // or its whole row is read, Some(None) not in the list. When it was last active is its whole row's (`chatRow`, held
  // while this reads it), the list's row being made without it: chat_card's)
  let found = fn() -> (ChatItem, Bool, Double?)?? {
    match named() {
      Chat(station, key, history, seq) => {
        guard @sfbase.chats_of(src, @sfbase.workspace_of(here), "all").0 is Some(_) else { return None }
        match peek_listed(src, here, station, key) {
          None => Some(None)
          Some(listed) => @sfbase.whole_row(src, listed).map(fn(i) { Some((i, history, seq)) })
        }
      }
      _ => None
    }
  }
  let shows = fn() {
    match linked() {
      Some(l) if l.archived => Archived
      _ =>
        match named() {
          Asking => Sample
          NoChat => Gone
          Chat(_) =>
            match found() {
              None => Sample
              Some(None) => Gone
              Some(Some(_)) => Found
            }
        }
    }
  }
  parent.pick(shows, fn(b, s) {
    @sf.style_node(b, fn() { peek_card_part })
    match s {
      Archived => {
        let l = fn() {
          linked().unwrap_or({ href: "", title: "", archived: true, note: "", thread: None })
        }
        b.box(fn(rich) {
          @sf.style_node(rich, fn() { peek_rich })
          rich.box(fn(t) {
            @sf.style_node(t, fn() { peek_chat_title })
            peek_title_node(t, fn() { l().title })
          })
          |> ignore
          rich.show(fn() { l().note != "" }, fn(n) {
            @sf.words_node(n, fn() { l().note }, fn() { peek_excerpt }) |> ignore
          })
          // (the message its link names, by the thread its message says it has)
          let message = fn() {
            match (named(), l().thread) {
              (Chat(station, _, _, Some(seq)), Some(thread)) => Some((station, thread, seq))
              _ => None
            }
          }
          message_said_node(rich, src, scope, message)
        })
        |> ignore
      }
      // (while the link or the list is read: a made-up chat's, in its bones)
      Sample =>
        @sf.waiting_node(b, fn(bones) {
          chat_card_of_node(bones, fn() { sample_chat(0) }, fn() { false }, fn() { false }, fn() { None }, src, scope)
        })
      Gone => @sf.words_node(b, fn() { @sf.t("web-main.chatRef.previewGone") }, fn() { peek_note }) |> ignore
      Found => {
        let it = fn() {
          match found() {
            Some(Some(f)) => Some(f)
            _ => None
          }
        }
        let item = fn() { it().map(fn(f) { f.0 }).unwrap_or(sample_chat(0)) }
        chat_card_of_node(
          b,
          item,
          fn() { item().station != here },
          fn() { it().map(fn(f) { f.1 }).unwrap_or(false) },
          fn() {
            match it() {
              Some((i, _, Some(seq))) =>
                match i.thread {
                  Some(thread) => Some((i.station, thread, seq))
                  None => None
                }
              _ => None
            }
          },
          src,
          scope,
        )
      }
    }
  })
}

///|
/// The card of a chat found (chat_card_of's) in `parent`, of `item` as it is now: its mark, title and when it was last
/// active; where it is (`elsewhere`, another station: its mark and name) and that the link is its agent's execution
/// history (`history`); the message the link names (`message`: its station, thread and number) in place of where it
/// stands or the last thing said in it (three lines at most).
fn chat_card_of_node(
  parent : @view.View,
  item : () -> ChatItem,
  elsewhere : () -> Bool,
  history : () -> Bool,
  message : () -> (String, Double, Double)?,
  src : Source,
  scope : String,
) -> Unit {
  parent.box(fn(rich) {
    @sf.style_node(rich, fn() { peek_rich })
    rich.box(fn(t) {
      @sf.style_node(t, fn() { peek_chat_title })
      // (none: nothing in its place, not even the room between, as chat_mark's 0)
      let tone = fn() { @sfbase.row_tone(item()) }
      t.show(fn() { tone() is ("busy" | "done" | "alert" | "wait") }, fn(m) { chat_mark_node(m, tone) })
      peek_title_node(t, fn() { item().title })
      t.show(fn() { item().ago != "" }, fn(a) { @sf.words_node(a, fn() { item().ago }, fn() { peek_meta_words }) |> ignore })
    })
    |> ignore
    rich.show(fn() { elsewhere() || history() }, fn(m) {
      @sf.style_node(m, fn() { peek_meta })
      m.box(fn(w) {
        @sf.style_node(w, fn() { peek_chat_where }, in_row=true)
        w.show(elsewhere, fn(s) {
          @sf.station_mark_node(
            s,
            fn() { item().station_emoji },
            fn() { item().station_icon },
            peek_station_mark,
            fn() { @sf.theme().p.muted },
            fn() { 0 },
          )
        })
        @sf.words_node(
          w,
          fn() {
            [
              if elsewhere() { item().station_name } else { "" },
              if history() { @sf.t("web-main.chatRef.previewHistory") } else { "" },
            ]
            .filter(fn(x) { x != "" })
            .join(" · ")
          },
          fn() { peek_meta_words },
        )
        |> ignore
      })
      |> ignore
    })
    message_said_node(rich, src, scope, message)
    // (where it names none: where it stands, else the last thing said in it)
    let said = fn() {
      let i = item()
      match (i.state_text, i.decision_text, i.last) {
        (Some(s), _, _) if s != "" => s
        (_, Some(s), _) if s != "" => s
        (_, _, Some(s)) => s
        _ => ""
      }
    }
    rich.show(fn() { message() is None && said() != "" }, fn(e) {
      @sf.words_node(e, said, fn() { peek_excerpt }) |> ignore
    })
  })
  |> ignore
}

///|
/// A card's title (peek_title, in what is left of its line, cut) in `parent`, as `title` says it now.
fn peek_title_node(parent : @view.View, title : () -> String) -> Unit {
  parent.box(fn(r) {
    @sf.style_node(r, fn() { peek_ref }, in_row=true)
    r.lines_up(Is(Some(@view.Along::Start))) |> ignore
    @sf.words_node(r, title, fn() { peek_title }) |> ignore
  })
  |> ignore
}

///|
/// The message of a chat on its card (message_said's) in `parent`, where `message` names one (its station, thread and
/// number, as it is now), as the core reads it (`messagePeek`, for `scope`): who said it and when, over its words (six
/// lines at most); that it can't be read, for one gone or a station that won't say; bones while it is read.
fn message_said_node(
  parent : @view.View,
  src : Source,
  scope : String,
  message : () -> (String, Double, Double)?,
) -> Unit {
  // (none named: nothing in its place, not even the room between)
  parent.show(fn() { message() is Some(_) }, fn(s) {
    s.pick(message, fn(b, m) {
      @sf.style_node(b, fn() { peek_card_part })
      guard m is Some((station, thread, seq)) else { return }
      let params : Map[String, Json] = {
        "station": Json::string(station),
        "thread": Json::number(thread),
        "seq": Json::number(seq),
      }
      let read = @sfbase.hold(src, scope, "messagePeek", params)
      let value = fn() -> Json? {
        match read.get().value {
          Some(Object(_)) as v => v
          _ => None
        }
      }
      // (said; read, in its bones; else gone: a value that is no message, or the core's error)
      let shows = fn() {
        let r = read.get()
        match r.value {
          Some(Object(_)) => 2
          None if r.error is None => 1
          _ => 0
        }
      }
      b.pick(shows, fn(q, k) {
        @sf.style_node(q, fn() { peek_card_part })
        match k {
          2 => {
            let head = fn() {
              let v = value()
              [text(v, "author"), text(field(field(v, "time"), "at"), "ago")].filter(fn(w) { w != "" }).join(" · ")
            }
            q.show(fn() { head() != "" }, fn(h) {
              // (as wide as it is, cut where it has not the room: not stretched across the card)
              h.lines_up(Is(Some(@view.Along::Start))) |> ignore
              @sf.words_node(h, head, fn() { peek_meta_words }) |> ignore
            })
            @sf.words_node(q, fn() { text(value(), "text") }, fn() { peek_message }) |> ignore
          }
          1 =>
            @sf.waiting_node(q, fn(bones) {
              @sf.words_node(bones, fn() { @sf.sample_words(8) }, fn() { peek_meta_words }) |> ignore
              @sf.words_node(bones, fn() { @sf.sample_words(60) }, fn() { peek_message }) |> ignore
            })
          _ =>
            @sf.words_node(q, fn() { @sf.t("web-main.chatRef.previewMessageGone") }, fn() { peek_note }) |> ignore
        }
      })
    })
  })
}
