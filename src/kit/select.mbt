// A select (Radix's Select): a trigger showing the option chosen (or its placeholder) that opens the options as a
// listbox below it, its focus on the one chosen; Enter, Space, Down and Up on the trigger open it, letters typed on it
// choose the option they start, the value the view's. A toolbar (Radix's Toolbar): what it holds one roving group, one
// Tab stop with the arrows along it. A navigation menu (Radix's NavigationMenu): links and triggers side by side, a
// trigger's content shown under it as the pointer rests on it (or it is clicked, or Down, Enter or Space with its
// focus), the pointer moving to another trigger showing that one at once; Escape closes it.

///|
/// What a select's trigger's look is given: the words shown (the option's, or the placeholder), whether they are the
/// placeholder, open, pointed at, focus shown, disabled, where it was last frame.
pub(all) struct SelectState {
  text : String
  placeholder : Bool
  open : Bool
  hovered : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
}

///|
/// `key`'s select (see the file's head) of `options`, `value` chosen ("" none: `placeholder` shown), `w` wide, named
/// `label` for the semantics tree. What is chosen now, and what happened.
pub fn select(
  c : @ui.Ctx,
  key : String,
  value : String,
  options : Array[Item],
  placeholder? : String = "",
  w? : Double = 200.0,
  label? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, SelectState) -> Unit = select_look,
  item_look? : (@ui.Ctx, MenuItemState) -> Unit = menu_item_look,
) -> @ui.Changed[String] {
  install()
  let id = c.id(key)
  let r = c.interact(id, disabled~)
  let mut open = kit.val.opens.get(id).unwrap_or(false)
  let mut now = value
  if !disabled && !open {
    if r.clicked {
      open = true
    }
    if r.focused {
      if c.take_key(@ui.key_code_down) || c.take_key(@ui.key_code_up) {
        open = true
      }
      // letters typed on it: the option they start
      let entries = options.map(fn(o) { menu_radio(o.value, o.value == now, label=o.label, disabled=o.disabled) })
      let ids = options.mapi(fn(k, _) { part_id(id, k) })
      let was = c.focused_id()
      // (typeahead moves a focus: here, the option it lands on is chosen and the focus stays on the trigger)
      typeahead(c, id, entries, ids, fn(k) { !options[k].disabled })
      for k, oid in ids {
        if c.focused_id() == oid {
          now = options[k].value
        }
      }
      if c.focused_id() != was {
        c.focus_on(id, visible=true)
      }
    }
  } else if r.clicked {
    open = false
  }
  let shown = match options.search_by(fn(o) { o.value == now }) {
    Some(k) => options[k].label
    None => ""
  }
  let st = {
    text: if shown == "" { placeholder } else { shown },
    placeholder: shown == "",
    open,
    hovered: r.hovered,
    focus_shown: r.focus_shown,
    disabled,
    rect: r.rect,
  }
  let i = c.box(id=if disabled { 0 } else { id }, w=Px(w), fn() { look(c, st) })
  c.semantics(i, Combobox, id~, label~, value=shown, expanded=open, disabled~, actions=pick(disabled, [], [Activate]))
  let p = presence(c, key, open, enter=@motion.tween(120.0, ease=Out), exit=@motion.tween(80.0, ease=LeaveFade))
  if p.built {
    let entries = options.map(fn(o) { menu_radio(o.value, o.value == now, label=o.label, disabled=o.disabled) })
    let pid = c.id(key + "/list/panel")
    let at = match options.search_by(fn(o) { o.value == now }) {
      Some(k) => part_id(pid, k)
      None => -1
    }
    let mut chosen : String? = None
    let o = c.overlay(key + "/list", modal=true, anchor=id, initial_focus=at, inert=p.leaving(), fn() {
      let out = menu_panel(
        c,
        key + "/list",
        entries,
        r.rect,
        Bottom,
        Start,
        4.0,
        p.t,
        label,
        0,
        true,
        w,
        fn(c, min_w, body) { menu_look(c, min_w, body) },
        item_look,
      )
      chosen = out.chosen
    })
    match chosen {
      Some(v) => {
        now = v
        open = false
      }
      None => if o.dismissed is Some(_) { open = false }
    }
  }
  ignore(told(c, open != kit.val.opens.get(id).unwrap_or(false)))
  kit.val.opens[id] = open
  { value: now, response: r.changed_to(told(c, now != value)) }
}

///|
/// A select's trigger's default look (still.fail's select, a pill as a one-line field is): a line round it that
/// darkens pointed at, its words (the subtle grey for the placeholder) and a chevron.
pub fn select_look(c : @ui.Ctx, s : SelectState) -> Unit {
  let t = c.theme()
  c.box(
    dir=Row,
    w=Fill(1.0),
    h=Px(t.control_h),
    padx=16.0,
    gap=8.0,
    align=ACenter,
    radius=t.control_h / 2.0,
    border=1.0,
    border_color=pick((s.hovered || s.open) && !s.disabled, t.field_hover, t.border),
    bg=t.bg,
    opacity=pick(s.disabled, 0.45, 1.0),
    fn() {
      c.box(w=Fill(1.0), fn() {
        c.text(s.text, size=t.font + 1.0, color=pick(s.placeholder, t.subtle, t.fg), wrap=false) |> ignore
      })
      |> ignore
      chevron(c, false, t.muted)
      focus_ring(c, s.focus_shown, s.rect, t.control_h / 2.0)
    },
  )
  |> ignore
}

