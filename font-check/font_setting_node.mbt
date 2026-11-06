// The fonts page, made in the window's tree. Its preferences and the files on this device are the core's; each
// choice is made once and follows them as they change.

///|
pub fn fonts_node(
  v : @view.View,
  core : Core,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  said? : (@sf.PageSaid) -> Unit,
  width? : () -> Double,
) -> Unit {
  let prefs = fn() { (core.topic)("prefs", Map::new()).value }
  let all = fn() { items(field(prefs(), "faces"), "list") }
  let files = fn() { (core.topic)("fonts", Map::new()).value }
  let place = fn() { @settings.font_places[@settings.fonts_at.get()] }
  let trying = @signals.signal("", same=fn(a, b) { a == b })
  let holding = @signals.signal(false, same=fn(a, b) { a == b })
  // The page's windowed list may let the preview block go while the faces remain in view. Its layout record belongs
  // to the page for that reason, and is cleared as soon as the hand leaves the faces, even between frames.
  let held_height = Ref(0.0)
  v.reacts(fn() { holding.get() }, fn(on) { if !on { held_height.val = 0.0 } })
  // Both topics belong to the page, even while its list is outside the windowed scroll's visible blocks. Ask for a
  // chosen face that is still coming here before a preview binding reads it: asking may change the core's live map.
  v.reacts(fn() { (prefs(), files()) }, fn(now) {
    let p = now.0
    let listed = items(field(p, "faces"), "list")
    for where_ in @settings.font_places {
      let id = font_chosen(p, where_)
      if id != "" && !(core.face_here)(id) {
        font_shown_in(core, listed, id) |> ignore
      }
    }
  })
  v.owns(fn() { trying.set("") }) |> ignore
  @sf.page_node(
    v,
    fn() { @sf.t("web-pages.appearance.fonts.title") },
    on_back~,
    frame~,
    said?,
    width?,
    lead=fn() { @sf.t("web-pages.appearance.fonts.description") },
    fn() { ["place", "preview", "faces"] },
    fn(b, key) {
      match key {
        "place" =>
          @sf.page_choice_node(
            b,
            fn() { @settings.font_places.map(fn(p) { @sf.t("web-pages.appearance.fonts." + p) }) },
            fn() { @settings.fonts_at.get() },
            fn(i) {
              if i >= 0 && i < @settings.font_places.length() {
                @settings.fonts_at.set(i)
              }
            },
          )
        "preview" => font_preview_node(b, core, prefs, all, place, trying, holding, held_height)
        _ => fonts_faces_node(b, core, prefs, all, files, place, trying, holding)
      }
    },
  )
}

///|
/// The sample conversation: a person's bubble, and an agent's name, time and formatted answer below it.
fn font_preview_node(
  parent : @view.View,
  core : Core,
  prefs : () -> Json?,
  all : () -> Array[Json],
  place : () -> String,
  trying : @signals.Signal[String],
  holding : @signals.Signal[Bool],
  held_height : Ref[Double],
) -> Unit {
  let faces = fn() {
    font_preview_faces(core, prefs(), all(), place(), trying.get(), fn(family) {
      if local_try_given.val == family { local_try_face } else { 0 }
    })
  }
  font_held_node(parent, holding, held_height, fn(room) { @sf.page_card_node(room, fn(card) {
    card.box(fn(col) {
      col.gap(Is(12.0)) |> ignore
      col.box(fn(line) {
        line.row(Is(true)).lies_along(Is(End)) |> ignore
        line.box(fn(clear) { clear.width_share(Is(fp_mine_clear_share / 100.0)) |> ignore }) |> ignore
        line.box(fn(bubble) {
          let inset = @sf.corner_inset - @sf.card_pad
          bubble
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          .margin(Is((0.0, inset, inset, 0.0)))
          .padding(Is((14.0, 10.0, 14.0, 10.0)))
          .radius(By(fn() { @ui.tree_theme().corner(Xl2) }))
          .ground(By(fn() { @ui.tree_theme().color(Bg) })) |> ignore
          font_words_node(
            bubble,
            fn() { @sf.t("web-pages.appearance.fonts.sampleMine") },
            fn() { @sf.body },
            fn() { faces().1 },
            words=fn() { faces().1 is None },
          ) |> ignore
        }) |> ignore
      }) |> ignore
      col.box(fn(agent) {
        agent.gap(Is(4.0)) |> ignore
        agent.box(fn(who) {
          who.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          let ui_face = fn() { let f = faces().0; if f == 0 { None } else { Some(f) } }
          font_words_node(who, fn() { "Claude" }, fn() { fp_who_words }, ui_face) |> ignore
          font_words_node(who, fn() { @sf.t("web-pages.appearance.fonts.sampleTime") }, fn() { fp_time_words }, ui_face) |> ignore
        }) |> ignore
        @sf.markdown_node(
          agent,
          fn() {
            @sf.t("web-pages.appearance.fonts.sampleText") + "\n\n" + fp_sample_code + "\n\n" + @sf.t("web-pages.appearance.fonts.sampleAfter")
          },
          size=fn() { body_size },
        ) |> ignore
      }) |> ignore
    }) |> ignore
  }) })
}

