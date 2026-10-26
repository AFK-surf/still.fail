// A picture or a film with media controls floating over it (web/ui viewer/media.css.ts: the app's video viewer, the
// drive's player, player.mbt): the controls' bar that fades (the picture's glass: the raised ground at 72%, solid
// here, as a native view under it cannot be blurred), a timeline, the buttons in its corners, the speed as a figure.

///|
/// The controls' bar (vvBar): as wide as 1080 allows less 16 either side, 16 off the foot, 2 over its timeline and the
/// ladder's inset round the rest, a card of the ladder's (its round buttons in its corners concentric with it); on the
/// raised ground at 72%. It fades out in 320 ms, back in 120.
pub let media_bar_most : Double = 1080.0

///|
pub let media_bar_in : Double = 16.0

///|
/// (its round buttons, 32, in its foot corners concentric with it: capsule_in, 8.87 in a card's 26)
pub let media_bar_pad : Double = capsule_in(card_corner, media_key_d)

///|
/// Over its timeline, in the bar; its buttons' size (vvBtn: 32 across); so the bar is this tall, its timeline and a row
/// of its buttons between its pads: what a picture fitted clear of it keeps off (player.mbt desk_play_room).
pub let media_bar_top : Double = 2.0

///|
pub let media_key_d : Double = 32.0

///|
pub let media_bar_h : Double = media_bar_top + media_timeline_h + media_key_d + media_bar_pad

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
/// The colours of what floats over a film or a song: its words, what is quieter, the controls' ground, and the stage
/// under it all.
pub(all) struct MediaInk {
  text : Int64
  muted : Int64
  ground : Int64
  stage : Int64
}

///|
/// Over a picture, whatever the theme: black under it (a film is watched on the dark, its frame no white round it), the
/// words near white on a deep tint (the picture's glass; a native view under it cannot be blurred: solid). A song has
/// no picture: the page's own colours (`picture` false).
pub fn media_ink(picture : Bool) -> MediaInk {
  if picture {
    { text: media_dark_text, muted: media_dark_muted, ground: media_dark_ground, stage: media_dark_stage }
  } else {
    let p = theme().p
    { text: p.text, muted: p.muted, ground: media_ground(), stage: p.canvas }
  }
}

///|
/// Over a picture: the words, the quieter ones, the tint (darkGlass's 0x121214, deeper with no blur), the stage.
pub let media_dark_text : Int64 = 0xF4F4F5FFL

///|
pub let media_dark_muted : Int64 = 0xFFFFFF99L

///|
pub let media_dark_ground : Int64 = 0x121214D9L

///|
pub let media_dark_stage : Int64 = 0x000000FFL

///|
/// A button's ground under the pointer (the words at 10%) and while what it turns on is on (16%).
let media_hot_share : Double = 0.1

