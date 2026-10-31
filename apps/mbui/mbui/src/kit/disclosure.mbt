// What shows a part and hides the rest: a collapsible (Radix's Collapsible: its trigger opens and closes its content,
// which grows and shrinks to its height), an accordion (Radix's Accordion: a column of collapsibles, their triggers one
// roving group, Up and Down moving among them; one open at a time unless `multiple`), tabs (Radix's Tabs: a roving
// group of tabs, the arrows choosing as they move, the chosen one's panel shown), a scroll area (Radix's ScrollArea:
// what is taller than its room scrolls in it, by the wheel, a drag and the keys, with a bar while it moves). Whether
// each is open, and which tab is chosen, are the view's.

///|
/// What a collapsible's or an accordion item's trigger look is given: its words, open, pointed at, focus shown,
/// disabled, where it was last frame.
pub(all) struct TriggerState {
  label : String
  open : Bool
  hovered : Bool
  focus_shown : Bool
  disabled : Bool
}

///|
/// `key`'s collapsible (see the file's head), `open` or not, its trigger saying `label`, what `body` builds shown
/// while open. Whether it is open now.
pub fn collapsible(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  label : String,
  body : () -> Unit,
  disabled? : Bool = false,
  look? : (@ui.Ctx, TriggerState) -> Unit = trigger_look,
) -> @ui.Changed[Bool] {
  let id = c.id(key)
  let r = c.interact(id, disabled~)
  let now = if r.clicked { !open } else { open }
  c.box(fn() {
    let i = c.box(id=pick(disabled, 0, id), fn() {
      look(c, { label, open: now, hovered: r.hovered, focus_shown: r.focus_shown, disabled })
    })
    c.semantics(i, Button, id~, label~, expanded=now, disabled~, actions=pick(disabled, [], [@ui.Action::Activate]))
    unfolding(c, key, now, label, body)
  })
  |> ignore
  { value: now, response: r.changed_to(now != open) }
}

///|
/// How long a collapsible's content takes to grow in (ms), and to shrink away: a tween each.
pub let collapsible_open_ms : Double = 200.0

///|
pub let collapsible_close_ms : Double = 160.0

///|
/// What `body` builds, while `open` (and while it closes), its height growing from nothing to its own and back by
/// `presence`; a region named `label` for the semantics tree.
fn unfolding(c : @ui.Ctx, key : String, open : Bool, label : String, body : () -> Unit) -> Unit {
  let p = presence(c, key + "/content", open, enter=@motion.tween(collapsible_open_ms, ease=Out), exit=@motion.tween(collapsible_close_ms, ease=Out))
  if !p.built {
    return
  }
  let cid = c.id(key + "/content")
  let k = if p.t > 1.0 { 1.0 } else if p.t < 0.0 { 0.0 } else { p.t }
  let full = match c.rect_of(cid) {
    Some((_, _, _, h)) => Some(h)
    None => None
  }
  // all the way open: as tall as it is (it may grow); on its way, cut to its share of its height
  let h : @ui.Size = match full {
    Some(fh) if k < 1.0 => Px(fh * k)
    // (not yet laid out: its first frame, at 0 of its way; its presence moving draws the next)
    None if k < 1.0 => Px(0.0)
    _ => Auto
  }
  // (on its way, what shows of it fading to where it is cut, by each pixel: @ui.cut_soft; cut there too, so nothing of
  // it past its room is pressed)
  c.box(h~, clip=true, fn() {
    let i = c.box(id=cid, fn() {
      if p.leaving() {
        c.hidden_from_semantics(body)
      } else {
        body()
      }
    })
    match full {
      Some(fh) if k < 1.0 => c.cut_to_top(i, fh * k, soft=@ui.cut_soft(fh * k, fh * (1.0 - k)))
      _ => ()
    }
    if !p.leaving() {
      c.semantics(i, Region, label~)
    }
  })
  |> ignore
}

///|
/// A collapsible's (and an accordion item's) trigger's default look (still.fail's rows): its words, a chevron that
/// turns as it opens, the hover's ground pointed at.
pub fn trigger_look(c : @ui.Ctx, s : TriggerState) -> Unit {
  let t = c.theme()
  c.box(
    dir=Row,
    min_h=40.0,
    padx=10.0,
    gap=8.0,
    align=ACenter,
    radius=t.radius,
    bg=pick(s.hovered && !s.disabled, t.hover, 0L),
    opacity=pick(s.disabled, 0.45, 1.0),
    fn() {
      c.box(w=Fill(1.0), fn() { c.text(s.label, size=t.font, weight=500, wrap=false) |> ignore }) |> ignore
      chevron(c, s.open, t.muted)
      focus_ring(c, s.focus_shown, t.radius)
    },
  )
  |> ignore
}

///|
/// An accordion's item: its value, its trigger's words, what it shows.
pub(all) struct Fold {
  value : String
  label : String
  body : () -> Unit
  disabled : Bool
}

///|
/// An accordion item `value`, its trigger saying `label`, showing what `body` builds.
pub fn fold(value : String, label : String, body : () -> Unit, disabled? : Bool = false) -> Fold {
  { value, label, body, disabled }
}

