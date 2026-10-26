// Home (ember apps/android chat/screens/Home.kt, web/src/mobile/Home.tsx): the workspace's chats' lists (sfpages'
// sidebar.mbt, every tier's) under a top bar (settings · the workspace, its switcher · the filter).

///|
/// The top bars' height under the status bar (a place's, TopGlassBar, and a chat's, BarFrame: TopBarHeight), what is in
/// them in its middle; the list starts under it. One length, on the device's pixels at once: 8 + 34 + 8 and 5 + 40 + 5,
/// each on whole pixels, can come out a pixel apart (at 2.85 pixels a point, 143 and 142), the two bars' lines apart
/// as a chat is swiped back.
let bar_h : Double = 50.0

///|
/// Home (Home.kt HomeScreen, mobile/Home.tsx Home): the chats' lists (sfpages' sidebar.mbt) under the top bar, what
/// is left up long after their words; a finger's search over them (sfpages' search.mbt), the bar away under it.
fn home_page(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
) -> Unit {
  ignore(all)
  let filter = filter_of(src, w.id)
  let (view, _) = chats_of(src, w.id, filter)
  let frame : @sfpages.ListsFrame = {
    // under the top bar, the status bar's height and its own (Home.kt padding: topBar + 8); over the bottom bar
    top: status_top() + bar_h + 8.0,
    // (the bar's foot: what is tucked over the rows goes under it)
    under: top_bar_h(),
    foot: nav_foot() + bar_room_now(),
    // (the search's bar under the status bar: sfpages' search.mbt)
    inset: status_top(),
    ground: @sf.theme().p.bg,
    // what the last update brought, until it is seen (sfpages' changelog.mbt; beside the wide frame's rail the web
    // says it in a bubble of its own), even while the list is read
    // and what comes to this device and goes between the stations (transfers.mbt)
    before: fn(_, _) {
      let out : Array[@sfpages.ListPart] = []
      if @sfpages.news_of(src) is Some(_) {
        out.push({ key: "changelog-news", draw: fn() { @sfpages.changelog_news(c, src) }, tucked: false })
      }
      if @sfdesk.transfers_shown(src, w.id) {
        out.push({ key: "transfers", draw: fn() { @sfdesk.home_transfers(c, src, w.id, @sf.theme().chat_list.band_in) }, tucked: false })
      }
      out
    },
    // what is left up a long while on the stations (OpenJobs.kt): nothing while there is none
    after: fn(_, _) {
      if items((src.topic)("longJobs", { "scope": Json::string(w.id) }).value, "groups").length() > 0 {
        [{ key: "open-jobs", draw: fn() { open_jobs(c, src, w) }, tucked: false }]
      } else {
        []
      }
    },
    others: [],
    shown: @sfpages.filter_at(src, w),
    at: Whole,
  }
  // under a finger's search (sfpages' search.mbt): the lists up and away, the bar faded (Home.kt `away`), the
  // search over them
  let away = @sfpages.search_away(c)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    c.layer(fn() { @sfpages.chats_lists(c, src, w, frame) }) |> ignore
    let bar = c.layer(fn() {
      top_bar(c, src, w, view, filter, invited)
    })
    if away > 0.0 {
      c.look(bar, { ..@ui.still_look, alpha: 1.0 - away })
    }
    @sfpages.chats_search(c, src, w, status_top(), Whole)
  })
  |> ignore
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
  let glass_top = c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    // under the status bar (PlacePage.kt TopGlassBar: windowInsetsPadding(statusBars), then TopBarHeight)
    c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=status_top(), min_h=top_bar_h(), gap=10.0, align=ACenter, fn() {
      if nav_button(c, "settings", 22.0, key="home-settings", said=tr("android-chat.home.settings")) {
        app.nav.push(Settings)
      }
      let wid = c.id("home-workspace")
      // (the fixture's home-sheet: opened by it, as the app starts)
      if c.clicked(wid) || home_sheet_at_start.val {
        home_sheet_at_start.val = false
        @sfpages.open_workspaces(src, Of(wid))
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
          // what the others have waiting, as their rows' marks (sfpages' chat_mark), said as the core says it; else an
          // invitation waiting (sfpages' workspace_mark.mbt)
          Some(String(tone)) =>
            c.box(style=others_mark, label=text(marks.value, "othersLabel"), fn() { @sfpages.chat_mark(c, tone) |> ignore })
            |> ignore
          _ => if invited { @sfpages.invite_dot(c, tr("android-chat.home.invited")) }
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
            @sfpages.filter_menu(Of(c.id("home-filter")), filter, fn(f) { home_filter_go(src, w, f) })
          }
        _ => ()
      }
    })
    |> ignore
  })
  // over what runs under it: the scroll bar there keeps clear of it
  c.floats_over(glass_top)
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
    c.text(label, size=t.t.ui, weight=600, color=t.p.text, wrap=false, line=21.0)
    |> ignore
  })
}

///|
/// The marks' colours (SettingParts.kt MarkBlue, MarkRed; Home.kt MarkYellow).
let mark_blue : Int64 = 0x3B82F6FFL

///|
let mark_red : Int64 = 0xE5484DFFL

///|
let mark_yellow : Int64 = 0xF2B01EFFL

///|
/// What the others have waiting, beside the name: its mark alone.
// kept across runs: a value (no field of it changes)
let others_mark : @ui.Style = @ui.css("row align=ACenter")

///|
/// The filter's menu chosen on Home (mobile/Home.tsx FilterButton): a filter its list, 奏 and 已归档 their pages.
fn home_filter_go(src : Source, w : Workspace, f : String) -> Unit {
  match f {
    "decisions" => open_page(Decisions)
    "archive" => open_page(Archived)
    _ => @sfpages.set_filter(src, w, f)
  }
}

///|
/// The workspaces opened from Home's top as it first draws (the fixture's home-sheet: newchat_fixture.mbt open_mode).
// kept across runs: put back by reset, let go as Home reads it
let home_sheet_at_start : Ref[Bool] = Ref(false)
