// The security pages' rows and cards as nodes. The page gives their content; the parts arrange it by its width.

///|
/// The rows of a security section: a list card when narrow, a card of rows 12 apart when wide. A button at the
/// top or bottom of the wide card sits in its corner, with the same inset as a card's foot button.
pub fn security_group_node(
  parent : @view.View,
  rows : (@view.View) -> Unit,
  top_button? : () -> Bool = fn() { false },
  bottom_button? : () -> Bool = fn() { false },
) -> Unit {
  if look_node(parent) is Narrow {
    group_node(parent, rows)
  } else {
    let at = part_of(parent)
    let make = fn(p : @view.View) {
      p.box(fn(card) {
        card
        .padding(By(fn() {
          let inset = card_foot_in(button_height())
          (card_pad, if top_button() { inset } else { card_pad }, card_pad, if bottom_button() { inset } else { card_pad })
        }))
        .gap(Is(12.0))
        .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
        .ground(By(fn() { @ui.tree_theme().color(Card) }))
        .lends(part_at, { ..at, list: false })
        |> ignore
        rows(card)
      })
      |> ignore
    }
    if at.section {
      make(parent)
    } else {
      parent.box(fn(room) {
        room.padding(Is((0.0, 0.0, 0.0, 28.0))) |> ignore
        make(room)
      })
      |> ignore
    }
  }
}

///|
/// A security row: a mark, its title and note, a value at its end and optional actions. Wide notes follow the title;
/// narrow notes and actions have their own lines. A droppable note goes whole when its line has not the room.
pub fn security_line_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  mark? : (@view.View) -> Unit,
  end? : (@view.View) -> Unit,
  acts? : (@view.View) -> Unit,
  acts_shown? : () -> Bool = fn() { true },
  indent? : Bool = false,
  warn? : () -> Bool = fn() { false },
  strong? : Bool = true,
  drops? : Bool = false,
) -> Unit {
  let wide = look_node(parent) is Wide
  parent.box(fn(row) {
    if wide {
      row.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))).min_height(Is(Some(30.0))) |> ignore
      match mark { Some(f) => f(row); None => () }
      row.box(fn(body) {
        body.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        body.box(fn(line) {
          line.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(End))).fits(Is(drops)) |> ignore
          line.show(fn() { title() != "" }, fn(t) {
            t.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            words_node(t, title, fn() { if strong { security_row_name } else { security_row_words } }) |> ignore
          })
          line.show(fn() { note() != "" }, fn(n) {
            if drops {
              n.drops(Is(1)) |> ignore
            } else {
              n.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
            }
            words_node(n, note, fn() { if warn() { security_warn } else { security_row_meta } }) |> ignore
          })
        }) |> ignore
      }) |> ignore
      match end { Some(f) => f(row); None => () }
      match acts {
        Some(f) => row.show(acts_shown, fn(a) { a.row(Is(true)).gap(Is(12.0)) |> ignore; f(a) })
        None => ()
      }
    } else {
      row.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle)))
      .padding(Is((if indent { 24.0 } else { 12.0 }, 10.0, 12.0, 10.0))) |> ignore
      let words = fn(at : @view.View) {
        match mark { Some(f) => f(at); None => () }
        security_narrow_words_node(at, title, note, end, warn)
      }
      match acts {
        None => words(row)
        Some(f) =>
          row.box(fn(content) {
            content.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            content.box(fn(top) {
              top.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
              words(top)
            }) |> ignore
            content.show(acts_shown, fn(a) {
              a.row(Is(true)).gap(Is(20.0))
              .padding(Is((if mark is Some(_) { 28.0 } else { 0.0 }, 6.0, 0.0, 0.0))) |> ignore
              f(a)
            })
          }) |> ignore
      }
    }
  }) |> ignore
}

