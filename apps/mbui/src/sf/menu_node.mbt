// A menu of the presenters' (menu_popover's: the library's dropdown, kit's dropdown_menu and menu_panel, in the web's
// look) as nodes of the window's tree: a modal layer over the window, nothing under it dimmed, its small panel beside
// what opened it (where it was drawn as it opened: under it, `offset` off, lined up `along` it, over it where there is
// not the room under: View::beside), grown out of that side as it comes (pop_in), gone at once as it closes (as the
// presenters let go of a menu the frame it closes: menu_popover); its rows as menu_row draws them (as high as the screen's pick row at least, its icon or a choice's check in
// a column before its words where one has one, a danger's in red, one not to be chosen faint), headings and lines
// between parts; what it holds scrolling where it is taller than the window leaves it. Its rows are one roving group, the
// one with the focus lit: Up and Down move the focus along them (not round), Home and End to the ends, letters typed
// (alone or with Shift) to the first whose words start with them (a second's worth together), shown, what holds them
// bringing it into sight; the pointer moving onto one gives it the focus, unseen. Enter, Space, a tap or a click choose
// one (it closes, then what it does goes on); a press on what of its panel cannot be chosen does nothing. Escape, back
// and a press outside close it. Opened by the keyboard, the focus on its first row, shown; else on its panel, nothing
// lit, till a key or the pointer moves it.

