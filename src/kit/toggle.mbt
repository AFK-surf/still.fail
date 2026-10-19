// A toggle (Radix's Toggle): a button that stays pressed, the value the view's; a tap, a click, Enter or Space with
// the focus, the Activate action turn it. A toggle group (Radix's ToggleGroup): toggles in a roving group (one stop
// for Tab, the arrows moving among them), one of them pressed at most (`multiple` false: pressing the pressed one
// lets it go) or any of them. A group that `slide`s (still.fail's segmented choice) has one thumb behind its items,
// moving on a spring to the pressed one.

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
  { value: on, response: r.changed_to(told(c, on != pressed)) }
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
/// a thumb (`thumb` its look, given its width and height) to it when `slide`. What is pressed now, and what happened to
/// the group (`changed`; `clicked` when an item was).
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
  look? : (@ui.Ctx, ToggleState) -> Unit,
  thumb? : (@ui.Ctx, Double, Double) -> Unit = group_thumb_look,
  ground? : (@ui.Ctx, GroupState, () -> Unit) -> Unit = group_look,
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
  let gi = c.box(fn() {
    c.roving(key, orientation~, wrap~, current~, fn() {
      ground(c, { vertical, disabled }, fn() {
        // the thumb behind the items, laid out over the one pressed (Ctx::cover)
        let holder = if slide { c.layer(fn() {  }) } else { -1 }
        let nodes : Array[Int] = []
        for k, it in items {
          let iid = part_id(id, k)
          let off = disabled || it.disabled
          let r = c.interact(iid, disabled=off)
          if r.clicked {
            any = r
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
          let i = c.box(id=if off { 0 } else { iid }, fn() { look(c, st) })
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
          match items.search_by(fn(it) { now.contains(it.value) }) {
            Some(k) => c.cover(key + "/thumb", holder, nodes, k, thumb)
            None => ()
          }
        }
      })
    })
  })
  c.semantics(gi, Group, label~, disabled~)
  let changed = now.length() != value.length() || now.iter().any(fn(v) { !value.contains(v) })
  { value: now, response: { ..any, id, changed: told(c, changed) } }
}

///|
/// A sliding group's default thumb (still.fail's segmented choice): `w` by `h`, raised on the page's ground with a
/// hairline and a soft shadow.
pub fn group_thumb_look(c : @ui.Ctx, w : Double, h : Double) -> Unit {
  let t = c.theme()
  c.box(
    w=Px(w),
    h=Px(h),
    bg=pick(t.dark, t.surface, t.bg),
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
/// the page's ground with a hairline and a soft shadow.
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
    bg=if s.on { pick(t.dark, t.surface, t.bg) } else { 0L },
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
