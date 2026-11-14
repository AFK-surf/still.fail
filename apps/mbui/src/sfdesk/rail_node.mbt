// The rail (Rail.tsx) as nodes of the window's tree, made once in the block (dock_node), off the tape and on it alike:
//
//   - its column as wide as the rail is drawn where the block's move has got (RailAt: its width, its padding, its top
//     row's height), 6 between what it holds;
//   - its top row the window's title bar where the window's buttons are in the app's top row (dragging the window);
//   - its places (rail_place_node), scrolling where the window is short: each a ground under its icon (the pointer's
//     ground eased in as it comes on, the lit place's), what waits in it hung on its corner, its tip (对话's and 用量's
//     their card as the pointer rests on them: rail_card_node), pressed its place, right clicked the rail's menu,
//     moved by a drag while the rail is changed (or with ⌘ held), outlined with its − while it is;
//   - at its foot what comes and goes (rail_transfers_node), the workspaces under the ＋ (rail_workspaces_node), and
//     settings.
//
// What opens from it stays the old frame's (rail_overlays): the rail's menu beside the place it was asked on, where that
// was as it was asked (rail_menu_from); 待处理's panel beside the bell, the ＋'s menu beside the ＋ and the list of what
// comes and goes beside its key, each where it was as it was pressed.

///|
/// How the rail is drawn where the block's move has got: the closed bar's or open; its width, its padding at its left,
/// top and foot, its top row's height (the space over its first place); what it stands on (its marks' discs); how far
/// in the lists' marks hung on its places are (as the sidebar folds).
priv struct RailAt {
  bar : Bool
  w : Double
  pl : Double
  pt : Double
  pb : Double
  top : Double
  under : Int64
  mark : Double
}

///|
/// The rail where the block's move has `f`, closed to the bar or not (`bar`).
fn rail_at_fold(bar : Bool, f : FoldLook) -> RailAt {
  { bar, w: f.rail_w, pl: f.rail_pl, pt: f.rail_pt, pb: f.rail_pb, top: f.rail_top, under: dock_ground(bar), mark: f.mark }
}

///|
/// The rail on the tape (open, its panel's: rail_open_tape), standing on `under` (its panel's ground, a step darker
/// behind the one in use).
fn rail_at_tape(under : Int64) -> RailAt {
  let inset = @sf.rail_in_tape()
  { bar: false, w: rail_box_w(false, None), pl: inset, pt: 0.0, pb: inset, top: rail_top_h(false), under, mark: 0.0 }
}

///|
/// Its grounds' corner, all one, linked to the corner they stand in: the closed bar's; the tape's sidebar panel's;
/// open, the window's, its places where the bar's are (12 in: through the bar, the same corner), as round as the bar's
/// would have them where the window has none to follow.
fn rail_round_of(bar : Bool) -> @ui.Radius {
  let in_bar : @ui.CornerOf = Follow(@sf.closed_bar_of(rail_closed_ground_in), rail_closed_ground_in, @sf.small_corner)
  if bar {
    @sf.rail_ground_radius(@sf.closed_bar_of(rail_closed_ground_in), rail_closed_ground_in)
  } else if wide.tape.get() {
    @sf.rail_ground_radius(@sf.tape_side_corners()[3], @sf.rail_in_tape() + rail_ground_in)
  } else {
    @sf.rail_ground_radius(Window, rail_window_in() + rail_ground_in, alone=in_bar.radius(@ui.corner_roots()))
  }
}

///|
/// Node `v` as round as the rail's grounds are where `at` says the rail is (rail_round_of): linked to the corner they
/// stand in where that is so, else one radius all round.
fn rail_round_node(v : @view.View, at : () -> RailAt) -> Unit {
  @ui.tree_corners_linked(v, fn() { rail_round_of(at().bar).links() })
  v.radius(By(fn() {
    let r = rail_round_of(at().bar)
    match r.links() {
      Some(_) => 0.0
      None => @ui.tree_theme().corner(r)
    }
  }))
  |> ignore
}

///|
/// The rail's places' nodes as they are made (their names), for what opens beside one at its cause (the rail's menu
/// asked of the rail itself or by a fixture: beside its first place, or the one named).
// kept across runs: each let go with its node
let rail_drawn : Map[String, @view.View] = Map([])

///|
/// The rail's node as it is made: the trigger of what opens beside it from the old frame (rail_adder: a press in the
/// rail none outside it).
// kept across runs: let go with its node
let rail_col : Ref[@view.View?] = Ref(None)

///|
/// Where the rail's menu opens beside: the place it was asked on, as it is placed now (View::placed_window_now), said
/// at that cause (a fixture's: open_rail_menu); None where it is not placed.
fn rail_place_at(place : String) -> (Double, Double, Double, Double)? {
  match rail_drawn.get(place) {
    Some(v) if v.alive() => Some(v.placed_window_now())
    _ => None
  }
}

