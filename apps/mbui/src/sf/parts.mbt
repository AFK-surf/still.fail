// still.fail's parts (web/ui parts.tsx, styles/controls.css.ts, page.css.ts,
// waiting.tsx), drawn with mbui: buttons, icon buttons, chips, a segmented
// choice, small panels and their rows, page heads and cards, and the three
// ways of waiting.

///|
/// A control answering (--dur on the ease-out, dur_ms: global.css.ts's buttons' background): a hover's or a press's
/// ground coming and going, a button's that can be pressed or not; how far it is on (0 … 1).
pub fn ease_to(c : @ui.Ctx, key : String, on : Bool) -> Double {
  @motion.animate(c, key, if on { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out))
}

///|
/// For parts whose own parameter is called `icon`.
fn draw_icon(c : @ui.Ctx, name : String, size : Double, color : Int64, by_ink? : Bool = false) -> Unit {
  // (a runtime's mark by its runtime, `runtime:<runtime>`: its maker's, as maker_mark draws it)
  if name.has_prefix("runtime:") {
    maker_mark(c, "", name.view(start_offset=8).to_string(), size) |> ignore
  } else {
    icon(c, name, size~, color~, by_ink~) |> ignore
  }
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
/// narrow, as tall as a bar's tools among them (viewer_bar's: 32); an icon before its words if given, a spinner in its
/// place while `busy`; `reach`, where it stands in a card's foot corners: how its ground reaches past the card's words
/// (foot_across); `hint`, what pressing it does in more words, over it while it is pointed at (a Button in a Tip). True
/// on the frame after it was pressed.
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
  hint? : String = "",
) -> Bool {
  let t = theme()
  let p = t.p
  let id = c.id(if key == "" { "sf-btn/" + label } else { key })
  let live = !disabled && !busy
  let h = ease_to(c, "sf-btn-h/\{id}", live && (c.lit(id) || c.pressed(id)))
  // (turning and greyed as a control answers: over dur_ms, never at once. With an icon, the spinner in its place, the
  // icon fading out under it as it fades in, nothing moved; with none, the spinner coming in before its words, which
  // stay: they are what it does, said on as it does it. At work is not greyed: it is the button pressed, at full
  // strength, its spinner what to look at (2026-10-31 the user: 从不带 loading 到带 loading……感觉有点不对, 能不能不换掉字;
  // it faded to 0.7 as the web's aria-busy does, its icon swapped at once, its words faded out under the spinner).)
  let turning = ease_to(c, "sf-btn-busy/\{id}", busy)
  let seen = @motion.animate(
    c,
    "sf-btn-seen/\{id}",
    if disabled {
      0.45
    } else {
      1.0
    },
    spec=@motion.tween(dur_ms, ease=Out),
  )
  let (ground, line, ink) = if on_night.val {
    // (on a stage: the night under it whatever the theme)
    match tone {
      Primary | DangerSolid => (mix(0xFFFFFFFFL, h, share_ink), 0L, share_ground)
      _ => (mix(stage_plain_lit, h, stage_plain), 0L, share_ink)
    }
  } else {
    // the phone's (Parts.kt): the ink with the paper's words, the chip's ground, no outline; pointed at or pressed, a
    // solid ground a step towards the page and a quiet one the hover's step darker (docs/ui-panels.md 悬停)
    match tone {
      Primary => {
        let g = mix(p.primary_hover, h, p.primary)
        (g, g, p.bg)
      }
      // (white on the light theme's deep red, the page's ink on the dark one's light red: white was 2.4 to 1 there)
      DangerSolid => {
        let g = mix(mix(p.red, 0.85, p.canvas), h, p.red)
        (g, g, if t.dark { p.bg } else { 0xFFFFFFFFL })
      }
      Danger => {
        let g = over(p.chip, alpha(p.hover, h))
        (g, g, p.red)
      }
      Ghost => (alpha(p.hover, h), 0L, p.text)
      GhostDanger => (alpha(p.hover, h), 0L, p.red)
      Plain => {
        let g = over(p.chip, alpha(p.hover, h))
        (g, g, p.text)
      }
    }
  }
  // (among the tools of a bar across the top: level with them and the window's buttons)
  let height = if tools_across.val { viewer_tool_h } else { button_height() }
  let solid = tone == Primary || tone == DangerSolid
  // (at a sheet's foot, in a thumb's reach: its share of the foot's width, the presenters')
  let w = if w is Auto && foot_fills.val { @ui.Fill(1.0) } else { w }
  // (one of words alone at a row's end: its words where the row's value would end, its ground reaching past them)
  let reach = match reach {
    None if (tone == Ghost || tone == GhostDanger) && at_row_end() => Some(outset_end(button_padx))
    r => r
  }
  // (its words' node, as built: how they move with it)
  let mut words_at = -1
  let b = c.box(
    style=reach.unwrap_or(@ui.style()),
    dir=Row,
    w~,
    h=Px(height),
    padx=button_padx,
    gap=if t.touch { 8.0 } else { 6.0 },
    align=ACenter,
    justify=JCenter,
    bg=ground,
    radius=height / 2.0,
    border=if line != 0L && line != ground { 1.0 } else { 0.0 },
    border_color=line,
    opacity=seen,
    id=if live { id } else { 0 },
    fn() {
      let turn = fn() {
        spinner(
          c,
          size=button_icon,
          ring=if solid { alpha(ink, 0.3) } else { p.line_strong },
          arc=if solid { ink } else { p.accent },
        )
        |> ignore
      }
      let gap = if t.touch { 8.0 } else { 6.0 }
      if icon != "" {
        c.box(fn() {
          // (by its ink: as far in from the end as the words are from the other, the grid's room round its strokes
          // taking none, so the two ends look alike)
          let drawn = c.box(fn() { draw_icon(c, icon, button_icon, ink, by_ink=true) })
          // (the spinner over it, in its place and its size: the icon's room kept, nothing beside it moved)
          if turning > 0.0 {
            c.look(drawn, @ui.look(alpha=1.0 - turning))
            c.layer(fn() {
              let s = c.box(style=button_turning, turn)
              c.look(s, @ui.look(alpha=turning))
            })
            |> ignore
          }
        })
        |> ignore
      }
      let words_in = fn() {
        let words = c.text(
          label,
          size=t.t.ui,
          weight=if t.touch { 600 } else { 500 },
          color=ink,
          wrap=false,
          line=t.t.ui_line,
        )
        words_at = words
      }
      if icon == "" {
        // (the spinner's room opening before its words, the button wider by it as its ends keep their room, on the
        // curve a thing reshaped is moved by, all beside it moved along; the spinner growing from its start as the room
        // opens: never out of the ground, never over the words. Kept as wide, its ends came to 4, 2026-10-31 the user:
        // 太贴边了.)
        let over = @motion.animate(c, "sf-btn-over/\{id}", if busy { 1.0 } else { 0.0 }, spec=button_reshape)
        let room = button_icon + gap
        c.box(style=button_spun, fn() {
          if busy || over > 0.0 {
            c.box(style=@ui.style(row=true, w=Fixed(room * over), h=Fixed(button_icon)), fn() {
              let s = c.box(style=button_spin, fn() { turn() })
              c.look(s, @ui.look(alpha=turning, scale=over, ox=0.0))
            })
            |> ignore
          }
          words_in()
        })
        |> ignore
      } else {
        words_in()
      }
    },
  )
  // its words changed (复制图片 to 已复制): its ground goes from the width it had to the new one, its words with it, on
  // the curve a thing reshaped is moved by, not at once (the user, 2026-10-30: 按钮的变长应该也有过渡; their cause,
  // its words: docs/motion.md 3)
  if key != "" {
    @motion.reshape(c, b, "sf-btn/shape/" + key, by=label, spec=button_reshape)
    @motion.layout(c, words_at, "sf-btn/words/" + key, by=label, spec=button_reshape)
  }
  // (in a page's bones, one piece where it has a ground; one of words alone, its words)
  if tone != Ghost && tone != GhostDanger {
    c.bone_whole(b)
  }
  // (said a button whether it takes presses or not: one that cannot is said disabled, not left out of the tree, and its
  // faded words are asked no contrast)
  c.semantics(b, Button, id=if live { id } else { 0 }, label~, disabled=!live)
  if live {
    tip(c, "sf-btn/" + key + label + "/tip", id, hint)
  }
  live && c.clicked(id)
}

///|
/// How a button whose words changed goes to its new width (button): a Move as long as its width changes.
let button_reshape : @motion.Spec = @motion.move()

///|
/// How far a button's words are in from its sides.
let button_padx : Double = 16.0

///|
/// How big a button's icon is.
let button_icon : Double = 16.0

///|
/// Where a button with no icon turns while busy: over its words, in the middle (button).
// kept across runs: a value (no field of it changes)
let button_turning : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// A button's spinner and its words, with no icon (button): in a row, the spinner's room opening before the words.
let button_spun : @ui.Style = @ui.css("row align=ACenter")

///|
/// Where a button's spinner turns (button): an icon's square.
let button_spin : @ui.Style = @ui.style(w=Fixed(button_icon), h=Fixed(button_icon))

///|
/// Whether a button laid out now is at a sheet's foot (the presenters' sheet_body says so while it draws one): each
/// of its buttons as wide as the others, across the sheet (the phone's sheets' primary button, Button in mPad).
let foot_fills : Ref[Bool] = { val: false }

///|
/// Whether a button is drawn on the night whatever the theme (a stage's foot: presenters' stage_centred), in its
/// colours.
// kept across runs: set only while a stage's foot is built, and put back
let on_night : Ref[Bool] = { val: false }

///|
/// A button's height: 34 on every screen with either native input, as keyboard and mouse's rows are (the user,
/// 2026-10-31: a finger's 44 「太大了」「我们现在发送按钮也没那么大」「按钮既然缩，那就跟大屏一致呗」「我们本就大屏小屏都支持
/// 触控」: drawn 44, one in a card's foot corners stood 4 from its edges); its press reaching the 44 every press has.
pub fn button_height() -> Double {
  menu_row_min
}

///|
/// An icon button's side (iconBtn's 32), with a finger too: what stands among a bar's icon buttons is as high.
pub let icon_button_side : Double = 32.0

///|
/// An icon button (page.css.ts iconBtn, parts.tsx IconButton): `size` square (32), its corner 12 (`corner`: the
/// ladder's step where it stands, a card's text inset in its corner the small block's 10; `round`: a circle, where it
/// stands in a pane's corner, concentric with it; `linked`: its corner where that comes from, a bar's buttons' at the
/// window's corner: @sf.bar_keys_link), the icon (16) quiet until pointed at (`lit`: so as what points at it is told
/// from outside, the host's: the window's maximize button the app draws, window_keys); `on` held down
/// (aria-pressed); named for a screen reader and said in its tip with its keys (`shortcut`, an action's).
/// `ink` and `quiet` for one over a ground of its own (the reader's paper).
pub fn icon_button(
  c : @ui.Ctx,
  icon : String,
  key? : String = "",
  size? : Double = icon_button_side,
  icon_size? : Double = 16.0,
  on? : Bool = false,
  lit? : Bool = false,
  round? : Bool = false,
  corner? : Double = r_field,
  linked? : @ui.CornerOf,
  ink? : Int64,
  quiet? : Int64,
  disabled? : Bool = false,
  label? : String = "",
  shortcut? : String = "",
) -> Bool {
  let t = theme()
  // (drawn its own size with a finger too: a finger reaches it from round it, mbui's press_reach)
  let ink = ink.unwrap_or(t.p.text)
  let quiet = quiet.unwrap_or(t.p.muted)
  let id = c.id(if key == "" { "sf-ib/" + icon } else { key })
  let h = ease_to(c, "sf-ib-h/\{id}", !disabled && (lit || c.lit(id) || c.pressed(id)))
  let ground = if on {
    alpha(ink, 0.08)
  } else {
    // the page's hover, as a tint of the ink it sits with
    alpha(ink, 0.065 * h)
  }
  let corner : @ui.Radius = match linked {
    Some(link) => Linked(link)
    None => rounded(if round { size / 2.0 } else { corner })
  }
  let b = c.box(
    style=@ui.style(radius=corner),
    w=Px(size),
    h=Px(size),
    align=ACenter,
    justify=JCenter,
    bg=ground,
    opacity=if disabled { 0.35 } else { 1.0 },
    id=if disabled { 0 } else { id },
    fn() {
      draw_icon(c, icon, icon_size, if on || h > 0.5 { ink } else { quiet })
    },
  )
  // named (IconButton's label): what a screen reader calls it, and its tip
  if label != "" {
    c.semantics(b, Button, id~, label~, disabled~)
    tip(c, "ib/" + key + icon, id, label, shortcut~)
  }
  !disabled && c.clicked(id)
}