///|
/// A menu in `parent` while `open()` (let go of at once once not): what `content` holds as it is now (None a line
/// between parts: its rows, what can be chosen of them, the keys' way along them and what a choice does, all from the
/// same of it, read again as it is told changed, the menu open as it was, its focus where it was), headed by
/// `title` ("" none), beside what `anchor` makes in its layer (what opened it, where that is drawn), `offset` off
/// it, lined up `along` it; `by_key`: opened by the keyboard (the focus on its first row); `keep_field`: opened by a
/// finger with a field focused (kit's dropdown_menu: its input method left in place): the focus left in that field, what
/// is typed still its (View::leaves_typing), every key, the wheel and every press the menu's as ever. `choose` with the item chosen, once,
/// as it closes; `cancel` as it is closed unchosen. `shown`, `gone`: as dialog_layer_node's.
pub fn menu_node(
  parent : @view.View,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  content : () -> Array[MenuItem?],
  title : String,
  along : @ui.Along,
  offset : Double,
  by_key : Bool,
  keep_field : Bool,
  choose : (MenuItem) -> Unit,
  cancel : () -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
) -> Unit {
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      let t = theme()
      // (how far in it is, from the moment it opened)
      let way = EdgeWay::new(0.0)
      way.go(layer, 1.0, @kit.pop_ms)
      let look = fn() {
        let p = way.shown(layer)
        @kit.pop_in.at(p, p)
      }
      let live = fn() { !layer.leaving() }
      // (its words and icons as far in as its look says: its ground first, then they, as pop_in has it)
      let words_in = fn() { look().words }
      // (its rows that can be chosen, by their index: the one with the focus is lit; the keyboard moves the focus along
      // them, shown, the pointer onto one, unseen)
      let rows : Map[Int, @view.View] = {}
      // (the row of the rows' one stop of Tab's: the last that had the focus, else the first: Radix's roving focus)
      let current = @signals.signal(first_live(@signals.untracked(content), 0, 1), same=fn(a, b) { a == b })
      // (where Tab stops in its rows, as they are now: that one while it can still be chosen; else (made one not to be
      // chosen, taken out, a heading now) the first that can, as ui's group_stop falls back)
      let stop = fn() {
        let items = content()
        let at = current.get()
        match items.get(at) {
          Some(Some(item)) if !item.disabled && !item.heading => at
          _ => first_live(items, 0, 1)
        }
      }
      let lit = fn() {
        let mut at = -1
        for i, r in rows {
          if r.focused() {
            at = i
          }
        }
        at
      }
      let light = fn(i : Int) {
        match rows.get(i) {
          Some(r) => r.ask_focus(visible=true) |> ignore
          None => ()
        }
      }
      // (said once: the first choice, or a close)
      let said = Ref(false)
      let go = fn(i : Int) {
        // (what it holds now: what the row pressed shows)
        match @signals.untracked(content).get(i) {
          Some(Some(item)) if !item.disabled && !item.heading && !said.val => {
            said.val = true
            choose(item)
          }
          _ => ()
        }
      }
      // (letters typed together, and when the last was)
      let typed = Ref("")
      let typed_at = Ref(-1.0e9)
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go)
      .modal(By(live))
      .held_back_goes_on()
      |> ignore
      if keep_field {
        // (what is typed the field's it leaves the focus in: kit's dropdown_menu's initial focus none)
        layer.leaves_typing() |> ignore
      }
      layer
      // (a press outside its panel its own, nothing under it pressed: closing it as it goes down, as the old frame's
      // menu is dismissed then)
      .presses(Is(true))
      .on_drag(fn(d) {
        if d.kind == Down && @signals.untracked(live) {
          cancel()
        }
      })
      .on_key(fn(k) {
        if !@signals.untracked(live) {
          return false
        }
        let now = @signals.untracked(lit)
        let items = @signals.untracked(content)
        if k.code == @ui.key_escape {
          cancel()
          true
        } else if keep_field && now < 0 {
          // (the focus still in the field it was opened by: no key of the menu's moves it into the menu, nor reaches
          // the field, as kit's menu takes none while the focus is not in it; once a mouse has brought it to a row,
          // its keys as ever)
          true
        } else if k.mods != 0 && !(k.mods == @ui.mod_shift_key && typed_char(k.code) is Some(_)) {
          // (with Ctrl, Alt, Cmd or Shift held, its keys none of the menu's, as kit's menu takes them bare alone
          // (but a letter with Shift, typed); Escape closes it whatever is held)
          false
        } else if k.code == @ui.key_code_down || k.code == @ui.key_code_up {
          let down = k.code == @ui.key_code_down
          // (from nothing lit, Down to the first and Up to the last; on from one, not round)
          let next = if now < 0 {
            if down { first_live(items, 0, 1) } else { first_live(items, items.length() - 1, -1) }
          } else {
            match first_live(items, now + (if down { 1 } else { -1 }), if down { 1 } else { -1 }) {
              -1 => now
              n => n
            }
          }
          light(next)
          true
        } else if k.code == @ui.key_code_home || k.code == @ui.key_code_end {
          light(if k.code == @ui.key_code_home { first_live(items, 0, 1) } else { first_live(items, items.length() - 1, -1) })
          true
        } else if k.code == @ui.key_code_enter || k.code == @ui.key_of_char(' ') {
          if now >= 0 {
            go(now)
          }
          true
        } else {
          // (a letter or digit alone or with Shift, as kit's typeahead takes them: never with Ctrl, Alt or Cmd)
          match (if k.mods == 0 || k.mods == @ui.mod_shift_key { typed_char(k.code) } else { None }) {
            Some(ch) => {
              // (a second's worth together: the same letter again moves on to the next it starts)
              let s = if k.at - typed_at.val <= @kit.typeahead_ms { typed.val + ch.to_string() } else { ch.to_string() }
              typed.val = s
              typed_at.val = k.at
              match typeahead_to(items, s, now) {
                -1 => ()
                n => light(n)
              }
              true
            }
            None => false
          }
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) {
          cancel()
        }
      })
      |> ignore
      // (what opened it, where it is drawn: what its panel goes beside)
      let at = anchor(layer)
      // (a column before every item's words where one has an icon or is one of a choice: menu_popover's dropdown)
      let iconed = fn() { content().iter().any(fn(x) { x is Some(i) && i.chosen is None && i.icon != "" }) }
      let lead = fn() { iconed() || content().iter().any(fn(x) { x is Some(i) && i.chosen is Some(_) }) }
      let gap = fn() { if lead() && !iconed() { chooser_gap } else { menu_gap } }
      let reach = menu_row_reach(t.rows.pick)
      let first_row = fn() {
        let items = content()
        items.length() > 0 && (items[0] is Some(i) && !i.heading) && title == ""
      }
      let last_row = fn() {
        let items = content()
        items.length() > 0 && (items[items.length() - 1] is Some(i) && !i.heading)
      }
      layer.box(fn(p) {
        p
        .beside(at.id(), side=Bottom, along=view_along(along), offset~, padding=8.0)
        .min_width(Is(Some(menu_w)))
        .max_width(By(fn() { Some(layer.window().0 - 16.0) }))
        .max_height(By(fn() { Some(dmax(0.0, layer.window().1 - 16.0)) }))
        // (small_panel: its padding, its rows reaching past it to stand concentric with its corners)
        .padding(
          By(fn() {
            (panel_pad - reach, if first_row() { panel_pad - reach } else { panel_pad }, panel_pad - reach, if last_row() { panel_pad - reach } else { panel_pad })
          }),
        )
        .radius(Is(r_menu))
        .ground(By(fn() { panel_ground() }))
        .edge(By(fn() { (1.0, library_theme().p.line) }))
        .shadow(By(fn() { (16.0, 12.0, library_theme().p.shadow) }))
        .clips(Is(true))
        .alpha(By(fn() { look().alpha }))
        .scale(By(fn() { look().sx }), about=FromBeside)
        .says(Is(Some(@view.said(Menu, label=title))))
        // (the focus its own as it opens, opened by the pointer: no key presses it; its rows lit as they have it; one of
        // the menu's two stops of Tab's, its rows the other, as kit's panel and roving group are)
        .focusable(Is(true), keys=0)
        // (a press on it its own: on what of it takes none (its padding, a heading, a line, a row not to be chosen),
        // nothing, not outside it)
        .presses(Is(true))
        .on_press(fn() {  })
        |> ignore
        p.box(fn(body) {
          body.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
            if title != "" {
              menu_heading_node(b, fn() { title }, lead, gap, reach, words_in)
            }
            // (each of what it holds by its place and its kind: one changing what it is (a line, a heading, a row) made
            // anew there; a row's words, icon, check and whether it can be chosen read again as they change, the row the
            // same, its focus kept)
            b.each(fn() { content().mapi(fn(i, x) { (i, menu_kind(x)) }) }, fn(k) { k }, fn(cell, k) {
              let (i, kind) = @signals.untracked(fn() { k.get() })
              let item = fn() {
                match content().get(i) {
                  Some(Some(item)) => item
                  _ => menu_none
                }
              }
              match kind {
                0 => menu_rule_node(cell, reach)
                1 => menu_heading_node(cell, fn() { item().label }, lead, gap, reach, words_in)
                _ => {
                  rows[i] = menu_row_node(cell, item, i, lead, gap, reach, go, words_in, current, stop)
                  cell.owns(fn() { rows.remove(i) }) |> ignore
                }
              }
            })
          })
          |> ignore
        })
        |> ignore
        // (the focus given as it opens: opened by the keyboard, to its first row; else its panel; back to what had it
        // as it goes)
        let first = match rows.get(first_live(@signals.untracked(content), 0, 1)) {
          Some(r) if by_key => r
          _ => p
        }
        // (the focus given as it opens; or, by a finger beside a field, left in that field, what had it given back as it
        // goes all the same: View::focus_returns)
        if keep_field {
          layer.focus_returns() |> ignore
        } else {
          layer.focus_opens(first) |> ignore
        }
      })
      |> ignore
    },
  )
}

