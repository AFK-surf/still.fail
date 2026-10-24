// Home (ember apps/android chat/screens/Home.kt): the workspace's chats as the `chats` view lists them, newest first
// and grouped by day, under a top bar (settings · the workspace, its switcher · the filter). A row (ChatRowBody): the
// chat's state a mark before its title (bold while something in it is unread), its station's mark, under it where it
// stands or the last thing said, who is in it small at the second line's end (RowPicture.kt); the time while it is
// held. Its states: the rows to come breathing while it is read, what is wrong over them, and an empty list's words.

///|
/// Home's list items, in order.
priv enum Item {
  /// room for the top bar over the list
  Top
  Search
  /// what the last update brought, until it is seen (home_news.mbt)
  News
  Wait(Int, ListNote?, String?)
  Empty
  /// the jobs left up a long while (OpenJobs.kt: sheets.mbt open_jobs)
  OpenJobs
  Header(String)
  Row(ChatItem)
  Foot
}

///|
/// The top bars' height under the status bar (a place's, TopGlassBar, and a chat's, BarFrame: TopBarHeight), what is in
/// them in its middle; the list starts under it. One length, on the device's pixels at once: 8 + 34 + 8 and 5 + 40 + 5,
/// each on whole pixels, can come out a pixel apart (at 2.85 pixels a point, 143 and 142), the two bars' lines apart
/// as a chat is swiped back.
let bar_h : Double = 50.0

///|
/// The lists Home follows, side by side in this order (Home.kt: all, mine, watching), and how long switching from one to
/// another slides (Home.kt `shift`: tween(240) on FastOutSlowIn).
// kept across runs: a table, never written
let home_filters : Array[String] = ["all", "mine", "watching"]

///|
let home_filter_ms : Double = 240.0

///|
/// Home (Home.kt HomeScreen): its lists side by side, the one in view slid to when the filter switches, nothing to wait
/// for once they are read; the top bar over them. The lists other than the one in view are read from when the filter's
/// menu opens (what switching would show is there by the time one is picked).
fn home_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  ignore(all)
  search_start(c)
  let filter = filter_of(src, w.id)
  let at = home_filters.search(filter).unwrap_or(0)
  let shift = @motion.animate(c, "home-filter/" + w.id, at.to_double(), spec=@motion.tween(home_filter_ms, ease=Standard))
  let (view, _) = chats_of(src, w.id, filter)
  match view {
    Some(v) => open_listed(v)
    None => ()
  }
  // the others read once switching to them is in sight
  if app.menu {
    for f in home_filters {
      chats_of(src, w.id, f) |> ignore
    }
  }
  // under the search (search.mbt): the lists up 56 and away, the bar faded (Home.kt `away`)
  let away = search_away(c)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    for k, f in home_filters {
      let off = k.to_double() - shift
      if off > -1.0 && off < 1.0 {
        let pane = c.layer(fn() { home_pane(c, src, w, f, f == filter) })
        if off != 0.0 || away > 0.0 {
          c.look(pane, { ..@ui.still_look, alpha: 1.0 - away, dx: off * c.width, dy: -search_list_rise * away })
        }
      }
    }
    let bar = c.layer(fn() {
      top_bar(c, src, w, view, filter, invited)
    })
    if away > 0.0 {
      c.look(bar, { ..@ui.still_look, alpha: 1.0 - away })
    }
    search_page(c, src, w)
  })
  |> ignore
}

