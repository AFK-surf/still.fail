// A panel of the presenters' opened by nothing (panel_centred's: the library's dialog, a panel in the middle of the
// window) as nodes of the window's tree: the presenters' dialog layer (dialog_layer_node: a press outside it closes it,
// as a dialog's does), its frame as dialog draws it (dialog_w wide, dialog_wide_w where `wide`, the window less
// dialog_margin at most, no taller than it less dialog_room; 24 in, a line round it, dialog_r round, the panel's ground
// and shadow); its head (its title and its close button, what it says under them, or its close button alone in its top
// corner where it has no title), what it holds and its foot each the old frame's, built in a hosted view out to the
// dialog's edges they stand by, the dialog's padding inside them, what it holds scrolling where the window leaves the
// dialog short of room. Escape, back, a press outside and its close button close it (its gone told); what it holds
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
) -> Unit {
  dialog_layer_node(parent, open, cancel, outside=true, shown~, gone~, dims~, fn(across, layer, look) {
    let theme = fn() { @ui.tree_theme() }
    let untitled = x.title == ""
    let w = fn() { dmin(if x.wide { dialog_wide_w } else { dialog_w }, layer.window().0 - dialog_margin) }
    // (its old views' words as far in as its look says, as kit's dialog's look gives them: read as they are painted)
    let words_look = fn(c : @ui.Ctx, held : Int) {
      c.look_by(held, fn() {
        { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: look().words }
      })
    }
    // (what it holds and its head on the line of its words, a row's padding in: panel_centred's)
    let words_in = card_pad - corner_inset
    let in_words = fn(f : () -> Unit) {
      let was = words_in_now.val
      words_in_now.val = words_in
      f()
      words_in_now.val = was
    }
    across.box(fn(d) {
      d
      .width(By(fn() { Some(w()) }))
      // (no taller than the window leaves it, dialog_room: what it holds scrolls in itself past that)
      .max_height(By(fn() { Some(dmax(0.0, layer.window().1 - dialog_room)) }))
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
      // (a press on it its own: not outside it)
      .presses(Is(true))
      .on_press(fn() {  })
      .says(Is(Some(@view.said(Dialog, label=x.title, description=x.description))))
      |> ignore
      // (untitled: its close button alone over its top corner, concentric with it: built first, as dialog builds its
      // layer before what it holds: read out first, drawn under what comes after it)
      if untitled {
        d.box(fn(o) {
          o.over(Is(true)).width(By(fn() { Some(w()) }))|> ignore
          @ui.old(o, natural=true, key=fn() { key + "/close" }, fn(c) {
            let held = c.box(style=dialog_close_row, fn() {
              c.box(style=dialog_close_corner(), fn() {
                if icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=t("common.close")) {
                  cancel()
                }
              })
              |> ignore
            })
            words_look(c, held)
          })
          |> ignore
        })
        |> ignore
      }
      // (its head: its title and its close button at its end where it has a title, what it says under them where it says
      // something: dialog's)
      if !untitled || x.description != "" {
        @ui.old(d, natural=true, key=fn() { key + "/head" }, fn(c) {
          let held = c.box(style=centred_part_in(dialog_pad, 0.0), fn() {
            in_words(fn() {
              let words_at = @ui.style(pl=room(words_in_now.val))
              if !untitled {
                c.box(style=dialog_head.then(words_at), fn() {
                  c.text(x.title, style=dialog_title) |> ignore
                  c.box(style=dialog_close_at(), fn() {
                    if icon_button(c, "close", key=key + "/close", size=dialog_close, round=true, label=t("common.close")) {
                      cancel()
                    }
                  })
                  |> ignore
                })
                |> ignore
              }
              if x.description != "" {
                c.box(style=dialog_lead_at.then(words_at), fn() { c.text(x.description, style=dialog_lead) |> ignore }) |> ignore
              }
            })
          })
          words_look(c, held)
        })
        .margin(Is((-dialog_pad, -dialog_pad, -dialog_pad, 0.0)))
        |> ignore
      }
      // (what it holds: 18 under its head, scrolling in itself where the dialog is short of room, out to its sides,
      // what it holds as far in as without: dialog's capped body)
      d.box(fn(b) {
        let scroll = @view.Scroll::new()
        b.shrink(Is(1.0)).min_height(Is(Some(0.0))).margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0))) |> ignore
        b.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
          @ui.old(s, natural=true, key=fn() { key + "/body" }, fn(c) {
            let column = @ui.style(px=room(words_in))
            let top = if untitled { dialog_untitled_top } else { no_style }
            let at = (if x.foot is None { dialog_body_end } else { dialog_body }).then(column).then(top)
            let held = c.box(style=centred_part_in(0.0, 0.0), fn() {
              c.box(style=at, gone_empty=true, fn() {
                // (what it holds in a column on its words' line, its rows' grounds reaching out across that to the
                // dialog's padding: panel_centred's)
                let was = (panel_sides_in.val, rows_out.val, words_in_now.val, column_given.val, column_in_now.val, in_dialog.val, untitled_clear_now.val)
                panel_sides_in.val = dialog_pad + words_in
                rows_out.val = words_in
                words_in_now.val = 0.0
                column_given.val = true
                column_in_now.val = words_in
                in_dialog.val = true
                untitled_clear_now.val = if untitled { dialog_close_clear() } else { 0.0 }
                panel_whole_now.val += 1
                draw_panel_body(x, c, close, keyed~)
                panel_whole_now.val -= 1
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
        })
        // (cut at its box while what it holds is taller than it, and taking presses within it alone then)
        .clips(By(fn() { scroll.goes() }))
        .bounds_input(By(fn() { scroll.goes() }))
        |> ignore
      })
      |> ignore
      // (its foot: its buttons at its end in its foot corner)
      match x.foot {
        Some(f) =>
          @ui.old(d, natural=true, key=fn() { key + "/foot" }, fn(c) {
            let held = c.box(style=centred_part_in(0.0, 0.0), fn() {
              in_words(fn() { c.box(style=dialog_foot.then(dialog_corner_foot(dialog_pad)), fn() { f(c, close) }) |> ignore })
            })
            words_look(c, held)
          })
          .margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0)))
          |> ignore
        None => ()
      }
    })
    |> ignore
    // (the focus on its own ground as it opens, as kit's dialog's: back to what had it as it goes)
    layer
  })
}

///|
/// A part of a centred panel's out to its sides (and `over` above it, `under` below it): the dialog's padding at its
/// sides inside it.
fn centred_part_in(over : Double, under : Double) -> @ui.Style {
  @ui.style(w=Full, pl=room(dialog_pad), pt=room(over), pr=room(dialog_pad), pb=room(under))
}
