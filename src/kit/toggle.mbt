// A toggle (Radix's Toggle): a button that stays pressed, the value the view's; a tap, a click, Enter or Space with
// the focus, the Activate action turn it. A toggle group (Radix's ToggleGroup): toggles in a roving group (one stop
// for Tab, the arrows moving among them), one of them pressed at most (`multiple` false: pressing the pressed one
// lets it go) or any of them.

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
/// The default look: the theme's control height, its words alone, a ground when pointed at, the faint ground when
/// pressed.
pub fn toggle_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let live = !s.disabled
  let ground = if s.on { t.faint } else { 0L }
  let bg = if ground == 0L {
    pick(live && s.pressed, doubled(t.hover), pick(live && s.hovered, t.hover, 0L))
  } else {
    tinted(c, ground, live && s.hovered, live && s.pressed)
  }
  c.box(
    dir=Row,
    h=Px(t.control_h),
    min_w=t.control_h,
    padx=10.0,
    align=ACenter,
    justify=JCenter,
    bg~,
    radius=t.radius,
    opacity=if s.disabled { disabled_alpha } else { 1.0 },
    fn() {
      c.text(s.label, size=t.font, weight=if s.on { 600 } else { 500 }, color=pick(s.on, t.fg, t.muted), wrap=false)
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
/// semantics tree; `orientation` the arrows that move along it, round unless not `wrap`. What is pressed now, and what
/// happened to the group (`changed`; `clicked` when an item was).
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
  look? : (@ui.Ctx, ToggleState) -> Unit = group_item_look,
  ground? : (@ui.Ctx, GroupState, () -> Unit) -> Unit = group_look,
) -> @ui.Changed[Array[String]] {
  let id = c.id(key)
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
      })
    })
  })
  c.semantics(gi, Group, label~, disabled~)
  let changed = now.length() != value.length() || now.iter().any(fn(v) { !value.contains(v) })
  { value: now, response: { ..any, id, changed } }
}

///|
/// A toggle group's default ground: its items side by side (or one under the other) on the faint ground, 2 apart.
pub fn group_look(c : @ui.Ctx, s : GroupState, items : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(
    dir=if s.vertical { Column } else { Row },
    pad=2.0,
    gap=2.0,
    bg=t.faint,
    radius=t.radius,
    opacity=if s.disabled { disabled_alpha } else { 1.0 },
    items,
  )
  |> ignore
}

///|
/// A toggle group's default item: words on nothing, raised on the surface when pressed.
pub fn group_item_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let h = t.control_h - 4.0
  let r = t.radius - 2.0
  let live = !s.disabled
  let bg = if s.on {
    if t.dark {
      0x636366FFL
    } else {
      t.surface
    }
  } else {
    pick(live && s.pressed, doubled(t.hover), pick(live && s.hovered, t.hover, 0L))
  }
  c.box(
    dir=Row,
    h=Px(h),
    min_w=h,
    padx=12.0,
    align=ACenter,
    justify=JCenter,
    bg~,
    radius=r,
    shadow=if s.on { 3.0 } else { 0.0 },
    shadow_color=t.shadow,
    shadow_y=1.0,
    opacity=if s.disabled { disabled_alpha } else { 1.0 },
    fn() {
      c.text(s.label, size=t.font_sm + 1.0, weight=if s.on { 600 } else { 500 }, color=pick(s.on, t.fg, t.muted), wrap=false)
      |> ignore
      focus_ring(c, s.focus_shown, s.rect, r)
    },
  )
  |> ignore
}
