// Links to a station's screens and to a chat's web service in an agent's words, as nodes of the window's tree, made
// once (screen_links.mbt's screen_links, screen_link_card, service_link_card, link_mark, link_card_words, their styles
// the same): a link alone in a paragraph its card, one bare in a sentence its title; each as the core says it as that
// changes (the screenCard, adbCard and job topics). A screen its station previews is live across its card's top
// (screen_peek's, by screen_peek_node): the card's node owns its preview (its Peek, in `peeks` by its key as the old
// view's) while it shows, its page showing (page_shows_lent) and the app shown: asked as all three come to hold, stopped
// as one stops holding or the node is let go (a page's list makes a block only while it shows and lets it go as it
// leaves: scrolled off, the card goes); nothing worked out frame by frame (the old view's peeks_built, peeks_frame,
// peeks_settle pass a node's Peek by). An Android device's (H.264 alone, where the host decodes it) is its Peek's
// Stream, drawn in the card by a stream node (ui's stream) the Peek closes itself (peek_drop_video: as the card leaves
// sight, and past video_peeks_most).

///|
/// Whether the page what is made in it is on shows (a chat's page made as nodes lends it to its rows:
/// chat_page_body_node): a card's preview is asked only while it does. Where none is lent, as shown.
// kept across runs: each lender's value kept by its node, let go with it (View::lends)
pub let page_shows_lent : @view.Lent[() -> Bool] = @view.Lent::new()

///|
/// The links to screens in an agent's words as a chat draws them (screen_links'), for markdown_node: their cards, and a
/// bare one's title (屏幕 until it is known); a station's 共享调试's title its own; a web service's card and title.
/// `message` names the message (a screen's preview is its card's own: by its message and its link, as screen_links').
pub fn screen_links_node(src : Source, message? : String = "") -> @sf.ScreensNode {
  {
    card: fn(v, href, to, words) {
      match to.card {
        "service" => service_link_card_node(v, src, href, to, words)
        _ => screen_link_card_node(v, src, message + "\n" + href, href, to, words)
      }
    },
    title: fn(_href, to) {
      if to.card == "adb" {
        adb_title(src, to)
      } else if to.card == "service" {
        service_card_of(src, to).0
      } else {
        match screen_card_of(src, to) {
          Some(card) => card.title
          None => @sf.t("android-misc.screen.title")
        }
      }
    },
  }
}

///|
/// A screen's link as its card (screen_link_card's) in `v`: its kind's mark (none till the core has said), its title
/// (the link's own words, where it has them) over what its station says of it, quieter for one its station no longer
/// has; tapped, where the link leads. As the core says it as that changes. One its station previews: the screen live
/// across its card's top, the words under it (screen_peek_card_node); `key` its preview's.
fn screen_link_card_node(
  v : @view.View,
  src : Source,
  key : String,
  href : String,
  to : @sf.LinkTo,
  words : String?,
) -> Unit {
  let card = fn() { screen_card_of(src, to) }
  let previewed = fn() {
    match card() {
      Some(k) => to.card == "screen" && k.peek && !k.gone
      None => false
    }
  }
  v.pick(previewed, fn(b, live) {
    if live {
      screen_peek_card_node(b, src, key, href, to, card, fn() {
        match (words, card()) {
          (Some(w), _) => w
          (None, Some(k)) => k.title
          (None, None) => ""
        }
      })
      return
    }
    link_card_node(
      b,
      href,
      fn() {
        match card() {
          None => None
          Some(k) => Some(if k.kind == "browser" { globe_mark } else { monitor_mark })
        }
      },
      fn() {
        match (words, card()) {
          (Some(w), _) => w
          (None, Some(k)) => k.title
          (None, None) => ""
        }
      },
      fn() {
        match card() {
          Some(k) => k.line
          None => ""
        }
      },
      fn() {
        match card() {
          Some(k) => k.gone
          None => false
        }
      },
    )
  })
}

