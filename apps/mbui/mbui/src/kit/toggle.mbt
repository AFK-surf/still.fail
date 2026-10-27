// A toggle (Radix's Toggle): a button that stays pressed, the value the view's; a tap, a click, Enter or Space with
// the focus, the Activate action turn it. A toggle group (Radix's ToggleGroup): toggles in a roving group (one stop
// for Tab, the arrows moving among them), one of them pressed at most (`multiple` false: pressing the pressed one
// lets it go) or any of them. A group that `slide`s (still.fail's segmented choice) has one thumb behind its items,
// moving on a spring to the pressed one. Given a `lens` (liquid glass), a finger on one of its items brings the thumb
// there as a lens over the items, larger, what is under its rim bent (iOS 26's segmented control); let go, the thumb
// again, on the one chosen.

///|
/// An item of a group (a toggle group's, a radio group's): its value, its words, whether it is disabled.
pub(all) struct Item {
  value : String
  label : String
  disabled : Bool
} derive(Eq, Show)

///|
/// An item `value`, its words `label` (the value by default).
pub fn item(value : String, label? : String = "", disabled? : Bool = false) -> Item {
  { value, label: if label == "" { value } else { label }, disabled }
}

///|
/// What a toggle's look is given (a toggle group's items' too: `first` and `last` in the group).
pub(all) struct ToggleState {
  label : String
  on : Bool
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
  first : Bool
  last : Bool
}

///|
/// A toggle labelled `label` (its id `key`'s, else its label's), `pressed` or not. What it became, and what happened
/// to it.
pub fn toggle(
  c : @ui.Ctx,
  label : String,
  pressed : Bool,
  key? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, ToggleState) -> Unit = toggle_look,
) -> @ui.Changed[Bool] {
  let id = c.id(if key == "" { "\u{2}toggle/" + label } else { key })
  let r = c.interact(id, disabled~)
  let on = if r.clicked { !pressed } else { pressed }
  let st = {
    label,
    on,
    hovered: r.hovered,
    pressed: r.pressed,
    focus_shown: r.focus_shown,
    disabled,
    rect: r.rect,
    first: true,
    last: true,
  }
  let i = c.box(id=if disabled { 0 } else { id }, fn() { look(c, st) })
  c.semantics(i, Button, id~, label~, pressed=on, disabled~, actions=pick(disabled, [], [Activate]))
  { value: on, response: r.changed_to(on != pressed) }
}

///|
/// The default look (still.fail's icon buttons, as words): 32 high, its corner the theme's, its words muted until
/// pointed at; pressed, on an 8% tint of the words' colour.
pub fn toggle_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let live = !s.disabled
  let lit = live && (s.hovered || s.pressed)
  c.box(
    dir=Row,
    h=Px(32.0),
    min_w=32.0,
    padx=10.0,
    align=ACenter,
    justify=JCenter,
    bg=if s.on { @ui.alpha(t.fg, 0.08) } else { pick(lit, t.hover, 0L) },
    radius=t.radius,
    opacity=if s.disabled { 0.35 } else { 1.0 },
    fn() {
      c.text(s.label, size=t.font, weight=if s.on { 600 } else { 500 }, color=pick(s.on || lit, t.fg, t.muted), wrap=false)
      |> ignore
      focus_ring(c, s.focus_shown, s.rect, t.radius)
    },
  )
  |> ignore
}

///|
/// A toggle group's ground, round its items (its look's, beside the items' own).
pub(all) struct GroupState {
  vertical : Bool
  disabled : Bool
}

