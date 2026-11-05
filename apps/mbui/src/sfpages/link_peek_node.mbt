// A link's card in words drawn by nodes (peeks.mbt's link_peek, Peeks.tsx Hover), while the pointer rests on it: opened
// once it has rested on the link hover_open_ms, closed hover_close_ms after it has left both the link and the card;
// under the piece of line it rests on and at its start, hover_offset away, kept in the chat's room; over the chat's
// messages and its composer (its page's flight layer: chat_flight_layer). What the card holds, the old view it is (a
// web page's tile or a pull request's card, a file's few lines, a chat's card), an island as tall as it is; what it
// shows read as the pointer comes onto the link and while the card shows, let go of once neither (peek_read's).

///|
/// The links of words `w` (their pieces as runs_links says them, `links`) in chat `here`'s message: each one's card
/// while the pointer rests on it. `agent` the agent whose files a path names (none: a path is no link of a card),
/// `chats` the chats the message names, `link_to` what each link is to as the core says it.
fn link_peeks_node(
  w : @view.View,
  links : @ui.RunsLinks,
  runs : () -> Array[@ui.Run],
  src : Source,
  here : () -> MessageHere,
  agent? : () -> String = fn() { "" },
  chats? : () -> Array[LinkedChat] = fn() { [] },
  link_to? : () -> (String) -> @sf.LinkTo = fn() { fn(_) { @sf.no_link_to } },
) -> Unit {
  // (words with no link: nothing of it)
  guard @signals.untracked(runs).iter().any(fn(r) { r.link != "" }) else { return }
  // (the link the pointer is on, by its first run's way: its href and words; "" none)
  let on_link = fn() -> (String, String) {
    let k = links.pointed_on_input.get()
    let rs = runs()
    guard k >= 0 && k < rs.length() else { return ("", "") }
    let href = rs[k].link
    let words = StringBuilder()
    let mut j = k
    while j < rs.length() && rs[j].link == href {
      words.write_string(rs[j].text)
      j = j + 1
    }
    (href, words.to_string())
  }
  // (the link whose card shows, and where its piece was as it opened; none closed)
  let open : @signals.Signal[(String, String, (Double, Double, Double, Double))?] = @signals.signal(None, same=fn(a, b) {
    a == b
  })
  let card_on : @signals.Signal[@view.View?] = @signals.signal(None,
    same=fn(a, b) { a.map(fn(v) { v.id() }) == b.map(fn(v) { v.id() }) })
  let due : Ref[() -> Unit] = Ref(fn() {  })
  let on_it = fn() {
    let over_card = card_on.get().map(pointer_over).unwrap_or(false)
    let (href, _) = on_link()
    @sf.pointer_rests() &&
    (href != "" || over_card)
  }
  // (rested on a link, its card; onto another, that one's; left, both the link and the card, closed: each from the
  // moment the pointer came or went)
  w.reacts(fn() { (on_it(), on_link().0) }, fn(now) {
    (due.val)()
    let (on, href) = now
    if on && href != "" {
      // (onto another link than the one whose card shows: that one closed, this one's to come)
      match @signals.untracked(fn() { open.get() }) {
        Some((was, _, _)) if was != href => open.set(None)
        _ => ()
      }
      let words = @signals.untracked(on_link).1
      let at = @signals.untracked(fn() { links.pointed_at_on_input.get() })
      // (read as the pointer comes onto it: the card's words there as it opens)
      warm_peek(src, here, href, @signals.untracked(agent), @signals.untracked(chats), @signals.untracked(link_to))
      match at {
        Some(rect) =>
          due.val = w.at_moment(w.cause_at() + hover_open_ms, fn() {
            if peek_shown(href, @signals.untracked(agent), @signals.untracked(chats), @signals.untracked(link_to)) {
              open.set(Some((href, words, rect)))
            }
          })
        None => ()
      }
    } else if !on {
      due.val = w.at_moment(w.cause_at() + hover_close_ms, fn() { open.set(None) })
    }
  })
  w.owns(fn() { (due.val)() }) |> ignore
  // (in the chat's flight layer, in a place of its own there let go with the words; nothing of it in the words: what
  // is laid out in them theirs alone)
  guard @signals.untracked(fn() { chat_flight_layer(here_ref(here())) }) is Some(l) else { return }
  // (made again for another link, closed first: on_link's)
  l.box(fn(place) {
    place.over(Is(true)) |> ignore
    place.show(fn() { open.get() is Some(_) }, fn(anchor) {
    guard @signals.untracked(fn() { open.get() }) is Some((href, words, (px, py, _, ph))) else { return }
    let scope = "link-peek-node/" + href
    l.box(fn(card) {
      let card_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
      card.owns(fn() {
        card_on.set(None)
        @sfbase.let_go(src, scope)
      })
      |> ignore
      // (under the piece of line it rests on, at its start; kept in the chat's room)
      card
      .offset(By(fn() {
        match l.laid_window_told() {
          Some((lx, ly, lw, _)) => {
            let cw = card_w.get().unwrap_or(0.0)
            (dmax(0.0, dmin(px - lx, lw - cw - 8.0)), py + ph + hover_offset - ly)
          }
          None => (0.0, 0.0)
        }
      }))
      |> ignore
      let tile = peek_tile_of(href, @signals.untracked(link_to))
      @ui.old(card, fn(c) {
        let h = here()
        c.box(style=if tile { hover_tile } else { hover_card }, fn() {
          @sf.small_panel(c, w=Fill(1.0), fn() {
            c.box(style=hover_inner, fn() {
              peek_body(c, src, h.station, scope, href, words, agent(), chats(), link_to())
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }, natural=true, fits=(if tile { link_peek_tile_most } else { link_peek_card_w }, card_w))
      // (as wide as the old frame lays what it holds out: it takes the pointer there, its own lighting by it)
      .width(By(fn() { card_w.get() }))
      |> fn(island) { card_on.set(Some(island)) }
    })
    .lives_with(anchor)
    |> ignore
    })
  })
  .lives_with(w)
  |> ignore
}

///|
/// A link's card as wide as what it holds at most (hover_tile_most's 420), or a card's (hover_card_w's 320).
let link_peek_tile_most : Double = 420.0

///|
let link_peek_card_w : Double = 320.0

///|
/// What link `href` is to, of the kinds that have a card (link_peek's): a file an agent names by its path, a chat, a
/// web page.
priv enum PeekOf {
  File(String, Int?)
  Chat(LinkedChat?)
  Web(String)
  NoPeek
}

///|
fn peek_of(href : String, agent : String, chats : Array[LinkedChat], link_to : (String) -> @sf.LinkTo) -> PeekOf {
  match @sf.path_of_link(href) {
    Some((path, line)) => return if agent != "" { File(path, line) } else { NoPeek }
    None => ()
  }
  let to = link_to(href)
  let linked = chats.iter().find_first(fn(l) { l.href == href })
  if linked is Some(_) || to.chat {
    return Chat(linked)
  }
  if href.has_prefix("https://") || href.has_prefix("http://") {
    Web(to.peek)
  } else {
    NoPeek
  }
}

///|
/// Whether link `href` has a card.
fn peek_shown(href : String, agent : String, chats : Array[LinkedChat], link_to : (String) -> @sf.LinkTo) -> Bool {
  !(peek_of(href, agent, chats, link_to) is NoPeek)
}

///|
/// Whether link `href`'s card is a tile, as wide as what it holds (a web page's without a rich card said of it).
fn peek_tile_of(href : String, link_to : (String) -> @sf.LinkTo) -> Bool {
  match peek_of(href, "", [], link_to) {
    Web(peek) => peek == ""
    _ => false
  }
}

///|
/// What link `href`'s card shows read as the pointer comes onto it (peek_read's warm, file_peek's subscribing again,
/// chat_peek's naming).
fn warm_peek(
  src : Source,
  here : () -> MessageHere,
  href : String,
  agent : String,
  chats : Array[LinkedChat],
  link_to : (String) -> @sf.LinkTo,
) -> Unit {
  let h = @signals.untracked(here)
  guard h.station != "" else { return }
  let scope = "link-peek-node/" + href
  match peek_of(href, agent, chats, link_to) {
    File(path, line) => {
      let params = file_peek_params(h.station, agent, path, line)
      // (the file may have been written or removed since the last time the pointer was here)
      (src.leave)("filePeek", params)
      ignore(@sfbase.hold(src, scope, "filePeek", params))
    }
    Chat(_) => ignore(chat_named(src, h.station, href))
    Web(_) => ignore(@sfbase.hold(src, scope, "linkPreview", link_params(h.station, href)))
    NoPeek => ()
  }
}

///|
/// What link `href`'s card holds (link_peek's bodies): a file's few lines, a chat's card, a web page's tile or a pull
/// request's card with its address to copy.
fn peek_body(
  c : @ui.Ctx,
  src : Source,
  station : String,
  scope : String,
  href : String,
  words : String,
  agent : String,
  chats : Array[LinkedChat],
  link_to : (String) -> @sf.LinkTo,
) -> Unit {
  match peek_of(href, agent, chats, link_to) {
    File(path, line) => file_card(c, src, scope, file_peek_params(station, agent, path, line), path)
    Chat(linked) => chat_card(c, src, scope, station, href, linked)
    Web(peek) => link_card(c, src, scope, link_params(station, href), href, words, peek~, copy=fn() { link_copy(c, href) })
    NoPeek => ()
  }
}