///|
/// One of Home's lists (Home.kt ChatPane): its rows by day under the top bar's room, or why there are none; `current`:
/// the one in view (whose rows the keys walk, home_rows).
fn home_pane(c : @ui.Ctx, src : Source, w : Workspace, filter : String, current : Bool) -> Unit {
  let (view, error) = chats_of(src, w.id, filter)
  let list : Array[Item] = [Top]
  match view {
    None => {
      // (even while the list is read)
      if news_of(src) is Some(_) {
        list.push(News)
      }
      list.push(Wait(7, None, error))
    }
    Some(v) => {
      let empty = match v.note {
        Some(n) => n.empty
        None => false
      }
      if !empty {
        list.push(Search)
      }
      if news_of(src) is Some(_) {
        list.push(News)
      }
      match v.note {
        Some(n) if n.reading || n.failing.length() > 0 =>
          list.push(Wait(if n.reading { 7 } else { 4 }, Some(n), None))
        _ => ()
      }
      if empty {
        list.push(Empty)
      }
      // what is left up a long while on the stations: nothing while there is none
      if items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups").length() > 0 {
        list.push(OpenJobs)
      }
      // while a finger is on the list or it moves, the rows keep their places (ListMotion.kt HeldOrder)
      let key = "home/" + w.id + "/" + filter
      let (_, _, down) = c.pointer()
      let days = held_order(key, v.days, down || c.list_moving(key))
      for d in days {
        list.push(Header(d.label))
        for item in d.items {
          list.push(Row(item))
        }
      }
    }
  }
  list.push(Foot)
  let lead = match view {
    Some(v) => v.leading
    None => "agents"
  }
  let key = "home/" + w.id + "/" + filter
  // the rows move as the list changes (ListMotion.kt): by their keys
  match view {
    Some(v) => if current { note_marks(c, v) }
    None => ()
  }
  let keys = list.map(item_key)
  // only the days and rows count (ListMotion.kt update): the list's first rows, after it waited, come as they are,
  // not growing in (nothing moves the first time)
  let moved = keys.filter(fn(k) { k.has_prefix("h/") || k.has_prefix("r/") })
  let row_keys = moved.map(fn(k) { key + "\u{1}" + k })
  if current {
    home_rows.val = row_keys
  }
  let lid = @motion.list_keys(c, key, row_keys, liftable=fn(k) { !k.contains("\u{1}h/") })
  c.list(key, list.length(), 66.0, fn(i) {
    match list[i] {
      // under the top bar, the status bar's height and its own (Home.kt padding: topBar + 8)
      Top => c.box(h=Px(status_top() + bar_h + 8.0), fn() {  }) |> ignore
      Search => search_field(c)
      News => changelog_news(c, src)
      Wait(n, note, error) => waiting(c, n, note, error)
      Empty =>
        match view {
          Some(v) => empty(c, v, filter)
          None => ()
        }
      OpenJobs => open_jobs(c, src, w)
      Header(label) => moving(c, lid, key, keys[i], section_header(c, label))
      Row(item) => {
        let name = key + "\u{1}" + keys[i]
        moving(
          c,
          lid,
          key,
          keys[i],
          chat_row(c, src, item, lead, lifted=@motion.lifted(c, lid, name), unghost=fn(off) {
            @motion.list_unghost(c, lid, name, off~)
          }),
        )
      }
      // room for the bottom bar over the navigation bar (Home.kt: navigationBars + LocalBarRoom); on a wide screen,
      // whose corners have 奏 and 令 over the list, a little
      Foot => c.box(h=Px(nav_foot() + bar_room_now()), fn() {  }) |> ignore
    }
  })
  |> ignore
  // the list's first time with its rows: at its first row, the search above it out of view, there once scrolled to
  // (Home.kt top: as the list first read, which the search comes in over)
  if !home_placed.contains(key) {
    home_placed[key] = true
    if list.search_by(fn(it) { it is Search }) is Some(at) {
      c.list_scroll_to(key, at + 1, offset=-(status_top() + bar_h + 8.0))
    }
  }
}

