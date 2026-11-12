// Links to a station's screens and to a chat's web service in an agent's words, as nodes of the window's tree, made
// once (screen_links.mbt's screen_links, screen_link_card, service_link_card, link_mark, link_card_words, their styles
// the same): a link alone in a paragraph its card, one bare in a sentence its title; each as the core says it as that
// changes (the screenCard, adbCard and job topics). Not here yet: a screen its station previews, live across its card's
// top (screen_peek: its pictures, an Android device's video, asked while its card shows and the app is in front): its
// card is not drawn till then.

///|
/// The links to screens in an agent's words as a chat draws them (screen_links'), for markdown_node: their cards, and a
/// bare one's title (屏幕 until it is known); a station's 共享调试's title its own; a web service's card and title.
pub fn screen_links_node(src : Source) -> @sf.ScreensNode {
  {
    card: fn(v, href, to, words) {
      match to.card {
        "service" => service_link_card_node(v, src, href, to, words)
        _ => screen_link_card_node(v, src, href, to, words)
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
/// has; tapped, where the link leads. As the core says it as that changes. One its station previews: not drawn yet.
fn screen_link_card_node(v : @view.View, src : Source, href : String, to : @sf.LinkTo, words : String?) -> Unit {
  let card = fn() { screen_card_of(src, to) }
  let previewed = fn() {
    match card() {
      Some(k) => to.card == "screen" && k.peek && !k.gone
      None => false
    }
  }
  v.show(fn() { !previewed() }, fn(b) {
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
    b.box(fn(w) {
      @sf.style_node(w, fn() { link_words }, in_row=true)
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