///|
/// A chip (the reader's bars, Reader.css.ts chip): 30 high, its corner 10 (`inner`: in a rounded surface's corner,
/// concentric with it), on a 7% tint of the ink, 12% under the pointer; its words small. One with an icon alone named
/// `said` (its aria-label), and in its tip.
pub fn chip(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  ink? : Int64,
  disabled? : Bool = false,
  inner? : Bool = false,
  said? : String = "",
) -> Bool {
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let id = c.id(if key == "" { "sf-chip/" + label + icon } else { key })
  let h = ease_to(c, "sf-chip-h/\{id}", !disabled && c.lit(id))
  let b = c.box(
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
  c.bone_whole(b)
  if said != "" {
    c.semantics(b, Button, id=if disabled { 0 } else { id }, label=said, disabled~)
    if !disabled {
      tip(c, "sf-chip/" + key + "/tip", id, said)
    }
  }
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
/// In a bar (`bar`): its track 2 round its options, as a bar's other tracks (Seg's), and an option's words 10 in from
/// its sides (seg_option's px=S2_5).
let segmented_bar_pad : Double = @ui.Space::px(S0_5)

///|
let segmented_bar_in : Double = @ui.Space::px(S2_5)

///|
/// Its options in a line, 2 apart.
// kept across runs: a value (no field of it changes)
let segmented_strip : @ui.Style = @ui.css("row gap=S0_5")

///|
/// A choice of a few (Segmented; the kit's sliding toggle group): a quiet pill track, the chosen lifted out of it (the
/// theme's lifted) and sliding to it; its options equal columns, as wide as the widest in the chosen weight with 12 either side
/// (segmented, segmentedOption, segmentedSizer), `item_w` at least, the track never wider than where it is. Where those
/// columns need more room than there is, the track takes what there is and its options share it as option_widths has
/// them: as alike as their words let them, their sides narrower, else their words smaller alike (to the system's own
/// size of words), else the chosen one alone in the track, the others in a pick (choice_pick). Always one line, each
/// one's words whole: nothing wrapped, cut or scrolled. `icons`: each option its icon in place of its words (its
/// label its tip and what a screen reader says), as wide as a press's room. `bar`: among a bar's buttons, as high as
/// they are and round as they are, on every page. `said`: what a screen reader calls it. `tips`: what each option says
/// on hover besides its words ("" nothing; a model's speed what Fast costs). `fill`: as a narrow page's is, as wide as
/// where it is, each option an equal share (choices one under another, their tracks' ends lined up). Returns the
/// chosen index.
pub fn segmented(
  c : @ui.Ctx,
  key : String,
  labels : Array[String],
  chosen : Int,
  item_w? : Double = 0.0,
  ink? : Int64,
  thumb? : Int64,
  icons? : Array[String] = [],
  bar? : Bool = false,
  said? : String = "",
  tips? : Array[String] = [],
  fill? : Bool = false,
) -> Int {
  // (a narrow page's: as wide as where it is, each option an equal share, Seg's look (seg.mbt), but at a head's end
  // (head_end), as wide as its options beside the title; a wide page's: the web's Segmented, as wide as its options,
  // its track round them alone; in a bar or of icons, the wide page's, round as a bar's buttons)
  if (look() is Narrow || fill) && !bar && icons.is_empty() {
    if at_head_end() && !fill {
      // (as wide as its options where its line has the room, as narrow as the chosen one with the chevron where it has
      // less: filling what that leaves it)
      let (whole, least) = seg_room(c, labels)
      let mut now = chosen
      c.box(style=@ui.style(w=Fixed(whole), min_w=Fixed(least)), fn() {
        now = seg(c, key, labels, chosen, fill=true, height=segmented_narrow_h)
      })
      |> ignore
      return now
    }
    let now = seg(c, key, labels, chosen, fill=true, height=segmented_narrow_h)
    segmented_tips(c, key, tips)
    return now
  }
  let t = theme()
  let ink = ink.unwrap_or(t.p.text)
  let thumb = thumb.unwrap_or(c.theme().lifted)
  // its words as drawn (the system's size of words applied), in the chosen weight (as wide unchosen as chosen: no
  // column changes as the choice does)
  // (in a bar, as its buttons are: as high as they are, its track 2 round its options, the bar's smaller words, each
  // option as wide as its own: a bar's room is short)
  let words_size = if bar { t.t.meta } else { t.t.ui }
  let size = c.sp(words_size)
  let pad = if bar { segmented_bar_pad } else { segmented_pad }
  let side = if bar { segmented_bar_in } else { segmented_in }
  let high = if bar { icon_button_side - 2.0 * pad } else { segmented_h }
  let corner = if bar { high / 2.0 } else { segmented_corner }
  let n = labels.length()
  let cols = if icons.is_empty() {
    let words = labels.map(fn(l) { choice_words_w(c, l, size, weight=500) + 2.0 * side })
    if bar {
      words.map(fn(w) { dmax(item_w, w) })
    } else {
      Array::make(n, dmax(item_w, words.fold(init=0.0, fn(m, w) { dmax(m, w) })))
    }
  } else {
    // (an icon each: square, as wide as a press's room with the gap beside it)
    Array::make(n, dmax(item_w, dmax(high, @ui.room_least() - segmented_gap)))
  }
  let gaps = segmented_gap * (n - 1).to_double()
  let whole = cols.fold(init=0.0, fn(s, w) { s + w }) + gaps + 2.0 * pad
  // the room the track had as last laid out (cut to where it is: read back, built again in the frame it is laid out
  // otherwise): less than its columns need, its options give way from them to what option_widths has them in it
  // (their columns as wide where the room is, the track then laid out as wide as they need)
  let track = c.id(key + "/track")
  let fit = match c.laid_size(track) {
    // (in a bar, or of icons, never: a bar gives what it has not the room for to its ⋯, not squeezed)
    Some((w, _)) if w < whole - 0.5 && !bar && icons.is_empty() =>
      Some(fitted(c, labels, w - 2.0 * pad - gaps, words_size, 500, side, segmented_least))
    _ => None
  }
  // its track: round its options (as wide as they are, cut to where it is), or round the chosen one where they do not
  // fit side by side (as wide as where it is)
  let track_box = fn(wide : Bool, inner : () -> Unit) -> Int {
    c.box(
      style=if wide {
        segmented_track_wide
      } else if bar || !icons.is_empty() {
        segmented_track_whole
      } else {
        segmented_track
      },
      id=track,
      pad~,
      bg=alpha(ink, 0.06),
      radius=corner + pad,
      inner,
    )
  }
  // an option: its words in its middle, in the chosen weight and the ink where chosen (`on`), in the ink pointed at
  // (`lit`); short of room, their least in from its sides
  // (with icons, its icon in their place)
  let option = fn(label : String, on : Bool, lit : Bool) {
    c.box(h=Px(high), padx?=fit.map(fn(_) { segmented_least }), align=ACenter, justify=JCenter, fn() {
      match labels.search(label).bind(fn(i) { icons.get(i) }) {
        Some(name) => icon(c, name, color=if on || lit { ink } else { t.p.muted }) |> ignore
        None =>
          c.text(
            label,
            size=words_size,
            weight=if on { 500 } else { 400 },
            color=if on || lit { ink } else { t.p.muted },
            wrap=false,
          )
          |> ignore
      }
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
      label=said,
      widths=match fit {
        Some(f) => f.widths.mapi(fn(i, w) { (cols[i], w) })
        None => cols.map(fn(w) { (w, w) })
      },
      look=fn(_, s) { option(s.label, s.on, s.hovered) },
      thumb=fn(c, w, h) {
        c.box(
          w=Px(w),
          h=Px(h),
          bg=thumb,
          radius=corner,
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
  // (icons: each one's words its tip; else what `tips` gives one)
  segmented_tips(c, key, if icons.is_empty() { tips } else { labels })
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(chosen)
    _ => chosen
  }
}

///|
/// What each of segmented `key`'s options says on hover (`said`, by its place; "" nothing).
fn segmented_tips(c : @ui.Ctx, key : String, said : Array[String]) -> Unit {
  let group = c.id(key)
  for i, words in said {
    if words != "" {
      tip(c, key + "/" + i.to_string(), @kit.part_id(group, i), words)
    }
  }
}

///|
/// How wide each of `n` options is for a segmented choice's track to be `room` across (its `item_w`): one that spans
/// the row it heads, as the field under it does (a chat's things').
pub fn segmented_item_w(room : Double, n : Int) -> Double {
  if n <= 0 {
    return 0.0
  }
  (room - 2.0 * segmented_pad - segmented_gap * (n - 1).to_double()) / n.to_double()
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
/// In a bar, or of icons: as wide as its options, never cut (what has not the room goes into the bar's ⋯).
// kept across runs: a value (no field of it changes)
let segmented_track_whole : @ui.Style = @ui.css("row")

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
/// A narrow page's (Seg filling, as the web's narrow pages' mSeg): 34 high.
let segmented_narrow_h : Double = 34.0

///|
/// How high a segmented control stands where it is drawn now (segmented: a narrow page's 34, a wide page's track round
/// its options, 36).
pub fn segmented_height() -> Double {
  if look() is Narrow {
    segmented_narrow_h
  } else {
    segmented_h + 2.0 * segmented_pad
  }
}

///|
let segmented_corner : Double = 15.0

///|
/// A line to type in as a look for mbui's field (@kit.text_field) where its words are set apart (a sheet's, a dialog's):
/// a one-line field's, `input`'s (a capsule as tall as the theme's controls), one frame for every line to type in (the
/// user, 2026-10-29: fields 37, 41 and 44 high, 12, 18 and 22 round, side by side).
pub fn field_look(c : @ui.Ctx, s : @kit.FieldState, editor : () -> Unit) -> Unit {
  let look = if s.hovered || s.focused { input_box_hot } else { input_box }
  c.box(id=s.id, style=look.then(control_height()).then(field_corner()), editor) |> ignore
}

// ---------------------------------------------------------------------------
// Small panels (docs/ui-panels.md)

///|
/// A small panel's ground (controls.css.ts popover): the canvas (the raised
/// grey in dark), a line round it, its shadow; padded panel_pad, its corner
/// the menu's. `min_w`: as wide as what it holds, at least that (a menu's,
/// controls.css.ts menuList); `max_w`: at most that.
pub fn small_panel(
  c : @ui.Ctx,
  w? : @ui.Size = Auto,
  h? : @ui.Size = Auto,
  min_w? : Double,
  max_w? : Double,
  body : () -> Unit,
) -> Int {
  let t = theme()
  c.box(
    w~,
    h~,
    min_w?,
    max_w?,
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
/// A small panel's look beside what opened it (@kit.popover's, @kit.hover_card's), `w` wide: what it holds kept within
/// the room the panel has (@kit.in_room: scrolling out to its sides past the window's height, and past `most`), in
/// `inner` where said (its own room round what it holds and between).
pub fn beside_look(
  w : @ui.Size,
  inner? : @ui.Style,
  most? : Double = 1.0e9,
) -> (@ui.Ctx, @kit.PopState, () -> Unit) -> Unit {
  fn(c, s, body) {
    small_panel(c, w~, fn() { within_room(c, s, body, inner?, most~) }) |> ignore
  }
}

///|
/// What a small panel beside what opened it (`s`, as its look is given it) holds, kept within the room it has
/// (beside_look's), in `inner` where said.
pub fn within_room(c : @ui.Ctx, s : @kit.PopState, body : () -> Unit, inner? : @ui.Style, most? : Double = 1.0e9) -> Unit {
  @kit.in_room(c, s, most~, reach=held_reach(), style=held_in(), fn() {
    match inner {
      Some(st) => c.box(style=st, body) |> ignore
      None => body()
    }
  })
  |> ignore
}

///|
/// A row of a small panel (menuItem): at its padding, words text_in in, its
/// ground under the pointer, concentric with the panel. `panel`: a panel's
/// row (parts.tsx PanelRow): its icon 18 in a column 20 wide, 10 from its words, `end` an icon at its
/// end, quiet. `note`: what it is at now (a word or two) at its end; `under`: what it is, a line under its words.
pub fn menu_item(
  c : @ui.Ctx,
  label : String,
  key? : String = "",
  icon? : String = "",
  mark? : (@ui.Ctx, Double) -> Unit,
  danger? : Bool = false,
  on? : Bool = false,
  note? : String = "",
  under? : String = "",
  panel? : Bool = false,
  end? : String = "",
  at_top? : Bool = false,
  at_foot? : Bool = false,
) -> Bool {
  let t = theme()
  let id = c.id(if key == "" { "sf-mi/" + label } else { key })
  let ink = if danger { t.p.red } else if on { t.p.accent_text } else { t.p.text }
  // (a capsule in the panel's corners: past its padding to where it is concentric with them, at its sides, and at its
  // top or foot where it is the first (`at_top`) or the last (`at_foot`) in it: menu_row_reach)
  let reach = menu_row_reach(t.rows.pick)
  let (over, under_by) = ends_reach(reach, at_top, at_foot)
  c.box(
    dir=Row,
    min_h=t.rows.pick,
    mx=-reach,
    mt=over,
    mb=under_by,
    padx=text_in + reach,
    pady=menu_row_over,
    gap=if panel { panel_row_gap } else { menu_row_gap },
    align=ACenter,
    bg=if c.lit(id) { t.p.hover } else { 0L },
    radius=small_panel_inner(r_menu),
    id~,
    fn() {
      let paneled = panel && (icon != "" || mark is Some(_))
      let leads = fn() {
        if paneled {
          c.box(style=panel_row_icon, fn() {
            match mark {
              Some(m) => m(c, panel_icon)
              None => draw_icon(c, icon, panel_icon, t.p.muted)
            }
          })
          |> ignore
        } else if icon != "" {
          draw_icon(c, icon, menu_item_icon, if danger { t.p.red } else { t.p.muted })
        }
      }
      let first = fn() {
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
      }
      if under == "" {
        leads()
        first()
      } else {
        // what it is under its words, what leads it by its first line (lead_by_first_line)
        let lead_w = if paneled { panel_icon_col } else if icon != "" { menu_item_icon } else { 0.0 }
        lead_by_first_line(c, lead_w, if panel { panel_row_gap } else { menu_row_gap }, leads, first, fn() {
          c.text(under, style=menu_note) |> ignore
        })
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
/// A menu item's icon, out of a panel's column (16).
let menu_item_icon : Double = 16.0

///|
/// A panel row's icon's column's width (panel_row_icon's S5).
let panel_icon_col : Double = 20.0

///|
/// A panel row's icon's column (parts.css.ts panelRowIcon): 20 wide, the icon in its middle.
// kept across runs: a value (no field of it changes)
let panel_row_icon : @ui.Style = @ui.css("w=S5 align=ACenter")

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
      if look() == Narrow {
        // a narrow page's place title (the phone's): display size
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
/// button in its foot corner stands there itself (foot_reach), its corner the card's whatever is in it; `ground` other
/// than the theme's card (over a picture: a player's).
pub fn card(c : @ui.Ctx, gap? : Double = 14.0, fill? : Bool = false, ground? : Int64, body : () -> Unit) -> Int {
  let t = theme()
  c.box(pad=card_pad, gap~, bg=ground.unwrap_or(t.p.card), radius=card_corner, w=if fill { card_across } else { Auto }, body)
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
/// What a sheet holds (`body`), laid out as a sheet is on any screen: narrow, as the presenters lay theirs out (its
/// parts read it: look).
pub fn sheet_laid(body : () -> Unit) -> Unit {
  with_look(Narrow, body)
}

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
let tip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=OnPrimary)

///|
// kept across runs: a value (no field of it changes)
let tip_keys : @ui.TextStyle = @ui.text_style(size=Meta, color=OnPrimary, wrap=false)

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
/// A menu's item (controls.css.ts menuItem), as mbui's menus draw it: as high as the screen's at least (Theme::rows
/// pick: 34, a finger's 44), 6 by 10 in, its words (13) after a column 14 wide (`lead`: the menu's items have one, so all their words are on one line) of its icon (muted)
/// or, one of a choice (parts.tsx ChooserItem), its check where it is the one chosen, `gap` from its words; the
/// pointer's or the keyboard's ground on it; one not to be chosen now (its entry disabled: never lit) in the subtle
/// ink (menuItem[data-disabled]). `note`: what it is, a line under its words (a pick's choice's: its icon, its name and
/// that, as a sheet's row has them).
pub fn menu_row(
  c : @ui.Ctx,
  s : @kit.MenuItemState,
  icon_name : String,
  lead : Bool,
  gap : Double,
  end : ((@ui.Ctx, @kit.MenuItemState) -> Unit)?,
  danger? : Bool = false,
  mark? : (@ui.Ctx, Double) -> Unit,
  note? : String = "",
  at_top? : Bool = false,
  at_foot? : Bool = false,
) -> Unit {
  let t = theme()
  let (choice, checked) = match s.entry.kind {
    Choice(on) | Check(on) => (true, on)
    _ => (false, false)
  }
  let off = s.entry.disabled
  let reach = menu_row_reach(t.rows.pick)
  let (over, under_by) = ends_reach(reach, at_top, at_foot)
  c.box(
    dir=Row,
    w=Fill(1.0),
    min_h=t.rows.pick,
    mx=-reach,
    mt=over,
    mb=under_by,
    padx=text_in + reach,
    pady=menu_row_over,
    gap~,
    align=ACenter,
    radius=small_panel_inner(r_menu),
    bg=if s.hot { t.p.hover } else { 0L },
    fn() {
      let leads = fn() {
        if lead {
          c.box(style=menu_check, fn() {
            if choice {
              if checked {
                icon(c, "check", size=14.0, color=t.p.text) |> ignore
              }
            } else if icon_name != "" {
              icon(c, icon_name, size=14.0, color=if danger { if off { t.p.subtle } else { t.p.red } } else { t.p.muted })
              |> ignore
            }
          })
          |> ignore
        }
        // its own mark (a station's, a maker's) after the check, before its words, as wide as the check's column
        match mark {
          Some(m) => c.box(style=menu_check, fn() { m(c, menu_check_w) }) |> ignore
          None => ()
        }
      }
      // (a danger's in red, its icon with it: menuItem[data-danger])
      let words = if off { menu_words_off } else if danger { menu_words_danger } else { menu_words }
      let first = fn() {
        c.text(s.entry.label, style=words) |> ignore
        // what stands at its end (a ＋): pushed there
        match end {
          Some(f) => {
            c.spacer()
            f(c, s)
          }
          None => ()
        }
      }
      if note == "" {
        leads()
        first()
      } else {
        // what it is under its words, what leads it by its first line
        let lead_w = (if lead { menu_check_w + gap } else { 0.0 }) + (if mark is Some(_) { menu_check_w + gap } else { 0.0 })
        lead_by_first_line(c, if lead_w > 0.0 { lead_w - gap } else { 0.0 }, gap, leads, first, fn() {
          c.text(note, style=menu_note) |> ignore
        })
      }
    },
  )
  |> ignore
}

///|
/// What an item is, under its words: the meta size, muted.
// kept across runs: a value (no field of it changes)
let menu_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// A row's words with a line under them (what it is), what leads it (`lead`: its icon, its check, its mark, `lead_w`
/// wide, `gap` from its words) standing by its first line's middle, not the whole's, and what is under it as far in
/// as its first line's words (the user, 2026-10-27: 「图标不要上下居中，跟第一行居中」): every row of a menu, a pick and
/// a sheet so made. `first`: its first line (its words, what is at their end); `under`: the lines under it.
pub fn lead_by_first_line(
  c : @ui.Ctx,
  lead_w : Double,
  gap : Double,
  lead : () -> Unit,
  first : () -> Unit,
  under : () -> Unit,
) -> Unit {
  c.box(style=lead_lines, fn() {
    c.box(style=lead_first_line.then(@ui.style(gap=room(gap))), fn() {
      lead()
      first()
    })
    |> ignore
    c.box(style=@ui.style(pl=room(lead_in(lead_w, gap))), under) |> ignore
  })
  |> ignore
}

///|
/// How far in the lines under a row's first stand: past what leads it and the gap after it, where something does.
fn lead_in(lead_w : Double, gap : Double) -> Double {
  if lead_w > 0.0 {
    lead_w + gap
  } else {
    0.0
  }
}

///|
/// (lead_by_first_line: the lines as wide as the row leaves them; the first a row, its parts by its middle)
let lead_lines : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let lead_first_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// Between an item's icon and its words (menuItem), its check's column and its words in a menu of choices alone
/// (chooserItem).
let menu_gap : Double = 8.0

///|
let chooser_gap : Double = 6.0

///|
/// The column before a menu item's words (controls.css.ts chooserCheck, a menuItem's svg): 14 wide, its icon or check in
/// its middle.
// kept across runs: a value (no field of it changes)
let menu_check : @ui.Style = @ui.css("w=S3_5 align=ACenter")

///|
/// How wide the column before a menu item's words is (menu_check's S3_5).
let menu_check_w : Double = 14.0

///|
/// A menu item's words: as long as they are (the menu as wide as its longest, controls.css.ts menuList).
// kept across runs: a value (no field of it changes)
let menu_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, leading=L5, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_words_danger : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, leading=L5, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let menu_words_off : @ui.TextStyle = @ui.text_style(size=Ui, color=Subtle, leading=L5, wrap=false)

///|
/// A heading among a menu's items (controls.css.ts menuLabel): its words as far in as a row's (text_in) and as far
/// under what is over it as a row's are (menu_row_over: at the panel's top, where its first item's words would be), 4
/// over the items it heads; 12, muted.
// kept across runs: a value (no field of it changes)
let menu_heading : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let menu_heading_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, leading=L4_75, wrap=false)

///|
/// A menu (parts.tsx Menu: mbui's dropdown menu, in the web's look): `entries` with their icons (by value), as wide as
/// its longest and `w` at least (controls.css.ts menuList 180; a menu of choices chooserMenu, 220), `offset` on `side`
/// of `trigger` (under it) lined up `along` it, or at `at`; what was chosen. The arrows, letters, Enter and Escape as a
/// menu's; a press outside closes it. `check_end`: its choices' checks are drawn at their rows' ends (`row_end`:
/// parts.tsx ChooserItem checkEnd), no column of them before their words.
pub fn dropdown(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  trigger : Int,
  entries : Array[@kit.Entry],
  icons : Map[String, String],
  w : Double,
  submenu? : Bool = false,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = 6.0,
  at? : (Double, Double, Double, Double),
  row_end? : (@ui.Ctx, @kit.MenuItemState) -> Unit,
  danger? : Array[String] = [],
  marks? : Map[String, (@ui.Ctx, Double) -> Unit] = {},
  notes? : Map[String, String] = {},
  check_end? : Bool = false,
) -> @kit.Menu {
  // (a column before every item's words where one has an icon or is one of a choice, its check there, so all their
  // words are on one line; a menu of choices alone, each chosen or not, its check 6 from its words)
  let choice = fn(e : @kit.Entry) { e.kind is Choice(_) || e.kind is Check(_) }
  let iconed = entries.iter().any(fn(e) { !choice(e) && icons.get(e.value).unwrap_or("") != "" })
  let lead = iconed || (!check_end && entries.iter().any(choice))
  let gap = if lead && !iconed { chooser_gap } else { menu_gap }
  @kit.dropdown_menu(
    c,
    key,
    open,
    trigger,
    entries,
    submenu~,
    side~,
    along~,
    offset~,
    min_w=w,
    at?,
    look=fn(c, w, body) { small_panel(c, min_w=w, body) |> ignore },
    item_look=fn(c, s) {
      menu_row(
        c,
        s,
        icons.get(s.entry.value).unwrap_or(""),
        lead,
        gap,
        row_end,
        danger=danger.contains(s.entry.value),
        mark?=marks.get(s.entry.value),
        note=notes.get(s.entry.value).unwrap_or(""),
        at_top=entries.length() > 0 && entries[0].value == s.entry.value,
        at_foot=entries.length() > 0 && entries[entries.length() - 1].value == s.entry.value,
      )
    },
    // (a heading's words on its items' words' line: past the column before them, where there is one)
    heading_look=fn(c, label) {
      let past = (if lead { menu_check_w + gap } else { 0.0 }) + (if marks.is_empty() { 0.0 } else { menu_check_w + gap })
      c.box(style=menu_heading.then(@ui.style(pl=room(text_in + past))), fn() { c.text(label, style=menu_heading_words) |> ignore })
      |> ignore
    },
    rule_look=menu_rule,
  )
}

///|
/// A line between parts of a small panel (controls.css.ts menuSep): the words' ink faintly (in dark the panel is
/// lighter than the page: its line a groove), 1 high, 6 over and under it, as wide as its rows' grounds (at the
/// panel's padding), so a row pointed at beside it ends where it does.
pub fn menu_rule(c : @ui.Ctx) -> Unit {
  c.box(style=menu_rule_at, fn() { c.box(style=rule_line.then(@ui.style(bg=Data(rule_ink(c)))), fn() {  }) |> ignore })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let menu_rule_at : @ui.Style = @ui.css("w=Full py=S1_5")

///|
/// What a menu holds (parts.tsx MenuItem): its words, its icon, in red (`danger`: what cannot be undone), not to be
/// chosen now (`disabled`), one of a choice (`chosen`: whether it is the one chosen; a menu with one is a menu of
/// choices, each checked or not in a column before its words: parts.tsx ChooserItem); what choosing it does.
pub(all) struct MenuItem {
  label : String
  icon : String
  danger : Bool
  disabled : Bool
  chosen : Bool?
  heading : Bool
  select : () -> Unit
}

///|
pub fn menu_item_of(
  label : String,
  select : () -> Unit,
  icon? : String = "",
  danger? : Bool = false,
  disabled? : Bool = false,
  chosen? : Bool,
  heading? : Bool = false,
) -> MenuItem {
  { label, icon, danger, disabled, chosen, heading, select }
}

///|
/// The menu open now (one at a time, as Radix's are), by its key, and where a right click opened it.
let menu_open : Ref[String] = Ref("")

///|
let menu_open_at : Ref[(Double, Double)] = Ref((0.0, 0.0))

///|
/// The menus closed and still going out (their exit playing), by their keys: what opened one keeps it built till gone.
let menu_going : Set[String] = Set::new()

///|
/// No menu open, no mark's words (the app begun again).
pub fn parts_reset() -> Unit {
  submenu_hover.val = ""
  held_felt.clear()
  presenters_reset()
  menu_open.val = ""
  about_open.val = ""
  menu_open_at.val = (0.0, 0.0)
  menu_going.clear()
}

///|
/// `items` drawn as a menu (None: a line between), open while `key` is the one open; chosen, closed and what it does
/// done once the frame is built. Whether it is open.
fn menu_items(
  c : @ui.Ctx,
  key : String,
  trigger : Int,
  items : Array[MenuItem?],
  submenu? : Bool = false,
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
        entries.push(
          if item.heading { @kit.menu_label(item.label) } else { match item.chosen {
            Some(on) => @kit.menu_radio(v, on, label=item.label, disabled=item.disabled)
            None => @kit.menu_item(v, label=item.label, disabled=item.disabled)
          } },
        )
        if item.icon != "" {
          icons[v] = item.icon
        }
        if item.danger {
          danger.push(v)
        }
      }
    }
  }
  let m = dropdown(c, key, open, trigger, entries, icons, menu_w, submenu~, side~, along~, offset~, at?, danger~)
  if open && !m.open {
    menu_open.val = ""
  }
  if m.shown && !m.open {
    menu_going.add(key)
  } else {
    menu_going.remove(key)
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
/// A menu behind ⋯ (parts.tsx Menu): an icon button (`label`, the app's word for 更多; shaped as a bar's tools are:
/// tool_button) that opens `items` under it, along its end, 4 below. Whether it is open.
pub fn menu_of(c : @ui.Ctx, key : String, items : Array[MenuItem?], label~ : String, size? : Double = 32.0) -> Bool {
  let open = menu_open.val == key
  if icon_button(c, "more", key=key + "/more", size~, on=open, round=true, linked?=bar_keys_link(), label~) {
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
/// An icon button as a tool (icon_button: `label` its tip, `lit` its ink and quiet, as one that is on; as a bar's
/// buttons are: round on the tape, the last in its panel's corner concentric with it, at a window's corner the corner
/// they share, @sf.bar_keys_link): pressed, `on_press`; gone (the `drop`-th), the ⋯'s line of the same icon and words.
/// `shortcut`: the action whose keys its tip says (tip).
pub fn tool_button(
  c : @ui.Ctx,
  key : String,
  icon : String,
  label : String,
  on_press~ : () -> Unit,
  drop? : Int = 0,
  lit? : Int64,
  disabled? : Bool = false,
  shortcut? : String = "",
) -> Tool {
  {
    key,
    drop,
    draw: fn() {
      if icon_button(c, icon, key~, ink?=lit, quiet?=lit, round=true, linked?=bar_keys_link(), disabled~, label~, shortcut~) {
        on_press()
      }
    },
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
  style? : @ui.Style = tools_line(),
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
/// A row of tools (tools_row): 6 apart, more where a press's room needs it (keys_gap), on a line.
pub fn tools_line() -> @ui.Style {
  tools_line_look.then(@ui.style(gap=keys_gap(least=tools_apart)))
}

///|
// kept across runs: a value (no field of it changes)
let tools_line_look : @ui.Style = @ui.css("row align=ACenter")

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
/// Whether the menu `key` is drawn: open, or closed and still going out. What shows its ⋯ only under the pointer
/// keeps it while this holds, so the menu goes out where it hung (not cut off, nor from the window's corner where
/// the ⋯ is not drawn the frame it plays in).
pub fn menu_shown(key : String) -> Bool {
  menu_open.val == key || menu_going.contains(key)
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
  @kit.switch_look_of(
    w~,
    h~,
    inset=switch_in,
    on_color=t.p.accent,
    off_color=t.p.line_strong,
    knob=0xFFFFFFFFL,
    lens=glass_knob(),
  )
}

///|
/// A switch's size by the screen, the theme's rows' (Rows: a finger's 44 by 26 with touch, the web's 36 by 22 on
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
  let b = c.box(style=switch_at, fn() {
    let look = switch_look_for(small)
    // (pressed within a finger's least round it, however small it is drawn: the room it takes is its press's)
    let reach = fn(c : @ui.Ctx, st : @kit.SwitchState) {
      c.box(style=switch_reach.then(@ui.style(min_h=Fixed(theme().items.least))), fn() { look(c, st) }) |> ignore
    }
    now = @kit.switch(c, key, on, label~, disabled=disabled || busy, look=reach).value
  })
  // (in a page's bones, one piece: on or off is not known yet)
  c.bone_whole(b)
  now
}

///|
// kept across runs: a value (no field of it changes)
let switch_at : @ui.Style = @ui.css("justify=JCenter align=AStart")

///|
/// A switch's press round it: its look in the middle of it, up and down.
// kept across runs: a value (no field of it changes)
let switch_reach : @ui.Style = @ui.css("justify=JCenter")

///|
/// A switch drawn in a row that takes the tap itself (the row turns it): its look alone, its thumb sliding as a
/// switch's does (`@kit.switch_knob` by `key`), held as the row is `pressed`.
pub fn switch_look(c : @ui.Ctx, key : String, on : Bool, small? : Bool = false, pressed? : Bool = false) -> Unit {
  let (w, h) = switch_size(small)
  switch_look_for(small)(c, {
    on,
    t: @kit.switch_knob(c, key, on),
    hovered: false,
    pressed,
    held: @kit.switch_held(c, key, pressed),
    focus_shown: false,
    disabled: false,
  })
}

///|
/// A setting's row (parts.tsx SwitchRow, switchRow): what it is on the left, `note` quieter under it, its switch on the
/// right, 16 apart; its words press the switch too. What it is now. (A page's switch_row, wide: page.mbt.)
fn wide_switch_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  on : Bool,
  note? : String = "",
  disabled? : Bool = false,
  busy? : Bool = false,
  title_style? : @ui.TextStyle = theme().rows.title,
  note_style? : @ui.TextStyle = theme().rows.note,
  lead? : (@ui.Ctx) -> Unit,
) -> Bool {
  let id = c.id(key + "/words")
  let mut now = on
  // (the switch alone answers, not its words: 2026-10-27 用户「只有开关响应」)
  control_row(c, title, fn() { now = switch(c, key, on, label=title, disabled~, busy~) }, note~, title_style~, note_style~, lead?)
  now
}

///|
/// A row's title, with `lead` before it on its line where given (a workspace's mark: workspace_badge), 6 apart.
fn led_title(c : @ui.Ctx, title : String, style : @ui.TextStyle, lead : ((@ui.Ctx) -> Unit)?) -> Unit {
  match lead {
    Some(draw) =>
      c.box(style=led_title_line, fn() {
        draw(c)
        c.text(title, style~) |> ignore
      })
      |> ignore
    None => c.text(title, style~) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let led_title_line : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// A row of a setting (a switch's, a choice's: switch_row, setting): its title with its note under it at its start,
/// taking what the control leaves, `control` at its end across their middle, 16 apart; its words pressed where
/// `words_id` is given (a switch's: they turn it).
fn control_row(
  c : @ui.Ctx,
  title : String,
  control : () -> Unit,
  note? : String = "",
  title_style? : @ui.TextStyle = theme().rows.title,
  note_style? : @ui.TextStyle = theme().rows.note,
  words_id? : Int = 0,
  lead? : (@ui.Ctx) -> Unit,
) -> Unit {
  c.box(style=switch_row_box, fn() {
    c.box(style=switch_row_words, id=words_id, fn() {
      led_title(c, title, title_style, lead)
      if note != "" {
        c.text(note, style=note_style) |> ignore
      }
    })
    |> ignore
    control()
  })
  |> ignore
}

///|
/// One of several to tick (a list a choice of some of: ChatPage.tsx ShareDialog's rows, the phone's PickRow): its box,
/// then what it is (`note` quieter under it), the whole row pressed to tick it or not, its ground lit under the hand. Its
/// room, its words and its box the theme's rows' (Rows: a finger's with touch, a list row's with keyboard and mouse). What
/// it is now. `lead`: what goes before its words, after its box (a workspace's mark: workspace_badge).
pub fn check_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  on : Bool,
  note? : String = "",
  disabled? : Bool = false,
  lead? : (@ui.Ctx) -> Unit,
) -> Bool {
  let id = c.id(key + "/row")
  let mut now = on
  let mut ticked = false
  let r = theme().rows
  c.box(style=check_row_box.then(@ui.style(min_h=Fixed(theme().items.least))), id=if disabled { 0 } else { id }, fn() {
    let look = @kit.checkbox_look_of(size=r.check, radius=r.check_corner)
    let v = @kit.checkbox(c, key, if on { On } else { Off }, label~, disabled~, look~).value
    if (v == On) != on {
      ticked = true
      now = v == On
    }
    match lead {
      Some(draw) => draw(c)
      None => ()
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
/// hand; as high at least, its words and its box as the theme's rows (Rows). Its box stands clear of the row's corners,
/// as far in from its start as the row is round: in the row's middle, as high as both its corners reach, no box of a
/// tick could be concentric with them (keyboard and mouse's 18 in a 40 row: 11 from its top and foot, as round as 9.2 there,
/// a circle), so it stands alone, its own corner.
// kept across runs: a value (no field of it changes)
let check_row_box : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S3 align=ACenter hovered{bg=Hover} pressed{bg=Hover}").then(
  @ui.style(radius=row_radius, pl=room(row_corner)),
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
/// line, 10 over what it holds; 28 under it all. (A page's section, wide: page.mbt.)
fn wide_section(
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
    in_section.val += 1
    body()
    in_section.val -= 1
  })
  |> ignore
}

///|
/// How many wide sections what is drawn is in (wide_section): a page's part in none stands as one of them does
/// (wide_alone).
// kept across runs: counted up and down round a section's body (0 between them)
let in_section : Ref[Int] = Ref(0)

///|
/// A page's part on a wide page standing alone, in no section (a group, a choice, a card of its own): as far from
/// what follows as a section is (section_box's 28), its own room over it the section's under what is over it.
fn wide_alone(c : @ui.Ctx, body : () -> Unit) -> Unit {
  if in_section.val > 0 || in_layers.val > 0 {
    body()
  } else {
    c.box(style=section_box, body) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let section_box : @ui.Style = @ui.css("w=Full mb=S7")

///|
// kept across runs: a value (no field of it changes)
let section_head : @ui.Style = @ui.css("row w=Full justify=JBetween align=ACenter gap=S3").then(
  @ui.style(mb=room(title_card_wide)),
)

///|
// kept across runs: a value (no field of it changes)
let section_words : @ui.Style = @ui.css("w=Grow(1.0)")

///|
// kept across runs: a value (no field of it changes)
let section_title_line : @ui.Style = @ui.css("row gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let section_title : @ui.TextStyle = @ui.text_style(size=Body, leading=L7, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let section_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

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
  let b = c.box(style=pill_box, padx=pill_in, bg=ground, fn() {
    if icon != "" {
      draw_icon(c, icon, pill_icon, ink)
    }
    if words != "" {
      c.text(words, style=pill_words, color=ink) |> ignore
    }
  })
  c.bone_whole(b)
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
pub let step_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg)

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
let step_number_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

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
let verify_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Positive)

///|
// kept across runs: a value (no field of it changes)
let pill_box : @ui.Style = @ui.style(row=true, h=Fixed(pill_h), gap=S1, radius=Full, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let pill_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, wrap=false)

///|
/// How something stands, at a glance (parts.tsx StatusDot, parts.css.ts statusDot): a dot 7 round, online the online
/// green, busy amber, error red, waiting (coming back) the muted ink, else (offline) a ring 1.5 in it. `state`:
/// "online", "busy", "error", "waiting", or anything else for offline (the web's Presence).
pub fn status_dot(c : @ui.Ctx, state : String) -> Unit {
  let p = theme().p
  let (ground, ring) = match state {
    "online" => (p.online, no_ground)
    "busy" => (p.warn_ink, no_ground)
    "error" => (p.red, no_ground)
    // coming back: a grey dot, filled (a ring is away)
    "waiting" => (p.muted, no_ground)
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
let first_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let first_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let first_lead_box : @ui.Style = @ui.style(max_w=first_lead_most, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let first_actions : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter justify=JCenter pt=S3")

// ---------------------------------------------------------------------------
// Dialogs (parts.tsx Dialog; parts.css.ts dialog, dialogHead, dialogLead, dialogBody, dialogFoot, overlay)

///|
/// How tall box `inner` that dialog `key` holds can show at most, in the window as it is now: the dialog as tall as it
/// may be (the window less dialog_room) less what is not its body (its title, what it says, its buttons, its padding)
/// and less what its body holds besides `inner` (its padding over it), as the last layout had them; None before it is
/// laid out. What holds a share of the window (presenters' `tall`) is held to it, all of it in view rather than
/// scrolled in a body taller than the dialog shows.
pub fn dialog_body_most(c : @ui.Ctx, key : String, inner : Int) -> Double? {
  match
    (
      c.laid_size(c.id(key + "/frame")),
      c.laid_size(c.capped_id(key + "/body")),
      c.laid_size(c.id(key + "/held")),
      c.laid_size(inner),
    ) {
    (Some((_, framed)), Some((_, shown)), Some((_, held)), Some((_, laid))) =>
      Some(dmax(0.0, c.height - dialog_room - (framed - shown) - (held - laid)))
    _ => None
  }
}

///|
/// A dialog (parts.tsx Dialog: mbui's, @kit.dialog: the page under it dimmed and taking no press, the focus kept in
/// it, Escape, the back and a press outside closing it) in the web's look: `w` wide (520; `wide` 640), 32 short of the
/// window at most; its corner 42 (its padding 24 and a pill's half height, so a pill in its corner and the close
/// button follow its edge: DIALOG_PAD), a small panel's ground and line, a deep shadow. Its title (22, 600) 25 under
/// its top beside the close button (round, 32: `close_label`, none when ""), `description` 6 under it (13, muted),
/// what `body` holds 18 under that (its parts 16 apart; none of that room where it holds nothing), and `footer`'s
/// buttons at its end 24 under it, 8 apart; what it holds `column_in` in from its padding (a panel's dialog's: on its
/// words' line, panel_centred).
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
  column_in? : Double = 0.0,
) -> Bool {
  let closed = Ref(false)
  let w = w.unwrap_or(if wide { dialog_wide_w } else { dialog_w })
  let d = @kit.dialog(
    c,
    key,
    open,
    title,
    description~,
    w=dmin(w, c.window_size().0 - dialog_margin),
    close_label="",
    look=fn(c, s, inner) {
      c.box(
        style=dialog_box,
        id=c.id(key + "/frame"),
        w=Px(s.w),
        max_h=c.height - dialog_room,
        radius=dialog_r,
        bg=panel_ground(),
        shadow=dialog_shadow,
        shadow_y=dialog_shadow_y,
        shadow_color=theme().p.shadow,
        fn() {
        // (its title and what it says on the line of its words: a panel's dialog's are a row's padding in, words_in_now)
        let words_at = @ui.style(pl=room(words_in_now.val))
        // untitled (what it holds has a head of its own: a chat's sheet, an agent's card): no row of its own, its close
        // button in its top right corner, concentric with it, over what it holds (which keeps clear of it:
        // untitled_clear)
        let untitled = s.title == "" && step == ""
        if untitled && close_label != "" {
          c.layer(fn() {
            c.box(style=dialog_close_row, fn() {
              c.box(style=dialog_close_corner(), fn() {
                if icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=close_label) {
                  closed.val = true
                }
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        }
        if !untitled {
        c.box(style=dialog_head.then(words_at), fn() {
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
          if close_label != "" {
            c.box(style=dialog_close_at(), fn() {
              if icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=close_label) {
                closed.val = true
              }
            })
            |> ignore
          }
        })
        |> ignore
        }
        if s.description != "" {
          c.box(style=dialog_lead_at.then(words_at), fn() { c.text(s.description, style=dialog_lead) |> ignore }) |> ignore
        }
        // what it holds scrolls in itself when the dialog would be taller than the window leaves it (dialogBody's
        // overflow: auto, its minimum 0): its title and its buttons stay. Out to the dialog's sides, what it holds back
        // on its words' line, and with no buttons down to its foot, 24 under what it holds: what reaches out to its
        // corners on purpose (dialog_rows, dialog_foot_rows) is not cut short of them.
        c.capped(key + "/body", c.height, shrinks=true, mx=-dialog_pad, padx=dialog_pad, fn() {
          // (holding nothing this time, none of its room: its title and what it says straight over its buttons)
          // (what it holds `column_in` in from its padding: a panel's dialog's, on its words' line)
          let column = @ui.style(px=room(column_in))
          // (untitled: from its padding's top, its head its own)
          let top = if untitled { dialog_untitled_top } else { no_style }
          c.box(style=(if footer is None { dialog_body_end } else { dialog_body }).then(column).then(top), id=c.id(key + "/held"), gone_empty=true, fn() {
            // (its rows told they are in a dialog: dialog_rows; untitled, its close button over its corner)
            let (was, clear_was) = (in_dialog.val, untitled_clear_now.val)
            in_dialog.val = true
            untitled_clear_now.val = if untitled && close_label != "" { dialog_close_clear() } else { 0.0 }
            inner()
            in_dialog.val = was
            untitled_clear_now.val = clear_was
          })
          |> ignore
        })
        |> ignore
        match footer {
          Some(f) => c.box(style=dialog_foot.then(dialog_corner_foot(dialog_pad)), f) |> ignore
          None => ()
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
/// title's (where it stands alone: dialog_close_at).
// kept across runs: a value (no field of it changes)
let dialog_head : @ui.Style = @ui.style(
  row=true,
  w=Full,
  justify=JBetween,
  align=ACenter,
  gap=S3,
  min_h=Fixed(dialog_close),
  pt=room(dialog_head_over),
  pr=room(dialog_head_end),
)

///|
/// How far its title's row stands under its padding's top, and in from its padding's end.
let dialog_head_over : Double = 1.0

///|
let dialog_head_end : Double = 2.0

///|
/// An untitled dialog's close button (dialog): in its top right corner as far in as makes it concentric with it
/// (capsule_in), from its outer edges (a layer is laid over the whole of the box, its padding too).
fn dialog_close_corner() -> @ui.Style {
  let d = capsule_in(dialog_r, dialog_close)
  @ui.style(mt=room(d), mr=room(d))
}

///|
/// The row an untitled dialog's close button stands at the end of (over what it holds).
// kept across runs: a value (no field of it changes)
let dialog_close_row : @ui.Style = @ui.css("row w=Full justify=JEnd")

///|
/// How far from its padding's end the first row of an untitled dialog keeps clear of its close button (and 8 more).
fn dialog_close_clear() -> Double {
  capsule_in(dialog_r, dialog_close) - dialog_pad + dialog_close + 8.0
}

///|
/// What the first row of what an untitled dialog holds keeps clear of at its end, its close button over it (0 elsewhere).
// kept across runs: said by dialog round what an untitled one holds
let untitled_clear_now : Ref[Double] = { val: 0.0 }

///|
/// The room a head of its own keeps at its end in an untitled dialog, its close button over it there (none elsewhere).
pub fn untitled_clear() -> @ui.Style {
  @ui.style(pr=room(untitled_clear_now.val))
}

///|
/// An untitled dialog's body from its padding's top (no title over it to stand 18 under).
// kept across runs: a value (no field of it changes)
let dialog_untitled_top : @ui.Style = @ui.css("pt=S0")

///|
/// Where its close button stands at its title's row's end: in its top right corner as far in as makes it concentric
/// with it (capsule_in: a mouse's 32 18 in, the ladder's pane corner's own place for it as on the tape's line; a
/// finger's 44, 12), the row as high as with a mouse's (its margins making up the rest, its middle no longer the
/// title's; the user, 2026-10-25: 25 in, by the corner and not with it).
fn dialog_close_at() -> @ui.Style {
  let side = dialog_close
  let d = capsule_in(dialog_r, side)
  let up = d - (dialog_pad + dialog_head_over)
  @ui.style(mt=room(up), mr=room(d - (dialog_pad + dialog_head_end)), mb=room(dialog_close - side - up))
}

///|
// kept across runs: a value (no field of it changes)
let dialog_title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let dialog_lead_at : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let dialog_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted)

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
/// Whether a dialog's body is being drawn (dialog), what its rows reach out by (dialog_rows).
// kept across runs: said by dialog round the body it draws, false between
let in_dialog : Ref[Bool] = { val: false }

///|
/// A list of rows `row_h` high, each pressed as a whole (a station to pick), and each row: in a dialog the rows round as
/// their height, the list out past the dialog's words at its sides and foot to where the last row stands concentric with
/// its foot corners (capsule_in), each row's words back on the words' line; elsewhere (a sheet's, a small panel's) as
/// the list and its rows are. One corner for all of them, the last's in the corners concentric, never that one's alone.
pub fn dialog_rows(row_h : Double) -> (@ui.Style, @ui.Style) {
  if !in_dialog.val {
    return (no_style, no_style)
  }
  // (from its column: its padding, and the room a panel's dialog stands what it holds in from that, column_in_now)
  let out = capsule_in(dialog_r, row_h) - dialog_pad
  let side = out - column_in_now.val
  (@ui.style(mx=room(side), mb=room(out)), @ui.style(radius=Full, px=room(-side)))
}

///|
// kept across runs: a value (no field of it changes)
let no_style : @ui.Style = @ui.css("")

///|
/// With no buttons, its body down to its foot, 24 under what it holds.
// kept across runs: a value (no field of it changes)
let dialog_body_end : @ui.Style = dialog_body.then(@ui.css("pb=S6"))

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
  // (on a wide page not the column's whole width: as wide as what is typed in it needs, rule 5; in a panel, its width)
  let wide_page = look() is Wide && !in_panel()
  c.box(style=if wide_page { field_box_wide } else { field_box }, fn() {
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
/// A field on a wide page: 420 at most (rule 5: what is typed not the column's whole width).
let field_box_wide : @ui.Style = field_box.then(@ui.style(max_w=Fixed(field_wide_most)))

///|
pub let field_wide_most : Double = 420.0

///|
// kept across runs: a value (no field of it changes)
let field_top : @ui.Style = @ui.css("row w=Full justify=JBetween align=AEnd gap=S2")

///|
// kept across runs: a value (no field of it changes)
let field_label : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let field_error : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let field_hint : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
/// A line to type in (controls.css.ts input, a one-line one: a pill as the buttons beside it are, 36 high at least,
/// 16 in, a line of the strong grey, the field's hover grey pointed at or written in, on the canvas, its words 14, the
/// placeholder subtle): mbui's field (@kit.text_field), its editor `key`'s; `field`: what it holds, the view's own;
/// `small`: 34 high (a small panel's, as its rows: input_box_small); `solid`: on a card's ground in a chat (field_solid);
/// `shorter`: other ways to say the placeholder where the field has less room (Ctx::editor's); `leaves`: the keys it
/// leaves to a menu it offers as it is typed in (text_field's). What is in it now, and whether Enter was pressed in it.
pub fn input(
  c : @ui.Ctx,
  key : String,
  placeholder? : String = "",
  shorter? : Array[String] = [],
  secret? : Bool = false,
  disabled? : Bool = false,
  small? : Bool = false,
  solid? : Bool = false,
  leaves? : Array[Int] = [],
  field? : @ui.Field,
) -> @kit.Field {
  // (its words the body's, as tall as the theme's controls: the web's with keyboard and mouse, a finger's with touch)
  let t = theme()
  @kit.text_field(c, key, placeholder~, shorter~, secret~, disabled~, size=t.t.body, line=t.t.body_line, leaves~, field?, look=fn(c, s, editor) {
    let hot = s.hovered || s.focused
    let look = match (small, hot) {
      (false, false) => input_box.then(control_height()).then(field_corner())
      (false, true) => input_box_hot.then(control_height()).then(field_corner())
      (true, false) => input_box_small
      (true, true) => input_box_small_hot
    }
    c.box(
      id=s.id,
      style=if solid {
        look.then(if hot { field_solid_hot } else { field_solid })
      } else {
        look
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
/// A field's corner, one for all of them: half its controls' height (Theme::control_h), so a one-line field is a
/// capsule and lines to type in (textarea) are one grown taller, its corners its ends'.
pub fn field_round() -> Double {
  theme().control_h / 2.0
}

///|
/// A field's corner as a style (field_round).
fn field_corner() -> @ui.Style {
  @ui.style(radius=rounded(field_round()))
}

///|
/// Lines to type in (controls.css.ts input as a textarea): a one-line field grown taller, round as its ends are
/// (field_round, not the web's --r-field: its first line clears that round), its words as far in as its (16) and 8
/// under its top; the strong grey's line, the field's hover grey pointed at or written in, on the canvas; its words 14
/// on lines 1.6 of them, at least
/// `rows` lines high and growing to `most`; `field`: what it holds, the view's own; `corner`, the ladder's where it
/// stands (first in a card, on its words' inset in its corners: the small block's 10); `solid`: on a card's ground in a
/// chat (field_solid). What is in it now.
pub fn textarea(
  c : @ui.Ctx,
  key : String,
  rows? : Int = 3,
  most? : Int = 16,
  placeholder? : String = "",
  field? : @ui.Field,
  corner? : Double,
  solid? : Bool = false,
) -> String {
  let t = theme()
  let box_id = c.id(key + "/frame")
  let hot = c.lit(box_id) || c.has_focus(c.id(key))
  let mut words = ""
  let tall = match corner {
    Some(k) => @ui.style(min_h=Fixed(rows.to_double() * textarea_line + textarea_in), radius=rounded(k))
    // (a field's corner, as a one-line field's ends: field_round)
    None => field_corner().then(@ui.style(min_h=Fixed(rows.to_double() * textarea_line + textarea_in)))
  }
  let look = if hot { textarea_box_hot } else { textarea_box }
  let look = if solid { look.then(if hot { field_solid_hot } else { field_solid }) } else { look }
  c.box(id=box_id, style=look.then(tall), fn() {
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
let textarea_box : @ui.Style = @ui.css("w=Full px=S4 py=S2 bg=Surface border=B1 border_color=Border")

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
/// A field on a card's ground in a chat (a key typed in for an agent's request, as a login's code is: sfpages
/// login_card.mbt lc_paste; MachineLogins.css.ts cardPaste, controls.css.ts inputSolid): solid, the page's own ground,
/// no line of its own; pointed at or written in, the field's hover grey round it as any field's (`_hot`).
// kept across runs: a value (no field of it changes)
let field_solid : @ui.Style = @ui.css("bg=Bg border_color=Bg")

///|
// kept across runs: a value (no field of it changes)
let field_solid_hot : @ui.Style = @ui.css("bg=Bg")

///|
/// `small`: a small panel's (its search), as high as its rows (menu_row_min), so a capsule its padding in from its
/// corner, concentric with it (capsule_in(r_menu, 34) = panel_pad), as its rows are; its words' line (the body's 22, not
/// a row's 20: menu_row_over would make it 36) in its middle.
// kept across runs: a value (no field of it changes)
let input_box_small : @ui.Style = input_box.then(@ui.style(h=Fixed(menu_row_min)))

///|
// kept across runs: a value (no field of it changes)
let input_box_small_hot : @ui.Style = input_box_small.then(@ui.css("border_color=FieldHover"))

///|
/// A choice among a few (parts.tsx Select): closed, a pill as a one-line field is (input_box: the theme's control
/// height and body words), what is chosen in it cut short, the placeholder subtle, a chevron at its end; pressed (or
/// Enter, Space), its options through the presenters (@sf.pick: beside it a menu's, the arrows, letters and Enter;
/// a sheet of rows with touch), the chosen checked, `hints` a quieter note at an option's end. `options`: each
/// value and its words; `choose` is given the one chosen. `whole`: never narrower than what is chosen in it says, its
/// words never cut (what is beside it gives way). `icons`: an option's icon by its value (an icon's name, or
/// `runtime:<runtime>` for a runtime's mark), before its words in its row and, chosen, in the select.
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
  whole? : Bool = false,
  icons? : Map[String, String] = {},
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
    keep=whole,
    fn() {
      c.box(style=select_lead, fn() {
        match icons.get(value) {
          Some(i) if words != "" => draw_icon(c, i, select_icon, t.p.text)
          _ => ()
        }
        c.text(if words == "" { placeholder } else { words }, style=if words == "" {
          select_placeholder
        } else {
          select_words
        })
        |> ignore
      })
      |> ignore
      icon(c, "chevron-down", size=select_chevron, color=t.p.muted) |> ignore
    },
  )
  c.semantics(b, Button, id~, label=if label == "" { words } else { label + ": " + words }, disabled~)
  if !disabled && c.clicked(id) {
    pick(
      label,
      options.map(fn(o) { choice(o.0, o.1, value=hints.get(o.0).unwrap_or(""), icon=icons.get(o.0).unwrap_or("")) }),
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
/// What is chosen in a select: its icon (where it has one) and its words, 6 apart.
// kept across runs: a value (no field of it changes)
let select_lead : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// A chosen option's icon in a select: as a row's mark (14).
let select_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let select_words : @ui.TextStyle = @ui.text_style(size=Body, leading=L6, wrap=false, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let select_placeholder : @ui.TextStyle = select_words.then(@ui.text_style(color=Subtle))

///|
/// An option's row (parts.css.ts selectItem: a menu's item, its check at its end 10 in).
// kept across runs: a value (no field of it changes)
let select_item : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let select_hint : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

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
      style=(if s.hovered || s.pressed { one_of_row_hot } else { one_of_row }).then(@ui.style(min_h=Fixed(t.items.least))),
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
/// at its end; the chosen one edged in the ink, what it holds more (`extra`, by its value: a switch of it; none, nor
/// its line, where it has none) under a line in it; those `disabled` faded and not chosen; `note`: what draws a
/// description of its own, by its value. `options`: each value, title and description. What is chosen now.
pub fn choices(
  c : @ui.Ctx,
  key : String,
  value : String,
  options : Array[(String, String, String)],
  label? : String = "",
  icon? : (String) -> Unit,
  extra? : (String) -> (() -> Unit)?,
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
          // (its icon by its title's line's middle, not the whole's: lead_by_first_line)
          let by_title = fn(f : () -> Unit) {
            c.box(style=@ui.style(min_h=Fixed(c.sp(choice_title_line(c))), justify=JCenter), f) |> ignore
          }
          c.box(style=if note == "" && note_of is None { choice_hit } else { choice_hit_top }, fn() {
            match icon {
              Some(f) => by_title(fn() { f(v) })
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
            // (its mark in its end's middle: concentric with the card's corners, docs/ui-panels.md)
            c.box(style=choice_mark_at, fn() {
              c.box(style=if s.on { radio_mark_on } else { radio_mark }, fn() {
                if s.on {
                  c.box(style=radio_dot, fn() {  }) |> ignore
                }
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
          // (parts.css.ts choiceExtra: 14 in at its sides, 12 over and 14 under what it holds; no line over it: only
          // a menu's parts are set apart by one, docs/ui-panels.md. Narrow, its rows each a ground pressed whole: those
          // a step of the ladder in from its sides and foot, round as that step, their words their own padding in)
          match extra.bind(fn(f) { f(v) }) {
            Some(f) if s.on =>
              c.box(style=if look() is Narrow { choice_extra_rows } else { choice_extra }, fn() {
                c.box(style=if look() is Narrow { choice_extra_rows_in } else { choice_extra_in }, fn() {
                  // (on the choice as on a card: a row's ground there rounds in its corners, in_card)
                  in_card.val += 1
                  f()
                  in_card.val -= 1
                })
                |> ignore
              })
              |> ignore
            _ => ()
          }
      })
      |> ignore
    }).value
}

///|
/// A choice: bordered, a block's corner of the ladder's (18: at a card's foot, reaching to its inset, concentric with
/// its corners; every one alike).
// kept across runs: a value (no field of it changes)
let choice_card : @ui.Style = @ui.css("w=Full bg=Surface border=B1 border_color=Border disabled{opacity=O55}").then(
  @ui.style(radius=row_radius),
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
/// (a choice's radio mark in the middle of its end, the card's top to its foot)
// kept across runs: a value (no field of it changes)
let choice_mark_at : @ui.Style = @ui.css("h=Full justify=JCenter")

///|
/// How high a choice's title's line is (choice_title's L6).
fn choice_title_line(c : @ui.Ctx) -> Double {
  let (_, font_line) = c.text_size(Ui)
  c.theme().leading(L6).unwrap_or(font_line)
}

///|
/// (choice_hit with a description under its title: what is beside its words by its title's line)
// kept across runs: a value (no field of it changes)
let choice_hit_top : @ui.Style = @ui.css("row w=Full px=S3_5 py=S3 gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let choice_extra : @ui.Style = @ui.css("w=Full px=S3_5")

///|
// kept across runs: a value (no field of it changes)
let choice_extra_in : @ui.Style = @ui.css("w=Full pt=S3 pb=S3_5")

///|
/// Narrow, where what it holds are rows each a ground pressed whole: those a step of the ladder in from the choice's
/// sides and its foot (corner_inset), round as that step (in_card: Inner), concentric with its corners.
// kept across runs: a value (no field of it changes)
let choice_extra_rows : @ui.Style = @ui.style(w=Full, px=inset_room)

///|
// kept across runs: a value (no field of it changes)
let choice_extra_rows_in : @ui.Style = @ui.style(w=Full, pt=S3, pb=inset_room)

///|
// kept across runs: a value (no field of it changes)
let choice_words : @ui.Style = @ui.css("w=Grow(1.0) gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let choice_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let choice_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

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
    w=dmin(confirm_w, c.window_size().0 - dialog_margin),
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
let confirm_error : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Danger)

///|
// kept across runs: a value (no field of it changes)
let confirm_foot : @ui.Style = @ui.css("row w=Full justify=JEnd align=ACenter gap=S2 pt=S2")

// ---------------------------------------------------------------------------
// A small panel's parts (parts.tsx PanelHead, PanelGroup, PanelNote, PanelFoot, PanelText, PanelButton,
// PanelIconButton; parts.css.ts: inside a small panel, @sf.small_panel, its rows @sf.menu_item(panel=true))

///|
/// A small panel's head (PanelHead): its title (13, 600) and `note` under it (12, muted), in by a row's padding, as far
/// under the panel's top as a menu's first item's words (menu_row_over), 4 over what follows; `end` beside the title
/// (panel's `head_end`).
pub fn panel_head(c : @ui.Ctx, title : String, note? : String = "", end? : (@ui.Ctx) -> Unit) -> Unit {
  match end {
    // (what stands at its end beside its title, in the middle of their line, the rest of it: a search)
    Some(f) => {
      // (what stands at its end a row's capsule in the panel's top corner: out as far as makes it concentric with it,
      // as a pick's search stands, menu_row_reach)
      let r = menu_row_reach(theme().rows.pick)
      c.box(style=panel_head_line.then(@ui.style(mt=room(-r), mr=room(-r))), fn() {
        c.text(title, style=panel_title) |> ignore
        c.box(style=panel_head_end, fn() { f(c) }) |> ignore
      })
      |> ignore
    }
    None =>
      c.box(style=panel_head_box, fn() {
        c.text(title, style=panel_title) |> ignore
        if note != "" {
          c.text(note, style=panel_note_words) |> ignore
        }
      })
      |> ignore
  }
}

///|
/// A small panel's head with what stands at its end: its title in by a row's padding, 12 before what follows it, which
/// takes the rest of the line, 4 over what follows.
// kept across runs: a value (no field of it changes)
let panel_head_line : @ui.Style = @ui.css("row w=Full pl=S2_5 pb=S1 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let panel_head_end : @ui.Style = @ui.style(w=grow)

///|
/// A group of a small panel's rows (PanelGroup) under a small `label` (12, muted: in by a row's padding, as far under
/// what is over it as a row's words, 2 over its rows), 2 apart.
/// `lead`: what goes before its label (a workspace's mark: workspace_badge).
pub fn panel_group(c : @ui.Ctx, body : () -> Unit, label? : String = "", lead? : (@ui.Ctx) -> Unit) -> Unit {
  c.box(style=panel_group_box, fn() {
    if label != "" {
      c.box(style=panel_label_at, fn() {
        match lead {
          Some(draw) =>
            c.box(style=panel_label_led, fn() {
              draw(c)
              c.text(label, style=panel_note_words) |> ignore
            })
            |> ignore
          None => c.text(label, style=panel_note_words) |> ignore
        }
      })
      |> ignore
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
  let mut words_at = -1
  let b = c.box(
    style=if tone == Filled { panel_button_filled } else { panel_button_box },
    disabled~,
    id=if disabled { 0 } else { id },
    fn() {
      words_at = c.text(words, style=match tone {
        Accent | Filled => panel_button_accent
        Quiet => if hot { panel_button_words } else { panel_button_quiet }
        Plainly => panel_button_words
      })
    },
  )
  // (its words changed, 复制链接 to 已复制: to its new width as a button does)
  @motion.reshape(c, b, "sf-pbtn/shape/" + key, by=words, spec=button_reshape)
  @motion.layout(c, words_at, "sf-pbtn/words/" + key, by=words, spec=button_reshape)
  c.semantics(b, Button, id~, label=words, disabled~)
  !disabled && c.clicked(id)
}

///|
/// An icon to press in a small panel (PanelIconButton: close, stop, a step): a 24 circle, the muted ink, the hover's
/// ground and the ink pointed at; named on hover; `cornered`, in the panel's top end corner (panel_icon_corner). True
/// on the frame after it was pressed.
pub fn panel_icon_button(
  c : @ui.Ctx,
  key : String,
  name : String,
  label : String,
  disabled? : Bool = false,
  cornered? : Bool = false,
) -> Bool {
  let p = theme().p
  let id = c.id(key)
  let hot = !disabled && c.lit(id)
  let style = if cornered { panel_icon_box.then(panel_icon_corner) } else { panel_icon_box }
  let b = c.box(style~, disabled~, id=if disabled { 0 } else { id }, fn() {
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
let panel_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Semibold, color=Fg)

///|
// kept across runs: a value (no field of it changes)
let panel_note_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let panel_group_box : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let panel_label_at : @ui.Style = @ui.css("w=Full px=S2_5 pt=S1_5 pb=S0_5")

///|
/// A label with something before it (panel_group's `lead`): in a line, 6 apart.
// kept across runs: a value (no field of it changes)
let panel_label_led : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

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
let panel_button_filled : @ui.Style = panel_button_box.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let panel_button_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, weight=Medium, wrap=false, color=Fg)

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

///|
/// Where a small panel's icon button stands in its top end corner (its ×): as far in as makes its circle
/// concentric with the panel's corner (capsule_in: the corner less its half), past the panel's padding (panel_pad).
pub let panel_icon_corner : @ui.Style = @ui.style(mt=room(panel_icon_in), mr=room(panel_icon_in))

///|
let panel_icon_in : Double = capsule_in(r_menu, panel_icon_side) - panel_pad

///|
/// Its side (panel_icon_box's S6).
let panel_icon_side : Double = 24.0

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
let command_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Fg, wrap=false)

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
let chooser_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, wrap=false, color=Muted)

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
  /// dragged (once it went past the slop from where it was pressed) to this width
  Dragging(Double)
  /// let go after it was dragged, at this width
  Dropped(Double)
  /// pressed and let go without moving (the web's `press`: a panel closing)
  Pressed
  /// the second of two clicks (the first was `Pressed`): its own width again, or as wide as what it holds needs
  Twice
} derive(Eq, Show, Debug)

///|
/// An edge in hand: where the press went down, its column's width then.
priv struct Handling {
  x0 : Double
  w0 : Double
}

///|
/// The edges in hand, by their ids.
let handlings : Map[Int, Handling] = {}

///|
/// What the pointer does with the edge `id` of a column `width` wide, on its `edge`, a drag area across (Ctx::drag_on:
/// a finger's or a mouse's, what scrolls or drags under it taking what goes its own way, claim.mbt; once it is the
/// drag's, no tap and no long press of it; a finger's only once held still on it a long press's time, `hold`: a swipe
/// or a scroll that passes over it is what it passes over's): pressed and gone past the slop from where it went down,
/// the width it is
/// dragged to (the width it had then, the pointer's way on the right edge, the other way on the left, between `min`
/// and `max` on whole pixels); let go, the width it ends at, or a press without moving, or the second of two clicks.
/// A width that changes builds the frame again (Ctx::built_from_changed): the page takes it there, the column and its
/// edge under the pointer at once.
pub fn handle_drag(
  c : @ui.Ctx,
  id : Int,
  width : Double,
  min~ : Double,
  max~ : Double,
  edge? : @ui.Side = Right,
) -> Resized {
  c.drag_on(id, axis=Horizontal, hold=true)
  // (read whatever comes of it: it takes presses in every build of a frame alike, the one that let it go, its end
  // taken, and one built again after it)
  let clicked = c.clicked(id)
  let at = fn(h : Handling, x : Double) {
    let d = if edge is Left { h.x0 - x } else { x - h.x0 }
    dmax(min, dmin(max, (h.w0 + d).round()))
  }
  guard c.drag_of(id) is Some(d) else { return Untouched }
  if d.down {
    // (from where it went down: the frame that sees the press may see it moved already)
    let h = match handlings.get(id) {
      Some(h) => h
      None => {
        let h : Handling = { x0: d.x0, w0: width }
        handlings[id] = h
        h
      }
    }
    if !d.moving {
      return Untouched
    }
    let w = at(h, d.x)
    // (the column was built at `width`: built again at this one, the edge under the pointer in this frame)
    if w != width {
      c.built_from_changed("a column's edge dragged")
    }
    return Dragging(w)
  }
  // (pressed, moved and let go before a frame saw it: from the width it has)
  let h = handlings.get(id).unwrap_or({ x0: d.x0, w0: width })
  handlings.remove(id)
  if c.double_clicked(id) {
    Twice
  } else if d.take_end() {
    let w = at(h, d.x)
    if w != width {
      c.built_from_changed("a column's edge let go")
    }
    Dropped(w)
  } else if clicked {
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
      c.move_state([(bar, ["height", "opacity"])], duration=edge_bar_ms, ease=Out)
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
/// leaves, and as it presses or drags it, until it has left and come again. Said each frame the thing is drawn. A
/// mouse's only: a finger points at nothing (held on an edge, it is to drag it; lifted, it is nowhere).
pub fn edge_tip(c : @ui.Ctx, key : String, id : Int, words : String, side? : @ui.Side = Right) -> Unit {
  if words == "" || id == 0 || @ui.pointing() is Finger {
    return
  }
  let (px, py, down) = c.pointer()
  let on = c.lit(id)
  let frame = c.frame_number()
  // (a drag area's in hand from the press on: pressed no more once it is dragged, Ctx::drag_on)
  if c.watch_press(id) || c.drag_of(id) is Some({ down: true, .. }) {
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
  if edge_tips_away.contains(key) && !c.watch_press(id) {
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
/// How far in the card of options' rows stand: a list card's (list_pad, as a menu's rows in its panel), round by the
/// ladder's row corner in its corners.
let options_card_pad : Double = list_pad

///|
/// An option's row's corner (the ladder's row corner, concentric in the card's).
let option_row_corner : Double = row_corner

///|
/// An option's measures, the theme's for the screen (decided once: docs/architecture.md): its number's disc a list
/// item's mark, as far in from the row's top and side as makes it concentric with the row (its corner less the disc's
/// half); its label in the controls' words, what it leads to in the meta's. Keyboard and mouse's as the web's
/// (Decisions.css.ts choice: a 20 disc 8 in, 13 on 20 over 12 on 18); a phone's or a tablet's a size up (a 22 disc 7
/// in, 15 on 22 over 13 on 18).
priv struct OptionType {
  disc : Double
  pad_in : Double
  label : Double
  label_line : Double
  detail : Double
  detail_line : Double
}

///|
fn option_type() -> OptionType {
  let t = theme()
  let disc = t.items.mark
  {
    disc,
    pad_in: capsule_in(option_row_corner, disc),
    label: t.t.ui,
    label_line: t.t.ui_line,
    detail: t.t.meta,
    detail_line: t.t.meta_line,
  }
}

///|
/// The card of options in the wide frame: as wide as what it says, 460 at least (Decisions.css.ts options); on a phone
/// as wide as where it is.
let options_least_wide : Double = 460.0

///|
/// The card's width at most: as wide as its widest label or detail with its number and paddings, 460 at least (the
/// web's `width: fit-content; min-width: min(100%, 460px)`), where it is at most as its layout gives it (the card fills
/// where it is up to this: never its room read back from a frame before, which a chat's first frame has not, the card
/// laid out none wide there and the list again in the next); on a phone where it is's (none).
fn options_most(options : Array[(String, String, Bool)], ot : OptionType, wide : Bool) -> Double {
  if !wide {
    return 1.0e9
  }
  let mut words = 0.0
  for o in options {
    words = dmax(words, @ui.text_advance(o.0, size=ot.label, weight=500))
    words = dmax(words, @ui.text_advance(o.1, size=ot.detail, weight=400))
  }
  // (the card's inset each side, the row's number in by 8 and 12 after it, the row's 12 at its end)
  dmax(options_least_wide, options_card_pad * 2.0 + ot.pad_in + ot.disc + 12.0 + words + 12.0).ceil()
}

///|
/// The card's corner: a list card's (a column of rows list_pad in, list_card_corner), its rows round by the ladder's
/// row corner and their discs concentric with them (as far in as their half less that: the row's pad_in).
let options_card_radius : Double = list_card_corner

///|
/// One line asked of the viewer on an option's ground (what the chat needs, at its end, with 忽略): one row laid as an
/// option's, alone (pad_in in on every side, its corner an option row's, so its words sit as far in from every side
/// and its corner's concentric with them), on the text at 5% as an options card under a post. No card round it: an
/// options card's list_pad is room for its rows' grounds lit under the hand, and nothing in this row lights up;
/// framed so (#2543) its words stood twice as far in and one line was a fat capsule. `body` the row's (a row;
/// `column` lays it a column instead).
pub fn ask_line_card(c : @ui.Ctx, column? : Bool = false, body : () -> Unit) -> Int {
  // (the row's room round its words an option's, the theme's for the screen: option_type)
  let inside = @ui.style(p=room(option_type().pad_in))
  c.box(style=(if column { ask_line_column } else { ask_line_row }).then(ask_line_ground).then(inside), body)
}

///|
/// What leads ask_line_card's words (what the chat needs: its bell), where an option's number is: in the middle of a
/// column as wide and as high as its disc, so it stands as far in from the row's corner as the disc, concentric.
pub fn ask_line_mark() -> @ui.Style {
  let d = ask_line_disc()
  @ui.style(w=Fixed(d), h=Fixed(d), align=ACenter, justify=JCenter)
}

///|
/// How big the check in a picked option's disc is, of the disc (options_card).
pub let option_check_share : Double = 0.6

///|
/// Where the check stands in a picked option's disc, over its number: its middle (options_card).
// kept across runs: a value (no field of it changes)
let option_check_room : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// How far an option's row keeps its words from its end, where the one being sent turns (options_card).
let option_row_end : Double = 12.0

///|
/// Room at the start of ask_line_card's row where no mark leads it (what the chat needed, let go): its words where the
/// mark `icon` wide would start in ask_line_mark's column.
pub fn ask_line_start(icon : Double) -> @ui.Style {
  let side = (ask_line_disc() - icon) / 2.0
  @ui.style(pl=room(side))
}

///|
/// Words to press ending ask_line_card's row (忽略 ending what a chat needs): quiet, the line's own words (not a
/// button's: the user, 2026-10-31, 太明显了), in its ink under the hand; their room a button's (as tall, round as it,
/// the press's room as least as the native input's), its ground under the hand or the finger concentric with the row's
/// end corner (capsule_in), its words where they stood, as far in as the row's start mark `mark` wide is from its start; on the
/// first of the row's lines, however many the words before it take. `disabled`: there and faded, taking no press.
/// True on the frame after it was pressed.
pub fn ask_line_button(
  c : @ui.Ctx,
  label : String,
  key~ : String,
  mark~ : Double,
  disabled? : Bool = false,
) -> Bool {
  let h = button_height()
  let pad = option_type().pad_in
  let inset = capsule_in(option_row_corner, h)
  let out = pad - inset
  let id = c.id(key)
  let live = !disabled
  let lit = ease_to(c, "sf-ask-line-btn/\{id}", live && (c.lit(id) || c.pressed(id)))
  let seen = @motion.animate(c, "sf-ask-line-btn-seen/\{id}", if disabled { 0.45 } else { 1.0 }, spec=@motion.tween(dur_ms, ease=Out))
  let look = theme().chat_list
  // (its words as far in from its end as the bell's from the row's start: the bell's room in its disc's column)
  let side = (ask_line_disc() - mark) / 2.0
  let room_of = @ui.style(
    row=true,
    h=Fixed(h),
    px=room(out + side),
    mt=room(-out),
    mb=room(-out),
    mr=room(-out),
    radius=Full,
    align=ACenter,
    bg=Data(alpha(theme().p.hover, lit)),
  )
  let b = c.box(
    style=room_of,
    id=if live { id } else { 0 },
    fn() {
      // (its ink the quiet one's, the line's own under the hand, over dur_ms)
      let ink = mix(theme().p.text, lit, theme().p.muted)
      let words = look.state_quiet.then(ask_line_button_words).then(@ui.text_style(color=Data(ink)))
      c.text(label, style=ask_line_words(words)) |> ignore
    },
  )
  c.look(b, @ui.look(alpha=seen))
  c.semantics(b, Button, id=if live { id } else { 0 }, label~, disabled=!live)
  live && c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let ask_line_button_words : @ui.TextStyle = @ui.text_style(w=Hug, wrap=false)

///|
/// The words of ask_line_card's row (what it says, 忽略 at its end): `words` on lines as high as ask_line_mark's
/// column, as an option's label on its disc, so the first line has the mark in its middle and the row as far over it
/// as under it. (On a list's state line, 18 against the disc's 20 laid from the top, the words stood 1 over the bell.)
pub fn ask_line_words(words : @ui.TextStyle) -> @ui.TextStyle {
  words.then(@ui.text_style(leading=theme().items.mark_line))
}

///|
/// The width of ask_line_mark's column: an option's disc, the theme's for the screen.
fn ask_line_disc() -> Double {
  option_type().disc
}

///|
/// ask_line_card's ground: an option row's corner, on the text at 5% (options_card `wide`).
// kept across runs: a value (no field of it changes)
let ask_line_ground : @ui.Style = @ui.css("bg=A(Fg,O5)").then(@ui.style(radius=rounded(option_row_corner)))

///|
/// Its row: 12 between its words and what is at its end, as an option's disc and label.
// kept across runs: a value (no field of it changes)
let ask_line_row : @ui.Style = @ui.css("row w=Full gap=S3 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let ask_line_column : @ui.Style = @ui.css("w=Full align=AStart")

///|
/// A card of options (SettingParts.kt DecisionOptions): each a row to be pressed (its ground under the finger list_pad
/// in from the card's edge, as a list card's, rounded 18), its number in a disc (the one recommended in the accent), its label and what it
/// leads to (`options`: each its label, its detail, whether recommended); half there when not `enabled`, a spinner on
/// the one being answered (`busy`, none pressed meanwhile; `chosen` stays whole); its measures the theme's for the
/// screen (option_type). Under a post as the web's (`wide`: as wide as what it says, where it is at most, on the
/// text at 5%); its row's ground under the pointer. `history` keeps the original choices fully legible and read-only,
/// with a check beside the chosen one; its presenter supplies the only ground and padding. The option tapped,
/// on the frame after.
pub fn options_card(
  c : @ui.Ctx,
  key : String,
  options : Array[(String, String, Bool)],
  enabled : Bool,
  busy : Int?,
  chosen? : Int? = None,
  wide? : Bool = false,
  history? : Bool = false,
) -> Int? {
  let t = theme()
  let free = enabled && busy is None && !history
  let mut picked : Int? = None
  let ot = option_type()
  let ground = if history { 0L } else if wide { alpha(t.p.text, 0.05) } else { t.p.chip }
  let padding = if history { 0.0 } else { options_card_pad }
  // (in the wide frame as wide as what it says and 460 at least, on the text at 5%: Decisions.css.ts options)
  c.box(w=Fill(1.0), align=if wide { AStart } else { AStretch }, fn() {
    let across = @ui.style(w=Full, max_w=Fixed(options_most(options, ot, wide)))
    c.box(style=across, radius=options_card_radius, bg=ground, pad=padding, fn() {
      // (nothing drawn between two: SettingParts.kt DecisionOptions)
      for i, o in options {
        let id = c.id(key + "/" + i.to_string())
        if free && c.clicked(id) {
          picked = Some(i)
        }
        // under a mouse's pointer its row's ground, in any layout (Decisions.css.ts choice:hover)
        let mouse = @ui.pointing() is Mouse
        let hot = mouse && free && c.lit(id)
        // (the one picked, answered: a check in its disc where its number was, on the accent; the rest half there, the
        // one being sent turning at its end: each over dur_ms, as a control answers, never at once)
        let picked_here = !history && chosen == Some(i)
        let ease = @motion.tween(dur_ms, ease=Out)
        let k = key + "/" + i.to_string()
        let there = @motion.animate(c, "options-seen/" + k, if history || enabled || chosen == Some(i) { 1.0 } else { 0.5 }, spec=ease)
        let ticked = @motion.animate(c, "options-ticked/" + k, if picked_here { 1.0 } else { 0.0 }, spec=ease)
        let turning = @motion.animate(c, "options-turning/" + k, if busy == Some(i) { 1.0 } else { 0.0 }, spec=ease)
        c.box(
          dir=Row,
          w=Fill(1.0),
          pl=ot.pad_in,
          pr=option_row_end,
          pt=ot.pad_in,
          pb=ot.pad_in,
          gap=12.0,
          align=AStart,
          radius=option_row_corner,
          bg=if hot { t.p.hover } else { 0L },
          opacity=there,
          id~,
          fn() {
            c.box(
              w=Px(ot.disc),
              h=Px(ot.disc),
              radius=ot.disc / 2.0,
              bg=if o.2 { t.p.accent } else { mix_seen(t.p.accent, ticked, alpha(t.p.text, 0.09)) },
              align=ACenter,
              justify=JCenter,
              fn() {
                let color = if o.2 { 0xFFFFFFFFL } else { t.p.muted }
                let number = if i < 6 {
                  icon(c, "option-\{i + 1}", size=ot.disc, color~)
                } else {
                  c.text("\{i + 1}", size=theme().t.caption, weight=600, color~, wrap=false)
                }
                if ticked > 0.0 {
                  c.look(number, @ui.look(alpha=1.0 - ticked))
                  c.layer(fn() {
                    let mark = c.box(style=option_check_room, fn() {
                      icon(c, "check", size=ot.disc * option_check_share, color=0xFFFFFFFFL) |> ignore
                    })
                    c.look(mark, @ui.look(alpha=ticked))
                  })
                  |> ignore
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
            // (turning over the row's end, in what it leaves at the end of the words: never narrowing them)
            if turning > 0.0 {
              c.layer(fn() {
                let s = c.box(style=@ui.style(w=Full, align=AEnd, pt=room_of(ot.pad_in), pr=room_of(option_row_end)), fn() {
                  c.box(h=Px(ot.label_line), justify=JCenter, fn() { spinner(c, size=12.0) |> ignore }) |> ignore
                })
                c.look(s, @ui.look(alpha=turning))
              })
              |> ignore
            }
            if history && chosen == Some(i) {
              let check_room = @ui.style(h=Fixed(ot.label_line), justify=JCenter)
              c.box(style=check_room, fn() {
                icon(c, "check", size=14.0, color=t.p.accent) |> ignore
              }) |> ignore
            }
            // SettingParts.kt options: clickable while free, its ripple in the ink (ripple(color = C.ink))
            if free {
              @motion.ripple(c, id, option_row_corner, ink=alpha(t.p.text, 0.1))
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
let dialog_step : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let dialog_title_one : @ui.TextStyle = dialog_title.then(one_line)

///|
/// A page that waits on something (cloud/Security.tsx SecurityWaiting, mobile/Security.tsx SecurityWaitingScreen):
/// its mark (`mark`, an icon's name), what it waits for (`title`, `lead`), then what can be done meanwhile (`body`); its parts 14 apart,
/// centred. On a touch screen the phone's (mWaiting: in the middle of its height, 28 in at its sides, the mark 44, the
/// title bold); with keyboard and mouse the desktop page's (waiting: 110 down, 460 wide at most, 24 in, the mark 40, the title
/// 600).
pub fn waiting_page(c : @ui.Ctx, mark : String, title : String, lead : String, body : () -> Unit) -> Unit {
  let touch = native_input() is Finger
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
let wait_title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let wait_title_touch : @ui.TextStyle = @ui.text_style(size=Heading, weight=Bold, color=Fg, center=true)

///|
/// What it waits for: the body's, muted (waitingLead).
// kept across runs: a value (no field of it changes)
let wait_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L7, color=Muted, center=true)

///|
/// The way into an app, signed out (the web's cloud/gate.tsx SignInPage; SignIn.kt SignInScreen), in the box it is
/// given: its picture (`art`, a drawable), what it is (`title`, `note`), its button (`label`; `busy` while it is under
/// way, not pressed again, a spinner before its words), what to know of it (`foot`), and what there is to say of
/// signing in under the button (`said`: what it waits on, or why it failed, `bad`, in the red), coming and going with
/// its room. Keyboard and mouse's the picture, the button and what is said of it alone, no wider than the desktop app's
/// (asked for, 2026-10-23); a touch screen's all of it, the button across its page. True on the frame after the button
/// was pressed.
pub fn way_in(
  c : @ui.Ctx,
  art : String,
  title : String,
  note : String,
  label : String,
  foot : String,
  busy? : Bool = false,
  said? : String = "",
  bad? : Bool = false,
) -> Bool {
  let bare = native_input() is Mouse
  let mut pressed = false
  // (what was said kept as it goes, its room closing under it)
  if said != "" {
    way_in_said.val = (said, bad)
  }
  let open = @motion.anim(c, "sign-in/said", if said != "" { 1.0 } else { 0.0 }, global=true)
  open.follow(if said != "" { 1.0 } else { 0.0 }, @motion.move().per_unit(@motion.reveal_height("sign-in/said")))
  let share = open.get()
  way_in_page(c, art, fn() {
    if !bare {
      way_in_title(c, title)
      way_in_note(c, note)
    }
    c.box(style=sign_in_gap, fn() {  }) |> ignore
    pressed = way_in_button(c, "sign-in", label, busy~)
    if share > 0.0 {
      let (words, red) = way_in_said.val
      @motion.reveal(c, "sign-in/said", share, middle=true, fn() {
        let i = c.text(words, style=if red { sign_in_said_bad } else { sign_in_said })
        @motion.leaving(c, i, said != "")
      })
    }
    if !bare {
      c.text(foot, style=sign_in_many) |> ignore
    }
  })
  pressed
}

///|
/// A page of the way in (way_in's, and those after it till a workspace is open: none yet, an invitation, an account
/// not let in), in the box it is given: its picture (`art`) over what `body` says and offers, all of it in the middle
/// of the page, no wider than a tablet's button. The picture keyed: from one of these pages to the next it goes from
/// where it was to its new place, not at once.
pub fn way_in_page(c : @ui.Ctx, art : String, body : () -> Unit) -> Unit {
  let w = dmin(sign_in_picture_w, c.width - sign_in_side_w - sign_in_side_w)
  // (its foot at the same height on each of them, whatever is under it: what changes from page to page is under the
  // picture, the picture and the title where they were)
  let above = dmax(0.0, c.height * way_in_picture_foot - drawable_height(art, w) - way_in_page_top)
  c.box(style=way_in_whole, fn() {
    c.box(style=@ui.style(h=Fixed(above)), fn() {  }) |> ignore
    let picture = drawable(c, art, w)
    @motion.layout(c, picture, "way-in/picture", spec=button_reshape)
    c.box(style=way_in_column, body) |> ignore
  })
  |> ignore
}

///|
/// Where a way-in page's picture ends, down its page (way_in_page): a little over its middle, so a page of a button or
/// two sits about the middle and one with more has room under it.
let way_in_picture_foot : Double = 0.42

///|
/// A way-in page (way_in_page): its picture and what is under it in a column down its middle, 30 in from its sides
/// and 40 from its top and foot, 12 apart (SignIn.kt: padding(horizontal = 30.dp, vertical = 40.dp), spacedBy(12.dp)).
// kept across runs: a value (no field of it changes)
let way_in_whole : @ui.Style = @ui.style(w=Full, h=Full, px=sign_in_side, py=S10, gap=S3, align=ACenter)

///|
/// How far down a way-in page what it holds starts (way_in_whole's py: S10).
let way_in_page_top : Double = 40.0

///|
/// A way-in page's title (way_in_page): under the picture, 28, bold.
pub fn way_in_title(c : @ui.Ctx, title : String) -> Unit {
  c.box(style=sign_in_title_box, fn() { c.text(title, style=sign_in_title) |> ignore }) |> ignore
}

///|
/// What a way-in page says under its title (way_in_page): the body's size, muted, centred.
pub fn way_in_note(c : @ui.Ctx, note : String) -> Unit {
  c.text(note, style=sign_in_note) |> ignore
}

///|
/// A way-in page's button (way_in_page; `key` its own): 50 high, a pill across a touch screen's page (420 at most),
/// 300 on a desktop; `solid` the ink's, the one thing to do, else the chip's ground; `busy` while what it does is under
/// way: a spinner before its words, not pressed again. Its words changed, they move to their new place. True on the
/// frame after it was pressed.
pub fn way_in_button(c : @ui.Ctx, key : String, label : String, solid? : Bool = true, busy? : Bool = false) -> Bool {
  let p = theme().p
  let bare = native_input() is Mouse
  let id = c.id(key)
  let pressed = !busy && c.clicked(id)
  let ink = if solid { p.bg } else { p.text }
  let mut words_at = -1
  let b = c.box(style=way_in_button_style(bare, solid), id~, fn() {
    // (as a button's: the spinner's room opening before its words, @sf.button)
    let turning = ease_to(c, key + "/busy", busy)
    let over = @motion.animate(c, key + "/over", if busy { 1.0 } else { 0.0 }, spec=button_reshape)
    if busy || over > 0.0 {
      let room = button_icon + sign_in_spin_gap
      c.box(style=@ui.style(row=true, w=Fixed(room * over), h=Fixed(button_icon)), fn() {
        let s = c.box(style=button_spin, fn() {
          spinner(c, size=button_icon, ring=alpha(ink, 0.3), arc=if solid { ink } else { p.accent }) |> ignore
        })
        c.look(s, @ui.look(alpha=turning, scale=over, ox=0.0))
      })
      |> ignore
    }
    words_at = c.text(label, style=if solid { sign_in_words } else { sign_in_words_plain })
    // SignIn.kt: clip(CircleShape).clickable
    if !busy {
      @motion.ripple(c, id, sign_in_button_h / 2.0)
    }
  })
  // (its words changed, 登录或注册 to 正在登录: moved to their new place, not at once)
  @motion.layout(c, words_at, key + "/words", by=label, spec=button_reshape)
  c.semantics(b, Button, id=if busy { 0 } else { id }, label~, disabled=busy)
  pressed
}

///|
/// What a way-in page offers last, quietly (way_in_page: 切换账号): its words alone, the page's ink, a ground under the
/// pointer. True on the frame after it was pressed.
pub fn way_in_link(c : @ui.Ctx, key : String, label : String, busy? : Bool = false) -> Bool {
  button(c, label, key~, tone=Ghost, busy~)
}

///|
/// What a way-in page says and offers under its picture (way_in_page): a column 12 apart, its things in its middle,
/// no wider than a tablet's button.
// kept across runs: a value (no field of it changes)
let way_in_column : @ui.Style = @ui.style(w=Full, max_w=Fixed(sign_in_touch_w), gap=S3, align=ACenter)

///|
/// What was last said under the sign-in button (way_in): kept as its room closes.
// kept across runs: what the page last said, drawn as it goes
let way_in_said : Ref[(String, Bool)] = Ref::new(("", false))

///|
/// Between the sign-in button's spinner and its words.
let sign_in_spin_gap : Double = 8.0

///|
/// What is said of signing in under its button: small, muted, centred, wrapping.
// kept across runs: a value (no field of it changes)
let sign_in_said : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)

///|
/// Why signing in failed: as what is said, in the red.
// kept across runs: a value (no field of it changes)
let sign_in_said_bad : @ui.TextStyle = sign_in_said.then(@ui.text_style(color=Danger))

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
/// What the page leaves either side of the picture (its sides: way_in_whole's px).
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
  center=true,
  w=Full,
  leading=Font,
)

///|
/// What still.fail is for: the body's size, muted, centred (SignIn.kt: 15.sp, lineHeight 21.sp).
// kept across runs: a value (no field of it changes)
let sign_in_note : @ui.TextStyle = @ui.text_style(size=Body, color=Muted, center=true, w=Full)

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
    // (a step towards the page under the pointer, as a solid button's: @sf.button's primary_hover)
    hovered=@ui.patch(bg=Over(Fg, A(Bg, O15))),
    pressed=@ui.patch(bg=Over(Fg, A(Bg, O15))),
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
/// A way-in page's other buttons (way_in_button `solid` false): the quiet ground of the words' colour, a step darker
/// under the pointer.
fn sign_in_button_plain(most : Double) -> @ui.Style {
  sign_in_button(most).then(@ui.style(bg=Tint, hovered=@ui.patch(bg=TintStrong), pressed=@ui.patch(bg=TintStrong)))
}

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_desk_plain : @ui.Style = sign_in_button_plain(sign_in_desk_w)

///|
// kept across runs: a value (no field of it changes)
let sign_in_button_touch_plain : @ui.Style = sign_in_button_plain(sign_in_touch_w)

///|
/// A way-in button's look (way_in_button): a desktop's or a touch screen's width, the ink's ground or the quiet one.
fn way_in_button_style(bare : Bool, solid : Bool) -> @ui.Style {
  match (bare, solid) {
    (true, true) => sign_in_button_desk
    (false, true) => sign_in_button_touch
    (true, false) => sign_in_button_desk_plain
    (false, false) => sign_in_button_touch_plain
  }
}

///|
// kept across runs: a value (no field of it changes)
let sign_in_words : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Bg, wrap=false, leading=Font)

///|
/// A way-in page's other buttons' words (sign_in_button_plain): the ink's.
// kept across runs: a value (no field of it changes)
let sign_in_words_plain : @ui.TextStyle = sign_in_words.then(@ui.text_style(color=Fg))

///|
/// 可同时登录多个账号: small, muted.
// kept across runs: a value (no field of it changes)
let sign_in_many : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, leading=Font)


///|
/// A newer build ready for the person's word (Home.kt's update key; one look wherever a frame puts it, the size of the
/// keys beside it: `side` across, its mark `mark`): the download mark in its middle (the key is there only while the
/// build waits on its press: no dot over it to say so); while it is `busy` (being put in place), in the mark's place
/// how far it has come (coming_mark: `coming`, 0 to 1, from its top; None while not known, the spinner's quarter
/// turning there), no words. `why` its tip. Said to be `label`. True on the frame it is pressed, not while it is busy.
pub fn update_key(
  c : @ui.Ctx,
  key : String,
  side : Double,
  mark : Double,
  label : String,
  why : String,
  coming : Double?,
  busy : Bool,
) -> Bool {
  let t = theme()
  let id = c.id(key)
  let hot = c.lit(id) && !busy
  let b = c.box(
    style=(if hot { update_key_hot } else { update_key_box }).then(@ui.style(w=Fixed(side), h=Fixed(side))),
    id~,
    fn() {
      if busy {
        coming_mark(c, key, coming, mark, t.p.text)
      } else {
        icon(c, "download", size=mark, color=t.p.text) |> ignore
      }
      if !busy {
        press_ripple(c, id, side / 2.0)
      }
    },
  )
  c.semantics(b, Button, id~, label~, disabled=busy)
  if why != "" {
    tip(c, key + "/tip", id, why, side=Bottom)
  }
  !busy && c.clicked(id)
}

///|
/// The list catching up on what changed while away (the chats' `syncing`; docs/ui-panels.md 等待): beside the keys of
/// the bar it stands in, `side` across, the refresh mark (`mark`, in the grey of what it says nothing of) turning, a
/// turn each sync_turn_ms, slow at its ends (by the clock as each frame is drawn: nothing built anew for it); `text` its tip and what it is said to be. Only once it has gone on later_ms
/// (a moment's catching up shows nothing). Once all is here, the mark becomes a tick: it goes on from where it is and as
/// fast as it turns, slowing to rest where it looks as upright (sync_rest), its arrows drawn back along their strokes,
/// then the tick drawn as a hand ticks (no two marks fading over each other); there sync_done_ms, then it fades.
pub fn sync_key(c : @ui.Ctx, key : String, side : Double, mark : Double, shown : Bool, text : String) -> Unit {
  let t = theme()
  let on = shown && waited_long(c, key)
  if shown {
    sync_said[key] = text
  } else {
    done_waiting(c, key)
  }
  if on {
    sync_seen[key] = true
  }
  // done: brought to rest, the tick drawn, held a while, then gone
  let seen = sync_seen.get(key).unwrap_or(false)
  let ticked = seen && !shown
  let rest = if ticked {
    match sync_rests.get(key) {
      Some(r) => Some(r)
      None => {
        let r = sync_rest(c.moment())
        sync_rests[key] = r
        Some(r)
      }
    }
  } else {
    sync_rests.remove(key)
    None
  }
  // the arrows go as it is nearly at rest (its last part hardly moves)
  let settle = match rest {
    Some(r) => r.ms * sync_rest_gone
    None => 0.0
  }
  let held = ticked && !@kit.after(c, key + "/done", true, settle + sync_back_ms + sync_tick_ms + sync_done_ms)
  if !ticked {
    @kit.after(c, key + "/done", false, sync_done_ms) |> ignore
  }
  let p = @kit.presence(c, key, on || held, exit=@motion.tween(sync_out_ms, ease=Leave))
  if !p.built {
    sync_said.remove(key)
    sync_seen.remove(key)
    sync_rests.remove(key)
    return
  }
  let words = sync_said.get(key).unwrap_or(text)
  // how far on to rest it has gone (0 to 1, as SyncRest::ease)
  let resting = @kit.animate(c, key + "/rest", if ticked { 1.0 } else { 0.0 }, transition=match rest {
    Some(r) => @motion.tween_to(duration=r.ms, ease=fn(s) { r.ease(s) })
    None => @motion.tween(0.0, ease=Out)
  })
  // how far the arrows are drawn back, then the tick drawn (0 to 1 each), once it is at rest
  let back = @kit.animate(
    c,
    key + "/back",
    if ticked { 1.0 } else { 0.0 },
    transition=@motion.tween(if ticked { sync_back_ms } else { 0.0 }, ease=InOut, delay=settle),
  )
  let drawn = @kit.animate(
    c,
    key + "/tick",
    if ticked { 1.0 } else { 0.0 },
    transition=@motion.tween(if ticked { sync_tick_ms } else { 0.0 }, ease=Out, delay=settle + sync_back_ms * 0.6),
  )
  let id = c.id(key)
  let b = c.box(style=update_key_box.then(@ui.style(w=Fixed(side), h=Fixed(side))), id~, fn() {
    if back < 1.0 {
      // (in the whole key, in its middle: turned about it)
      let a = c.layer(fn() {
        c.box(style=update_ring_at, fn() {
          ignore(
            if back > 0.0 {
              icon_traced(c, "refresh", fn(i, pts) { sync_drawn_back(i, pts, 1.0 - back) }, size=mark, color=t.p.muted)
            } else {
              icon(c, "refresh", size=mark, color=t.p.muted)
            },
          )
        })
        |> ignore
      })
      match rest {
        // turned by the clock as each frame is drawn (Ctx::cycle_look), slow at a turn's ends
        None => c.cycle_look(a, sync_turn_ms, fn(k) { @ui.look(rot=sync_turned(k)) })
        // going on to rest (upright again once there: it looks the same each half turn)
        Some(r) =>
          if back == 0.0 && resting < 1.0 {
            c.look(a, @ui.look(rot=r.from + (r.to - r.from) * resting))
          }
      }
    }
    if drawn > 0.0 {
      c.layer(fn() {
        c.box(style=update_ring_at, fn() {
          ignore(
            if drawn < 1.0 {
              icon_traced(c, "check", fn(_, pts) { [stroke_from_start(pts, drawn)] }, size=mark, color=t.p.muted)
            } else {
              icon(c, "check", size=mark, color=t.p.muted)
            },
          )
        })
        |> ignore
      })
      |> ignore
    }
  })
  c.look(b, { ..@ui.still_look, alpha: dmin(1.0, p.t) })
  c.semantics(b, Status, id~, label=words)
  tip(c, key + "/tip", id, words, side=Bottom)
}

///|
/// How far round the mark has turned where a turn is at `k` (0 to 1): slow at its ends (smoothstep, as CSS's
/// cubic-bezier(.45, .05, .55, .95) the web turns it by).
fn sync_turned(k : Double) -> Double {
  k * k * (3.0 - 2.0 * k) * 2.0 * 3.141592653589793
}

///|
/// How fast it turns there (a turn's part per ms).
fn sync_turning(k : Double) -> Double {
  6.0 * k * (1.0 - k) * 2.0 * 3.141592653589793 / sync_turn_ms
}

///|
/// The mark brought to rest once all is here: from `from`, going `speed` (per ms), to `to` in `ms`, as a cubic going on
/// from that speed and slowing to none there.
struct SyncRest {
  ms : Double
  from : Double
  speed : Double
  to : Double
}

///|
/// Where it rests from a turn's state at moment `now`: the next half turn on (the mark is two arrows, the same turned
/// half round), slowing evenly from its speed (what it has to go over half its speed: in sync_settle_least to
/// sync_settle_most), not going back; at once where it is (nearly) at rest there already.
fn sync_rest(now : Double) -> SyncRest {
  let pi = 3.141592653589793
  let p = now / sync_turn_ms
  let k = p - p.floor()
  let from = sync_turned(k)
  let speed = sync_turning(k)
  if from - (from / pi).floor() * pi <= sync_rest_near && speed * sync_settle_least <= sync_rest_near {
    return { ms: 0.0, from, speed, to: from }
  }
  // a cubic from `speed` to none goes back unless what it has to go is at least a third of `speed` over its time
  let mut to = ((from - sync_rest_near) / pi).ceil() * pi
  while to <= from || speed * sync_settle_least > 3.0 * (to - from) {
    to = to + pi
  }
  let even = if speed > 0.0 { 2.0 * (to - from) / speed } else { sync_settle_most }
  let ms = dmin(sync_settle_most, dmax(sync_settle_least, even))
  { ms, from, speed, to }
}

///|
/// How far on to rest it is where its time is at `s` (0 to 1): leaving at its speed, arriving with none (a cubic
/// Hermite, from 0 to 1).
fn SyncRest::ease(self : SyncRest, s : Double) -> Double {
  let lead = if self.to > self.from { self.ms * self.speed / (self.to - self.from) } else { 0.0 }
  let s2 = s * s
  let s3 = s2 * s
  (s3 - 2.0 * s2 + s) * lead + (3.0 * s2 - 2.0 * s3)
}

///|
/// The refresh mark's parts with `left` of each drawn (1 whole, 0 none): each arrow's curve from its head, the head's
/// two strokes from their corner where the curve starts (refresh's data: curve, head, curve, head).
fn sync_drawn_back(part : Int, pts : Array[Double], left : Double) -> Array[Array[Double]] {
  if part % 2 == 0 {
    [stroke_from_start(pts, left)]
  } else {
    // (a head: its first point, its corner, its last)
    [
      stroke_from_start([pts[2], pts[3], pts[0], pts[1]], left),
      stroke_from_start([pts[2], pts[3], pts[4], pts[5]], left),
    ]
  }
}

///|
/// What the catching up said last, by its key (said as it goes), and whether it showed (only then the tick).
// kept across runs: put back as it goes (sync_key)
let sync_said : LiveMap[String, String] = LiveMap::new()

///|
// kept across runs: put back as it goes (sync_key)
let sync_seen : LiveMap[String, Bool] = LiveMap::new()

///|
/// Where each mark comes to rest once all is here, by its key, from the frame it was.
// kept across runs: put back as it goes (sync_key)
let sync_rests : LiveMap[String, SyncRest] = LiveMap::new()

///|
/// A turn of the mark (the web's SyncMark: 1.4s, eased in and out).
let sync_turn_ms : Double = 1400.0

///|
/// How long the mark takes to come to rest, at least and at most; how far on in that the arrows start to go; how near
/// rest it may be to stop where it is (of a turn's 2π).
let sync_settle_least : Double = 150.0

///|
let sync_settle_most : Double = 700.0

///|
let sync_rest_gone : Double = 0.8

///|
let sync_rest_near : Double = 0.03

///|
/// How long the tick stays once drawn, how long the arrows take to be drawn back and the tick to be drawn (begun as
/// they are mostly back), and to fade.
let sync_done_ms : Double = 1000.0

///|
let sync_back_ms : Double = 180.0

///|
let sync_tick_ms : Double = 240.0

///|
let sync_out_ms : Double = 400.0

///|
/// A key of a bar for what comes by itself (what comes to this device: sfdesk transfers.mbt), as update_key draws one:
/// round, `side` across, its `glyph` `mark` big in its middle, in its place while something comes how far it has come
/// (`coming`: coming_mark; None while nothing comes), update_key's dot, red's, where something `failed`; pressed, what
/// comes (the page's). True on its press.
pub fn progress_key(
  c : @ui.Ctx,
  key : String,
  side : Double,
  mark : Double,
  glyph : String,
  label : String,
  coming : Double?,
  failed~ : Bool,
) -> Bool {
  let t = theme()
  let id = c.id(key)
  let b = c.box(
    style=(if c.lit(id) { update_key_hot } else { update_key_box }).then(@ui.style(w=Fixed(side), h=Fixed(side))),
    id~,
    fn() {
      if coming is Some(_) {
        coming_mark(c, key, coming, mark, t.p.text)
      } else {
        icon(c, glyph, size=mark, color=t.p.text) |> ignore
      }
      if failed {
        c.layer(fn() {
          c.box(style=update_dot_at, fn() {
            c.box(style=update_dot_ring, fn() { c.box(style=update_dot_bad, fn() {  }) |> ignore })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      }
      press_ripple(c, id, side / 2.0)
    },
  )
  c.semantics(b, Button, id~, label~)
  c.clicked(id)
}

///|
/// The key: round, what it holds in its middle.
// kept across runs: a value (no field of it changes)
let update_key_box : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter")

///|
/// Under the pointer: on the hover's ground.
// kept across runs: a value (no field of it changes)
let update_key_hot : @ui.Style = update_key_box.then(@ui.css("bg=Hover"))

///|
/// What a key holds, in its middle, over what else it holds (sync_key's marks turning into each other).
// kept across runs: a value (no field of it changes)
let update_ring_at : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// What comes (a download, a newer build), drawn as an icon in an icon's place (`size`, the box the icons beside it
/// are drawn in, in `color`): a ring where those icons draw their circles (as check-circle's, 3.5 to 20.5 of their 24
/// grid, a line as wide as theirs), the accent from its top as far round as it has come (`coming`, 0 to 1; None, the
/// spinner's quarter turning: @sf.progress_spinner), a short arrow down in it. No bigger than the icons beside it: a
/// ring drawn round the download's mark instead stood out of the row, half again as wide as its neighbours.
pub fn coming_mark(c : @ui.Ctx, key : String, coming : Double?, size : Double, color : Int64) -> Unit {
  let stroke = size * icon_stroke / 24.0
  c.box(style=@ui.style(w=Fixed(size), h=Fixed(size), align=ACenter, justify=JCenter), fn() {
    progress_spinner(c, key, coming, size=size * coming_ring / 24.0 + stroke, stroke~) |> ignore
    c.layer(fn() {
      c.box(style=update_ring_at, fn() { icon(c, "download-ring", size~, color~) |> ignore }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The icons' line (design/icons: stroke-width 1.75 of 24), and the width of the circles they draw (3.5 to 20.5).
let icon_stroke : Double = 1.75

///|
let coming_ring : Double = 17.0

///|
/// Its dot: 3 in from the key's top right, 9 across on a ring of the page's ground 2 wide (Home.kt).
// kept across runs: a value (no field of it changes)
let update_dot_at : @ui.Style = @ui.style(w=Full, h=Full, pt=room(update_dot_in), pr=room(update_dot_in), align=AEnd)

///|
let update_dot_in : Double = 3.0

///|
// kept across runs: a value (no field of it changes)
let update_dot_ring : @ui.Style = @ui.style(
  w=Fixed(update_dot_side),
  h=Fixed(update_dot_side),
  radius=Full,
  bg=Bg,
  p=room(update_dot_rim),
)

///|
let update_dot_side : Double = 13.0

///|
let update_dot_rim : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let update_dot_bad : @ui.Style = @ui.css("w=Full h=Full radius=Full bg=Danger")
