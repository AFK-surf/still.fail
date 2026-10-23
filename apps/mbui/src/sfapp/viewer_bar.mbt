// The bar every file opened shows across the window's top on a desktop (ember @stillfail/ui viewer/ViewerBar.tsx,
// ViewerBar.css.ts): a picture's, a PDF's or code's preview (preview.mbt), a text read (drive_reader.mbt), a film
// played (play.mbt). Always there, along the window's top, 45 high: the way back on the left (where to, by name), the
// file's name and a line about it in the middle, its tools on the right as icons, download last. Its ground is the
// file's (the paper under a text) at 82% over a 20 blur, saturated, a line of its own under it at 70%; it drags the
// window, clear of the window's buttons where they are in the app's top row. Gone up out of the way (a picture left
// alone, a text read on down) it slides up its height and fades (240 ms, ease-out), and takes no presses.

///|
/// The colours a bar is drawn in: the file's ground under it, its words, what is quieter, its line.
priv struct ViewerInk {
  ground : Int64
  ink : Int64
  muted : Int64
  line : Int64
}

///|
/// The page's own (a preview's: the canvas, the page's words).
fn page_viewer_ink() -> ViewerInk {
  let p = @sf.theme().p
  { ground: p.canvas, ink: p.text, muted: p.muted, line: p.line }
}

///|
/// The bar (`key` its own): back to `back`, `name` and `meta` under it, `tools` at its end (viewer_tool,
/// viewer_download); `hidden`, gone up out of the way. True on the frame after its way back was pressed.
fn viewer_bar(
  c : @ui.Ctx,
  key : String,
  back : String,
  name : String,
  meta : String,
  hidden : Bool,
  ink : ViewerInk,
  tools : () -> Unit,
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
    tint=@sf.alpha(ink.ground, viewer_bar_share),
    solid=ink.ground,
    saturation=viewer_bar_saturation,
  )
  let mut went = false
  let node = c.box(style=viewer_bar_box, glass~, id=if live { bar } else { 0 }, fn() {
    c.box(style=viewer_bar_row, fn() {
      // clear of the window's buttons (ViewerBar.css.ts: 84 in, not in full screen)
      if @ui.window_inset() {
        c.box(style=viewer_bar_buttons, fn() {  }) |> ignore
      }
      c.box(style=viewer_bar_start, fn() {
        let id = c.id(key + "/back")
        c.cursor(id, Hand)
        if live && c.clicked(id) {
          went = true
        }
        let b = c.box(style=viewer_back_box, id=if live { id } else { 0 }, fn() {
          @sf.icon(c, "chevron-left", size=viewer_back_icon, color=ink.ink) |> ignore
          c.text(back, style=viewer_back_words.then(@ui.text_style(color=Data(ink.ink)))) |> ignore
        })
        c.semantics(b, Button, id~, label=back)
      })
      |> ignore
      // the middle, as wide as what it says, the sides kept for the way back and the tools
      let most = dmax(viewer_none, c.width - viewer_bar_sides)
      c.box(style=viewer_bar_middle.then(@ui.style(max_w=Fixed(most))), fn() {
        c.text(name, style=viewer_name_words.then(@ui.text_style(color=Data(ink.ink)))) |> ignore
        if meta != "" {
          c.text(meta, style=viewer_meta_words.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        }
      })
      |> ignore
      c.box(style=viewer_bar_end, tools) |> ignore
    })
    |> ignore
    c.box(style=viewer_bar_rule.then(@ui.style(bg=Data(@sf.alpha(ink.line, viewer_line_share)))), fn() {  })
    |> ignore
  })
  c.look(node, @ui.look(alpha=1.0 - gone, dy=-viewer_bar_h * gone))
  went
}

