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
/// A choice of a few (Segmented): a quiet pill track, the chosen raised on
/// the canvas and sliding to it. Returns the chosen index.
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
  let base = c.id(key)
  let mut sel = chosen
  for i, _ in labels {
    if c.clicked(base + i + 1) {
      sel = i
    }
  }
  // as wide as the widest, each, unless told
  let w = if item_w > 0.0 { item_w } else { 76.0 }
  let x = c.spring(key + "/thumb", sel.to_double() * (w + 2.0))
  c.box(
    dir=Row,
    pad=3.0,
    gap=2.0,
    bg=alpha(ink, 0.06),
    radius=18.0,
    fn() {
      c.box(w=Px(0.0), h=Px(30.0), fn() {
        c.box(
          w=Px(w),
          h=Px(30.0),
          bg=thumb,
          radius=15.0,
          border=0.5,
          border_color=t.p.line,
          shadow=2.0,
          shadow_color=t.p.shadow,
          shadow_y=0.0,
          tx=x,
          fn() {  },
        )
        |> ignore
      })
      |> ignore
      for i, l in labels {
        let on = i == sel
        let id = base + i + 1
        c.box(
          w=Px(w),
          h=Px(30.0),
          align=ACenter,
          justify=JCenter,
          id~,
          fn() {
            c.text(
              l,
              size=t.t.ui,
              weight=if on { 500 } else { 400 },
              color=if on || c.hovered(id) { ink } else { t.p.muted },
              wrap=false,
            )
            |> ignore
          },
        )
        |> ignore
      }
    },
  )
  |> ignore
  sel
}

// ---------------------------------------------------------------------------
// Small panels (docs/ui-panels.md)

///|
/// A small panel's ground (controls.css.ts popover): the canvas (the raised
/// grey in dark), a line round it, its shadow; padded panel_pad, its corner
/// the menu's.
pub fn panel(
  c : @ui.Ctx,
  w? : @ui.Size = Auto,
  h? : @ui.Size = Auto,
  body : () -> Unit,
) -> Int {
  let t = theme()
  c.box(
    w~,
    h~,
    pad=panel_pad,
    bg=if t.dark { t.p.raised } else { t.p.canvas },
    radius=r_menu,
    border=1.0,
    border_color=t.p.line,
    shadow=32.0,
    shadow_y=12.0,
    shadow_color=t.p.shadow,
    clip=true,
    body,
  )
}

