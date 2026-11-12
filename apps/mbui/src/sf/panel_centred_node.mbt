// A panel of the presenters' opened by nothing (panel_centred's: the library's dialog, a panel in the middle of the
// window) as nodes of the window's tree: the presenters' dialog layer (dialog_layer_node: a press outside it closes it,
// as a dialog's does), its frame as dialog draws it (dialog_w wide, dialog_wide_w where `wide`, the window less
// dialog_margin at most, no taller than it less dialog_room; 24 in, a line round it, dialog_r round, the panel's ground
// and shadow); its head (its title and its close button, what it says under them, or its close button alone in its top
// corner where it has no title), what it holds and its foot each the old frame's, built in a hosted view out to the
// dialog's edges they stand by, the dialog's padding inside them (or nodes where they are, panel_nodes: laid out as
// those are), what it holds scrolling where the window leaves the dialog short of room. Escape, back, a press outside and its close button close it (its gone told); what it holds
// closes it with what it was given (nothing told).

///|
/// A centred panel `x` in `parent` while `open()` (going over pop_out_ms once not); `key`: what its old views are named
/// by (the presented's); `close`: what what it holds is given to close it; `cancel` as it is closed by its close button,
/// Escape, back or a press outside. `shown`, `gone`: as dialog_layer_node's.
fn panel_centred_node(
  parent : @view.View,
  key : String,
  open : () -> Bool,
  x : PanelOf,
  close : () -> Unit,
  cancel : () -> Unit,
  keyed : Presented,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Bool = fn() { false },
) -> Unit {
  // (one that goes in steps: Escape and back a step back first, its steps' own)
  // (a step further in from a panel: back to that one)
  let within = fn() { steps_escape(keyed) || back_under(keyed) }
  // (its own ground keeps the focus as it opens, none of what it holds given it: a search at hand by touch)
  let own_ground : Ref[Bool] = Ref(false)
  dialog_layer_node(parent, open, cancel, outside=true, first_stop=fn() { keyed.steps is None && !own_ground.val }, first_takes?=if x.nodes is Some(_) { Some(fn(s : @view.Said) { opens_on_role(s.role) }) } else { None }, shown~, gone~, dims~, covered~, within~, fn(across, layer, look, veil) {
    let theme = fn() { @ui.tree_theme() }
    // (one that goes in steps: each its own head and foot, sliding in whole; the dialog untitled round them)
    let steps = keyed.steps
    // (its title, step and what it says as they are now: `live`'s, read where each is used and followed as it changes;
    // its head there or not as they say, what holds what it holds the same)
    let now = fn() {
      match x.live {
        Some(f) => f()
        None => (x.title, "", x.description)
      }
    }
    let untitled = fn() {
      steps is Some(_) || {
        let (title, step, _) = now()
        title == "" && step == "" && x.title_row is None
      }
    }
    let w = fn() { dmin(if x.wide { dialog_wide_w } else { dialog_w }, over_room(layer).0 - dialog_margin) }
    // (its old views' words as far in as its look says, as kit's dialog's look gives them: read as they are painted)
    let words_look = fn(c : @ui.Ctx, held : Int) {
      c.look_by(held, fn() {
        { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: look().words }
      })
    }
    // (its close button in its top corner, an old view in `o` (`let_go`: its field let go of first, field_let_go))
    let close_old = fn(o : @view.View, let_go : Bool) {
      @ui.old(o, natural=true, key=fn() { key + "/close" }, fn(c) {
        let held = c.box(style=dialog_close_row, fn() {
          c.box(style=dialog_close_corner(), fn() {
            icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=t("common.close"), on_press=fn() {
              if let_go {
                field_let_go(keyed)
              }
              cancel()
            }) |> ignore
          })
          |> ignore
        })
        words_look(c, held)
      })
      |> ignore
    }
    // (what it holds and its head on the line of its words, a row's padding in: panel_centred's)
    let words_in = panel_words - dialog_pad
    // (what it holds and its foot nodes, panel_nodes')
    let foot_nodes = x.nodes.bind(fn(n) { n.foot })
    let footed = x.foot is Some(_) || foot_nodes is Some(_)
    let in_words = fn(f : () -> Unit) {
      let was = words_in_now.val
      words_in_now.val = words_in
      f()
      words_in_now.val = was
    }
    // (which of what it holds takes the focus as it opens, where what it holds says one: panel_opens_on_node)
    let opens_on : Ref[@view.View?] = Ref(None)
    // (and the field it opens to be typed in, before that: panel_opens_in_node, panel_search_at_hand_node)
    let field : Ref[PanelField?] = Ref(None)
    // (what its fields offer made in its layer: offers_layer_lent)
    offers_layer_lend(layer)
    across.box(fn(d) {
      d.lends(panel_opens_lent, opens_on) |> ignore
      d.lends(panel_field_lent, field) |> ignore
      d
      .width(By(fn() { Some(w()) }))
      // (no taller than the window leaves it, dialog_room: what it holds scrolls in itself past that)
      .max_height(By(fn() { Some(dmax(0.0, over_room(layer).1 - dialog_room)) }))
      // (dialog_box: 24 over its title, 24 in at its sides; each part out to them, the padding inside it)
      .padding(Is((dialog_pad, dialog_pad, dialog_pad, 0.0)))
      .radius(Is(dialog_r))
      .ground(By(fn() { panel_ground() }))
      .edge(By(fn() { (1.0, theme().color(Line)) }))
      .shadow(By(fn() { (dialog_shadow, dialog_shadow_y, library_theme().p.shadow) }))
      .clips(Is(true))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      // (one that goes in steps read out by its own title still: what its steps say is theirs)
      .says(By(fn() {
        let (title, _, description) = if steps is Some(_) { (x.title, "", x.description) } else { now() }
        Some(@view.said(Dialog, label=title, description~))
      }))
      // (a press on it its own: not outside it)
      |> ground_node
      |> ignore
      // (where what it holds starts: under an untitled one's close button; right under a title row of its own, which
      // keeps what space it wants under it, as what it holds kept it when it drew that row itself; a title's gap else)
      let body_top = fn() {
        if untitled() {
          dialog_untitled_top()
        } else if x.title_row is Some(_) {
          title_row_under
        } else {
          no_style
        }
      }
      // (untitled: its close button alone over its top corner, concentric with it, there while it is untitled: built
      // first, as dialog built its layer before what it holds (read out first, drawn under what comes after it); one
      // whose title is as it is now (`live`) built after what it holds and its foot, as the old frame builds it now (read
      // out last, drawn over them))
      // (its close button as nodes, where what it holds is nodes (panel_nodes): its field let go of first, as the old
      // frame has it: field_let_go)
      // (no stop of Tab's, as the old frame's close button takes no focus: a press, Escape and back close it)
      let close_node = fn(v : @view.View) {
        icon_button_node(v, "close", fn() { t("common.close") }, fn() {
          field_let_go(keyed)
          cancel()
        }, size=dialog_close)
        .tab_stop(Is(false))
        |> ignore
      }
      let corner = fn() {
        // (one titled by a row of its own (title_row): its close button in its corner as an untitled one's, not on that
        // row's line: the user, 2026-11-04, x 不要跟着 title 走)
        d.show(fn() { steps is None && (untitled() || x.title_row is Some(_)) }, fn(o) {
          o.over(Is(true)).width(By(fn() { Some(w()) })) |> ignore
          if x.nodes is Some(_) {
            o.box(fn(row) {
              style_node(row, fn() { dialog_close_row })
              row.alpha(By(fn() { look().words })) |> ignore
              row.box(fn(at) {
                style_node(at, fn() { dialog_close_corner() })
                close_node(at)
              })
              |> ignore
            })
            |> ignore
            return
          }
          // (its field let go of first, as the old frame has it: field_let_go)
          close_old(o, true)
        })
      }
      if x.live is None {
        corner()
      }
      // (its head: its title (its step beside it) and its close button at its end where it has a title, what it says
      // under them where it says something: dialog's, as they are now)
      d.show(fn() { steps is None && (!untitled() || now().2 != "") }, fn(h) {
        h.margin(Is((-dialog_pad, -dialog_pad, -dialog_pad, 0.0))) |> ignore
        // (where what it holds is nodes (panel_nodes, which takes no title_row): its head nodes too, as the old frame's
        // is laid out, its words as faint as its look says)
        if x.nodes is Some(_) {
          // (as wide as the dialog, out to its sides: the old frame's head's room)
          h.width(By(fn() { Some(w()) })) |> ignore
          h.box(fn(part) {
            style_node(part, fn() { centred_part_in(dialog_pad, 0.0) })
            part.alpha(By(fn() { look().words })) |> ignore
            // (its title's line, there while it has a title: its title, its step beside it, its close button at its end)
            part.box(fn(line) {
              style_node(line, fn() { dialog_head.then(@ui.style(pl=room(words_in))) })
              line.laid_nowhere(By(untitled)) |> ignore
              // (a step further in from a panel: its back key before its title, back to that one)
              let stepped = keyed.under is Some(_)
              if stepped {
                line.box(fn(k) {
                  style_node(k, fn() { dialog_back_at }, in_row=true)
                  icon_button_node(k, "chevron-left", fn() { t("common.back") }, fn() { back_under(keyed) |> ignore }, size=step_back_side)
                  |> ignore
                })
                |> ignore
              }
              line.box(fn(l) {
                style_node(l, fn() { dialog_title_line }, in_row=true)
                l.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                if stepped {
                  l.grow(Is(1.0)) |> ignore
                }
                words_node(l, fn() { now().0 }, fn() { if now().1 != "" { dialog_title_one } else { dialog_title } })
                |> ignore
                words_node(l, fn() { now().1 }, fn() { dialog_step }) |> ignore
              })
              |> ignore
              line.box(fn(at) {
                style_node(at, fn() { dialog_close_at() }, in_row=true)
                close_node(at)
              })
              |> ignore
            })
            |> ignore
            part.show(fn() { now().2 != "" }, fn(lead) {
              style_node(lead, fn() { dialog_lead_at.then(@ui.style(pl=room(words_in))) })
              words_node(lead, fn() { now().2 }, fn() { dialog_lead }) |> ignore
            })
          })
          |> ignore
          return
        }
        @ui.old(h, natural=true, key=fn() { key + "/head" }, fn(c) {
          let (title, step, description) = now()
          let held = c.box(style=centred_part_in(dialog_pad, 0.0), fn() {
            in_words(fn() {
              let words_at = @ui.style(pl=room(words_in_now.val))
              if !untitled() {
                c.box(style=dialog_head.then(words_at), fn() {
                  // (a step further in from a panel: its back key before its title, back to that one)
                  let stepped = keyed.under is Some(_)
                  if stepped {
                    c.box(style=dialog_back_at, fn() {
                      icon_button(c, "chevron-left", key=key + "/back", size=step_back_side, round=true, label=t("common.back"), on_press=fn() {
                        back_under(keyed) |> ignore
                      }) |> ignore
                    })
                    |> ignore
                  }
                  // (a step's count beside the title: dialog's)
                  if step != "" {
                    c.box(style=dialog_title_line, fn() {
                      c.text(title, style=dialog_title_one) |> ignore
                      c.text(step, style=dialog_step) |> ignore
                    })
                    |> ignore
                  } else {
                    match x.title_row {
                      // (what it draws in its title's place, as wide as the row leaves it clear of the close button in the
                      // corner over its end: title_row)
                      Some(f) =>
                        c.box(style=title_row_room.then(@ui.style(pr=room(dialog_close_clear()))), fn() { f(c) }) |> ignore
                      None =>
                        if stepped {
                          c.box(style=sheet_row_words_at, fn() { c.text(title, style=dialog_title) |> ignore }) |> ignore
                        } else {
                          c.text(title, style=dialog_title) |> ignore
                        }
                    }
                  }
                  if x.title_row is None {
                    c.box(style=dialog_close_at(), fn() {
                      icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=t("common.close"), on_press=fn() {
                        // (its field let go of first, as the old frame has it: field_let_go)
                        field_let_go(keyed)
                        cancel()
                      }) |> ignore
                    })
                    |> ignore
                  }
                })
                |> ignore
              }
              if description != "" {
                c.box(style=dialog_lead_at.then(words_at), fn() { c.text(description, style=dialog_lead) |> ignore }) |> ignore
              }
            })
          })
          words_look(c, held)
        })
        |> ignore
      })
      // (a share of the window tall, not a form (one as tall as what it holds, whatever its share): what it holds as tall
      // as its lists say they would be, up to that share, filling it where none says (measured_body's, capped_want's); no
      // taller than the dialog leaves it, laid out in that, its lists giving way and scrolling in themselves (old's
      // `gives`), nothing of it scrolling past it)
      if x.tall > 0.0 && !x.form && steps is None && x.nodes is Some(n) {
        // (what it holds nodes: its share of the window less its frame, its body's own room over and under it outside
        // that, as the old body's measured box stood in its padding (measured_body in `at`); no taller than the dialog
        // leaves it, all of it giving way where it is short of room, what it holds filling that share and laid out in
        // it, scrolling as it does itself)
        d.box(fn(b) {
          style_node(b, fn() { centred_part_in(0.0, 0.0) })
          b
          .shrink(Is(1.0))
          .min_height(Is(Some(0.0)))
          .margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0)))
          .alpha(By(fn() { look().words }))
          |> ignore
          b.box(fn(col) {
            style_node(col, fn() {
              (if footed { dialog_body } else { dialog_body_end }).then(@ui.style(px=room(words_in))).then(body_top())
            })
            col.grow(Is(1.0)).shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            // (its rows out across the room the dialog leaves them, as far as an old body's: rows_out's)
            panel_in_lend(col, Wide, 0.0, sides=dialog_pad + words_in, rows_out=panel_words - panel_card_in, centred=true, clear=@signals.untracked(fn() {
              if untitled() { dialog_close_clear() } else { 0.0 }
            }))
            // (what it holds, together in one box as the old body's measured box held it (none of the body's gap
            // between its parts): its share tall; one as tall as what it holds up to that share (`hugs`), no taller)
            col.box(fn(held) {
              let share = fn() { Some(dmax(0.0, x.tall * over_room(layer).1 - dialog_frame_h)) }
              if n.hugs {
                held.max_height(By(share)) |> ignore
              } else {
                held.height(By(share)) |> ignore
              }
              held.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
              (n.body)(held, close)
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      } else if x.tall > 0.0 && !x.form && steps is None {
        // (whether a list in it says how tall it would be, as it was last built: what it holds as tall as that then)
        let says = @signals.signal(false)
        // (the old view itself held shorter where the dialog is short of room: what it asks its own node's height)
        @ui.old(d, natural=true, gives=true, key=fn() { key + "/body" }, fn(c) {
          let share = dmax(0.0, x.tall * c.window_size().1 - dialog_frame_h)
          let column = @ui.style(px=room(words_in))
          let top = body_top()
          let at = (if x.foot is None { dialog_body_end } else { dialog_body }).then(column).then(top)
          let whole = if says.get() { @ui.style(w=Full, max_h=Fixed(share)) } else { @ui.style(w=Full, h=Fixed(share)) }
          let id = c.id("sf-present/capped/\{keyed.serial}")
          let held = c.box(style=centred_part_in(0.0, 0.0).then(@ui.style(h=Full)), fn() {
            c.box(style=at.then(@ui.style(h=Full)), fn() {
              let was = (panel_sides_in.val, rows_out.val, words_in_now.val, column_given.val, column_in_now.val, in_dialog.val, untitled_clear_now.val, lists_sized_now.val)
              panel_sides_in.val = dialog_pad + words_in
              rows_out.val = panel_words - panel_card_in
              words_in_now.val = 0.0
              column_given.val = true
              column_in_now.val = words_in
              in_dialog.val = true
              untitled_clear_now.val = if untitled() { dialog_close_clear() } else { 0.0 }
              lists_sized_now.val = true
              // (what holds what it holds giving way to the height the dialog leaves it)
              c.gives_way(measured_body(c, keyed.serial, id, whole, fn() { titled_by_row(x, fn() { draw_panel_body(x, c, close, keyed~) }) }))
              panel_sides_in.val = was.0
              rows_out.val = was.1
              words_in_now.val = was.2
              column_given.val = was.3
              column_in_now.val = was.4
              in_dialog.val = was.5
              untitled_clear_now.val = was.6
              lists_sized_now.val = was.7
            })
            |> ignore
          })
          // (a list in it said how tall it would be, or none did: told as that changes, what read it built again)
          let said = lists_of.get(keyed.serial).unwrap_or([]).length() > 0
          if says.untracked() != said {
            says.set(said)
          }
          words_look(c, held)
        })
        .shrink(Is(1.0))
        .min_height(Is(Some(0.0)))
        .margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0)))
        |> ignore
      } else {
        // (what it holds: 18 under its head, scrolling in itself where the dialog is short of room, out to its sides,
        // what it holds as far in as without: dialog's capped body)
        d.box(fn(b) {
          let scroll = @view.Scroll::new()
          b.shrink(Is(1.0)).min_height(Is(Some(0.0))).margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0))) |> ignore
          b.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
            match x.nodes {
              // (what it holds nodes: in a column on its words' line as the old frame's body is laid out, its words as
              // far in as its look says)
              Some(n) =>
                s.box(fn(outer) {
                  style_node(outer, fn() { centred_part_in(0.0, 0.0) })
                  outer.alpha(By(fn() { look().words })) |> ignore
                  outer.box(fn(col) {
                    style_node(col, fn() {
                      (if footed { dialog_body } else { dialog_body_end }).then(@ui.style(px=room(words_in))).then(body_top())
                    })
                    // (holding nothing laid out, none of its room: its title and what it says straight over its foot,
                    // as the old body's box gone_empty)
                    col.gone_empty(Is(true)) |> ignore
                    // (on its words' line already: none further in; its rows out across the room the dialog leaves them,
                    // as far as an old body's (rows_out's); clear of its close button while untitled)
                    panel_in_lend(col, Wide, 0.0, sides=dialog_pad + words_in, rows_out=panel_words - panel_card_in, centred=true, clear=@signals.untracked(fn() {
                      if untitled() { dialog_close_clear() } else { 0.0 }
                    }))
                    (n.body)(col, close)
                  })
                  |> ignore
                })
                |> ignore
              None =>
            @ui.old(s, natural=true, key=fn() { key + "/body" }, fn(c) {
              let column = @ui.style(px=room(words_in))
              let top = body_top()
              let at = if steps is Some(_) {
                full_width.then(column).then(top)
              } else {
                (if x.foot is None { dialog_body_end } else { dialog_body }).then(column).then(top)
              }
              let held = c.box(style=centred_part_in(0.0, 0.0), fn() {
                c.box(style=at, gone_empty=true, fn() {
                  // (what it holds in a column on its words' line, its rows' grounds reaching out across that to the
                  // dialog's padding: panel_centred's)
                  let was = (panel_sides_in.val, rows_out.val, words_in_now.val, column_given.val, column_in_now.val, in_dialog.val, untitled_clear_now.val)
                  panel_sides_in.val = dialog_pad + words_in
                  rows_out.val = panel_words - panel_card_in
                  words_in_now.val = 0.0
                  column_given.val = true
                  column_in_now.val = words_in
                  in_dialog.val = true
                  untitled_clear_now.val = if untitled() { dialog_close_clear() } else { 0.0 }
                  match steps {
                    // (its steps a stack, out to the dialog's edges, each whole: steps_centred's)
                    Some(nav) => {
                      // (each step's own head and foot on the words' line, as steps_centred has them)
                      words_in_now.val = words_in
                      steps_shown(c, keyed, nav, false, dialog_pad + words_in, fn(st, back) {
                        dialog_page(c, key, keyed, { ..x, body: st.body, foot: st.foot }, st, close, back)
                      })
                      words_in_now.val = 0.0
                    }
                    None => {
                      panel_whole_now.val += 1
                      titled_by_row(x, fn() { draw_panel_body(x, c, close, keyed~) })
                      panel_whole_now.val -= 1
                    }
                  }
                  panel_sides_in.val = was.0
                  rows_out.val = was.1
                  words_in_now.val = was.2
                  column_given.val = was.3
                  column_in_now.val = was.4
                  in_dialog.val = was.5
                  untitled_clear_now.val = was.6
                })
                |> ignore
              })
              words_look(c, held)
            })
            |> ignore
            }
          })
          // (cut at its box while what it holds is taller than it, and taking presses within it alone then)
          .clips(By(fn() { scroll.goes() }))
          .bounds_input(By(fn() { scroll.goes() }))
          |> ignore
        })
        |> ignore
      }
      // (its foot: its buttons at its end in its foot corner)
      match x.foot {
        Some(f) if steps is None =>
          @ui.old(d, natural=true, key=fn() { key + "/foot" }, fn(c) {
            let held = c.box(style=centred_part_in(0.0, 0.0), fn() {
              in_words(fn() { c.box(style=dialog_foot.then(dialog_corner_foot(dialog_pad)), fn() { f(c, close) }) |> ignore })
            })
            words_look(c, held)
          })
          .margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0)))
          |> ignore
        // (its foot nodes: its buttons at its end in its foot corner, as the old frame's foot is laid out)
        _ if steps is None =>
          match foot_nodes {
            Some(f) =>
              d.box(fn(fv) {
                style_node(fv, fn() { centred_part_in(0.0, 0.0) })
                fv.margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0))).alpha(By(fn() { look().words })) |> ignore
                fv.box(fn(row) {
                  style_node(row, fn() { dialog_foot.then(dialog_corner_foot(dialog_pad)) })
                  f(row, close)
                })
                |> ignore
              })
              |> ignore
            None => ()
          }
        _ => ()
      }
      if x.live is Some(_) {
        corner()
      }
      // (one that goes in steps: its close button over its steps, laid after them, a step sliding in or away under it)
      if steps is Some(_) {
        d.box(fn(o) {
          o.over(Is(true)).width(By(fn() { Some(w()) }))|> ignore
          close_old(o, false)
        })
        |> ignore
      }
      // (another dialog over it: dimmed over all of itself, its corners its own)
      d.box(fn(v) { v.over(Is(true)).radius(Is(dialog_r)).ground(By(veil)) |> ignore }) |> ignore
    })
    |> ignore
    // (the focus on its own ground as it opens, back to what had it as it goes: on the field it opens to be typed in, or
    // the one of what it holds that said so, where one did (panel_opens_in_node, panel_search_at_hand_node,
    // panel_opens_on_node); else the first of what it holds that takes it once that is built and laid out (first_stop;
    // not one in steps, whose steps keep it on its ground as they come), as kit's dialog's: where what it holds is nodes,
    // only what takes what is typed or the arrows (opens_on_role), none of it where nothing does (its own ground: the
    // keys its, Escape; Enter nothing), as the old dialog's went to the first of its fields and choices it registered)
    let (to, own) = match (field.val, opens_on.val) {
      (Some(f), _) if f.keyed(false) => (f.field, false)
      // (a search at hand by touch: its own ground, no input method raised over what it lists)
      (Some(_), _) => (layer, true)
      (None, Some(first)) => (first, false)
      (None, None) => (layer, false)
    }
    own_ground.val = own
    to
  })
}

