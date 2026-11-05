// An agent at work in a chat's list (chat_rows.mbt's activity_row) made once in the window's tree: its picture ringed,
// what it does now steadied (each step a moment at least, each glyph giving way to the next step's at its place), how
// long its turn has run; pressed, its history beside the chat; one of several, its own stop under the pointer. For a
// message to come out of its picture the line folds to the picture, which is away while its copy flies (emit.mbt).

///|
/// Agent `a`'s line (as it is now) in `row` of chat `rk`'s list: `came` the moment its row came new into the list it is
/// watched in (its first words come in a glyph at a time from then), None where it was there already.
fn activity_node(row : @view.View, src : Source, here : () -> MessageHere, a : () -> Agent, rk : String, came : Double?) -> Unit {
  let em = @sfbase.emits_of(rk)
  let key = @signals.untracked(a).key
  let row_key = rk + "\u{1}" + key
  // (what it does now, as the core says: what it waits on, else its live step)
  let said = fn() -> (String, String, Bool, Bool) {
    let now = a()
    match now.wait {
      Some((_, _, w)) => ("wait", if w != "" { w } else { @sf.t("web-main.activity.waiting") }, false, true)
      None => {
        let h = here()
        let live = @sfbase.hold(src, @sfbase.chat_scope(h.station, h.session), "live", {
          "station": Json::string(h.station),
          "key": Json::string(key),
        })
        let n = field(field(live.value, "activity"), "now")
        match text(n, "text") {
          "" => ("busy", @sf.t("web-main.activity.busy"), false, false)
          s => (text(n, "key"), s, flag(n, "mono"), flag(n, "important"))
        }
      }
    }
  }
  // (folded to its picture from when its first message waits till its last is out)
  let folded = fn() { emit_folded(em, key) }
  let tail = @motion.Way::new(if @signals.untracked(folded) { 0.0 } else { 1.0 })
  // (what it does now as wide as it was laid out whole, as it set out to fold away: what it is cut to a share of; and
  // that, made later)
  let inner_w : @signals.Signal[Double] = @signals.signal(0.0, same=fn(x, y) { x == y })
  let inner_at : Ref[@view.View?] = Ref(None)
  row.reacts(folded, fn(f) {
    let to = if f { 0.0 } else { 1.0 }
    if tail.target() != to {
      // (as wide as it is laid out as of this moment, whole as it sets out: said once, never followed)
      if f && tail.value_at(row.cause_at()) >= 1.0 {
        match inner_at.val {
          Some(v) => inner_w.set(v.laid_size().0)
          None => ()
        }
      }
      tail.go(to, @motion.tween(fold_ms, ease=Out), at=row.cause_at())
    }
  })
  let tail_k = fn() { way_shown(tail, row) }
  // (several agents: each its own stop, under the pointer)
  let several = fn() { here().view.agents.length() > 1 }
  let hot : Ref[() -> Bool] = Ref(fn() { false })
  let area : Ref[@view.View?] = Ref(None)
  row.row(Is(true)).gap(Is(4.0)).lines_up(Is(Some(Middle))) |> ignore
  area.val = Some(row)
  row.box(fn(line) {
    let inline = fn() { here().inline }
    line
    .row(Is(true))
    .gap(Is(8.0))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    .lines_up(Is(Some(Middle)))
    .margin(By(fn() { (if inline() { 0.0 } else { -@sf.message_avatar_reach }, 0.0, 0.0, 0.0) }))
    .says(By(fn() { Some(@view.said(Button, label=a().who + "：" + said().1)) }))
    |> ignore
    @sf.presses_node(line, fn() {
      let h = here()
      open_detail(src, here_ref(h), key)
    })
    // (over it or over what it holds: its words take the pointer too, to be picked)
    hot.val = fn() { row.pointed_in() }
    // (its picture with the ring round it, 24 across, the ring reaching 3 past the picture into no room of the line's;
    // away while its copy flies, its ring with it)
    line.box(fn(face) {
      face
      .width(Is(Some(ring_side)))
      .height(Is(Some(ring_side)))
      .margin(Is((-ring_room, 0.0, -ring_room, 0.0)))
      .lies_along(Is(Middle))
      .lines_up(Is(Some(Middle)))
      .alpha(By(fn() {
        em.read()
        if em.copied == key { 0.0 } else { 1.0 }
      }))
      |> ignore
      let av = agent_avatar_node(face, fn() { a().maker }, fn() { a().runtime }, fn() { "" })
      emit_place_node(av, fn() { Some("emit-avatar/" + rk + "/" + key) })
      // (its agent's card under the pointer resting on its picture, as beside its messages: agent_hover_node)
      agent_hover_node(face, src, here, fn() { key })
      face.box(fn(ring) {
        ring.over(Is(true)) |> ignore
        ring.pick(fn() { a().wait is Some(_) }, fn(w, waiting) {
          if waiting {
            w
            .width(Is(Some(ring_side)))
            .height(Is(Some(ring_side)))
            .radius(Is(ring_side / 2.0))
            .edge(By(fn() { (ring_stroke, @ui.tree_theme().color(Line)) }))
            |> ignore
          } else {
            @sf.segments_node(w, ring_side, ring_stroke, fn() { @sf.theme().p.accent }, fn() { @sf.theme().p.bg })
            |> ignore
          }
        })
      })
      |> ignore
    })
    |> ignore
    // (what it does now and how long: folded away to its width's share, cut there, faded)
    line.box(fn(cut) {
      cut
      .row(Is(true))
      .min_width(Is(Some(0.0)))
      .shrink(Is(1.0))
      .clips(By(fn() { tail_k() < 1.0 }))
      .max_width(By(fn() {
        let k = tail_k()
        if k < 1.0 && inner_w.get() > 0.0 {
          Some(inner_w.get() * k)
        } else {
          None
        }
      }))
      .alpha(By(fn() { tail_k() }))
      |> ignore
      cut.box(fn(inner) {
        inner.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).min_width(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
        inner_at.val = Some(inner)
        inner.owns(fn() { inner_at.val = None }) |> ignore
        // (its clock after its words, made once they are: what their room is less)
        let clock : Ref[Ref[@view.View?]] = Ref(Ref(None))
        steady_node(inner, row_key, said, fn() { (hot.val)() }, came, fn() {
          // (the room its words have: the row's end less its stop's, its clock's and the gap before it)
          match (area.val, clock.val.val) {
            (Some(r), Some(c)) => {
              let (rx, _, rw, _) = r.rect()
              let (sx, _, _, _) = inner.rect()
              let (_, _, cw, _) = c.rect()
              let stop = if several() { 28.0 } else { 0.0 }
              dmax(rx + rw - sx - stop - (if cw > 0.0 { cw + 8.0 } else { 0.0 }), 0.0)
            }
            _ => 0.0
          }
        })
        clock.val = activity_clock_node(inner, src, a, came)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // (one of several agents: stopped alone from its row, its key at the row's end laid out there whether it shows or not,
  // shown while the pointer is over the row or it shows the focus, faded in and out from that moment (how opaque it is
  // as it is drawn, nothing laid out again for it), pressed with a mouse alone: the web's activityStop)
  row.show(fn() { several() }, fn(s) {
    let label = fn() { @sf.t("web-main.activity.stop", args=[("who", a().who)]) }
    let shown = @sf.EdgeWay::new(0.0)
    s.reacts(fn() { (hot.val)() || s.focus_shown() }, fn(on) { shown.go(s, if on { 1.0 } else { 0.0 }, @sf.dur_ms) })
    s
    .alpha(By(fn() { shown.shown(s) }))
    .hides(By(fn() { shown.target() == 0.0 }))
    .presses(By(fn() { @ui.pointing() is Mouse }))
    .width(Is(Some(24.0)))
    .height(Is(Some(24.0)))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if s.pointed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(s, fn() {
      let h = here()
      act(src, @sf.t("web-pages.chat.stop"), "", "session.stop", {
        "station": Json::string(h.station),
        "key": Json::string(key),
      }, done=@sf.t("web-pages.chat.stopAsked"))
    })
    @sf.icon_node(s, "stop", stop_icon, By(fn() { if s.pointed() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
  })
}

///|
/// How long agent `a`'s turn has run (or how long it has waited, of how long at most), in whole seconds, going on by
/// the clock: the node, where it shows one. Its row new to the list at `came`: faded in from then (as its row's room
/// opens).
fn activity_clock_node(parent : @view.View, src : Source, a : () -> Agent, came : Double?) -> Ref[@view.View?] {
  let at : Ref[@view.View?] = Ref(None)
  // (a second gone by: told at each whole second of what it shows)
  let tick = @signals.signal(0)
  let since = fn() -> (Double, Double?)? {
    let now = a()
    match now.wait {
      Some((since, most, _)) => Some((since, most.map(fn(sec) { since + sec * 1000.0 })))
      None => now.since.map(fn(s) { (s, None) })
    }
  }
  let words = fn() {
    tick.get() |> ignore
    match since() {
      Some((from, most)) => {
        let now = (src.now)()
        let to = match most {
          Some(m) => dmin(now, m)
          None => now
        }
        elapsed(to - from) +
        (match (a().wait, most) {
          (Some((_, Some(sec), _)), Some(_)) => " / " + elapsed(sec * 1000.0)
          _ => ""
        })
      }
      None => ""
    }
  }
  parent.show(fn() { since() is Some(_) }, fn(c) {
    at.val = Some(c)
    let next : Ref[() -> Unit] = Ref(fn() {  })
    let wake : Ref[() -> Unit] = Ref(fn() {  })
    wake.val = fn() {
      match @signals.untracked(since) {
        Some((from, most)) => {
          let now = (src.now)()
          if most is Some(m) && now >= m {
            return
          }
          let gone = dmax(now - from, 0.0)
          let left = second_ms - (gone - (gone / second_ms).floor() * second_ms)
          next.val = c.at_moment(c.logic_at() + left, fn() {
            tick.set(@signals.untracked(fn() { tick.get() }) + 1)
            (wake.val)()
          })
        }
        None => ()
      }
    }
    c.reacts(since, fn(_) {
      (next.val)()
      (wake.val)()
    })
    c.owns(fn() { (next.val)() }) |> ignore
    @sf.words_node(c, words, fn() { activity_clock }) |> ignore
    match came {
      Some(start) =>
        c.alpha(By(fn() {
          if c.logic_at() >= start + @ui.row_size_ms {
            1.0
          } else {
            @ui.Ease::Out.at(dmax(dmin((c.drawn_at() - start) / @ui.row_size_ms, 1.0), 0.0))
          }
        }))
        |> ignore
      None => ()
    }
  })
  at
}

///|
/// Where way `w` is as node `v` is drawn while it goes, followed by the clock then; its end once it is there.
fn way_shown(w : @motion.Way, v : @view.View) -> Double {
  w.said()
  if w.goes_at(v.logic_at()) {
    w.value_at(v.drawn_at())
  } else {
    w.target()
  }
}

///|
/// What an activity's node shows, steadied (steady_words's), by its row: what it shows and what it showed before, from
/// when, what waits for its turn; the change's glyphs' places and widths; its ways (the change, the line's width).
priv struct SteadyNode {
  mut key : String
  mut words : String
  mut mono : Bool
  mut important : Bool
  mut was : String
  mut was_mono : Bool
  mut at : Double
  mut pending : String?
  mut pending_at : Double
  mut important_next : (String, String, Bool, Double)?
  mut places : Int
  mut old_cells : Array[(Double, Double)]
  mut new_cells : Array[(Double, Double)]
  /// the line's width at each end of the change, what shows of it and whole
  mut from_w : Double
  mut to_w : Double
  mut whole_from : Double
  mut whole_to : Double
  /// the first words' coming in (from when; -inf none), the change's glyphs and the line's width
  mut came : Double
  reveal : @motion.Way
  swap : @motion.Way
  /// told as what it shows changes
  told : @signals.Signal[Int]
  /// how many changes it has begun (each made anew, its two lines its own)
  mut changes : Int
}

///|
// kept across runs: rows_reset empties it
let steady_nodes : Map[String, SteadyNode] = {}

///|
fn SteadyNode::tell(self : SteadyNode) -> Unit {
  self.told.set(@signals.untracked(fn() { self.told.get() }) + 1)
}

///|
/// What an activity says now in `parent`, steadied (steady_words's): brief routine steps coalesced, important ones each
/// a turn; each step a moment at least; each glyph giving way to the next step's at its place, the line going from
/// the one's width to the other's. `room` the line's room for its words as it is laid out.
fn steady_node(
  parent : @view.View,
  row : String,
  said : () -> (String, String, Bool, Bool),
  hot : () -> Bool,
  came : Double?,
  room : () -> Double,
) -> Unit {
  // (its ink brighter under the pointer, as it is drawn alone: its words set as ever, nothing laid out again for it)
  let style = fn() { if hot() { now_words_hot } else { now_words } }
  let first = @signals.untracked(said)
  let st = match steady_nodes.get(row) {
    Some(s) => s
    None => {
      let (key, words, mono, important) = first
      let s = {
        key,
        words,
        mono,
        important,
        was: "",
        was_mono: false,
        at: parent.cause_at(),
        pending: None,
        pending_at: 0.0,
        important_next: None,
        places: 1,
        old_cells: [],
        new_cells: [],
        from_w: 0.0,
        to_w: 0.0,
        whole_from: 0.0,
        whole_to: 0.0,
        came: -1.0e18,
        reveal: @motion.Way::new(1.0),
        swap: @motion.Way::new(1.0),
        told: @signals.signal(0),
        changes: 0,
      }
      steady_nodes[row] = s
      // (new to the list it is watched in: its first words in a glyph at a time, from when its row came)
      match came {
        Some(at) => {
          s.came = at
          s.at = at
          s.reveal.put(0.0)
          s.reveal.go(1.0, @motion.tween(activity_glyph_in_ms, ease=Linear), at~)
        }
        None => ()
      }
      s
    }
  }
  // (what it waits for before the next check: let go as it checks again)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  // (the change under way's end)
  let ends : Ref[() -> Unit] = Ref(fn() {  })
  let check : Ref[() -> Unit] = Ref(fn() {  })
  let wait_till = fn(at : Double) {
    (due.val)()
    due.val = parent.at_moment(at, fn() { (check.val)() })
  }
  check.val = fn() {
    let (key, words, mono, important) = @signals.untracked(said)
    // (the moment what it checks was told: the core's change's, a due moment's, whatever frame takes it)
    let now = parent.cause_at()
    let mut next : (String, String, Bool, Bool, Double)? = None
    if st.came > now {
      // (before its row's turn, its first words are what the agent does at that turn)
      st.key = key
      st.words = words
      st.mono = mono
      st.important = important
      st.pending = None
      st.important_next = None
      st.tell()
      return
    }
    if important && key != st.key && words != st.words {
      let since = match st.important_next {
        Some((old, _, _, at)) if old == key => at
        _ => now
      }
      st.important_next = Some((key, words, mono, since))
    }
    match st.important_next {
      Some((next_key, next_words, next_mono, since)) => {
        // (a change under way not started again, an important step not cut short before it can be read)
        let wait = if st.important {
          steady_dwell_ms
        } else if @ui.reduced_motion() {
          0.0
        } else if st.was == "" {
          activity_glyph_in_ms
        } else {
          @sfbase.glyph_change_in_ms
        }
        let at = dmax(st.at + wait, since)
        if now < at {
          wait_till(at)
        } else {
          next = Some((next_key, next_words, next_mono, true, at))
          st.important_next = None
          // (the live step moved on while the important one waited: a turn of its own after it)
          if key != next_key && words != next_words {
            st.pending = Some(key)
            st.pending_at = now
            wait_till(dmax(at + steady_dwell_ms, now + steady_candidate_ms))
          } else {
            st.pending = None
          }
        }
      }
      None =>
        if key == st.key || words == st.words {
          if st.key != key || st.words != words || st.mono != mono || st.important != important {
            st.key = key
            st.words = words
            st.mono = mono
            st.important = important
            st.tell()
          }
          st.pending = None
        } else {
          // (a routine step gone before its own change could finish never starts one)
          if st.pending != Some(key) {
            st.pending = Some(key)
            st.pending_at = now
          }
          let at = dmax(st.at + steady_dwell_ms, st.pending_at + steady_candidate_ms)
          if now < at {
            wait_till(at)
          } else {
            next = Some((key, words, mono, false, at))
            st.pending = None
          }
        }
    }
    if next is Some((next_key, next_words, next_mono, next_important, at)) {
      let c = @ui.current()
      let s = @signals.untracked(style)
      st.was = st.words
      st.was_mono = st.mono
      st.key = next_key
      st.words = next_words
      st.mono = next_mono
      st.important = next_important
      st.at = at
      st.changes = st.changes + 1
      st.old_cells = @ui.runs_glyph_cells([@ui.span(st.was, mono=st.was_mono)], @ui.style_words(s))
      st.new_cells = @ui.runs_glyph_cells([@ui.span(st.words, mono=st.mono)], @ui.style_words(s))
      // (the reading order over what can be seen of either, however much longer one step is than the line)
      let visible = room()
      st.places = activity_change_places(st.old_cells, st.new_cells, visible)
      // (as wide as their nodes lay them out: the new one's where the change ends)
      st.whole_from = @ui.runs_across([@ui.span(st.was, mono=st.was_mono)], @ui.style_words(s))
      st.whole_to = @ui.runs_across([@ui.span(st.words, mono=st.mono)], @ui.style_words(s))
      st.from_w = dmin(st.whole_from, visible)
      st.to_w = dmin(st.whole_to, visible)
      st.reveal.put(0.0)
      st.reveal.go(1.0, @motion.tween(@sfbase.glyph_change_in_ms, ease=Linear), at~)
      st.swap.put(0.0)
      // (a Move as long as the line's change in width)
      st.swap.go(1.0, @motion.move(over=dmax(c.text_size(Meta).1, (st.to_w - st.from_w).abs())), at~)
      st.tell()
      // (its change over: what it shows told again, and the next step checked; its own, kept whatever is waited for
      // meanwhile)
      (due.val)()
      (ends.val)()
      ends.val = parent.at_moment(dmax(st.reveal.end(), st.swap.end()), fn() {
        st.tell()
        (check.val)()
      })
    }
  }
  parent.owns(fn() {
    (due.val)()
    (ends.val)()
  })
  |> ignore
  parent.reacts(said, fn(_) { (check.val)() })
  // (changing: its glyphs giving way, the line's width going between the two)
  let changing = fn() {
    st.told.get() |> ignore
    st.was != "" && (st.reveal.goes_at(parent.logic_at()) || st.swap.goes_at(parent.logic_at()))
  }
  // (each change its own nodes, one begun as the one before ends among them: its lines are its own)
  parent.pick(fn() { if changing() { st.changes } else { -1 } }, fn(w, change) {
    let is_changing = change >= 0
    w.row(Is(true)).min_width(Is(Some(0.0))).shrink(Is(1.0)) |> ignore
    let line = @signals.untracked(fn() { @ui.tree_theme().text_size(Meta).1 })
    let runs = fn(words : String, mono : Bool) { [@ui.span(words, mono~)] }
    if !is_changing {
      w.box(fn(t) {
        t
        .min_width(Is(Some(0.0)))
        .shrink(Is(1.0))
        .words_runs(By(fn() {
          st.told.get() |> ignore
          runs(st.words, st.mono)
        }))
        .words_look(By(fn() { @ui.style_words(now_words) }))
        .ink(By(fn() { @ui.style_ink(style()) }))
        .cuts(Is(true))
        .allow_ellipsis(Is(true))
        // (its first words in a glyph at a time, along the line)
        .glyphs_by(By(fn() { st.reveal.said(); if st.reveal.goes_at(t.logic_at()) { Some(t.drawn_at()) } else { None } }), fn(at, g) {
          let (x, _, width, _) = t.rect()
          let along = if width > 0.0 { dmax(dmin((g.x - x) / width, 1.0), 0.0) } else { 0.0 }
          let elapsed = st.reveal.value_at(at) * activity_glyph_in_ms - activity_glyph_delay_ms
          let l = @sfbase.glyph_in(elapsed, along * @sfbase.glyph_line_ms, g.index, row.length())
          { alpha: l.alpha, dx: l.dx, dy: l.dy, scale: l.scale, sx: l.sx }
        })
        |> ignore
      })
      |> ignore
      return
    }
    let k = fn() { way_shown(st.swap, w) }
    let across = fn() { st.from_w + (st.to_w - st.from_w) * k() }
    let wide = dmax(st.whole_from, st.whole_to)
    let clipped = st.whole_from > st.from_w + 0.5 || st.whole_to > st.to_w + 0.5
    // (both lines in a window no wider than the line has room for, the end faded where it widens, narrows or cuts)
    w.box(fn(window) {
      window
      .width(By(fn() { Some(across()) }))
      .height(Is(Some(line)))
      .clips(Is(true))
      .fades(By(fn() {
        let k = k()
        let gone = (st.to_w - st.from_w).abs()
        let from_fade = if st.whole_from > st.from_w + 0.5 { @ui.cut_soft_most } else { 0.0 }
        let to_fade = if st.whole_to > st.to_w + 0.5 { @ui.cut_soft_most } else { 0.0 }
        (0.0, 0.0, dmax(@ui.cut_soft(gone * k, gone * (1.0 - k)), from_fade * (1.0 - k) + to_fade * k), 0.0)
      }))
      |> ignore
      window.box(fn(both) {
        both.height(Is(Some(line))).width(By(fn() { Some(if clipped { across() } else { wide }) })) |> ignore
        let glyphs = fn(v : @view.View, incoming : Bool) {
          v.glyphs_by(By(fn() { if changing() { Some(v.drawn_at()) } else { None } }), fn(at, g) {
            let l = activity_change_glyph(st, row, incoming, way_value(st.reveal, at), way_value(st.swap, at), g.index)
            l
          })
          |> ignore
        }
        both.box(fn(before) {
          before
          .words_runs(Is(runs(st.was, st.was_mono)))
          .words_look(By(fn() { @ui.style_words(now_words) }))
          .ink(By(fn() { @ui.style_ink(style()) }))
          |> ignore
          glyphs(before, false)
        })
        |> ignore
        both.box(fn(next) {
          next
          .over(Is(true))
          .words_runs(Is(runs(st.words, st.mono)))
          .words_look(By(fn() { @ui.style_words(now_words) }))
          .ink(By(fn() { @ui.style_ink(style()) }))
          |> ignore
          glyphs(next, true)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// Where way `w` is at `t`.
fn way_value(w : @motion.Way, t : Double) -> Double {
  w.value_at(t)
}

///|
/// Glyph `index` of the step going (`incoming` false) or coming in a change (activity_change_glyphs's): each place's
/// glyph fading before the other comes, their centres going together from the old line's places to the new's.
fn activity_change_glyph(st : SteadyNode, row : String, incoming : Bool, reveal : Double, k : Double, index : Int) -> @view.GlyphLook {
  let (old_cells, new_cells, places) = (st.old_cells, st.new_cells, st.places)
  let intervals = if places > 1 { places - 1 } else { 1 }
  let along = dmin(index.to_double() / intervals.to_double(), 1.0)
  let look = @sfbase.glyph_change(reveal * @sfbase.glyph_change_in_ms, along * @sfbase.glyph_change_line_ms, index, row.length(), incoming)
  let (dx, sx) = if index < old_cells.length() && index < new_cells.length() {
    let (old_x, old_w) = old_cells[index]
    let (new_x, new_w) = new_cells[index]
    let distance = new_x - old_x
    let width = old_w + (new_w - old_w) * k
    let face_w = if incoming { new_w } else { old_w }
    (if incoming { -distance * (1.0 - k) } else { distance * k }, if face_w > 0.0 { dmin(width / face_w, 1.0) } else { 1.0 })
  } else if index < old_cells.length() && new_cells.length() > 0 {
    let n = new_cells.length() - 1
    let (old_x, old_w) = old_cells[n]
    let (new_x, new_w) = new_cells[n]
    ((new_x + new_w / 2.0 - old_x - old_w / 2.0) * k, 1.0)
  } else if index < new_cells.length() && old_cells.length() > 0 {
    let n = old_cells.length() - 1
    let (old_x, old_w) = old_cells[n]
    let (new_x, new_w) = new_cells[n]
    ((old_x + old_w / 2.0 - new_x - new_w / 2.0) * (1.0 - k), 1.0)
  } else {
    (0.0, 1.0)
  }
  { alpha: look.alpha, dx, dy: look.dy, scale: look.scale, sx }
}
