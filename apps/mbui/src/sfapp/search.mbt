// The search at the top of Home's list (ember apps/android chat/screens/Search.kt; web mobile/Home.tsx SearchField,
// SearchPage): a field at the list's top; tapped, the list goes up and away with the bars, the field comes up from
// where it was to the top (narrowing as 取消 comes in beside it), and under it what the words find in the workspace
// (the core's `search` topic, docs/search.md): the chats, the messages that have them (each opening its chat at it,
// the words marked there), then what the stations found besides, a section per kind. 查看更多 under a section lists
// that kind alone; 全部结果 (or back) every kind again. Under it all, the stations still answering and what the core
// says of the rest. 取消 (or back) puts the field back in the list.

///|
/// The search as it stands: open (its field off the list: `from`, its top in the window when tapped, and `wide`, its
/// width there), going back (`leaving`), the words typed and the kind alone looked at ("" every kind); the last view
/// read, kept while the next words are looked up.
priv struct Search {
  mut open : Bool
  mut leaving : Bool
  mut from : Double
  mut wide : Double
  mut query : String
  mut kind : String
  /// the field to take the focus (as it opens)
  mut focus : Bool
  /// the kind looked at changed: the list from its top
  mut to_top : Bool
  mut kept : SearchView?
  /// the topic's version `kept` was read at, and its query and kind
  mut kept_of : (Int, String, String)
  /// the field's words (its editor shows them)
  field : @ui.Field
}

///|
let search : Search = {
  open: false,
  leaving: false,
  from: 0.0,
  wide: 0.0,
  query: "",
  kind: "",
  focus: false,
  to_top: false,
  kept: None,
  kept_of: (-1, "", ""),
  field: @ui.Field::new(),
}

///|
/// A search open as the app starts (src/sffix's modes search-results and search-jobs, the Android app's
/// SearchResultsTest twins): the words typed, the kind alone ("" every kind); its field come up, the keyboard away.
let search_at_start : Ref[(String, String)?] = Ref(None)

///|
/// What a fixture mode opens of the search (open_fixture_mode).
fn open_search_mode(mode : String) -> Unit {
  if mode == "search-results" || mode == "search-results-dark" {
    search_at_start.val = Some(("登录", ""))
  } else if mode == "search-jobs" || mode == "search-jobs-dark" {
    search_at_start.val = Some(("登录", "job"))
  }
}

///|
/// The search the app starts with, opened as Home first builds.
fn search_start(c : @ui.Ctx) -> Unit {
  match search_at_start.val {
    Some((q, k)) => {
      search_at_start.val = None
      search.open = true
      search.query = q
      search.kind = k
      search_up(c).snap(1.0)
      search.field.set(q)
    }
    None => ()
  }
}

///|
fn search_reset() -> Unit {
  search_at_start.val = None
  search.open = false
  search.leaving = false
  search.from = 0.0
  search.wide = 0.0
  search.query = ""
  search.kind = ""
  search.focus = false
  search.to_top = false
  search.kept = None
  search.kept_of = (-1, "", "")
  search.field.set("")
}

///|
/// How long the field takes to come up (Ease.Arrive) and to go back (Ease.Standard), and how far the list goes up
/// meanwhile (Home.kt, Search.kt).
let search_in_ms : Double = 280.0

///|
let search_out_ms : Double = 240.0

///|
let search_list_rise : Double = 56.0

///|
/// The search's way up: 0 its field in the list, 1 at the top (Search.kt `up`, Home.kt `away`: the same times).
fn search_up(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "search/up", 0.0, global=true)
}

///|
/// How far Home is away under the search (0 none).
fn search_away(c : @ui.Ctx) -> Double {
  if search.open {
    search_up(c).get()
  } else {
    0.0
  }
}

///|
/// The bottom bar out of the search's way while it is open (Home.kt app.barAway): from the tap until it starts back.
fn search_bar_away() -> Bool {
  search.open && !search.leaving
}

///|
/// The field at the list's top tapped: the search opens from it (its top in the window, its width).
fn search_open(c : @ui.Ctx, from : Double, wide : Double) -> Unit {
  if search.open {
    return
  }
  search.open = true
  search.leaving = false
  search.from = from
  search.wide = wide
  search.focus = true
  let up = search_up(c)
  up.snap(0.0)
  up.animate(1.0, @motion.tween(search_in_ms, ease=Arrive))
}

///|
/// 取消 or back: the keyboard goes and the field goes back to the list (Search.kt close).
fn search_close(c : @ui.Ctx) -> Unit {
  if !search.open || search.leaving {
    return
  }
  search.leaving = true
  c.blur()
  search_up(c).animate(0.0, @motion.tween(search_out_ms, ease=Standard))
}