///|
/// The preview's layout keeps its own high-water height while the pointer is on the faces. It measures its child and
/// gives the held height to its holder in the same layout; no measured size is published as state for another layout.
fn font_held_node(
  parent : @view.View,
  holding : @signals.Signal[Bool],
  held_height : Ref[Double],
  body : (@view.View) -> Unit,
) -> Unit {
  parent.box(fn(room) {
    let child = room.box(body)
    room.layout_box(By(fn() { holding.get() }), fn(l, on) {
      let natural = l.measure(child, l.width).1
      if on && natural > held_height.val { held_height.val = natural }
      l.place(child, 0.0, 0.0)
      l.size_to(if on && held_height.val > natural { held_height.val } else { natural })
    }, sized=true) |> ignore
  }) |> ignore
}

///|
/// Words in a particular host face, or in the paragraph's face when none is named. A run's Some(0) explicitly uses
/// the app's face even when its paragraph is set in the person's text face.
fn font_words_node(
  parent : @view.View,
  text : () -> String,
  style : () -> @ui.TextStyle,
  face : () -> Int?,
  words? : () -> Bool = fn() { false },
  max_lines? : Int = 0,
) -> @view.View {
  parent.box(fn(w) {
    w
    .words_runs(By(fn() { let run = @view.words_run(text()); [{ ..run, face: face() }] }))
    .words_look(By(fn() { @ui.style_words(style()) }))
    .runs_look(By(fn() { { ..@view.runs_plain, words: words(), max_lines } }))
    .ink(By(fn() { @ui.style_ink(style()) })) |> ignore
  })
}

///|
/// The default and the faces for the selected place, in the core's order, with each row following its own state.
fn fonts_faces_node(
  parent : @view.View,
  core : Core,
  prefs : () -> Json?,
  all : () -> Array[Json],
  files : () -> Json?,
  place : () -> String,
  trying : @signals.Signal[String],
  holding : @signals.Signal[Bool],
) -> Unit {
  let chosen = fn() { font_chosen(prefs(), place()) }
  parent.box(fn(region) {
    // Points also covers the spaces between rows, without taking a press from any row or an overlay above the list.
    region.points(Is(true)) |> ignore
    region.reacts(fn() { @ui.pointing() is Mouse && region.pointed_in() }, fn(on) { holding.set(on) })
    region.owns(fn() { holding.set(false) }) |> ignore
    @sf.group_node(region, fn(g) {
    font_face_node(
      g,
      core,
      place,
      trying,
      fn() { "" },
      fn() { @sf.t(if place() == "text" { "web-pages.appearance.fonts.followUi" } else { "web-pages.appearance.fonts.default" }) },
      fn() { chosen() == "" },
      fn() { if place() == "code" { (core.own_code_face)() } else { 0 } },
      fn() { ("", false) },
    )
    let faces = fn() { all().filter(fn(f) { flag(Some(f), "mono") == (place() == "code") }) }
    g.each(faces, fn(f) { text(Some(f), "id") }, fn(slot, item) {
      let f = fn() { item.get() }
      let id = fn() { text(Some(f()), "id") }
      font_face_node(
        slot,
        core,
        place,
        trying,
        id,
        fn() { text(Some(f()), "name") },
        fn() { chosen() == id() },
        fn() {
          let own = if place() == "code" { (core.own_code_face)() } else { 0 }
          match font_shown_in(core, all(), id()) { 0 => own; preview => preview }
        },
        fn() { font_status(core, files(), items(files(), "kept"), f()) },
      )
    })
    g.show(fn() { @ui.local_font_families() != "" }, fn(slot) {
      let look = @sf.look_node(slot)
      @ui.old(slot, natural=true, unlaid=fn() { 64.0 }, fn(c) {
        @sf.with_look(look, fn() { local_face_row(c, core, place(), chosen()) })
      }) |> ignore
    })
    })
  }) |> ignore
}

