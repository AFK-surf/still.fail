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
      let leave_from = Ref(0.0)
      let leave_look = Ref(@kit.pop_in.at(0.0, 0.0))
      layer.reacts(fn() { layer.leaving() }, fn(going) {
        if going {
          if x.fade_out_together {
            // Keep the appearance reached if it is closed before its entrance finishes.
            let p = way.way.value_at(layer.cause_at())
            leave_from.val = p
            leave_look.val = @kit.pop_in.at(p, p)
          }
          way.go(layer, 0.0, @kit.pop_out_ms, ease=Leave)
        } else {
          way.go(layer, 1.0, @kit.pop_ms)
        }
      })
      let look = fn() {
        let p = way.shown(layer)
        if layer.leaving() && x.fade_out_together {
          // Fade the whole panel from that appearance, retaining the popover's scale and curve.
          let fade = if leave_from.val > 0.0 { dmin(1.0, dmax(0.0, p / leave_from.val)) } else { 0.0 }
          { ..@kit.pop_out.at(p, p), alpha: leave_look.val.alpha * fade, words: leave_look.val.words }
        } else if layer.leaving() {
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
      // (its old views' words as far in as its look says: on entering, its ground first, then they; read as they are
      // painted (Ctx::look_by), so that its way in and out paints them, nothing of them built again)
      // (`fits`: how wide what its head, its body and its foot each hold is laid out, out to the panel's sides: what it
      // is as wide as; each made before what reads them)
      let wide : Array[@signals.Signal[Double?]] = Array::makei(3, fn(_) { @signals.signal(None, same=fn(a, b) { a == b }) })
      let fits = fn(k : Int) -> (Double, @signals.Signal[Double?])? { if x.fits { Some((x.w, wide[k])) } else { None } }
      let words_look = fn(c : @ui.Ctx, held : Int) {
        c.look_by(held, fn() {
          { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: look().words }
        })
      }
      layer.box(fn(p) {
        p
        .beside(at.id(), side=x.side, along=x.along, offset=x.offset, padding=8.0)
        // (`fits`: as wide as what it holds, `w` at most, never narrower than it has been: its parts each told how wide
        // what they hold is laid out, out to its sides, none narrower than it is, small_panel's min_w and max_w)
        .width(if x.fits { By(fn() { Some(dmin(x.w, wide.iter().fold(init=0.0, fn(m, s) { dmax(m, s.get().unwrap_or(0.0)) }))) }) } else { Is(Some(x.w)) })
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
        // (the side of what opened it it went on, as the tree placed it (View::went_told: flipped there for want of room,
        // told as it goes to the other): what its parts keep nearest what opened it is by that side (panel_opens_up), read
        // as each is built, so built again as it goes to the other side, never as it only moves; what was told before
        // given back after, for no other panel to read)
        let opened = fn() {
          let was = beside_given.val
          beside_given.val = { side: p.went_told().unwrap_or(x.side), room: 1.0e9, panel: 0 }
          was
        }
        // (each part of it out to the panel's edges it stands by, the panel's padding round what it holds inside it: what
        // reaches into that padding on purpose (a head's search in its top corner, a foot's buttons in its foot corner, a
        // row out to its sides) drawn and pressed there, cut by the panel alone, as small_panel's are)
        let headed = x.title != "" || x.head_end is Some(_)
        let footed = x.foot is Some(_)
        let (over, under) = (if headed { 0.0 } else { panel_pad }, if footed { 0.0 } else { panel_pad })
        // (its title, panel_head's)
        if headed {
          @ui.old(p, natural=true, fits?=fits(0), key=fn() { key + "/head" }, fn(c) {
            let was = opened()
            let held = c.box(style=panel_part_in(panel_pad, 0.0), fn() { panel_head(c, x.title, end?=x.head_end) })
            beside_given.val = was
            words_look(c, held)
          })
          .margin(Is((-panel_pad, -panel_pad, -panel_pad, 0.0)))
          |> ignore
        }
        // (`tall`: what it holds fills the room it is given, laid out in it, scrolling as it does itself: panel_grows)
        if x.tall > 0.0 {
          p.box(fn(b) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))).margin(Is((-panel_pad, -over, -panel_pad, -under))).focusable(Is(x.focus), keys=0, tab=false) |> ignore
            body_box.val = Some(b)
            @ui.old(b, key=fn() { key + "/body" }, fn(c) {
              let was = opened()
              let held = c.box(style=panel_grows.then(panel_part_in(over, under)), fn() {
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
              beside_given.val = was
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
              @ui.old(s, natural=true, fits?=fits(1), key=fn() { key + "/body" }, fn(c) {
              let was = opened()
                let held = c.box(style=held_in().then(@ui.style(pt=room(over), pb=room(under))), fn() {
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
                beside_given.val = was
                words_look(c, held)
              })
              .margin(Is((0.0, -over, 0.0, -under)))
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
            @ui.old(p, natural=true, fits?=fits(2), key=fn() { key + "/foot" }, fn(c) {
              let was = opened()
              let held = c.box(style=panel_part_in(0.0, panel_pad), fn() {
                if x.ruled {
                  c.box(style=foot_rule.then(@ui.style(mx=room(-panel_pad), mt=room(panel_pad))), fn() {  }) |> ignore
                }
                let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
                c.box(style=panel_foot_at.then(at), fn() { f(c, close) }) |> ignore
              })
              beside_given.val = was
              words_look(c, held)
            })
            .margin(Is((-panel_pad, 0.0, -panel_pad, -panel_pad)))
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
/// A part of a panel's out to its sides (and `over` above it, `under` below it, where it stands by the panel's top or
/// foot): the panel's padding round what it holds, inside it.
fn panel_part_in(over : Double, under : Double) -> @ui.Style {
  @ui.style(w=Full, pl=room(panel_pad), pt=room(over), pr=room(panel_pad), pb=room(under))
}