///|
/// The view for the words typed, or the last one read while they are looked up.
fn search_read(src : Source, scope : String) -> (SearchView?, Bool) {
  let params : Map[String, Json] = {
    "scope": Json::string(scope),
    "query": Json::string(search.query),
  }
  if search.kind != "" {
    params["kind"] = Json::string(search.kind)
  }
  let topic = (src.topic)("search", params)
  match topic.value {
    Some(v) => {
      let of = (topic.version, search.query, search.kind)
      if search.kept_of != of || search.kept is None {
        search.kept = Some(search_view(v))
        search.kept_of = of
      }
    }
    None => ()
  }
  (search.kept, topic.error is Some(_))
}

///|
/// A row of the search's list, in order.
priv enum SearchRow {
  /// over one kind alone: back to every kind
  AllKinds
  /// a line of grey words (none found, the core too old to search)
  Note(String)
  Head(String)
  Chat(FoundChat)
  Message(FoundMessage)
  Item(FoundItem)
  /// 查看更多 under a kind: that kind alone
  More(String)
  /// the stations still answering, or one that could not be searched (red)
  Wait(String, Bool)
  /// what the core says of the rest
  Said(String)
}

///|
fn search_rows(view : SearchView?, failed : Bool) -> Array[SearchRow] {
  let rows : Array[SearchRow] = []
  let words = search.query.trim(chars=" \t\n\r\u{3000}").to_owned() != ""
  if words && search.kind != "" {
    rows.push(AllKinds)
  }
  if words && view is None && failed {
    rows.push(Note(tr("android-chat.search.update")))
  }
  match view {
    Some(v) if words => {
      if v.chats.length() > 0 {
        rows.push(Head(tr("android-chat.search.chats")))
        for ch in v.chats {
          rows.push(Chat(ch))
        }
        if search.kind == "" && v.chats_more {
          rows.push(More("chat"))
        }
      }
      if v.messages.length() > 0 {
        rows.push(Head(tr("android-chat.search.messages")))
        for m in v.messages {
          rows.push(Message(m))
        }
        if search.kind == "" && v.messages_more {
          rows.push(More("message"))
        }
      }
      for g in v.groups {
        rows.push(Head(g.title))
        for it in g.items {
          rows.push(Item(it))
        }
        if search.kind == "" && g.more {
          rows.push(More(g.kind))
        }
      }
      let none = v.chats.length() == 0 &&
        v.messages.length() == 0 &&
        v.groups.iter().all(fn(g) { g.items.length() == 0 })
      if none && !v.reading {
        rows.push(Note(tr("android-chat.search.none")))
      }
      if v.reading {
        rows.push(Wait(v.wait_text.unwrap_or(tr("common.reading")), false))
      }
      for f in v.failing {
        rows.push(Wait(f, true))
      }
      match v.note {
        Some(n) => rows.push(Said(n))
        None => ()
      }
    }
    _ => ()
  }
  rows
}

// ── the look (Search.kt) ───────────────────────────────────────────────

///|
/// The page over Home: all of it, nothing under it touched through it.
// kept across runs: a value (no field of it changes)
let search_page_box : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Its bar: under the status bar 8 (the home bar's top), 16 either side, 8 under; 取消 12 after the field.
// kept across runs: a value (no field of it changes)
let search_bar_row : @ui.Style = @ui.css("row w=Full pl=S4 pr=S4 pt=S2 pb=S2 gap=S3 align=ACenter")

///|
/// Where the field rests at the top: the room 取消 leaves it.
// kept across runs: a value (no field of it changes)
let search_slot : @ui.Style = @ui.style(w=@sf.grow, h=@sf.search_field_h)

///|
/// The field (Search.kt SearchField, SearchPage's): 38 high, a capsule of the ink at 6%, 12 in, its icon 8 before
/// the words.
// kept across runs: a value (no field of it changes)
let search_field_box : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.search_field_h,
  px=S3,
  gap=S2,
  align=ACenter,
  radius=Full,
  bg=@sf.search_ground,
)