///|
/// A part of a centred panel's out to its sides (and `over` above it, `under` below it): the dialog's padding at its
/// sides inside it.
fn centred_part_in(over : Double, under : Double) -> @ui.Style {
  @ui.style(w=Full, pl=room(dialog_pad), pt=room(over), pr=room(dialog_pad), pb=room(under))
}

///|
/// What a panel's own title row (panel's `title_row`) stands in: as wide as its head's row leaves it before the close
/// button.
// kept across runs: a value (no field of it changes)
let title_row_room : @ui.Style = @ui.style(w=grow)

///|
/// What a panel holds under its own title row (panel's `title_row`): from right under it, the row keeping what it
/// wants under it.
// kept across runs: a value (no field of it changes)
let title_row_under : @ui.Style = @ui.css("pt=S0")

///|
/// Whether what a panel holds is drawn under a title row the panel draws for it (panel's `title_row`, in the middle of
/// the window): it draws no head of its own then; elsewhere (a sheet, beside what opened it) it does.
// kept across runs: said round what such a panel holds as it is drawn
pub let title_row_given : Ref[Bool] = { val: false }

///|
/// What `x` holds drawn by `body`, told whether its title row is the panel's (title_row_given).
fn titled_by_row(x : PanelOf, body : () -> Unit) -> Unit {
  let was = title_row_given.val
  title_row_given.val = x.title_row is Some(_)
  body()
  title_row_given.val = was
}

///|
/// Whether what is read out as `role` is what a dialog of nodes opens on (its layer's focus_opens_first `takes`): what takes what is typed (a field, a
/// box offering what to type) or the arrow keys (a choice of a few, its radios or its tabs; a slider). One place: a
/// kind to add is added here.
fn opens_on_role(role : @view.Role) -> Bool {
  match role {
    TextField | Combobox | Radio | Tab | Slider => true
    _ => false
  }
}