///|
/// The top bar (PlacePage.kt TopGlassBar), over the list's top: settings, the workspace's name (its switcher, a
/// dot when another has something waiting), the filter.
fn top_bar(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  view : ChatsView?,
  filter : String,
  invited : Bool,
) -> Unit {
  let t = @sf.theme()
  // frosted glass over the list (the page's paper at 70% over a 24px blur), no line under it
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    // under the status bar (PlacePage.kt TopGlassBar: windowInsetsPadding(statusBars), then TopBarHeight)
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="home-settings", said=tr("android-chat.home.settings")) {
        app.nav.push(Settings)
      }
      let wid = c.id("home-workspace")
      if c.clicked(wid) {
        raise_sheet(Workspaces)
      }
      c.box(dir=Row, w=Fill(1.0), h=Px(34.0), gap=6.0, align=ACenter, id=wid, fn() {
        // the name as long as there is room for it
        let room = c.width - 16.0 * 2.0 - 34.0 * 2.0 - 10.0 * 2.0 - 6.0 * 2.0 - 16.0 - 10.0
        c.box(max_w=dmax(room, 40.0), fn() {
          top_bar_title(c, w.name) |> ignore
        })
        |> ignore
        let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
        match field(marks.value, "others") {
          Some(String(tone)) => workspace_mark(c, tone, text(marks.value, "othersLabel"))
          _ =>
            if invited {
              c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.accent, label=tr("android-chat.home.invited"), fn() {  })
              |> ignore
            }
        }
        @sf.icon(c, "chevron-down", size=16.0, color=t.p.muted) |> ignore
      })
      |> ignore
      // a newer build that brings something (updates.mbt): its key, or how far it has come
      update_button(c, src)
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station
      match view {
        Some(v) if v.stations > 0 =>
          if nav_button(
              c,
              "filter",
              20.0,
              key="home-filter",
              color=if filter != "all" { t.p.accent } else { t.p.text },
              said=fill("android-chat.home.filter.label", [
                (
                  "filter",
                  tr(
                    match filter {
                      "mine" => "android-chat.home.filter.mine"
                      "watching" => "android-chat.home.filter.watching"
                      _ => "android-chat.home.filter.all"
                    },
                  ),
                ),
              ]),
            ) {
            app.menu = true
          }
        _ => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The name in a top bar (PlacePage.kt TopBarTitle): 24 bold, its letters 0.4 closer, on one line.
fn top_bar_title(c : @ui.Ctx, s : String) -> Int {
  c.text(s, size=24.0, weight=700, color=@sf.theme().p.text, wrap=false, line=30.0, tracking=top_title_tracking)
}

///|
let top_title_tracking : Double = -0.4

///|
/// A round button in a bar (Parts.kt NavButton): 34 across, the icon alone, no disc behind it (a ground while
/// pressed). True on the frame after it was pressed.
fn nav_button(
  c : @ui.Ctx,
  icon : String,
  size : Double,
  key~ : String,
  color? : Int64,
  said? : String,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    id~,
    fn() {
      @sf.icon(c, icon, size~, color=color.unwrap_or(t.p.text)) |> ignore
      // Parts.kt NavButton: clip(CircleShape).clickable
      @motion.ripple(c, id, 17.0)
    },
  )
  // what it is to a screen reader, where the page says (a Box's contentDescription round it)
  match said {
    Some(s) => c.semantics(b, Button, id~, label=s)
    None => ()
  }
  c.clicked(id)
}

///|
/// A day's heading (Parts.kt SectionHeader).
fn section_header(c : @ui.Ctx, label : String) -> Int {
  let t = @sf.theme()
  c.box(pl=20.0, pr=20.0, pt=14.0, pb=6.0, fn() {
    c.text(label, size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0)
    |> ignore
  })
}

///|
/// An item's key in the list (ListMotion.kt rowKey, dayKey): a row by its name, a day by its heading.
fn item_key(it : Item) -> String {
  match it {
    Top => "top"
    Search => "search"
    News => "changelog-news"
    Wait(_, _, _) => "wait"
    Empty => "empty"
    OpenJobs => "open-jobs"
    Header(label) => "h/" + label
    Row(item) => "r/" + row_name(item)
    Foot => "foot"
  }
}

///|
/// Home's rows and days' headings as last built, by their motion keys (home_rest).
let home_rows : Ref[Array[String]] = Ref([])

///|
/// When Home's rows and headings are in their places and in (the frames' clock: the latest of their moves' and
/// entrances' ends, @motion.layout_rest; -1 when all are at rest): what a test of the app over its pages
/// (src/sfreplay) runs to at its end.
pub fn home_rest() -> Double {
  let mut e = -1.0
  for k in home_rows.val {
    let r = @motion.layout_rest(k)
    if r > e {
      e = r
    }
  }
  e
}

///|
/// How a row or day's heading moves as the list changes (Home.kt Moving, Leaving): from where it was to where it is
/// on the MOVE spring (a little late while closing over one gone), growing in when new (240 ms after 100, Ease.Out,
/// from 90% and nothing), and one gone drawn where it was as it shrinks to 90% and fades (200 ms, CSS's ease-out);
/// one that went ahead of others passes over them.
fn moving(c : @ui.Ctx, lid : Int, list : String, key : String, i : Int) -> Unit {
  @motion.layout(
    c,
    i,
    list + "\u{1}" + key,
    spec=@motion.row_spring,
    enter=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(240.0, ease=Out, delay=100.0)),
    exit=@motion.trans(fade=0.0, scale=0.9, spec=@motion.tween(200.0, ease=CssOut)),
  )
  if @motion.lifted(c, lid, list + "\u{1}" + key) >= 0.0 {
    c.put_over(i)
  }
}

