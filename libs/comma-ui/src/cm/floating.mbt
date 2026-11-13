// Comma's floating parts as nodes of the window's tree, drawn in the layer (layer.mbt): Tooltip (tooltip/TooltipBubble),
// Menu (menu/styles.ts), Dropdown (dropdown/Dropdown, SelectItem), Popup (popup/Popup) and Dialog (dialog/styles.ts).
// Each comes as its cause says, faded and grown in from 0.97 over its own duration on surface-smooth-out, and goes the
// same way back; a menu, a dropdown's list and a popup go at a press outside them or Escape, a dialog at a press on its
// scrim or Escape.

///|
/// A shadow of Comma's, light and dark (tokens_made's `shadow_*` and `shadow_dark_*`), as the appearance is now.
fn cast(light : (Double, Double, Int64), dark : (Double, Double, Int64)) -> (Double, Double, Int64) {
  if is_dark() {
    dark
  } else {
    light
  }
}

///|
/// What a floating panel looks like (menu's surface, popup's, dialog's): its corner, its ground and its shadow, the
/// primary border half a point wide; how far in it is from `e`, faded and grown in from 0.97.
fn panel_look(
  p : @view.View,
  e : Eased,
  corner : Double,
  ground : () -> Int64,
  shadow : () -> (Double, Double, Int64),
) -> Unit {
  p
  .radius(Is(corner))
  .ground(By(ground))
  .edge(By(fn() { (0.5, colors().border_primary) }))
  .shadow(By(shadow))
  .scale(By(fn() { 0.97 + 0.03 * e.shown(p) }))
  .alpha(By(fn() { seen_at(0.97 + 0.03 * e.shown(p)) * e.shown(p) }))
  |> ignore
}

///|
/// Comma's tooltip of `anchor` saying `label`, on its `side`, in `layer`: shown as the pointer rests on it `delay` ms
/// (300, Comma's) or at once as the keyboard's focus shows on it; gone as either leaves (`shown`: shown while it says so
/// too, a story's). Its bubble: the tooltip's ground in its edge half a point wide, rounded md, its words xs medium.
pub fn tooltip_node(
  layer : Layer,
  anchor : @view.View,
  label : () -> String,
  side? : @view.Side = Top,
  delay? : Double = 300.0,
  shown? : () -> Bool = fn() { false },
) -> Unit {
  let open : @signals.Signal[Bool] = @signals.signal(false)
  let pending : Ref[() -> Unit] = Ref(fn() {  })
  let wants = fn() {
    (@ui.pointing() is Mouse && anchor.pointed(), anchor.focus_shown(), shown())
  }
  anchor.reacts(wants, fn(w) {
    let (over, focused, said) = w
    (pending.val)()
    pending.val = fn() {  }
    if focused || said {
      open.set(true)
    } else if over {
      pending.val = anchor.at_moment(anchor.cause_at() + delay, fn() { open.set(true) })
    } else {
      open.set(false)
    }
  })
  let h = layer.holder(anchor)
  h.show(fn() { open.get() }, leave=ms_tooltip_exit, fn(t) {
    let e = opening(t, fn() { open.get() }, ms_tooltip_enter, ms_tooltip_exit)
    t.beside(anchor.id(), side~, along=Middle, offset=space_sm) |> ignore
    t
    .padding(Is((space_md, space_xs, space_md, space_xs)))
    .radius(Is(radius_md))
    .ground(By(fn() { colors().tooltip_bg }))
    .edge(By(fn() { (0.5, colors().tooltip_border) }))
    .shadow(By(fn() { cast(shadow_xs, shadow_dark_xs) }))
    .scale(By(fn() { 0.97 + 0.03 * e.shown(t) }))
    .alpha(By(fn() { e.shown(t) }))
    .says(By(fn() { Some(@view.said(Tooltip, label=label())) }))
    |> ignore
    t.box(fn(w) {
      w.words(By(label), look=words_in(type_mini, weight=weight_medium)).ink(By(fn() { colors().tooltip_text })) |> ignore
    })
    |> ignore
  })
}

///|
/// A row of a menu: its words, what it does, whether it destroys (in the error's words), whether it is the chosen one
/// (a tick at its end), a line over it (a new group).
pub(all) struct MenuRow {
  label : String
  press : () -> Unit
  danger : Bool
  checked : Bool
  divided : Bool
}

