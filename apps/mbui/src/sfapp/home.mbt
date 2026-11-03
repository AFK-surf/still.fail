// Home (ember apps/android chat/screens/Home.kt, web/src/mobile/Home.tsx): the workspace's chats' lists (sfpages'
// sidebar.mbt, every tier's) under a top bar (the filter · the workspace's switcher and settings).

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
    before: fn(_, _) {
      let cards : Array[@sfpages.ListPart] = []
      // what the update wants of the person (the leave to install apps), over what the last one brought
      if @sfpages.update_card_shown() {
        cards.push({ key: "update-card", draw: fn() { @sfpages.update_card(c, src) }, tucked: false })
      }
      if @sfpages.news_of(src) is Some(_) {
        cards.push({ key: "changelog-news", draw: fn() { @sfpages.changelog_news(c, src) }, tucked: false })
      }
      cards
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
/// The top bar over the list: the filter at the left, the workspace's switcher and settings at the right. The
/// switcher has a dot when another workspace has something waiting.
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
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station
      match view {
        Some(v) if v.stations > 0 =>
          if nav_button(
              c,
              "filter",
              20.0,
              key="home-filter",
              // (never marked for the list shown: asked 2026-10-27)
              color=t.p.text,
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
      // Catching up and transfers stay beside the filter.
      let (syncing, said) = match view {
        Some({ syncing: Some(y), .. }) => (true, y)
        _ => (false, "")
      }
      @sf.sync_key(c, "home-syncing", 34.0, 20.0, syncing, said)
      @sfdesk.transfers_key(c, src, w.id, 34.0, 20.0)
      c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, justify=JEnd, fn() {
        let wid = c.id("home-workspace")
        // (the fixture's home-sheet: opened by it, as the app starts)
        if c.clicked(wid) || home_sheet_at_start.val {
          home_sheet_at_start.val = false
          @sfpages.open_workspaces(src, Of(wid))
        }
        c.box(dir=Row, h=Px(34.0), gap=6.0, align=ACenter, id=wid, fn() {
          @sf.icon(c, "chevron-down", size=16.0, color=t.p.muted) |> ignore
          // its mark before its name (the one in use: a GIF of it moves); none where it has none, its letter only the
          // name's first again beside it
          if @sf.has_station_mark(w.emoji, w.icon) {
            @sf.workspace_badge(c, w.name, w.emoji, w.icon, home_ws_mark, still=false)
          }
          // A long name gives way to the controls actually present, including the sync mark while it exits.
          top_bar_title(c, w.name, cut=true) |> ignore
          let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) })
          match field(marks.value, "others") {
            // what the others have waiting, as their rows' marks (sfpages' chat_mark), said as the core says it; else an
            // invitation waiting (sfpages' workspace_mark.mbt)
            Some(String(tone)) =>
              c.box(style=others_mark, label=text(marks.value, "othersLabel"), fn() { @sfpages.chat_mark(c, tone) |> ignore })
              |> ignore
            _ => if invited { @sfpages.invite_dot(c, tr("android-chat.home.invited")) }
          }
        })
        |> ignore
        if nav_button(c, "settings", 22.0, key="home-settings", said=tr("android-chat.home.settings")) {
          @sfbase.history_push()
          app.nav.push(Settings)
        }
      })
      |> ignore
    })
    |> ignore
  })
  // over what runs under it: the scroll bar there keeps clear of it
  c.floats_over(glass_top)
}

///|
/// The name in a top bar (PlacePage.kt TopBarTitle): 24 bold, its letters 0.4 closer, on one line.
fn top_bar_title(c : @ui.Ctx, s : String, cut? : Bool = false) -> Int {
  let look = @sf.top_bar_title_look
  // (said as it is: Ctx::text makes it larger at the system's size of words, as view_spacing does a ScaledPoints)
  guard look.tracking is ScaledPoints(tracking) else { abort("top_bar_title_look's tracking: ScaledPoints") }
  c.text(s, size=look.size, weight=look.weight, color=@sf.theme().p.text, wrap=look.wrap, line=look.line, tracking~, w=if cut {
    Cut
  } else {
    Auto
  })
}

///|
/// A bar's round key's side (nav_button's 34).
let nav_key_side : Double = 34.0

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
/// The filter's menu chosen on Home (mobile/Home.tsx FilterButton): a filter its list, 已归档 its page.
fn home_filter_go(src : Source, w : Workspace, f : String) -> Unit {
  match f {
    "archive" => open_page(Archived)
    _ => @sfpages.set_filter(src, w, f)
  }
}

///|
/// The workspaces opened from Home's top as it first draws (the fixture's home-sheet: newchat_fixture.mbt open_mode).
// kept across runs: put back by reset, let go as Home reads it
let home_sheet_at_start : Ref[Bool] = Ref(false)

///|
/// The workspace's mark before its name in Home's bar (Home.tsx WorkspaceBadge: 20).
let home_ws_mark : Double = 20.0