///|
/// A toggle group (see the file's head) of `items`, those of `value` pressed (its id `key`'s), named `label` for the
/// semantics tree; `orientation` the arrows that move along it, round unless not `wrap`; one pressed at most sliding
/// a thumb (`thumb` its look, given its width and height) to it when `slide`; `grow`: as wide as where it is, the
/// items sharing its width, none narrower than its look needs (its words whole: one that needs more than its share
/// keeps that, the others sharing what is left, as CSS's flex: 1); `widths`: each item as wide as its first where the
/// room is, giving way down to its second where there is less (CSS's width with its min-width: a row short of room
/// takes alike from each, none past its least), its look as wide; `lens`: the glass the thumb is under a finger
/// (`lens_grow` larger, a capsule). What is pressed now, and what happened to the group (`changed`; `clicked` when an item was).
pub fn toggle_group(
  c : @ui.Ctx,
  key : String,
  items : Array[Item],
  value : Array[String],
  multiple? : Bool = false,
  orientation? : @ui.Orientation = Horizontal,
  wrap? : Bool = true,
  disabled? : Bool = false,
  label? : String = "",
  slide? : Bool = false,
  grow? : Bool = false,
  widths? : Array[(Double, Double)] = [],
  look? : (@ui.Ctx, ToggleState) -> Unit,
  thumb? : (@ui.Ctx, Double, Double) -> Unit = group_thumb_look,
  ground? : (@ui.Ctx, GroupState, () -> Unit) -> Unit = group_look,
  lens? : @ui.Glass,
  lens_grow? : Double = 1.12,
) -> @ui.Changed[Array[String]] {
  let id = c.id(key)
  let slide = slide && !multiple
  let look = look.unwrap_or(if slide { group_slid_item_look } else { group_item_look })
  let mut now = value.copy()
  let mut any = @ui.Response::none()
  let first_on = items.search_by(fn(it) { value.contains(it.value) })
  let current = match first_on {
    Some(k) => part_id(id, k)
    None => 0
  }
  let vertical = orientation == Vertical
  let gi = c.box(style=if grow { group_item_grow } else { group_item_own }, fn() {
    c.roving(key, orientation~, wrap~, current~, fn() {
      ground(c, { vertical, disabled }, fn() {
        // the thumb behind the items, laid out over the one pressed (Ctx::cover)
        let holder = if slide { c.layer(fn() {  }) } else { -1 }
        let nodes : Array[Int] = []
        // (the item a finger is on, where the thumb is a lens)
        let mut fingered = -1
        for k, it in items {
          let iid = part_id(id, k)
          let off = disabled || it.disabled
          // (with a lens, a finger held on it is still its press: let go, chosen)
          let r = c.interact(iid, disabled=off, holds=slide && lens is Some(_))
          if r.pressed && @ui.pointing() is Finger {
            fingered = k
          }
          if r.clicked {
            any = r
            // another chosen by a finger: felt
            if !now.contains(it.value) {
              felt_tick(c, key)
            }
            if multiple {
              now = if now.contains(it.value) {
                now.filter(fn(v) { v != it.value })
              } else {
                now + [it.value]
              }
            } else {
              now = if now.contains(it.value) { [] } else { [it.value] }
            }
            if now.contains(it.value) {
              c.roving_prefer(iid)
            }
          }
          let on = now.contains(it.value)
          let st = {
            label: it.label,
            on,
            hovered: r.hovered,
            pressed: r.pressed,
            focus_shown: r.focus_shown,
            disabled: off,
            rect: r.rect,
            first: k == 0,
            last: k == items.length() - 1,
          }
          let (w, least) = match widths.get(k) {
            Some((w, least)) => (Some(@ui.Size::Px(w)), Some(least))
            None => (None, None)
          }
          let i = c.box(
            style=if grow { group_item_shared } else { group_item },
            keep=grow,
            id=if off { 0 } else { iid },
            w?=w,
            min_w?=least,
            fn() { look(c, st) },
          )
          nodes.push(i)
          if multiple {
            c.semantics(i, Button, id=iid, label=it.label, pressed=on, disabled=off, actions=pick(off, [], [Activate]))
          } else {
            c.semantics(i, Radio, id=iid, label=it.label, check=if on { On } else { Off }, disabled=off, actions=pick(
              off,
              [],
              [Activate],
            ))
          }
        }
        if slide {
          let glass = match lens {
            Some(g) if !c.glass_solid() => Some(g)
            _ => None
          }
          let held = match glass {
            Some(_) =>
              animate(c, key + "/held", if fingered >= 0 { 1.0 } else { 0.0 }, transition=@motion.motion_spring(
                0.3,
                bounce=0.3,
              ))
            None => 0.0
          }
          let chosen = items.search_by(fn(it) { now.contains(it.value) })
          let at = if glass is Some(_) && fingered >= 0 { Some(fingered) } else { chosen }
          match at {
            Some(k) => {
              c.cover(key + "/thumb", holder, nodes, k, fn(c, w, h) {
                let b = c.box(fn() { thumb(c, w, h) })
                if held > 0.0 {
                  c.look(b, @ui.look(alpha=1.0 - dmin(1.0, held)))
                }
              })
              // the lens over the items, on the thumb's way (the same item at the same moments: the same spring)
              match glass {
                Some(g) => {
                  let over = c.layer(fn() {  })
                  c.cover(key + "/lens", over, nodes, k, fn(c, w, h) {
                    if held > 0.0 {
                      // (raised off the track as it grows past it: a shadow as far as it is in the finger)
                      let full = dmin(1.0, held)
                      let shade : @ui.Shadow = Cast(lens_shadow * full, lens_shadow_y * full, c.theme().shadow)
                      let b = c.box(style=lens_capsule(w, h).then(@ui.style(shadow=shade)), glass=g, fn() {  })
                      c.look(b, @ui.look(alpha=full, scale=1.0 + (lens_grow - 1.0) * held))
                    }
                  })
                }
                None => ()
              }
            }
            None => ()
          }
        }
      })
    })
  })
  c.semantics(gi, Group, label~, disabled~)
  let changed = now.length() != value.length() || now.iter().any(fn(v) { !value.contains(v) })
  { value: now, response: { ..any, id, changed: changed } }
}

