// Menus (Radix's Menu, what DropdownMenu, ContextMenu, Menubar and Select stand on): a panel of entries over the page,
// put by what opened it. Its items are one roving group: Up and Down move along them (not round), Home and End to the
// ends, letters typed go to the first whose words start with them; the pointer moving over one moves the focus to it.
// Enter, Space, a tap or a click choose one, and the menu closes. A submenu opens by Right (Left right to left), Enter,
// a click or the pointer coming to its item, its first item focused when the keyboard opened it; Left and Escape close
// it alone. Escape, the back and a press outside close the menu. Opened by the pointer, the focus is on the panel
// (nothing lit) until a key or the pointer moves it.

///|
/// What an entry of a menu is: an item that does something, one turned on or off (a checkbox item), one of a choice
/// (a radio item: on or not), a line between parts, words heading a part, a submenu's item.
pub(all) enum EntryKind {
  Action
  Check(Bool)
  Choice(Bool)
  Rule
  Heading
  Sub(Array[Entry])
}

///|
/// A menu's entry: what it is, its value (what choosing it reports), its words, its shortcut's words ("" none),
/// whether it is disabled.
pub(all) struct Entry {
  kind : EntryKind
  value : String
  label : String
  shortcut : String
  disabled : Bool
}

///|
/// An item `value` (its words `label`, the value by default) that does something.
pub fn menu_item(value : String, label? : String = "", shortcut? : String = "", disabled? : Bool = false) -> Entry {
  { kind: Action, value, label: if label == "" { value } else { label }, shortcut, disabled }
}

///|
/// An item `value` turned on or off (`checked`): choosing it reports it; the view turns it.
pub fn menu_check(
  value : String,
  checked : Bool,
  label? : String = "",
  shortcut? : String = "",
  disabled? : Bool = false,
) -> Entry {
  { kind: Check(checked), value, label: if label == "" { value } else { label }, shortcut, disabled }
}

///|
/// An item `value` of a choice, `checked` if it is the one chosen.
pub fn menu_radio(value : String, checked : Bool, label? : String = "", disabled? : Bool = false) -> Entry {
  { kind: Choice(checked), value, label: if label == "" { value } else { label }, shortcut: "", disabled }
}

///|
/// A line between parts of a menu.
pub fn menu_separator() -> Entry {
  { kind: Rule, value: "", label: "", shortcut: "", disabled: true }
}

///|
/// Words heading a part of a menu.
pub fn menu_label(text : String) -> Entry {
  { kind: Heading, value: "", label: text, shortcut: "", disabled: true }
}

///|
/// An item `label` that opens a submenu of `entries`.
pub fn menu_sub(label : String, entries : Array[Entry], disabled? : Bool = false) -> Entry {
  { kind: Sub(entries), value: "", label, shortcut: "", disabled }
}

///|
/// What a menu reports: whether it is open now, and the value of the item chosen (it closes then).
pub(all) struct Menu {
  open : Bool
  chosen : String?
  /// still drawn: open, or going out (its exit playing), so what opened it is kept where the menu hangs on it
  shown : Bool
}

///|
/// What a menu item's look is given: the entry, lit (the focus is on it), its submenu open; `hot`: lit for the person
/// to see, the pointer over it (a finger on it) or the keyboard's focus shown on it, not the focus a menu opened by a
/// touch puts on its first item (Android's menus light an item only while it is pressed).
pub(all) struct MenuItemState {
  entry : Entry
  lit : Bool
  open : Bool
  hot : Bool
  /// what it is pressed as (its row's id): for what the look draws of a press itself (a ripple)
  id : Int
}

///|
/// What a panel reports to what holds it: the item chosen, and whether Left (Right to left: Right) asked to close it
/// (a submenu's).
priv struct PanelOut {
  chosen : String?
  back : Bool
}

