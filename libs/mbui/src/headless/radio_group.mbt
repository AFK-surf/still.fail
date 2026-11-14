// The radio group and the tab list: a control of several parts, one among them chosen at a time. The group says it is a
// radio group (`RadioGroup`) or a tab list (`TabList`) called by its label; each item made by `RadioGroup::item` says it
// is a radio (`Radio`, checked `On` or `Off`) or a tab (`Tab`, `selected` true or false) called by its own label.
//
// Roving focus and keys: Tab stops at one item of the group alone — the chosen one while it is enabled, or the first
// enabled item when none matches `chosen()`. While any item of the group has the keyboard's focus, the arrow keys along
// `axis` (`Horizontal`: ← and →; `Vertical`: ↑ and ↓; `Both`: all four) step to the enabled item before or after,
// wrapping around the ends, and Home and End go to the first and the last enabled item, each choosing what it comes to
// (`choose` told its key when it is not chosen already) and moving visible focus there. Pressing an item (by the
// pointer, by Space or Enter while it has focus, or by a screen reader's Activate) chooses it when it is not chosen
// already, and does nothing when it already is or while disabled.

///|
/// What the group and its items are to a screen reader: a `Radio` group (`RadioGroup` of `Radio` items) or a `Tab`
/// list (`TabList` of `Tab` items).
#derive(Eq, Debug)
pub(all) enum GroupKind {
  Radio
  Tab
}

///|
/// Which arrow keys step along the group: `Horizontal` (← and →), `Vertical` (↑ and ↓), or `Both` (all four).
#derive(Eq, Debug)
pub(all) enum GroupAxis {
  Horizontal
  Vertical
  Both
}

///|
/// One registered item of a `RadioGroup[K]`.
priv struct GroupEntry[K] {
  node : @view.View
  key : () -> K
  off : () -> Bool
}

///|
/// A radio group or tab list handed to its look to register its items with `RadioGroup::item`.
pub struct RadioGroup[K] {
  priv kind : GroupKind
  priv selected : Bool
  priv now : () -> K
  priv choose : (K) -> Unit
  priv off : () -> Bool
  priv items : Array[GroupEntry[K]]
  priv building : Ref[Bool]
  priv stops : Array[(@view.View, () -> Unit)]
}

///|
/// Whether the whole group is disabled (as its caller says).
pub fn[K] RadioGroup::disabled(self : RadioGroup[K]) -> Bool {
  (self.off)()
}

///|
/// One item of a `RadioGroup[K]` as its look reads it: each a reading, followed where a binding reads it.
pub struct RadioItem {
  priv node : @view.View
  priv now : () -> Bool
  priv off : () -> Bool
}

///|
/// Whether this item is the chosen one now.
pub fn RadioItem::chosen(self : RadioItem) -> Bool {
  (self.now)()
}

///|
/// Whether this item is disabled (either the group or the item itself is disabled).
pub fn RadioItem::disabled(self : RadioItem) -> Bool {
  (self.off)()
}

///|
/// Whether a finger or the pointer is held on this item now (View::pressed).
pub fn RadioItem::pressed(self : RadioItem) -> Bool {
  self.node.pressed()
}

///|
/// Whether a pointer rests over this item now (View::pointed): a mouse's, never a finger's.
pub fn RadioItem::hovered(self : RadioItem) -> Bool {
  self.node.pointed()
}

///|
/// Whether this item has the keyboard's focus and that shows (View::focus_shown).
pub fn RadioItem::focus_shown(self : RadioItem) -> Bool {
  self.node.focus_shown()
}

///|
/// Pressed now, for what a look adds that ends in a press: asked of the tree as a press delivered to the item's node
/// (View::press).
pub fn RadioItem::press(self : RadioItem) -> Unit {
  self.node.press() |> ignore
}

///|
/// The key codes that step along a group (`ui`'s `key_code_*`).
let group_key_left : Int = 3

///|
let group_key_right : Int = 4

///|
let group_key_up : Int = 5

///|
let group_key_down : Int = 6

///|
let group_key_home : Int = 8

///|
let group_key_end : Int = 9

