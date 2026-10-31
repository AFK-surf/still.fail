// The bar every file opened shows across the window's top on a desktop (web/ui viewer/ViewerBar.tsx, ViewerBar.css.ts):
// a picture's, a PDF's or code's preview (the app's FilePreview), a text read (reader.mbt), a film played (player.mbt). Always there, along the window's top, 45 high: the way back on the left (where to, by name), the
// file's name and a line about it in the middle, its tools on the right as icons, download last. Its ground is the
// file's (the paper under a text) at 82% over a 20 blur, saturated, a line of its own under it at 70%; it drags the
// window, clear of the window's buttons where they are in the app's top row. Gone up out of the way (a picture left
// alone, a text read on down) it slides up its height and fades (240 ms, ease-out), and takes no presses.

///|
/// The colours a bar is drawn in: the file's ground under it, its words, what is quieter, its line; a button's ground
/// under the pointer (`hover`) and while what it opens is open (`chosen`), over that ground (a film's black has its
/// own: the page's hover on it is dark on black, or near none: Player.css.ts's film --hover and --selected).
pub(all) struct ViewerInk {
  ground : Int64
  ink : Int64
  muted : Int64
  line : Int64
  hover : Int64
  chosen : Int64
}

///|
/// The page's own (a preview's: the canvas, the page's words).
pub fn page_viewer_ink() -> ViewerInk {
  let p = theme().p
  { ground: p.canvas, ink: p.text, muted: p.muted, line: p.line, hover: p.hover, chosen: p.selected }
}