///|
/// `key`'s accordion (see the file's head) of `items`, those of `value` open; one at a time unless `multiple`
/// (`collapsible`: the open one closes when its trigger is pressed again). What is open now.
pub fn accordion(
  c : @ui.Ctx,
  key : String,
  items : Array[Fold],
  value : Array[String],
  multiple? : Bool = false,
  collapsible? : Bool = true,
  label? : String = "",
  look? : (@ui.Ctx, TriggerState) -> Unit = trigger_look,
) -> @ui.Changed[Array[String]] {
  let t = c.theme()
  let id = c.id(key)
  let mut now = value.copy()
  let gi = c.box(fn() {
    c.roving(key, orientation=Vertical, wrap=true, fn() {
      for k, it in items {
        let iid = part_id(id, k)
        let r = c.interact(iid, disabled=it.disabled)
        let was = now.contains(it.value)
        if r.clicked {
          now = if was {
            if multiple || collapsible {
              now.filter(fn(v) { v != it.value })
            } else {
              now
            }
          } else if multiple {
            now + [it.value]
          } else {
            [it.value]
          }
        }
        let on = now.contains(it.value)
        if k > 0 {
          c.box(h=Px(1.0), bg=t.line, fn() {  }) |> ignore
        }
        let i = c.box(id=pick(it.disabled, 0, iid), fn() {
          look(c, { label: it.label, open: on, hovered: r.hovered, focus_shown: r.focus_shown, disabled: it.disabled })
        })
        c.semantics(i, Button, id=iid, label=it.label, expanded=on, disabled=it.disabled, actions=pick(it.disabled, [], [
          @ui.Action::Activate,
        ]))
        unfolding(c, key + "/" + it.value, on, it.label, fn() {
          c.box(padx=10.0, pb=12.0, fn() { (it.body)() }) |> ignore
        })
      }
    })
  })
  c.semantics(gi, Group, label~)
  let changed = now.length() != value.length() || now.iter().any(fn(v) { !value.contains(v) })
  { value: now, response: { ..@ui.Response::none(), id, changed: changed } }
}

///|
/// `key`'s tabs (see the file's head): `tabs` side by side (one under the other when `orientation` is Vertical),
/// `value` chosen, its panel what `panel` builds for it; the arrows choose as they move unless `manual` (then Enter or
/// Space does). Which is chosen now.
pub fn tabs(
  c : @ui.Ctx,
  key : String,
  tabs : Array[Item],
  value : String,
  panel : (String) -> Unit,
  orientation? : @ui.Orientation = Horizontal,
  manual? : Bool = false,
  label? : String = "",
  look? : (@ui.Ctx, ToggleState) -> Unit = group_item_look,
  ground? : (@ui.Ctx, GroupState, () -> Unit) -> Unit = group_look,
) -> @ui.Changed[String] {
  let id = c.id(key)
  let mut now = value
  let vertical = orientation == Vertical
  let current = match tabs.search_by(fn(it) { it.value == value }) {
    Some(k) => part_id(id, k)
    None => 0
  }
  c.box(dir=pick(vertical, Row, Column), gap=12.0, fn() {
    // the list as wide as its tabs
    c.box(dir=pick(vertical, Column, Row), fn() {
      let li = c.box(fn() {
        c.roving(key, orientation~, wrap=true, current~, fn() {
          ground(c, { vertical, disabled: false }, fn() {
            for k, it in tabs {
              let tid = part_id(id, k)
              let r = c.interact(tid, disabled=it.disabled)
              if r.clicked || (!manual && !it.disabled && c.focus_roved_to(tid)) {
                now = it.value
                c.roving_prefer(tid)
              }
              let on = now == it.value
              let i = c.box(id=pick(it.disabled, 0, tid), fn() {
                look(c, {
                  label: it.label,
                  on,
                  hovered: r.hovered,
                  pressed: r.pressed,
                  focus_shown: r.focus_shown,
                  disabled: it.disabled,
                  first: k == 0,
                  last: k == tabs.length() - 1,
                })
              })
              c.semantics(i, Tab, id=tid, label=it.label, selected=on, disabled=it.disabled, actions=pick(it.disabled, [], [
                @ui.Action::Activate,
              ]))
            }
          })
        })
      })
      c.semantics(li, TabList, label~)
    })
    |> ignore
    let shown = match tabs.search_by(fn(it) { it.value == now }) {
      Some(k) => tabs[k].label
      None => ""
    }
    let pi = c.box(w=Fill(1.0), fn() { panel(now) })
    c.semantics(pi, TabPanel, label=shown)
  })
  |> ignore
  { value: now, response: { ..@ui.Response::none(), id, changed: now != value } }
}

///|
/// `key`'s scroll area (see the file's head), `h` high, what `body` builds scrolling in it when it is taller; named
/// `label` for the semantics tree.
pub fn scroll_area(c : @ui.Ctx, key : String, h : Double, body : () -> Unit, label? : String = "") -> Unit {
  let i = c.box(h=Px(h), clip=true, fn() {
    c.list(key, 1, h, fn(_) { body() }, h=Fill(1.0)) |> ignore
  })
  c.semantics(i, ScrollArea, label~)
}