///|
/// A link to a chat's web service as its card (service_link_card's) in `v`: the web's mark, its title (the link's own
/// words, where it has them) over its station and port and how it stands; quieter where it is no longer up. Tapped,
/// where the link leads. As the core says it as that changes.
fn service_link_card_node(v : @view.View, src : Source, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  let said = fn() { service_card_of(src, to) }
  link_card_node(
    v,
    href,
    fn() { Some(globe_mark) },
    fn() {
      match words {
        Some(w) => w
        None => said().0
      }
    },
    fn() { said().1 },
    fn() { said().2 },
  )
}

///|
/// A link's card (link_card's) in `v`: a capsule a file's card's size, `mark` in its room (none: the room kept), its
/// `title` over its `line` (each as high as its words at least), the title quieter where `gone`; tapped, `href` opened (open_link, as the link does). Named
/// as a link by its title. Each as it changes.
fn link_card_node(
  v : @view.View,
  href : String,
  mark : () -> LinkMark?,
  title : () -> String,
  line : () -> String,
  gone : () -> Bool,
) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { link_card })
    @sf.presses_node(b, fn() { open_link(href) })
    b.says(By(fn() { Some(@view.said(Link, label=title())) })) |> ignore
    link_mark_node(b, mark)
    link_words_node(b, link_words, true, title, line, gone)
  })
  |> ignore
}