///|
/// The field at the list's top: 16 either side, 6 under it.
// kept across runs: a value (no field of it changes)
let search_field_line : @ui.Style = @ui.css("w=Full pl=S4 pr=S4 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let search_field_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let search_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let search_cancel : @ui.TextStyle = @ui.text_style(size=Xl, color=Link, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let search_list_box : @ui.Style = @ui.style(w=Full, h=@sf.grow)

///|
/// 查看更多 (MoreRow): 22 in, 10 over and under.
// kept across runs: a value (no field of it changes)
let search_more_row : @ui.Style = @ui.style(
  w=Full,
  pl=@sf.found_start,
  pr=S4,
  pt=S2_5,
  pb=S2_5,
)

///|
// kept across runs: a value (no field of it changes)
let search_link_words : @ui.TextStyle = @ui.text_style(size=Base, color=Link, wrap=false)

///|
/// 全部结果 (BackRow): 16 in, 10 over, 4 under; its chevron 4 before the words.
// kept across runs: a value (no field of it changes)
let search_back_row : @ui.Style = @ui.css("row w=Full pl=S4 pr=S4 pt=S2_5 pb=S1 gap=S1 align=ACenter")

///|
/// A line of grey words (SearchNote): 22 in, 16 over and under.
// kept across runs: a value (no field of it changes)
let search_note_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S4)

///|
// kept across runs: a value (no field of it changes)
let search_note_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
/// The stations still answering (WaitLine: 22 in, 12 over and under), one that could not be searched (6).
// kept across runs: a value (no field of it changes)
let search_wait_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S3)

///|
// kept across runs: a value (no field of it changes)
let search_failing_box : @ui.Style = @ui.style(w=Full, px=@sf.found_start, py=S1_5)

///|
/// What the core says of the rest: 13 on 18, 22 in, 12 over and under.
// kept across runs: a value (no field of it changes)
let search_said_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, w=Full)

///|
/// A message or a chat found by its words (HitRow): 66 high, 22 in on the left and 16 on the right.
// kept across runs: a value (no field of it changes)
let found_hit_row : @ui.Style = @ui.style(
  w=Full,
  h=@sf.found_row_h,
  pl=@sf.found_start,
  pr=S4,
  justify=JCenter,
)

///|
/// Something else found (ItemRow): 66 high with its line of words, 50 without; its icon 12 before what it is.
// kept across runs: a value (no field of it changes)
let found_item_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.found_row_h,
  pl=@sf.found_start,
  pr=S4,
  gap=S3,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let found_item_row_short : @ui.Style = found_item_row.then(@ui.style(h=@sf.found_row_short_h))

///|
// kept across runs: a value (no field of it changes)
let found_icon_box : @ui.Style = @ui.css("w=S5 h=S5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let found_column : @ui.Style = @ui.style(w=@sf.grow, justify=JCenter)

///|
/// A row's lines: its first 22 high, the one under it 20; what is beside 8 apart.
// kept across runs: a value (no field of it changes)
let found_line_22 : @ui.Style = @ui.style(row=true, w=Full, h=@sf.found_line_h, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let found_line_20 : @ui.Style = @ui.css("row w=Full h=S5 gap=S2 align=ACenter")


///|
/// A hit's line: 15 on 22, one line cut at its end; an item's: 14 on 20.
// kept across runs: a value (no field of it changes)
let found_hit_words : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=Fg, max_lines=1, w=Full)

///|
// kept across runs: a value (no field of it changes)
let found_item_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted, max_lines=1, w=Full)

///|
/// Under a hit: where it is (its chat), 14 on 20, muted, one line.
// kept across runs: a value (no field of it changes)
let found_under : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted, wrap=false, w=@sf.grow)

///|
/// Who and when, beside it: 12, muted.
// kept across runs: a value (no field of it changes)
let found_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// An item's title: 15 on 22, one line.
// kept across runs: a value (no field of it changes)
let found_title : @ui.TextStyle = @ui.text_style(size=Lg, leading=L7, color=Fg, wrap=false, w=@sf.grow)

// ── Home's field ───────────────────────────────────────────────────────

///|
/// The search at the list's top (Search.kt SearchField): a quiet field; tapped, the search opens from it. Not seen
/// while the search's field is it (one field at a time, flying from and back to here).
fn search_field(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let id = c.id("home-search")
  if c.clicked(id) {
    match c.rect_of(id) {
      Some((_, y, w, _)) => search_open(c, y, w)
      None => ()
    }
  }
  c.box(style=search_field_line, fn() {
    let f = c.box(style=search_field_box, id~, fn() {
      @sf.icon(c, "search", size=17.0, color=t.p.muted) |> ignore
      c.text(tr("android-chat.search.field"), style=search_field_words) |> ignore
    })
    if search.open {
      c.look(f, { ..@ui.still_look, alpha: 0.0 })
    }
  })
  |> ignore
}

// ── the page ───────────────────────────────────────────────────────────

