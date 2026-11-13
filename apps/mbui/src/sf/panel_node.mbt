// A panel of the presenters' beside what opened it (panel_popover's: a small panel, its title, what it holds and its
// foot) as nodes of the window's tree: a modal layer over the window, nothing under it dimmed, its panel beside what
// opened it (View::beside, as menu_node's, `side`, `along`, `offset` off it), `w` wide, grown out of that side as it
// comes and shrunk back into it as it goes (pop_in, pop_out: drawn till its way out is over, pressed no more); its
// title (panel_head), what it holds and its foot each the old frame's, built in a hosted view as tall as what it holds
// (@ui.old's `natural`), or what it holds and its foot nodes where they are (panel_nodes: laid out as those are), what
// it holds scrolling where the window leaves the panel short of room. Escape, back and a
// press outside close it (its gone told); what it holds closes it with what it was given (nothing told).

///|
/// The outer boxes of small panels drawn beside what opened them (panel_node), by their serial: what a sub-panel
/// aligned with one (`match_panel`) goes beside while keeping its own width.
// kept across runs: put back by presenters_reset; each let go as its layer is
let presented_popovers : Map[Int, @view.View] = Map([])

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
      layer.owns(fn() {
        presented_popovers.remove(keyed.serial)
        gone()
      })
      |> ignore
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
      // (a submenu row's menu in what it holds made in it: submenu_layer_lent)
      submenu_layer_lend(layer)
      // (what its fields offer made in it: offers_layer_lent)
      offers_layer_lend(layer)
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
      // (Escape and back, a step further in from a panel: back to that one, back_under; else it closes)
      .on_key(fn(k) {
        if k.code == @ui.key_escape && @signals.untracked(live) {
          if !back_under(keyed) {
            cancel()
          }
          true
        } else {
          false
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) && !back_under(keyed) {
          cancel()
        }
      })
      |> ignore
      // (what opened it, where it is drawn, or the small panel it stands flush with (`match_panel`): what its panel
      // goes beside)
      let matched = if x.match_panel > 0 { presented_popovers.get(x.match_panel) } else { None }
      let at = match matched {
        Some(v) => v
        None => anchor(layer)
      }
      // (what holds its body: what takes the focus as it opens)
      let body_box : Ref[@view.View?] = Ref(None)
      // (the field it opens to be typed in, where what it holds says one: panel_opens_in_node,
      // panel_search_at_hand_node)
      let field : Ref[PanelField?] = Ref(None)
      layer.lends(panel_field_lent, field) |> ignore
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
        presented_popovers[keyed.serial] = p
        p
        .beside(at.id(), side=x.side, along=x.along, offset=x.offset, padding=8.0)
        // (`fits`: as wide as what it holds, `w` at most, never narrower than it has been: its parts each told how wide
        // what they hold is laid out, out to its sides, none narrower than it is, small_panel's min_w and max_w)
        .width(if x.fits { By(fn() { Some(dmin(x.w, wide.iter().fold(init=0.0, fn(m, s) { dmax(m, s.get().unwrap_or(0.0)) }))) }) } else { Is(Some(x.w)) })
        .max_height(By(fn() { Some(dmax(0.0, over_room(layer).1 - 16.0)) }))
        // (`tall`: a share of the window, no taller than the room beside what opened it, small_panel's `h`)
        .height(By(fn() { if x.tall > 0.0 { Some(dmin(x.tall * over_room(layer).1, dmax(0.0, over_room(layer).1 - 16.0))) } else { None } }))
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
        |> ground_node
        |> ignore
        // (the side of what opened it it went on, as the tree placed it (@ui.old_went: flipped there for want of room,
        // its old views built again as it goes to the other): what its parts keep nearest what opened it is by that side
        // (panel_opens_up), read as each is built, never as it only moves; what was told before given back after, for no
        // other panel to read)
        let opened = fn() {
          let was = beside_given.val
          beside_given.val = { side: @ui.old_went().unwrap_or(x.side), room: 1.0e9, panel: 0 }
          was
        }
        // (each part of it out to the panel's edges it stands by, the panel's padding round what it holds inside it: what
        // reaches into that padding on purpose (a head's search in its top corner, a foot's buttons in its foot corner, a
        // row out to its sides) drawn and pressed there, cut by the panel alone, as small_panel's are)
        // (its title as it is now, `live`'s first (small_panel's: its step and what it says not drawn beside what opened
        // it); headed as it is, told only as that changes: what stands by its top built again then, not as the title's
        // words change)
        let title = fn() {
          match x.live {
            Some(f) => f().0
            None => x.title
          }
        }
        // (a live one headed only while it has a title, what stands at its head's end with it, as small_panel heads it;
        // what it is presented with headed by a head's end alone too)
        // (a step further in from a panel, what it holds nodes: headed by its back key before its title, untitled too,
        // as a sheet's page and a dialog have it)
        let stepped = x.nodes is Some(_) && keyed.under is Some(_)
        let headed_now : @signals.Computed[Bool] = @signals.computed(
          fn(_) { !x.heads_itself && (title() != "" || stepped) },
          same=fn(a, b) { a == b },
        )
        let headed = fn() { headed_now.get() }
        let footed = x.foot is Some(_) || x.nodes.bind(fn(n) { n.foot }) is Some(_)
        // (ruled, the room over the line its body's, not the foot's: a line of what it holds going down to meet it reaches
        // it, its body cutting nothing of it: panel_rule_over)
        let ruled_foot = x.ruled && footed
        let over = fn() { if headed() { 0.0 } else { panel_pad } }
        let under = if !footed || ruled_foot { panel_pad } else { 0.0 }
        // (out to the panel's edge under it where nothing is under it; over a ruled foot, the room its own, in it)
        let out_under = if footed { 0.0 } else { panel_pad }
        // (its title, panel_head's: out to the panel's edges over it, on `v`'s node; where what it holds is nodes
        // (panel_nodes), nodes too, its words as faint as the panel's look says: nothing of the old frame in it)
        let head = fn(v : @view.View) {
          if x.nodes is None {
            return @ui.old(v, natural=true, fits?=fits(0), key=fn() { key + "/head" }, fn(c) {
              let was = opened()
              let held = c.box(style=panel_part_in(panel_pad, 0.0), fn() { panel_head(c, title()) })
              beside_given.val = was
              words_look(c, held)
            })
          }
          v.box(fn(h) {
            style_node(h, fn() { panel_part_in(panel_pad, 0.0) })
            h.alpha(By(fn() { look().words })) |> ignore
            h.box(fn(b) {
              style_node(b, fn() { panel_head_box })
              if !stepped {
                words_node(b, title, fn() { panel_title }) |> ignore
                return
              }
              // (its back key before its title, back to the panel it came from, concentric in its corner)
              b.box(fn(line) {
                style_node(line, fn() { panel_step_line })
                line.box(fn(k) {
                  style_node(k, fn() { step_back_out }, in_row=true)
                  icon_button_node(k, "chevron-left", fn() { t("common.back") }, fn() { back_under(keyed) |> ignore }, size=step_back_side)
                  |> ignore
                })
                |> ignore
                words_node(line, title, fn() { panel_title }).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              })
              |> ignore
            })
            |> ignore
          })
        }
        match x.live {
          // (there while it has a title as it is now, what holds what it holds the same as it comes and goes)
          Some(_) =>
            p.show(headed, fn(h) {
              h.margin(Is((-panel_pad, -panel_pad, -panel_pad, 0.0))) |> ignore
              head(h) |> ignore
            })
          None =>
            if headed() {
              head(p).margin(Is((-panel_pad, -panel_pad, -panel_pad, 0.0))) |> ignore
            }
        }
        // (`tall`: what it holds fills the room it is given, laid out in it, scrolling as it does itself: panel_grows)
        if x.tall > 0.0 {
          p.box(fn(b) {
            // (the room under its head and no more, whatever it holds: grown from none, as what holds a list sized by
            // what it holds would stand past the panel's foot, its last rows cut there)
            b.grow(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).margin(By(fn() { (-panel_pad, -over(), -panel_pad, -out_under) })).focusable(Is(x.focus), keys=0, tab=false) |> ignore
            body_box.val = Some(b)
            match x.nodes {
              // (what it holds nodes: in a column as the old frame's body is laid out, its words as far in as its look says)
              Some(n) =>
                b.box(fn(col) {
                  style_node(col, fn() { panel_grows.then(panel_part_in(over(), under)) })
                  col.grow(Is(1.0)).alpha(By(fn() { look().words })) |> ignore
                  // (laid out as a small panel's old body is: wide, its words a row's padding in)
                  panel_in_lend(col, Wide, text_in, sides=panel_pad, small=true)
                  (n.body)(col, close)
                })
                |> ignore
              None =>
            @ui.old(b, key=fn() { key + "/body" }, fn(c) {
              let was = opened()
              let held = c.box(style=panel_grows.then(panel_part_in(over(), under)), fn() {
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
            }
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
              match x.nodes {
                // (what it holds nodes: in a column as the old frame's body is laid out, its words as far in as its look
                // says)
                Some(n) =>
                  s.box(fn(col) {
                    style_node(col, fn() { held_in().then(@ui.style(pt=room(over()), pb=room(under))) })
                    col.margin(By(fn() { (0.0, -over(), 0.0, -out_under) })).alpha(By(fn() { look().words })) |> ignore
                    // (laid out as a small panel's old body is: wide, its words a row's padding in)
                    panel_in_lend(col, Wide, text_in, sides=panel_pad, small=true)
                    (n.body)(col, close)
                  })
                  |> ignore
                None =>
              @ui.old(s, natural=true, fits?=fits(1), key=fn() { key + "/body" }, fn(c) {
              let was = opened()
                let held = c.box(style=held_in().then(@ui.style(pt=room(over()), pb=room(under))), fn() {
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
              .margin(By(fn() { (0.0, -over(), 0.0, -out_under) }))
              |> ignore
              }
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
                  c.box(style=foot_rule.then(@ui.style(mx=room(-panel_pad))), fn() {  }) |> ignore
                }
                let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(@ui.capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
                c.box(style=panel_foot_at.then(at), fn() { f(c, close) }) |> ignore
              })
              beside_given.val = was
              words_look(c, held)
            })
            .margin(Is((-panel_pad, 0.0, -panel_pad, -panel_pad)))
            |> ignore
          None =>
            match x.nodes.bind(fn(n) { n.foot }) {
              // (its foot nodes: laid out as the old frame's foot is, its words as far in as its look says)
              Some(f) =>
                p.box(fn(fv) {
                  style_node(fv, fn() { panel_part_in(0.0, panel_pad) })
                  fv.margin(Is((-panel_pad, 0.0, -panel_pad, -panel_pad))).alpha(By(fn() { look().words })) |> ignore
                  if x.ruled {
                    fv.box(fn(r) { style_node(r, fn() { foot_rule.then(@ui.style(mx=room(-panel_pad))) }) }) |> ignore
                  }
                  fv.box(fn(row) {
                    let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(@ui.capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
                    style_node(row, fn() { panel_foot_at.then(at) }, in_row=false)
                    f(row, close)
                  })
                  |> ignore
                })
                |> ignore
              None => ()
            }
        }
        // (the focus on the field it opens to be typed in, where it says one; else what holds its body's as it opens
        // where it takes it, else where it was; back to what had it as it goes)
        match (field.val, body_box.val) {
          (Some(f), _) if f.keyed(false) => layer.focus_opens(f.field) |> ignore
          // (a search at hand by touch: the focus left where it is, as on a sheet)
          (Some(_), _) => layer.focus_returns() |> ignore
          (None, Some(b)) if x.focus => layer.focus_opens(b) |> ignore
          _ => layer.focus_returns() |> ignore
        }
      })
      |> ignore
    },
    leave=@kit.pop_out_ms,
  )
}

///|
/// A step's head beside what opened it: its back key, then its title, a step's head's gap apart (step_head_gap), up
/// from where a title's line is so that the key stands as far in from the panel's top as from its side, concentric with
/// its corner (as far in as its corner less the key's).
// kept across runs: a value (no field of it changes)
let panel_step_line : @ui.Style = @ui.css("row w=Full align=ACenter gap=S1").then(@ui.style(mt=room(panel_step_up)))

///|
/// How far up from a title's line (panel_head_box's, panel_pad and its top in) a step's head stands (panel_step_line).
let panel_step_up : Double = r_menu - step_back_side / 2.0 - panel_pad - @ui.Space::S1_5.px()

///|
/// A part of a panel's out to its sides (and `over` above it, `under` below it, where it stands by the panel's top or
/// foot): the panel's padding round what it holds, inside it.
fn panel_part_in(over : Double, under : Double) -> @ui.Style {
  @ui.style(w=Full, pl=room(panel_pad), pt=room(over), pr=room(panel_pad), pb=room(under))
}
