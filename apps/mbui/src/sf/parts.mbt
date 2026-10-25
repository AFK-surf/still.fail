// still.fail's parts (web/ui parts.tsx, styles/controls.css.ts, page.css.ts,
// waiting.tsx), drawn with mbui: buttons, icon buttons, chips, a segmented
// choice, small panels and their rows, page heads and cards, and the three
// ways of waiting.

///|
/// A hover's or a press's ground coming and going over --dur on the ease-out (dur_ms).
fn ease_to(c : @ui.Ctx, key : String, on : Bool) -> Double {
  @motion.animate(c, key, if on { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out))
}

///|
/// For parts whose own parameter is called `icon`.
fn draw_icon(c : @ui.Ctx, name : String, size : Double, color : Int64) -> Unit {
  icon(c, name, size~, color~) |> ignore
}

///|
/// What a button is (controls.css.ts): `Plain` lined, on the canvas;
/// `Primary` the one thing to do, solid; `Ghost` words alone, a ground
/// under the pointer; `Danger` lined, its words red; `DangerSolid` solid red.
pub(all) enum Tone {
  Plain
  Primary
  Ghost
  Danger
  DangerSolid
  /// a ghost's in the red (controls.css.ts btnGhost with btnDanger: 删除 beside a dialog's other buttons)
  GhostDanger
} derive(Eq)

///|
/// A button (Button): a 36 pill on the wide screen, the phone's 38 one on a
/// narrow; an icon before its words if given, a spinner in its place while
/// `busy`; `reach`, where it stands in a card's foot corners: how its ground reaches past the card's words
/// (foot_across). True on the frame after it was pressed.
pub fn button(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  tone? : Tone = Plain,
  icon? : String = "",
  busy? : Bool = false,
  disabled? : Bool = false,
  w? : @ui.Size = Auto,
  reach? : @ui.Style,
) -> Bool {
  let t = theme()
  let p = t.p
  let id = c.id(if key == "" { "sf-btn/" + label } else { key })
  let live = !disabled && !busy
  let h = ease_to(c, "sf-btn-h/\{id}", live && (c.lit(id) || c.pressed(id)))
  let (ground, line, ink) = if t.narrow {
    match tone {
      Primary => (p.text, p.text, p.bg)
      DangerSolid => (p.red, p.red, 0xFFFFFFFFL)
      Danger => (p.chip, p.chip, p.red)
      Ghost => (alpha(p.hover, h), 0L, p.text)
      GhostDanger => (alpha(p.hover, h), 0L, p.red)
      Plain => (p.chip, p.chip, p.text)
    }
  } else {
    match tone {
      Primary => {
        let g = mix(p.primary_hover, h, p.primary)
        (g, g, p.on_primary)
      }
      DangerSolid => {
        let g = mix(mix(p.red, 0.85, 0x000000FFL), h, p.red)
        (g, g, 0xFFFFFFFFL)
      }
      Ghost => (alpha(p.hover, h), 0L, p.text)
      GhostDanger => (alpha(p.hover, h), 0L, p.red)
      Danger => (over(p.canvas, alpha(p.hover, h)), p.line_strong, p.red)
      Plain => (over(p.canvas, alpha(p.hover, h)), p.line_strong, p.text)
    }
  }
  let height = button_height()
  let solid = tone == Primary || tone == DangerSolid
  // (at a sheet's foot, in a thumb's reach: its share of the foot's width, the presenters')
  let w = if w is Auto && foot_fills.val { @ui.Fill(1.0) } else { w }
  c.box(
    style=reach.unwrap_or(@ui.style()),
    dir=Row,
    w~,
    h=Px(height),
    padx=16.0,
    gap=if t.narrow { 8.0 } else { 6.0 },
    align=ACenter,
    justify=JCenter,
    bg=ground,
    radius=height / 2.0,
    border=if line != 0L && line != ground { 1.0 } else { 0.0 },
    border_color=line,
    opacity=if disabled { 0.45 } else if busy { 0.7 } else { 1.0 },
    id=if live { id } else { 0 },
    fn() {
      if busy {
        spinner(
          c,
          ring=if solid { alpha(ink, 0.3) } else { p.line_strong },
          arc=if solid { ink } else { p.accent },
        )
        |> ignore
      } else if icon != "" {
        draw_icon(c, icon, 16.0, ink)
      }
      c.text(
        label,
        size=t.t.ui,
        weight=if t.narrow { 600 } else { 500 },
        color=ink,
        wrap=false,
        line=t.t.ui_line,
      )
      |> ignore
    },
  )
  |> ignore
  live && c.clicked(id)
}

///|
/// Whether a button laid out now is at a sheet's foot (the presenters' sheet_body says so while it draws one): each
/// of its buttons as wide as the others, across the sheet (the phone's sheets' primary button, Button in mPad).
let foot_fills : Ref[Bool] = { val: false }

///|
/// A button's height in the theme in force: the phone's 38 on a narrow, else button_h.
pub fn button_height() -> Double {
  if theme().narrow {
    38.0
  } else {
    button_h
  }
}

///|
/// An icon button (page.css.ts iconBtn): `size` square (32), its corner 12,
/// the icon (16) quiet until pointed at; `on` held down (aria-pressed).
/// `ink` and `quiet` for one over a ground of its own (the reader's paper).
pub fn icon_button(
  c : @ui.Ctx,
  icon : String,
  key? : String = "",
  size? : Double = 32.0,
  icon_size? : Double = 16.0,
  on? : Bool = false,
  round? : Bool = false,
  ink? : Int64,
  quiet? : Int64,
  disabled? : Bool = false,
  label? : String = "",
) -> Bool {
  let t = theme()
  // (a finger's: 44 at least, the icon in its middle)
  let size = finger_side(size)
  let ink = ink.unwrap_or(t.p.text)
  let quiet = quiet.unwrap_or(t.p.muted)
  let id = c.id(if key == "" { "sf-ib/" + icon } else { key })
  let h = ease_to(c, "sf-ib-h/\{id}", !disabled && (c.lit(id) || c.pressed(id)))
  let ground = if on {
    alpha(ink, 0.08)
  } else {
    // the page's hover, as a tint of the ink it sits with
    alpha(ink, 0.065 * h)
  }
  let b = c.box(
    w=Px(size),
    h=Px(size),
    align=ACenter,
    justify=JCenter,
    bg=ground,
    radius=if round { size / 2.0 } else { r_field },
    opacity=if disabled { 0.35 } else { 1.0 },
    id=if disabled { 0 } else { id },
    fn() {
      draw_icon(c, icon, icon_size, if on || h > 0.5 { ink } else { quiet })
    },
  )
  // named (IconButton's label): what a screen reader calls it, and its tip
  if label != "" {
    c.semantics(b, Button, id~, label~, disabled~)
    tip(c, "ib/" + key + icon, id, label)
  }
  !disabled && c.clicked(id)
}

///|
/// A chip (the reader's bars, Reader.css.ts chip): 30 high, its corner 10 (`inner`: in a rounded surface's corner,
/// concentric with it), on a 7% tint of the ink, 12% under the pointer; its words small.
pub fn chip(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  ink? : Int64,
  disabled? : Bool = false,
  inner? : Bool = false,
) -> Bool {
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let id = c.id(if key == "" { "sf-chip/" + label + icon } else { key })
  let h = ease_to(c, "sf-chip-h/\{id}", !disabled && c.lit(id))
  c.box(
    dir=Row,
    h=Px(30.0),
    min_w=30.0,
    padx=if label == "" { 0.0 } else { 10.0 },
    gap=2.0,
    align=ACenter,
    justify=JCenter,
    bg=alpha(ink, 0.07 + 0.05 * h),
    style=if inner { chip_inner } else { @ui.style() },
    radius?=if inner { None } else { Some(10.0) },
    opacity=if disabled { 0.35 } else { 1.0 },
    id=if disabled { 0 } else { id },
    fn() {
      if icon != "" {
        draw_icon(c, icon, 16.0, ink)
      }
      if label != "" {
        c.text(label, size=t.t.meta, color=ink, wrap=false, line=18.0) |> ignore
      }
    },
  )
  |> ignore
  !disabled && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let chip_inner : @ui.Style = @ui.css("radius=Inner")

///|
/// How far an option's words stand in from its column's sides (segmentedOption: 0 12), and how little they may where
/// the room is short (option_widths).
let segmented_in : Double = 12.0

///|
let segmented_least : Double = 8.0

///|
/// How far its track's ground stands out round its options, and how far apart they are (segmented's --gap).
let segmented_pad : Double = 3.0

///|
let segmented_gap : Double = 2.0

///|
/// Its options in a line, 2 apart.
// kept across runs: a value (no field of it changes)
let segmented_strip : @ui.Style = @ui.css("row gap=S0_5")

///|
/// A choice of a few (Segmented; the kit's sliding toggle group): a quiet pill track, the chosen raised on the canvas
/// and sliding to it; its options equal columns, as wide as the widest in the chosen weight with 12 either side
/// (segmented, segmentedOption, segmentedSizer), `item_w` at least, the track never wider than where it is. Where those
/// columns need more room than there is, the track takes what there is and its options share it as option_widths has
/// them: as alike as their words let them, their sides narrower, else their words smaller alike (to the system's own
/// size of words), else the chosen one alone in the track, the others in a pick (choice_pick). Always one line, each
/// one's words whole: nothing wrapped, cut or scrolled. Returns the chosen index.
pub fn segmented(
  c : @ui.Ctx,
  key : String,
  labels : Array[String],
  chosen : Int,
  item_w? : Double = 0.0,
  ink? : Int64,
  thumb? : Int64,
) -> Int {
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let thumb = thumb.unwrap_or(t.p.canvas)
  // its words as drawn (the system's size of words applied), in the chosen weight (as wide unchosen as chosen: no
  // column changes as the choice does)
  let size = c.sp(t.t.ui)
  let words = labels.map(fn(l) { @ui.text_advance(l, size~, weight=500) })
  let widest = words.fold(init=0.0, fn(m, w) { dmax(m, w) })
  let col = dmax(item_w, widest + 2.0 * segmented_in)
  let n = labels.length()
  let gaps = segmented_gap * (n - 1).to_double()
  let whole = col * n.to_double() + gaps + 2.0 * segmented_pad
  // the room the track had as last laid out (cut to where it is: read back, built again in the frame it is laid out
  // otherwise): less than its columns need, its options give way from them to what option_widths has them in it
  // (their columns as wide where the room is, the track then laid out as wide as they need)
  let track = c.id(key + "/track")
  let fit = match c.laid_size(track) {
    Some((w, _)) if w < whole - 0.5 =>
      Some(fitted(c, labels, w - 2.0 * segmented_pad - gaps, t.t.ui, 500, segmented_in, segmented_least))
    _ => None
  }
  // its track: round its options (as wide as they are, cut to where it is), or round the chosen one where they do not
  // fit side by side (as wide as where it is)
  let track_box = fn(wide : Bool, inner : () -> Unit) -> Int {
    c.box(
      style=if wide { segmented_track_wide } else { segmented_track },
      id=track,
      pad=segmented_pad,
      bg=alpha(ink, 0.06),
      radius=segmented_corner + segmented_pad,
      inner,
    )
  }
  // an option: its words in its middle, in the chosen weight and the ink where chosen (`on`), in the ink pointed at
  // (`lit`); short of room, their least in from its sides
  let option = fn(label : String, on : Bool, lit : Bool) {
    c.box(h=Px(segmented_h), padx?=fit.map(fn(_) { segmented_least }), align=ACenter, justify=JCenter, fn() {
      c.text(
        label,
        size=t.t.ui,
        weight=if on { 500 } else { 400 },
        color=if on || lit { ink } else { t.p.muted },
        wrap=false,
      )
      |> ignore
    })
    |> ignore
  }
  // (not side by side: the chosen one in its track, as wide as where it is, a chevron at its end; all of them in a
  // pick)
  if fit is Some({ fit: Menu, .. }) {
    return choice_pick(c, key, track, labels, chosen, fn(_, _, words) {
      track_box(true, fn() {
        c.box(style=segmented_menu, fn() {
          option(words, true, false)
          icon(c, "chevron-down", size=segmented_chevron, color=t.p.muted) |> ignore
        })
        |> ignore
      })
    })
  }
  let items = labels.mapi(fn(i, l) { @kit.item(i.to_string(), label=l) })
  // (made smaller to fit: their words drawn that much smaller)
  let smaller = match fit {
    Some({ fit: Smaller(k), .. }) => k
    _ => 1.0
  }
  let now = c.words_smaller(smaller, fn() {
    @kit.toggle_group(
      c,
      key,
      items,
      [chosen.to_string()],
      slide=true,
      widths=match fit {
        Some(f) => f.widths.map(fn(w) { (col, w) })
        None => Array::make(n, (col, col))
      },
      look=fn(_, s) { option(s.label, s.on, s.hovered) },
      thumb=fn(c, w, h) {
        c.box(
          w=Px(w),
          h=Px(h),
          bg=thumb,
          radius=segmented_corner,
          border=0.5,
          border_color=t.p.line,
          shadow=1.0,
          shadow_color=t.p.shadow,
          shadow_y=0.0,
          fn() {  },
        )
        |> ignore
      },
      ground=fn(c, _, items) { track_box(false, fn() { c.box(style=segmented_strip, items) |> ignore }) |> ignore },
    ).value
  })
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(chosen)
    _ => chosen
  }
}