///|
/// The bar (`key` its own): back to `back`, `name` and `meta` under it (`title`, where the file is, over them while
/// they are pointed at: ViewerBar.tsx's title), `tools` at its end (viewer_tool, viewer_download); `hidden`, gone up
/// out of the way. Its last tool stands at the window's top right corner as a page's bar's last button does
/// (window_end_in: following the window's corner, as far in as from the bar's top), or clear of it where the last is
/// a capsule of words (`capsule_end`: window_clear_in). True on the frame after its way back was pressed.
pub fn viewer_bar(
  c : @ui.Ctx,
  key : String,
  back : String,
  name : String,
  meta : String,
  hidden : Bool,
  ink : ViewerInk,
  tools : () -> Unit,
  title? : String = "",
  capsule_end? : Bool = false,
) -> Bool {
  let gone = @motion.animate(c, key + "/gone", if hidden { 1.0 } else { 0.0 }, spec=@motion.tween(
      viewer_bar_ms,
      ease=Out,
    ))
  let bar = c.id(key)
  let live = gone < 1.0 && !hidden
  if live && @ui.window_inset() {
    c.window_drag(bar)
  }
  let glass = @ui.Glass::frosted(
    blur=viewer_bar_blur,
    tint=alpha(ink.ground, viewer_bar_share),
    solid=ink.ground,
    saturation=viewer_bar_saturation,
  )
  let mut went = false
  // (its ground on under the status bar where the system's bars are over the window: a tablet's)
  let top = (viewer_host().room)().0
  let node = c.box(style=viewer_bar_box, glass~, id=if live { bar } else { 0 }, fn() {
    if top > 0.0 {
      c.box(style=@ui.style(w=Full, h=Fixed(top)), fn() {  }) |> ignore
    }
    // (its way back at the window's top left corner, as a page's bar's last key at its right is: viewer_back_at_corner)
    let at_corner = viewer_back_at_corner()
    let alone = c.theme().corner(Xl)
    let start = if at_corner { viewer_bar_start_in(alone, @ui.corner_roots()) } else { viewer_bar_in }
    c.box(style=viewer_bar_row.then(@ui.style(pl=room(start))), fn() {
      // clear of the window's buttons at its left, the system's (ViewerBar.css.ts: 84 in, not in full screen)
      if @ui.window_keys_left() {
        c.box(style=viewer_bar_buttons, fn() {  }) |> ignore
      }
      c.box(style=viewer_bar_start, fn() {
        let id = c.id(key + "/back")
        if live && c.clicked(id) {
          went = true
        }
        let corner = if at_corner { @ui.style(radius=Linked(viewer_back_corner(alone))) } else { @ui.style() }
        let b = c.box(style=viewer_back_box.then(corner).then(viewer_lit(ink)), id=if live { id } else { 0 }, fn() {
          icon(c, "chevron-left", size=viewer_back_icon, color=ink.ink) |> ignore
          // (short of room, its words leave it whole and the chevron stays, as a page's bar's way back does)
          c.box(drop=1, fn() {
            c.text(back, style=viewer_back_words.then(@ui.text_style(color=Data(ink.ink)))) |> ignore
          })
          |> ignore
        })
        c.semantics(b, Button, id~, label=back)
      })
      |> ignore
      // the middle, as wide as what it says, the sides kept for the way back and the tools
      let most = dmax(viewer_none, c.width - viewer_bar_sides)
      let middle = c.id(key + "/name")
      c.box(style=viewer_bar_middle.then(@ui.style(max_w=Fixed(most))), id=if live && title != "" { middle } else { 0 }, taps=false, points=true, fn() {
        c.text(name, style=viewer_name_words.then(@ui.text_style(color=Data(ink.ink)))) |> ignore
        if meta != "" {
          c.text(meta, style=viewer_meta_words.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        }
      })
      |> ignore
      if live {
        tip(c, key + "/name-tip", middle, title)
      }
      // clear of the window's buttons at its right where they are the app's (Windows': window_keys); else at the
      // window's corner as a page's bar's last is
      let end = if @ui.window_keys_own() {
        window_keys_room_at(c.width) + viewer_bar_in
      } else if capsule_end {
        window_clear_in(viewer_bar_in)
      } else {
        window_end_in(viewer_bar_in)
      }
      // (short of room, the tools kept whole: the way back and the name give way)
      c.box(style=viewer_bar_end().then(@ui.style(pr=room(end))), keep=true, fn() {
        tools_across.val = true
        tools()
        tools_across.val = false
      })
      |> ignore
    })
    |> ignore
  })
  c.look(node, @ui.look(alpha=1.0 - gone, dy=-(viewer_bar_h + top) * gone))
  went
}

///|
/// Whether the tools being drawn are the bar's across the top (viewer_bar), which a finger's are 44 at least in (the
/// floating head's, laid out Small, are as the phone's are).
// kept across runs: true only while viewer_bar draws its tools, false again after them
let tools_across : Ref[Bool] = Ref(false)

///|
/// One of a bar's tools (ViewerBar.tsx ViewerTool): an 18 icon in a 32 button, in the file's quieter ink until
/// pointed at or `on` (its ground then the page's chosen one), named on hover. True on the frame after it was pressed.
pub fn viewer_tool(
  c : @ui.Ctx,
  key : String,
  icon_name : String,
  label : String,
  ink : ViewerInk,
  on? : Bool = false,
  disabled? : Bool = false,
) -> Bool {
  let id = c.id(key)
  let live = !disabled
  let hot = live && (c.lit(id) || c.pressed(id))
  let b = c.box(style=viewer_tool_box.then(viewer_tool_corner()).then(viewer_lit(ink)), selected=on, disabled~, id=if live { id } else { 0 }, fn() {
    icon(c, icon_name, size=viewer_tool_icon, color=if on || hot { ink.ink } else { ink.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~, pressed=on, disabled~)
  if live {
    tip(c, key + "/tip", id, label, side=Bottom)
  }
  live && c.clicked(id)
}

///|
/// The corner of a tool in the bar across the top: at a window's corner the one a page's bar's buttons share there
/// (bar_keys_link: the window's followed, not a circle beside an arc it could never follow), the last of them in that
/// corner concentric with it; round elsewhere (a panel's, a square window's, the floating head's).
pub fn viewer_tool_corner() -> @ui.Style {
  match bar_keys_link() {
    Some(link) if tools_across.val => @ui.style(radius=Linked(link))
    _ => @ui.style()
  }
}

///|
/// Download, as every bar has it last (ViewerDownload). True on the frame after it was pressed. `coming`: how far a
/// download of it has come (0 to 1), a ring of the file's ink in its place meanwhile, not pressed again.
pub fn viewer_download(c : @ui.Ctx, key : String, ink : ViewerInk, disabled? : Bool = false, coming? : Double) -> Bool {
  match coming {
    Some(part) => {
      let label = t("web-main.preview.download")
      let b = c.box(style=viewer_tool_box.then(viewer_tool_corner()), disabled=true, fn() {
        progress_ring(c, viewer_tool_icon, part, ink.ink) |> ignore
      })
      c.semantics(b, Button, label~, disabled=true)
      false
    }
    None => viewer_tool(c, key, "download", t("web-main.preview.download"), ink, disabled~)
  }
}

///|
/// When a bar over a file read down (a text, a PDF, code) is out of the way (useBarOnScroll): gone as it is read on
/// down, back as it is read back up, or as the pointer comes to the window's top. Where the list it reads by was last
/// seen: its first row in view and how far down it.
pub(all) struct BarOnScroll {
  mut hidden : Bool
  mut seen : (Int, Double)
}

///|
/// A bar there, nothing read yet.
pub fn BarOnScroll::new() -> BarOnScroll {
  { hidden: false, seen: (0, 0.0) }
}

///|
/// Told how the list `list` stands this frame (onScroll) and where the pointer is (onPointerMove): near its top
/// always there; on down, gone; back up, back; the pointer near the window's top, back.
pub fn BarOnScroll::heard(self : BarOnScroll, c : @ui.Ctx, list : String) -> Unit {
  match c.list_place(list) {
    Some((first, off, _)) => {
      let (was_first, was_off) = self.seen
      if first == 0 && off < viewer_top_kept {
        self.hidden = false
      } else if first > was_first || (first == was_first && off - was_off > viewer_moved) {
        self.hidden = true
      } else if first < was_first || (first == was_first && was_off - off > viewer_moved) {
        self.hidden = false
      }
      self.seen = (first, off)
    }
    None => ()
  }
  let (_, py, _) = c.pointer()
  if py >= 0.0 && py < viewer_bar_reach {
    self.hidden = false
  }
}

///|
/// Read down this far before the bar goes (TOP_KEPT); this much of a scroll at once says which way (MOVED).
let viewer_top_kept : Double = 48.0

///|
let viewer_moved : Double = 6.0

///|
/// The pointer this near the window's top brings the bar back (VIEWER_BAR_REACH).
pub let viewer_bar_reach : Double = 72.0

///|
/// How tall the bar is (VIEWER_BAR: a page's bar, its 32 buttons level with the window's): what is under it starts
/// below it or goes under it.
pub let viewer_bar_h : Double = 45.0

///|
/// How far down from the window's top what is under the bar starts: the bar, and the status bar over it where the
/// system's bars are over the window (a tablet's).
pub fn viewer_bar_under() -> Double {
  viewer_bar_h + (viewer_host().room)().0
}

///|
/// Its going and coming (ViewerBar.css.ts: transform and opacity, 240 ms ease-out).
pub let viewer_bar_ms : Double = 240.0

///|
/// Its glass: the ground at 82% over a 20 blur, saturated 1.4; its line at 70%.
let viewer_bar_share : Double = 0.82

///|
pub let viewer_bar_blur : Double = 20.0

///|
pub let viewer_bar_saturation : Double = 1.4

///|
/// What the middle leaves its sides at least: the way back's and the tools' room either side (as the grid's equal
/// sides keep it in the middle).
let viewer_bar_sides : Double = 320.0

///|
let viewer_none : Double = 0.0

///|
pub let viewer_back_icon : Double = 20.0

///|
pub let viewer_tool_icon : Double = 18.0

///|
/// The room the window's buttons have in the app's top row, past the bar's own 12 (84 in all).
let viewer_buttons_w : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_box : @ui.Style = @ui.css("w=Full")

///|
/// Its row: all its 45 (no line under it: its glass sets it apart from what goes under it), its buttons as far under
/// its top as a page's bar's (bar_keys_top: that bar's 45 has its line under them), 12 in at its start, 16 between its
/// three parts (its end's room viewer_bar's).
// kept across runs: a value (no field of it changes)
let viewer_bar_row : @ui.Style = @ui.css("row w=Full pl=S3 gap=S4 align=ACenter").then(
  @ui.style(h=Fixed(viewer_bar_h), pb=room(hairline_h)),
)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_buttons : @ui.Style = @ui.style(w=Fixed(viewer_buttons_w), h=Full)

///|
/// (its row's px)
pub let viewer_bar_in : Double = 12.0

///|
/// Whether the way back stands at the window's top left corner: no buttons of the system's there (window_keys_left),
/// the bar in the window's whole, not a pane's (in_pane, as bar_keys_link has the bar's last key at its right).
pub fn viewer_back_at_corner() -> Bool {
  !@ui.window_keys_left() && !in_pane()
}

///|
/// The corner of the way back at the window's top left corner (viewer_back_at_corner): the window's followed from as far
/// in as it stands from the bar's top (bar_keys_top), a block concentric with it where the window's corner lets one
/// follow it (a Mac's 16, 6 in: 11.2), as a page's bar's last key at its right is (window_corner_key); `alone` (the
/// theme's Xl) where it cannot.
pub fn viewer_back_corner(alone : Double) -> @ui.CornerOf {
  Follow(Window, bar_keys_top(), alone)
}

///|
/// How far in from the window's left the way back stands at the window's corner (viewer_back_at_corner): as far as from
/// the bar's top where it follows the window's corner there (viewer_back_corner, `alone` round where it cannot), else
/// the bar's 12.
pub fn viewer_bar_start_in(alone : Double, roots : @ui.CornerRoots) -> Double {
  if viewer_back_corner(alone).follows(roots) {
    bar_keys_top()
  } else {
    viewer_bar_in
  }
}

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_start : @ui.Style = @ui.style(row=true, w=grow, align=ACenter, clip=true)

///|
/// Its tools at its end, as far apart as makes each a press's room across (keys_gap).
fn viewer_bar_end() -> @ui.Style {
  @ui.style(row=true, w=grow, gap=keys_gap(), align=ACenter, justify=JEnd)
}

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_middle : @ui.Style = @ui.css("align=ACenter clip")

///|
/// The way back (ViewerBar.css.ts back): 32 high, 4 before the chevron and 10 after the words, the page's corner.
// kept across runs: a value (no field of it changes)
let viewer_back_box : @ui.Style = @ui.css("row h=S8 pl=S1 pr=S2_5 gap=S0_5 align=ACenter radius=Xl")

///|
/// Words in the bar: the way back's and the name 13 on 20 (the name in 600), what is said of it 11 on 16.
// kept across runs: a value (no field of it changes)
let viewer_back_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let viewer_name_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let viewer_meta_words : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4, wrap=false)

///|
/// How tall a bar's tools are (viewer_tool_box's S8): a button in words among them too (button).
let viewer_tool_h : Double = 32.0

///|
/// A tool (page.css.ts iconBtn): 32, round, as a bar's buttons are (in the corner of a bar 44 high, 6 in, as round as
/// it is there), the bar's hover under the pointer, its chosen ground on (viewer_lit).
// kept across runs: a value (no field of it changes)
let viewer_tool_box : @ui.Style = @ui.css(
  #|w=S8 h=S8 radius=Full align=ACenter justify=JCenter disabled{opacity=O35}
)

///|
/// What a bar's buttons are under the pointer and while on: its ink's hover and chosen grounds.
pub fn viewer_lit(ink : ViewerInk) -> @ui.Style {
  @ui.style(hovered=@ui.patch(bg=Data(ink.hover)), selected=@ui.patch(bg=Data(ink.chosen)))
}
