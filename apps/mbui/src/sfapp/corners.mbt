// A phone's or a tablet's screen wider than a phone's (still.fail's Android app, chat/screens/Wide.kt, as the web's
// mobile/app.tsx WIDE draws it: an opened foldable, a phone on its side, a film turned sideways): the phone's pages
// the screen's whole width, no bottom bar under them; at the screen's bottom left, level with the composer and as
// tall, a button raises the latest chats over the page (a chat's composer starts beside it); on Home, 奏 and the
// new-chat button at its bottom right, the stations at a glance in its top bar. A new chat keeps a column in the
// middle. The drive's reader and player take the whole screen: nothing at their corners. Not the desktop's wide frame
// (wide.mbt): no rail, no sidebar, the phone's theme, a finger drags the lists as on a phone.

///|
/// From this width on, a phone's or a tablet's screen is wide (Wide.kt WideAt).
let corners_from : Double = 680.0

///|
/// Whether this frame is drawn as Android's wide screen.
let corners_on : Ref[Bool] = Ref(false)

///|
/// The latest chats raised (Wide.kt Recent `open`), and the page they were raised over: put away as it changes.
let recent_open : Ref[Bool] = Ref(false)

///|
let recent_over : Ref[Page?] = Ref(None)

///|
/// Whether a window this wide is drawn as Android's wide screen: a phone's or a tablet's (a desktop's is wide.mbt's).
pub fn is_corners(c : @ui.Ctx) -> Bool {
  c.width >= corners_from && @sf.touch_system()
}

///|
/// Whether the pages have the bottom bar under them (a phone's screen): no room kept for it otherwise.
fn has_bar() -> Bool {
  !wide_on.val && !corners_on.val
}

///|
/// Where a chat's composer starts on a wide screen: beside the latest chats' button (10 + 52 + 10: Wide.kt
/// BesideRecent).
let beside_recent : Double = 72.0

///|
/// What Home's list keeps at its foot on a wide screen, whose corners have 奏 and 令 (Home.kt: 8).
let wide_foot : Double = 8.0

///|
/// A new chat on a wide screen: a column up to 680 wide in the middle, with at least 72 of room either side (Wide.kt
/// NewChatColumn).
let new_chat_most : Double = 680.0

///|
let new_chat_side : Double = 72.0