///|
/// One of a bar's tools (ViewerBar.tsx ViewerTool): an 18 icon in a 32 button, in the file's quieter ink until
/// pointed at or `on` (its ground then the page's chosen one), named on hover. True on the frame after it was pressed.
fn viewer_tool(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : String,
  ink : ViewerInk,
  on? : Bool = false,
  disabled? : Bool = false,
) -> Bool {
  let id = c.id(key)
  let live = !disabled
  if live {
    c.cursor(id, Hand)
  }
  let hot = live && (c.hovered(id) || c.pressed(id))
  let b = c.box(style=viewer_tool_box, selected=on, disabled~, id=if live { id } else { 0 }, fn() {
    @sf.icon(c, icon, size=viewer_tool_icon, color=if on || hot { ink.ink } else { ink.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~, pressed=on, disabled~)
  if live {
    @kit.tooltip(c, key + "/tip", id, label, side=Bottom) |> ignore
  }
  live && c.clicked(id)
}

///|
/// Download, as every bar has it last (ViewerDownload). True on the frame after it was pressed.
fn viewer_download(c : @ui.Ctx, key : String, ink : ViewerInk, disabled? : Bool = false) -> Bool {
  viewer_tool(c, key, "download", tr("web-main.preview.download"), ink, disabled~)
}

///|
/// How tall the bar is (VIEWER_BAR: a page's bar, its 32 buttons level with the window's): what is under it starts
/// below it or goes under it.
let viewer_bar_h : Double = 45.0

///|
/// Its going and coming (ViewerBar.css.ts: transform and opacity, 240 ms ease-out).
let viewer_bar_ms : Double = 240.0

///|
/// Its glass: the ground at 82% over a 20 blur, saturated 1.4; its line at 70%.
let viewer_bar_share : Double = 0.82

///|
let viewer_bar_blur : Double = 20.0

///|
let viewer_bar_saturation : Double = 1.4

///|
let viewer_line_share : Double = 0.7

///|
/// What the middle leaves its sides at least: the way back's and the tools' room either side (as the grid's equal
/// sides keep it in the middle).
let viewer_bar_sides : Double = 320.0

///|
let viewer_none : Double = 0.0

///|
let viewer_back_icon : Double = 20.0

///|
let viewer_tool_icon : Double = 18.0

///|
/// The room the window's buttons have in the app's top row, past the bar's own 12 (84 in all).
let viewer_buttons_w : Double = 72.0

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_box : @ui.Style = @ui.style(w=Full)

///|
/// Its row: 44 of its 45 (the line under it the last), 12 in, 16 between its three parts.
// kept across runs: a value (no field of it changes)
let viewer_bar_row : @ui.Style = @ui.style(row=true, w=Full, h=S11, px=S3, gap=S4, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_buttons : @ui.Style = @ui.style(w=Fixed(viewer_buttons_w), h=Full)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_start : @ui.Style = @ui.style(row=true, w=@sf.grow, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_end : @ui.Style = @ui.style(row=true, w=@sf.grow, gap=S0_5, align=ACenter, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_middle : @ui.Style = @ui.style(align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let viewer_bar_rule : @ui.Style = @ui.style(w=Full, h=SPx)

///|
/// The way back (ViewerBar.css.ts back): 32 high, 4 before the chevron and 10 after the words, the page's corner.
// kept across runs: a value (no field of it changes)
let viewer_back_box : @ui.Style = @ui.style(
  row=true,
  h=S8,
  pl=S1,
  pr=S2_5,
  gap=S0_5,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Hover),
)

///|
/// Words in the bar: the way back's and the name 13 on 20 (the name in 600), what is said of it 11 on 16.
// kept across runs: a value (no field of it changes)
let viewer_back_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let viewer_name_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let viewer_meta_words : @ui.TextStyle = @ui.text_style(size=Xs2, leading=L4, wrap=false)

///|
/// A tool (page.css.ts iconBtn): 32, the page's corner, the page's hover under the pointer, its chosen ground on.
// kept across runs: a value (no field of it changes)
let viewer_tool_box : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Xl,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
  disabled=@ui.patch(opacity=O35),
)