///|
/// Its track: its options in a line, as wide as they are, cut to where it is; where they do not fit side by side, as
/// wide as where it is.
// kept across runs: a value (no field of it changes)
let segmented_track : @ui.Style = @ui.css("row w=Cut")

///|
// kept across runs: a value (no field of it changes)
let segmented_track_wide : @ui.Style = @ui.css("row w=Full")

///|
/// A segmented choice whose options do not fit side by side (choice_pick), in its track: the chosen one as its option
/// is at its start (its words as far in, cut short where they must be), a chevron at its end; a press on the track
/// opens the pick.
// kept across runs: a value (no field of it changes)
let segmented_menu : @ui.Style = @ui.css("row w=Full pr=S2 gap=S2 align=ACenter justify=JBetween")

///|
let segmented_chevron : Double = 16.0

///|
/// An option's height on one line (segmentedOption: 30), and the thumb's corner, a pill's (the track's concentric
/// round it).
let segmented_h : Double = 30.0

///|
let segmented_corner : Double = 15.0

///|
/// A line to type in, its frame (Controls.kt Field) as a look for mbui's field (@kit.text_field): 12 round, the card's
/// ground, a line round it, its words 12 by 10 in.
pub fn field_look(c : @ui.Ctx, s : @kit.FieldState, editor : () -> Unit) -> Unit {
  c.box(id=s.id, style=field_frame, editor) |> ignore
}

///|
/// Controls.kt Field's frame: as wide as where it is, 12 by 10 in, 12 round, the card's ground, a line round it.
// kept across runs: a value (no field of it changes)
let field_frame : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 radius=Xl bg=Card border=B1 border_color=Line")

// ---------------------------------------------------------------------------
// Small panels (docs/ui-panels.md)

///|
/// A small panel's ground (controls.css.ts popover): the canvas (the raised
/// grey in dark), a line round it, its shadow; padded panel_pad, its corner
/// the menu's. `min_w`: as wide as what it holds, at least that (a menu's,
/// controls.css.ts menuList).
pub fn small_panel(
  c : @ui.Ctx,
  w? : @ui.Size = Auto,
  h? : @ui.Size = Auto,
  min_w? : Double,
  body : () -> Unit,
) -> Int {
  let t = theme()
  c.box(
    w~,
    h~,
    min_w?,
    pad=panel_pad,
    bg=panel_ground(),
    radius=r_menu,
    border=1.0,
    border_color=t.p.line,
    shadow=16.0,
    shadow_y=12.0,
    shadow_color=t.p.shadow,
    clip=true,
    body,
  )
}