///|
/// The title, end and note in a narrow security row, beside its optional mark.
fn security_narrow_words_node(
  parent : @view.View,
  title : () -> String,
  note : () -> String,
  end : ((@view.View) -> Unit)?,
  warn : () -> Bool,
) -> Unit {
  parent.box(fn(body) {
    body.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
    body.box(fn(line) {
      line.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
      line.box(fn(t) {
        t.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        words_node(t, title, fn() { pg_row_title }) |> ignore
      }) |> ignore
      match end {
        Some(f) => line.box(fn(e) { e.row(Is(true)).height_share(Is(1.0)).gap(Is(8.0)).lines_up(Is(Some(Start))) |> ignore; f(e) }) |> ignore
        None => ()
      }
    }) |> ignore
    body.show(fn() { note() != "" }, fn(n) {
      words_node(n, note, fn() { if warn() { security_narrow_warn } else { pg_link_note } }) |> ignore
    })
  }) |> ignore
}

///|
/// What a security row says at its end (a role or protection state), never cut short.
pub fn security_end_node(parent : @view.View, words : () -> String, warn? : () -> Bool = fn() { false }) -> Unit {
  let wide = look_node(parent) is Wide
  words_node(parent, words, fn() {
    if wide { if warn() { security_warn_state } else { security_row_state } }
    else { if warn() { security_narrow_end_warn } else { security_narrow_end } }
  }) |> ignore
}

///|
/// A member's name and role: the role follows the name wide, and stands at the end of the first line narrow.
pub fn security_person_node(parent : @view.View, name : () -> String, role : () -> String) -> Unit {
  let wide = look_node(parent) is Wide
  security_line_node(parent, name, fn() { if wide { role() } else { "" } }, end=fn(e) {
    if !wide { security_end_node(e, role) }
  })
}

///|
/// A device's action: a quiet button wide, link-coloured words narrow, a spinner in its place while busy.
pub fn security_action_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
) -> Unit {
  if look_node(parent) is Wide {
    button_node(parent, label, press, tone=Ghost, busy~) |> ignore
  } else {
    parent.pick(busy, fn(p, working) {
      if working { spinner_node(p, size=14.0) |> ignore } else { tap_text_node(p, label, press) }
    })
  }
}

///|
/// A station's state and name. When it has a mark, the wide row puts the mark and name together after the state dot;
/// the narrow row keeps the name as its title. `end` makes the protection state or the action to protect it.
pub fn security_station_line_node(
  parent : @view.View,
  name : () -> String,
  note : () -> String,
  guarded : () -> Bool,
  emoji : () -> String,
  icon : () -> String,
  stint : () -> Int,
  end : (@view.View) -> Unit,
) -> Unit {
  let wide = look_node(parent) is Wide
  let named = fn() { wide && has_station_mark(emoji(), icon()) }
  security_line_node(parent, fn() { if named() { "" } else { name() } }, note, mark=fn(m) {
    m.box(fn(dot) {
      dot.width(Is(Some(7.0))).height(Is(Some(7.0))).radius(Is(1000.0))
      .ground(By(fn() { @ui.tree_theme().color(if guarded() { Positive } else { Warn }) })) |> ignore
    }) |> ignore
    m.show(named, fn(mark) {
      mark.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
      station_mark_node(mark, emoji, icon, row_mark, fn() { theme().p.text }, stint)
      words_node(mark, name, fn() { security_row_name }) |> ignore
    })
  }, end~)
}

///|
/// A station's protection button, reaching the wide card's edge so its outer corners follow the card.
pub fn security_join_button_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
) -> Unit {
  let button = button_node(parent, label, press, tone=Ghost, busy~)
  if look_node(parent) is Wide {
    button.margin(Is((0.0, 0.0, card_foot_in(button_height()) - card_pad, 0.0))) |> ignore
  }
}