///|
/// The search over Home (Search.kt SearchPage), while it is open.
fn search_page(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  if !search.open {
    return
  }
  let up = search_up(c)
  // back: from one kind to every kind first, then the search away
  if !search.leaving && app.nav.depth() == 1 {
    c.take_back(fn() {
      if search.kind != "" {
        search.kind = ""
        search.to_top = true
      } else {
        search_close(c)
      }
    })
  }
  let u = up.get()
  // gone back: the field is the list's again
  if search.leaving && !up.moving() {
    search.open = false
    search.leaving = false
    search.query = ""
    search.kind = ""
    search.kept = None
    search.kept_of = (-1, "", "")
    search.field.set("")
    return
  }
  let (view, failed) = search_read(src, w.id)
  let rows = search_rows(view, failed)
  // with several stations, an item found says which it is on
  let several = match (src.topic)("stations", { "scope": Json::string(w.id) }).value {
    Some(Array(a)) => a.length() > 1
    _ => false
  }
  let t = @sf.theme()
  c.layer(fn() {
    c.box(style=search_page_box, id=c.id("search/page"), fn() {
      // under the status bar (Search.kt: windowInsetsPadding(statusBars))
      if status_top() > 0.0 {
        c.box(style=@ui.style(w=Full, h=Fixed(status_top())), fn() {  }) |> ignore
      }
      c.box(style=search_bar_row, fn() {
        // as wide as the list's while there, narrowing to its room as it comes up (and back as it goes): 取消 comes
        // in with its right edge, not the field jumping between the two widths
        let slot = c.id("search/slot")
        let (room, rest_y) = match c.laid_rect(slot) {
          Some((_, y, rw, _)) => (rw, y)
          None => (search.wide, search.from)
        }
        c.box(style=search_slot, id=slot, fn() {
          c.layer(fn() {
            let now = dmax(if search.wide > 0.0 { search.wide + (room - search.wide) * u } else { room }, 0.0)
            let f = c.box(style=search_field_box.then(@ui.style(w=Fixed(now))), fn() {
              @sf.icon(c, "search", size=17.0, color=t.p.muted) |> ignore
              c.box(style=search_grow, fn() {
                let res = c.editor(
                  "search-field",
                  placeholder=tr("android-chat.search.field"),
                  font_size=16.0,
                  max_lines=1,
                  // the keyboard's search key (Search.kt: ImeAction.Search)
                  ime_action=@hostapi.ime_action_search,
                  plain=true,
                  color=t.p.text,
                  placeholder_color=t.p.muted,
                  caret_color=t.p.accent,
                  field=search.field,
                )
                if res.text != search.query {
                  search.query = res.text
                }
                if search.focus {
                  search.focus = false
                  c.focus_on(c.id("search-field"))
                }
              })
              |> ignore
            })
            c.look(f, { ..@ui.still_look, dy: (search.from - rest_y) * (1.0 - u) })
          })
          |> ignore
        })
        |> ignore
        let cancel = c.id("search/cancel")
        if c.clicked(cancel) && !search.leaving {
          search_close(c)
        }
        let cw = match c.laid_rect(cancel) {
          Some((_, _, cw, _)) => cw
          None => 0.0
        }
        let cb = c.box(id=cancel, fn() {
          c.text(tr("android-chat.search.cancel"), style=search_cancel) |> ignore
        })
        c.look(cb, { ..@ui.still_look, alpha: u, dx: (cw + 12.0) * (1.0 - u) })
      })
      |> ignore
      let lb = c.box(style=search_list_box, fn() {
        let key = "search/list"
        c.list(key, rows.length(), 66.0, fn(i) { search_row(c, src, rows[i], view, several) }) |> ignore
        // into one kind or back out of it: from the top
        if search.to_top {
          search.to_top = false
          c.list_scroll_to(key, 0)
        }
      })
      c.look(lb, { ..@ui.still_look, alpha: u })
    })
    |> ignore
  })
  |> ignore
}