///|
/// A face's choice: its name and sample, its download or error status, and the selected mark.
fn font_face_node(
  parent : @view.View,
  core : Core,
  place : () -> String,
  trying : @signals.Signal[String],
  id : () -> String,
  name : () -> String,
  chosen : () -> Bool,
  face : () -> Int,
  status : () -> (String, Bool),
) -> Unit {
  // Ask for the preview as the row is made. Its subsequent value is followed by the words below.
  @signals.untracked(face) |> ignore
  let row = @sf.choice_row_node(parent, name, chosen, fn() {
    let face = id()
    @settings.set_font(core, place(), if face == "" { None } else { Some(face) })
  }, body=fn(r) {
    r.box(fn(lines) {
      lines.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
      let shown = fn() { let f = face(); if f == 0 { None } else { Some(f) } }
      font_words_node(lines, name, fn() { face_name_words }, shown, max_lines=1) |> ignore
      font_words_node(lines, fn() { @sf.t("web-pages.appearance.fonts.sampleRow") }, fn() { face_sample_words }, shown, max_lines=1) |> ignore
    }) |> ignore
    r.show(fn() { status().0 != "" }, fn(s) {
      s.max_width(Is(Some(140.0))) |> ignore
      @sf.words_node(s, fn() { status().0 }, fn() { if status().1 { face_status_words.then(@sf.bad) } else { face_status_words } }) |> ignore
    })
  })
  let tried = fn() { let face = id(); if face == "" { "\u{1}" } else { face } }
  font_try_node(row, trying, tried)
}

///|
/// Try a row's face while the hand is on it, letting go only of this row's own try as the hand leaves or the row goes.
fn font_try_node(row : @view.View, trying : @signals.Signal[String], tried : () -> String) -> Unit {
  row.reacts(fn() { @sf.lit_in_node(row) }, fn(on) {
    let face = @signals.untracked(tried)
    if on {
      if face.has_prefix(local_prefix) {
        local_tried(face.unsafe_substring(start=local_prefix.length(), end=face.length())) |> ignore
      }
      trying.set(face)
    } else if @signals.untracked(fn() { trying.get() }) == face {
      trying.set("")
    }
  })
  row.owns(fn() {
    if @signals.untracked(fn() { trying.get() }) == @signals.untracked(tried) {
      trying.set("")
    }
  }) |> ignore
}

///|
/// The installed families in their host's order. The field finds a family, and the list caps its own height while
/// keeping its rows reachable by the hand, keyboard and accessibility actions.
fn font_local_list_node(
  parent : @view.View,
  core : Core,
  place : () -> String,
  chosen : () -> String,
  trying : @signals.Signal[String],
  close : () -> Unit,
) -> Unit {
  parent.box(fn(search) {
    search.padding(Is((0.0, 0.0, 0.0, 6.0))) |> ignore
    @sf.input_node(search, local_filter, placeholder_by=fn() { @sf.t("web-pages.appearance.fonts.searchLocal") }, small=true) |> ignore
  }) |> ignore
  let shown = fn() {
    let find = local_filter.text().trim(chars=" ").to_lower()
    let found = local_families().filter(fn(f) { find == "" || f.to_lower().contains(find) })
    if found.length() > local_most { found[:local_most].to_array() } else { found }
  }
  parent.show(fn() { shown().is_empty() }, fn(note) {
    note.padding(Is((10.0, 8.0, 10.0, 8.0))) |> ignore
    @sf.words_node(note, fn() { @sf.t("web-pages.appearance.fonts.noMatch") }, fn() { local_note }) |> ignore
  })
  let scroll = @view.Scroll::new()
  parent.box(fn(list) {
    list.max_height(Is(Some(local_list_most))).clips(Is(true)).bounds_input(Is(true)) |> ignore
    list.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(body) {
      body.each(shown, fn(f) { f }, fn(slot, item) {
        let family = fn() { item.get() }
        let selected = fn() { chosen() == local_prefix + family() }
        let row = slot.box(fn(r) {
          r
          .row(Is(true))
          .padding(Is((10.0, 0.0, 10.0, 0.0)))
          .gap(Is(8.0))
          .min_height(By(fn() { Some(@sf.theme().rows.pick) }))
          .lines_up(Is(Some(Middle)))
          .radius(By(fn() { @ui.tree_theme().corner(Inner) }))
          .ground(By(fn() { if selected() || @sf.lit_in_node(r) { @ui.tree_theme().color(Hover) } else { 0L } }))
          .says(By(fn() { Some(@view.said(Button, label=family(), selected=selected())) })) |> ignore
          @sf.presses_node(r, fn() {
            @settings.set_font(core, place(), Some(local_prefix + family()))
            close()
          })
          r.box(fn(label) {
            label.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            @sf.words_node(label, family, fn() { local_name }) |> ignore
          }) |> ignore
          r.show(selected, fn(mark) {
            @sf.icon_node(mark, "check", font_check, By(fn() { @sf.theme().p.text })) |> ignore
          })
        })
        font_try_node(row, trying, fn() { local_prefix + family() })
      })
    }) |> ignore
  }) |> ignore
}
