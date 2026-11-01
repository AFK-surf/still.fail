// A panel of the presenters' beside what opened it (panel_popover's: a small panel, its title, what it holds and its
// foot) as nodes of the window's tree: a modal layer over the window, nothing under it dimmed, its panel beside what
// opened it (View::beside, as menu_node's, `side`, `along`, `offset` off it), `w` wide, grown out of that side as it
// comes and shrunk back into it as it goes (pop_in, pop_out: drawn till its way out is over, pressed no more); its
// title (panel_head), what it holds and its foot each the old frame's, built in a hosted view as tall as what it holds
// (@ui.old's `natural`), what it holds scrolling where the window leaves the panel short of room. Escape, back and a
// press outside close it (its gone told); what it holds closes it with what it was given (nothing told).

///|
/// A panel `x` in `parent` while `open()` (going over pop_out_ms once not), beside what `anchor` makes in its layer;
/// `key`: what its old views are named by (the presented's); `close`: what what it holds is given to close it; `cancel`
/// as it is closed by Escape, back or a press outside. `shown`, `gone`: as dialog_layer_node's.
fn panel_node(
  parent : @view.View,
  key : String,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  x : PanelOf,
  close : () -> Unit,
  cancel : () -> Unit,
  keyed : Presented,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
) -> Unit {
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      // (how far in it is, from the moment it opened; out from the moment it closed)
      let way = EdgeWay::new(0.0)
      layer.reacts(fn() { layer.leaving() }, fn(going) {
        if going {
          way.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
        } else {
          way.go(layer, 1.0, @kit.pop_ms)
        }
      })
      let look = fn() {
        let p = way.shown(layer)
        if layer.leaving() {
          @kit.pop_out.at(p, p)
        } else {
          @kit.pop_in.at(p, p)
        }
      }
      let live = fn() { !layer.leaving() }
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go)
      .modal(By(live))
      // (going, nothing of it read out: as an old layer on its way out, inert, is hidden from what reads the screen)
      .hides(By(fn() { layer.leaving() }))
      .held_back_goes_on()
      |> ignore
      // (the focus left where it is as it opens (not `focus`): what is typed still that field's, its keys the layer's
      // (kit's popover with its initial focus prevented, as menu_node's keep_field)
      if !x.focus {
        layer.leaves_typing() |> ignore
      }
      layer
      // (a press outside its panel its own, nothing under it pressed: closing it as it goes down)
      .presses(Is(true))
      .on_drag(fn(d) {
        if d.kind == Down && @signals.untracked(live) {
          cancel()
        }
      })
      .on_key(fn(k) {
        if k.code == @ui.key_escape && @signals.untracked(live) {
          cancel()
          true
        } else {
          false
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
      // (what holds its body: what takes the focus as it opens)
      let body_box : Ref[@view.View?] = Ref(None)
      // (its old views' words as far in as its look says: its ground first, then they, as kit's look gives them; read as
      // they are painted (Ctx::look_by), so that its way in and out paints them, nothing of them built again)
      let words_look = fn(c : @ui.Ctx, held : Int) {
        c.look_by(held, fn() {
          { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: look().words }
        })
      }
      layer.box(fn(p) {
        p
        .beside(at.id(), side=x.side, along=x.along, offset=x.offset, padding=8.0)
        .width(Is(Some(x.w)))
        .max_height(By(fn() { Some(dmax(0.0, layer.window().1 - 16.0)) }))
        // (`tall`: a share of the window, no taller than the room beside what opened it, small_panel's `h`)
        .height(By(fn() { if x.tall > 0.0 { Some(dmin(x.tall * layer.window().1, dmax(0.0, layer.window().1 - 16.0))) } else { None } }))
        // (small_panel's: its padding round what it holds, its corner, ground, line and shadow)
        .padding(Is((panel_pad, panel_pad, panel_pad, panel_pad)))
        .radius(Is(r_menu))
        .ground(By(fn() { panel_ground() }))
        .edge(By(fn() { (1.0, library_theme().p.line) }))
        .shadow(By(fn() { (16.0, 12.0, library_theme().p.shadow) }))
        .clips(Is(true))
        .alpha(By(fn() { look().alpha }))
        .scale(By(fn() { look().sx }), about=FromBeside)
        .says(Is(Some(@view.said(Dialog, label=x.title))))
        // (a press on it its own: not outside it)
        .presses(Is(true))
        .on_press(fn() {  })
        |> ignore
        // (its title, panel_head's)
        if x.title != "" || x.head_end is Some(_) {
          @ui.old(p, natural=true, key=fn() { key + "/head" }, fn(c) {
            let held = c.box(style=panel_part_at, fn() { panel_head(c, x.title, end?=x.head_end) })
            words_look(c, held)
          })
          |> ignore
        }
        // (`tall`: what it holds fills the room it is given, laid out in it, scrolling as it does itself: panel_grows)
        if x.tall > 0.0 {
          p.box(fn(b) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))).focusable(Is(x.focus), keys=0, tab=false) |> ignore
            body_box.val = Some(b)
            @ui.old(b, key=fn() { key + "/body" }, fn(c) {
              let held = c.box(style=panel_grows, fn() {
                panel_sides_in.val = panel_pad
                small_panel_now.val = true
                words_in_now.val = text_in
                rule_over_now.val = if x.ruled && x.foot is Some(_) { panel_pad } else { 0.0 }
                draw_panel_body(x, c, close, keyed~)
                panel_sides_in.val = 0.0
                small_panel_now.val = false
                words_in_now.val = 0.0
                rule_over_now.val = 0.0
              })
              words_look(c, held)
            }).grow(Is(1.0))
            |> ignore
          })
          |> ignore
        } else {
          // (what it holds, as small_panel lays it out; scrolling where the window leaves the panel short of room, out to the
          // panel's sides, what it holds as far in as without (held_reach, held_in: in_room's))
          p.box(fn(b) {
            let scroll = @view.Scroll::new()
            b
            .shrink(Is(1.0))
            .min_height(Is(Some(0.0)))
            .margin(Is((-panel_pad, 0.0, -panel_pad, 0.0)))
            // (the focus its own as it opens where it takes it (`focus`, kit's popover's: on what holds its body, said
            // nothing of itself): no key presses it)
            .focusable(Is(x.focus), keys=0, tab=false)
            |> ignore
            body_box.val = Some(b)
            b.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
              @ui.old(s, natural=true, key=fn() { key + "/body" }, fn(c) {
                let held = c.box(style=held_in(), fn() {
                  // (held shorter than what it holds: what would scroll in itself there laid out whole, panel_held)
                  panel_held_now.val = scroll.goes()
                  panel_sides_in.val = panel_pad
                  small_panel_now.val = true
                  words_in_now.val = text_in
                  rule_over_now.val = if x.ruled && x.foot is Some(_) { panel_pad } else { 0.0 }
                  draw_panel_body(x, c, close, keyed~)
                  panel_sides_in.val = 0.0
                  small_panel_now.val = false
                  words_in_now.val = 0.0
                  rule_over_now.val = 0.0
                  panel_held_now.val = false
                })
                words_look(c, held)
              })
              |> ignore
            })
            // (cut at its box while what it holds is taller than it, as @kit.in_room's held list (pick_node's): else what
            // reaches past it drawn whole, in the panel's round corners; what it paints alone, nothing laid out by it)
            .clips(By(fn() { scroll.goes() }))
            // (and taking presses within its box alone then too)
            .bounds_input(By(fn() { scroll.goes() }))
            |> ignore
          })
          |> ignore
        }
        // (its foot: its buttons in its foot corner, a line over them where `ruled`)
        match x.foot {
          Some(f) =>
            @ui.old(p, natural=true, key=fn() { key + "/foot" }, fn(c) {
              let held = c.box(style=panel_part_at, fn() {
                if x.ruled {
                  c.box(style=foot_rule.then(@ui.style(mx=room(-panel_pad), mt=room(panel_pad))), fn() {  }) |> ignore
                }
                let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
                c.box(style=panel_foot_at.then(at), fn() { f(c, close) }) |> ignore
              })
              words_look(c, held)
            })
            |> ignore
          None => ()
        }
        // (the focus what holds its body's as it opens where it takes it, else where it was; back to what had it as it
        // goes)
        match body_box.val {
          Some(b) if x.focus => layer.focus_opens(b) |> ignore
          _ => layer.focus_returns() |> ignore
        }
      })
      |> ignore
    },
    leave=@kit.pop_out_ms,
  )
}

///|
// kept across runs: a value (no field of it changes)
let panel_part_at : @ui.Style = @ui.css("w=Full")