///|
/// A radio group or tab list in `parent`, called `label` (what a screen reader says), `chosen` saying which key `K` is
/// chosen now and `choose` told the key chosen by a press or an arrow key; `kind` whether it is a `Radio` group or a
/// `Tab` list; `axis` which arrow keys step along it; `disabled` while the whole group takes no press and no focus.
/// `look` is given the group's node and the `RadioGroup[K]` with which its items are made (`RadioGroup::item`, directly
/// or inside `View::each`). The group's node.
#callsite(autofill(loc))
pub fn[K : Eq] radio_group(
  parent : @view.View,
  label : () -> String,
  chosen : () -> K,
  choose : (K) -> Unit,
  look : (@view.View, RadioGroup[K]) -> Unit,
  kind? : GroupKind = Radio,
  axis? : GroupAxis = Horizontal,
  shown? : () -> Bool = fn() { true },
  selected? : Bool = false,
  in_node? : Bool = false,
  disabled? : () -> Bool = fn() { false },
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  let setup = fn(v : @view.View) {
    let items : Array[GroupEntry[K]] = []
    let building = Ref(true)
    let stops : Array[(@view.View, () -> Unit)] = []
    let rg : RadioGroup[K] = { kind, selected, now: chosen, choose, off: disabled, items, building, stops }
    look(v, rg)
    building.val = false
    for s in stops {
      if s.0.alive() {
        (s.1)()
      }
    }
    v
    .says(By(fn() {
      if !shown() {
        None
      } else {
        Some(
          match kind {
            Radio => @view.said(RadioGroup, label=label())
            Tab => @view.said(TabList, label=label())
          },
        )
      }
    }))
    .on_key(fn(k) {
      if disabled() || k.mods != 0 {
        return false
      }
      let live = items.filter(fn(e) { e.node.alive() && !(e.off)() })
      let n = live.length()
      if n == 0 {
        return false
      }
      let at = live.search_by(fn(e) { e.node.focused() })
      guard at is Some(i) else { return false }
      let prev = match axis {
        Horizontal => k.code == group_key_left
        Vertical => k.code == group_key_up
        Both => k.code == group_key_left || k.code == group_key_up
      }
      let next = match axis {
        Horizontal => k.code == group_key_right
        Vertical => k.code == group_key_down
        Both => k.code == group_key_right || k.code == group_key_down
      }
      let to = if prev {
        Some((i + n - 1) % n)
      } else if next {
        Some((i + 1) % n)
      } else if k.code == group_key_home {
        Some(0)
      } else if k.code == group_key_end {
        Some(n - 1)
      } else {
        None
      }
      match to {
        Some(j) => {
          let target = live[j]
          let next_key = (target.key)()
          if next_key != chosen() {
            choose(next_key)
          }
          target.node.ask_focus(visible=true) |> ignore
          true
        }
        None => false
      }
    })
    |> ignore
  }
  if in_node {
    setup(parent)
    parent
  } else {
    parent.box(loc~, made_for=made_for.unwrap_or(loc), setup)
  }
}

///|
/// An item of `self` in `parent` (which may be the group's node or a slot/container inside it), identified by `key`
/// and read out as `label`. `look` is given the item's node and its `RadioItem` state. `disabled` disables this item
/// alone; `space_only` limits keyboard activation on the focused item to Space (leaving Enter to a surrounding form);
/// `slop` attaches a pointer gesture of that touch slop whose tap or release on the item presses it (for sliding-thumb
/// strips where a finger moved off and back onto an item still chooses it on release). The item's node.
#callsite(autofill(loc))
pub fn[K : Eq] RadioGroup::item(
  self : RadioGroup[K],
  parent : @view.View,
  key : () -> K,
  label : () -> String,
  look : (@view.View, RadioItem) -> Unit,
  disabled? : () -> Bool = fn() { false },
  space_only? : Bool = false,
  slop? : Double,
  made_for? : SourceLoc,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(loc~, made_for=made_for.unwrap_or(loc), fn(v) {
    let off = fn() { (self.off)() || disabled() }
    let able = fn() { !off() }
    let on = fn() { (self.now)() == key() }
    self.items.push({ node: v, key, off: disabled })
    v.owns(fn() {
      self.items.retain(fn(e) { e.node.id() != v.id() })
      self.stops.retain(fn(s) { s.0.id() != v.id() })
    })
    |> ignore
    look(v, { node: v, now: on, off })
    if slop is Some(s) {
      let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
      v.gesture(
        s,
        tap=fn(d) { if on_it(d) { v.press() |> ignore } },
        drag=fn(d) { if d.kind == Up && on_it(d) { v.press() |> ignore } },
      )
      |> ignore
    }
    let stop = fn() {
      let cur = (self.now)()
      let mut any_on = false
      let mut first_id : @view.NodeId? = None
      for e in self.items {
        if e.node.alive() {
          let e_off = (e.off)()
          let e_key = (e.key)()
          if !e_off {
            if first_id is None {
              first_id = Some(e.node.id())
            }
            if e_key == cur {
              any_on = true
            }
          }
        }
      }
      if off() {
        false
      } else if on() {
        true
      } else if any_on {
        false
      } else {
        first_id == Some(v.id())
      }
    }
    let keys = if space_only { @view.focus_space } else { @view.focus_enter | @view.focus_space }
    v
    .presses(By(able))
    .focusable(By(able), keys~)
    .says(By(fn() {
      let now = on()
      Some(
        match self.kind {
          Radio =>
            if self.selected {
              @view.said(Radio, label=label(), selected=now)
            } else {
              @view.said(Radio, label=label(), check=if now { On } else { Off })
            }
          Tab => @view.said(Tab, label=label(), selected=now)
        },
      )
    }))
    .on_press(fn() {
      if !off() {
        let k = key()
        if (self.now)() != k {
          (self.choose)(k)
        }
      }
    })
    |> ignore
    let bind_stop = fn() { v.tab_stop(By(stop)) |> ignore }
    self.stops.push((v, bind_stop))
    if !self.building.val {
      for s in self.stops {
        if s.0.alive() {
          (s.1)()
        }
      }
    }
  })
}
