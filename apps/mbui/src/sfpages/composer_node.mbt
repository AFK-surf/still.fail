// A composer kept by its page. One Writing and one field live through its capsule/box changes; effects receive
// draft and host answers, actions send, and the properties describe only what is shown.

///|
pub(all) struct ComposerNode {
  root : @view.View
  cap : @view.View
  field : @view.View
  writing : Writing
  opened : () -> Bool
  hold : () -> ((Double) -> Unit)
  ground : () -> (Double, Double, Double, Double)
}

///|
/// The composer of this draft. The page supplies its retained extras, choices and tail. A send reads the current
/// specification; `place` and `room` describe the page's current room (`room`: composer_field_node's), never an old
/// frame's construction values.
pub fn composer_node(
  parent : @view.View,
  src : Source,
  draft : String,
  spec : () -> ComposerSpec,
  send : (Writing) -> Unit,
  room : (@view.View, (Double, Double) -> Double),
  extras : (@view.View, Writing, () -> Double, (@view.View) -> Unit) -> Unit,
  place? : () -> ComposerPlace = fn() { composer_alone },
  place_in? : (@view.View, (Double) -> ComposerPlace),
  toolbar? : (@view.View) -> Unit = fn(_) {  },
  tail? : (@view.View) -> Unit = fn(_) {  },
  tips? : @sf.TipLayer,
  active? : () -> Bool = fn() { true },
  neighbour? : (Int) -> Unit,
  drops? : @view.View,
) -> ComposerNode {
  let origin = if active() { composing.origin } else { None }
  let from = match origin {
    Some(o) if o.old && o.roomy != spec().roomy => (o.places)(parent.cause_at())
    _ => Map([])
  }
  let leaving_toolbar = match origin {
    Some(o) if !from.is_empty() && spec().toolbar is None => o.toolbar_node
    _ => None
  }
  let positions : Ref[(Double) -> Map[String, (Double, Double, Double, Double)]] = Ref(fn(_) { Map([]) })
  let cap_at : Ref[@view.View?] = Ref(None)
  let field_at : Ref[@view.View?] = Ref(None)
  let w_at : Ref[Writing?] = Ref(None)
  let focused = @signals.signal(false, same=fn(a, b) { a == b })
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  let held_box = fn() { composer_held_box_node(parent, draft) }
  let release : Ref[() -> Unit] = Ref(fn() {  })
  let ground : Ref[() -> (Double, Double, Double, Double)] = Ref(fn() { (0.0, 0.0, 0.0, 0.0) })
  let ref_keys : Ref[(Int, Int) -> Bool] = Ref(fn(_, _) { false })
  let opened = fn() {
    let w = w_at.val.unwrap()
    spec().roomy || focused.get() || held.get() || held_box() > 0.0 ||
      w.text.get() != "" || !w.files.get().is_empty() || !w.quotes.get().is_empty()
  }
  let root = parent.box(fn(root) {
    let w = @sfbase.writing_in(root, src, draft)
    w_at.val = Some(w)
    // (the composer on this draft now, as the old one says it as its draft changes: a composer made after it (the home's,
    // gone back to) finds its draft another, the cursor in it with keyboard and mouse: composer.mbt's entry rule)
    composing.draft = "\u{1}" + @signals.untracked(spec).session
    // A chat replacing an existing composer starts with the cursor it will take on a keyboard-driven screen.
    if origin is Some(_) && active() && !spec().locked && !@sf.soft_keyboard() && !@ui.current().field_focused() {
      w.field.focus()
    }
    let ready = fn() { (w.ready.get() || (w.text.get().trim() != "" && !w.starting.get())) && !spec().locked }
    let no_files = fn() { spec().locked || spec().offline }
    let has_extras = fn() { !w.files.get().is_empty() || !w.quotes.get().is_empty() }
    let inner = fn() { @ui.concentric(place().corner, @sf.composer_pad) }
    let submit = fn() {
      if ready() {
        @sfbase.send_sharing(src, w.key, spec().station, w.text.get().trim(chars=" \n\t").to_string(), fn() { send(w) })
      }
    }
    let last_warm : Ref[Double?] = Ref(None)
    let changed = fn() {
      let s = spec()
      if s.session == "" || s.locked || s.offline || !s.warm_agent || src.read_only { return }
      let now = root.cause_at()
      if last_warm.val is Some(before) && now - before < warm_every_ms { return }
      last_warm.val = Some(now)
      (src.call)("session.warm", { "station": Json::string(s.station), "key": Json::string(s.session) }, fn(_) {  })
    }
    let shape = fn() {
      "\{spec().roomy}|\{opened()}|\{held_box() > 0.0}|\{w.error.get()}|\{w.text.get()}|" +
      w.files.get().map(fn(f) { text(Some(f), "id") + "=" + waiting_picture(src, w, Some(f)).unwrap_or("none") }).join("|") +
      w.quotes.get().map(fn(q) { text(Some(q), "id") + "=" + text(Some(q), "text") }).join("|")
    }
    let (hint_alpha, caret_alpha) = composer_hint_node(root, draft, fn() { focused.get() || held.get() }, shape)
    let (hint_words, words_alpha) = composer_hint_words_node(root, fn() {
      focused.get() |> ignore
      let hint = space_hint(@ui.current(), (src.topic)("prefs", {}).value, spec().locked)
      if active() && hint != "" { hint } else { spec().placeholder }
    }, fn() { focused.get() || held.get() })
    let cap = composer_box_node(root, opened, has_extras, place, shape,
      fn(p, moves) { extras(p, w, inner, moves) },
      fn(p) {
        let field = composer_field_node(p, src, w, fn() { spec().station }, fn() { spec().locked }, fn() { spec().offline },
          hint_words, submit, changed, room, hint_alpha=fn() { hint_alpha() * words_alpha() }, caret_alpha~,
          keys=fn(code, mods) { (ref_keys.val)(code, mods) || composer_input_key(src, spec, w, active, neighbour, code, mods) })
        field_at.val = Some(field)
        field.reacts(fn() { (field.focused(), composing.cold_open.get() == notice_choice_key(draft, "wait")) }, fn(state) {
          let (on, choosing) = state
          focused.set(on)
          (release.val)()
          if on { held.set(true) } else if held.get() && !choosing {
            release.val = field.at_moment(field.cause_at() + let_go_ms, fn() { held.set(false) })
          }
        })
        field
      },
      fn(p) {
        @sf.composer_attach_node(p, no_files, fn(button) {
          if @sf.attach_from_sheet() {
            let (x, y, w, h) = button.placed_window_now()
            attach_open_from(At(x, y, w, h), src, draft)
          } else { pick_files(w) }
        }, tips?=tips) |> ignore
      },
      fn(p) {
        toolbar(p)
        match leaving_toolbar {
          Some(f) => {
            // The old choices leave on their own fade while the empty composer is already laid out as a capsule.
            // Keep their source room as a drawing over that new layout; the shared movement carries it with the box.
            let before = from["choices"]
            let box = from["box"]
            let fade = @sfbase.new_fade(@ui.current())
            // (the same choices' nodes as the page had them, drawn only: read out by nothing, a press going through to what
            // is under them, as the old frame's draw_only)
            p.over(Is(true)).width(Is(Some(before.2))).height(Is(Some(before.3)))
            .offset(Is((before.0 - box.0, before.1 - box.1)))
            .laid_nowhere(By(fn() { p.drawn_past(fade.ends()) })) |> ignore
            p.box(fn(row) {
              // (the fade as it was told (became_starts: new_fade_spec, to its declared end), where its spec puts it at the
              // moment each frame is drawn, as composer_hint_node's: what reads it painted again, nothing laid out)
              let ends = fade.ends()
              row.grow(Is(1.0)).presses(Is(false)).hides(Is(true)).alpha(By(fn() {
                let t = if row.drawn_past(ends) { ends } else { row.drawn_at() }
                1.0 - @sfbase.new_fade_spec().value_at(t - (ends - @sfbase.new_fade_ms), @sfbase.new_fade_ms, 0.0, 1.0, 0.0).0
              })) |> ignore
              f(row)
            }).grow(Is(1.0)) |> ignore
          }
          None => ()
        }
      },
      fn(p) {
        p.box(fn(t) {
          t.laid_nowhere(By(fn() { !opened() })) |> ignore
          t.show(opened, tail)
        }) |> ignore
        let note = composer_note_node(p, fn() { spec().note })
        let send = @sf.composer_send_node(p, ready, fn() { w.starting.get() }, submit, tips?=tips)
        // The chooser is made as the box opens; it has no visible place in the closed capsule to move from.
        // Only the note and send button survive both shapes and keep their positions through that change.
        [note, send]
      },
      ground=fn(read) { ground.val = read },
      from~, arrival=if flight_carried(draft) { @motion.tween(flight_desk_ms, ease=Flight) } else { @motion.move() },
      positions=fn(read) { positions.val = read },
      place_in?=place_in,
    )
    cap_at.val = Some(cap)
    cap.min_height(By(fn() { if held_box() > 0.0 { Some(held_box()) } else { None } }))
    .presses(By(fn() { !spec().locked }))
    .on_press(fn() { if !spec().locked { w.field.focus() } })
    .on_menu(fn(m) { if !spec().locked { w.field.edit_menu(m.wx, m.wy) } })
    .cursor(By(fn() { if spec().locked { None } else { Some(IBeam) } })) |> ignore
    root.show(fn() { w.error.get() != "" }, fn(p) {
      p.padding(Is((32.0, 4.0, 32.0, 10.0))) |> ignore
      p.box(fn(e) { e.words(By(fn() { w.error.get() })).words_look(By(fn() { @ui.style_words(composer_error_words) })).ink(By(fn() { @sf.theme().p.red })) |> ignore }) |> ignore
    })
    // Taking an answer is an effect, never a layout/property getter. The picker and host answers read by take_in
    // wake this effect; the editor receives its own files directly. Reusing the same business path preserves all
    // share-in, quotes, marked images, station files and optimistic write semantics.
    root.owns(@signals.effect(fn() {
      ignore(w.files.get())
      take_in(@ui.current(), src, spec(), w, no_files(), focus=fn() { w.field.focus() })
    })) |> ignore
    root.owns(@signals.effect(fn() {
      match @sfbase.outside_ask.get() {
        Some(s) if s.key == draft => {
          ignore(s.go.get())
          ignore(s.open.get())
          @signals.untracked(fn() {
            @sfbase.sharing_go(draft)
            outside_dialog(@ui.current(), src, draft)
          })
        }
        _ => ()
      }
    })) |> ignore
    root.owns(fn() { (release.val)() }) |> ignore
  })
  let cap = cap_at.val.unwrap()
  let field = field_at.val.unwrap()
  let w = w_at.val.unwrap()
  @ui.words_into_node(drops.unwrap_or(cap), field, when=fn() { active() && !spec().locked }, paths=fn(paths) {
    if spec().offline || !@sfbase.finder_by_station() { return false }
    writing_drop(src, w, spec().station, @sfbase.finder_dragged(src, paths).map(dropped_of), drops_as_files(src, draft))
    true
  })
  ref_keys.val = ref_menu_node(root, cap, field_at.val.unwrap(), src, spec, w_at.val.unwrap(), active)
  composer_keyboard_node(root, src, spec, w_at.val.unwrap(), field_at.val.unwrap(), active, neighbour)
  root.reacts(active, fn(on) {
    if on {
      composing.origin = Some({ old: false, roomy: spec().roomy, toolbar: spec().toolbar, toolbar_node: spec().toolbar_node, places: positions.val })
      composing.roomy = Some(spec().roomy)
    }
  })
  {
    root, cap, field: field_at.val.unwrap(), writing: w_at.val.unwrap(), opened, ground: ground.val,
    hold: fn() {
      // Capture once, before taking the draft. A landing can retime this hold; it still holds the box the words
      // left, not the emptied box or a new frame of its previous growth.
      let box = cap.placed_now().3 + (ground.val)().3
      fn(ms) { composer_hold(draft, 0.0, box, ms) }
    },
  }
}