///|
/// The mark each chat has had (ListMotion.kt MarksSeen), from the whole list: a mark that came while the list shows
/// pops in, its pop set out as it comes (mark_pop_of); one there from the first does not.
let marks_seen : Map[String, String] = {}

///|
fn note_marks(c : @ui.Ctx, v : ChatsView) -> Unit {
  for d in v.days {
    for item in d.items {
      let k = row_name(item)
      let tone = row_tone(item)
      match marks_seen.get(k) {
        None => marks_seen[k] = tone
        Some(was) if was != tone => {
          marks_seen[k] = tone
          let p = mark_pop_of(c, k, tone)
          p.snap(0.0)
          p.animate(1.0, @motion.tween(mark_pop_ms, ease=CssOut))
        }
        _ => ()
      }
    }
  }
}

///|
/// The list read the first time (the library's Waiting: @sf.waiting, its rows): rows to come breathing, what is wrong
/// over them in red (the shapes then still); what it waits on said only to a screen reader while it reads.
fn waiting(c : @ui.Ctx, n : Int, note : ListNote?, error : String?) -> Unit {
  @sf.waiting(
    c,
    shape=Rows,
    count=n,
    text=tr("common.reading"),
    error=error.unwrap_or(""),
    note?=match note {
      Some(nt) => Some({ reading: nt.reading, text: nt.text.unwrap_or(""), failing: nt.failing })
      None => None
    },
  )
}

///|
/// Nothing in the list (Home.kt Empty): with no station yet, adding the first one is the page; else the
/// illustration and what to do.
fn empty(c : @ui.Ctx, v : ChatsView, filter : String) -> Unit {
  let t = @sf.theme()
  if v.stations == 0 && filter == "all" {
    c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_no_station_dark"
        } else {
          "illus_no_station"
        },
        240.0,
      )
      |> ignore
      c.text(
        tr("android-settings.station.first"),
        size=17.0,
        weight=600,
        color=t.p.text,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(
        tr("android-settings.station.firstNote"),
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
    })
    |> ignore
    return
  }
  c.box(w=Fill(1.0), padx=30.0, pady=20.0, gap=8.0, align=ACenter, fn() {
    @sf.drawable(
      c,
      if t.dark {
        "illus_new_chat_dark"
      } else {
        "illus_new_chat"
      },
      240.0,
    )
    |> ignore
    if filter == "mine" {
      c.text(tr("android-chat.home.empty.mine"), size=14.0, color=t.p.muted) |> ignore
    } else if filter == "watching" {
      c.text(tr("android-chat.home.empty.watching"), size=14.0, color=t.p.muted)
      |> ignore
    } else {
      c.text(
        if v.stations > 1 {
          tr("android-chat.home.empty.many")
        } else {
          tr("android-chat.home.empty.one")
        },
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(tr("android-chat.newChat"), size=14.0, color=@sf.link_ink()) |> ignore
    }
  })
  |> ignore
}

///|
/// The marks' colours (SettingParts.kt MarkBlue, MarkRed; Home.kt MarkYellow).
let mark_blue : Int64 = 0x3B82F6FFL

///|
let mark_red : Int64 = 0xE5484DFFL

///|
let mark_yellow : Int64 = 0xF2B01EFFL

///|
/// What a workspace has waiting (SettingParts.kt WorkspaceMark): `alert` a red dot with a soft halo, `wait` a blue
/// ring, `done` a blue dot.
fn workspace_mark(c : @ui.Ctx, tone : String, label : String) -> Unit {
  // (what it says to a screen reader: SettingParts.kt WorkspaceMark's contentDescription)
  c.box(w=Px(10.0), h=Px(10.0), label~, fn() {
    match tone {
      "alert" => halo_dot(c, mark_red)
      "wait" => ring(c, mark_blue)
      _ => dot(c, mark_blue)
    }
  })
  |> ignore
}

///|
/// A dot 8 across in the middle of a mark's 10.
fn dot(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=color, tx=1.0, ty=1.0, fn() {  })
  |> ignore
}

///|
/// A red dot with its halo (the halo 14 across, past the mark's edges).
fn halo_dot(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(
    w=Px(14.0),
    h=Px(14.0),
    radius=7.0,
    bg=@sf.alpha(color, 0.25),
    tx=-2.0,
    ty=-2.0,
    align=ACenter,
    justify=JCenter,
    fn() { c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=color, fn() {  }) |> ignore },
  )
  |> ignore
}