///|
let media_lit_share : Double = 0.16

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
/// A round head `part` along its track (vvHeadRail, vvHead: centred where it is, a shadow under it), `r` its half; in a
/// timeline (`rail`: its track in by the timeline's px, media_timeline_box) on the track, not the timeline's whole
/// width (a layer is its parent's whole box).
pub fn media_head(c : @ui.Ctx, part : Double, color : Int64, small? : Bool = false, rail? : Bool = false) -> Unit {
  let (room, head, r) = if small {
    (media_small_head_room, media_small_head, media_small_head_r)
  } else {
    (media_head_room, media_head_disc, media_head_r)
  }
  c.box(style=if rail { media_head_rail } else { media_head_row }, fn() {
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
/// One of the controls' buttons (page.css.ts iconBtn in vvBar: 32, round, as the speed by them is: the first and the
/// last in the bar's corners, 10 in, concentric with its 26): a 20 icon (18
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
  ink? : MediaInk,
) -> Bool {
  let ink = ink.unwrap_or(media_ink(false))
  let id = c.id(key)
  let hot = on && (c.lit(id) || c.pressed(id))
  let ground = if lit { alpha(ink.text, media_lit_share) } else if hot { alpha(ink.text, media_hot_share) } else { no_ground }
  let b = c.box(style=media_key_box.then(@ui.style(bg=Data(ground))), disabled=!on, id=if on { id } else { 0 }, fn() {
    icon(c, icon_name, size=if small { viewer_tool_icon } else { viewer_back_icon }, color=if bright || hot || lit { ink.text } else { ink.muted })
    |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled=!on, pressed=lit)
  if on {
    tip(c, key + "/tip", id, label)
  }
  on && c.clicked(id)
}

///|
/// The speed as a figure (vvRate): 28 high, 46 wide at least, 8 in, a capsule concentric in the bar's corner, on the words at 10%. True on the
/// frame after it was pressed.
pub fn media_rate(c : @ui.Ctx, key : String, words : String, label : String, on : Bool, ink? : MediaInk) -> Bool {
  let ink = ink.unwrap_or(media_ink(false))
  let id = c.id(key)
  let b = c.box(style=media_rate_box.then(@ui.style(bg=Data(alpha(ink.text, media_rate_share)))), id=if on { id } else { 0 }, fn() {
    c.rich([@ui.span(words, weight=media_strong, mono=true, color=ink.text)], style=media_rate_words) |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled=!on)
  // (named on hover, as the keys beside it: SpeedMenu's Tip)
  if on {
    tip(c, key + "/tip", id, label)
  }
  on && c.clicked(id)
}

///|
/// What is said in the code face in the bar (vvInfo, vvNow): the time where it is in 600.
pub let media_strong : Int = 600

///|
// kept across runs: a value (no field of it changes)
pub let media_bar_box : @ui.Style = @ui.css("radius=Xl3").then(
  @ui.style(pt=room(media_bar_top), pl=room(media_bar_pad), pr=room(media_bar_pad), pb=room(media_bar_pad)),
)

///|
// kept across runs: a value (no field of it changes)
pub let media_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let media_group : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let media_time_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
// kept across runs: a value (no field of it changes)
pub let media_timeline_box : @ui.Style = @ui.style(w=Full, h=Fixed(media_timeline_h), px=S2_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
pub let media_track : @ui.Style = @ui.css("w=Full h=S1 radius=Full clip")

///|
// kept across runs: a value (no field of it changes)
pub let media_head_row : @ui.Style = @ui.css("row w=Full h=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let media_head_rail : @ui.Style = media_head_row.then(@ui.css("px=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let media_head_room : @ui.Style = @ui.css("w=S0 h=S3")

///|
// kept across runs: a value (no field of it changes)
let media_head_disc : @ui.Style = @ui.css("w=S3 h=S3 radius=Full shadow=Sm")

///|
/// A smaller head (the volume's, Player.css.ts volumeHead: 10 across).
let media_small_head_r : Double = 5.0

///|
// kept across runs: a value (no field of it changes)
let media_small_head_room : @ui.Style = @ui.css("w=S0 h=S2_5")

///|
// kept across runs: a value (no field of it changes)
let media_small_head : @ui.Style = @ui.css("w=S2_5 h=S2_5 radius=Full shadow=Sm")

///|
// kept across runs: a value (no field of it changes)
let media_rate_box : @ui.Style = @ui.style(
  h=S7,
  min_w=Fixed(media_rate_w),
  px=S2,
  mr=capsule_room(card_corner, media_rate_h, less=media_bar_pad),
  radius=Full,
  align=ACenter,
  justify=JCenter,
)

///|
let media_rate_w : Double = 46.0

///|
/// The speed's height (28: S7).
let media_rate_h : Double = 28.0

///|
// kept across runs: a value (no field of it changes)
let media_rate_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let media_key_box : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter disabled{opacity=O35}").then(
  @ui.style(w=Fixed(media_key_d), h=Fixed(media_key_d)),
)