///|
/// `body` in a new chat's column on a wide screen (Wide.kt NewChatColumn), what it reads of the Ctx's width the
/// column's; the screen's whole width otherwise.
fn new_chat_column(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if !corners_on.val {
    body()
    return
  }
  let w = dmax(0.0, dmin(new_chat_most, c.width - 2.0 * new_chat_side))
  c.box(style=column_row, fn() {
    c.box(style=@ui.style(w=Fixed(w), h=Full), fn() { c.sized(w, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let column_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, justify=JCenter)

///|
/// What is at the screen's bottom corners over the page (Wide.kt WideCorners): on Home 奏 and the new-chat button;
/// nothing over 奏's page (its foot is its own) nor the drive's reader and player (their controls are there); on the
/// others the latest chats' button.
fn wide_corners(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let top = app.nav.top()
  // put away when the page changes under them (a new chat becoming its chat, a link opened)
  match recent_over.val {
    Some(p) if p != top => {
      recent_open.val = false
      recent_over.val = None
    }
    _ => ()
  }
  match top {
    Home => home_corner(c, src, w)
    Decisions | DriveRead(_) | DrivePlay(_) => ()
    _ => recent_corner(c, src, w, top)
  }
}

///|
/// 奏 and the new-chat button at Home's bottom right, 10 in from the edges, over the navigation bar (Wide.kt).
fn home_corner(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  c.layer(fn() {
    c.box(style=corner_end, fn() {
      c.box(style=corner_row, fn() {
        // in the floating capsules' glass, over the plain page (Glass.kt floatingStill: Raised at 72% over the page)
        c.box(style=still_capsule, fn() {
          decisions_capsule(c, src, w, @sf.over(t.p.bg, @sf.alpha(t.p.raised, 0.72)))
        })
        |> ignore
        new_chat_disc(c)
      })
      |> ignore
      c.box(style=@ui.style(h=Fixed(nav_foot())), fn() {  }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let corner_end : @ui.Style = @ui.style(w=Full, h=Full, align=AEnd, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let corner_row : @ui.Style = @ui.style(row=true, pr=S2_5, pb=S2_5, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let still_capsule : @ui.Style = @ui.style(radius=Full, shadow=@sf.floating.cast())

///|
/// The new-chat button (Wide.kt NewChatDisc): a disc of the capsules' glass in the accent, 令 white.
fn new_chat_disc(c : @ui.Ctx) -> Unit {
  let id = c.id("wide/new-chat")
  if c.clicked(id) {
    new_chat(c)
  }
  let node = c.box(style=new_chat_disc_box, id~, fn() { @sf.icon(c, "ling", size=44.0, color=white) |> ignore })
  c.semantics(node, Button, id~, label=tr("android-misc.wide.newChat"))
}

///|
// kept across runs: a value (no field of it changes)
let new_chat_disc_box : @ui.Style = @ui.style(
  w=S14,
  h=S14,
  radius=Full,
  bg=Over(Bg, A(Accent, O70)),
  shadow=@sf.floating.cast(),
  align=ACenter,
  justify=JCenter,
)

///|
let white : Int64 = 0xFFFFFFFFL

///|
/// The latest chats' button at the screen's bottom left, as high as the composer is (ChatHost.kt: 10 from the foot, 52
/// tall on one line), and the chats it raises over the page (not dimmed): the list's first six, the one open marked; a
/// new chat at their head, the whole list at their foot. One picked takes the place of the page open (AppState.open).
fn recent_corner(c : @ui.Ctx, src : Source, w : Workspace, top : Page) -> Unit {
  let t = @sf.theme()
  let open = recent_open.val
  if open {
    // back puts them away first
    c.on_back(fn() { recent_open.val = false })
    // a tap anywhere else puts them away
    c.layer(fn() {
      let away = c.id("wide/recent-away")
      if c.clicked(away) {
        recent_open.val = false
      }
      c.box(style=recent_away, id=away, fn() {  }) |> ignore
    })
    |> ignore
  }
  c.layer(fn() {
    c.box(style=recent_column, fn() {
      if open {
        recent_panel(c, src, w, top)
        c.box(style=recent_gap, fn() {  }) |> ignore
      }
      let id = c.id("wide/recent")
      if c.clicked(id) {
        recent_open.val = !open
        recent_over.val = if open { None } else { Some(top) }
      }
      let node = c.box(style=if open { recent_button_open } else { recent_button }, id~, fn() {
        @sf.icon(c, "chats", size=22.0, color=if open { t.p.bg } else { t.p.text }) |> ignore
      })
      c.semantics(node, Button, id~, label=tr("android-misc.wide.recent"), expanded=open)
      c.box(style=@ui.style(h=Fixed(nav_foot())), fn() {  }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let recent_away : @ui.Style = @ui.style(w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let recent_column : @ui.Style = @ui.style(w=Full, h=Full, pl=S2_5, pb=S2_5, align=AStart, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let recent_gap : @ui.Style = @ui.style(h=S2_5)

///|
// kept across runs: a value (no field of it changes)
let recent_button : @ui.Style = @ui.style(
  w=@sf.recent_button,
  h=@sf.recent_button,
  radius=Full,
  bg=Floating,
  shadow=@sf.floating.cast(),
  align=ACenter,
  justify=JCenter,
)

///|
/// Open: in the words' colour (Wide.kt: shadow(1), ink).
// kept across runs: a value (no field of it changes)
let recent_button_open : @ui.Style = recent_button.then(
  @ui.style(bg=Fg, shadow=@sf.button_raised.cast()),
)

///|
/// The panel (Wide.kt Recent): 340 wide, 560 tall at most, in the capsules' glass; its new-chat button round in its
/// corner, its rows' grounds and its foot's 6 in, concentric with it.
fn recent_panel(c : @ui.Ctx, src : Source, w : Workspace, top : Page) -> Unit {
  let (view, error) = chats_of(src, w.id, "all")
  c.box(style=recent_panel_box, fn() {
    c.box(style=recent_head, fn() {
      c.text(tr("android-misc.wide.recent"), style=recent_title) |> ignore
      let id = c.id("wide/recent-new")
      if c.clicked(id) {
        recent_open.val = false
        new_chat(c, in_place=true)
      }
      let node = c.box(style=recent_new_box, id~, fn() { @sf.icon(c, "ling", size=26.0, color=white) |> ignore })
      c.semantics(node, Button, id~, label=tr("android-misc.wide.newChat"))
    })
    |> ignore
    match view {
      None => waiting(c, recent_waiting, None, error)
      // no rows: what the list says in their place (the core's `note`), as Home does: its rows to come while read, or
      // what could not be; else that there are none
      Some(v) if v.days.is_empty() =>
        match v.note {
          Some(note) if note.reading || note.failing.length() > 0 => waiting(c, recent_waiting, Some(note), None)
          _ => c.text(tr("android-misc.wide.empty"), style=recent_empty) |> ignore
        }
      Some(v) => {
        let items : Array[ChatItem] = []
        for d in v.days {
          for it in d.items {
            if items.length() < recent_chats_most {
              items.push(it)
            }
          }
        }
        c.box(style=recent_rows, fn() {
          for item in items {
            let here = match top {
              Chat(r) => r.station == item.station && r.session == item.session
              _ => false
            }
            c.box(style=if here { recent_row_here } else { recent_row }, fn() {
              chat_row(c, src, item, v.leading, found=true, opened=fn(r) {
                recent_open.val = false
                if !here {
                  open_in_place(Chat(r))
                }
              })
              |> ignore
            })
            |> ignore
          }
        })
        |> ignore
      }
    }
    c.box(style=recent_rule, fn() {  }) |> ignore
    c.box(style=recent_foot, fn() {
      let id = c.id("wide/recent-all")
      if c.clicked(id) {
        recent_open.val = false
        home()
      }
      c.box(style=recent_all, id~, fn() {
        c.text(tr("android-misc.wide.all"), style=recent_all_words) |> ignore
        @sf.icon(c, "chevron-right", size=16.0, color=@sf.theme().p.accent_text) |> ignore
        // Wide.kt Recent: 全部 clickable over its clip, Smooth(concentric(PANEL_PAD + 16, PANEL_PAD))
        @motion.ripple(c, id, 22.0 - 6.0 / @sf.smooth_scale)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How many of the list's chats the panel has, and how many rows breathe while they are read.
let recent_chats_most : Int = 6

///|
let recent_waiting : Int = 4

///|
// kept across runs: a value (no field of it changes)
let recent_panel_box : @ui.Style = @ui.style(
  w=@sf.recent_w,
  max_h=@sf.recent_max_h,
  radius=Xl3,
  bg=Floating,
  shadow=@sf.recent_raised.cast(),
  clip=true,
)

///|
// kept across runs: a value (no field of it changes)
let recent_head : @ui.Style = @ui.style(row=true, w=Full, pl=S4_5, pr=S1_5, pt=S1_5, pb=S1_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let recent_title : @ui.TextStyle = @ui.text_style(size=Lg, weight=Semibold, color=Fg, w=Full, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let recent_new_box : @ui.Style = @ui.style(w=S8, h=S8, radius=Full, bg=Accent, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let recent_empty : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let recent_rows : @ui.Style = @ui.style(w=Full, px=S1_5)

///|
// kept across runs: a value (no field of it changes)
let recent_row : @ui.Style = @ui.style(w=Full, radius=Inner, clip=true)

///|
// kept across runs: a value (no field of it changes)
let recent_row_here : @ui.Style = recent_row.then(@ui.style(bg=AccentBg))

///|
// kept across runs: a value (no field of it changes)
let recent_rule : @ui.Style = @ui.style(w=Full, h=@sf.hairline, bg=Line)

///|
// kept across runs: a value (no field of it changes)
let recent_foot : @ui.Style = @ui.style(w=Full, p=S1_5)

///|
// kept across runs: a value (no field of it changes)
let recent_all : @ui.Style = @ui.style(
  row=true,
  w=Full,
  pl=S3,
  pr=S2_5,
  pt=S1_5,
  pb=S1_5,
  radius=Inner,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let recent_all_words : @ui.TextStyle = @ui.text_style(size=Base, color=AccentText, w=Full, wrap=false)

///|
/// `p` in the place of the page on top, or over Home when it is alone (AppState.open), the sheets and the menu put
/// away.
fn open_in_place(p : Page) -> Unit {
  lower_sheet()
  app.menu = false
  if app.nav.depth() > 1 {
    app.nav.replace(p)
  } else {
    app.nav.push(p)
  }
}

///|
/// The stations at a glance, as the core has them in workspace `ws` (StationGlyph.kt's counts: asleep while the core
/// reaches nothing at all), and in words: asleep, what the core cannot reach says it; else the stations (the core's),
/// and what is wrong with them.
fn stations_at_glance(src : Source, ws : String) -> (@sf.GlyphCounts, String) {
  let chats = (src.topic)("chats", { "scope": Json::string(ws), "mine": Json::boolean(false) })
  let g = field(chats.value, "glyph")
  let status = (src.topic)("status", { "workspace": Json::string(ws) }).value
  let asleep = text(status, "state") == "trouble"
  let glyph : @sf.GlyphCounts = {
    online: count(g, "online"),
    dim: count(g, "dim"),
    failing: count(g, "failing"),
    working: count(g, "working"),
    connecting: count(g, "connecting"),
    asleep,
  }
  let said = if asleep { text(status, "text") } else { text(g, "label") }
  let words = match field(chats.value, "trouble") {
    _ if said == "" => ""
    Some(Object(_)) as trouble => fill("android-chat.home.stations.trouble", [("said", said), ("trouble", text(trouble, "text"))])
    _ => fill("android-chat.home.stations", [("said", said)])
  }
  (glyph, words)
}

///|
/// The stations at a glance in Home's top bar on a wide screen (Home.kt: 34 round, the glyph 24): tapped, their page.
fn stations_button(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let (glyph, said) = stations_at_glance(src, w.id)
  let id = c.id("home-stations")
  if c.clicked(id) {
    app.nav.push(Setting(@settings.Route::Stations))
  }
  let node = c.box(style=stations_box, id~, fn() {
    @sf.station_glyph(c, glyph, 24.0, t.p.text, t.p.red) |> ignore
    // Home.kt: the stations' button clickable over its circle
    @motion.ripple(c, id, 17.0)
  })
  c.semantics(node, Button, id~, label=said)
}

///|
// kept across runs: a value (no field of it changes)
let stations_box : @ui.Style = @ui.style(
  w=@sf.nav_button_side,
  h=@sf.nav_button_side,
  radius=Full,
  align=ACenter,
  justify=JCenter,
)