///|
/// A hollow ring 9 across, 2 thick.
fn ring(c : @ui.Ctx, color : Int64) -> Unit {
  c.box(
    w=Px(9.0),
    h=Px(9.0),
    radius=4.5,
    border=2.0,
    border_color=color,
    tx=0.5,
    ty=0.5,
    fn() {  },
  )
  |> ignore
}

///|
/// A chat's state, a mark before its title (Home.kt ChatMark): a blue dot done and unread, a red one with a soft
/// halo to be seen now, yellow spokes stepping round at work, a blue ring when something waits on the viewer, a
/// grey one when only on others.
fn chat_mark(c : @ui.Ctx, tone : String, pop? : String = "") -> Unit {
  let t = @sf.theme()
  // what it says to a screen reader (Home.kt ChatMark's contentDescription)
  let label = tr(
    match tone {
      "done" => "android-chat.home.mark.done"
      "alert" => "android-chat.home.mark.alert"
      "wait" => "android-chat.home.mark.wait"
      "other" => "android-chat.home.mark.other"
      _ => "android-chat.home.mark.busy"
    },
  )
  let mark = c.box(w=Px(10.0), h=Px(10.0), label~, fn() {
    match tone {
      "done" => dot(c, mark_blue)
      "alert" => halo_dot(c, mark_red)
      "wait" => ring(c, mark_blue)
      "other" => ring(c, t.p.subtle)
      // yellow spokes stepping round (Spokes.kt)
      _ => @sf.spokes(c, 10.0, mark_yellow) |> ignore
    }
  })
  // one that came while the list shows pops in (Home.kt ChatMark: 320 ms, CSS's ease-out, 0 → 1.3 at 60% → 1)
  if pop != "" {
    let v = mark_pop_of(c, pop, tone).get()
    if v < 1.0 {
      let s = if v < 0.6 { 1.3 * v / 0.6 } else { 1.3 - 0.3 * (v - 0.6) / 0.4 }
      c.look(mark, @ui.look(scale=s))
    }
  }
}

///|
/// The pop's length.
let mark_pop_ms : Double = 320.0

///|
/// A chat's pop of its mark `tone` (whole, 1, unless one set out as the mark came: note_marks).
fn mark_pop_of(c : @ui.Ctx, chat : String, tone : String) -> @motion.Anim {
  @motion.anim(c, "mark-pop/" + chat + "/" + tone, 1.0, global=true)
}

///|
/// How long a row is held before its time shows (a long press).
let hold_ms : Double = 450.0

///|
/// A row's height (ChatRowBody), its title's line and its second line's (the state line's), the two in its middle.
let chat_row_h : Double = 66.0

///|
let chat_title_h : Double = 22.0

///|
let chat_line_h : Double = 20.0

///|
/// How far down a row its second line starts.
let chat_line_top : Double = (chat_row_h - chat_title_h - chat_line_h) / 2.0 + chat_title_h

///|
/// A row let go without opening its chat (a scroll, a hold): what it read ahead let go too, unless its page is open.
fn unprime(src : Source, r : ChatRef) -> Unit {
  if !src.read_only && !readings.contains(r.station + "\u{1}" + r.session) {
    (src.leave)("chat", chat_params(r))
  }
}

///|
/// The message a tap `ty` down the window opens a row's chat at, the row's top at `ry`: on its state line while the line
/// names one (Home.kt ChatRow onTap: `stateAbout`) and nothing in the chat is unread (then at the unread line, as any
/// tap); else None, where it opens.
fn row_opens_at(item : ChatItem, ry : Double, ty : Double) -> Double? {
  match item.state_about {
    Some(seq) if !item.unread && ty >= ry + chat_line_top && ty < ry + chat_line_top + chat_line_h => Some(seq)
    _ => None
  }
}

