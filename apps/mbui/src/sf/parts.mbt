// still.fail's parts (web/ui parts.tsx, styles/controls.css.ts, page.css.ts,
// waiting.tsx), drawn with mbui: buttons, icon buttons, chips, a segmented
// choice, small panels and their rows, page heads and cards, and the three
// ways of waiting.

///|
/// A hover's or a press's ground coming and going over --dur.
fn ease_to(c : @ui.Ctx, key : String, on : Bool) -> Double {
  c.spring(key, if on { 1.0 } else { 0.0 }, stiffness=900.0, damping=60.0)
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
} derive(Eq)

///|
/// A button (Button): a 36 pill on the wide screen, the phone's 38 one on a
/// narrow; an icon before its words if given, a spinner in its place while
/// `busy`. True on the frame after it was pressed.
pub fn button(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  tone? : Tone = Plain,
  icon? : String = "",
  busy? : Bool = false,
  disabled? : Bool = false,
  w? : @ui.Size = Auto,
) -> Bool {
  let t = theme()
  let p = t.p
  let id = c.id(if key == "" { "sf-btn/" + label } else { key })
  let live = !disabled && !busy
  let h = ease_to(c, "sf-btn-h/\{id}", live && (c.hovered(id) || c.pressed(id)))
  let (ground, line, ink) = if t.narrow {
    match tone {
      Primary => (p.text, p.text, p.bg)
      DangerSolid => (p.red, p.red, 0xFFFFFFFFL)
      Danger => (p.chip, p.chip, p.red)
      Ghost => (alpha(p.hover, h), 0L, p.text)
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
      Danger => (over(p.canvas, alpha(p.hover, h)), p.line_strong, p.red)
      Plain => (over(p.canvas, alpha(p.hover, h)), p.line_strong, p.text)
    }
  }
  let height = if t.narrow { 38.0 } else { button_h }
  let solid = tone == Primary || tone == DangerSolid
  c.box(
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
) -> Bool {
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let quiet = quiet.unwrap_or(t.p.muted)
  let id = c.id(if key == "" { "sf-ib/" + icon } else { key })
  let h = ease_to(c, "sf-ib-h/\{id}", !disabled && (c.hovered(id) || c.pressed(id)))
  let ground = if on {
    alpha(ink, 0.08)
  } else {
    // the page's hover, as a tint of the ink it sits with
    alpha(ink, 0.065 * h)
  }
  c.box(
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
  |> ignore
  !disabled && c.clicked(id)
}

///|
/// A chip (the reader's bars, Reader.css.ts chip): 30 high, its corner 10,
/// on a 7% tint of the ink, 12% under the pointer; its words small.
pub fn chip(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  ink? : Int64,
  disabled? : Bool = false,
) -> Bool {
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let id = c.id(if key == "" { "sf-chip/" + label + icon } else { key })
  let h = ease_to(c, "sf-chip-h/\{id}", !disabled && c.hovered(id))
  c.box(
    dir=Row,
    h=Px(30.0),
    min_w=30.0,
    padx=if label == "" { 0.0 } else { 10.0 },
    gap=2.0,
    align=ACenter,
    justify=JCenter,
    bg=alpha(ink, 0.07 + 0.05 * h),
    radius=10.0,
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
/// A choice of a few (Segmented; the kit's sliding toggle group): a quiet
/// pill track, the chosen raised on the canvas and sliding to it. Returns the
/// chosen index.
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
  // as wide as the widest, each, unless told
  let w = if item_w > 0.0 { item_w } else { 76.0 }
  let items = labels.mapi(fn(i, l) { @kit.item(i.to_string(), label=l) })
  let now = @kit.toggle_group(
    c,
    key,
    items,
    [chosen.to_string()],
    slide=true,
    look=fn(c, s) {
      c.box(w=Px(w), h=Px(30.0), align=ACenter, justify=JCenter, fn() {
        c.text(
          s.label,
          size=t.t.ui,
          weight=if s.on { 500 } else { 400 },
          color=if s.on || s.hovered { ink } else { t.p.muted },
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    },
    thumb=fn(c, w, h) {
      c.box(
        w=Px(w),
        h=Px(h),
        bg=thumb,
        radius=15.0,
        border=0.5,
        border_color=t.p.line,
        shadow=1.0,
        shadow_color=t.p.shadow,
        shadow_y=0.0,
        fn() {  },
      )
      |> ignore
    },
    ground=fn(c, _, items) {
      c.box(dir=Row, pad=3.0, gap=2.0, bg=alpha(ink, 0.06), radius=18.0, items) |> ignore
    },
  ).value
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(chosen)
    _ => chosen
  }
}

///|
/// A line to type in, its frame (Controls.kt Field) as a look for mbui's field (@kit.text_field): 12 round, the card's
/// ground, a line round it, its words 12 by 10 in.
pub fn field_look(c : @ui.Ctx, s : @kit.FieldState, editor : () -> Unit) -> Unit {
  c.box(id=s.id, style=field_frame, editor) |> ignore
}

///|
/// Controls.kt Field's frame: as wide as where it is, 12 by 10 in, 12 round, the card's ground, a line round it.
// kept across runs: a value (no field of it changes)
let field_frame : @ui.Style = @ui.style(w=Full, px=S3, py=S2_5, radius=Xl, bg=Card, border=B1, border_color=Line)

// ---------------------------------------------------------------------------
// Small panels (docs/ui-panels.md)

///|
/// A small panel's ground (controls.css.ts popover): the canvas (the raised
/// grey in dark), a line round it, its shadow; padded panel_pad, its corner
/// the menu's. `min_w`: as wide as what it holds, at least that (a menu's,
/// controls.css.ts menuList).
pub fn panel(
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
    min_h=34.0,
    padx=text_in,
    pady=7.0,
    gap=if panel { panel_row_gap } else { menu_row_gap },
    align=ACenter,
    bg=if c.hovered(id) { t.p.hover } else { 0L },
    radius=@ui.concentric(r_menu, panel_pad),
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
let panel_row_icon : @ui.Style = @ui.style(w=S5, align=ACenter)

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
/// A page card of words (pages.css.ts card): card_pad in from every side,
/// its corner 22, or 38 with a solid button in its corner (`button_corner`).
pub fn card(
  c : @ui.Ctx,
  button_corner? : Bool = false,
  gap? : Double = 14.0,
  body : () -> Unit,
) -> Int {
  let t = theme()
  c.box(
    pad=card_pad,
    gap~,
    bg=t.p.card,
    radius=if button_corner {
      card_pad + button_h / 2.0
    } else {
      card_corner
    },
    body,
  )
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

// ---------------------------------------------------------------------------
// Waiting (waiting.tsx; docs/ui-panels.md 等待)

///|
/// Words about a wait show only once it has taken this long.
pub let later_ms : Double = 400.0

///|
/// Whether `key` has been waited on for later_ms, since the first frame that asked (@kit.after's clock: a frame comes
/// when it has).
fn waited_long(c : @ui.Ctx, key : String) -> Bool {
  @kit.after(c, "sf-wait/" + key, true, later_ms)
}

///|
/// Forgets a wait, so the next one on `key` waits its 400ms again.
pub fn done_waiting(c : @ui.Ctx, key : String) -> Unit {
  @kit.after(c, "sf-wait/" + key, false, later_ms) |> ignore
}

///|
/// One breath of the placeholders.
let breath_ms : Double = 1400.0

///|
/// The placeholders' breath: 1 → 0.5 → 1 in breath_ms, eased; 0.6 when what they wait on failed.
pub fn breath(c : @ui.Ctx, failed? : Bool = false) -> Double {
  if failed {
    return 0.6
  }
  let pi = 3.141592653589793
  let f = c.cycle(breath_ms)
  // ease-in-out between the two ends
  0.75 + 0.25 * @dmath.cos(2.0 * pi * f)
}

///|
/// A placeholder bar (a title's, a line's, a picture's): the neutral grey,
/// round; `breathing`, on the placeholders' breath by itself (Stations.kt Bar).
pub fn bar(
  c : @ui.Ctx,
  w : @ui.Size,
  h : Double,
  radius? : Double = -1.0,
  breathing? : Bool = false,
) -> Unit {
  let t = theme()
  let seen = if breathing { breath(c) } else { 1.0 }
  c.box(
    w~,
    h=Px(h),
    bg=t.p.neutral_bg,
    radius=if radius >= 0.0 { radius } else { h / 2.0 },
    opacity=seen,
    fn() {  },
  )
  |> ignore
}

///|
/// What could not be read, over the shapes (WaitPill): a pill, red when it
/// failed; the others only after later_ms.
pub fn wait_pill(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && !waited_long(c, "pill/" + key + text) {
    return
  }
  c.box(dir=Row, padx=12.0, pady=6.0, gap=8.0, bg=t.p.neutral_bg, radius=15.0, fn() {
    c.text(
      text,
      size=t.t.meta,
      color=if error { t.p.red } else { t.p.muted },
      line=18.0,
    )
    |> ignore
  })
  |> ignore
}

///|
/// WaitLine's words: 13/18 on every width (Waiting.kt: fontSize 13.sp, lineHeight 18.sp).
// kept across runs: a value (no field of it changes)
let wait_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5)

///|
/// A small part still on its way (WaitLine): a 12 spinner and grey words
/// after later_ms; red words and no spinner when it failed.
pub fn wait_line(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && !waited_long(c, "line/" + key + text) {
    c.box(h=Px(18.0), fn() {  }) |> ignore
    return
  }
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    if !error {
      spinner(c, size=12.0) |> ignore
    }
    c.text(text, style=wait_words, color=if error { t.p.red } else { t.p.muted }) |> ignore
  })
  |> ignore
}

///|
/// How much of something with a size has come (Progress): mbui's progress bar (@kit.progress) in still.fail's look, a 3
/// high pill on 18% of the accent; `part` None when the whole is not known, a 40% piece sweeping across.
pub fn progress(c : @ui.Ctx, part : Double?, w? : @ui.Size = Fill(1.0), color? : Int64) -> Unit {
  let accent = color.unwrap_or(theme().p.accent)
  @kit.progress(
    c,
    match part {
      Some(k) => Some(k * 100.0)
      None => None
    },
    max=100.0,
    w~,
    look=@kit.progress_look_of(fill=accent),
  )
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
let sheet_grab_outer : @ui.Style = @ui.style(w=Full, pt=S2, pb=S1)

///|
// kept across runs: a value (no field of it changes)
let sheet_grab_inner : @ui.Style = @ui.style(w=Full, py=S1, align=ACenter)

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
/// The only way anything explains itself on hover. With no label, none. `key` names it where it is asked.
pub fn tip(
  c : @ui.Ctx,
  key : String,
  id : Int,
  label : String,
  side? : @ui.Side = Bottom,
  shortcut? : String = "",
) -> Unit {
  if label == "" || id == 0 {
    return
  }
  let keys = shortcut_keys(shortcut)
  @kit.tooltip(c, "tip/" + key, id, label, delay=tip_delay_ms, side~, look=fn(c, _, words) {
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
let tip_line : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let tip_words : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary)

///|
// kept across runs: a value (no field of it changes)
let tip_keys : @ui.TextStyle = @ui.text_style(size=Xs, color=OnPrimary, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tip_quiet : @ui.Style = @ui.style(opacity=O60)

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
/// How a small panel comes (controls.css.ts popover's popKeyframes): from 97% and clear to itself over 140 ms
/// (--ease-out), from its top; it goes at once, as the web's does.
// kept across runs: a value (no field of it changes)
pub let pop_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, ox=0.5, oy=0.0, spec=@motion.tween(140.0, ease=Out))

///|
// kept across runs: a value (no field of it changes)
pub let pop_out : @motion.Trans = @motion.trans(spec=@motion.tween(0.0))

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
) -> Unit {
  let t = theme()
  let checked = match s.entry.kind {
    Choice(true) | Check(true) => true
    _ => false
  }
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=34.0,
    padx=10.0,
    pady=7.0,
    gap=if chooser { chooser_gap } else { menu_gap },
    align=ACenter,
    radius=@ui.concentric(20.0, 6.0),
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
        icon(c, icon_name, size=14.0, color=t.p.muted) |> ignore
      }
      c.text(s.entry.label, style=menu_words) |> ignore
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
let menu_check : @ui.Style = @ui.style(w=S3_5, align=ACenter)

///|
/// A menu item's words: as long as they are (the menu as wide as its longest, controls.css.ts menuList).
// kept across runs: a value (no field of it changes)
let menu_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, leading=L5, wrap=false)

///|
/// A heading among a menu's items (controls.css.ts menuLabel): 6 over, 4 under, 10 in; 12, muted.
// kept across runs: a value (no field of it changes)
let menu_heading : @ui.Style = @ui.style(w=Full, px=S2_5, pt=S1_5, pb=S1)

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
pub fn menu(
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
    enter=pop_in,
    exit=pop_out,
    look=fn(c, w, body) { panel(c, min_w=w, body) |> ignore },
    item_look=fn(c, s) { menu_row(c, s, icons.get(s.entry.value).unwrap_or(""), chooser, row_end) },
    heading_look=fn(c, label) {
      c.box(style=menu_heading, fn() { c.text(label, style=menu_heading_words) |> ignore }) |> ignore
    },
  )
}

///|
/// The least a menu is wide (controls.css.ts menuList), and a menu of choices (chooserMenu).
pub let menu_w : Double = 180.0

///|
pub let chooser_menu_w : Double = 220.0

///|
/// What a thing is, said when the pointer rests on a quiet mark beside it (parts.tsx About, own.css.ts about: a 20
/// circle, its ⓘ 14 in the subtle ink, the words' under the pointer; what it says in a tip under it, or on `side`).
/// `label`: what a screen reader calls the mark (the app's word for 关于).
pub fn about(c : @ui.Ctx, key : String, words : String, label~ : String, side? : @ui.Side = Bottom) -> Unit {
  let t = theme()
  let id = c.id(key)
  let b = c.box(style=about_box, id~, fn() {
    icon(c, "info", size=about_icon, color=if c.hovered(id) { t.p.text } else { t.p.subtle }) |> ignore
  })
  c.semantics(b, Button, id~, label~)
  tip(c, key + "/tip", id, words, side~)
}

///|
let about_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let about_box : @ui.Style = @ui.style(w=S5, h=S5, radius=Full, align=ACenter, justify=JCenter)