///|
/// A row of a small panel (menuItem): at its padding, words text_in in, its
/// ground under the pointer, concentric with the panel.
pub fn menu_item(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  danger? : Bool = false,
  on? : Bool = false,
  note? : String = "",
) -> Bool {
  let t = theme()
  let id = c.id(if key == "" { "sf-mi/" + label } else { key })
  let ink = if danger { t.p.red } else if on { t.p.accent_text } else { t.p.text }
  c.box(
    dir=Row,
    min_h=34.0,
    padx=text_in,
    pady=7.0,
    gap=8.0,
    align=ACenter,
    bg=if c.hovered(id) { t.p.hover } else { 0L },
    radius=r_menu - panel_pad,
    id~,
    fn() {
      if icon != "" {
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
    },
  )
  |> ignore
  c.clicked(id)
}

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
let first_seen : Map[Int, Double] = {}

///|
/// Since when `key` has been waited on (the first frame that asked).
fn waited(c : @ui.Ctx, key : String) -> Double {
  let id = c.id("sf-wait/" + key)
  match first_seen.get(id) {
    Some(t) => c.now() - t
    None => {
      first_seen[id] = c.now()
      0.0
    }
  }
}

///|
/// Forgets a wait, so the next one on `key` waits its 400ms again.
pub fn done_waiting(c : @ui.Ctx, key : String) -> Unit {
  first_seen.remove(c.id("sf-wait/" + key))
}

///|
/// The placeholders' breath: 1 → 0.5 → 1 in 1.4s, eased; still (1) for
/// screenshots, 0.6 when what they wait on failed.
pub fn breath(c : @ui.Ctx, failed? : Bool = false) -> Double {
  if failed {
    return 0.6
  }
  if c.stable() {
    return 1.0
  }
  c.request_frame()
  let pi = 3.141592653589793
  let k = c.now() / 1400.0
  let f = k - k.floor()
  // ease-in-out between the two ends
  0.75 + 0.25 * @math.cos(2.0 * pi * f)
}

///|
/// A placeholder bar (a title's, a line's, a picture's): the neutral grey,
/// round.
pub fn bar(
  c : @ui.Ctx,
  w : @ui.Size,
  h : Double,
  radius? : Double = -1.0,
) -> Unit {
  let t = theme()
  c.box(
    w~,
    h=Px(h),
    bg=t.p.neutral_bg,
    radius=if radius >= 0.0 { radius } else { h / 2.0 },
    fn() {  },
  )
  |> ignore
}

///|
/// What could not be read, over the shapes (WaitPill): a pill, red when it
/// failed; the others only after later_ms.
pub fn wait_pill(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && waited(c, "pill/" + key + text) < later_ms {
    c.request_frame()
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
/// A small part still on its way (WaitLine): a 12 spinner and grey words
/// after later_ms; red words and no spinner when it failed.
pub fn wait_line(c : @ui.Ctx, text : String, key? : String = "", error? : Bool = false) -> Unit {
  let t = theme()
  if !error && waited(c, "line/" + key + text) < later_ms {
    c.request_frame()
    c.box(h=Px(18.0), fn() {  }) |> ignore
    return
  }
  c.box(dir=Row, gap=8.0, align=ACenter, fn() {
    if !error {
      spinner(c, size=12.0) |> ignore
    }
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
/// How much of something with a size has come (Progress): a 3 high pill on
/// 18% of the accent; `part` None when the whole is not known, a 40% piece
/// sweeping across.
pub fn progress(c : @ui.Ctx, part : Double?, w? : @ui.Size = Fill(1.0), color? : Int64) -> Unit {
  let t = theme()
  let accent = color.unwrap_or(t.p.accent)
  c.box(
    dir=Row,
    w~,
    h=Px(3.0),
    bg=alpha(accent, 0.18),
    radius=1.5,
    clip=true,
    fn() {
      match part {
        Some(k) => {
          let k = if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k }
          if k > 0.0 {
            c.box(w=Fill(k), h=Px(3.0), bg=accent, radius=1.5, fn() {  })
            |> ignore
          }
          if k < 1.0 {
            c.box(w=Fill(1.0 - k), fn() {  }) |> ignore
          }
        }
        None => {
          // the box's width is known only at layout: sweep in shares of it
          let f = if c.stable() {
            0.3
          } else {
            c.request_frame()
            let k = c.now() / 1400.0
            let x = k - k.floor()
            // ease-in-out there and back, as the keyframes
            let e = 0.5 - 0.5 * @math.cos(3.141592653589793 * x)
            e
          }
          // the 40% piece from -100% of itself to 250%: its start from -0.4
          // to 1.0 of the track
          let start = -0.4 + 1.4 * f
          if start > 0.0 {
            c.box(w=Fill(start), fn() {  }) |> ignore
          }
          let shown = if start < 0.0 { 0.4 + start } else { 0.4 }
          c.box(w=Fill(shown), h=Px(3.0), bg=accent, radius=1.5, fn() {  })
          |> ignore
          let rest = 1.0 - (if start > 0.0 { start } else { 0.0 }) - shown
          if rest > 0.0 {
            c.box(w=Fill(rest), fn() {  }) |> ignore
          }
        }
      }
    },
  )
  |> ignore
}

///|
/// A setting along a hairline with a knob (Reader.css.ts slider): the line
/// 2 high on 16% of the ink, the part up to the knob in the accent, the knob
/// 16 with a ring of the ground round it; dragged or tapped along. Returns
/// the value, snapped to `step`.
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
  let ink = ink.unwrap_or(t.p.text)
  let accent = accent.unwrap_or(t.p.accent)
  let ground = ground.unwrap_or(t.p.canvas)
  let id = c.id(key)
  let edge = 11.0
  let mut v = value
  let (px, _, down) = c.pointer()
  if down && c.pressed(id) {
    match c.rect_of(id) {
      Some((x, _, w, _)) if w > 2.0 * edge => {
        let f = (px - x - edge) / (w - 2.0 * edge)
        let f = if f < 0.0 { 0.0 } else if f > 1.0 { 1.0 } else { f }
        v = min + f * (max - min)
        if step > 0.0 {
          v = min + ((v - min) / step).round() * step
        }
      }
      _ => ()
    }
  }
  let f = if max > min { (v - min) / (max - min) } else { 0.0 }
  let f = if f < 0.0 { 0.0 } else if f > 1.0 { 1.0 } else { f }
  let held = c.pressed(id)
  c.box(w=Fill(1.0), h=Px(28.0), justify=JCenter, id~, fn() {
    c.box(dir=Row, padx=edge, h=Px(2.0), fn() {
      if f > 0.0 {
        c.box(w=Fill(f), h=Px(2.0), bg=accent, fn() {  }) |> ignore
      }
      if f < 1.0 {
        c.box(w=Fill(1.0 - f), h=Px(2.0), bg=alpha(ink, 0.16), fn() {  })
        |> ignore
      }
    })
    |> ignore
    c.layer(fn() {
      c.box(dir=Row, h=Fill(1.0), align=ACenter, fn() {
        if f > 0.0 {
          c.box(w=Fill(f), fn() {  }) |> ignore
        }
        let k = if held { 26.0 } else { 22.0 }
        c.box(w=Px(22.0), h=Px(22.0), align=ACenter, justify=JCenter, fn() {
          c.box(
            w=Px(k),
            h=Px(k),
            bg=accent,
            radius=k / 2.0,
            border=3.0,
            border_color=ground,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
        if f < 1.0 {
          c.box(w=Fill(1.0 - f), fn() {  }) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  v
}
