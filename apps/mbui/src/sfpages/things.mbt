// What was said in a chat besides words (the core's `chatThings` view, things.ts): its pictures and videos, its other
// files, the web links in its messages and the pull requests among them, each once and the latest first. One body for
// the wide frame's tab beside the chat (sfdesk panel.mbt) and the narrow frame's sheet (sfapp sheets.mbt): the kinds it
// has to choose from, a field finding among the chosen kind's by their words, then that kind's: the pictures a grid,
// the rest a row each. Pressed, a picture or a file opens in the preview (an image stepping through the chat's), a
// link or a pull request in the browser; held or right clicked, its menu goes to the message it was last said in (在对话
// 里看). The chat's info names its pull requests itself (things_pulls).

///|
/// Each chat's page of things as it was left: the kind chosen ("" the first it has) and the words found by.
priv struct ThingsAt {
  mut kind : String
  field : @ui.Field
}

///|
let things_at : Map[String, ThingsAt] = {}

///|
fn things_reset() -> Unit {
  things_at.clear()
}

///|
fn things_of(key : String) -> ThingsAt {
  match things_at.get(key) {
    Some(t) => t
    None => {
      let t = { kind: "", field: @ui.Field::new() }
      things_at[key] = t
      t
    }
  }
}

///|
/// Chat `r`'s page of things to show its `kind` next (the info's 全部 N 个 for its pull requests).
pub fn things_choose(r : ChatRef, kind : String) -> Unit {
  things_of(r.station + "\u{1}" + r.session).kind = kind
}

///|
/// The kinds, in the order the page offers them (things.ts KINDS), and what each is called.
// kept across runs: a value (no field of it changes)
let thing_kinds : Array[String] = ["media", "files", "links", "pulls"]

///|
fn thing_kind_name(kind : String) -> String {
  @sf.t("web-main.things." + kind)
}

///|
/// The params of a chat's things (the core's `chatThings` view): on `station`, its thread `thread`, those that have
/// the words `q` (all of them with none).
pub fn things_params(station : String, thread : Double, q? : String = "") -> Map[String, Json] {
  let p : Map[String, Json] = { "station": Json::string(station), "thread": Json::number(thread) }
  if q.trim(chars=" ") != "" {
    p["q"] = Json::string(q)
  }
  p
}

///|
/// How many things a chat has of every kind but its pull requests (what the info's row to the page counts), and its
/// pull requests, the latest first, as the core has them now (none until it has read them).
pub fn things_now(src : Source, station : String, thread : Double) -> (Int, Array[Json]) {
  let v = (src.topic)("chatThings", things_params(station, thread)).value
  let counts = field(v, "counts")
  let n = count(counts, "media") + count(counts, "files") + count(counts, "links")
  (n, items(v, "pulls"))
}

///|
/// A pull request's mark (GitHub's octicon for how it stands, peeks.mbt pr_glyph), `side` square: in the quiet grey
/// while it stands as it should, red where something is wrong (closed without being merged, a check failed).
pub fn pull_mark(c : @ui.Ctx, pull : Json?, side : Double) -> Unit {
  let p = @sf.theme().p
  let state = text(pull, "state")
  let wrong = state == "closed" || count(field(pull, "checks"), "failed") > 0
  let ink = if wrong { p.red } else { p.muted }
  match pr_glyph(state) {
    Some(d) => @sf.vector(c, "thing-pull/" + state + "/" + (if wrong { "wrong" } else { "fine" }), glyph_of(d, ink), side) |> ignore
    None => ()
  }
}

///|
/// What a pull request is called: its title once its card is read, else its repository and number.
pub fn pull_title(pull : Json?) -> String {
  match text(pull, "title") {
    "" => text(pull, "repository") + " #" + count(pull, "number").to_string()
    t => t
  }
}

///|
/// What a pull request's line under its title says: how it stands (once it is not open), its repository and number, when it last changed
/// (else when it was last said).
fn pull_meta(pull : Json?) -> String {
  // (how it stands where it is no longer open: open is what one is, said by nothing)
  let parts = []
  match text(pull, "state") {
    "" | "open" => ()
    state => parts.push(@sf.t(pr_state_key(state)))
  }
  if count(field(pull, "checks"), "failed") > 0 {
    parts.push(@sf.t("web-main.preview.checks.failed", args=[("count", count(field(pull, "checks"), "failed").to_string())]))
  }
  parts.push(text(pull, "repository") + " #" + count(pull, "number").to_string())
  let ago = match text(field(field(pull, "time"), "updatedAt"), "ago") {
    "" => text(field(field(pull, "time"), "createdAt"), "ago")
    a => a
  }
  if ago != "" {
    parts.push(ago)
  }
  parts.join(" · ")
}

