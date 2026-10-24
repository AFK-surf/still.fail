// What a chat's agents and other chats' agents wrote each other (session_send), in a tab beside the chat (ember
// web/src/Letters.tsx, Letters.css.ts; the core's `chatLetters` view): first the chats it wrote with, a row each, the
// last written with first; one opened, its letters both ways in the order written, each drawn as the chat draws a
// message (the page's).

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
/// Chat `r`'s letters (its thread `thread`): its list, or the chat opened in it, its messages each drawn by `message`;
/// a chat's title pressed opened by `link`.
fn letters_tab(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  thread : Double,
  message : (Json) -> Unit,
  link : (String) -> Unit,
) -> Unit {
  let key = chat_key(r)
  let view = (src.topic)("chatLetters", { "station": Json::string(r.station), "thread": Json::number(thread) }).value
  let chats = items(view, "chats")
  let whole = flag(view, "whole")
  if !(view is Some(Object(_))) || (chats.length() == 0 && !whole) {
    @sf.waiting(c, shape=Rows, fill=true)
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
      rows.push(fn() {
        c.box(style=letters_list, fn() {
          for ch in chats {
            let cv = Some(ch)
            let ck = text(cv, "key")
            let id = c.id("letters/row/" + ck)
            c.cursor(id, Hand)
            if c.clicked(id) {
              letters_opened[key] = ck
            }
            let b = c.box(style=letters_row, id~, fn() {
              c.box(style=letters_row_head, fn() {
                c.box(style=letters_grow, fn() { c.text(text(cv, "title"), style=letters_row_title) |> ignore })
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
      })
    Some(ch) => {
      let cv = Some(ch)
      rows.push(fn() {
        // back to the list, and its title (which opens that chat)
        c.box(style=letters_head, fn() {
          if icon_button(c, "letters/back", "arrow-left", label=@sf.t("web-main.letters.back")) {
            letters_opened.remove(key)
          }
          let title = text(cv, "title")
          let to = text(cv, "link")
          if to == "" {
            c.text(title, style=letters_name) |> ignore
          } else {
            let nid = c.id("letters/name")
            c.cursor(nid, Hand)
            if c.clicked(nid) {
              link(to)
            }
            let b = c.box(style=letters_name_box, id=nid, fn() {
              // (underlined on hover)
              c.rich([@ui.span(title, underline=c.hovered(nid))], style=letters_name) |> ignore
            })
            c.semantics(b, Link, id=nid, label=title)
          }
        })
        |> ignore
      })
      for m in items(cv, "letters") {
        rows.push(fn() { c.box(style=letters_message, fn() { message(m) }) |> ignore })
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
let letters_row_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let letters_row_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let letters_row_last : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, w=Full)

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
let letters_name : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)


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
let letters_none : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)
