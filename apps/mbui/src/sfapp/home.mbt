// Home: the workspace's chats' lists (sfpages'
// sidebar.mbt, every tier's) under a top bar (the filter · the workspace's switcher and settings).

///|
/// The top bars' height under the status bar (a place's, TopGlassBar, and a chat's, BarFrame: TopBarHeight), what is in
/// them in its middle; the list starts under it. One length, on the device's pixels at once: 8 + 34 + 8 and 5 + 40 + 5,
/// each on whole pixels, can come out a pixel apart (at 2.85 pixels a point, 143 and 142), the two bars' lines apart
/// as a chat is swiped back.
let bar_h : Double = 50.0

///|
/// The name in a top bar: 24 bold, its letters 0.4 closer, on one line.
fn top_bar_title(c : @ui.Ctx, s : String, look? : @view.WordsLook = @sf.top_bar_title_look, cut? : Bool = false) -> Int {
  // (said as it is: Ctx::text makes it larger at the system's size of words, as view_spacing does a ScaledPoints)
  guard look.tracking is ScaledPoints(tracking) else { @halt.saying("top_bar_title_look's tracking: ScaledPoints") }
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
/// A round button in a bar: 34 across, the icon alone, no disc behind it (a ground while
/// pressed). `on_press` as it is pressed.
fn nav_button(
  c : @ui.Ctx,
  icon : String,
  size : Double,
  key~ : String,
  color? : Int64,
  said? : String,
  on_press? : () -> Unit,
) -> Unit {
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
  match on_press {
    Some(f) => c.on_press(id, f)
    None => ()
  }
}

///|
/// The filter's menu chosen on Home: a filter its list, 已归档 its page.
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
/// The workspace's mark before its name in Home's bar.
let home_ws_mark : Double = 20.0