///|
/// Chat `r`'s things (its thread `thread`), as the page shows them, `key` naming its list; `sheet`: in the narrow
/// frame's sheet (its sides the sheet's words'), else in the wide frame's tab. `away` goes to the chat at a message
/// (the sheet closed first).
pub fn things_body(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, sheet : Bool, away : (Double) -> Unit) -> Unit {
  let key = r.station + "\u{1}" + r.session
  let at = things_of(key)
  let q = at.field.text()
  let topic = (src.topic)("chatThings", things_params(r.station, thread, q~))
  let v = topic.value
  let counts = field(v, "counts")
  let has = thing_kinds.filter(fn(k) { count(counts, k) > 0 })
  let whole = flag(v, "whole")
  let side = if sheet { @sf.panel_words_in() } else { things_side }
  if !(v is Some(Object(_))) || (has.length() == 0 && !whole) {
    @sf.waiting(c, fill=true, fn() { things_sample(c, side) })
    return
  }
  if has.length() == 0 {
    @sf.empty(c, fn() { c.text(@sf.t("web-main.things.none"), style=things_none) |> ignore })
    return
  }
  let kind = if has.contains(at.kind) { at.kind } else { has[0] }
  let shown = items(v, kind)
  let rows : Array[() -> Unit] = []
  // (the field's box: as wide as the room the grid's tiles share; named here, where the rows are not yet each a scope
  // of their own)
  let room_id = c.id("things/grid/" + key)
  // the kinds it has to choose from, each with how many; the field finding among the chosen kind's
  rows.push(fn() {
    c.box(style=things_head.then(side), fn() {
      if has.length() > 1 {
        let labels = has.map(fn(k) { thing_kind_name(k) + " " + count(counts, k).to_string() })
        // (across the row, as the field under it is: their columns share it)
        let item_w = match c.laid_size(room_id) {
          Some((w, _)) if w > 0.0 => @sf.segmented_item_w(w, labels.length())
          _ => 0.0
        }
        let chosen = @sf.segmented(c, "things/kinds/" + key, labels, has.search(kind).unwrap_or(0), item_w~)
        match has.get(chosen) {
          Some(k) if k != kind => at.kind = k
          _ => ()
        }
      } else {
        c.text(thing_kind_name(kind), style=things_kind_alone) |> ignore
      }
      c.box(style=things_measure, id=room_id, fn() {
        @sf.input(c, "things/find/" + key, placeholder=@sf.t("web-main.things.find"), small=true, field=at.field) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  if shown.length() == 0 {
    rows.push(fn() {
      c.box(style=things_found_none.then(side), fn() { c.text(@sf.t("web-main.find.none"), style=things_none) |> ignore })
      |> ignore
    })
  } else if kind == "media" {
    // a grid, as many across as leave each 96 at least (3 at least), 4 apart
    let room = match c.laid_size(room_id) {
      Some((w, _)) if w > 0.0 => w
      _ => c.width - 32.0
    }
    let fits = ((room + things_gap) / (things_tile_least + things_gap)).to_int()
    let across = if fits < 3 { 3 } else { fits }
    let tile = (room - things_gap * (across - 1).to_double()) / across.to_double()
    let lines = (shown.length() + across - 1) / across
    for i in 0..<lines {
      rows.push(fn() {
        // (the room the tiles share: the field's over them, as wide as the sides leave whatever the tiles take)
        c.box(style=things_grid_line.then(side), fn() {
          c.box(style=things_grid_row, fn() {
            let end = if (i + 1) * across < shown.length() { (i + 1) * across } else { shown.length() }
            for j in (i * across)..<end {
              media_tile(c, src, r, thread, Some(shown[j]), tile, away)
            }
          })
          |> ignore
        })
        |> ignore
      })
    }
  } else {
    for t in shown {
      let tv = Some(t)
      rows.push(fn() { c.box(style=things_line.then(side), fn() { thing_row(c, src, r, thread, kind, tv, away) }) |> ignore })
    }
  }
  // not all of the chat is here yet: more may come, older ones
  if !whole {
    rows.push(fn() { c.box(style=things_more, fn() { @sf.spinner(c, size=16.0) |> ignore }) |> ignore })
  }
  rows.push(fn() { c.box(style=things_foot, fn() {  }) |> ignore })
  c.list("things/" + key + "/" + kind, rows.length(), 48.0, fn(i) { (rows[i])() }) |> ignore
}

///|
/// A thing held or right clicked (box `id`, said in message `seq`): its menu at the pointer, 在对话中查看 first (`away`),
/// then a link's copy (`url`: none for a file). The chat's info's pull requests have it too.
pub fn thing_menu(c : @ui.Ctx, id : Int, seq : Double, url : String, away : (Double) -> Unit) -> Unit {
  match c.menu_asked(id) {
    Some((x, y)) => {
      @sf.menu_held(c, "thing") |> ignore
      let menu : Array[@sf.MenuItem?] = [Some(@sf.menu_item_of(@sf.t("web-main.things.show"), fn() { away(seq) }, icon="chat"))]
      if url != "" {
        menu.push(Some(@sf.menu_item_of(@sf.t("common.link.copy"), fn() { copy_link(c, url) }, icon="copy")))
      }
      @sf.menu(menu, from=@sf.at_point(x, y))
    }
    None => ()
  }
}

///|
/// A link's address copied, said so.
fn copy_link(c : @ui.Ctx, url : String) -> Unit {
  c.copy_text(url)
  say(c, @sf.t("common.link.copied"))
}

///|
/// A picture or a video of the chat's, a square tile `side` across: its picture (a video's still with its play mark)
/// covering it, round as a message's file is. Pressed, the preview, a picture stepping through the chat's.
fn media_tile(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, t : Json?, side : Double, away : (Double) -> Unit) -> Unit {
  let a = @sfbase.attachment_of(field(t, "file").unwrap_or(Json::object({})))
  let owner = if a.owner != "" { a.owner } else { r.session }
  let id = c.id("things/tile/" + text(t, "key"))
  if c.clicked(id) {
    @sfbase.open_preview(r.station, owner, a, steps=InChat(Some(thread), r.session))
  }
  thing_menu(c, id, number(t, "seq"), "", away)
  let video = file_kind(a.name) == "video"
  let picture = if video {
    @sfbase.video_still(c, src, r.station, owner, a, r.station + "/" + owner + "/" + a.path)
  } else {
    (src.file)(r.station, owner, stored_name(a.path))
  }
  let likeness = @gallery.thumbhash_image(a.thumbhash).unwrap_or("")
  let b = c.box(style=things_tile.then(@ui.style(w=Fixed(side), h=Fixed(side))), id~, fn() {
    if picture != "" && picture != "!" {
      c.image(picture, w=Px(side), h=Px(side), fit=FitCover, bg=0L) |> ignore
    } else if likeness != "" {
      c.image(likeness, w=Px(side), h=Px(side), fit=FitCover, bg=0L, fade=false) |> ignore
    } else if picture == "!" {
      c.box(style=things_tile_none, fn() { @sf.icon(c, if video { "file-video" } else { "photo" }, size=20.0, color=@sf.theme().p.muted) |> ignore })
      |> ignore
    }
    if video {
      c.layer(fn() { c.box(style=things_tile_play, fn() { @sf.play_mark(c, things_play_side, @sf.video_shade) |> ignore }) |> ignore })
      |> ignore
    }
  })
  c.semantics(b, Button, id~, label=@sf.t(if video { "web-main.file.play" } else { "web-main.file.view" }, args=[("name", a.name)]))
}

///|
/// A file, a link or a pull request of the chat's, a row: its mark, what it is called (cut to its line) and a line
/// under it of what else is known of it, 在对话中查看 at its end; a link's card at its left while it is pointed at, its
/// copy and 在对话中查看 under it. Pressed, a file opens in the preview, a link and a pull
/// request in the browser.
fn thing_row(c : @ui.Ctx, src : Source, r : ChatRef, thread : Double, kind : String, t : Json?, away : (Double) -> Unit) -> Unit {
  let p = @sf.theme().p
  let id = c.id("things/row/" + kind + "/" + text(t, "key"))
  let seq = number(t, "seq")
  let url = text(t, "url")
  let ago = text(field(field(t, "time"), "createdAt"), "ago")
  let with_ago = fn(parts : Array[String]) {
    parts.push(ago)
    @sf.join_meta(parts)
  }
  let (name, meta) = match kind {
    "files" => {
      let f = field(t, "file")
      (text(f, "name"), with_ago([@sf.file_size(number(f, "size")), text(t, "by")]))
    }
    "pulls" => (pull_title(t), pull_meta(t))
    _ => {
      let n = count(t, "count")
      let site = text(t, "site")
      match text(t, "title") {
        "" => (site, with_ago([if n > 1 { "×" + n.to_string() } else { "" }]))
        title => (title, with_ago([site, if n > 1 { "×" + n.to_string() } else { "" }]))
      }
    }
  }
  if c.clicked(id) {
    if kind == "files" {
      let a = @sfbase.attachment_of(field(t, "file").unwrap_or(Json::object({})))
      @sfbase.open_preview(r.station, if a.owner != "" { a.owner } else { r.session }, a)
    } else {
      c.tell("things/open", fn() { @sfbase.open_link_in(src, url) })
    }
  }
  thing_menu(c, id, seq, url, away)
  // pointed at, a link's card over it, a pull request's as a message's link to it shows it (peeks.mbt)
  if kind != "files" {
    // (at its left: under it, it would cover the rows after it)
    web_peek(c, src, r.station, url, name, id, side=Left)
  }
  let show = c.id("things/show/" + kind + "/" + text(t, "key"))
  if c.clicked(show) {
    away(seq)
  }
  let b = c.box(style=things_row, id~, fn() {
    c.box(style=things_row_mark, fn() {
      match kind {
        "pulls" => pull_mark(c, t, 16.0)
        "files" => @sf.icon(c, "file", size=16.0, color=p.muted) |> ignore
        _ => @sf.icon(c, "link", size=16.0, color=p.muted) |> ignore
      }
    })
    |> ignore
    c.box(style=things_row_words, fn() {
      c.text(name, style=things_row_name) |> ignore
      if meta != "" {
        c.text(meta, style=things_row_meta) |> ignore
      }
    })
    |> ignore
    if @sf.icon_button(c, "chat", key="things/show/" + kind + "/" + text(t, "key"), round=true, label=@sf.t("web-main.things.show")) {
      away(seq)
    }
  })
  c.semantics(b, Button, id~, label=name)
}

///|
/// Things made up, for what the page shows while they are read (things_body in its bones): the kinds' choice and a few
/// rows.
fn things_sample(c : @ui.Ctx, side : @ui.Style) -> Unit {
  c.box(style=things_head.then(side), fn() {
    @sf.segmented(c, "things/sample", ["media", "files", "links"].map(fn(k) { thing_kind_name(k) + " 0" }), 0) |> ignore
  })
  |> ignore
  for n in [18, 24, 14, 20, 16] {
    c.box(style=things_line.then(side), fn() {
      c.box(style=things_row, fn() {
        c.box(style=things_row_mark, fn() { @sf.icon(c, "link", size=16.0, color=@sf.theme().p.muted) |> ignore }) |> ignore
        c.box(style=things_row_words, fn() {
          c.text(@sf.sample_words(n), style=things_row_name) |> ignore
          c.text(@sf.sample_words(10), style=things_row_meta) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// How far its rows stand in from the tab's sides (16, as the letters' messages do), the sheet's words' in a sheet.
// kept across runs: a value (no field of it changes)
let things_side : @ui.Style = @ui.css("px=S4")

///|
/// The kinds and the field over the rest: 12 over, 12 under, 8 apart.
// kept across runs: a value (no field of it changes)
let things_head : @ui.Style = @ui.css("w=Full pt=S3 pb=S3 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let things_kind_alone : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// A tile at least this across, the tiles this far apart.
let things_tile_least : Double = 96.0

///|
let things_gap : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let things_grid_line : @ui.Style = @ui.css("w=Full pb=S1")

///|
// kept across runs: a value (no field of it changes)
let things_grid_row : @ui.Style = @ui.css("row w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let things_measure : @ui.Style = @ui.css("w=Full")

///|
/// A tile: round as a message's file, the hover's grey under its picture while it comes; pointed at, a shade fainter.
// kept across runs: a value (no field of it changes)
let things_tile : @ui.Style = @ui.css("radius=Lg clip bg=Hover hovered{opacity=O85}")

///|
// kept across runs: a value (no field of it changes)
let things_tile_none : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let things_tile_play : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
let things_play_side : Double = 32.0

///|
/// A row's room in the list: 2 under it.
// kept across runs: a value (no field of it changes)
let things_line : @ui.Style = @ui.css("w=Full pb=S0_5")

///|
/// A row: 8 by 8 in (its mark at the rows' words' inset less 8), round as an option, the pointer's ground on it; its
/// mark, its two lines and 在对话里看 10 apart.
// kept across runs: a value (no field of it changes)
let things_row : @ui.Style = @ui.css("row w=Full py=S2 pl=S2 pr=S1 gap=S2_5 align=ACenter radius=Xl hovered{bg=Hover} pressed{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let things_row_mark : @ui.Style = @ui.css("w=S4 h=S4 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let things_row_words : @ui.Style = @ui.style(w=@sf.grow).then(@ui.css("gap=S0_5"))

///|
// kept across runs: a value (no field of it changes)
let things_row_name : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let things_row_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let things_found_none : @ui.Style = @ui.css("w=Full py=S3")

///|
// kept across runs: a value (no field of it changes)
let things_none : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let things_more : @ui.Style = @ui.css("row w=Full py=S2 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let things_foot : @ui.Style = @ui.css("w=Full h=S6")