///|
fn search_row(c : @ui.Ctx, src : Source, row : SearchRow, view : SearchView?, several : Bool) -> Unit {
  let t = @sf.theme()
  match row {
    AllKinds => {
      let id = c.id("search/all")
      if c.clicked(id) {
        search.kind = ""
        search.to_top = true
      }
      c.box(style=search_back_row, id~, fn() {
        @sf.icon(c, "chevron-left", size=16.0, color=t.p.accent) |> ignore
        c.text(tr("android-chat.search.all"), style=search_link_words) |> ignore
        // Search.kt BackRow: the row clickable
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    }
    Note(s) =>
      c.box(style=search_note_box, fn() { c.text(s, style=search_note_words) |> ignore }) |> ignore
    Head(s) => section_header(c, s) |> ignore
    Chat(ch) =>
      match ch.found {
        Some(found) => {
          let meta = @sf.join_meta([
            if ch.archived {
              tr("android-chat.search.archived")
            } else {
              ""
            },
            ch.item.ago,
          ])
          if hit_row(c, "c/" + ch.item.station + "/" + ch.item.id, found, ch.marks, meta, ch.item.title) {
            app.nav.push(Chat(chat_ref_of(ch.item)))
          }
        }
        None => @sfpages.chat_row(c, src, ch.item, "agents", found=true) |> ignore
      }
    Message(m) => {
      let meta = @sf.join_meta([m.by, m.ago])
      let key = "m/" + m.station + "/" + m.chat.session + "/" + m.seq.to_string()
      if hit_row(c, key, m.text, m.marks, meta, m.chat.title) {
        let words = match view {
          Some(v) => v.words
          None => []
        }
        open_chat_found(chat_ref_of(m.chat), m.seq, words)
      }
    }
    Item(it) =>
      if item_row(c, it, several) {
        open_found(it)
      }
    More(kind) => {
      let id = c.id("search/more/" + kind)
      if c.clicked(id) {
        search.kind = kind
        search.to_top = true
      }
      c.box(style=search_more_row, id~, fn() {
        c.text(tr("android-chat.search.more"), style=search_link_words) |> ignore
        // Search.kt MoreRow: the row clickable
        @motion.ripple(c, id, 0.0)
      })
      |> ignore
    }
    Wait(s, error) =>
      c.box(style=if error { search_failing_box } else { search_wait_box }, fn() {
        @sf.wait_line(c, s, key="search", error~)
      })
      |> ignore
    Said(s) =>
      c.box(style=search_wait_box, fn() { c.text(s, style=search_said_words) |> ignore }) |> ignore
  }
}


///|
/// A message or a chat found by words (HitRow): what has them on its first line, the row's width (they bold, stroked
/// under); where it is (its chat) under it, who and when beside that. True when tapped.
fn hit_row(
  c : @ui.Ctx,
  key : String,
  text : String,
  marks : Array[(Int, Int)],
  meta : String,
  under : String,
) -> Bool {
  let t = @sf.theme()
  let id = c.id("search/hit/" + key)
  c.box(style=found_hit_row, id~, fn() {
    c.box(style=found_line_22, fn() {
      @sf.found_line(c, key, text, marks, found_hit_words, t.p.text)
    })
    |> ignore
    c.box(style=found_line_20, fn() {
      c.text(under, style=found_under) |> ignore
      if meta != "" {
        c.text(meta, style=found_meta) |> ignore
      }
    })
    |> ignore
    // Search.kt HitRow: the row clickable
    @motion.ripple(c, id, 0.0)
  })
  |> ignore
  c.clicked(id)
}


///|
/// Something found besides a chat or a message (ItemRow): its kind's icon (a station its own mark), what it is, where
/// (its station, with several) and when, over its line that has the words. True when tapped.
fn item_row(c : @ui.Ctx, it : FoundItem, several : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("search/item/" + it.key)
  c.box(style=if it.text == "" { found_item_row_short } else { found_item_row }, id~, fn() {
    c.box(style=found_icon_box, fn() {
      if it.kind == "station" {
        @sf.station_mark(c, it.station_emoji, it.station_icon, 18.0, t.p.muted, none="server")
      } else {
        @sf.icon(
          c,
          if it.kind == "file" && it.dir { "folder" } else { @sf.kind_icon(it.kind) },
          size=18.0,
          color=t.p.muted,
        )
        |> ignore
      }
    })
    |> ignore
    c.box(style=found_column, fn() {
      c.box(style=found_line_22, fn() {
        c.text(it.title, style=found_title) |> ignore
        let meta = @sf.join_meta([
          if several && it.kind != "station" {
            it.station_name
          } else {
            ""
          },
          it.ago,
        ])
        if meta != "" {
          c.text(meta, style=found_meta) |> ignore
        }
      })
      |> ignore
      if it.text != "" {
        c.box(style=found_line_20, fn() {
          @sf.found_line(c, "i/" + it.key, it.text, it.marks, found_item_words, t.p.text)
        })
        |> ignore
      }
    })
    |> ignore
    // Search.kt ItemRow: the row clickable
    @motion.ripple(c, id, 0.0)
  })
  |> ignore
  c.clicked(id)
}