///|
/// A sliding group's lens's shadow, held all the way: its blur and how far down.
let lens_shadow : Double = 6.0

///|
let lens_shadow_y : Double = 2.0

///|
/// A sliding group's default thumb (still.fail's segmented choice): `w` by `h`, lifted out of the track (the theme's
/// lifted) with a hairline and a soft shadow.
pub fn group_thumb_look(c : @ui.Ctx, w : Double, h : Double) -> Unit {
  let t = c.theme()
  c.box(
    w=Px(w),
    h=Px(h),
    bg=t.lifted,
    radius=h / 2.0,
    border=0.5,
    border_color=t.line,
    shadow=2.0,
    shadow_color=t.shadow,
    shadow_y=0.0,
    fn() {  },
  )
  |> ignore
}

///|
/// A sliding group's default item: `group_item_look`'s words, on no ground of their own (the thumb is behind them).
pub fn group_slid_item_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let live = !s.disabled
  c.box(
    dir=Row,
    h=Px(30.0),
    min_w=30.0,
    padx=12.0,
    align=ACenter,
    justify=JCenter,
    opacity=if s.disabled { 0.4 } else { 1.0 },
    fn() {
      c.text(
        s.label,
        size=t.font,
        weight=if s.on { 500 } else { 400 },
        color=pick(s.on || (live && s.hovered), t.fg, t.muted),
        wrap=false,
      )
      |> ignore
      focus_ring(c, s.focus_shown, s.rect, 15.0)
    },
  )
  |> ignore
}

///|
/// A toggle group's default ground: its items side by side (or one under the other) on the faint ground, 2 apart.
pub fn group_look(c : @ui.Ctx, s : GroupState, items : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(
    dir=if s.vertical { Column } else { Row },
    pad=3.0,
    gap=2.0,
    bg=t.faint,
    radius=18.0,
    opacity=if s.disabled { 0.4 } else { 1.0 },
    items,
  )
  |> ignore
}

///|
/// A toggle group's default item (still.fail's segmented choice): its words, muted until pressed; pressed, raised on
/// the track (the theme's lifted) with a hairline and a soft shadow.
pub fn group_item_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let live = !s.disabled
  c.box(
    dir=Row,
    h=Px(30.0),
    min_w=30.0,
    padx=12.0,
    align=ACenter,
    justify=JCenter,
    bg=if s.on { t.lifted } else { 0L },
    radius=15.0,
    border=if s.on { 0.5 } else { 0.0 },
    border_color=t.line,
    shadow=if s.on { 2.0 } else { 0.0 },
    shadow_color=t.shadow,
    shadow_y=0.0,
    opacity=if s.disabled { 0.4 } else { 1.0 },
    fn() {
      c.text(
        s.label,
        size=t.font,
        weight=if s.on { 500 } else { 400 },
        color=pick(s.on || (live && s.hovered), t.fg, t.muted),
        wrap=false,
      )
      |> ignore
      focus_ring(c, s.focus_shown, s.rect, 15.0)
    },
  )
  |> ignore
}

///|
/// A group and its items as wide as what their looks draw, or (`grow`) the group as wide as where it is and each item
/// an equal share of it.
// kept across runs: a value (no field of it changes)
let group_item_own : @ui.Style = @ui.css("")

///|
// kept across runs: a value (no field of it changes)
let group_item_grow : @ui.Style = @ui.css("w=Full")

///|
/// An item: its look in its middle where it is taller than that (its row as tall as its tallest item's).
// kept across runs: a value (no field of it changes)
let group_item : @ui.Style = @ui.css("justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let group_item_shared : @ui.Style = group_item.then(group_item_grow)