///|
/// A dangerous action below security: a danger button wide, a red row on its own card narrow.
pub fn security_danger_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
) -> Unit {
  if look_node(parent) is Wide {
    parent.box(fn(line) {
      line.row(Is(true)) |> ignore
      button_node(line, label, press, tone=Danger, busy~) |> ignore
    }) |> ignore
  } else {
    parent.box(fn(foot) {
      foot.padding(Is((0.0, 16.0, 0.0, 0.0))) |> ignore
      group_node(foot, fn(g) {
        g.box(fn(row) {
          row.row(Is(true)).padding(Is((12.0, 10.0, 12.0, 10.0))).lines_up(Is(Some(Middle)))
          .min_height(By(fn() { Some(theme().items.least) })) |> ignore
          row.box(fn(hit) {
            hit.over(Is(true)).width_share(Is(1.0)).height_share(Is(1.0)) |> ignore
            pressed_node(hit, fn() { if !@signals.untracked(busy) { press() } }, Is(row_corner), Button, label)
            hit.presses(By(fn() { !busy() })).focusable(By(fn() { !busy() })) |> ignore
          }) |> ignore
          words_node(row, label, fn() { body.then(bad) }).grow(Is(1.0)) |> ignore
          row.show(busy, fn(s) { spinner_node(s, size=14.0) |> ignore })
        }) |> ignore
      })
    }) |> ignore
  }
}

///|
/// A person's devices under their row: wide, 12 below the person, 40 in and 8 apart; narrow, their rows make the inset.
pub fn security_devices_node(parent : @view.View, rows : (@view.View) -> Unit) -> Unit {
  let wide = look_node(parent) is Wide
  parent.box(fn(devices) {
    if wide { devices.padding(Is((40.0, 12.0, 0.0, 0.0))).gap(Is(8.0)) |> ignore }
    rows(devices)
  }) |> ignore
}

///|
/// One app's devices, with its app name above the first and extra room above subsequent app groups.
pub fn security_device_group_node(
  parent : @view.View,
  title : () -> String,
  rows : (@view.View) -> Unit,
  apart? : () -> Bool = fn() { false },
) -> Unit {
  let wide = look_node(parent) is Wide
  parent.box(fn(group) {
    if wide { group.gap(Is(8.0)) |> ignore }
    group.box(fn(head) {
      head.padding(By(fn() {
        if wide { (0.0, if apart() { 6.0 } else { 0.0 }, 0.0, 0.0) }
        else { (24.0, 6.0, 12.0, 0.0) }
      })) |> ignore
      words_node(head, title, fn() { if wide { security_over_words } else { security_narrow_over_words } }) |> ignore
    }) |> ignore
    rows(group)
  }) |> ignore
}

///|
/// What signing means and its actions, flowing onto another line when the page has not the room.
pub fn security_footer_node(parent : @view.View, note : () -> String, actions : (@view.View) -> Unit) -> Unit {
  let wide = look_node(parent) is Wide
  parent.box(fn(foot) {
    foot.row(Is(true)).padding(Is((if wide { 0.0 } else { 4.0 }, if wide { 20.0 } else { 16.0 }, if wide { 0.0 } else { 4.0 }, 0.0)))
    .gap(Is(12.0)).lines_up(Is(Some(Middle))).wraps(Is(Some(12.0))) |> ignore
    words_node(foot, note, fn() { security_footer_note }) |> ignore
    foot.box(fn(a) { a.row(Is(true)).gap(Is(10.0)).lines_up(Is(Some(Middle))) |> ignore; actions(a) }) |> ignore
  }) |> ignore
}

///|
let security_row_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, weight=Medium, color=Fg, wrap=false)
///|
let security_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false)
///|
let security_row_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false, w=Cut)
///|
let security_row_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)
///|
let security_warn : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false, w=Cut)
///|
let security_warn_state : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=WarnInk, wrap=false)
///|
let security_narrow_warn : @ui.TextStyle = pg_link_note.then(@ui.text_style(color=WarnInk))
///|
let security_narrow_end : @ui.TextStyle = secondary.then(one_line)
///|
let security_narrow_end_warn : @ui.TextStyle = security_narrow_end.then(@ui.text_style(color=WarnInk))
///|
let security_over_words : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, weight=Medium, color=Muted, wrap=false, w=Cut)
///|
let security_narrow_over_words : @ui.TextStyle = secondary.then(@ui.text_style(weight=Medium, wrap=false, w=Cut))
///|
let security_footer_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)
