// A picture or a film with media controls floating over it (web/ui viewer/media.css.ts: the app's video viewer, the
// drive's player, player.mbt): the controls' bar that fades (the picture's glass: the raised ground at 72%, solid
// here, as a native view under it cannot be blurred), a timeline, the buttons in its corners, the speed as a figure.

///|
/// The controls' bar (vvBar): as wide as 1080 allows less 16 either side, 16 off the foot, 2 over its timeline and 6
/// round the rest, its corner 16; on the raised ground at 72%. It fades out in 320 ms, back in 120.
pub let media_bar_most : Double = 1080.0

///|
pub let media_bar_in : Double = 16.0

///|
pub let media_bar_pad : Double = 6.0

///|
pub let media_glass_share : Double = 0.72

///|
/// The speed's ground (vvRate): the words at 10%; the timeline's track (vvTrack) the words at 20%, what has come at
/// 22% over it (Player.css.ts buffered).
pub let media_rate_share : Double = 0.1

///|
pub let media_track_share : Double = 0.2

///|
pub let media_came_share : Double = 0.22

///|
/// The timeline (vvTimeline): 22 high, 10 in from the bar's sides; its head (vvHead) 12 across, centred on where it is.
pub let media_timeline_h : Double = 22.0

///|
let media_head_r : Double = 6.0

///|
let media_whole : Double = 1.0

///|
/// The bar's ground over `canvas` (the picture's glass, solid).
pub fn media_ground() -> Int64 {
  let p = theme().p
  over(p.canvas, alpha(p.raised, media_glass_share))
}

///|
/// `part` of a track from its start, in `color`.
pub fn media_share_bar(c : @ui.Ctx, part : Double, color : Int64) -> Unit {
  c.box(style=media_head_row, fn() {
    c.box(style=@ui.style(w=Grow(part), h=Full, bg=Data(color)), fn() {  }) |> ignore
    c.box(style=@ui.style(w=Grow(media_whole - part), h=Full), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A round head `part` along its track (vvHeadRail, vvHead: centred where it is, a shadow under it), `r` its half.
pub fn media_head(c : @ui.Ctx, part : Double, color : Int64, small? : Bool = false) -> Unit {
  let (room, head, r) = if small {
    (media_small_head_room, media_small_head, media_small_head_r)
  } else {
    (media_head_room, media_head_disc, media_head_r)
  }
  c.box(style=media_head_row, fn() {
    c.box(style=@ui.style(w=Grow(part)), fn() {  }) |> ignore
    c.box(style=room, fn() {
      c.box(style=head.then(@ui.style(bg=Data(color))), tx=-r, fn() {  }) |> ignore
    })
    |> ignore
    c.box(style=@ui.style(w=Grow(media_whole - part)), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// One of the controls' buttons (page.css.ts iconBtn in vvBar: 32, its corner the bar's less 6): a 20 icon (18
/// `small`), in the quieter ink until pointed at, a bright one's (play) in the words'; `lit` while what it turns on is.
/// Named on hover. True on the frame after it was pressed.
pub fn media_key(
  c : @ui.Ctx,
  key : String,
  icon_name : String,
  label : String,
  on : Bool,
  small? : Bool = false,
  bright? : Bool = false,
  lit? : Bool = false,
) -> Bool {
  let pal = theme().p
  let id = c.id(key)
  if on {
    c.cursor(id, Hand)
  }
  let hot = on && (c.hovered(id) || c.pressed(id))
  let b = c.box(style=media_key_box, selected=lit, disabled=!on, id=if on { id } else { 0 }, fn() {
    icon(c, icon_name, size=if small { viewer_tool_icon } else { viewer_back_icon }, color=if bright || hot || lit { pal.text } else { pal.muted })
    |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled=!on, pressed=lit)
  if on {
    tip(c, key + "/tip", id, label)
  }
  on && c.clicked(id)
}

///|
/// The speed as a figure (vvRate): 28 high, 46 wide at least, 8 in, its corner 10, on the words at 10%. True on the
/// frame after it was pressed.
pub fn media_rate(c : @ui.Ctx, key : String, words : String, label : String, on : Bool) -> Bool {
  let pal = theme().p
  let id = c.id(key)
  if on {
    c.cursor(id, Hand)
  }
  let b = c.box(style=media_rate_box.then(@ui.style(bg=Data(alpha(pal.text, media_rate_share)))), id=if on { id } else { 0 }, fn() {
    c.rich([@ui.span(words, weight=media_strong, mono=true)], style=media_rate_words) |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled=!on)
  on && c.clicked(id)
}

///|
/// What is said in the code face in the bar (vvInfo, vvNow): the time where it is in 600.
pub let media_strong : Int = 600

///|
// kept across runs: a value (no field of it changes)
pub let media_bar_box : @ui.Style = @ui.style(pl=S1_5, pr=S1_5, pt=S0_5, pb=S1_5, radius=Xl1_5)

///|
// kept across runs: a value (no field of it changes)
pub let media_row : @ui.Style = @ui.style(row=true, w=Full, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
pub let media_group : @ui.Style = @ui.style(row=true, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
pub let media_time_words : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
// kept across runs: a value (no field of it changes)
pub let media_timeline_box : @ui.Style = @ui.style(w=Full, h=Fixed(media_timeline_h), px=S2_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
pub let media_track : @ui.Style = @ui.style(w=Full, h=S1, radius=Full, clip=true)

///|
// kept across runs: a value (no field of it changes)
pub let media_head_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let media_head_room : @ui.Style = @ui.style(w=S0, h=S3)

///|
// kept across runs: a value (no field of it changes)
let media_head_disc : @ui.Style = @ui.style(w=S3, h=S3, radius=Full, shadow=Sm)

///|
/// A smaller head (the volume's, Player.css.ts volumeHead: 10 across).
let media_small_head_r : Double = 5.0

///|
// kept across runs: a value (no field of it changes)
let media_small_head_room : @ui.Style = @ui.style(w=S0, h=S2_5)

///|
// kept across runs: a value (no field of it changes)
let media_small_head : @ui.Style = @ui.style(w=S2_5, h=S2_5, radius=Full, shadow=Sm)

///|
// kept across runs: a value (no field of it changes)
let media_rate_box : @ui.Style = @ui.style(h=S7, min_w=Fixed(media_rate_w), px=S2, radius=Lg, align=ACenter, justify=JCenter)

///|
let media_rate_w : Double = 46.0

///|
// kept across runs: a value (no field of it changes)
let media_rate_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let media_key_box : @ui.Style = @ui.style(
  w=S8,
  h=S8,
  radius=Lg,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
  selected=@ui.patch(bg=Selected),
  disabled=@ui.patch(opacity=O35),
)