///|
/// A row of a small panel (menuItem): at its padding, words text_in in, its
/// ground under the pointer, concentric with the panel. `panel`: a panel's
/// row (parts.tsx PanelRow): its icon 18 in a column 20 wide (`word` in its
/// place, a word for an icon: 奏), 10 from its words, `end` an icon at its
/// end, quiet.
pub fn menu_item(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  danger? : Bool = false,
  on? : Bool = false,
  note? : String = "",
  panel? : Bool = false,
  word? : String = "",
  end? : String = "",
) -> Bool {
  let t = theme()
  let id = c.id(if key == "" { "sf-mi/" + label } else { key })
  let ink = if danger { t.p.red } else if on { t.p.accent_text } else { t.p.text }
  c.box(
    dir=Row,
    min_h=menu_row_min,
    padx=text_in,
    pady=menu_row_over,
    gap=if panel { panel_row_gap } else { menu_row_gap },
    align=ACenter,
    bg=if c.lit(id) { t.p.hover } else { 0L },
    radius=small_panel_inner(r_menu),
    id~,
    fn() {
      if panel && (icon != "" || word != "") {
        c.box(style=panel_row_icon, fn() {
          if word != "" {
            c.text(word, style=panel_row_word) |> ignore
          } else {
            draw_icon(c, icon, panel_icon, t.p.muted)
          }
        })
        |> ignore
      } else if icon != "" {
        draw_icon(c, icon, 16.0, if danger { t.p.red } else { t.p.muted })
      }
      c.text(
        label,
        size=t.t.ui,
        weight=if on { 500 } else { 400 },
        color=ink,
        wrap=false,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
      if note != "" {
        c.text(note, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
      }
      if end != "" {
        draw_icon(c, end, panel_end_icon, t.p.subtle)
      }
    },
  )
  |> ignore
  c.clicked(id)
}

///|
/// Between a menu item's icon and its words (menuItem: 8), a panel row's (panelRow: 10); a panel row's icon (18) and
/// what is at its end (14).
let menu_row_gap : Double = 8.0

///|
let panel_row_gap : Double = 10.0

///|
let panel_icon : Double = 18.0

///|
let panel_end_icon : Double = 14.0

///|
/// A panel row's icon's column (parts.css.ts panelRowIcon): 20 wide, the icon in its middle.
// kept across runs: a value (no field of it changes)
let panel_row_icon : @ui.Style = @ui.css("w=S5 align=ACenter")

///|
/// A word for an icon in a panel's row (Rail.css.ts zouSmall: 14 on 18, 600).
// kept across runs: a value (no field of it changes)
let panel_row_word : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, leading=L5, wrap=false)

// ---------------------------------------------------------------------------
// Pages (styles/pages.css.ts)

///|
/// A page's head: its name (text-heading, 600), a line under it, and its
/// buttons at its end.
pub fn page_head(
  c : @ui.Ctx,
  title : String,
  meta? : String = "",
  actions? : () -> Unit = fn() {  },
) -> Unit {
  let t = theme()
  c.box(dir=Row, gap=16.0, align=AStart, fn() {
    c.box(w=Fill(1.0), gap=4.0, fn() {
      if t.narrow {
        // the phone's place title: display size
        c.text(
          title,
          size=t.t.display,
          weight=600,
          color=t.p.text,
          wrap=false,
          line=34.0,
        )
        |> ignore
      } else {
        c.text(
          title,
          size=t.t.heading,
          weight=600,
          color=t.p.text,
          wrap=false,
          line=34.0,
        )
        |> ignore
      }
      if meta != "" {
        c.text(meta, size=t.t.meta, color=t.p.muted, wrap=false, line=t.t.meta_line)
        |> ignore
      }
    })
    |> ignore
    c.box(dir=Row, gap=6.0, align=ACenter, h=Px(34.0), actions) |> ignore
  })
  |> ignore
}

///|
/// A page card of words (pages.css.ts card): card_pad in from every side, round by the ladder's card step; a solid
/// button in its foot corner stands there itself (foot_reach), its corner the card's whatever is in it.
pub fn card(c : @ui.Ctx, gap? : Double = 14.0, body : () -> Unit) -> Int {
  let t = theme()
  c.box(pad=card_pad, gap~, bg=t.p.card, radius=card_corner, body)
}

///|
/// The words of a card: a title, what it says.
pub fn card_text(c : @ui.Ctx, title : String, line? : String = "") -> Unit {
  let t = theme()
  c.box(gap=4.0, fn() {
    c.text(title, size=t.t.title, weight=600, color=t.p.text, line=t.t.title_line)
    |> ignore
    if line != "" {
      c.text(line, size=t.t.ui, color=t.p.muted, line=t.t.ui_line) |> ignore
    }
  })
  |> ignore
}

///|
/// A setting along a hairline with a knob (Reader.css.ts slider): mbui's slider (@kit.slider) in still.fail's look, the
/// line 2 high on 16% of the ink, the part up to the knob in the accent, the knob 22 with a ring of the ground round
/// it; dragged or tapped along, and with the keyboard. Returns the value, snapped to `step` (0: none).
pub fn slider(
  c : @ui.Ctx,
  key : String,
  value : Double,
  min : Double,
  max : Double,
  step? : Double = 0.0,
  ink? : Int64,
  accent? : Int64,
  ground? : Int64,
) -> Double {
  let t = theme()
  @kit.slider(
    c,
    key,
    value,
    min~,
    max~,
    step~,
    w=Fill(1.0),
    look=@kit.slider_look_of(
      ink=ink.unwrap_or(t.p.text),
      fill=accent.unwrap_or(t.p.accent),
      ring=ground.unwrap_or(t.p.canvas),
    ),
  ).value
}

///|
/// Round a sheet's grabber: 8 above and 4 under it, then 4 above and under it (Sheet.kt's two paddings, each a length
/// of its own: on Android's whole pixels 21 + 11 above the grabber and 11 + 11 under it, not one 12 and one 8).
// kept across runs: a value (no field of it changes)
let sheet_grab_outer : @ui.Style = @ui.css("w=Full pt=S2 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let sheet_grab_inner : @ui.Style = @ui.css("w=Full py=S1 align=ACenter")

///|
/// The grabber at a sheet's top (Sheet.kt SheetGrab): 38 × 5 in the line's colour, 12 above it and 8 under.
pub fn sheet_grab(c : @ui.Ctx) -> Unit {
  let grabber = sheet_grabber.then(@ui.style(bg=Data(theme().p.line)))
  c.box(style=sheet_grab_outer, fn() {
    c.box(style=sheet_grab_inner, fn() { c.box(style=grabber, fn() {  }) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// How long the pointer rests on a control before its tip shows (the web's Tooltip.Provider delayDuration).
pub let tip_delay_ms : Double = 400.0

///|
/// A tip over control `id` (parts.tsx Tip): `label` said beside it once the pointer has rested on it a moment (on
/// `side`, under it by default), and with a `shortcut`, the keys that do the same after it, quieter (shortcuts.mbt).
/// The only way anything explains itself on hover; to a finger, which rests on nothing, as it holds what it names
/// (Android's tooltips: @kit.tooltip). With no label, none. `key` names it where it is asked.
pub fn tip(
  c : @ui.Ctx,
  key : String,
  id : Int,
  label : String,
  side? : @ui.Side = Bottom,
  shortcut? : String = "",
  shown? : Bool = false,
) -> Unit {
  if label == "" || id == 0 {
    return
  }
  let keys = shortcut_keys(shortcut)
  @kit.tooltip(c, "tip/" + key, id, label, delay=tip_delay_ms, side~, shown~, look=fn(c, _, words) {
    tip_look(c, words, keys)
  })
  |> ignore
}

///|
/// A tip as the web draws it (parts.css.ts tooltip): small words on the primary ink, 5 by 10 in, 8 round, a soft
/// shadow; the keys 8 after the words at 60% (tipKeys).
pub fn tip_look(c : @ui.Ctx, words : String, keys : String) -> Unit {
  c.box(style=tip_box, fn() {
    c.box(style=tip_line, fn() {
      c.text(words, style=tip_words) |> ignore
      if keys != "" {
        c.box(style=tip_quiet, fn() { c.text(keys, style=tip_keys) |> ignore }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let tip_box : @ui.Style = @ui.style(px=S2_5, py=S1_25, bg=Primary, radius=Lg, max_w=tip_max, shadow=Md)

///|
// kept across runs: a value (no field of it changes)
let tip_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let tip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary)

///|
// kept across runs: a value (no field of it changes)
let tip_keys : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tip_quiet : @ui.Style = @ui.css("opacity=O60")

///|
/// A small panel's ground (glass.ts panel): the canvas in light, the raised grey in dark, a hairline round it.
pub fn panel_ground() -> Int64 {
  let t = theme()
  if t.dark {
    t.p.raised
  } else {
    t.p.canvas
  }
}

///|
/// A menu's item (controls.css.ts menuItem), as mbui's menus draw it: 34 high at least, 7 by 10 in, its icon (14,
/// muted) and words (13), 8 apart; the pointer's or the keyboard's ground on it. In a menu of choices (`chooser`,
/// parts.tsx ChooserItem) a column 14 wide before the words instead, the one chosen checked in it, 6 apart.
pub fn menu_row(
  c : @ui.Ctx,
  s : @kit.MenuItemState,
  icon_name : String,
  chooser : Bool,
  end : ((@ui.Ctx, @kit.MenuItemState) -> Unit)?,
  danger? : Bool = false,
) -> Unit {
  let t = theme()
  let checked = match s.entry.kind {
    Choice(true) | Check(true) => true
    _ => false
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=menu_row_min,
    padx=text_in,
    pady=menu_row_over,
    gap=if chooser { chooser_gap } else { menu_gap },
    align=ACenter,
    radius=small_panel_inner(r_menu),
    bg=if s.hot { t.p.hover } else { 0L },
    fn() {
      if chooser {
        c.box(style=menu_check, fn() {
          if checked {
            icon(c, "check", size=14.0, color=t.p.text) |> ignore
          }
        })
        |> ignore
      } else if icon_name == "zou" {
        // 奏 its word (Rail.css.ts zouSmall)
        c.text("奏", style=menu_zou) |> ignore
      } else if icon_name != "" {
        icon(c, icon_name, size=14.0, color=if danger { t.p.red } else { t.p.muted }) |> ignore
      }
      // (a danger's in red, its icon with it: menuItem[data-danger])
      c.text(s.entry.label, style=if danger { menu_words_danger } else { menu_words }) |> ignore
      // what stands at its end (a ＋): pushed there
      match end {
        Some(f) => {
          c.spacer()
          f(c, s)
        }
        None => ()
      }
    },
  )
  |> ignore
}

///|
/// Between an item's icon and its words (menuItem), its check's column and its words (chooserItem).
let menu_gap : Double = 8.0

///|
let chooser_gap : Double = 6.0

///|
/// A chooser's check's column (controls.css.ts chooserCheck): 14 wide, the check in its middle.
// kept across runs: a value (no field of it changes)
let menu_check : @ui.Style = @ui.css("w=S3_5 align=ACenter")

///|
/// A menu item's words: as long as they are (the menu as wide as its longest, controls.css.ts menuList).
// kept across runs: a value (no field of it changes)
let menu_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L5, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_words_danger : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, leading=L5, wrap=false)

///|
/// A heading among a menu's items (controls.css.ts menuLabel): 6 over, 4 under, 10 in; 12, muted.
// kept across runs: a value (no field of it changes)
let menu_heading : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let menu_heading_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, leading=L4_75, wrap=false)

///|
/// 奏 as an icon in a menu or a panel's row: 14 on 18, 600 (Rail.css.ts zouSmall).
// kept across runs: a value (no field of it changes)
let menu_zou : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, leading=L5, wrap=false)

///|
/// A menu (parts.tsx Menu: mbui's dropdown menu, in the web's look): `entries` with their icons (by value), as wide as
/// its longest and `w` at least (controls.css.ts menuList 180; a menu of choices chooserMenu, 220), `offset` on `side`
/// of `trigger` (under it) lined up `along` it, or at `at`; what was chosen. The arrows, letters, Enter and Escape as a
/// menu's; a press outside closes it.
pub fn dropdown(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  trigger : Int,
  entries : Array[@kit.Entry],
  icons : Map[String, String],
  w : Double,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = 6.0,
  at? : (Double, Double, Double, Double),
  row_end? : (@ui.Ctx, @kit.MenuItemState) -> Unit,
  danger? : Array[String] = [],
) -> @kit.Menu {
  // (a menu of choices: each chosen or not, checked before its words)
  let chooser = entries.iter().any(fn(e) { e.kind is Choice(_) })
  @kit.dropdown_menu(
    c,
    key,
    open,
    trigger,
    entries,
    side~,
    along~,
    offset~,
    min_w=w,
    at?,
    look=fn(c, w, body) { small_panel(c, min_w=w, body) |> ignore },
    item_look=fn(c, s) {
      menu_row(c, s, icons.get(s.entry.value).unwrap_or(""), chooser, row_end, danger=danger.contains(s.entry.value))
    },
    heading_look=fn(c, label) {
      c.box(style=menu_heading, fn() { c.text(label, style=menu_heading_words) |> ignore }) |> ignore
    },
  )
}

///|
/// What a menu holds (parts.tsx MenuItem): its words, its icon, in red (`danger`: what cannot be undone), not to be
/// chosen now (`disabled`); what choosing it does.
pub(all) struct MenuItem {
  label : String
  icon : String
  danger : Bool
  disabled : Bool
  select : () -> Unit
}

///|
pub fn menu_item_of(
  label : String,
  select : () -> Unit,
  icon? : String = "",
  danger? : Bool = false,
  disabled? : Bool = false,
) -> MenuItem {
  { label, icon, danger, disabled, select }
}

///|
/// The menu open now (one at a time, as Radix's are), by its key, and where a right click opened it.
let menu_open : Ref[String] = Ref("")

///|
let menu_open_at : Ref[(Double, Double)] = Ref((0.0, 0.0))

///|
/// No menu open, no mark's words (the app begun again).
pub fn parts_reset() -> Unit {
  held_felt.clear()
  presenters_reset()
  menu_open.val = ""
  about_open.val = ""
  menu_open_at.val = (0.0, 0.0)
}

///|
/// `items` drawn as a menu (None: a line between), open while `key` is the one open; chosen, closed and what it does
/// done once the frame is built. Whether it is open.
fn menu_items(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  items : Array[MenuItem?],
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = 6.0,
  at? : (Double, Double, Double, Double),
) -> Bool {
  let open = menu_open.val == key
  let entries : Array[@kit.Entry] = []
  let icons : Map[String, String] = {}
  let danger : Array[String] = []
  for i, x in items {
    match x {
      None => entries.push(@kit.menu_separator())
      Some(item) => {
        let v = i.to_string()
        entries.push(@kit.menu_item(v, label=item.label, disabled=item.disabled))
        if item.icon != "" {
          icons[v] = item.icon
        }
        if item.danger {
          danger.push(v)
        }
      }
    }
  }
  let m = dropdown(c, key, open, trigger, entries, icons, menu_w, side~, along~, offset~, at?, danger~)
  if open && !m.open {
    menu_open.val = ""
  }
  match m.chosen {
    Some(v) => {
      menu_open.val = ""
      let i = v.iter().fold(init=0, fn(n, ch) { n * 10 + (ch.to_int() - 48) })
      match items.get(i) {
        Some(Some(item)) => c.tell(key + "/chosen", item.select)
        _ => ()
      }
    }
    None => ()
  }
  m.open
}

///|
/// A menu behind ⋯ (parts.tsx Menu): an icon button (`label`, the app's word for 更多) that opens `items` under it,
/// along its end, 4 below. Whether it is open.
pub fn menu_of(c : @ui.Ctx, key : String, items : Array[MenuItem?], label~ : String, size? : Double = 32.0) -> Bool {
  let open = menu_open.val == key
  if icon_button(c, "more", key=key + "/more", size~, on=open, label~) {
    menu_open.val = if open { "" } else { key }
  }
  menu_items(c, key, c.id(key + "/more"), items, along=End, offset=4.0)
}

///|
/// One of a row's tools (tools_row): what it draws in the row, and what the row's ⋯ offers in its place once the row
/// has not the room for it (Ctx::box `drop`: the k-th to go; 0 never).
pub(all) struct Tool {
  key : String
  drop : Int
  draw : () -> Unit
  instead : Array[MenuItem]
}

///|
/// A tool drawn by `draw`, offering `instead` in the ⋯ when it goes (the `drop`-th).
pub fn tool_of(key : String, draw : () -> Unit, drop? : Int = 0, instead? : Array[MenuItem] = []) -> Tool {
  { key, drop, draw, instead }
}

///|
/// An icon button as a tool (icon_button: `label` its tip, `lit` its ink and quiet, as one that is on): pressed,
/// `on_press`; gone (the `drop`-th), the ⋯'s line of the same icon and words.
pub fn tool_button(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : String,
  on_press~ : () -> Unit,
  drop? : Int = 0,
  lit? : Int64,
  disabled? : Bool = false,
) -> Tool {
  {
    key,
    drop,
    draw: fn() { if icon_button(c, icon, key~, ink?=lit, quiet?=lit, disabled~, label~) { on_press() } },
    instead: [menu_item_of(label, on_press, icon~, disabled~)],
  }
}

///|
/// `tools` in a row (`style`: a row's), then its ⋯ (`label`, the app's word for 更多): what the row has not the room
/// for leaves it, the lowest `drop` first, and is offered in the ⋯ instead, over its own `more` (a line between); with
/// none of its own, the ⋯ is there only while something went into it. Nothing in it is squeezed.
pub fn tools_row(
  c : @ui.Ctx,
  key : String,
  tools : Array[Tool],
  more? : Array[MenuItem?] = [],
  label~ : String,
  style? : @ui.Style = tools_line,
) -> Unit {
  c.box(style~, fn() {
    let gone : Array[MenuItem?] = []
    for x in tools {
      let slot = c.id(key + "/tool/" + x.key)
      c.box(id=slot, taps=false, drop=x.drop, fn() { (x.draw)() }) |> ignore
      if x.drop > 0 && c.left_out(slot) {
        for m in x.instead {
          gone.push(Some(m))
        }
      }
    }
    let items = if gone.is_empty() {
      more
    } else if more.is_empty() {
      gone
    } else {
      gone + [None] + more
    }
    if more.is_empty() {
      c.box(more=true, fn() { menu_of(c, key, items, label~) |> ignore }) |> ignore
    } else {
      menu_of(c, key, items, label~) |> ignore
    }
  })
  |> ignore
}

///|
/// A row of tools (tools_row): 6 apart, on a line.
// kept across runs: a value (no field of it changes)
pub let tools_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// A right click's menu (Radix's ContextMenu, Drive.tsx MenuContent): opened at the pointer by `menu_open_here`, then
/// drawn there while it is open. Whether it is open.
pub fn context_items(c : @ui.Ctx, key : String, items : Array[MenuItem?]) -> Bool {
  if menu_open.val != key {
    return false
  }
  let (x, y) = menu_open_at.val
  menu_items(c, key, 0, items, offset=0.0, at=(x, y, 0.0, 0.0))
}

///|
/// The menu `key` opened at (`x`, `y`): a right click there.
pub fn menu_open_here(key : String, x : Double, y : Double) -> Unit {
  menu_open.val = key
  menu_open_at.val = (x, y)
}

///|
/// Whether the menu `key` is open now.
pub fn menu_is_open(key : String) -> Bool {
  menu_open.val == key
}

///|
/// The least a menu is wide (controls.css.ts menuList), and a menu of choices (chooserMenu).
pub let menu_w : Double = 180.0

///|
pub let chooser_menu_w : Double = 220.0

///|
/// What a thing is, said when the pointer rests on a quiet mark beside it (parts.tsx About, own.css.ts about: a 20
/// circle, its ⓘ 14 in the subtle ink, the words' under the pointer; what it says in a tip under it, or on `side`); to
/// a finger, which rests on nothing, once it is tapped, until a tap anywhere. `label`: what a screen reader calls the
/// mark (the app's word for 关于).
pub fn about(c : @ui.Ctx, key : String, words : String, label~ : String, side? : @ui.Side = Bottom) -> Unit {
  let t = theme()
  let id = c.id(key)
  let finger = @ui.pointing() is Finger
  if finger && c.clicked(id) {
    about_open.val = if about_open.val == key { "" } else { key }
  } else if about_open.val == key && c.tapped_anywhere() is Some(_) {
    about_open.val = ""
  }
  let b = c.box(style=about_box, id~, fn() {
    icon(c, "info", size=about_icon, color=if c.lit(id) { t.p.text } else { t.p.subtle }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  tip(c, key + "/tip", id, words, side~, shown=finger && about_open.val == key)
}

///|
/// The mark a finger tapped open (`about`'s key), "" none.
let about_open : Ref[String] = Ref("")

///|
let about_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let about_box : @ui.Style = @ui.css("w=S5 h=S5 radius=Full align=ACenter justify=JCenter")

// ---------------------------------------------------------------------------
// Switches, sections, pills, dots, the empty and the first one (parts.tsx Switch, SwitchRow, Section, Pill,
// StatusDot, Empty, FirstOne; parts.css.ts, own.css.ts)

///|
/// A switch's look (parts.css.ts switch_, switchThumb): 36 by 22, its thumb 18 white 2 in with a faint shadow, the
/// strong line's grey off, the accent on, the thumb sliding between; `small` (switchSmall: in a line of small text) 26
/// by 16, its thumb 12.
fn switch_look_for(small : Bool) -> (@ui.Ctx, @kit.SwitchState) -> Unit {
  let t = theme()
  let (w, h) = switch_size(small)
  @kit.switch_look_of(w~, h~, inset=switch_in, on_color=t.p.accent, off_color=t.p.line_strong, knob=0xFFFFFFFFL)
}

///|
/// A switch's size by the screen, the theme's rows' (Rows: a finger's 44 by 26 on a touch device, the web's 36 by 22 on
/// a computer); small, 26 by 16.
fn switch_size(small : Bool) -> (Double, Double) {
  if small {
    (switch_small_w, switch_small_h)
  } else {
    let r = theme().rows
    (r.switch_w, r.switch_h)
  }
}

///|
/// A switch (parts.tsx Switch: mbui's, @kit.switch: a tap, Space or Enter turn it), `on` or not, named `label` for a
/// screen reader, in the web's look (switch_look_for). `busy`: what it set is on its way, a small ring before it, and it
/// is not turned again meanwhile. What it is now (the other, turned this frame).
pub fn switch(
  c : @ui.Ctx,
  key : String,
  on : Bool,
  label? : String = "",
  disabled? : Bool = false,
  small? : Bool = false,
  busy? : Bool = false,
) -> Bool {
  if busy {
    spinner(c, size=if small { spinner_inline } else { spinner_size }) |> ignore
  }
  // its own height wherever it is (in a row, in its middle: switchSmall's alignSelf), not stretched
  let mut now = on
  c.box(style=switch_at, fn() {
    now = @kit.switch(c, key, on, label~, disabled=disabled || busy, look=switch_look_for(small)).value
  })
  |> ignore
  now
}

///|
// kept across runs: a value (no field of it changes)
let switch_at : @ui.Style = @ui.css("justify=JCenter align=AStart")

///|
/// A switch drawn in a row that takes the tap itself (the row turns it): its look alone, its thumb sliding as a
/// switch's does (`@kit.switch_knob` by `key`).
pub fn switch_look(c : @ui.Ctx, key : String, on : Bool, small? : Bool = false) -> Unit {
  let (w, h) = switch_size(small)
  switch_look_for(small)(c, {
    on,
    t: @kit.switch_knob(c, key, on),
    hovered: false,
    pressed: false,
    focus_shown: false,
    disabled: false,
    rect: (0.0, 0.0, w, h),
  })
}

///|
/// A setting's row (parts.tsx SwitchRow, switchRow): what it is on the left, `note` quieter under it, its switch on the
/// right, 16 apart; its words press the switch too. What it is now.
pub fn switch_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  on : Bool,
  note? : String = "",
  disabled? : Bool = false,
  busy? : Bool = false,
) -> Bool {
  let id = c.id(key + "/words")
  let mut now = on
  c.box(style=switch_row_box, fn() {
    c.box(style=switch_row_words, id=if disabled || busy { 0 } else { id }, fn() {
      c.text(title, style=theme().rows.title) |> ignore
      if note != "" {
        c.text(note, style=theme().rows.note) |> ignore
      }
    })
    |> ignore
    now = switch(c, key, on, label=title, disabled~, busy~)
  })
  |> ignore
  if c.clicked(id) {
    !on
  } else {
    now
  }
}

///|
/// One of several to tick (a list a choice of some of: ChatPage.tsx ShareDialog's rows, the phone's PickRow): its box,
/// then what it is (`note` quieter under it), the whole row pressed to tick it or not, its ground lit under the hand. Its
/// room, its words and its box the theme's rows' (Rows: a finger's on a touch device, a list row's on a computer). What
/// it is now.
pub fn check_row(c : @ui.Ctx, key : String, label : String, on : Bool, note? : String = "", disabled? : Bool = false) -> Bool {
  let id = c.id(key + "/row")
  if !disabled {
    c.cursor(id, Hand)
  }
  let mut now = on
  let mut ticked = false
  let r = theme().rows
  c.box(style=check_row_box.then(@ui.style(min_h=r.least)), id=if disabled { 0 } else { id }, fn() {
    let look = @kit.checkbox_look_of(size=r.check, radius=r.check_corner)
    let v = @kit.checkbox(c, key, if on { On } else { Off }, label~, disabled~, look~).value
    if (v == On) != on {
      ticked = true
      now = v == On
    }
    // (its words as a setting row's: what is left of the row)
    c.box(style=switch_row_words, fn() {
      c.text(label, style=r.title) |> ignore
      if note != "" {
        c.text(note, style=theme().rows.note) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  if !ticked && !disabled && c.clicked(id) {
    !on
  } else {
    now
  }
}

///|
/// A tick row's room (check_row): 12 by 10 in, its box 12 before its words, a row's corner, the hover grey under the
/// hand; as high at least, its words and its box as the theme's rows (Rows).
// kept across runs: a value (no field of it changes)
let check_row_box : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 align=ACenter hovered{bg=Hover} pressed{bg=Hover}").then(
  @ui.style(radius=row_radius),
)


///|
// kept across runs: a value (no field of it changes)
let switch_row_box : @ui.Style = @ui.css("row w=Full align=ACenter gap=S4")

///|
// kept across runs: a value (no field of it changes)
let switch_row_words : @ui.Style = @ui.css("w=Grow(1.0) gap=S0_5")


///|
/// A titled block of a page (parts.tsx Section, page.css.ts section, parts.css.ts sectionHead): its title (14 on 22,
/// 600) and `note` under it (12, muted, 3 under, 52em at most), its `actions` at the head's end on the title's centre
/// line, 10 over what it holds; 28 under it all.
pub fn section(
  c : @ui.Ctx,
  title : String,
  body : () -> Unit,
  note? : String = "",
  actions? : () -> Unit,
  title_after? : () -> Unit,
) -> Unit {
  c.box(style=section_box, fn() {
    c.box(style=section_head, fn() {
      c.box(style=section_words, fn() {
        // what the title holds after its words (its title a node: a count, a mark), 8 after them in a line
        match title_after {
          Some(f) =>
            c.box(style=section_title_line, fn() {
              c.text(title, style=section_title) |> ignore
              f()
            })
            |> ignore
          None => c.text(title, style=section_title) |> ignore
        }
        if note != "" {
          c.box(style=section_note_box, pt=section_note_gap, fn() { c.text(note, style=section_note) |> ignore })
          |> ignore
        }
      })
      |> ignore
      match actions {
        Some(f) => c.box(style=section_actions, f) |> ignore
        None => ()
      }
    })
    |> ignore
    body()
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let section_box : @ui.Style = @ui.css("w=Full mb=S7")

///|
// kept across runs: a value (no field of it changes)
let section_head : @ui.Style = @ui.css("row w=Full justify=JBetween align=ACenter gap=S3 mb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let section_words : @ui.Style = @ui.css("w=Grow(1.0)")

///|
// kept across runs: a value (no field of it changes)
let section_title_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let section_title : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let section_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let section_note_box : @ui.Style = @ui.style(max_w=section_note_most)

///|
// kept across runs: a value (no field of it changes)
let section_actions : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
/// A pill's tone (parts.tsx Tone): its ground and its words' ink.
pub(all) enum PillTone {
  Neutral
  Green
  Blue
  Amber
  Red
  Accented
} derive(Eq)

///|
/// A pill (parts.tsx Pill, parts.css.ts pill): words 12, 500, on one line, 22 high, 9 in, round; on the quiet grey in
/// the muted ink, or in a tone (its pale ground, its ink). `icon`: what leads it, 14, in its ink (a status's check or
/// wait: ui.tsx StatusText), 4 before its words.
pub fn pill(c : @ui.Ctx, words : String, tone? : PillTone = Neutral, icon? : String = "") -> Unit {
  let p = theme().p
  let (ground, ink) = match tone {
    Neutral => (p.neutral_bg, p.muted)
    Green => (p.green_bg, p.green_ink)
    Blue => (p.blue_bg, p.blue)
    Amber => (p.amber_bg, p.warn_ink)
    Red => (p.red_bg, p.red)
    Accented => (p.accent_bg, p.accent_text)
  }
  c.box(style=pill_box, padx=pill_in, bg=ground, fn() {
    if icon != "" {
      draw_icon(c, icon, pill_icon, ink)
    }
    if words != "" {
      c.text(words, style=pill_words, color=ink) |> ignore
    }
  })
  |> ignore
}

///|
let pill_icon : Double = 14.0

///|
/// Steps to take in order (controls.css.ts steps: an ordered list, its numbers in the muted ink in 20 at its start,
/// 8 apart, the ui's 13): each what `steps` draws for it (its words, a button after them), their parts 8 apart in a
/// line, going on in the next where they do not fit.
pub fn steps(c : @ui.Ctx, steps : Array[() -> Unit]) -> Unit {
  c.box(style=steps_box, fn() {
    for i, step in steps {
      c.box(style=step_row, fn() {
        c.box(style=step_number, fn() { c.text((i + 1).to_string() + ".", style=step_number_words) |> ignore }) |> ignore
        c.box(style=step_body, flow=true, fn() { step() }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A step's words (the ui's 13 on 20).
pub let step_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let steps_box : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let step_row : @ui.Style = @ui.css("row w=Full align=AStart")

///|
// kept across runs: a value (no field of it changes)
let step_number : @ui.Style = @ui.css("w=S5")

///|
// kept across runs: a value (no field of it changes)
let step_number_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let step_body : @ui.Style = @ui.style(row=true, w=grow, gap=S2, align=ACenter)

///|
/// What was checked and found right (controls.css.ts verifyOk): a ticked circle 16 and its words, 6 apart, the ui's 13
/// in green.
pub fn verify_ok(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=verify_line, fn() {
    draw_icon(c, "check-circle", verify_icon, theme().p.green_ink)
    c.text(words, style=verify_words) |> ignore
  })
  |> ignore
}

///|
let verify_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let verify_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let verify_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Positive)

///|
// kept across runs: a value (no field of it changes)
let pill_box : @ui.Style = @ui.style(row=true, h=Fixed(pill_h), gap=S1, radius=Full, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let pill_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, weight=Medium, wrap=false)

///|
/// How something stands, at a glance (parts.tsx StatusDot, parts.css.ts statusDot): a dot 7 round, online the online
/// green, busy amber, error red, else (offline) a ring 1.5 in the muted ink. `state`: "online", "busy", "error", or
/// anything else for offline (the web's Presence).
pub fn status_dot(c : @ui.Ctx, state : String) -> Unit {
  let p = theme().p
  let (ground, ring) = match state {
    "online" => (p.online, no_ground)
    "busy" => (p.warn_ink, no_ground)
    "error" => (p.red, no_ground)
    _ => (no_ground, p.muted)
  }
  c.box(style=status_dot_box, bg=ground, border=if ring == no_ground { no_ring } else { status_ring }, border_color=ring, fn() {  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let status_dot_box : @ui.Style = @ui.style(w=dot_size, h=dot_size, radius=Full)

///|
/// Nothing here (parts.tsx Empty, parts.css.ts empty): what `body` says in the middle of the room it has, 40 in, its
/// parts 6 apart, in the muted ink (its words the page's, centred).
pub fn empty(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=empty_box, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let empty_box : @ui.Style = @ui.css("w=Full h=Grow(1.0) p=S10 gap=S1_5 align=ACenter justify=JCenter")

///|
/// The first one to make (parts.tsx FirstOne, own.css.ts firstOne): a list with nothing in it yet, or a page whose first
/// step is still to take. Its scene (`art`), what that first one is (16, 600, 12 under the scene), a line about it (13,
/// muted, 34em at most), and the one thing to do (12 under it, its buttons 8 apart, centred); 480 at most, in the
/// middle, 24 over and under.
pub fn first_one(
  c : @ui.Ctx,
  title : String,
  actions : () -> Unit,
  art? : () -> Unit,
  lead? : String = "",
) -> Unit {
  c.box(style=first_room, fn() {
    c.box(style=first_box, fn() {
      match art {
        Some(f) => f()
        None => ()
      }
      c.box(style=first_title_at, fn() { c.text(title, style=first_title) |> ignore }) |> ignore
      if lead != "" {
        c.box(style=first_lead_box, fn() { c.text(lead, style=first_lead) |> ignore }) |> ignore
      }
      c.box(style=first_actions, actions) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let first_room : @ui.Style = @ui.css("w=Full align=ACenter py=S6")

///|
// kept across runs: a value (no field of it changes)
let first_box : @ui.Style = @ui.style(w=Full, max_w=first_most, pt=S2, pb=S6, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let first_title_at : @ui.Style = @ui.css("pt=S3")

///|
// kept across runs: a value (no field of it changes)
let first_title : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let first_lead : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let first_lead_box : @ui.Style = @ui.style(max_w=first_lead_most, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let first_actions : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter justify=JCenter pt=S3")

// ---------------------------------------------------------------------------
// Dialogs (parts.tsx Dialog; parts.css.ts dialog, dialogHead, dialogLead, dialogBody, dialogFoot, overlay)

///|
/// A dialog (parts.tsx Dialog: mbui's, @kit.dialog: the page under it dimmed and taking no press, the focus kept in
/// it, Escape, the back and a press outside closing it) in the web's look: `w` wide (520; `wide` 640), 32 short of the
/// window at most; its corner 42 (its padding 24 and a pill's half height, so a pill in its corner and the close
/// button follow its edge: DIALOG_PAD), a small panel's ground and line, a deep shadow. Its title (22, 600) 25 under
/// its top beside the close button (round, 32: `close_label`, none when ""), `description` 6 under it (13, muted),
/// what `body` holds 18 under that (its parts 16 apart), and `footer`'s buttons at its end 24 under it, 8 apart.
/// Whether it is open now (closed by its close button too).
pub fn dialog(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  body : () -> Unit,
  description? : String = "",
  footer? : () -> Unit,
  wide? : Bool = false,
  w? : Double,
  close_label? : String = "",
  step? : String = "",
) -> Bool {
  let closed = Ref(false)
  let w = w.unwrap_or(if wide { dialog_wide_w } else { dialog_w })
  let d = @kit.dialog(
    c,
    key,
    open,
    title,
    description~,
    w=dmin(w, c.width - dialog_margin),
    close_label="",
    look=fn(c, s, inner) {
      c.box(
        style=dialog_box,
        w=Px(s.w),
        max_h=c.height - dialog_room,
        radius=dialog_r,
        bg=panel_ground(),
        shadow=dialog_shadow,
        shadow_y=dialog_shadow_y,
        shadow_color=theme().p.shadow,
        fn() {
        c.box(style=dialog_head, fn() {
          // a step's count beside the title (Connect.css.ts dialogStep: the ui's 13 in 400 muted, 8 after it)
          if step != "" {
            c.box(style=dialog_title_line, fn() {
              c.text(s.title, style=dialog_title_one) |> ignore
              c.text(step, style=dialog_step) |> ignore
            })
            |> ignore
          } else {
            c.text(s.title, style=dialog_title) |> ignore
          }
          if close_label != "" &&
            icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=close_label) {
            closed.val = true
          }
        })
        |> ignore
        if s.description != "" {
          c.box(style=dialog_lead_at, fn() { c.text(s.description, style=dialog_lead) |> ignore }) |> ignore
        }
        // what it holds scrolls in itself when the dialog would be taller than the window leaves it (dialogBody's
        // overflow: auto, its minimum 0): its title and its buttons stay
        c.capped(key + "/body", c.height, shrinks=true, fn() { c.box(style=dialog_body, inner) |> ignore }) |> ignore
        match footer {
          Some(f) => c.box(style=dialog_foot.then(dialog_corner_foot(dialog_pad)), f) |> ignore
          None => c.box(style=dialog_end, fn() {  }) |> ignore
        }
        },
      )
      |> ignore
    },
    body,
  )
  d.value && !closed.val
}

///|
/// What the window keeps round a dialog up and down (parts.css.ts dialog: at most 100dvh - 48 tall).
let dialog_room : Double = 48.0

///|
/// A dialog's frame: 24 in at its sides and over its title, a line round it (its corner, ground and shadow: dialog_r,
/// panel_ground, dialog_shadow).
// kept across runs: a value (no field of it changes)
let dialog_box : @ui.Style = @ui.css("px=S6 pt=S6 border=B1 border_color=Line")

///|
/// Its title's row (dialogHead: 25 under the top, 26 from the right): the close button at its end, its middle on the
/// title's.
// kept across runs: a value (no field of it changes)
let dialog_head : @ui.Style = @ui.css("row w=Full justify=JBetween align=ACenter gap=S3 min_h=S8 pt=SPx pr=S0_5")

///|
// kept across runs: a value (no field of it changes)
let dialog_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let dialog_lead_at : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let dialog_lead : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted)

///|
/// What it holds: 18 under the title (or its lead), its parts 16 apart.
// kept across runs: a value (no field of it changes)
let dialog_body : @ui.Style = @ui.css("w=Full pt=S4_5 gap=S4")

///|
/// Its buttons: at its end, 8 apart, 24 under what it holds; the last in its foot corner concentric with it (a pane of
/// the ladder's: dialog_corner_foot).
// kept across runs: a value (no field of it changes)
let dialog_foot : @ui.Style = @ui.css("row w=Full justify=JEnd align=ACenter gap=S2 pt=S6")

///|
/// A dialog's sides' room (24).
let dialog_pad : Double = 24.0

///|
/// With none, 24 under what it holds.
// kept across runs: a value (no field of it changes)
let dialog_end : @ui.Style = @ui.css("h=S6")

// ---------------------------------------------------------------------------
// Fields, selects, choices (parts.tsx Field, Select, Choices; parts.css.ts field, select, choice, radio)

///|
/// A field (parts.tsx Field, parts.css.ts field): its `label` (13, 500) with `aside` at the head's end, what `body`
/// holds (the input), and under it what is wrong (`error`, 12 red) or else a `hint` (12, muted); 6 apart.
pub fn field(
  c : @ui.Ctx,
  label : String,
  body : () -> Unit,
  hint? : String = "",
  error? : String = "",
  aside? : () -> Unit,
) -> Unit {
  c.box(style=field_box, fn() {
    c.box(style=field_top, fn() {
      c.text(label, style=field_label) |> ignore
      match aside {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
    body()
    if error != "" {
      c.text(error, style=field_error) |> ignore
    } else if hint != "" {
      c.text(hint, style=field_hint) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let field_box : @ui.Style = @ui.css("w=Full gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let field_top : @ui.Style = @ui.css("row w=Full justify=JBetween align=AEnd gap=S2")

///|
// kept across runs: a value (no field of it changes)
let field_label : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let field_error : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let field_hint : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
/// A line to type in (controls.css.ts input, a one-line one: a pill as the buttons beside it are, 36 high at least,
/// 16 in, a line of the strong grey, the field's hover grey pointed at or written in, on the canvas, its words 14, the
/// placeholder subtle): mbui's field (@kit.text_field), its editor `key`'s; `field`: what it holds, the view's own;
/// `small`: 32 high (a small panel's, as its rows: input_box_small). What is in it now, and whether Enter was pressed
/// in it.
pub fn input(
  c : @ui.Ctx,
  key : String,
  placeholder? : String = "",
  secret? : Bool = false,
  disabled? : Bool = false,
  small? : Bool = false,
  field? : @ui.Field,
) -> @kit.Field {
  // (its words the body's, as tall as the theme's controls: the web's on a computer, a finger's on a touch device)
  let t = theme()
  @kit.text_field(c, key, placeholder~, secret~, disabled~, size=t.t.body, line=t.t.body_line, field?, look=fn(c, s, editor) {
    let hot = s.hovered || s.focused
    c.box(
      id=s.id,
      style=match (small, hot) {
        (false, false) => input_box.then(control_height())
        (false, true) => input_box_hot.then(control_height())
        (true, false) => input_box_small
        (true, true) => input_box_small_hot
      },
      editor,
    )
    |> ignore
  })
}

///|
/// As tall as the theme's controls at least (Theme::control_h: a field's, a select's).
fn control_height() -> @ui.Style {
  @ui.style(min_h=Fixed(theme().control_h))
}

///|
/// Lines to type in (controls.css.ts input as a textarea: --r-field round, not a pill; 12 by 7 in, the strong grey's
/// line, the field's hover grey pointed at or written in, on the canvas; its words 14 on lines 1.6 of them), at least
/// `rows` lines high and growing to `most`; `field`: what it holds, the view's own. What is in it now.
pub fn textarea(
  c : @ui.Ctx,
  key : String,
  rows? : Int = 3,
  most? : Int = 16,
  placeholder? : String = "",
  field? : @ui.Field,
) -> String {
  let t = theme()
  let box_id = c.id(key + "/frame")
  let hot = c.lit(box_id) || c.has_focus(c.id(key))
  let mut words = ""
  let tall = @ui.style(min_h=Fixed(rows.to_double() * textarea_line + textarea_in))
  c.box(id=box_id, style=(if hot { textarea_box_hot } else { textarea_box }).then(tall), fn() {
    words = c.editor(
      key,
      field?,
      placeholder~,
      font_size=input_size,
      max_lines=most,
      plain=true,
      line=textarea_line,
      color=t.p.text,
      placeholder_color=t.p.subtle,
      caret_color=t.p.accent,
      enter_sends=false,
    ).text
  })
  |> ignore
  words
}

///|
/// A textarea's lines (AutomaticDecisions.css.ts policyText: 1.6 of the words), and what its frame adds over them (7
/// and 1 above and under).
let textarea_line : Double = 22.4

///|
let textarea_in : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let textarea_box : @ui.Style = @ui.css("w=Full px=S3 py=S2 radius=Xl bg=Surface border=B1 border_color=Border")

///|
// kept across runs: a value (no field of it changes)
let textarea_box_hot : @ui.Style = textarea_box.then(@ui.css("border_color=FieldHover"))

///|
/// What is typed in: as what is read (global.css.ts --text-input), on the line of a list's words.
let input_size : Double = 14.0

///|
let input_line : Double = 20.0

///|
/// A one-line field's height (the theme's controls': Theme::control_h), for what stands it concentric in a corner.
pub fn input_height() -> Double {
  theme().control_h
}

///|
// kept across runs: a value (no field of it changes)
let input_box : @ui.Style = @ui.css(
  #|row w=Full px=S4 py=S1_5 radius=Full bg=Surface border=B1 border_color=Border align=ACenter
  #|disabled{opacity=O55}
)

///|
/// Pointed at or written in: the field's hover grey round it.
// kept across runs: a value (no field of it changes)
let input_box_hot : @ui.Style = input_box.then(@ui.css("border_color=FieldHover"))

///|
/// `small`: 32 high, a small panel's (its search): a capsule its padding in from its corner, concentric with it
/// (capsule_in(r_menu, 32) = panel_pad), as its rows are.
// kept across runs: a value (no field of it changes)
let input_box_small : @ui.Style = input_box.then(@ui.style(min_h=Fixed(menu_row_min), py=room(menu_row_over)))

///|
// kept across runs: a value (no field of it changes)
let input_box_small_hot : @ui.Style = input_box_small.then(@ui.css("border_color=FieldHover"))

///|
/// A choice among a few (parts.tsx Select): closed, a pill as a one-line field is (input_box: the theme's control
/// height and body words), what is chosen in it cut short, the placeholder subtle, a chevron at its end; pressed (or
/// Enter, Space), its options through the presenters (@sf.pick: beside it a menu's, the arrows, letters and Enter;
/// a sheet of rows on a touch device), the chosen checked, `hints` a quieter note at an option's end. `options`: each
/// value and its words; `choose` is given the one chosen.
pub fn select(
  c : @ui.Ctx,
  key : String,
  value : String,
  options : Array[(String, String)],
  choose : (String) -> Unit,
  placeholder? : String = "",
  label? : String = "",
  disabled? : Bool = false,
  w? : Double = select_w,
  hints? : Map[String, String] = {},
) -> Unit {
  let t = theme()
  let id = c.id(key)
  let words = match options.iter().find_first(fn(o) { o.0 == value }) {
    Some(o) => o.1
    None => ""
  }
  let hot = !disabled && (c.lit(id) || c.has_focus(id))
  let b = c.box(
    style=(if hot { select_box_hot } else { select_box }).then(control_height()).then(@ui.style(max_w=Fixed(w))),
    id=if disabled { 0 } else { id },
    disabled~,
    fn() {
      c.text(if words == "" { placeholder } else { words }, style=if words == "" {
        select_placeholder
      } else {
        select_words
      })
      |> ignore
      icon(c, "chevron-down", size=select_chevron, color=t.p.muted) |> ignore
    },
  )
  c.semantics(b, Button, id~, label=if label == "" { words } else { label + ": " + words }, disabled~)
  if !disabled && c.clicked(id) {
    pick(
      label,
      options.map(fn(o) { choice(o.0, o.1, note=hints.get(o.0).unwrap_or("")) }),
      value,
      choose,
      from=Of(id),
    )
  }
}

///|
// kept across runs: a value (no field of it changes)
let select_box : @ui.Style = @ui.css(
  #|row w=Full px=S4 py=S1_5 gap=S2 radius=Full bg=Surface border=B1 border_color=Border align=ACenter
  #|justify=JBetween disabled{opacity=O55}
)

///|
/// Pointed at, open or focused: the field's hover grey round it.
// kept across runs: a value (no field of it changes)
let select_box_hot : @ui.Style = select_box.then(@ui.css("border_color=FieldHover"))

///|
// kept across runs: a value (no field of it changes)
let select_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, wrap=false, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let select_placeholder : @ui.TextStyle = select_words.then(@ui.text_style(color=Subtle))

///|
/// An option's row (parts.css.ts selectItem: a menu's item, its check at its end 10 in).
// kept across runs: a value (no field of it changes)
let select_item : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let select_hint : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// One of a few (a choice whose options need no sentence each: an account, a role): up to `one_of_listed_most` of
/// them listed where it is, a row each (the screen's rows, Theme::rows: check_row's height and title, a row's corner,
/// the hover's ground), the chosen checked at its end, a press choosing it at once (the arrows move among them, as a radio
/// group's); more, a select (a pill, its options through the presenters). Listed or not is the number's, the same on
/// every screen: two accounts read as clearly listed in a dialog as in a sheet, a press less than a select's two.
/// `choose` is given the one chosen.
pub fn one_of(
  c : @ui.Ctx,
  key : String,
  value : String,
  options : Array[(String, String)],
  choose : (String) -> Unit,
  label? : String = "",
  placeholder? : String = "",
  disabled? : Bool = false,
) -> Unit {
  if options.length() > one_of_listed_most {
    select(c, key, value, options, choose, label~, placeholder~, disabled~)
    return
  }
  let t = theme()
  let rows = t.rows
  let items = options.map(fn(o) { @kit.item(o.0, label=o.1) })
  let r = @kit.radio_group(c, key, items, value, label~, disabled~, gap=0.0, look=fn(c, s) {
    c.box(
      style=(if s.hovered || s.pressed { one_of_row_hot } else { one_of_row }).then(@ui.style(min_h=rows.least)),
      disabled=s.disabled,
      fn() {
        c.text(s.label, style=rows.title) |> ignore
        if s.on {
          icon(c, "check", size=one_of_check, color=t.p.accent) |> ignore
        }
      },
    )
    |> ignore
  })
  if r.value != value {
    choose(r.value)
  }
}

///|
/// How many one_of lists where it is; more are a select's.
let one_of_listed_most : Int = 5

///|
/// A row of one_of: as wide as where it is, 12 in, its words and its check apart, a row's corner (row_radius).
// kept across runs: a value (no field of it changes)
let one_of_row : @ui.Style = @ui.css("row w=Full px=S3 gap=S2 align=ACenter justify=JBetween disabled{opacity=O55}").then(
  @ui.style(radius=row_radius),
)

///|
// kept across runs: a value (no field of it changes)
let one_of_row_hot : @ui.Style = one_of_row.then(@ui.css("bg=Hover"))

///|
let one_of_check : Double = 16.0

///|
/// Exclusive options that need a sentence each (parts.tsx Choices: mbui's radio group, @kit.radio_group): bordered
/// cards 8 apart, each its `icon` (by its value) before its title (13, 600) and `description` (12, muted), a radio mark
/// at its end; the chosen one edged in the ink, what it holds more (`extra`, by its value: a switch of it) under a line
/// in it; those `disabled` faded and not chosen; `note`: what draws a description of its own, by its value. `options`: each value, title and description. What is chosen now.
pub fn choices(
  c : @ui.Ctx,
  key : String,
  value : String,
  options : Array[(String, String, String)],
  label? : String = "",
  icon? : (String) -> Unit,
  extra? : (String) -> Unit,
  disabled? : Array[String] = [],
  note? : (String) -> Unit,
) -> String {
  let note_of = note
  let items = options.map(fn(o) { @kit.item(o.0, label=o.1, disabled=disabled.contains(o.0)) })
  @kit.radio_group(c, key, items, value, label~, gap=choice_gap, look=fn(c, s) {
      let at = options.search_by(fn(o) { o.1 == s.label })
      let v = at.map(fn(i) { options[i].0 }).unwrap_or("")
      let note = at.map(fn(i) { options[i].2 }).unwrap_or("")
      c.box(style=if s.on { choice_card_on } else if s.hovered { choice_card_hot } else { choice_card }, disabled=s.disabled, fn() {
          c.box(style=choice_hit, fn() {
            match icon {
              Some(f) => f(v)
              None => ()
            }
            c.box(style=choice_words, fn() {
              c.text(s.label, style=choice_title) |> ignore
              // (its description a part of its own, by its value: a Slack workspace's token's owner)
              match note_of {
                Some(f) => f(v)
                None =>
                  if note != "" {
                    c.text(note, style=choice_note) |> ignore
                  }
              }
            })
            |> ignore
            c.box(style=if s.on { radio_mark_on } else { radio_mark }, fn() {
              if s.on {
                c.box(style=radio_dot, fn() {  }) |> ignore
              }
            })
            |> ignore
          })
          |> ignore
          // (parts.css.ts choiceExtra: 14 in at its sides, under a line, 12 over and 14 under what it holds)
          match extra {
            Some(f) if s.on =>
              c.box(style=choice_extra, fn() {
                c.box(style=choice_rule, fn() {  }) |> ignore
                c.box(style=choice_extra_in, fn() { f(v) }) |> ignore
              })
              |> ignore
            _ => ()
          }
      })
      |> ignore
    }).value
}

///|
// kept across runs: a value (no field of it changes)
let choice_card : @ui.Style = @ui.css(
  #|w=Full radius=Xl1_5 bg=Surface border=B1 border_color=Border disabled{opacity=O55}
)

///|
/// Pointed at: the field's hover grey round it; chosen: edged twice in the ink (its line and a ring of 1).
// kept across runs: a value (no field of it changes)
let choice_card_hot : @ui.Style = choice_card.then(@ui.css("border_color=FieldHover"))

///|
// kept across runs: a value (no field of it changes)
let choice_card_on : @ui.Style = choice_card.then(@ui.css("border=B2 border_color=Fg"))

///|
/// What is pressed of it (choiceHit): 12 by 14 in, its parts 12 apart.
// kept across runs: a value (no field of it changes)
let choice_hit : @ui.Style = @ui.css("row w=Full px=S3_5 py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let choice_extra : @ui.Style = @ui.css("w=Full px=S3_5")

///|
// kept across runs: a value (no field of it changes)
let choice_rule : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
// kept across runs: a value (no field of it changes)
let choice_extra_in : @ui.Style = @ui.css("w=Full pt=S3 pb=S3_5")

///|
// kept across runs: a value (no field of it changes)
let choice_words : @ui.Style = @ui.css("w=Grow(1.0) gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let choice_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let choice_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
/// The radio mark: 18 round, edged 1.5 (the strong grey; the ink chosen), its dot 8 in the ink.
// kept across runs: a value (no field of it changes)
let radio_mark : @ui.Style = @ui.css(
  #|w=S4_5 h=S4_5 radius=Full border=B1 border_color=Border align=ACenter justify=JCenter
)

///|
// kept across runs: a value (no field of it changes)
let radio_mark_on : @ui.Style = radio_mark.then(@ui.css("border_color=Fg"))

///|
// kept across runs: a value (no field of it changes)
let radio_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Fg")

// ---------------------------------------------------------------------------
// Asking before (parts.tsx Confirm; parts.css.ts dialogAlert, dialogError)

///|
/// What a confirm reports: whether it is open now, and whether its action was pressed this frame.
pub(all) struct Confirmed {
  open : Bool
  confirmed : Bool
}

///|
/// Asks before something that cannot be undone (parts.tsx Confirm: an alert dialog, a press outside does not close
/// it): 420 wide, 28 over its title, 24 in; its title (22, 600) and `description` (13, muted), what went wrong (`error`:
/// 13 red, 12 over the buttons, it stays open), then `cancel` (its words alone) and `action` (solid red, the primary's
/// when not `danger`; a ring while `busy`) at its end, 16 under, 8 apart. Escape, the back and `cancel` close it.
pub fn confirm_dialog(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  title : String,
  description : String,
  action : String,
  cancel~ : String,
  busy? : Bool = false,
  error? : String = "",
  danger? : Bool = true,
) -> Confirmed {
  let mut confirmed = false
  let mut closed = false
  let d = @kit.dialog(
    c,
    key,
    open,
    title,
    description~,
    w=dmin(confirm_w, c.width - dialog_margin),
    outside=false,
    close_label="",
    look=fn(c, s, inner) {
      c.box(
        style=confirm_box,
        w=Px(s.w),
        radius=dialog_r,
        bg=panel_ground(),
        shadow=dialog_shadow,
        shadow_y=dialog_shadow_y,
        shadow_color=theme().p.shadow,
        fn() {
          c.text(s.title, style=dialog_title) |> ignore
          c.text(s.description, style=dialog_lead) |> ignore
          inner()
        },
      )
      |> ignore
    },
    fn() {
      if error != "" {
        c.box(style=confirm_error_at, fn() { c.text(error, style=confirm_error) |> ignore }) |> ignore
      }
      c.box(style=confirm_foot.then(dialog_corner_foot(dialog_pad)), fn() {
        if button(c, cancel, key=key + "/cancel", tone=Ghost) {
          closed = true
        }
        if button(c, action, key=key + "/action", tone=if danger { DangerSolid } else { Primary }, busy~) {
          confirmed = true
        }
      })
      |> ignore
    },
  )
  { open: d.value && !closed, confirmed }
}

///|
/// Its frame (dialogAlert: 28 over, 24 in, 8 between its title, its lead and what follows; its foot its buttons':
/// confirm_foot).
// kept across runs: a value (no field of it changes)
let confirm_box : @ui.Style = @ui.css("px=S6 pt=S7 gap=S2 border=B1 border_color=Line")

///|
// kept across runs: a value (no field of it changes)
let confirm_error_at : @ui.Style = @ui.css("w=Full pt=S1")

///|
// kept across runs: a value (no field of it changes)
let confirm_error : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let confirm_foot : @ui.Style = @ui.css("row w=Full justify=JEnd align=ACenter gap=S2 pt=S2")

// ---------------------------------------------------------------------------
// A small panel's parts (parts.tsx PanelHead, PanelGroup, PanelNote, PanelFoot, PanelText, PanelButton,
// PanelIconButton; parts.css.ts: inside a small panel, @sf.small_panel, its rows @sf.menu_item(panel=true))

///|
/// A small panel's head (PanelHead): its title (13, 600) and `note` under it (12, muted), in by a row's padding, 6 over
/// and 4 under.
pub fn panel_head(c : @ui.Ctx, title : String, note? : String = "") -> Unit {
  c.box(style=panel_head_box, fn() {
    c.text(title, style=panel_title) |> ignore
    if note != "" {
      c.text(note, style=panel_note_words) |> ignore
    }
  })
  |> ignore
}

///|
/// A group of a small panel's rows (PanelGroup) under a small `label` (12, muted), 2 apart.
pub fn panel_group(c : @ui.Ctx, body : () -> Unit, label? : String = "") -> Unit {
  c.box(style=panel_group_box, fn() {
    if label != "" {
      c.box(style=panel_label_at, fn() { c.text(label, style=panel_note_words) |> ignore }) |> ignore
    }
    body()
  })
  |> ignore
}

///|
/// A note in a small panel (PanelNote): 12, muted, in by a row's padding.
pub fn panel_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=panel_text_box, fn() { c.text(words, style=panel_note_words) |> ignore }) |> ignore
}

///|
/// A block of words in a small panel (PanelText): in by a row's padding, on the line its rows' words are.
pub fn panel_text(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=panel_text_box, body) |> ignore
}

///|
/// A small panel's buttons at its foot (PanelFoot): at its end, 6 apart, 4 under what is over them.
pub fn panel_foot(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=panel_foot_box, body) |> ignore
}

///|
/// How a small panel's button stands (PanelButton's tone): its words alone, the accent's ink (the one thing to do),
/// muted (a lesser one), or the accent's pale ground always (one that must be seen).
pub(all) enum PanelTone {
  Plainly
  Accent
  Quiet
  Filled
} derive(Eq)

///|
/// Words to press in a small panel (PanelButton): a small pill, 24 high, 10 in, its words 12 and 500; a ground only
/// while pointed at (`Filled`: the accent's pale ground always, the accent at 20% pointed at: the web's 22%, the scale's
/// nearest). True on the frame after it was pressed.
pub fn panel_button(
  c : @ui.Ctx,
  key : String,
  words : String,
  tone? : PanelTone = Plainly,
  disabled? : Bool = false,
) -> Bool {
  let id = c.id(key)
  let hot = !disabled && c.lit(id)
  let b = c.box(
    style=if tone == Filled { panel_button_filled } else { panel_button_box },
    disabled~,
    id=if disabled { 0 } else { id },
    fn() {
      c.text(words, style=match tone {
        Accent | Filled => panel_button_accent
        Quiet => if hot { panel_button_words } else { panel_button_quiet }
        Plainly => panel_button_words
      })
      |> ignore
    },
  )
  c.semantics(b, Button, id~, label=words, disabled~)
  !disabled && c.clicked(id)
}

///|
/// An icon to press in a small panel (PanelIconButton: close, stop, a step): a 24 circle, the muted ink, the hover's
/// ground and the ink pointed at; named on hover. True on the frame after it was pressed.
pub fn panel_icon_button(c : @ui.Ctx, key : String, name : String, label : String, disabled? : Bool = false) -> Bool {
  let p = theme().p
  let id = c.id(key)
  let hot = !disabled && c.lit(id)
  let b = c.box(style=panel_icon_box, disabled~, id=if disabled { 0 } else { id }, fn() {
    icon(c, name, size=panel_icon_size, color=if hot { p.text } else { p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label~, disabled~)
  tip(c, "pib/" + key, id, label)
  !disabled && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let panel_head_box : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S1 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let panel_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let panel_note_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let panel_group_box : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let panel_label_at : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S0_5")

///|
// kept across runs: a value (no field of it changes)
let panel_text_box : @ui.Style = @ui.css("w=Full px=S2_5")

///|
/// A small panel's foot with a pill at its end (its one thing to do), or at both its ends (`panel_foot_ends`: who runs
/// it at its start, buttons at its end): each in its foot corner, as far in as makes a pill concentric with it, past the
/// panel's padding; its words where they are.
// kept across runs: a value (no field of it changes)
pub let panel_foot_end : @ui.Style = @ui.style(
  pr=capsule_room(r_menu, panel_pill, less=panel_pad),
  pb=capsule_room(r_menu, panel_pill, less=panel_pad),
)

///|
// kept across runs: a value (no field of it changes)
pub let panel_foot_ends : @ui.Style = @ui.style(
  px=capsule_room(r_menu, panel_pill, less=panel_pad),
  pb=capsule_room(r_menu, panel_pill, less=panel_pad),
)

///|
// kept across runs: a value (no field of it changes)
let panel_foot_box : @ui.Style = @ui.style(
  row=true,
  w=Full,
  justify=JEnd,
  gap=S1_5,
  pt=S1,
  // (the last in its panel's foot corner: as far in as makes a pill concentric with it)
  pr=capsule_room(r_menu, panel_pill, less=panel_pad),
  pb=capsule_room(r_menu, panel_pill, less=panel_pad),
)

///|
// kept across runs: a value (no field of it changes)
let panel_button_box : @ui.Style = @ui.css(
  #|row h=S6 px=S2_5 gap=S1 radius=Full align=ACenter justify=JCenter hovered{bg=Hover} disabled{opacity=O50}
)

///|
// kept across runs: a value (no field of it changes)
let panel_button_filled : @ui.Style = panel_button_box.then(
  @ui.css("bg=AccentBg hovered{bg=A(Accent,O20)}"),
)

///|
// kept across runs: a value (no field of it changes)
let panel_button_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L6, weight=Medium, wrap=false, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let panel_button_accent : @ui.TextStyle = panel_button_words.then(@ui.text_style(color=AccentText))

///|
// kept across runs: a value (no field of it changes)
let panel_button_quiet : @ui.TextStyle = panel_button_words.then(@ui.text_style(color=Muted))

///|
// kept across runs: a value (no field of it changes)
let panel_icon_box : @ui.Style = @ui.css(
  #|w=S6 h=S6 radius=Full align=ACenter justify=JCenter hovered{bg=Hover} disabled{opacity=O35}
)

// ---------------------------------------------------------------------------
// A command to copy, a chooser (parts.tsx CopyCommand, Chooser; parts.css.ts command, controls.css.ts chooser)

///|
/// A command to copy (CopyCommand, parts.css.ts command): the words in the code face (12) on one line, its copy button
/// at its end (an icon button, 6 in, its corner concentric), on the paper, 14 in at its start; pressed, the words
/// copied and a check for a moment (`copied` its name then, `copy` before).
pub fn copy_command(c : @ui.Ctx, key : String, text : String, copy~ : String, copied~ : String) -> Unit {
  let id = c.id(key + "/copy")
  let just = c.within(id, copied_ms)
  c.box(style=command_box, bg=theme().p.paper, fn() {
    c.box(style=command_words_at, fn() { c.text(text, style=command_words) |> ignore }) |> ignore
    if icon_button(c, if just { "check" } else { "copy" }, key=key + "/copy", label=if just { copied } else { copy }) {
      @ui.clipboard_set(text)
      c.mark(id)
      c.wake_in(copied_ms, later=true)
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let command_box : @ui.Style = @ui.css("row w=Full pl=S3_5 pr=S1_5 py=S1_5 gap=S2 radius=Xl align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let command_words_at : @ui.Style = @ui.css("w=Grow(1.0)")

///|
// kept across runs: a value (no field of it changes)
let command_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Fg, wrap=false)

///|
/// A choice that opens a menu of what it can be (Chooser, controls.css.ts chooser): quiet words (12) and a small
/// chevron, 28 high, 8 in, 8 round, the hover's ground and the ink pointed at or open; pressed, its menu (@sf.dropdown) of
/// `entries` (a choice each: @kit.menu_radio) on `side`, 220 wide at least. `open`: whether its menu is open, the
/// view's (what it is now comes back with what was chosen). `lead`: what stands before its words (a station's mark),
/// in the ink its words have.
pub fn chooser(
  c : @ui.Ctx,
  key : String,
  words : String,
  entries : Array[@kit.Entry],
  open : Bool,
  side? : @ui.Side = Bottom,
  lead? : (Int64) -> Unit,
) -> @kit.Menu {
  let p = theme().p
  let id = c.id(key)
  let opened = if c.clicked(id) { !open } else { open }
  let lit = c.lit(id) || opened
  let b = c.box(style=chooser_box, selected=opened, id~, fn() {
    match lead {
      Some(f) => f(if lit { p.text } else { p.muted })
      None => ()
    }
    c.text(words, style=if lit { chooser_words_lit } else { chooser_words }) |> ignore
    icon(c, "chevron-down", size=chooser_chevron, color=if lit { p.text } else { p.muted }) |> ignore
  })
  c.semantics(b, Button, id~, label=words, expanded=opened)
  dropdown(c, key + "/menu", opened, id, entries, {}, chooser_menu_w, side~)
}

///|
// kept across runs: a value (no field of it changes)
let chooser_box : @ui.Style = @ui.css(
  #|row h=S7 px=S2 gap=S1_25 radius=Lg align=ACenter hovered{bg=Hover} selected{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let chooser_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, wrap=false, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let chooser_words_lit : @ui.TextStyle = chooser_words.then(@ui.text_style(color=Fg))

// ---------------------------------------------------------------------------
// A column's edge (parts.tsx ResizeHandle, usePointerTip; Rail.tsx SidebarEdge and DriveViews.tsx ColumnEdge look as
// it does and take the pointer as it does)

///|
/// What a column's edge was done with this frame.
pub(all) enum Resized {
  /// nothing
  Untouched
  /// dragged (once it went 3 from where it was pressed) to this width
  Dragging(Double)
  /// let go after it was dragged, at this width
  Dropped(Double)
  /// pressed and let go without moving (the web's `press`: a panel closing)
  Pressed
  /// the second of two clicks (the first was `Pressed`): its own width again, or as wide as what it holds needs
  Twice
} derive(Eq, Show, Debug)

///|
/// An edge in hand: where the press went down, its column's width then, whether it has gone past the slop.
priv struct Handling {
  x0 : Double
  w0 : Double
  mut moved : Bool
}

///|
/// The edges in hand, by their ids.
let handlings : Map[Int, Handling] = {}

///|
/// What the pointer does with the edge `id` of a column `width` wide, on its `edge`: pressed and gone 3 from where it
/// went down, the width it is dragged to (the width it had then, the pointer's way on the right edge, the other way on
/// the left, between `min` and `max` on whole pixels); let go, the width it ends at, or a press without moving, or the
/// second of two clicks. The pointer is the edge's while it is pressed, over it or not. A width that changes builds the
/// frame again (Ctx::built_from_changed): the page takes it there, the column and its edge under the pointer at once.
pub fn handle_drag(
  c : @ui.Ctx,
  id : Int,
  width : Double,
  min~ : Double,
  max~ : Double,
  edge? : @ui.Side = Right,
) -> Resized {
  let (px, _, down) = c.pointer()
  let at = fn(h : Handling) {
    let d = if edge is Left { h.x0 - px } else { px - h.x0 }
    dmax(min, dmin(max, (h.w0 + d).round()))
  }
  if c.pressed(id) {
    let h = match handlings.get(id) {
      Some(h) => h
      None => {
        // (from where it went down: the frame that sees the press may see it moved already)
        let h : Handling = { x0: c.press_x, w0: width, moved: false }
        handlings[id] = h
        h
      }
    }
    h.moved = h.moved || (px - h.x0).abs() >= handle_slop
    if !h.moved {
      return Untouched
    }
    let w = at(h)
    // (the column was built at `width`: built again at this one, the edge under the pointer in this frame)
    if w != width {
      c.built_from_changed("a column's edge dragged")
    }
    return Dragging(w)
  }
  let held = if down { None } else { handlings.get(id) }
  if !down {
    handlings.remove(id)
  }
  if c.double_clicked(id) {
    Twice
  } else if held is Some(h) && h.moved {
    let w = at(h)
    if w != width {
      c.built_from_changed("a column's edge let go")
    }
    Dropped(w)
  } else if c.clicked(id) {
    Pressed
  } else {
    Untouched
  }
}

///|
/// How an edge shows: its bar `over` its column, or `on` it (pointed at, focused, in hand), or `active` (pressed,
/// dragged); the line along it on it or active, unless it has `line` false.
fn edge_state(over : Bool, on : Bool, active : Bool, line : Bool) -> Int {
  (if over || on || active { 1 } else { 0 }) |
  (if on || active { 2 } else { 0 }) |
  (if active { 4 } else { 0 }) |
  (if (on && line) || active { 8 } else { 0 })
}

///|
/// How each edge showed last, by its key: as it changes, its look moves to the new one (the web's transitions).
let edges_shown : Map[String, Int] = {}

///|
/// A column's edge as it looks (parts.css.ts resizeHandle; Rail.css.ts edge the same), 7 wide and as high as what holds
/// it: a bar 5 wide at its middle and a hairline through the bar's middle, 8 short of the ends, clear toward them
/// (clear to 10%, the field's edge grey at 50%, clear from 90%). The bar shows, 24 high, while the pointer is `over` the
/// column; 48 high while `on` the edge (pointed at, focused, in hand), in the field's edge grey while `active`
/// (pressed, dragged), else the strong line's grey; the line while on the edge, unless `line` is false (the sidebar's
/// edge, folded), and while active. Its bar's height and showing move over 180 ms (a quick start, a soft landing), its
/// grey over 150 and its line over 140 on the ease-out.
pub fn edge_look(
  c : @ui.Ctx,
  key : String,
  over~ : Bool,
  on~ : Bool,
  active~ : Bool,
  line? : Bool = true,
) -> Unit {
  let now = edge_state(over, on, active, line)
  let bar = key + "/bar"
  let hairline = key + "/line"
  match edges_shown.get(key) {
    Some(was) if was != now => {
      c.move_state([(bar, ["height", "opacity"])], duration=edge_bar_ms, ease=Soft)
      c.move_state([(bar, ["background-color"])], duration=edge_ink_ms, ease=Out)
      c.move_state([(hairline, ["opacity"])], duration=edge_line_ms, ease=Out)
    }
    _ => ()
  }
  edges_shown[key] = now
  c.box(style=edge_box, fn() {
    c.layer(fn() {
      c.box(style=edge_line_place, fn() {
        c.box(style=if (now & 8) != 0 { edge_line_on } else { edge_line }, moves=hairline, fn() {
          for i in 0..<edge_line_steps {
            let y = (i.to_double() + 0.5) / edge_line_steps.to_double()
            // (clear to 10% and from 90%, the grey whole at the middle, straight between)
            let a = if y <= 0.1 || y >= 0.9 { 0.0 } else if y < 0.5 { (y - 0.1) / 0.4 } else { (0.9 - y) / 0.4 }
            c.look(c.box(style=edge_step, fn() {  }), @ui.look(alpha=a))
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    let look = if (now & 4) != 0 {
      edge_bar_active
    } else if (now & 2) != 0 {
      edge_bar_on
    } else if (now & 1) != 0 {
      edge_bar_shown
    } else {
      edge_bar
    }
    c.box(style=look, moves=bar, fn() {  }) |> ignore
  })
  |> ignore
}

///|
let edge_bar_ms : Double = 180.0

///|
let edge_ink_ms : Double = 150.0

///|
let edge_line_ms : Double = 140.0

///|
// kept across runs: a value (no field of it changes)
let edge_box : @ui.Style = @ui.style(row=true, w=Fixed(handle_w), h=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let edge_line_place : @ui.Style = @ui.css("row w=Full h=Full py=S2 justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let edge_line : @ui.Style = @ui.css("w=SPx h=Full opacity=O0")

///|
// kept across runs: a value (no field of it changes)
let edge_line_on : @ui.Style = edge_line.then(@ui.css("opacity=O100"))

///|
// kept across runs: a value (no field of it changes)
let edge_step : @ui.Style = @ui.style(w=Full, h=grow, bg=FieldHover)

///|
// kept across runs: a value (no field of it changes)
let edge_bar : @ui.Style = @ui.style(w=Fixed(edge_bar_w), h=S6, radius=Full, bg=Border, opacity=O0)

///|
// kept across runs: a value (no field of it changes)
let edge_bar_shown : @ui.Style = edge_bar.then(@ui.css("opacity=O100"))

///|
// kept across runs: a value (no field of it changes)
let edge_bar_on : @ui.Style = edge_bar_shown.then(@ui.css("h=S12"))

///|
// kept across runs: a value (no field of it changes)
let edge_bar_active : @ui.Style = edge_bar_on.then(@ui.css("bg=FieldHover"))

///|
/// The edges whose tip is put away, by their keys, and the last frame each was pressed in: pressed since the pointer
/// came onto them (the web's tip.hide() as the pointer goes down: back only once it has left and come again).
let edge_tips_away : Map[String, Int] = {}

///|
/// A tip that follows the pointer along a tall thin thing (usePointerTip: an edge), `id`: shown 300 ms after the pointer
/// comes onto it, 14 beside the pointer on `side`, its middle level with it, as the pointer moves along; gone as it
/// leaves, and as it presses, until it has left and come again. Said each frame the thing is drawn.
pub fn edge_tip(c : @ui.Ctx, key : String, id : Int, words : String, side? : @ui.Side = Right) -> Unit {
  if words == "" || id == 0 {
    return
  }
  let (px, py, down) = c.pointer()
  let on = c.lit(id) ||
    (match c.rect_of(id) {
      Some((x, y, w, h)) => px >= x && px < x + w && py >= y && py < y + h
      None => false
    })
  let frame = c.frame_number()
  if c.pressed(id) || c.clicked(id) {
    edge_tips_away[key] = frame
  } else if !on && !down {
    match edge_tips_away.get(key) {
      // (the frame it is let go in: the pointer may be past where the edge was last drawn, as it followed it)
      Some(at) if at == frame || at == frame - 1 => ()
      _ => edge_tips_away.remove(key)
    }
  }
  // (put away, it is not drawn at all; its delay starts anew once the pointer is back on it. The press itself is told
  // to the tip, so it is shut as it is pressed, not left open to show for a moment as the pointer leaves.)
  if edge_tips_away.contains(key) && !c.pressed(id) && !c.clicked(id) {
    return
  }
  @kit.tooltip(
    c,
    "edge-tip/" + key,
    id,
    words,
    delay=edge_tip_ms,
    skip=0.0,
    side~,
    offset=edge_tip_gap,
    at=(px, py, 0.0, 0.0),
    look=fn(c, _, words) { tip_look(c, words, "") },
  )
  |> ignore
}

///|
/// ResizeHandle (parts.tsx): a strip 7 wide over its column's `edge`, 4 of it past it (its line on the edge), the
/// column's height, that drags the column's width (handle_drag: from `width`, between `min` and `max`), as edge_look
/// shows it: its bar while the pointer is `over` the column (the page says), the line and the longer bar on it, and
/// `active` while it, or another edge dragged with it, is in hand. Its words, `label` (and `press`'s after it, what a
/// press without moving does), follow the pointer along it, gone as it is pressed until the pointer comes onto it
/// again. Drawn last in its column's box (it is put by its edges, out of the column's flow). What was done with it
/// comes back: the page keeps the width (the web's keptWidth and setKeptWidth: where it keeps what it keeps on the
/// device), and a press or the second of two clicks is the page's.
pub fn resize_handle(
  c : @ui.Ctx,
  key : String,
  width : Double,
  min~ : Double,
  max~ : Double,
  label~ : String,
  edge? : @ui.Side = Right,
  press? : String = "",
  over? : Bool = false,
  active? : Bool = false,
) -> Resized {
  let id = c.id(key)
  c.cursor(id, ResizeX)
  let said = handle_drag(c, id, width, min~, max~, edge~)
  let held = active || (said is Dragging(_)) || c.pressed(id)
  let on = c.lit(id) || c.focus_shown(id) || held
  let words = if press == "" { label } else { label + " · " + press }
  let body = fn() { edge_look(c, key, over~, on~, active=held) }
  let b = if edge is Left {
    c.box(left=-handle_out, top=0.0, bottom=0.0, id~, body)
  } else {
    c.box(right=-handle_out, top=0.0, bottom=0.0, id~, body)
  }
  c.semantics(b, Separator, id~, label=words)
  // (pressed, it goes until the pointer has left the edge and come again)
  edge_tip(c, key, id, words, side=if edge is Left { Left } else { Right })
  said
}

// ---------------------------------------------------------------------------
// A card of options (SettingParts.kt DecisionOptions; Decisions.css.ts options, choice)

///|
/// How far in the card of options' rows stand (the ladder's inset: round by its next step, 18, in the card's corners),
/// how far a row's number stands in it (concentric with the row: its corner less the disc's half), its disc's size.
let options_card_pad : Double = corner_inset

///|
let options_row_pad : Double = 7.0

///|
let option_disc : Double = 22.0

///|
/// An option's measures: its number's disc and how far in it stands (7 from the row's top and side, 22 across); its
/// label's size and line, its detail's. The wide frame's as the web's (Decisions.css.ts choice: a 20 disc 8 in, 13 on
/// 20 over 12 on 18).
priv struct OptionType {
  disc : Double
  pad_in : Double
  label : Double
  label_line : Double
  detail : Double
  detail_line : Double
}

///|
fn option_type(wide : Bool) -> OptionType {
  if wide {
    { disc: 20.0, pad_in: 8.0, label: 13.0, label_line: 20.0, detail: 12.0, detail_line: 18.0 }
  } else {
    { disc: option_disc, pad_in: options_row_pad, label: 15.0, label_line: 21.0, detail: 13.0, detail_line: 18.0 }
  }
}

///|
/// The card of options in the wide frame: as wide as what it says, 460 at least (Decisions.css.ts options); on a phone
/// as wide as where it is.
let options_least_wide : Double = 460.0

///|
/// The card's width: as wide as its widest label or detail with its number and paddings, 460 at least, `room` at most
/// (the web's `width: fit-content; min-width: min(100%, 460px)`); on a phone where it is's.
fn options_w(options : Array[(String, String, Bool)], ot : OptionType, wide : Bool, room : Double) -> @ui.Size {
  if !wide {
    return Fill(1.0)
  }
  let mut words = 0.0
  for o in options {
    words = dmax(words, @ui.text_advance(o.0, size=ot.label, weight=500))
    words = dmax(words, @ui.text_advance(o.1, size=ot.detail, weight=400))
  }
  // (the card's inset each side, the row's number in by 8 and 12 after it, the row's 12 at its end)
  Px(dmin(room, dmax(options_least_wide, options_card_pad * 2.0 + ot.pad_in + ot.disc + 12.0 + words + 12.0)).ceil())
}

///|
/// The card's corner: a card's of the ladder, its rows the ladder's inset in round by its next step (18) and their
/// discs concentric with them (as far in as their half less that: the row's pad_in).
let options_card_radius : Double = card_corner

///|
/// A card of options (SettingParts.kt DecisionOptions): each a row to be pressed (its ground under the finger the
/// ladder's inset in from the card's edge, rounded 18), its number in a disc (the one recommended in the accent), its label and what it
/// leads to (`options`: each its label, its detail, whether recommended); half there when not `enabled`, a spinner on
/// the one being answered (`busy`, none pressed meanwhile; `chosen` stays whole). The wide frame's as the web's (`wide`:
/// as wide as what it says, `room` at most, on the text at 5%, its row's ground under the pointer). The option
/// tapped, on the frame after.
pub fn options_card(
  c : @ui.Ctx,
  key : String,
  options : Array[(String, String, Bool)],
  enabled : Bool,
  busy : Int?,
  chosen? : Int? = None,
  wide? : Bool = false,
  room? : Double = 0.0,
) -> Int? {
  let t = theme()
  let free = enabled && busy is None
  let mut picked : Int? = None
  let ot = option_type(wide)
  // (in the wide frame as wide as what it says and 460 at least, on the text at 5%: Decisions.css.ts options)
  c.box(w=Fill(1.0), align=if wide { AStart } else { AStretch }, fn() {
    c.box(w=options_w(options, ot, wide, room), radius=options_card_radius, bg=if wide { alpha(t.p.text, 0.05) } else { t.p.chip }, pad=options_card_pad, fn() {
      // (nothing drawn between two: SettingParts.kt DecisionOptions)
      for i, o in options {
        let id = c.id(key + "/" + i.to_string())
        if c.clicked(id) && free {
          picked = Some(i)
        }
        // under a mouse's pointer its row's ground, in any layout (Decisions.css.ts choice:hover)
        let mouse = @ui.pointing() is Mouse
        if mouse && free {
          c.cursor(id, Hand)
        }
        let hot = mouse && free && c.lit(id)
        c.box(
          dir=Row,
          w=Fill(1.0),
          pl=ot.pad_in,
          pr=12.0,
          pt=ot.pad_in,
          pb=ot.pad_in,
          gap=12.0,
          align=AStart,
          radius=18.0,
          bg=if hot { t.p.hover } else { 0L },
          opacity=if enabled || chosen == Some(i) { 1.0 } else { 0.5 },
          id~,
          fn() {
            c.box(
              w=Px(ot.disc),
              h=Px(ot.disc),
              radius=ot.disc / 2.0,
              bg=if o.2 { t.p.accent } else { alpha(t.p.text, 0.09) },
              align=ACenter,
              justify=JCenter,
              fn() {
                let color = if o.2 { 0xFFFFFFFFL } else { t.p.muted }
                if i < 6 {
                  icon(c, "option-\{i + 1}", size=ot.disc, color~) |> ignore
                } else {
                  c.text("\{i + 1}", size=12.0, weight=600, color~, wrap=false) |> ignore
                }
              },
            )
            |> ignore
            c.box(w=Fill(1.0), fn() {
              c.text(o.0, size=ot.label, weight=500, color=t.p.text, line=ot.label_line) |> ignore
              if o.1 != "" {
                c.text(o.1, size=ot.detail, color=t.p.muted, line=ot.detail_line) |> ignore
              }
            })
            |> ignore
            if busy == Some(i) {
              c.box(h=Px(ot.label_line), justify=JCenter, fn() { spinner(c, size=12.0) |> ignore })
              |> ignore
            }
            // SettingParts.kt options: clickable while free, its ripple in the ink (ripple(color = C.ink))
            if free {
              @motion.ripple(c, id, 18.0, ink=alpha(t.p.text, 0.1))
            }
          },
        )
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  picked
}

///|
// kept across runs: a value (no field of it changes)
let dialog_title_line : @ui.Style = @ui.style(row=true, w=grow, gap=S2, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let dialog_step : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dialog_title_one : @ui.TextStyle = dialog_title.then(one_line)

///|
/// A page that waits on something (cloud/Security.tsx SecurityWaiting, mobile/Security.tsx SecurityWaitingScreen):
/// its mark (`mark`, an icon's name), what it waits for (`title`, `lead`), then what can be done meanwhile (`body`); its parts 14 apart,
/// centred. On a touch screen the phone's (mWaiting: in the middle of its height, 28 in at its sides, the mark 44, the
/// title bold); on a computer the desktop page's (waiting: 110 down, 460 wide at most, 24 in, the mark 40, the title
/// 600).
pub fn waiting_page(c : @ui.Ctx, mark : String, title : String, lead : String, body : () -> Unit) -> Unit {
  let touch = touch_system()
  c.box(style=if touch { wait_room_touch } else { wait_room }, fn() {
    if !touch {
      c.box(style=@ui.style(h=Fixed(wait_top)), fn() {  }) |> ignore
    }
    c.box(style=if touch { wait_column_touch } else { wait_column }, fn() {
      icon(c, mark, size=if touch { wait_icon_touch } else { wait_icon }, color=c.color(Fg)) |> ignore
      c.text(title, style=if touch { wait_title_touch } else { wait_title }) |> ignore
      c.text(lead, style=wait_lead) |> ignore
      body()
    })
    |> ignore
  })
  |> ignore
}

///|
/// The desktop page's place (waiting: margin 110 auto 0) and the touch screen's (mWaiting: its height, the column in
/// its middle).
// kept across runs: a value (no field of it changes)
let wait_room : @ui.Style = @ui.css("w=Full h=Full align=ACenter")

///|
let wait_top : Double = 110.0

///|
// kept across runs: a value (no field of it changes)
let wait_room_touch : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// The column: 460 wide at most, 24 in at its sides (waiting); a touch screen's 28 in (mWaiting); 14 apart.
// kept across runs: a value (no field of it changes)
let wait_column : @ui.Style = @ui.css("w=Full px=S6 gap=S3_5 align=ACenter").then(@ui.style(max_w=Fixed(wait_w)))

///|
let wait_w : Double = 460.0

///|
// kept across runs: a value (no field of it changes)
let wait_column_touch : @ui.Style = @ui.css("w=Full px=S7 gap=S3_5 align=ACenter")

///|
/// The mark: 40 on the desktop page, 44 on a touch screen.
let wait_icon : Double = 40.0

///|
let wait_icon_touch : Double = 44.0

///|
/// The title: the heading's size, 600 (waitingTitle); a touch screen's bold (mWaitingTitle, a <b>).
// kept across runs: a value (no field of it changes)
let wait_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let wait_title_touch : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Bold, color=Fg, center=true)

///|
/// What it waits for: the body's, muted (waitingLead).
// kept across runs: a value (no field of it changes)
let wait_lead : @ui.TextStyle = @ui.text_style(size=Base, leading=L7, color=Muted, center=true)

///|
/// The way into an app, signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box it is
/// given: its picture (`art`, a drawable), what it is (`title`, `note`), its button (`label`; `busy` while it is under
/// way, not pressed again), what to know of it (`foot`). A computer's the picture and the button alone, no wider than
/// the desktop app's (asked for, 2026-10-23); a touch screen's all of it, the button across its page. True on the frame
/// after the button was pressed.
pub fn way_in(
  c : @ui.Ctx,
  art : String,
  title : String,
  note : String,
  label : String,
  foot : String,
  busy? : Bool = false,
) -> Bool {
  let bare = !touch_system()
  let id = c.id("sign-in")
  let pressed = c.clicked(id) && !busy
  c.box(style=sign_in_box, fn() {
    drawable(c, art, dmin(sign_in_picture_w, c.width - sign_in_side_w - sign_in_side_w)) |> ignore
    if !bare {
      c.box(style=sign_in_title_box, fn() { c.text(title, style=sign_in_title) |> ignore }) |> ignore
      c.text(note, style=sign_in_note) |> ignore
    }
    c.box(style=sign_in_gap, fn() {  }) |> ignore
    c.box(style=if bare { sign_in_button_desk } else { sign_in_button_touch }, id~, fn() {
      c.text(label, style=sign_in_words) |> ignore
      // SignIn.kt: clip(CircleShape).clickable
      if !busy {
        @motion.ripple(c, id, sign_in_button_h / 2.0)
      }
    })
    |> ignore
    if !bare {
      c.text(foot, style=sign_in_many) |> ignore
    }
  })
  |> ignore
  pressed
}

///|
/// The sign-in button's width at most on a desktop, as the desktop app's.
let sign_in_desk_w : Double = 300.0

///|
/// On a phone or a tablet: across a phone's page less its sides; no wider than this on a larger one.
let sign_in_touch_w : Double = 420.0

///|
/// The button: 50 high, a pill (SignIn.kt: height(50.dp), CircleShape).
let sign_in_button_h : Double = 50.0

///|
/// The picture: as wide as the button at most (SignIn.kt: widthIn(max = 300.dp)), never past the page's sides.
let sign_in_picture_w : Double = 300.0

///|
/// The page: its picture, words and button in a column in its middle, 30 in from its sides and 40 from its top and
/// foot, 12 apart (SignIn.kt: padding(horizontal = 30.dp, vertical = 40.dp), spacedBy(12.dp)).
// kept across runs: a value (no field of it changes)
let sign_in_box : @ui.Style = @ui.style(
  w=Full,
  h=Full,
  px=sign_in_side,
  py=S10,
  gap=S3,
  align=ACenter,
  justify=JCenter,
)

///|
/// What the page leaves either side of the picture (its sides: sign_in_box's px).
let sign_in_side_w : Double = 30.0

///|
/// The title 10 under the picture, 28, bold, on the font's own line (SignIn.kt: 28.sp, Bold).
// kept across runs: a value (no field of it changes)
let sign_in_title_box : @ui.Style = @ui.css("pt=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sign_in_title : @ui.TextStyle = @ui.text_style(
  size=sign_in_title_size,
  weight=Bold,
  color=Fg,
  wrap=false,
  leading=Font,
)

///|
/// What still.fail is for: the body's size, muted, centred (SignIn.kt: 15.sp, lineHeight 21.sp).
// kept across runs: a value (no field of it changes)
let sign_in_note : @ui.TextStyle = @ui.text_style(size=Lg, color=Muted, center=true, w=Full)

///|
/// 6 more over the button.
// kept across runs: a value (no field of it changes)
let sign_in_gap : @ui.Style = @ui.css("h=S1_5")

///|
/// The button: the ink's, a pill across the page, no wider than `most`; its words the page's ground, semibold.
fn sign_in_button(most : Double) -> @ui.Style {
  @ui.style(
    row=true,
    w=Full,
    max_w=Fixed(most),
    h=Fixed(sign_in_button_h),
    radius=Full,
    bg=Fg,
    align=ACenter,
    justify=JCenter,
  )
}

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_desk : @ui.Style = sign_in_button(sign_in_desk_w)

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_touch : @ui.Style = sign_in_button(sign_in_touch_w)

///|
// kept across runs: a value (no field of it changes)
let sign_in_words : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, color=Bg, wrap=false, leading=Font)

///|
/// 可同时登录多个账号: small, muted.
// kept across runs: a value (no field of it changes)
let sign_in_many : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false, leading=Font)