///|
/// A row of a menu (MenuRow).
pub fn menu_item(
  label : String,
  press : () -> Unit,
  danger? : Bool = false,
  checked? : Bool = false,
  divided? : Bool = false,
) -> MenuRow {
  { label, press, danger, checked, divided }
}

///|
/// The rows of a menu in `m`: each 6 in from the menu's sides, rounded sm, 8 in and 6 over and under its words (small,
/// medium, the secondary's), lit in quaternary under the hand or by the arrow keys; Enter or a press does it and closes
/// the menu. `lit` is the row lit now (-1 none).
#callsite(autofill(loc))
fn menu_rows(
  parent : @view.View,
  items : () -> Array[MenuRow],
  lit : @signals.Signal[Int],
  close : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(m) {
    let all = @signals.untracked(items)
    for i, item in all {
      if item.divided {
        m.box(fn(d) {
          d.height(Is(Some(0.5))).margin(Is((0.0, space_xs, 0.0, space_xs))).ground(By(fn() { colors().border_primary }))
          |> ignore
        })
        |> ignore
      }
      m.box(fn(g) {
        g.padding(Is((space_sm, 0.0, space_sm, 0.0))) |> ignore
        g.box(fn(r) {
          let on = fn() { lit.get() == i }
          let hand = eased_by(r, on, ms_feedback_out, ease_smooth_out)
          r
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .gap(Is(space_lg))
          .padding(Is((space_md, space_sm, space_md, space_sm)))
          .radius(Is(radius_sm))
          .ground(By(fn() { alpha(colors().bg_quaternary, hand.shown(r)) }))
          .says(Is(Some(@view.said(MenuItem, label=item.label))))
          |> ignore
          presses_node(r, fn() {
            (item.press)()
            close()
          })
          r.reacts(fn() { r.pointed() }, fn(p) { if p { lit.set(i) } })
          r.box(fn(w) {
            w
            .grow(Is(1.0))
            .words(Is(item.label), look=words_in(type_small, weight=weight_medium))
            .ink(By(fn() {
              let c = colors()
              if item.danger {
                c.text_error_primary
              } else if on() {
                c.sidebar_text_highlight
              } else {
                c.text_secondary
              }
            }))
            |> ignore
          })
          |> ignore
          if item.checked {
            icon_node(r, icon_check, 20.0, fn() { colors().fg_brand_primary }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    // (the arrow keys move the lit row, Enter does it)
    m.on_key(fn(k) {
      let n = @signals.untracked(items).length()
      if n == 0 {
        return false
      }
      let now = lit.untracked()
      if k.code == @ui.key_code_down {
        lit.set(if now < 0 { 0 } else { (now + 1) % n })
        true
      } else if k.code == @ui.key_code_up {
        lit.set(if now <= 0 { n - 1 } else { now - 1 })
        true
      } else if k.code == @ui.key_code_enter && now >= 0 && now < n {
        (@signals.untracked(items)[now].press)()
        close()
        true
      } else {
        false
      }
    })
    |> ignore
  }) |> ignore
}


///|
/// Comma's menu of `anchor` in `layer`, open while `open` says: `items` (MenuRow), 240 wide (`width`), under `anchor`
/// at its start, 4 off. Its surface: popup-secondary, rounded xl, the primary border half a point, the lg shadow, 6
/// over and under its rows. Gone at a press outside it, Escape, or a row done (`open` set false). Read out a menu named
/// `label`.
pub fn menu_node(
  layer : Layer,
  anchor : @view.View,
  open : @signals.Signal[Bool],
  items : () -> Array[MenuRow],
  label? : String = "Menu",
  width? : Double = 240.0,
  side? : @view.Side = Bottom,
) -> Unit {
  let close = fn() { open.set(false) }
  let lit : @signals.Signal[Int] = @signals.signal(-1)
  let h = layer.holder(anchor)
  escape_closes(h, fn() { open.get() }, close)
  h.show(fn() { open.get() }, fn(c) { closes_outside(c, close, "Close " + label) })
  h.show(fn() { open.get() }, leave=ms_menu_exit, fn(m) {
    lit.set(-1)
    let e = opening(m, fn() { open.get() }, ms_menu_enter, ms_menu_exit)
    m.beside(anchor.id(), side~, along=Start, offset=space_xs) |> ignore
    m.width(Is(Some(width))).padding(Is((0.0, space_sm, 0.0, space_sm))) |> ignore
    panel_look(m, e, radius_xl, fn() { colors().bg_popup_secondary }, fn() { cast(shadow_lg, shadow_dark_lg) })
    m.says(Is(Some(@view.said(Menu, label~)))) |> ignore
    menu_rows(m, items, lit, close)
  })
}

///|
/// Comma's dropdown in `parent`: a trigger like an input (40 high, rounded md, the primary edge, the xs shadow, its
/// words small: the chosen option, else `placeholder` in the placeholder's colour, a chevron at its end), opening under
/// it as wide as it a menu of `options` with a tick by the chosen one. Choosing sets `chosen` (its index). Read out a
/// combo box named `label`. The trigger's node.
#callsite(autofill(loc))
pub fn dropdown_node(
  parent : @view.View,
  layer : Layer,
  options : Array[String],
  chosen : @signals.Signal[Int],
  label? : String = "",
  placeholder? : String = "Select",
  open? : @signals.Signal[Bool] = @signals.signal(false),
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> @view.View {
  let trigger = parent.box(made_for=loc, fn(t) {
    let live = fn() { !disabled() }
    t
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(space_md))
    .height(Is(Some(40.0)))
    .padding(Is((space_lg + space_xxs, 0.0, space_lg, 0.0)))
    .radius(Is(radius_md))
    .ground(By(fn() { if disabled() { colors().bg_disabled } else { colors().bg_primary } }))
    .edge(By(fn() {
      let c = colors()
      (1.0, if open.get() { c.border_brand } else { c.border_primary })
    }))
    .shadow(By(fn() { cast(shadow_xs, shadow_dark_xs) }))
    .says(By(fn() {
      let i = chosen.get()
      let value = if i >= 0 && i < options.length() { options[i] } else { "" }
      Some(@view.said(Combobox, label~, value~, expanded=open.get()))
    }))
    |> ignore
    presses_node(t, fn() { open.set(!open.untracked()) }, on=live)
    t.box(fn(w) {
      w
      .grow(Is(1.0))
      .words(
        By(fn() {
          let i = chosen.get()
          if i >= 0 && i < options.length() {
            options[i]
          } else {
            placeholder
          }
        }),
        look=words_in(type_small),
      )
      .ink(By(fn() {
        let c = colors()
        if disabled() {
          c.text_disabled
        } else if chosen.get() >= 0 {
          c.text_primary
        } else {
          c.text_placeholder
        }
      }))
      |> ignore
    })
    |> ignore
    icon_node(t, icon_chevron_down_small, 20.0, fn() { colors().fg_quaternary }).turn(By(fn() {
      if open.get() {
        3.141592653589793
      } else {
        0.0
      }
    }))
    |> ignore
    ring_node(t, fn() { radius_md })
  })
  let close = fn() { open.set(false) }
  let lit : @signals.Signal[Int] = @signals.signal(-1)
  let h = layer.holder(trigger)
  escape_closes(h, fn() { open.get() }, close)
  h.show(fn() { open.get() }, fn(c) { closes_outside(c, close, "Close " + label) })
  h.show(fn() { open.get() }, leave=ms_menu_exit, fn(m) {
    lit.set(chosen.untracked())
    let e = opening(m, fn() { open.get() }, ms_menu_enter, ms_menu_exit)
    m.beside(trigger.id(), side=Bottom, along=Start, offset=space_xs, width=Anchor) |> ignore
    m.padding(Is((0.0, space_sm, 0.0, space_sm))) |> ignore
    panel_look(m, e, radius_xl, fn() { colors().bg_popup_secondary }, fn() { cast(shadow_lg, shadow_dark_lg) })
    m.says(Is(Some(@view.said(Listbox, label~)))) |> ignore
    let items = fn() {
      let i = chosen.get()
      options.mapi(fn(j, o) { menu_item(o, fn() { chosen.set(j) }, checked=j == i) })
    }
    menu_rows(m, items, lit, close)
  })
  trigger
}

///|
/// Comma's popup of `anchor` in `layer`, open while `open` says: a card `width` wide (280, 360 or 480: Popup's sizes),
/// popup-primary, rounded 2xl, the primary border half a point, 16 in, the sm shadow, holding what `body` makes; under
/// `anchor` at its start, 8 off. Gone at a press outside it or Escape. Read out a dialog named `label`.
pub fn popup_node(
  layer : Layer,
  anchor : @view.View,
  open : @signals.Signal[Bool],
  body : (@view.View) -> Unit,
  label? : String = "Popup",
  width? : Double = 360.0,
) -> Unit {
  let close = fn() { open.set(false) }
  let h = layer.holder(anchor)
  escape_closes(h, fn() { open.get() }, close)
  h.show(fn() { open.get() }, fn(c) { closes_outside(c, close, "Close " + label) })
  h.show(fn() { open.get() }, leave=ms_hover_card_exit, fn(p) {
    let e = opening(p, fn() { open.get() }, ms_hover_card_enter, ms_hover_card_exit)
    p.beside(anchor.id(), side=Bottom, along=Start, offset=space_md) |> ignore
    p.width(Is(Some(width))).padding(Is((space_xl, space_xl, space_xl, space_xl))) |> ignore
    panel_look(p, e, radius_2xl, fn() { colors().bg_popup_primary }, fn() { cast(shadow_sm, shadow_dark_sm) })
    p.says(Is(Some(@view.said(Dialog, label~)))) |> ignore
    body(p)
  })
}

///|
/// Comma's dialog in `layer`, open while `open` says: over a scrim of the overlay's colour, in the window's middle, a
/// panel up to 400 wide (popup-primary, rounded xl, the primary border half a point, 16 in, the md shadow), 20 between
/// its parts: `title` (md, semibold, the primary's) with `description` under it (xs, the quaternary's), what `body`
/// makes, and its actions at its foot's end (`actions`: Comma's buttons). Taking all input while open (modal); gone at
/// a press on the scrim or Escape. Read out a dialog named `title`.
pub fn dialog_node(
  layer : Layer,
  open : @signals.Signal[Bool],
  title : () -> String,
  description? : () -> String = fn() { "" },
  body? : (@view.View) -> Unit = fn(_) {  },
  actions? : (@view.View) -> Unit = fn(_) {  },
  width? : Double = 400.0,
) -> Unit {
  let close = fn() { open.set(false) }
  match layer.at.val {
    None => @halt.saying("cm: a dialog made before its layer (layer_node)")
    Some(l) =>
      l.box(fn(h) {
        h.over(Is(true)) |> ignore
        h.show(fn() { open.get() }, leave=ms_dialog_exit, fn(s) {
          // (Escape taken by the dialog itself: what is under a modal layer takes no keys)
          escape_closes(s, fn() { open.get() }, close)
          let e = opening(s, fn() { open.get() }, ms_dialog_enter, ms_dialog_exit)
          s
          .over(Is(true))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .padding(Is((space_xl, space_xl, space_xl, space_xl)))
          |> ignore
          s.modal(Is(true)) |> ignore
          // (the scrim: a press on it closes the dialog)
          s.box(fn(c) {
            c
            .over(Is(true))
            // (Comma's bg-overlay-scrim: the overlay's colour at 60%, generate-css.ts)
            .ground(By(fn() { alpha(colors().bg_overlay, 0.6) }))
            .alpha(By(fn() { e.shown(c) }))
            .says(Is(Some(@view.said(Button, label="Close dialog"))))
            |> ignore
            c.presses(Is(true)).on_press(close) |> ignore
          })
          |> ignore
          s.box(fn(p) {
            p
            .width(Is(Some(width)))
            .max_width(Is(Some(width)), within=true)
            .gap(Is(space_2xl))
            .padding(Is((space_xl, space_xl, space_xl, space_xl)))
            .clips(Is(true))
            |> ignore
            panel_look(p, e, radius_xl, fn() { colors().bg_popup_primary }, fn() { cast(shadow_md, shadow_dark_md) })
            p.says(By(fn() { Some(@view.said(Dialog, label=title())) })) |> ignore
            p.box(fn(head) {
              head.gap(Is(space_xxs)) |> ignore
              head.box(fn(w) {
                w
                .words(By(title), look=words_in(type_regular, weight=weight_semibold, wrap=true))
                .ink(By(fn() { colors().text_primary }))
                |> ignore
              })
              |> ignore
              head.show(fn() { description() != "" }, fn(d) {
                d.words(By(description), look=words_in(type_mini, wrap=true)).ink(By(fn() { colors().text_quaternary }))
                |> ignore
              })
            })
            |> ignore
            body(p)
            p.box(fn(f) {
              f.row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Middle))).gap(Is(space_md)) |> ignore
              actions(f)
            })
            |> ignore
          })
          |> ignore
        })
      })
      |> ignore
  }
}