///|
/// rail_place_at's for the rail's menu asked on the rail itself: beside its first place.
fn rail_menu_from(place : String, src : Source) -> (Double, Double, Double, Double)? {
  if place != "" {
    return rail_place_at(place)
  }
  match @sfbase.workspace_in_view(src).0 {
    Some(w) => rail_place_at(rail_items(src, w.id).get(0).unwrap_or(""))
    None => None
  }
}

///|
/// What the rail (rail_node) shows of a workspace as it opens, asked of `ask` (sfbase's opens_answered): the core's
/// marks (its places' tones, the workspaces' at its foot: one topic whichever workspace is shown), what it reads of it but
/// the prefs, which are the app's whole.
fn rail_opens(ask : (String, Map[String, Json]) -> @sfbase.TopicState) -> Bool {
  @sfbase.opens_answered(ask("workspaceMarks", @sfbase.marks_asked()))
}

///|
/// The rail in node `n` (as wide as the rail is drawn, the block's height), where `at` says it is drawn, in the workspace
/// in view; its tips in `tips`, its places' cards in `cards` (a layer over all of the window).
fn rail_node(n : @view.View, src : Source, tips : @sf.TipLayer, at : () -> RailAt) -> Unit {
  let ws = fn() { @sfbase.workspace_in_view(src).0 }
  n.box(fn(r) {
    rail_col.val = Some(r)
    r.owns(fn() {
      match rail_col.val {
        Some(v) if physical_equal(v, r) => rail_col.val = None
        _ => ()
      }
    })
    |> ignore
    r
    .grow(Is(1.0))
    .width(By(fn() { Some(at().w) }))
    .padding(By(fn() {
      let a = at()
      (a.pl, a.pt, 0.0, a.pb)
    }))
    .gap(Is(rail_gap))
    // (its menu asked of the rail itself: beside its first place)
    .on_menu(fn(_) {
      if wide.rail_menu.untracked() is None {
        wide.rail_menu.set(Some(("", rail_menu_from("", src))))
      }
    })
    |> ignore
    // its top row the window's title bar (the macOS app's buttons in it) across all of it, its padding too; not in the
    // closed bar (what is pressed there its places')
    r.box(fn(o) {
      o.over(Is(true)) |> ignore
      o.box(fn(row) {
        row
        .width(By(fn() { Some(at().w) }))
        .height(By(fn() { Some(dmax(at().top, closed_bar_top)) }))
        .margin(By(fn() {
          let a = at()
          (-a.pl, -a.pt, 0.0, 0.0)
        }))
        .laid_nowhere(By(fn() { !@ui.window_inset_now() || at().bar }))
        .moves_window(By(fn() { @ui.window_inset_now() && !at().bar }))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // the room over its first place (the column's gap after it part of it: where it is less than the gap, the excess
    // undone, so the places follow the move all the way to none)
    r.box(fn(t) {
      t
      .height(By(fn() { Some(dmax(0.0, at().top - rail_gap)) }))
      .margin(By(fn() { (0.0, 0.0, 0.0, dmin(0.0, at().top - rail_gap)) }))
      .laid_nowhere(By(fn() { at().top <= 0.0 }))
      |> ignore
    })
    |> ignore
    // the places, giving way and scrolling where the window is short (their marks reaching into the rail's margin)
    let places = @view.Scroll::new()
    r.box(fn(cap) {
      cap.margin(Is((-rail_ground_in, 0.0, -rail_ground_in, 0.0))) |> ignore
      cap.scrolls(places, fn(body) {
        body.box(fn(col) {
          @sf.style_node(col, fn() { rail_places_col })
          col.padding(Is((rail_ground_in, 0.0, rail_ground_in, 0.0))) |> ignore
          col.each(
            fn() {
              match ws() {
                Some(w) => rail_shown(src, w)
                None => []
              }
            },
            fn(p) { p },
            fn(item, place) { rail_place_node(item, src, tips, place.untracked(), at) },
          )
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    r.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    // what comes and goes (transfers.mbt), over the workspaces
    rail_transfers_node(r, src, tips, at)
    // the workspaces (sfpages' workspace.mbt), giving way and scrolling where the window is short
    rail_workspaces_node(r, src, tips, at)
    // settings
    rail_key_node(r, tips, at, fn() { lit_place() == "settings" }, fn() { @sf.t("web-pages.settings.title") }, rail_gear, fn(k) {
      @sf.icon_node(k.sq, "settings", rail_icon_size, By(k.ink)) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The settings' gear pressed: lit (in the settings), back out of them, to the chat last open; their list folded for the
/// page's room: shown over the page, or folded again (返回会话 at its top goes back).
fn rail_gear() -> Unit {
  let lit = lit_place()
  if lit == "settings" && wide.crowded {
    wide.peeking.set(!wide.peeking.get())
  } else if lit == "settings" {
    @sfbase.history_push()
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    wide.landed.set("")
  } else {
    open_settings()
    wide.peek_next.set(wide.crowded)
  }
}

///|
/// What a key of the rail gives what it draws on its ground: its ground (its 30 square), and its icon's ink now (the
/// words' colour eased in over 140 ms as it is lit or pointed at).
priv struct RailKey {
  sq : @view.View
  ink : () -> Int64
}

///|
/// A key of the rail in `parent`: its 38 to press, its ground 30 square under its icon (`square`: the 30 square alone,
/// a workspace's, its own to press), round as the rail's grounds are (`at`); the pointer's ground eased in as it comes
/// on it, and while `rest` says so at rest, the lit one's while `on` (where `on` lights it: `lit`), its icon's ink with
/// them (140 ms, lit while `on`); read out as a button saying `label`, beside it on hover its tip in `tips` (none where
/// `tipped` is false). Pressed, `press`. What it draws in its ground by `body`. Its node.
fn rail_key_node(
  parent : @view.View,
  tips : @sf.TipLayer,
  at : () -> RailAt,
  on : () -> Bool,
  label : () -> String,
  press : () -> Unit,
  body : (RailKey) -> Unit,
  tipped? : Bool = true,
  square? : Bool = false,
  rest? : () -> Bool = fn() { false },
  lit? : Bool = true,
) -> @view.View {
  let made : Ref[@view.View?] = Ref(None)
  parent.box(fn(item) {
    made.val = Some(item)
    @sf.style_node(item, fn() { if square { rail_sq } else { rail_item } })
    let hover = @sf.EdgeWay::new(0.0)
    let chosen = @sf.EdgeWay::new(if lit && @signals.untracked(on) { 1.0 } else { 0.0 })
    let ink = @sf.EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
    item.reacts(fn() { @sf.lit_node(item) }, fn(h) { hover.go(item, if h { 1.0 } else { 0.0 }, @sf.dur_ms) })
    if lit {
      item.reacts(on, fn(o) { chosen.go(item, if o { 1.0 } else { 0.0 }, @sf.dur_ms) })
    }
    item.reacts(fn() { on() || @sf.lit_node(item) }, fn(k) { ink.go(item, if k { 1.0 } else { 0.0 }, @sf.dur_ms) })
    item
    .presses(Is(true))
    .focusable(Is(true))
    .on_press(press)
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    if tipped {
      @sf.tip_node(tips, item, label, side=Right) |> ignore
    }
    let grounded = fn(sq : @view.View) {
      rail_round_node(sq, at)
      // (lit in the closed bar, on its floating ground: the words' colour at 12%, as plain a step above it as the
      // selected grey is above the sidebar; Rail.css.ts item, closed)
      sq.ground(By(fn() {
        let t = @sf.theme()
        let lit = if wide.closed.get() { @sf.alpha(t.p.text, lit_in_bar) } else { t.p.selected }
        let h = dmax(hover.shown(item), if rest() { 1.0 } else { 0.0 })
        let o = chosen.shown(item)
        if h <= 0.0 && o <= 0.0 {
          0L
        } else {
          @sf.over(@sf.alpha(t.p.hover, h * (1.0 - o)), @sf.alpha(lit, o))
        }
      }))
      |> ignore
      body({
        sq,
        ink: fn() {
          let t = @sf.theme()
          @sf.mix(t.p.text, ink.shown(item), t.p.muted)
        },
      })
    }
    if square {
      grounded(item)
    } else {
      item.box(fn(sq) {
        @sf.style_node(sq, fn() { rail_sq })
        grounded(sq)
      })
      |> ignore
    }
  })
  |> ignore
  made.val.unwrap_or(parent)
}

///|
/// A mark hung on the top right corner of a ground of the rail (`sq`, its 30 square), as rail_hung's: on the corner,
/// its middle on the ground's curve where it turns 45°, on a disc of what the rail stands on 2 round it; `shown` of the
/// way in (a list's as the sidebar folds: from 40%, clear up to half its size). What it is by `mark`.
fn rail_hung_node(sq : @view.View, at : () -> RailAt, shown : () -> Double, mark : (@view.View) -> Unit) -> Unit {
  let reach = fn() {
    @sf.on_corner(@ui.tree_theme().corner(rail_round_of(at().bar)), rail_hung_side, room=rail_sq_side / 2.0)
  }
  sq.box(fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(room) {
      @sf.style_node(room, fn() { rail_hung_room })
      room.offset(By(fn() { (rail_sq_side - rail_hung_side + reach(), -reach()) })) |> ignore
      room.box(fn(ring) {
        @sf.style_node(ring, fn() { rail_hung_ring })
        let scale = fn() {
          let s = shown()
          if s < 1.0 {
            fold_at(mark_folded_from, 1.0, s)
          } else {
            1.0
          }
        }
        ring
        .ground(By(fn() { at().under }))
        .alpha(By(fn() { @sf.seen_at(scale()) }))
        .scale(By(scale))
        |> ignore
        mark(ring)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What waits on a place: a red dot 8 across.
fn rail_dot_node(ring : @view.View) -> Unit {
  ring.box(fn(d) { @sf.style_node(d, fn() { rail_dot }) }) |> ignore
}

///|
/// One place of the rail in `item`, where `at` says the rail is drawn: its icon (the stations' their glyph), what waits on
/// it hung on its corner (a list's rows' mark while the sidebar is folded; 待处理's red dot); pressed, its page (the
/// lit place pressed again: its sidebar folded or opened); right clicked, the rail's menu beside it; dragged up or down
/// while the rail is changed or with ⌘ held as it was pressed, to another place in the rail; while the rail is changed,
/// outlined, its − at its top left corner. Its tip, or 对话's and 用量's card as the pointer rests on it.
fn rail_place_node(item : @view.View, src : Source, tips : @sf.TipLayer, place : String, at : () -> RailAt) -> Unit {
  let ws = fn() { @sfbase.workspace_in_view(src).0 }
  let t = fn() { @sf.theme() }
  // (as its key went down, whether ⌘ was held; how far the hold had gone as this place took it over from its key: each
  // said at that event)
  let cmd_down = Ref(false)
  let claimed = Ref(false)
  let claimed_dy = Ref(0.0)
  item
  // moved with its drag
  .offset(By(fn() {
    match wide.rail_drag.get() {
      Some((p, _, dy)) if p == place && dy.abs() > rail_slop => (0.0, dy)
      _ => (0.0, 0.0)
    }
  }))
  // dragged up or down past the slop while the rail is changed or with ⌘ held as it was pressed: the hold taken over
  // from its key (whose press is called off), to another place in the rail, the others as they were until let go
  .claims(fn(_, dy) {
    let takes = dy.abs() > rail_slop && (wide.editing.untracked() || cmd_down.val)
    if takes {
      claimed.val = true
      claimed_dy.val = dy
    }
    takes
  })
  .on_drag(fn(d) {
    match d.kind {
      Down => {
        let y0 = d.wy - claimed_dy.val
        wide.rail_drag.set(Some((place, y0, d.wy - y0)))
      }
      Moved =>
        match wide.rail_drag.get() {
          Some((p, y0, _)) if p == place => wide.rail_drag.set(Some((p, y0, d.wy - y0)))
          _ => ()
        }
      Up =>
        match wide.rail_drag.get() {
          Some((p, y0, _)) if p == place => {
            // let go: its place by how far it went
            let dy = d.wy - y0
            wide.rail_drag.set(None)
            guard ws() is Some(w) else { return }
            let places = rail_items(src, w.id)
            let from = places.search_by(fn(x) { x == place }).unwrap_or(0)
            let to = dmax(0.0, dmin((places.length() - 1).to_double(), from.to_double() + (dy / rail_pitch).round())).to_int()
            if to != from {
              let next = places.filter(fn(x) { x != place })
              next.insert(to, place)
              rail_keep(src, w.id, next)
            }
          }
          _ => ()
        }
      Off =>
        match wide.rail_drag.get() {
          Some((p, _, _)) if p == place => wide.rail_drag.set(None)
          _ => ()
        }
    }
  })
  |> ignore
  rail_drawn[place] = item
  item.owns(fn() {
    match rail_drawn.get(place) {
      Some(v) if physical_equal(v, item) => rail_drawn.remove(place)
      _ => ()
    }
  })
  |> ignore
  let on = fn() {
    match ws() {
      Some(w) => rail_lit(src, w, place) || (place == "attention" && wide.attention_open.get())
      None => false
    }
  }
  let label = fn() {
    match place {
      "stations" =>
        match ws() {
          Some(w) => "Station：" + rail_stations_label(src, w.id)
          None => "Station"
        }
      _ => rail_label(src, place)
    }
  }
  // pressed and let go: as it is let go, as things are then (while the rail is changed, a press of it is the change's;
  // dragged past a few points, a drag's; lit or not as it is then)
  let press = fn() {
    if wide.editing.get() {
      return
    }
    guard ws() is Some(w) else { return }
    // the lit place pressed again (not 待处理, a panel): its sidebar folded or opened, not gone to; folded so with the
    // pointer on the rail, it is shown a while; on the tape, the page brought over
    if rail_lit(src, w, place) && place != "attention" && !place_bare(lit_place()) {
      if wide.crowded {
        wide.peeking.set(!wide.peeking.get())
      } else {
        sidebar_toggle()
        wide.peeking.set(side_folded())
      }
    } else {
      rail_go_told(src, w, place, fn(_, g) { g() })
      // (pressed into a place whose sidebar is folded for the page's room: shown a while from the start, as the web's
      // pressed into a folded one)
      wide.peek_next.set(wide.crowded && !place_bare(place) && place != "attention")
    }
  }
  // what wants the person in a list, as its rows' marks: while the sidebar is folded (open, the rows show it;
  // Rail.css.ts listMark)
  let tone = fn() {
    match ws() {
      Some(w) => {
        let marks = src.topic("workspaceMarks", @sfbase.marks_asked()).get().value
        let here = field(field(marks, "workspaces"), w.id)
        match place {
          "chats" => text(here, "tone")
          "mine" => text(here, "mineTone")
          "watching" => text(here, "watchingTone")
          _ => ""
        }
      }
      None => ""
    }
  }
  let dot = fn() {
    place == "attention" &&
    (match ws() {
      Some(w) => bell_lit(src, w)
      None => false
    })
  }
  let carded = rail_carded(place)
  let key = rail_key_node(item, tips, at, on, label, press, tipped=!carded, fn(k) {
    if place == "stations" {
      // the stations at a glance (20)
      @sf.station_glyph_node(
        k.sq,
        fn() {
          match ws() {
            Some(w) => @sfbase.stations_at_glance(src, w.id).0
            None => { online: 0, dim: 0, failing: 0, working: 0, asleep: false, connecting: 0 }
          }
        },
        rail_icon_size,
        k.ink,
        fn() { t().p.red },
      )
      |> ignore
    } else {
      @sf.icon_node(k.sq, rail_icon(place), rail_icon_size, By(k.ink)) |> ignore
    }
    // hung on its ground's corner
    k.sq.show(fn() { tone() != "" && at().mark > 0.0 }, fn(m) {
      m.over(Is(true)) |> ignore
      rail_hung_node(m, at, fn() { at().mark }, fn(ring) { @sfpages.chat_mark_node(ring, tone) })
    })
    k.sq.show(dot, fn(m) {
      m.over(Is(true)) |> ignore
      rail_hung_node(m, at, fn() { 1.0 }, rail_dot_node)
    })
  })
  // right clicked, the rail's menu beside it (its key's: the node a press there finds)
  key.on_menu(fn(_) { wide.rail_menu.set(Some((place, Some(item.placed_window_now())))) }) |> ignore
  // (as its key goes down, said at that event: pressed while the rail is changed or with ⌘ held, its drag begun, not
  // moved yet (where from, as the hold is taken over past the slop); let go or called off with none taken over, over)
  key.reacts(fn() { key.pressed() }, fn(down) {
    if down {
      cmd_down.val = (@ui.mods_held() & @ui.mod_cmd) != 0
      claimed.val = false
      if wide.editing.untracked() || cmd_down.val {
        wide.rail_drag.set(Some((place, 0.0, 0.0)))
      }
    } else if !claimed.val {
      match wide.rail_drag.untracked() {
        Some((p, _, _)) if p == place => wide.rail_drag.set(None)
        _ => ()
      }
    }
  })
  // while the rail is changed: outlined, dashed, its − at its top left corner (taking it out, while another is left)
  item.show(fn() { wide.editing.get() }, fn(e) {
    e.over(Is(true)) |> ignore
    e.box(fn(d) {
      d
      .width(Is(Some(rail_dash_side + rail_dash_line)))
      .height(Is(Some(rail_dash_side + rail_dash_line)))
      .offset(Is((rail_dash_at, rail_dash_at)))
      .picture(By(fn() {
        Some(@sf.dashed_vector(rail_dash_side, rail_dash_side, rail_dash_r, rail_dash_line, t().p.line_strong))
      }))
      |> ignore
    })
    |> ignore
    e.box(fn(at_corner) {
      @sf.style_node(at_corner, fn() { rail_remove_at })
      at_corner.offset(Is((rail_remove_out, rail_remove_out))) |> ignore
      at_corner.box(fn(rm) {
        @sf.style_node(rm, fn() { rail_remove })
        rm
        .presses(Is(true))
        .on_press(fn() {
          guard ws() is Some(w) else { return }
          let items = rail_items(src, w.id)
          if items.length() > 1 {
            rail_keep(src, w.id, items.filter(fn(i) { i != place }))
          }
        })
        .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.rail.remove", args=[("name", rail_label(src, place))]))) }))
        |> ignore
        @sf.icon_node(rm, "minus", rail_remove_icon, By(fn() { t().p.sidebar })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // 对话's, 用量's: what the place is about at a glance, beside it as the pointer rests on it (in place of its tip)
  if carded {
    rail_card_node(key, src, tips, place)
  }
}

///|
/// Where 待处理's panel opens beside the rail's bell: where the bell was as the panel opened (attention_set; none: no bell
/// placed then).
// kept across runs: said at each opening of the panel, put back by wide_reset
let attention_from : Ref[(Double, Double, Double, Double)?] = Ref(None)

///|
/// Place `place`'s card (rail_card's: 对话's, 用量's) beside its key `anchor` on the rail, at its right, lined up with
/// its top, as the pointer rests on it a while (hover_open_ms: 320) with no press, a mouse's; kept while the pointer is
/// on the key or the card, gone hover_close_ms (120) after it has left both. In the tips' layer, over all of the window,
/// a small panel 320 wide whose words are the core's card (sfpages' rail_card_node).
fn rail_card_node(anchor : @view.View, src : Source, tips : @sf.TipLayer, place : String) -> Unit {
  let open : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  let card : Ref[@view.View?] = Ref(None)
  let due : Ref[(() -> Unit)?] = Ref(None)
  let stop = fn() {
    match due.val {
      Some(s) => s()
      None => ()
    }
    due.val = None
  }
  let on_card = fn() {
    match card.val {
      Some(c) if c.alive() => c.pointed_in()
      _ => false
    }
  }
  let made = Ref(false)
  let make = fn() {
    guard (tips.layer)() is Some(l) else { return }
    made.val = true
    let holder = l.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(anchor)
    holder.show(fn() { open.get() }, fn(k) {
      card.val = Some(k)
      k.beside(anchor.id(), side=Right, along=Start, offset=rail_card_off) |> ignore
      k
      .width(Is(Some(rail_card_w)))
      // (a small panel's: @sf.small_panel)
      .ground(By(fn() { @sf.panel_ground() }))
      .radius(Is(@sf.r_menu))
      .edge(By(fn() { (1.0, @sf.theme().p.line) }))
      .shadow(By(fn() { (16.0, 12.0, @sf.theme().p.shadow) }))
      .clips(Is(true))
      .padding(Is((@sf.panel_pad, @sf.panel_pad, @sf.panel_pad, @sf.panel_pad)))
      // (a press on it its own: a ground, the arrow over it)
      |> @sf.ground_node
      |> ignore
      // (its words 10 in: what reaches out to the panel's padding, 分享卡片, drawn there)
      k.box(fn(w) {
        @sf.style_node(w, fn() { rail_card_words })
        // (a figure pressed: the chats it counts, the card gone)
        @sfpages.rail_card_node(w, src, fn() { @sfbase.workspace_in_view(src).0 }, place, go=fn(to) {
          stop()
          open.set(false)
          guard @sfbase.workspace_in_view(src).0 is Some(ws) else { return }
          // (待处理 opened, never closed by it: the bell's own press toggles it)
          if to == "attention" {
            attention_set(true)
          } else {
            rail_go_told(src, ws, to, fn(_, f) { f() })
          }
        })
      })
      |> ignore
    })
  }
  let state = fn() { (@sf.pointer_rests() && anchor.pointed() && !anchor.pressed(), on_card()) }
  anchor.reacts(state, fn(s) {
    let (rests, held) = s
    let at = anchor.cause_at()
    stop()
    if rests || held {
      if !open.untracked() {
        due.val = Some(
          anchor.at_moment(at + @sfpages.hover_open_ms, fn() {
            let (rests, _) = @signals.untracked(state)
            if rests {
              if !made.val {
                make()
              }
              open.set(true)
            }
          }),
        )
      }
    } else if open.untracked() {
      due.val = Some(
        anchor.at_moment(at + @sfpages.hover_close_ms, fn() {
          let (rests, held) = @signals.untracked(state)
          if !rests && !held {
            open.set(false)
          }
        }),
      )
    }
  })
  anchor.owns(stop) |> ignore
}

///|
/// The card beside its place: 320 wide, 6 past it, its words 16 in (the small panel's 6 and the card's 10).
let rail_card_w : Double = 320.0

///|
let rail_card_off : Double = 6.0

///|
/// How far in the card's words stand from the small panel's padding (hover_words_in: 10): what reaches out by as much
/// (rail_card_node's 分享卡片) inside it.
// kept across runs: a value (no field of it changes)
let rail_card_words : @ui.Style = @ui.css("w=Full p=S2_5")

///|
/// What comes and goes (transfers.mbt's) as a key of the rail in `r`, over the workspaces (as a small screen's home's
/// key: transfers_key): as far as it has come (@sf.coming_mark_node in its mark's place), the alert's dot hung on its
/// corner when one failed; pressed, their list beside it (rail_overlays: where it was as it was pressed). Laid nowhere
/// while there is none.
fn rail_transfers_node(r : @view.View, src : Source, tips : @sf.TipLayer, at : () -> RailAt) -> Unit {
  let ws = fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => w.id
      None => ""
    }
  }
  let going = fn() { coming(src, ws()).going() }
  let key = rail_key_node(
    r,
    tips,
    at,
    fn() { ftransfers.open.get() },
    fn() {
      let (n, percent, _) = going()
      coming_words(n, percent)
    },
    // (pressed and let go: its list opened beside where it is then, or closed)
    fn() {
      let open = !ftransfers.open.get()
      if open {
        transfers_from.val = rail_transfers_key.val.map(fn(v) { v.placed_window_now() })
      }
      ftransfers.open.set(open)
    },
    fn(k) {
      @sf.coming_mark_node(k.sq, fn() { going().1.to_double() / 100.0 }, rail_icon_size, k.ink)
      k.sq.show(fn() { going().2 }, fn(m) {
        m.over(Is(true)) |> ignore
        rail_hung_node(m, at, fn() { 1.0 }, fn(ring) { @sfpages.chat_mark_node(ring, fn() { "alert" }) })
      })
    },
  )
  rail_transfers_key.val = Some(key)
  key.owns(fn() {
    match rail_transfers_key.val {
      Some(v) if physical_equal(v, key) => rail_transfers_key.val = None
      _ => ()
    }
  })
  |> ignore
  key.laid_nowhere(By(fn() { coming(src, ws()).none() })) |> ignore
}

///|
/// The key of what comes and goes as it is made (rail_transfers_node), and where it was as its list was opened from it:
/// where the list opens beside (rail_overlays).
// kept across runs: let go with its node
let rail_transfers_key : Ref[@view.View?] = Ref(None)

///|
// kept across runs: said as the list is opened from the key, put back by wide_reset
let transfers_from : Ref[(Double, Double, Double, Double)?] = Ref(None)

///|
/// The workspaces at the rail's foot (workspaceItem) in `r`, under the ＋, where `at` says the rail is drawn: each on a
/// 30 square of its own, 6 apart (a letter on the places' ground, a mark on nothing, the places' ground under the
/// pointer); the one in view a short bar at its left; another with what waits in it (the core's marks' tone) its mark on
/// its corner, said beside its name. The ＋ (making one, another account, invitations; the accent's dot on its corner
/// while one waits) always seen (the web's only as the pointer comes over them), lit while its menu is open; pressed,
/// its menu (sfpages' workspace_menu, beside where it was as it was pressed: rail_overlays). Pressed, that workspace.
/// Giving way and scrolling where the window is short.
fn rail_workspaces_node(r : @view.View, src : Source, tips : @sf.TipLayer, at : () -> RailAt) -> Unit {
  let ws = fn() { @sfbase.workspace_in_view(src).0 }
  let marks = fn() {
    match ws() {
      Some(_) => field(src.topic("workspaceMarks", @sfbase.marks_asked()).get().value, "workspaces")
      None => None
    }
  }
  let list = @view.Scroll::new()
  r.box(fn(cap) {
    cap.shrink(Is(1.0)).min_height(Is(Some(0.0))).margin(Is((-rail_ground_in, 0.0, -rail_ground_in, 0.0))) |> ignore
    cap.scrolls(list, fn(body) {
      body.box(fn(col) {
        @sf.style_node(col, fn() { rail_ws_list })
        col.padding(Is((rail_ground_in + rail_ground_in, rail_ground_in, rail_ground_in, rail_ground_in))) |> ignore
        // the ＋
        let add = rail_key_node(
          col,
          tips,
          at,
          @sfpages.workspace_menu_open,
          fn() { @sf.t("web-main.rail.addWorkspace") },
          fn() {
            if !@sfpages.workspace_menu_open() {
              workspace_add_from.val = rail_add.val.map(fn(v) { v.placed_window_now() })
            }
            @sfpages.workspace_add_pressed()
          },
          square=true,
          rest=@sfpages.workspace_menu_open,
          lit=false,
          fn(k) {
            // (always seen: what stands over it, what comes to this device, would else stand alone over a gap)
            @sf.icon_node(k.sq, "plus", rail_plus_size, By(k.ink)) |> ignore
            // an invitation waiting: the accent's dot
            k.sq.show(fn() { @sfpages.invitations_waiting(src).length() > 0 }, fn(m) {
              m.over(Is(true)) |> ignore
              rail_hung_node(m, at, fn() { 1.0 }, rail_invite_node)
            })
          },
        )
        rail_add.val = Some(add)
        add.owns(fn() {
          match rail_add.val {
            Some(v) if physical_equal(v, add) => rail_add.val = None
            _ => ()
          }
        })
        |> ignore
        col.each(
          fn() { @sfbase.workspace_in_view(src).1.map(fn(x) { x.id }) },
          fn(id) { id },
          fn(row, item) {
            let id = item.untracked()
            let it = fn() { @sfbase.workspace_in_view(src).1.iter().find_first(fn(x) { x.id == id }) }
            let here = fn() { ws().map(fn(w) { w.id == id }).unwrap_or(false) }
            let marked = fn() { it().map(@sfpages.workspace_marked).unwrap_or(false) }
            let tone = fn() { if here() { "" } else { text(field(marks(), id), "tone") } }
            let label = fn() {
              let name = it().map(fn(x) { x.name }).unwrap_or("")
              let said = text(field(marks(), id), "label")
              if here() || said == "" {
                name
              } else {
                name + " · " + said
              }
            }
            let key = rail_key_node(
              row,
              tips,
              at,
              here,
              label,
              fn() {
                if !here() {
                  @sfpages.switch_workspace(src, id)
                }
              },
              square=true,
              rest=fn() { !marked() },
              lit=false,
              fn(k) {
                // its mark, else its letter (sfpages' workspace_mark)
                k.sq.pick(fn() { if marked() { 1 } else { 0 } }, fn(m, which) {
                  if which == 1 {
                    @sf.station_mark_node(
                      m,
                      fn() { it().map(fn(x) { x.emoji }).unwrap_or("") },
                      fn() { it().map(fn(x) { x.icon }).unwrap_or("") },
                      rail_ws_mark,
                      fn() { @sf.theme().p.text },
                      fn() { 0 },
                    )
                  } else {
                    @sf.words_node(m, fn() { @sf.initial(it().map(fn(x) { x.name }).unwrap_or("")) }, fn() { rail_letter })
                    .ink(By(k.ink))
                    |> ignore
                  }
                })
                // the one in view: a short bar in the margin at its left
                k.sq.show(here, fn(m) {
                  m.over(Is(true)) |> ignore
                  m.box(fn(bar) {
                    @sf.style_node(bar, fn() { rail_bar })
                    bar.offset(Is((-rail_bar_out, rail_bar_down))) |> ignore
                  })
                  |> ignore
                })
                // another's: what waits there, as its rows' marks
                k.sq.show(fn() { tone() != "" }, fn(m) {
                  m.over(Is(true)) |> ignore
                  rail_hung_node(m, at, fn() { 1.0 }, fn(ring) { @sfpages.chat_mark_node(ring, tone) })
                })
              },
            )
            // A workspace has no place to remove, but the rail's menu still opens beside the workspace asked on.
            key.on_menu(fn(_) { wide.rail_menu.set(Some(("", Some(key.placed_window_now())))) }) |> ignore
          },
        )
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The ＋ over the workspaces as it is made, and where it was as its menu was opened from it: where the menu opens beside
/// (rail_overlays).
// kept across runs: let go with its node
let rail_add : Ref[@view.View?] = Ref(None)

///|
// kept across runs: said as the menu is opened from the ＋, put back by wide_reset
let workspace_add_from : Ref[(Double, Double, Double, Double)?] = Ref(None)

///|
/// An invitation waiting, hung on the ＋'s corner (sfpages' invite_dot): the chats' blue dot, 8 across.
fn rail_invite_node(ring : @view.View) -> Unit {
  ring.box(fn(d) { @sf.style_node(d, fn() { rail_invite_dot }) }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let rail_invite_dot : @ui.Style = @ui.style(w=S2, h=S2, radius=Full, bg=@sf.mark_blue)

///|
/// The ＋'s icon (16), a workspace's mark (18).
let rail_plus_size : Double = 16.0

///|
let rail_ws_mark : Double = 18.0

///|
/// A workspace's letter (600), as big in each; its ink the rail's keys' (muted unless it is the one in view or pointed
/// at).
// kept across runs: a value (no field of it changes)
let rail_letter : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, color=Muted, wrap=false)

///|
/// The workspaces' column: 6 between.
// kept across runs: a value (no field of it changes)
let rail_ws_list : @ui.Style = @ui.css("gap=S1_5")

///|
/// The bar at the left of the workspace in view: 8 down its square, 6 out past it, 3 by 14, its corner 2.
// kept across runs: a value (no field of it changes)
let rail_bar : @ui.Style = @ui.style(w=Fixed(rail_bar_w), h=S3_5, radius=Sm, bg=Fg)

///|
let rail_bar_w : Double = 3.0

///|
let rail_bar_out : Double = 6.0

///|
let rail_bar_down : Double = 8.0