///|
/// What a menu holds at a place is, by its kind: a line (0), a heading (1), a row (2).
fn menu_kind(x : MenuItem?) -> Int {
  match x {
    None => 0
    Some(item) if item.heading => 1
    Some(_) => 2
  }
}

///|
/// What a row of a menu reads where its place holds nothing more (its menu holding less now, the row about to go).
let menu_none : MenuItem = {
  label: "",
  icon: "",
  danger: false,
  disabled: true,
  chosen: None,
  heading: false,
  select: fn() {  },
}

///|
/// A row of a menu (menu_row's look) in `b`: what `item()` is now, the `i`th; lit while it has the focus (its ground
/// the pointer's or the keyboard's where that is shown or the pointer is on it); the pointer moving onto it gives it the
/// focus, unseen; pressed, `go`. Its words, icon, check and whether it can be chosen as the item has them now. The row.
fn menu_row_node(
  b : @view.View,
  item : () -> MenuItem,
  i : Int,
  lead : () -> Bool,
  gap : () -> Double,
  reach : Double,
  go : (Int) -> Unit,
  words_in : () -> Double,
  current : @signals.Signal[Int],
  stop : () -> Int,
) -> @view.View {
  let t = theme()
  let off = fn() { item().disabled }
  b.box(fn(r) {
    r
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .min_height(Is(Some(t.rows.pick)))
    .padding(Is((text_in + reach, menu_row_over, text_in + reach, menu_row_over)))
    .gap(By(gap))
    .radius(Is(small_panel_inner(r_menu)))
    .ground(By(fn() { if r.focused() && (r.focus_shown() || r.pointed()) { library_theme().p.hover } else { 0L } }))
    .presses(By(fn() { !off() }))
    // (one of the roving group: the menu's keys move along it, no key of its own; Tab stopping on the group's current
    // one alone)
    .focusable(By(fn() { !off() }), keys=0, tab=false)
    .tab_stop(By(fn() { stop() == i }))
    .on_press(fn() { go(i) })
    .says(
      By(fn() {
        let it = item()
        let actions : Array[@view.Action] = if it.disabled { [] } else { [Activate] }
        Some(
          match it.chosen {
            Some(on) => @view.said(MenuItemRadio, label=it.label, check=if on { On } else { Off }, actions~)
            None => @view.said(MenuItem, label=it.label, actions~)
          },
        )
      }),
    )
    |> ignore
    // (the pointer moved onto it or over it: the focus its, unseen, as kit's menu has it (hovered and the pointer moved);
    // come under a pointer that stays still (what holds it scrolled to bring another into sight), nothing)
    // (come to have the focus, however: the group's current one)
    r.reacts(fn() { r.focused() }, fn(f) {
      if f {
        current.set(i)
      }
    })
    r.on_pointer_moved(fn() {
      if !@signals.untracked(off) {
        r.ask_focus() |> ignore
      }
    })
    |> ignore
    // (its column before its words, where the menu has one: a choice's check, or its icon)
    r.show(lead, fn(col) {
      col.width(Is(Some(menu_check_w))).lines_up(Is(Some(Middle))).alpha(By(words_in)) |> ignore
      let mark = fn() {
        let it = item()
        match it.chosen {
          Some(true) => "\u{1}check"
          Some(false) => ""
          None => it.icon
        }
      }
      col.each(fn() { if mark() == "" { [] } else { [mark()] } }, fn(m) { m }, fn(slot, m) {
        let name = @signals.untracked(fn() { m.get() })
        if name == "\u{1}check" {
          icon_node(slot, "check", 14.0, By(fn() { library_theme().p.text })) |> ignore
        } else {
          icon_node(slot, name, 14.0, By(fn() {
            let p = library_theme().p
            if item().danger {
              if off() { p.subtle } else { p.red }
            } else {
              p.muted
            }
          }))
          |> ignore
        }
      })
    })
    r.box(fn(w) {
      w
      .words(By(fn() { item().label }), look=toast_words_look(Ui, L5, 400, false))
      .ink(By(fn() { @ui.tree_theme().color(if off() { Subtle } else if item().danger { Danger } else { Fg }) }))
      .alpha(By(words_in))
      |> ignore
    })
    |> ignore
  })
}