///|
/// `key`'s toolbar (see the file's head), named `label`, what `body` builds one roving group (`orientation` its
/// arrows), on the faint ground.
pub fn toolbar(
  c : @ui.Ctx,
  key : String,
  body : () -> Unit,
  label? : String = "",
  orientation? : @ui.Orientation = Horizontal,
) -> Unit {
  let t = c.theme()
  let mut i = 0
  // as wide as what it holds, wherever it stands
  c.box(dir=Row, fn() {
    i = c.box(
      dir=pick(orientation == Vertical, Column, Row),
      gap=2.0,
      pad=3.0,
      align=ACenter,
      bg=t.faint,
      radius=t.radius + 3.0,
      fn() { c.roving(key, orientation~, wrap=true, body) },
    )
  })
  |> ignore
  c.semantics(i, Toolbar, label~)
}

///|
/// A navigation menu's item: its value, its words, and what its trigger shows (None: it is a link).
pub(all) struct NavItem {
  value : String
  label : String
  content : (() -> Unit)?
}

///|
/// A navigation menu's link `value` (its words `label`, the value by default).
pub fn nav_link(value : String, label? : String = "") -> NavItem {
  { value, label: if label == "" { value } else { label }, content: None }
}

///|
/// A navigation menu's trigger `label`, showing what `content` builds.
pub fn nav_trigger(label : String, content : () -> Unit) -> NavItem {
  { value: label, label, content: Some(content) }
}

///|
/// `key`'s navigation menu (see the file's head) of `items`, a trigger's content shown once the pointer has rested on
/// it `delay` ms, hidden `close_delay` ms after it has left both; named `label`. The link followed, if one was.
pub fn navigation_menu(
  c : @ui.Ctx,
  key : String,
  items : Array[NavItem],
  delay? : Double = 200.0,
  close_delay? : Double = 150.0,
  label? : String = "",
  trigger_look? : (@ui.Ctx, ToggleState) -> Unit = menubar_trigger_look,
  look? : (@ui.Ctx, PopState, () -> Unit) -> Unit = popover_look,
) -> String? {
  install()
  let id = c.id(key)
  let was = kit.val.bars.get(id).unwrap_or(-1)
  let mut open = was
  let mut followed : String? = None
  let n = items.length()
  let tids = items.mapi(fn(k, _) { part_id(id, k) })
  let cid = c.id(key + "/content/panel")
  let on_content = was >= 0 && pointer_in(c, cid)
  let mut hovered_any = -1
  // opened by the keyboard: it stays until Escape, a press outside or a trigger closes it
  let mut by_key = was >= 0 && kit.val.opens.get(cid).unwrap_or(false)
  let nav = c.box(dir=Row, gap=2.0, fn() {
    c.roving(key, orientation=Horizontal, wrap=false, fn() {
      for k, it in items {
        let tid = tids[k]
        let r = c.interact(tid)
        if r.hovered {
          hovered_any = k
        }
        match it.content {
          None => if r.clicked { followed = Some(it.value) }
          Some(_) => {
            if r.clicked {
              open = if open == k { -1 } else { k }
              by_key = c.focus_shown(tid)
            }
            if c.has_focus(tid) && open != k && c.take_key(@ui.key_code_down) {
              open = k
              by_key = true
            }
          }
        }
        let st = {
          label: it.label,
          on: open == k,
          hovered: r.hovered,
          pressed: r.pressed,
          focus_shown: r.focus_shown,
          disabled: false,
          rect: r.rect,
          first: k == 0,
          last: k == n - 1,
        }
        let i = c.box(id=tid, fn() {
          trigger_look(c, st)
        })
        match it.content {
          None => c.semantics(i, Link, id=tid, label=it.label, actions=[Activate])
          Some(_) => c.semantics(i, Button, id=tid, label=it.label, expanded=open == k, actions=[Activate])
        }
      }
    })
  })
  c.semantics(nav, Navigation, label~)
  // the pointer: resting on a trigger opens it (at once while another is open), leaving both closes it
  let over = if hovered_any >= 0 && items[hovered_any].content is Some(_) { hovered_any } else { -1 }
  if over >= 0 && over != open {
    if open >= 0 || after(c, key + "/in", true, delay) {
      open = over
    }
  } else {
    ignore(after(c, key + "/in", false, delay))
  }
  if open >= 0 && !by_key && over < 0 && !on_content && hovered_any < 0 {
    if after(c, key + "/out", true, close_delay) {
      open = -1
    }
  } else {
    ignore(after(c, key + "/out", false, close_delay))
  }
  if open >= 0 {
    match items[open].content {
      Some(body) => {
        let k = open
        let o = c.overlay(key + "/content", anchor=tids[k], initial_focus=pick(c.focus_shown(tids[k]), -1, 0), fn() {
          beside(c, key + "/content", tids[k], Bottom, Start, 6.0, 1.0, Region, items[k].label, look, body)
        })
        if o.dismissed is Some(_) {
          open = -1
        }
      }
      None => open = -1
    }
  }
  ignore(told(c, open != was))
  kit.val.bars[id] = open
  kit.val.opens[cid] = open >= 0 && by_key
  followed
}
