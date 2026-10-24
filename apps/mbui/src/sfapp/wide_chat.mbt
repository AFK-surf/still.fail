// A chat in the wide frame's pane (ember web/src/pages/ChatPage.tsx, styles/sidebar.css.ts pageBar, session.css.ts,
// dock.css.ts): its bar (45 high, the title 14 in 600, who is in it, its agents; at its end 归档 while nothing is left
// in it, its services and jobs, its info), the messages in a column 760 wide at most in the middle of the pane (the
// phone's rows: chat.mbt), the composer at its foot, 804 at most. What the phone's chat page does (reading, following
// its end, the way to the newest, telling the core what shows) is the same page's.

///|
/// The column the messages keep to (later.css.ts: 760), and the least room at its sides (session.css.ts: 40).
let column_w : Double = 760.0

///|
/// A page's bar in the wide frame (styles/sidebar.css.ts pageBar: 45, its 1 at the foot).
let wide_bar_h : Double = 45.0

///|
/// What a chat's rows stand in from the pane's sides: 14 on a phone; in the wide frame, the column in the middle.
fn row_side(c : @ui.Ctx) -> Double {
  if wide_on.val {
    dmax(40.0, (c.width - column_w) / 2.0)
  } else {
    14.0
  }
}

///|
/// What the composer's column holds, in the pane's middle (the column and the capsule's curve each side, 804 wide at
/// most, 12 from the pane's sides: dock.css.ts), in the wide frame; as it is elsewhere.
fn wide_center(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if !wide_on.val {
    body()
    return
  }
  let inner = wide_composer_w(c)
  c.box(style=wide_centred, fn() {
    c.box(w=Px(inner), fn() { c.sized(inner, c.height, body) }) |> ignore
  })
  |> ignore
}

///|
/// The composer's width in the wide frame's pane `c.width` wide (dock.css.ts composerBox: the column and 22 each side,
/// 12 from the pane's sides).
fn wide_composer_w(c : @ui.Ctx) -> Double {
  dmin(c.width - 24.0, column_w + 44.0)
}

///|
/// A page's title in its bar (sidebar.css.ts pageBar h1: 14 in 600, on 20).
// kept across runs: a value (no field of it changes)
let bar_title : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let bar_title_room : @ui.Style = @ui.css("w=Full")

///|
/// What is done in a page's bar, at its end, 2 apart (ChatPage.css.ts pageBarActions).
// kept across runs: a value (no field of it changes)
let bar_buttons : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let wide_centred : @ui.Style = @ui.css("row w=Full justify=JCenter")

///|
/// An icon button of a page's bar (page.css.ts iconBtn): 32 square, the nav's corner, the pointer's ground and ink
/// on hover. True on the frame after a press.
fn icon_button(c : @ui.Ctx, key : String, icon : String, label? : String = "", action? : String = "") -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.lit(id) || c.pressed(id)
  let b = c.box(
    w=Px(32.0),
    h=Px(32.0),
    radius=12.0,
    align=ACenter,
    justify=JCenter,
    bg=if hot { t.p.hover } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size=16.0, color=if hot { t.p.text } else { t.p.muted }) |> ignore },
  )
  // named for a screen reader (the web's aria-label), and said under it on hover with its keys (the web's IconButton)
  if label != "" {
    c.semantics(b, Button, id~, label~)
    @sf.tip(c, key, id, label, shortcut=action)
  }
  c.clicked(id)
}

///|
/// A page's bar in the wide frame (styles/sidebar.css.ts pageBar): 45 high, 12 in; back (a page under another), the
/// title in 14 and 600, what the page does at its end. True on the frame after back was pressed.
fn page_bar_wide(c : @ui.Ctx, title : String, back : Bool, trailing : () -> Unit) -> Bool {
  let t = @sf.theme()
  let bar = c.id("page-bar")
  if @ui.window_inset() {
    c.window_drag(bar)
  }
  let mut went = false
  let (room_l, room_r, ml, mr) = @sfdesk.page_bar_room()
  c.box(moves="page-bar", dir=Row, w=Fill(1.0), h=Px(wide_bar_h), pl=room_l, pr=room_r, ml~, mr~, pb=1.0, gap=8.0, align=ACenter, bg=t.p.bg, id=bar, fn() {
    if back {
      went = icon_button(c, "page-bar/back", "chevron-left")
    }
    c.box(style=bar_title_room, fn() { c.text(title, style=bar_title) |> ignore }) |> ignore
    c.box(style=bar_buttons, trailing) |> ignore
  })
  |> ignore
  went
}

///|
/// ⌘F's bar (sfdesk/find.mbt) opened in chat `r`, what opens under the chat's bar closed (sfdesk's chat page).
fn find_open(c : @ui.Ctx, r : ChatRef) -> Unit {
  @sfdesk.chat_find_open(c, r)
}


///|
/// The message the chat's window was last moved about for what ⌘F found (`chat.around`, once each).
let find_around : Ref[Double] = Ref(-1.0)