///|
/// A card's two lines (link_card_words') in `v`, in a box of `look` (`in_row`: laid out along a row): its `title` over
/// its `line`, each as high as its words at least, the title quieter where `gone`. Each as it changes.
fn link_words_node(
  v : @view.View,
  look : @ui.Style,
  in_row : Bool,
  title : () -> String,
  line : () -> String,
  gone : () -> Bool,
) -> Unit {
  v.box(fn(w) {
    @sf.style_node(w, fn() { look }, in_row~)
    w.box(fn(l) {
      @sf.style_node(l, fn() { link_title_line_node })
      @sf.words_node(l, title, fn() { if gone() { link_title_gone } else { link_title } }) |> ignore
    })
    |> ignore
    w.box(fn(l) {
      @sf.style_node(l, fn() { link_line_line_node })
      @sf.words_node(l, line, fn() { link_line }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A screen its station previews as its card (screen_link_card's peek_card) in `v`: a column, the screen live across
/// its top (screen_peek_node, `key` its preview's), its `title` over what its station says of it under it; tapped,
/// where `href` leads. Named as a link by its title. Each as the core says it (`card`) as that changes.
fn screen_peek_card_node(
  v : @view.View,
  src : Source,
  key : String,
  href : String,
  to : @sf.LinkTo,
  card : () -> ScreenCard?,
  title : () -> String,
) -> Unit {
  v.box(fn(b) {
    @sf.style_node(b, fn() { peek_card })
    @sf.presses_node(b, fn() { open_link(href) })
    b.says(By(fn() { Some(@view.said(Link, label=title())) })) |> ignore
    screen_peek_node(b, src, key, to.station, to.screen, card)
    link_words_node(
      b,
      peek_card_words,
      false,
      title,
      fn() {
        match card() {
          Some(k) => k.line
          None => ""
        }
      },
      fn() { false },
    )
  })
  |> ignore
}

///|
/// The screen `screen` of `station` live in its card (screen_peek's) in `v`, its preview the card's own (`key`: its
/// Peek in `peeks`, held by this node: Peek's `made`): asked (JPEG, and H.264 where the host decodes it) while the node is,
/// the page it is on shows (page_shows_lent) and the app is shown, stopped as one of them stops holding, and as the node
/// is let go, its pictures let go with it and its Peek taken out of `peeks`. Each frame that comes acknowledged
/// peek_ms after the one before (the first at once), at its moment; ended (refused, or no longer previewed) while it is
/// wanted, asked again peek_again_ms on. Its mark till a picture comes; the newest picture decoded filling it, cropped
/// from the top, a newer one drawn over it once decoded and the older let go of then; a video's decoder over them all,
/// filling it the same way (nothing of it drawn till a frame shows). A browser's 16:10; another screen's as its picture
/// is (its video's, once one shows), its listed size till one is decoded, within peek_ratio_least and peek_ratio_most.
fn screen_peek_node(
  v : @view.View,
  src : Source,
  key : String,
  station : String,
  screen : String,
  card : () -> ScreenCard?,
) -> Unit {
  let p = peek_for(key, station, screen)
  p.made = true
  let shows = match v.lent(page_shows_lent) {
    Some(f) => f
    None => fn() { true }
  }
  // (asked while all of it holds; stopped as any stops: nothing of its ending kept to ask again by)
  v.reacts(fn() { shows() && @ui.app_visible() }, fn(want) {
    if want {
      if p.run == PeekOff {
        peek_start(src, p)
      }
    } else if p.run != PeekOff {
      peek_stop(src, p)
    }
  })
  // (ended while it is wanted: asked again peek_again_ms on, where it still is; a time nothing shown waits for, as the
  // old view's wake said `later`)
  v.reacts(fn() { p.told.get() |> ignore; (p.run == PeekEnded, p.view) }, fn(now) {
    guard now.0 else { return }
    let view = now.1
    v.at_moment(
      v.cause_at() + peek_again_ms,
      fn() {
        if p.run == PeekEnded && p.view == view && @signals.untracked(fn() { shows() && @ui.app_visible() }) {
          peek_start(src, p)
        }
      },
      later=true,
    )
    |> ignore
  })
  // (each frame waiting acknowledged in its turn: the first at once, each next peek_ms after the one before was sent)
  let next_at = Ref(0.0)
  let waits = Ref(false)
  let ack_next : Ref[() -> Unit] = Ref(fn() {  })
  ack_next.val = fn() {
    guard !waits.val && p.run == PeekOn && p.waiting.length() > 0 else { return }
    let view = p.view
    let n = p.acked
    waits.val = true
    let at = if n == 0 { v.cause_at() } else { next_at.val }
    let send = fn() {
      waits.val = false
      if p.view == view && p.acked == n && p.waiting.length() > 0 {
        let ts = p.waiting.remove(0)
        p.acked = n + 1
        next_at.val = v.cause_at() + peek_ms
        (src.call)("screen.ack", { "view": Json::string(view), "ts": ts }, answer_unread)
      }
      (ack_next.val)()
    }
    v.at_moment(at, send, later=true) |> ignore
  }
  v.reacts(fn() { p.told.get() |> ignore; (p.view, p.acked, p.waiting.length()) }, fn(_) { (ack_next.val)() })
  // (let go: stopped, its pictures' bytes emptied (nothing draws them again), its Peek no longer the app's)
  v.owns(fn() {
    peek_stop(src, p)
    for k in p.pictures {
      @ui.add_image(k, b"")
    }
    p.pictures.clear()
    match peeks.get(key) {
      Some(q) if physical_equal(q, p) => peeks.remove(key)
      _ => ()
    }
  })
  |> ignore
  v.box(fn(f) {
    // (peek_frame's, its corners concentric with the card's said here: no node lays radius=Inner)
    @sf.style_node(f, fn() { peek_frame_node })
    f.radius(Is(dmax(0.0, @sf.message_file_corner - @sf.peek_card_in_px))) |> ignore
    // (where among its pictures the newest decoded is, -1 none: followed as the host says a decode is ready)
    let newest = fn() {
      p.told.get() |> ignore
      let mut at = -1
      for i, k in p.pictures {
        if f.image_ready(k, 1.0) {
          at = i
        }
      }
      at
    }
    // (those under the newest decoded let go of: their bytes emptied, nothing draws them again)
    f.reacts(newest, fn(at) {
      guard at > 0 else { return }
      for i in 0..<at {
        @ui.add_image(p.pictures[i], b"")
      }
      let rest = p.pictures[at:].to_owned()
      p.pictures.clear()
      p.pictures.append(rest)
      p.tell()
    })
    f.aspect(
      By(fn() {
        guard card() is Some(k) else { return peek_ratio }
        let at = newest()
        // (a video's picture, once one shows, as the old view's: its size what it is told with its frames)
        let video = match p.stream {
          Some(st) if st.shown_any() => st.size()
          _ => None
        }
        let natural = if video is Some((w, h)) && h > 0 {
          w.to_double() / h.to_double()
        } else if at >= 0 {
          match @ui.image_natural(p.pictures[at]) {
            Some((w, h)) if h > 0.0 => w / h
            _ => 0.0
          }
        } else {
          0.0
        }
        let listed = if k.width > 0.0 && k.height > 0.0 { k.width / k.height } else { 0.0 }
        // (a simulator's panel, and so its shape, may have changed since it was listed: as its picture has it)
        let own = if natural > 0.0 { natural } else { listed }
        if k.kind != "browser" && own > 0.0 {
          dclamp(own, peek_ratio_least, peek_ratio_most)
        } else {
          peek_ratio
        }
      }),
    )
    |> ignore
    // (its mark in its middle till a picture is decoded; the picture over it then, which covers it)
    f.show(at_once=true, fn() { newest() < 0 }, fn(m) {
      link_mark_node(m, fn() {
        Some(if card().map(fn(k) { k.kind }) == Some("browser") { globe_mark } else { monitor_mark })
      })
    })
    // (the newest decoded and any newer one decoding, each over it all, filling it from its top, the newer over it)
    f.each(
      fn() {
        let at = newest()
        let from = if at < 0 { 0 } else { at }
        p.pictures[from:].to_owned()
      },
      fn(k) { k },
      fn(i, k) {
        i
        .over(Is(true))
        .image(By(fn() { Some((k.get(), "", peek_size.to_int())) }))
        .image_covers_at(Is(Some(0.0)))
        |> ignore
      },
      at_once=true,
    )
    // (its video's decoder, while it has one, over them all: drawn as each frame shows; closed by the Peek itself, as the
    // card leaves sight or the app's videos are past video_peeks_most, not by the node)
    f.each(
      fn() {
        p.told.get() |> ignore
        match p.stream {
          Some(st) => [st.id()]
          None => []
        }
      },
      fn(id) { id },
      fn(i, id) {
        let id = @signals.untracked(fn() { id.get() })
        guard p.stream is Some(st) && st.id() == id else { return }
        i.over(Is(true)) |> ignore
        @ui.stream(i, st, fit=FitCoverAt(0.0), closes=false).over(Is(true)) |> ignore
      },
      at_once=true,
    )
  })
  |> ignore
}

///|
/// A mark in its room, 24, muted (link_mark's) in `v`; none, its room kept, while `mark` says none.
fn link_mark_node(v : @view.View, mark : () -> LinkMark?) -> Unit {
  v.box(fn(r) {
    @sf.style_node(r, fn() { link_mark_box }, in_row=true)
    r.pick(fn() { mark().map(fn(m) { m.name }) }, fn(i, name) {
      match name {
        Some(n) => @sf.icon_node(i, n, 24.0, By(fn() { @sf.theme().p.muted })) |> ignore
        None => ()
      }
    })
  })
  |> ignore
}

///|
/// Each of a card's two lines a line high at least (link_title_line's 20, link_line_line's 16), as high as its words
/// where the system's size of words makes them higher: at 1.3 the old view's ran over each other (a box holding words
/// grows with them: apps/mbui/AGENTS.md, What is checked).
// kept across runs: a value (no field of it changes)
let link_title_line_node : @ui.Style = @ui.css("w=Full min_h=S5")

///|
// kept across runs: a value (no field of it changes)
let link_line_line_node : @ui.Style = @ui.css("w=Full min_h=S4")

///|
/// The preview's frame (peek_frame's but its corner, said on its node: concentric with the card's).
// kept across runs: a value (no field of it changes)
let peek_frame_node : @ui.Style = @ui.css("w=Full align=ACenter justify=JCenter bg=Wash clip")
