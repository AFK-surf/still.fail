// What a chat's agents and other chats' agents wrote each other (session_send), in a tab beside the chat (ember
// web/src/Letters.tsx, Letters.css.ts; the core's `chatLetters` view): first the chats it wrote with, a row each, the
// last written with first; one opened, its letters both ways in the order written, each drawn as the chat draws a
// message out of its list (StaticMessage: message.mbt).

///|
/// The chat opened in each chat's letters (by the chat's key; none: the list).
let letters_opened : Map[String, String] = {}

///|
fn letters_reset() -> Unit {
  letters_opened.clear()
}

///|
/// Chat `r`'s letters' tab at its list.
pub fn letters_to_list(r : ChatRef) -> Unit {
  letters_opened.remove(chat_key(r))
}

///|
/// The chats that wrote each other (`chats`), a row each: its title, how many letters and when, the last; pressed,
/// opened in the tab of chat `key`.
fn letters_list_of(c : @ui.Ctx, key : String, chats : Array[Json]) -> Unit {
  c.box(style=letters_list, fn() {
    for ch in chats {
      let cv = Some(ch)
      let ck = text(cv, "key")
      let id = c.id("letters/row/" + ck)
      if c.clicked(id) {
        letters_opened[key] = ck
      }
      let b = c.box(style=letters_row, id~, fn() {
        c.box(style=letters_row_head, fn() {
          c.box(style=letters_grow, fn() { c.text(text(cv, "title"), style=letters_row_title, allow_ellipsis=true) |> ignore })
          |> ignore
          let n = @sf.t("web-main.letters.count", args=[("n", items(cv, "letters").length().to_string())])
          let ago = text(field(field(cv, "time"), "lastActiveAt"), "ago")
          c.text(if ago == "" { n } else { n + " · " + ago }, style=letters_row_meta) |> ignore
        })
        |> ignore
        c.text(text(cv, "last"), style=letters_row_last) |> ignore
      })
      c.semantics(b, Button, id~, label=text(cv, "title"))
    }
  })
  |> ignore
}

///|
/// Chats that wrote each other, made up, for what the tab shows while they are read (letters_list_of in its bones).
fn letters_sample() -> Array[Json] {
  [(8, 18), (6, 22), (10, 14), (7, 20)].mapi(fn(i, n) {
    Json::object({
      "key": Json::string("sample" + i.to_string()),
      "title": Json::string(@sf.sample_words(n.0)),
      "last": Json::string(@sf.sample_words(n.1)),
      "time": { "lastActiveAt": { "ago": Json::string(@sf.sample_words(3)) } },
    })
  })
}

///|
/// Chat `r`'s letters (its view `v`, its thread `thread`): its list, or the chat opened in it, its messages each drawn
/// as the chat draws one, its files kept by the chat's sessions; a chat's title pressed opened as a link in it is.
fn letters_tab(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, thread : Double) -> Unit {
  let key = chat_key(r)
  let view = (src.topic)("chatLetters", { "station": Json::string(r.station), "thread": Json::number(thread) }).value
  let chats = items(view, "chats")
  let whole = flag(view, "whole")
  if !(view is Some(Object(_))) || (chats.length() == 0 && !whole) {
    @sf.waiting(c, fill=true, fn() { letters_list_of(c, "sample", letters_sample()) })
    return
  }
  if chats.length() == 0 {
    @sf.empty(c, fn() { c.text(@sf.t("web-main.letters.none"), style=letters_none) |> ignore })
    return
  }
  let opened = match letters_opened.get(key) {
    Some(k) => chats.iter().find_first(fn(ch) { text(Some(ch), "key") == k })
    None => None
  }
  let rows : Array[() -> Unit] = []
  match opened {
    None =>
      rows.push(fn() { letters_list_of(c, key, chats) })
    Some(ch) => {
      let cv = Some(ch)
      rows.push(fn() {
        // back to the list, and its title (which opens that chat)
        c.box(style=letters_head, fn() {
          if @sf.icon_button(c, "arrow-left", key="letters/back", round=true, label=@sf.t("web-main.letters.back")) {
            letters_opened.remove(key)
          }
          let title = text(cv, "title")
          let to = text(cv, "link")
          if to == "" {
            c.text(title, style=letters_name, allow_ellipsis=true) |> ignore
          } else {
            let nid = c.id("letters/name")
            if c.clicked(nid) {
              c.tell("letters/name", fn() { open_link(to) })
            }
            let b = c.box(style=letters_name_box, id=nid, fn() {
              // (underlined on hover)
              c.rich([@ui.span(title, underline=c.lit(nid))], style=letters_name, allow_ellipsis=true) |> ignore
            })
            c.semantics(b, Link, id=nid, label=title)
          }
        })
        |> ignore
      })
      for m in items(cv, "letters") {
        let here : MessageHere = { station: r.station, session: r.session, view: v, go: None, inline: true, gutter: 0.0, list: None, core: None }
        rows.push(fn() { c.box(style=letters_message, fn() { message_row(c, src, here, message_of(m)) }) |> ignore })
      }
      rows.push(fn() { c.box(style=letters_foot, fn() {  }) |> ignore })
    }
  }
  // not all of the chat is here yet: more may come, older ones
  if !whole {
    rows.push(fn() { c.box(style=letters_more, fn() { @sf.spinner(c) |> ignore }) |> ignore })
  }
  c.list("letters/" + key + "/" + letters_opened.get(key).unwrap_or(""), rows.length(), 60.0, fn(i) { (rows[i])() })
  |> ignore
}

///|
/// The chats it wrote with (lettersList): 6 over, 8 at the sides, 16 under, 2 apart.
// kept across runs: a value (no field of it changes)
let letters_list : @ui.Style = @ui.css("w=Full pt=S1_5 px=S2 pb=S4 gap=S0_5")

///|
/// A chat it wrote with (lettersRow): 8 by 12 in, round as an option, the pointer's ground on it; its title (13 in
/// 500 on 20) and how many and when (12, muted) on a line, the last letter in brief under them (12, muted).
// kept across runs: a value (no field of it changes)
let letters_row : @ui.Style = @ui.css("w=Full py=S2 px=S3 gap=S0_5 radius=Xl hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let letters_row_head : @ui.Style = @ui.css("row w=Full gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let letters_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let letters_row_title : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let letters_row_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let letters_row_last : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Full)

///|
/// One opened (lettersHead): back and its title 4 apart, 6 over and under, 6 in at its start, 12 at its end; its title
/// 13 in 500, underlined on hover where it opens that chat.
// kept across runs: a value (no field of it changes)
let letters_head : @ui.Style = @ui.css("row w=Full py=S1_5 pl=S1_5 pr=S3 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let letters_name_box : @ui.Style = @ui.style(row=true, w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let letters_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)


///|
/// Its letters (lettersMessages): 20 apart, 10 over, 16 at the sides, 24 under the last.
// kept across runs: a value (no field of it changes)
let letters_message : @ui.Style = @ui.css("w=Full pt=S2_5 px=S4 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let letters_foot : @ui.Style = @ui.css("w=Full h=S6")

///|
/// More to come (lettersMore): a spinner in the middle, 4 over and under.
// kept across runs: a value (no field of it changes)
let letters_more : @ui.Style = @ui.css("row w=Full py=S1 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let letters_none : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)