///|
/// A heading among a menu's items (menu_popover's heading_look): its words (`label()`) as far in as its rows' words
/// (past the column before them where there is one), small and muted, 6 over and 4 under it.
fn menu_heading_node(
  b : @view.View,
  label : () -> String,
  lead : () -> Bool,
  gap : () -> Double,
  reach : Double,
  words_in : () -> Double,
) -> Unit {
  b.box(fn(h) {
    h.padding(By(fn() { (text_in + (if lead() { menu_check_w + gap() } else { 0.0 }) + reach, 6.0, 10.0 + reach, 4.0) })) |> ignore
    h.box(fn(w) {
      w
      .words(By(label), look=toast_words_look(Meta, L4_75, 400, false))
      .ink(By(fn() { @ui.tree_theme().color(Muted) }))
      .alpha(By(words_in))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A line between parts of a menu (menu_rule): the words' ink faintly, 1 high, 6 over and under it, as wide as its rows'
/// grounds.
fn menu_rule_node(b : @view.View, reach : Double) -> Unit {
  b.box(fn(r) {
    r.padding(Is((reach, 6.0, reach, 6.0))) |> ignore
    r.box(fn(l) { l.height(Is(Some(1.0))).ground(By(fn() { @ui.alpha(@ui.tree_theme().fg, 0.12) })) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The first item from `from` on, going `step`, that can be chosen (not a line, a heading, nor disabled): -1 none.
fn first_live(items : Array[MenuItem?], from : Int, step : Int) -> Int {
  let mut k = from
  while k >= 0 && k < items.length() {
    match items[k] {
      Some(item) if !item.disabled && !item.heading => return k
      _ => ()
    }
    k = k + step
  }
  -1
}

///|
/// The letter or digit key `code` is (kit's typeahead's: ASCII, lower case), if it is one.
fn typed_char(code : Int) -> Char? {
  let lower = "abcdefghijklmnopqrstuvwxyz0123456789".to_array()
  let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".to_array()
  for i, ch in lower {
    if code == @ui.key_of_char(ch) || code == @ui.key_of_char(upper[i]) {
      return Some(ch)
    }
  }
  None
}

///|
/// Where letters `typed` take a menu lit at `at` (kit's typeahead): the same letter again to the next item after it
/// that starts with it; more letters to the first from it that starts with them; -1 none.
fn typeahead_to(items : Array[MenuItem?], typed : String, at : Int) -> Int {
  let n = items.length()
  if n == 0 {
    return -1
  }
  let first = typed.view(start_offset=0, end_offset=1).to_string()
  let same = typed.iter().all(fn(ch) { ch.to_string() == first })
  let want = if same { first } else { typed }
  let from = if same { at + 1 } else if at < 0 { 0 } else { at }
  for j in 0..<n {
    let k = (from + j) % n
    match items[k] {
      Some(item) if !item.disabled && !item.heading && item.label.to_lower().has_prefix(want) => return k
      _ => ()
    }
  }
  -1
}

///|
/// The tree's Along for the library's.
fn view_along(a : @ui.Along) -> @view.Along {
  match a {
    Start => Start
    Middle => Middle
    End => End
  }
}

///|
/// What a menu goes beside at a place in the window (x, y, w, h: a point where w and h are 0), made in `layer`.
pub fn fixed_anchor(layer : @view.View, at : (Double, Double, Double, Double)) -> @view.View {
  layer.box(fn(a) {
    let (x, y, w, h) = at
    a.width(Is(Some(w))).height(Is(Some(h))).offset(Is((x, y))) |> ignore
  })
}