///|
/// A row (Home.kt ChatRow, ChatRowBody): 66 high, two lines; pressed, on the ground it has held (a found one rippled);
/// tapped, its chat is pushed (at the message its state line names, tapped there), or given to `opened` (the latest
/// chats under a chat's composer on a device half open: tabletop.mbt).
fn chat_row(
  c : @ui.Ctx,
  src : Source,
  item : ChatItem,
  lead : String,
  lifted? : Double = -1.0,
  found? : Bool = false,
  opened? : (ChatRef) -> Unit,
  unghost? : (Bool) -> Unit = fn(_) {  },
) -> Int {
  let t = @sf.theme()
  let id = c.id("row/" + row_name(item))
  // a chat the search found (Search.kt: ChatRowBody alone, a tap its chat): not held, archived nor swiped
  let pressed = c.pressed(id) && !found
  let r : ChatRef = {
    station: item.station,
    session: item.session,
    title: item.title,
    station_name: item.station_name,
  }
  if pressed && app.held != id {
    app.held = id
    app.held_long = false
    // pressed, the chat is read ahead of its page (Home.kt ChatRow onPress: AppState.prime)
    if !src.read_only {
      (src.topic)("chat", chat_params(r)) |> ignore
    }
  }
  // held hold_ms (a frame asked for when it will have been)
  let held = @kit.after(c, "row-hold/" + row_name(item), pressed && app.held == id, hold_ms)
  if held {
    app.held_long = true
    // held long: what can be done to the chat (home_menu.mbt)
    row_held(c, id, item)
  }
  if c.clicked(id) {
    // a long press is not a tap
    let long = app.held == id && app.held_long
    app.held = 0
    if long {
      unprime(src, r)
    } else if opened is Some(f) {
      f(r)
    } else {
      // on its state line while it names a message (and nothing in it is unread: then at the unread line, as any
      // tap), at that message
      let at = match (c.rect_of(id), c.tapped_anywhere()) {
        (Some((_, ry, _, _)), Some((_, ty))) => row_opens_at(item, ry, ty)
        _ => None
      }
      match at {
        Some(seq) => open_chat_at(r, seq)
        None => app.nav.push(Chat(r))
      }
    }
  } else if !pressed && app.held == id {
    app.held = 0
    unprime(src, r)
  }
  let dim = if item.offline is Some(_) { 0.45 } else { 1.0 }
  let archivable = item.archivable && item.offline is None && !item.pending && !found
  let busy = row_busy(item)
  let failed = row_failed(c, item)
  let row = fn(tx : Double) -> Int {
    // pressed and where it rests (not swiped over its 归档)
    let pressed_here = pressed && tx == 0.0
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(chat_row_h),
      tx~,
      pl=22.0,
      pr=16.0,
      gap=6.0,
      align=ACenter,
      // held, its menu open, or pressed (once the press is not the list's: Ctx::pressed): Home.kt ChatRowBody
      // `held || pressed`, as PlaceRow's pressed ground
      bg=if held || row_menu_open(item) || pressed_here {
        @sf.alpha(t.p.text, 0.05)
      } else if lifted >= 0.0 {
        // going ahead of others, on a ground of its own over them: held to 60% of its 480 ms, then fading
        let p = lifted / 480.0
        @sf.alpha(@sf.over(t.p.bg, @sf.alpha(t.p.text, 0.06)), if p < 0.6 { 1.0 } else { 1.0 - (p - 0.6) / 0.4 })
      } else if tx != 0.0 {
        // swiped, over its 归档 (home_menu.mbt swipe_to_archive)
        t.p.bg
      } else {
        0L
      },
      id~,
      fn() {
        if archivable {
          archive_chip(c, src, item, busy)
        }
        c.box(w=Fill(1.0), justify=JCenter, opacity=if item.settled { 0.45 } else { 1.0 }, fn() {
          c.box(dir=Row, w=Fill(1.0), h=Px(chat_title_h), gap=8.0, align=ACenter, fn() {
            let tone = row_tone(item)
            if tone != "" {
              chat_mark(c, tone, pop=row_name(item))
            }
            c.box(w=Fill(1.0), opacity=dim, fn() {
              c.text(
                item.title,
                size=16.0,
                weight=if item.unread { 600 } else { 400 },
                color=t.p.text,
                wrap=false,
                line=22.0,
              )
              |> ignore
            })
            |> ignore
            if @sf.has_station_mark(item.station_emoji, item.station_icon) {
              // (read as its station's name: Home.kt's contentDescription)
              c.box(opacity=dim, label=item.station_name, fn() {
                @sf.station_mark(c, item.station_emoji, item.station_icon, 12.0, t.p.muted)
              })
              |> ignore
            }
            if busy || failed {
              // its pin or archive under way: a spinner; failed a moment ago: a red mark (DoingMark)
              c.box(w=Px(14.0), align=ACenter, fn() {
                if busy {
                  @sf.spinner(c, size=12.0) |> ignore
                } else {
                  @sf.icon(c, "info", size=12.0, color=t.p.red) |> ignore
                }
              })
              |> ignore
            } else if item.offline is Some(_) || item.reconnecting is Some(_) {
              c.box(w=Px(14.0), align=ACenter, label=match item.offline {
                Some(o) => o
                None => item.reconnecting.unwrap_or("")
              }, fn() {
                @sf.icon(c, "unplug", size=13.0, color=t.p.subtle) |> ignore
              })
              |> ignore
            } else if item.connect {
              c.box(
                w=Px(14.0),
                align=ACenter,
                label=if item.origin_text != "" { item.origin_text } else { "Slack" },
                fn() { @sf.slack_mark(c, 13.0) |> ignore },
              )
              |> ignore
            }
          })
          |> ignore
          c.box(dir=Row, w=Fill(1.0), h=Px(chat_line_h), gap=8.0, align=ACenter, fn() {
            c.box(w=Fill(1.0), opacity=dim, fn() {
              let state = match item.state_text {
                Some(s) => Some(s)
                None => item.decision_text
              }
              match state {
                Some(s) =>
                  state_line(c, s, lead=item.state_lead, lead_text=item.state_lead_text, rest=item.state_rest, alert=item.unsent)
                None =>
                  match item.last {
                    Some(l) =>
                      c.text(l, size=14.0, color=t.p.muted, wrap=false, line=20.0)
                      |> ignore
                    None => ()
                  }
              }
            })
            |> ignore
            // held, or its menu open: when it was last active (Home.kt ChatRowBody `held || menuOpen`)
            if held || row_menu_open(item) {
              c.text(item.ago, size=12.0, color=t.p.subtle, wrap=false) |> ignore
            } else {
              c.box(opacity=dim, fn() { row_aside(c, src, item, lead) }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
        // a chat the search found, or in the latest chats: ChatRowBody's clickable (Search.kt)
        if found {
          @motion.ripple(c, id, 0.0)
        }
      },
    )
  }
  if archivable {
    swipe_to_archive(c, src, item, busy, row, unghost~)
  } else {
    row(0.0)
  }
}

///|
/// A small 归档 at a row's start, for a chat with nothing left in it: a tap archives it (home_menu.mbt archive_from_row), not
/// while its pin or archive is under way.
fn archive_chip(c : @ui.Ctx, src : Source, item : ChatItem, busy : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("archive/" + row_name(item))
  if c.clicked(id) && !busy {
    archive_from_row(src, item)
  }
  let chip = c.box(
    padx=10.0,
    pady=4.0,
    radius=12.0,
    bg=t.p.chip,
    id~,
    fn() {
      c.text(
        tr("android-chat.archive"),
        size=12.0,
        weight=500,
        color=t.p.muted,
        wrap=false,
        line=16.0,
      )
      |> ignore
      // Home.kt: 归档, clip(RoundedCornerShape(50)).clickable(enabled = !busy)
      if !busy {
        @motion.ripple(c, id, 12.0)
      }
    },
  )
  // (Home.kt: 归档「title」 to a screen reader)
  c.semantics(chip, Button, id~, label=fill("android-chat.archive.named", [("title", item.title)]), disabled=busy)
}

///|
/// Where the chat stands, in its last message's place (Home.kt StateLine), by what the core says leads its words
/// (`lead`: ChatItem's state_lead, `lead_text` its card's lead word, `rest` what follows the lead): needs the viewer a
/// bell, in ink; waiting the wait mark, watching the watch before its words, done a check, each where the title's mark
/// is; a card waiting for the viewer (奏 · …) in ink with its lead word bold; anything else in the secondary colour.
fn state_line(
  c : @ui.Ctx,
  state : String,
  lead? : String = "",
  lead_text? : String = "",
  rest? : String = "",
  alert? : Bool = false,
  size? : Double = 14.0,
  line? : Double = 20.0,
) -> Unit {
  let t = @sf.theme()
  let icon = match lead {
    "need" => "bell"
    "done" => "check"
    "wait" => "wait"
    "watch" => "watch"
    _ => ""
  }
  if icon != "" {
    let tint = if lead == "need" { t.p.text } else { t.p.muted }
    // (read out whole: StateLine's contentDescription)
    c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, label=state, fn() {
      // the title's mark's place (10), the icon 14 centred on it
      c.box(w=Px(10.0), h=Px(14.0), fn() {
        c.box(tx=-2.0, fn() { @sf.icon(c, icon, size=14.0, color=tint) |> ignore })
        |> ignore
      })
      |> ignore
      if rest != "" {
        c.box(w=Fill(1.0), fn() {
          c.text(rest, size~, color=tint, wrap=false, line~) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    return
  }
  // (a message that did not go: in red)
  if lead == "decision" && lead_text != "" && state.has_prefix(lead_text) {
    let ink = if alert { t.p.red } else { t.p.text }
    c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
      c.text(lead_text, size~, weight=700, color=ink, wrap=false, line~)
      |> ignore
      c.box(w=Fill(1.0), fn() {
        c.text(
          state.view(start_offset=lead_text.length()).to_owned(),
          size~,
          color=ink,
          wrap=false,
          line~,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    return
  }
  c.text(state, size~, color=if alert { t.p.red } else { t.p.muted }, wrap=false, line~) |> ignore
}

///|
/// Who is in a chat, small at its second line's end (RowPicture.kt RowAside): its agents (a mark per maker) and its
/// people, those that lead first; the people only when they lead or someone other than the viewer is in it.
fn row_aside(c : @ui.Ctx, src : Source, item : ChatItem, lead : String, face_size? : Double = 18.0) -> Unit {
  let t = @sf.theme()
  let groups = row_agent_groups(item)
  let people = item.people
  let with_people = people.length() > 0 &&
    (lead == "people" || people.iter().any(fn(p) { !p.mine }))
  if groups.length() == 0 && !with_people {
    return
  }
  let agents = fn() {
    // (RowPicture.kt Agents: the agents in words to a screen reader)
    let said = item.agents.map(fn(a) { a.text }).filter(fn(s) { s != "" })
    c.box(dir=Row, gap=4.0, align=ACenter, label=said.join(tr("web-main.list.separator")), fn() {
      for k, g in groups {
        if k < 3 {
          @sf.maker_mark(c, g.maker, g.runtime, 14.0) |> ignore
        }
      }
      if groups.length() > 3 {
        c.text("+\{groups.length() - 3}", size=12.0, color=t.p.muted, wrap=false)
        |> ignore
      }
    })
    |> ignore
  }
  let faces = fn() {
    let shown = if people.length() > 3 { people[:3].to_array() } else { people }
    let starter = fn(p : Person) { people.length() > 1 && p.id == item.creator }
    // (RowPicture.kt Faces: the people in words to a screen reader)
    c.box(dir=Row, align=ACenter, label=item.people_text, fn() {
      for i, p in shown {
        let f = face(c, src, p, face_size, starter(p), -3.0 * i.to_double())
        // the one who started the chat over the rest (RowPicture.kt Faces: zIndex(1f))
        if starter(p) {
          c.put_over(f)
        }
      }
      if people.length() > shown.length() {
        c.box(tx=-3.0 * (shown.length() - 1).to_double() + 3.0, fn() {
          c.text(
            "+\{people.length() - shown.length()}",
            size=12.0,
            color=t.p.muted,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  }
  c.box(dir=Row, gap=6.0, align=ACenter, fn() {
    if lead == "people" {
      if with_people {
        faces()
      }
      if groups.length() > 0 {
        agents()
      }
    } else {
      if groups.length() > 0 {
        agents()
      }
      if with_people {
        faces()
      }
    }
  })
  |> ignore
}

///|
/// A person, round (RowPicture.kt Face, Parts.kt Avatar): their account's picture once it is here, their initial on
/// their colour until then; ringed 1.5 over their edge, in ink when they started the chat, else in the page's ground
/// (the starter's ring asked 4 wider is held to the face's own size by its Box, as Compose's `size` takes the
/// constraints it is given).
fn face(c : @ui.Ctx, src : Source, p : Person, size : Double, starter : Bool, dx : Double) -> Int {
  let t = @sf.theme()
  let picture = if p.picture != "" { (src.picture)(p.picture, c.page_stint()) } else { "" }
  c.box(w=Px(size), h=Px(size), tx=dx, fn() {
    @sf.avatar(c, if p.email != "" { p.email } else { p.id }, p.name, picture, size)
    c.layer(fn() {
      c.box(
        w=Px(size),
        h=Px(size),
        radius=size / 2.0,
        border=1.5,
        border_color=if starter { t.p.text } else { t.p.bg },
        fn() {  },
      )
      |> ignore
    })
    |> ignore
  })
}
