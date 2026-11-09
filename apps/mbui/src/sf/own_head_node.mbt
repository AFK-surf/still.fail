// A page's own head and the small parts of a page's cards and sections (page.mbt's own_head, action, icon_action,
// figures, loose; parts.mbt's copy_command, field) as nodes of
// the window's tree made once: laid out by the arrangement of the page they are in (look_node), what they say followed
// as it changes; their styles the old view's, the same (style_node).

///|
/// A page's own head (own_head's) in `parent`, in place of its title (page_node's `head`): its `mark` in its box (given
/// the box's side), its `name`, renamed by `rename` (said `rename_label`) while `renames` says it may be, `busy` while
/// it is saved; `tags` (its runtimes: what it is); `lines` of what it is and where; how it stands under them (`state`),
/// what it does at the end of its name's line (`actions`); `dot` (a state's: online, offline …; "" none) before its
/// first line, `state` only while `state_shown` says, what is wrong with it under all of them (`warnings`: its words,
/// red or else amber). Wide, the web's identity: its mark 48, its name large with
/// its tags and a pencil after it, the lines under it as wide as its words. Narrow: its mark, its name and what it does
/// in one line (what it does on back's line over it where the page puts back there: head_back_holds), the name a size
/// under the page's large title on as many lines as it takes, pressed to rename it; its tags and lines under them.
#callsite(autofill(loc))
pub fn own_head_node(
  parent : @view.View,
  mark : (@view.View, Double) -> Unit,
  name : () -> String,
  rename? : () -> Unit,
  renames? : () -> Bool = fn() { true },
  rename_label? : () -> String = fn() { "" },
  busy? : () -> Bool = fn() { false },
  tags? : (@view.View) -> Unit,
  lines? : () -> Array[String] = fn() { [] },
  state? : (@view.View) -> Unit,
  actions? : (@view.View) -> Unit,
  dot? : () -> String = fn() { "" },
  state_shown? : () -> Bool = fn() { true },
  warnings? : () -> Array[(String, Bool)] = fn() { [] },
  loc~ : SourceLoc,
) -> Unit {
  let narrow = look_node(parent) is Narrow
  let shown = fn() { lines().filter(fn(l) { l != "" }) }
  let line_look = fn() { if narrow { head_line_narrow } else { head_line } }
  // what is under its name: the first line (narrow its tags, what it is), the others, how it stands
  let below = fn(b : @view.View) {
    b.show(fn() { shown().length() > 0 || (narrow && tags is Some(_)) || dot() != "" }, fn(r) {
      style_node(r, fn() { head_line_row })
      r.show(fn() { dot() != "" }, fn(d) { state_dot_node(d, dot) })
      if narrow {
        match tags {
          Some(f) => f(r)
          None => ()
        }
      }
      r.show(fn() { shown().length() > 0 }, fn(w) {
        w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        words_node(w, fn() { shown().get(0).unwrap_or("") }, line_look) |> ignore
      })
    })
    b.each(fn() { shown().mapi(fn(i, l) { (i, l) }).filter(fn(x) { x.0 > 0 }) }, fn(x) { x.0 }, fn(w, x) {
      words_node(w, fn() { x.get().1 }, line_look) |> ignore
    })
    match state {
      Some(f) =>
        b.show(state_shown, fn(x) {
          x.box(fn(s) {
            style_node(s, fn() { head_state })
            // (going on in the next line where its line has not the room: head_state's flow)
            s.wraps(Is(Some(0.0))) |> ignore
            f(s)
          })
          |> ignore
        })
      None => ()
    }
    // (red where it does not work, else amber)
    b.each(fn() { warnings().mapi(fn(i, w) { (i, w) }) }, fn(x) { x.0 }, fn(w, x) {
      words_node(w, fn() { x.get().1.0 }, fn() { if x.get().1.1 { head_warn_red } else { head_warn_amber } }) |> ignore
    })
  }
  let end = fn(e : @view.View) {
    match actions {
      Some(f) =>
        e.box(fn(a) {
          style_node(a, fn() { head_actions })
          f(a)
        })
        |> ignore
      None => ()
    }
  }
  if narrow {
    let at_back = parent.lent(head_back_holds).unwrap_or(fn() { false })
    parent.box(made_for=loc, fn(h) {
      // (16 over what follows; under a state's line, its button's room is that room already)
      style_node(h, fn() { if state is None || !state_shown() { head_narrow.then(head_narrow_foot) } else { head_narrow } })
      h.box(fn(top) {
        style_node(top, fn() { head_top_narrow })
        top.box(fn(m) {
          style_node(m, fn() { head_mark_narrow })
          mark(m, head_mark_narrow_side)
        })
        |> ignore
        top.box(fn(words) {
          style_node(words, fn() { pg_row_words }, in_row=true)
          words.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          // its name a size under the page's large title (its mark beside it: a phone's line), on as many lines as it
          // takes (an address broken after its @ and its dots, not inside a word of it), pressed to rename it
          words.box(fn(n) {
            match rename {
              Some(f) => {
                presses_node(n, f, on=renames)
                n
                .says(By(fn() {
                  if renames() {
                    Some(@view.said(Button, label=if rename_label() == "" { name() } else { rename_label() }))
                  } else {
                    None
                  }
                }))
                .alpha(By(fn() { if renames() && n.pressed() { head_pressed_alpha } else { 1.0 } }))
                |> ignore
              }
              None => ()
            }
            words_node(n, fn() { name().replace_all(old="@", new="@\u{200B}").replace_all(old=".", new=".\u{200B}") }, fn() {
              head_name_lines
            })
            |> ignore
          })
          |> ignore
          words.show(busy, fn(s) { spinner_node(s, size=spinner_inline) |> ignore })
        })
        |> ignore
        top.show(fn() { !at_back() }, end)
      })
      |> ignore
      below(h)
    })
    |> ignore
    return
  }
  parent.box(fn(h) {
    style_node(h, fn() { head_wide })
    h.box(fn(m) {
      style_node(m, fn() { head_mark_wide })
      mark(m, head_mark_wide_side)
    })
    |> ignore
    h.box(fn(id) {
      style_node(id, fn() { head_identity }, in_row=true)
      id.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      // its name and what it does on the name's line, the lines under them as wide as its words (lines of their own)
      id.box(fn(row) {
        style_node(row, fn() { head_name_row })
        row.box(fn(l) {
          style_node(l, fn() { head_name_line.then(head_name_grow) }, in_row=true)
          l.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          // (short of room, its name is cut short, what follows it kept)
          words_node(l, name, fn() { head_name_wide }).shrink(Is(1.0)) |> ignore
          l.show(busy, fn(s) { spinner_node(s, size=spinner_inline) |> ignore })
          match tags {
            Some(f) =>
              l.box(fn(t) {
                style_node(t, fn() { head_tags_wide })
                t.row(Is(true)) |> ignore
                f(t)
              })
              |> ignore
            None => ()
          }
          match rename {
            Some(f) => l.show(renames, fn(e) { icon_action_node(e, "edit", rename_label, f) |> ignore })
            None => ()
          }
        })
        |> ignore
        end(row)
      })
      |> ignore
      below(id)
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far a narrow own head's name is seen while it is pressed to rename it (head_name_press's pressed{opacity=O60}).
let head_pressed_alpha : Double = 0.6

///|
/// A button of a mark alone (icon_action's, as a node: a head's rename, check again, ⋯) in `parent`, said to be
/// `label`: as wide as the native input's hand needs (a finger's 44, a pointer's 32); `press` done as it is pressed,
/// while it is not `disabled`. The node.
#callsite(autofill(loc))
pub fn icon_action_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  disabled? : () -> Bool = fn() { false },
  tips? : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  icon_action_by(loc~, parent, icon, label, fn(_) { press() }, disabled, tips)
}

///|
/// icon_action_node's button that opens what goes beside it (a ⋯'s menu): `open` given the button itself as it is
/// pressed, where it is placed then.
#callsite(autofill(loc))
pub fn icon_action_opens_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  open : (@view.View) -> Unit,
  disabled? : () -> Bool = fn() { false },
  tips? : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  icon_action_by(loc~, parent, icon, label, open, disabled, tips)
}

///|
/// icon_action_node's button, `press` given the button itself: as wide as the native input's hand needs.
#callsite(autofill(loc))
fn icon_action_by(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : (@view.View) -> Unit,
  disabled : () -> Bool,
  tips : TipLayer?,
  loc~ : SourceLoc,
) -> @view.View {
  if native_input() is Finger {
    icon_button_by(loc~, parent, icon, label, press, tips, touch_target, touch_glyph, None, disabled)
  } else {
    icon_button_by(parent, icon, label, press, tips, icon_button_side, 16.0, None, disabled)
  }
}

///|
/// What a part does at its heading's end (action's, as a node: section_node's `ends`): wide, the quiet button with its
/// mark; narrow, the heading's trailing words in the link's ink, room round them for a finger, rippling as pressed; a
/// spinner in their place while it is `busy`; `bad`: one that takes something away, in the red. `press` done as it is
/// pressed, while it is not `disabled`.
#callsite(autofill(loc))
pub fn action_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  icon? : String = "",
  busy? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
  bad? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  match look_node(parent) {
    Wide => button_node(loc~, parent, label, press, tone=if bad { GhostDanger } else { Ghost }, icon~, busy~, disabled~) |> ignore
    Narrow =>
      parent.pick(fn() { if busy() { 0 } else if disabled() { 1 } else { 2 } }, fn(p, what) {
        match what {
          0 => spinner_node(p, size=spinner_inline) |> ignore
          _ =>
            p.box(fn(a) {
              style_node(a, fn() { pg_action })
              if what == 2 {
                pressed_node(a, press, Is(row_corner), Button, label)
              }
              words_node(a, label, fn() { if bad { pg_action_bad } else { pg_action_words } }) |> ignore
            })
            |> ignore
        }
      })
  }
}

///|
/// A command to copy (copy_command's, as a node) in `parent`: `text` in the code face (12) on one line, its copy button
/// at its end, on the paper, 14 in at its start; pressed, the words copied and a check for a moment (copied_ms from the
/// press: `copied` its name then, `copy` before).
#callsite(autofill(loc))
pub fn copy_command_node(
  parent : @view.View,
  text : () -> String,
  copy~ : String,
  copied~ : String,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(b) {
    // (已复制 from each press till copied_ms after it, a press while it shows starting it again: the box's own, let go
    // with it; a time it shows for, not waited for)
    let (copied_now, just) = b.holds_for(copied_ms, later=true)
    style_node(b, fn() { command_box })
    b.ground(By(fn() { theme().p.paper })) |> ignore
    b.box(fn(w) {
      style_node(w, fn() { command_words_at }, in_row=true)
      w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words_node(w, text, fn() { command_words }) |> ignore
    })
    |> ignore
    icon_button_node(
      b,
      "copy",
      fn() { if just() { copied } else { copy } },
      fn() {
        @ui.clipboard_set(@signals.untracked(text))
        copied_now()
      },
      icon_now=fn() { if just() { "check" } else { "copy" } },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Figures side by side (figures', as a node) in `parent`: what each is, its number large, a line under it where it has
/// one, as `figures` says them now, on the page's ground as cards of their own; always on one line, sharing it: narrow,
/// closer and their numbers a size smaller, each's line under it there only where it fits whole.
#callsite(autofill(loc))
pub fn figures_node(parent : @view.View, figures : () -> Array[(String, String, String)], loc~ : SourceLoc) -> Unit {
  let narrow = look_node(parent) is Narrow
  parent.box(made_for=loc, fn(o) {
    style_node(o, fn() { if narrow { pg_card_room } else { wide_block } })
    o.box(fn(r) {
      style_node(r, fn() { if narrow { fig_row_narrow } else { fig_row } })
      r.each(fn() { figures().mapi(fn(i, f) { (i, f) }) }, fn(x) { x.0 }, fn(tile, x) {
        style_node(tile, fn() { if narrow { fig_tile_narrow } else { fig_tile } }, in_row=true)
        words_node(tile, fn() { x.get().1.0 }, fn() { fig_label }) |> ignore
        words_node(tile, fn() { x.get().1.1 }, fn() { if narrow { fig_value_narrow } else { fig_value } }) |> ignore
        tile.show(fn() { x.get().1.2 != "" }, fn(s) {
          if narrow {
            // (its line under it whole, or none: words cut short say nothing)
            s.box(fn(l) {
              style_node(l, fn() { fig_sub_line })
              l.fits(Is(true)) |> ignore
              words_node(l, fn() { x.get().1.2 }, fn() { fig_sub_whole }).drops(Is(1)) |> ignore
            })
            |> ignore
          } else {
            words_node(s, fn() { x.get().1.2 }, fn() { fig_sub }) |> ignore
          }
        })
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a section holds that is neither rows nor a card (loose's, as a node: its chips, a field with its button) in
/// `parent`, what `body` makes in it 12 apart: narrow, as far in as the page's headings' words, 10 under it; wide, at
/// the column's edges.
#callsite(autofill(loc))
pub fn loose_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let narrow = look_node(parent) is Narrow
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { if narrow { pg_loose } else { wide_block } })
    body(b)
  })
  |> ignore
}

///|
/// A field (field's, as a node) in `parent`: its `label` (13, 500), what `body` makes (the input), and under it what is
/// wrong (`error`, 12 red) or else a `hint` (12, muted), as each says it now, 6 apart; on a wide page 420 at most.
#callsite(autofill(loc))
pub fn labelled_field_node(
  parent : @view.View,
  label : () -> String,
  body : (@view.View) -> Unit,
  hint? : () -> String = fn() { "" },
  error? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  let wide = look_node(parent) is Wide
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { if wide { field_box_wide } else { field_box } })
    words_node(b, label, fn() { field_label }) |> ignore
    body(b)
    b.show(fn() { error() != "" }, fn(w) { words_node(w, error, fn() { field_error }) |> ignore })
    b.show(fn() { error() == "" && hint() != "" }, fn(w) { words_node(w, hint, fn() { field_hint }) |> ignore })
  })
  |> ignore
}