///|
/// A heading among a menu's items (Radix's Label), as mbui draws one: small, quiet, 10 in, 6 over and 4 under it.
pub fn menu_heading_look(c : @ui.Ctx, label : String) -> Unit {
  c.box(padx=10.0, pt=6.0, pb=4.0, fn() {
    c.text(label, size=c.theme().font_sm, color=c.theme().muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
/// A line between parts of a menu, as mbui draws one: the words' colour faintly (in dark the panel is lighter than the
/// page: its line a groove), 6 over and under it, 4 in.
pub fn menu_rule_look(c : @ui.Ctx) -> Unit {
  c.box(pady=6.0, padx=4.0, fn() {
    c.box(h=Px(1.0), w=Fill(1.0), bg=@ui.alpha(c.theme().fg, 0.12), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// The panel of menu `key` (built in its layer): by `anchor` (a rectangle in the window) on its `side`, `offset`
/// away (by its size last frame), named `label`; a submenu's when `depth` > 0; a listbox (a select's) when `listbox`.
fn menu_panel(
  c : @ui.Ctx,
  key : String,
  entries : Array[Entry],
  anchor : (Double, Double, Double, Double),
  side : @ui.Side,
  along : @ui.Along,
  offset : Double,
  shows : @ui.Look,
  label : String,
  depth : Int,
  listbox : Bool,
  min_w : Double,
  look : (@ui.Ctx, Double, () -> Unit) -> Unit,
  item_look : (@ui.Ctx, MenuItemState) -> Unit,
  heading_look? : (@ui.Ctx, String) -> Unit = menu_heading_look,
  rule_look? : (@ui.Ctx) -> Unit = menu_rule_look,
) -> PanelOut {
  let pid = c.id(key + "/panel")
  let ids = entries.mapi(fn(k, _) { part_id(pid, k) })
  let live = fn(k : Int) {
    let e = entries[k]
    !e.disabled &&
    (match e.kind {
      Rule | Heading => false
      _ => true
    })
  }
  let mine = c.has_focus(pid) || ids.iter().any(fn(id) { c.has_focus(id) })
  let mut sub = kit.val.subs.get(pid).unwrap_or(-1)
  let mut chosen : String? = None
  let mut back = false
  if mine {
    // from the panel itself, Down and Home to the first, Up and End to the last
    if c.has_focus(pid) {
      let order = if c.take_key(@ui.key_code_down) || c.take_key(@ui.key_code_home) {
        Some(false)
      } else if c.take_key(@ui.key_code_up) || c.take_key(@ui.key_code_end) {
        Some(true)
      } else {
        None
      }
      match order {
        Some(last) => {
          let mut k = if last { entries.length() - 1 } else { 0 }
          while k >= 0 && k < entries.length() && !live(k) {
            k = if last { k - 1 } else { k + 1 }
          }
          if k >= 0 && k < entries.length() {
            c.focus_on(ids[k], visible=true)
          }
        }
        None => ()
      }
    }
    // a submenu's: Left (right to left, Right) goes back
    if depth > 0 && c.take_key(if c.rtl() { @ui.key_code_right } else { @ui.key_code_left }) {
      back = true
    }
    typeahead(c, pid, entries, ids, live)
  }
  let (ww, _) = c.window_size()
  c.focusable(pid, keys=0)
  // by its trigger, by its size as laid out (its first frame too), growing out of the side it went on (as this frame
  // lays it out; its first, the side asked for); its entries within the window (in_room: scrolling only where they are
  // more than it holds)
  let went = went_side(c, pid, anchor, side, along, offset)
  let i = c.box(id=pid, max_w=ww - 16.0, fn() {
    look(c, min_w, fn() {
      in_room(c, { side: went, room: c.place_most(), panel: pid }, key=key + "/room", fn() {
        c.roving(key + "/items", orientation=Vertical, wrap=false, fn() {
          for n, e in entries {
            match e.kind {
              Rule => rule_look(c)
              Heading => heading_look(c, e.label)
              _ => {
                let iid = ids[n]
                let r = c.interact(iid, disabled=e.disabled)
                // the pointer moving onto it: the focus (unseen), and its submenu open or another's closed
                if r.hovered && pointer_moved(c) && !e.disabled {
                  if !c.has_focus(iid) {
                    c.focus_on(iid)
                  }
                  sub = if e.kind is Sub(_) { n } else { -1 }
                }
                let opens = if c.rtl() { @ui.key_code_left } else { @ui.key_code_right }
                match e.kind {
                  Sub(_) =>
                    if r.clicked || (c.has_focus(iid) && c.take_key(opens)) {
                      sub = n
                    }
                  _ => if r.clicked { chosen = Some(e.value) }
                }
                let on = sub == n && e.kind is Sub(_)
                let row = c.box(id=if e.disabled { 0 } else { iid }, fn() {
                  item_look(c, {
                    entry: e,
                    lit: c.has_focus(iid) || (on && !mine),
                    open: on,
                    hot: (c.has_focus(iid) && (c.focus_shown(iid) || r.hovered)) || (on && !mine),
                    id: iid,
                  })
                })
                let actions = pick(e.disabled, [], [@ui.Action::Activate])
                match e.kind {
                  Check(v) =>
                    c.semantics(row, MenuItemCheckbox, id=iid, label=e.label, check=pick(v, On, Off), disabled=e.disabled, actions~)
                  Choice(v) =>
                    if listbox {
                      c.semantics(row, Option, id=iid, label=e.label, selected=v, disabled=e.disabled, actions~)
                    } else {
                      c.semantics(row, MenuItemRadio, id=iid, label=e.label, check=pick(v, On, Off), disabled=e.disabled, actions~)
                    }
                  Sub(_) =>
                    c.semantics(row, MenuItem, id=iid, label=e.label, expanded=on, disabled=e.disabled, actions~)
                  _ => c.semantics(row, MenuItem, id=iid, label=e.label, disabled=e.disabled, actions~)
                }
                // its submenu, beside it
                match e.kind {
                  Sub(children) if on => {
                    let by_key = c.focus_shown(iid)
                    let sk = key + "/" + n.to_string()
                    let mut out : PanelOut = { chosen: None, back: false }
                    let o = c.overlay(sk, anchor=iid, initial_focus=if by_key { first_item(c, sk, children) } else { 0 }, fn() {
                      out = menu_panel(
                        c,
                        sk,
                        children,
                        c.rect_of(iid).unwrap_or(anchor),
                        if c.rtl() { Left } else { Right },
                        Start,
                        -4.0,
                        @ui.still_look,
                        e.label,
                        depth + 1,
                        false,
                        min_w,
                        look,
                        item_look,
                        heading_look~,
                        rule_look~,
                      )
                    })
                    if out.chosen is Some(_) {
                      chosen = out.chosen
                    }
                    if out.back || o.dismissed is Some(_) {
                      sub = -1
                      c.focus_on(iid, visible=true)
                    }
                  }
                  _ => ()
                }
              }
            }
          }
        })
      })
      |> ignore
    })
  })
  c.place_by_size(i, fn(pw, ph) {
    let (x, y, _) = c.place(anchor, pw, ph, side~, along~, offset~)
    (x, y)
  })
  c.semantics(i, if listbox { Listbox } else { Menu }, id=pid, label~)
  c.look(i, grown_from(shows, went, along))
  kit.val.subs[pid] = sub
  { chosen, back }
}

///|
/// How long letters typed one after another find an entry together (Radix's typeahead: a second).
pub let typeahead_ms : Double = 1000.0

///|
/// Letters typed with the focus in panel `pid`: the focus to the first live entry after it whose words start with
/// what was typed in the last second.
fn typeahead(c : @ui.Ctx, pid : Int, entries : Array[Entry], ids : Array[Int], live : (Int) -> Bool) -> Unit {
  let mut typed = match kit.val.typed.get(pid) {
    Some(s) if c.within(pid, typeahead_ms) => s
    _ => ""
  }
  let mut any = false
  for ch in "abcdefghijklmnopqrstuvwxyz0123456789" {
    if c.take_key(@ui.key_of_char(ch)) || c.take_key(@ui.key_of_char(ch), mods=@ui.mod_shift_key) {
      typed = typed + ch.to_string()
      any = true
    }
  }
  if !any {
    return
  }
  kit.val.typed[pid] = typed
  c.mark(pid)
  let n = entries.length()
  let mut at = -1
  for k, id in ids {
    if c.has_focus(id) {
      at = k
    }
  }
  // the same letter again moves on to the next it starts; more letters stay on the one that matches
  let first = typed.view(start_offset=0, end_offset=1).to_string()
  let same = typed.iter().all(fn(ch) { ch.to_string() == first })
  let want = if same { first } else { typed }
  let from = if same { at + 1 } else { imax(at, 0) }
  for j in 0..<n {
    let k = (from + j) % n
    if live(k) && lower(entries[k].label).has_prefix(want) {
      c.focus_on(ids[k], visible=true)
      return
    }
  }
}

///|
/// The id of panel `key`'s first live item (-1 none): where the keyboard's opening puts the focus.
fn first_item(c : @ui.Ctx, key : String, entries : Array[Entry]) -> Int {
  let pid = c.id(key + "/panel")
  for k, e in entries {
    match e.kind {
      Rule | Heading => ()
      _ => if !e.disabled { return part_id(pid, k) }
    }
  }
  -1
}

///|
/// `s` with its ASCII letters lower case.
fn lower(s : String) -> String {
  let b = StringBuilder()
  for ch in s {
    b.write_char(if ch >= 'A' && ch <= 'Z' { (ch.to_int() + 32).unsafe_to_char() } else { ch })
  }
  b.to_string()
}

///|
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// `key`'s dropdown menu (Radix's DropdownMenu, see the file's head), `open` or not, of `entries`, by the trigger
/// `trigger` (its id: the view's button, which opens it; `at`: by this rectangle instead); Down on the trigger opens
/// it too, and the keyboard's opening focuses its first item. `scrim`: the page under it dimmed so (in and out over 200
/// ms); it comes by `enter` and goes by `exit` (still.fail's small panel's by default: popover.mbt pop_in, pop_out).
/// Whether it is open now, and what was chosen.
pub fn dropdown_menu(
  c : @ui.Ctx,
  key : String,
  open : Bool,
  trigger : Int,
  entries : Array[Entry],
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = 4.0,
  label? : String = "",
  min_w? : Double = 180.0,
  look? : (@ui.Ctx, Double, () -> Unit) -> Unit = menu_look,
  item_look? : (@ui.Ctx, MenuItemState) -> Unit = menu_item_look,
  heading_look? : (@ui.Ctx, String) -> Unit = menu_heading_look,
  rule_look? : (@ui.Ctx) -> Unit = menu_rule_look,
  at? : (Double, Double, Double, Double),
  scrim? : Int64 = 0L,
  submenu? : Bool = false,
  enter? : @motion.Trans = pop_in,
  exit? : @motion.Trans = pop_out,
) -> Menu {
  install()
  let mut now = open
  if !open && c.has_focus(trigger) && c.take_key(@ui.key_code_down) {
    now = true
  }
  let by_key = c.focus_shown(trigger)
  let pid = c.id(key + "/panel")
  let moved = @motion.presence(c, "\u{2}pop/" + key, now, initial=true, enter~, exit~)
  let shown = moved is Some(_)
  // the scrim, if any, in and out over 200 ms: the layer stays until both the panel and it have gone (Android's
  // MenuHost), fading together
  let dim = if scrim != 0L { animate(c, key + "/scrim", if now { 1.0 } else { 0.0 }, transition=@motion.tween(200.0, ease=Out)) } else { 0.0 }
  let mut chosen = None
  if shown || dim > 0.0 {
    // A menu opened by touch alongside a field leaves its input method in place. When opened by the keyboard, the
    // first choice takes focus as usual; a menu without an active field focuses its panel.
    let initial = if by_key { first_item(c, key, entries) } else if @ui.pointing() is Finger && c.field_focused() { 0 } else { pid }
    let o = c.overlay(key, modal=!submenu, anchor=trigger, return_focus=if submenu { trigger } else { 0 }, scrim=faded(scrim, dim), initial_focus=initial, inert=!now, fn() {
      guard moved is Some(shows) else { return }
      let out = menu_panel(
        c,
        key,
        entries,
        match at {
          Some(r) => r
          None => menu_anchor(c, pid, trigger, now)
        },
        side,
        along,
        offset,
        shows,
        label,
        if submenu { 1 } else { 0 },
        false,
        min_w,
        look,
        item_look,
        heading_look~,
        rule_look~,
      )
      chosen = out.chosen
      if out.back { now = false }
    })
    if o.dismissed is Some(_) || chosen is Some(_) {
      now = false
    }
  }
  { open: now, chosen, shown: shown || dim > 0.0 }
}

///|
/// Where a dropdown's panel `pid` hangs, by its trigger (popover.mbt anchor_of: where it was drawn last frame, else
/// where the panel was put by it the frame before); going out (not `open`), where it was last put by it however long
/// ago, so that it goes where it was rather than from the window's corner where its trigger is not drawn the frame its
/// exit plays in (a trigger shown only under the pointer, back from under the menu). Nowhere known: the window's corner.
fn menu_anchor(c : @ui.Ctx, pid : Int, trigger : Int, open : Bool) -> (Double, Double, Double, Double) {
  match anchor_of(c, pid, trigger) {
    Some(r) => r
    None =>
      match kit.val.anchors.get(pid) {
        Some((r, _)) if !open => r
        _ => (0.0, 0.0, 0.0, 0.0)
      }
  }
}

///|
/// `key`'s context menu (Radix's ContextMenu) of `entries`, for what `area` (its id) draws: opened at the pointer by
/// a right click (Ctrl-click on macOS) or a long press on it; the menu otherwise as a dropdown's. Whether it is open,
/// and what was chosen.
pub fn context_menu(
  c : @ui.Ctx,
  key : String,
  area : Int,
  entries : Array[Entry],
  label? : String = "",
  min_w? : Double = 180.0,
  look? : (@ui.Ctx, Double, () -> Unit) -> Unit = menu_look,
  item_look? : (@ui.Ctx, MenuItemState) -> Unit = menu_item_look,
) -> Menu {
  install()
  let id = c.id(key)
  // (its right click and its long press, not its click: what a click on the area does is the area's, and so is the
  // pointer's shape over it)
  let mut now = kit.val.opens.get(id).unwrap_or(false)
  match c.right_clicked(area) {
    Some(at) => {
      now = true
      kit.val.at[id] = at
    }
    None =>
      if c.held_long(area) {
        let (x, y, _) = c.pointer()
        now = true
        kit.val.at[id] = (x, y)
      }
  }
  let (ax, ay) = kit.val.at.get(id).unwrap_or((0.0, 0.0))
  let mut chosen = None
  let moved = @motion.presence(c, "\u{2}pop/" + key, now, initial=true, enter=pop_in, exit=pop_out)
  if moved is Some(shows) {
    let pid = c.id(key + "/panel")
    let o = c.overlay(key, modal=true, initial_focus=pid, inert=!now, fn() {
      let out = menu_panel(c, key, entries, (ax, ay, 0.0, 0.0), Bottom, Start, 2.0, shows, label, 0, false, min_w, look, item_look)
      chosen = out.chosen
    })
    if o.dismissed is Some(_) || chosen is Some(_) {
      now = false
    }
  }
  kit.val.opens[id] = now
  { open: now, chosen, shown: moved is Some(_) }
}

///|
/// `key`'s menubar (Radix's Menubar): `menus` (each its trigger's words and its entries) side by side, one roving
/// group. A click opens one (or closes it); while one is open, the pointer coming to another trigger opens that one,
/// and Left and Right move to the menu beside; Down, Enter and Space on a trigger open its menu at its first item.
/// The value chosen, if one was.
pub fn menubar(
  c : @ui.Ctx,
  key : String,
  menus : Array[(String, Array[Entry])],
  label? : String = "",
  min_w? : Double = 200.0,
  look? : (@ui.Ctx, Double, () -> Unit) -> Unit = menu_look,
  item_look? : (@ui.Ctx, MenuItemState) -> Unit = menu_item_look,
  trigger_look? : (@ui.Ctx, ToggleState) -> Unit = menubar_trigger_look,
) -> String? {
  install()
  let id = c.id(key)
  let was = kit.val.bars.get(id).unwrap_or(-1)
  let mut open = was
  let mut chosen = None
  let n = menus.length()
  let tids = menus.mapi(fn(k, _) { part_id(id, k) })
  let bar = c.box(dir=Row, gap=2.0, fn() {
    c.roving(key, orientation=Horizontal, wrap=true, current=pick(open >= 0, tids[imax(open, 0)], 0), fn() {
      for k, m in menus {
        let tid = tids[k]
        let r = c.interact(tid, keys=@ui.press_enter | @ui.press_space)
        if r.clicked {
          open = if open == k { -1 } else { k }
        }
        if open < 0 && c.has_focus(tid) && c.take_key(@ui.key_code_down) {
          open = k
        }
        if open >= 0 && open != k && r.hovered && pointer_moved(c) {
          open = k
        }
        let st = {
          label: m.0,
          on: open == k,
          hovered: r.hovered,
          pressed: r.pressed,
          focus_shown: r.focus_shown,
          disabled: false,
          first: k == 0,
          last: k == n - 1,
        }
        let i = c.box(id=tid, fn() { trigger_look(c, st) })
        c.semantics(i, MenuItem, id=tid, label=m.0, expanded=open == k, actions=[Activate])
      }
    })
  })
  c.semantics(bar, MenuBar, label~)
  if open >= 0 {
    let k = open
    let mk = key + "/" + k.to_string()
    let pid = c.id(mk + "/panel")
    let mut out : PanelOut = { chosen: None, back: false }
    let mut step = 0
    // opened by the keyboard (its trigger's focus shows): at its first item
    let o = c.overlay(mk, anchor=tids[k], trap=true, initial_focus=pick(c.focus_shown(tids[k]), first_item(c, mk, menus[k].1), pid), fn() {
      out = menu_panel(
        c,
        mk,
        menus[k].1,
        c.rect_of(tids[k]).unwrap_or((0.0, 0.0, 0.0, 0.0)),
        Bottom,
        Start,
        4.0,
        @ui.still_look,
        menus[k].0,
        0,
        false,
        min_w,
        look,
        item_look,
      )
      // Left and Right not taken by a submenu: the menu beside, at its first item (read in the menu: its keys while
      // the focus is in it)
      if out.chosen is None {
        let (prev, next) = if c.rtl() {
          (@ui.key_code_right, @ui.key_code_left)
        } else {
          (@ui.key_code_left, @ui.key_code_right)
        }
        step = if c.take_key(next) {
          1
        } else if c.take_key(prev) {
          -1
        } else {
          0
        }
      }
    })
    if out.chosen is Some(_) {
      chosen = out.chosen
      open = -1
    } else if o.dismissed is Some(_) {
      open = -1
    } else if step != 0 {
      open = (k + step + n) % n
      c.focus_on(tids[open], visible=true)
    }
  }
  kit.val.bars[id] = open
  chosen
}

///|
/// A menubar's (and a navigation menu's) trigger's default look (still.fail's chooser): quiet small words, 28 high,
/// the hover's ground and the words' colour when pointed at or open.
pub fn menubar_trigger_look(c : @ui.Ctx, s : ToggleState) -> Unit {
  let t = c.theme()
  let lit = s.on || s.hovered
  c.box(h=Px(28.0), padx=8.0, justify=JCenter, radius=8.0, bg=pick(lit, t.hover, 0L), fn() {
    c.text(s.label, size=t.font, weight=pick(s.on, 500, 400), color=pick(lit, t.fg, t.muted), wrap=false) |> ignore
    focus_ring(c, s.focus_shown, 8.0)
  })
  |> ignore
}

///|
/// A menu's panel's default look (still.fail's small panel): the theme's surface, its large corner, 6 in (what has a
/// ground of its own, a row, stands so far from its edge), a line round it, a shadow; at least `min_w` wide.
pub fn menu_look(c : @ui.Ctx, min_w : Double, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(
    min_w~,
    pad=6.0,
    bg=t.surface,
    radius=t.radius_lg,
    border=1.0,
    border_color=t.line,
    shadow=32.0,
    shadow_color=t.shadow,
    shadow_y=12.0,
    body,
  )
  |> ignore
}

///|
/// A menu item's default look (still.fail's menu rows): 34 high, its words 10 in, its corner the panel's less the
/// panel's 6 (one curve with it); lit on the hover's ground; a mark's room before its words (✓ for a checked item, •
/// for the chosen of a choice), its shortcut or a submenu's › after them; disabled in the subtle grey.
pub fn menu_item_look(c : @ui.Ctx, s : MenuItemState) -> Unit {
  let t = c.theme()
  let e = s.entry
  let ink = if e.disabled { t.subtle } else { t.fg }
  let mark = match e.kind {
    Check(true) => "✓"
    Choice(true) => "•"
    _ => ""
  }
  let marks = match e.kind {
    Check(_) | Choice(_) => true
    _ => false
  }
  c.box(
    dir=Row,
    min_h=34.0,
    padx=10.0,
    pady=7.0,
    gap=8.0,
    align=ACenter,
    radius=@ui.concentric(t.radius_lg, 6.0),
    bg=pick((s.lit || s.open) && !e.disabled, t.hover, 0L),
    fn() {
      if marks {
        c.box(w=Px(14.0), align=ACenter, fn() { c.text(mark, size=t.font, weight=600, color=ink, wrap=false) |> ignore })
        |> ignore
      }
      c.box(w=Fill(1.0), fn() { c.text(e.label, size=t.font, color=ink, wrap=false, line=20.0) |> ignore }) |> ignore
      if e.shortcut != "" {
        c.text(e.shortcut, size=t.font_sm, color=t.muted, wrap=false) |> ignore
      }
      if e.kind is Sub(_) {
        c.text(if c.rtl() { "‹" } else { "›" }, size=t.font + 2.0, color=t.muted, wrap=false) |> ignore
      }
    },
  )
  |> ignore
}
