// The reader's layout (排版: Reader.tsx Layout) as nodes of the window's tree, laid over the reader where its panel is
// (reader.mbt's, an old view): the day's papers, the size with its keys, the lines and the margins on sliders, the
// face and the indent each a choice (seg_node), each changed as it is picked (the host's set_reader_style). While a
// reading's layout is open (layout_open, reader_panel_set): on 小屏 a sheet from the window's foot, half of it tall, on
// the page's own ground (sheet_node, as the reader's other panels are the host's sheets there); else docked at the
// window's right under the reader's bar, 320 wide, on its paper (the old panel's place, desk_panel's: the text kept
// clear of it as reader_column has it), its head the title and its close. It follows the tier as the window changes,
// as the old panel did; closed (Escape, its close, the sheet let go, gone back), it goes as the sheet goes, or at once.
// A reader in a tab beside a chat has the same docked panel in the tab's own stage (reader_layout_docked, laid by
// sfbase's viewer_tab_node), going and coming back with the tab.

///|
/// What of the reader the window's tree lays over it, in `root` (presented_nodes'): its layout's panel while one is
/// open, docked beside the text or a sheet on 小屏.
#callsite(autofill(loc))
fn reader_layout_nodes(root : @view.View, loc~ : SourceLoc) -> Unit {
  let small = fn() { layout(root.window().0) is Small }
  let open = fn() { layout_open.get() is Some(_) }
  // (the reading whose panel it is, as it opens)
  let reading = fn() { reading_for(layout_open.untracked().unwrap_or("")) }
  let close = fn(r : Reading) { fn() { reader_panel_set(r, NoPanel) } }
  // docked at the window's right, under the bar (desk_panel's place)
  root.show(fn() { open() && !small() }, fn(o) {
    let r = reading()
    // The reader can itself be inside the viewer's modal layer. Its panel must take input above that layer, while
    // presenters (whose serials start at 1) still open above the panel.
    o.over(Is(true)).stacked(Is(0)) |> ignore
    o.box(fn(top) { top.height(By(fn() { Some(viewer_bar_under()) })) |> ignore }) |> ignore
    reader_layout_docked(o, close(r))
  })
  // a sheet from the window's foot on 小屏, half of it tall, its title as the host's reader sheet heads it
  let x : PanelOf = {
    title: t("web-pages.drive.reader.layout"),
    description: "",
    body: fn(_, _) {  },
    foot: None,
    w: panel_w,
    fits: false,
    wide: false,
    live: None,
    tall: narrow_sheet_half,
    grows: false,
    focus: true,
    ruled: false,
    lists: false,
    fade_out_together: false,
    form: false,
    field: "",
    stage: false,
    above: None,
    title_row: None,
    heads_itself: true,
    side: Bottom,
    along: Start,
    offset: panel_offset,
    match_panel: 0,
    steps: false,
    on_back: None,
    nodes: Some({
      body: fn(col, _) {
        col.box(fn(head) {
          style_node(head, fn() { layout_sheet_head })
          // (its words' own line, as the host's sheet sets its title: dv_sheet_frame's, no line of the size's)
          head.box(fn(w) {
            w
            .words(By(fn() { t("web-pages.drive.reader.layout") }))
            .words_look(By(fn() { { ..@ui.style_words(sheet_title_words), line: -@ui.tree_theme().text_line } }))
            .ink(By(fn() { @ui.style_ink(sheet_title_words) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
        layout_body(col, true, sheet_paper)
      },
      foot: None,
      hugs: false,
    }),
  }
  let shut = fn() {
    match layout_open.untracked() {
      Some(k) => reader_panel_set(reading_for(k), NoPanel)
      None => ()
    }
  }
  root.box(made_for=loc, fn(layer) {
    layer.over(Is(true)).stacked(Is(0)) |> ignore
    sheet_node(
      layer,
      "sf-reader-layout",
      fn() { open() && small() },
      fn() { [{ n: 0, x, nodes: x.nodes, close: shut, from: Unanchored, lists: -1 }] },
      shut,
    )
  })
  |> ignore
}

///|
/// The layout's panel docked at the right of `parent` (a column), from where it is to its foot: the text's room, then
/// the panel 320 wide on the reader's paper (desk_panel's box), its head the title and its close (`close`), its controls
/// (layout_body). `fits`: no wider than `parent` where that is less (a tab's stage beside a chat: viewer_tab_node's).
#callsite(autofill(loc))
pub fn reader_layout_docked(parent : @view.View, close : () -> Unit, fits? : Bool = false, loc~ : SourceLoc) -> Unit {
  let paper = fn() { reader_paper((viewer_host().reader_style)().paper) }
  parent.box(made_for=loc, fn(row) {
    style_node(row, fn() { desk_panel_row })
    row.box(fn(room) { style_node(room, fn() { desk_panel_room }, in_row=true) }) |> ignore
    row.box(fn(p) {
      style_node(p, fn() { desk_panel_box.then(@ui.style(bg=Data(paper().ground))) }, in_row=true)
      if fits {
        p.shrink(Is(1.0)).min_width(Is(Some(0.0))).clips(Is(true)) |> ignore
      }
      // (a press on it its own: not the text's under it)
      ground_node(p) |> ignore
      p.box(fn(head) {
        style_node(head, fn() { desk_panel_head })
        words_node(head, fn() { t("web-pages.drive.reader.layout") }, fn() {
          desk_panel_title.then(@ui.text_style(color=Data(paper().ink)))
        })
        |> ignore
        head.box(fn(g) { style_node(g, fn() { desk_grow }, in_row=true) }) |> ignore
        chip_node(head, fn() { "" }, close, icon="close", ink=fn() { paper().ink }, said=fn() { t("common.close") })
        |> ignore
      })
      |> ignore
      layout_body(p, false, paper)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The layout's controls in `col` (desk_layout's as it was): in the panel's 280 (320 less 20 either side), or a sheet's
/// width less 20 either side (`narrow`, the face and the indent side by side there); on paper `p`.
#callsite(autofill(loc))
fn layout_body(col : @view.View, narrow : Bool, p : () -> ReaderPaper, loc~ : SourceLoc) -> Unit {
  let style = fn() { (viewer_host().reader_style)() }
  let set = fn(change : ReaderStyleChange) { (viewer_host().set_reader_style)(change) }
  let inner = fn() { if narrow { dmax(desk_none, col.window().0 - 2.0 * desk_layout_in) } else { desk_layout_inner } }
  let swatch = fn() { (inner() - desk_papers_gaps) / desk_papers_row }
  let half = fn() { (inner() - desk_pair_gap) / 2.0 }
  // (each option at least half its half less its track's room, a sheet's; the panel's 138: made again as that changes)
  let seg_item = fn() { if narrow { (half() - desk_seg_track) / 2.0 } else { desk_seg_item } }
  let label = fn(parent : @view.View, key : String) {
    words_node(parent, fn() { t(key) }, fn() { desk_layout_label.then(@ui.text_style(color=Data(p().muted))) }) |> ignore
  }
  col.box(made_for=loc, fn(b) {
    style_node(b, fn() { desk_layout_box })
    // the day's papers; night is the app's dark (外观), never picked here
    b.box(fn(k) {
      style_node(k, fn() { desk_layout_block })
      label(k, "web-pages.drive.reader.paper")
      k.box(fn(row) {
        style_node(row, fn() { desk_papers })
        let shown = fn() { if theme().dark { "night" } else { day_paper_key(style().paper) } }
        for key in ["white", "green", "grey"] {
          layout_swatch(row, key, fn() { shown() == key }, p, swatch, fn() { set(Paper(key)) })
        }
      })
      |> ignore
    })
    |> ignore
    b.box(fn(k) {
      style_node(k, fn() { desk_layout_block })
      label(k, "web-pages.drive.reader.size")
      k.box(fn(row) {
        style_node(row, fn() { desk_size_row.then(@ui.style(bg=Data(alpha(p().ink, desk_size_ground)))) }, in_row=false)
        let (least, most) = reader_sizes
        let word = fn() { t("web-pages.drive.reader.size") }
        let now = fn() { @signals.untracked(style).size }
        layout_size_key(row, "A−", fn() { style().size > least }, p, fn() {
          t("web-pages.drive.reader.less", args=[("what", word())])
        }, fn() { set(Size(now() - 1)) })
        row.box(fn(m) {
          style_node(m, fn() { desk_grow_middle }, in_row=true)
          words_node(m, fn() { "\{style().size}" }, fn() { desk_size_value.then(@ui.text_style(color=Data(p().ink))) })
          |> ignore
        })
        |> ignore
        layout_size_key(row, "A+", fn() { style().size < most }, p, fn() {
          t("web-pages.drive.reader.more", args=[("what", word())])
        }, fn() { set(Size(now() + 1)) })
      })
      |> ignore
    })
    |> ignore
    // (the sliders' names in a column as wide as the wider of them in this language, 48 at least: words of a length
    // known, whole)
    let names = ["web-pages.drive.reader.lines", "web-pages.drive.reader.margin"]
    let label_w = fn() {
      b.words_redone() |> ignore
      let size = node_sp(b, @ui.style_words(desk_layout_label).size)
      names.fold(init=desk_slider_label_w, fn(m, k) { dmax(m, node_words_w(t(k), size).ceil()) })
    }
    let (lines_least, lines_most) = reader_lines
    // (kept as the pointer lets it go, or a key steps it)
    layout_slider_row(b, names[0], label_w, fn() { style().line }, lines_least, lines_most, desk_lines_step, p, fn(v) {
      "\{(v * 100.0).round().to_int()}%"
    }, fn(v) { set(Line(v)) })
    let (margin_least, margin_most) = reader_margins
    layout_slider_row(
      b,
      names[1],
      label_w,
      fn() { style().margin.to_double() },
      margin_least.to_double(),
      margin_most.to_double(),
      desk_margin_step,
      p,
      fn(v) { "\{v.round().to_int()}" },
      fn(v) { set(Margin(v.round().to_int())) },
    )
    b.box(fn(pair) {
      style_node(pair, fn() { if narrow { desk_layout_pair } else { desk_layout_column } })
      let half_style = fn() { if narrow { desk_layout_half.then(@ui.style(w=Fixed(half()))) } else { desk_layout_block } }
      pair.box(fn(k) {
        style_node(k, half_style, in_row=narrow)
        label(k, "web-pages.drive.reader.face")
        k.pick(seg_item, fn(v, item_w) {
          seg_node(
            v,
            fn() { [t("web-pages.drive.reader.serif"), t("web-pages.drive.reader.sans")] },
            fn() { if style().face == "serif" { 0 } else { 1 } },
            fn(i) {
              let want = if i == 0 { "serif" } else { "sans" }
              if want != @signals.untracked(style).face {
                set(Face(want))
              }
            },
            item_w~,
          )
          |> ignore
        })
      })
      |> ignore
      pair.box(fn(k) {
        style_node(k, half_style, in_row=narrow)
        label(k, "web-pages.drive.reader.indentLabel")
        k.pick(seg_item, fn(v, item_w) {
          seg_node(
            v,
            fn() { [t("web-pages.drive.reader.indent"), t("web-pages.drive.reader.flush")] },
            fn() { if style().indent { 0 } else { 1 } },
            fn(i) {
              if (i == 0) != @signals.untracked(style).indent {
                set(Indent(i == 0))
              }
            },
            item_w~,
          )
          |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// One paper in `row`, drawn in itself (desk_swatch's): 文 on its ground, ringed in the accent when it is the one (`on`),
/// its name under it, `w()` wide; `press` as it is pressed.
#callsite(autofill(loc))
fn layout_swatch(
  row : @view.View,
  key : String,
  on : () -> Bool,
  p : () -> ReaderPaper,
  w : () -> Double,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  // (each as it is by day, whatever the app's theme)
  let paper = paper_by_key(key)
  let glyph = fn() { t("web-pages.drive.reader.paperGlyph") }
  let name = fn() { t("web-pages.drive.reader.paper." + key) }
  row.box(made_for=loc, fn(s) {
    style_node(s, fn() { desk_swatch_box.then(@ui.style(w=Fixed(w()))) }, in_row=true)
    presses_node(s, press)
    s.says(By(fn() { Some(@view.said(Button, label=glyph() + " " + name())) })) |> ignore
    s.box(fn(g) {
      // (its ring desk_swatch_on's B2 in the accent where it is on, desk_swatch_off's B1 in the page's ink, faint)
      style_node(g, fn() {
        (if on() { desk_swatch_on } else { desk_swatch_off }).then(
          @ui.style(bg=Data(paper.ground), border_color=Data(if on() { p().accent } else { alpha(p().ink, desk_swatch_line) })),
        )
      })
      g.box(fn(m) {
        m
        .words_runs(By(fn() { [@ui.span(glyph(), serif=true)] }))
        .words_look(By(fn() { @ui.style_words(desk_swatch_glyph) }))
        .ink(Is(paper.ink))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    words_node(s, name, fn() { desk_swatch_name.then(@ui.text_style(color=Data(p().muted))) }) |> ignore
  })
  |> ignore
}

///|
/// A size's key in `row` (desk_size_key's): A− or A+, 32 high, 44 wide at least, quiet where it can go no further (not
/// `on`), the tint under the hand; read out a button named `said`, `press` as it is pressed.
#callsite(autofill(loc))
fn layout_size_key(
  row : @view.View,
  words : String,
  on : () -> Bool,
  p : () -> ReaderPaper,
  said : () -> String,
  press : () -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  row.box(made_for=loc, fn(k) {
    style_node(k, fn() { desk_size_key_box })
    k
    .alpha(By(fn() { if on() { desk_whole } else { desk_size_key_off } }))
    .radius(By(desk_size_key_corner))
    .ground(By(fn() { if on() && lit_node(k) { @ui.tree_theme().color(Tint) } else { no_ground } }))
    .says(By(fn() { Some(@view.said(Button, label=said())) }))
    |> ignore
    presses_node(k, on~, press)
    words_node(k, fn() { words }, fn() { desk_size_key_words.then(@ui.text_style(color=Data(p().ink))) }) |> ignore
  })
  |> ignore
}

///|
/// How a size's key that can go no further shows (desk_size_key_box's disabled{opacity=O35}).
let desk_size_key_off : Double = 0.35

///|
/// A setting along a hairline with a knob in `parent` (desk_slider_row's): its name (`label_w()` wide), the line, its
/// value as `shown` says; dragged or tapped, the value follows, and is kept (`keep`) as the pointer lets go there, or a
/// key steps it.
#callsite(autofill(loc))
fn layout_slider_row(
  parent : @view.View,
  name_key : String,
  label_w : () -> Double,
  value : () -> Double,
  min : Double,
  max : Double,
  step : Double,
  p : () -> ReaderPaper,
  shown : (Double) -> String,
  keep : (Double) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let name = fn() { t(name_key) }
  parent.box(made_for=loc, fn(row) {
    style_node(row, fn() { desk_slider_box })
    // (held: where it is drawn, a draft; let go: kept, the draft let go with it)
    let draft : @signals.Signal[Double?] = @signals.signal(None)
    let now = fn() { draft.get().unwrap_or(value()) }
    row.box(fn(l) {
      l.width(By(fn() { Some(label_w()) })) |> ignore
      words_node(l, name, fn() { desk_layout_label.then(@ui.text_style(color=Data(p().muted))) }) |> ignore
    })
    |> ignore
    row.box(fn(g) {
      style_node(g, fn() { desk_grow }, in_row=true)
      slider_node(g, name, now, min, max, step, p, fn(v) { draft.set(Some(v)) }, fn(v) {
        draft.set(None)
        if v != @signals.untracked(value) {
          keep(v)
        }
      })
    })
    |> ignore
    row.box(fn(v) {
      style_node(v, fn() { desk_slider_value_box })
      words_node(v, fn() { shown(now()) }, fn() { desk_slider_value.then(@ui.text_style(color=Data(p().ink))) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A slider in `parent` as nodes (the library's slider, @kit.slider's in still.fail's look: slider_look_of's): a line
/// 2 high on 16% of the ink, the part up to the knob in the accent, the knob 22 across in it ringed 3 in the paper's
/// ground (4 more while held), 28 high; its knob's middle from half a knob in to as far from the end. At `now()`
/// between `min` and `max`, on steps of `step`. Held and dragged along (a press first jumping it there), `moved` told
/// the value under the hand at each step, `let_go` the value as it is let go; with the keyboard's focus on it the arrows
/// a step (→ and ↑ more), Page Up and Down ten, Home and End its ends, and a screen reader's step, each `moved` and
/// let go at once. Read out a slider named `label`, its value as @kit.slider says it.
#callsite(autofill(loc))
fn slider_node(
  parent : @view.View,
  label : () -> String,
  now : () -> Double,
  min : Double,
  max : Double,
  step : Double,
  p : () -> ReaderPaper,
  moved : (Double) -> Unit,
  let_go : (Double) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  let span = if max > min { max - min } else { 1.0 }
  let at = fn() { dmin(desk_whole, dmax(desk_none, (now() - min) / span)) }
  let held = @signals.signal(false)
  let snap = fn(v : Double) { @kit.snap(v, min, max, step) }
  let along = fn(d : @view.Drag) {
    if d.w > slider_thumb_room {
      moved(snap(min + dmin(desk_whole, dmax(desk_none, (d.x - slider_thumb_room / 2.0) / (d.w - slider_thumb_room))) * span))
    }
  }
  let stepped = fn(v : Double) {
    let v = snap(v)
    moved(v)
    let_go(v)
  }
  parent.box(made_for=loc, fn(s) {
    s
    .height(Is(Some(slider_thumb_d + slider_room)))
    .lies_along(Is(Middle))
    .focusable(Is(true))
    .presses(Is(true))
    .says(By(fn() {
      let v = now()
      let said = if step >= 1.0 && step.floor() == step { v.to_int().to_string() } else { v.to_string() }
      Some(@view.said(Slider, label=label(), value=said, range=(min, v, max), actions=[Increment, Decrement]))
    }))
    .on_step(fn(by) { stepped(@signals.untracked(now) + by.to_double() * step) })
    .on_drag(fn(d) {
      match d.kind {
        Down => {
          // (the keyboard's focus taken as it is pressed, not shown: @kit.slider's focus_on_press)
          s.ask_focus() |> ignore
          held.set(true)
          along(d)
        }
        Moved => along(d)
        Up => {
          along(d)
          held.set(false)
          let_go(@signals.untracked(now))
        }
        Off => {
          held.set(false)
          let_go(@signals.untracked(now))
        }
      }
    })
    .on_key(fn(k) {
      if !s.focused() || k.mods != 0 {
        return false
      }
      let v = @signals.untracked(now)
      let to = if k.code == @ui.key_code_right || k.code == @ui.key_code_up {
        Some(v + step)
      } else if k.code == @ui.key_code_left || k.code == @ui.key_code_down {
        Some(v - step)
      } else if k.code == @ui.key_code_page_up {
        Some(v + step * 10.0)
      } else if k.code == @ui.key_code_page_down {
        Some(v - step * 10.0)
      } else if k.code == @ui.key_code_home {
        Some(min)
      } else if k.code == @ui.key_code_end {
        Some(max)
      } else {
        None
      }
      match to {
        Some(x) => {
          stepped(x)
          true
        }
        None => false
      }
    })
    |> ignore
    // its line: the accent up to the knob, the ink at 16% after it
    s.box(fn(line) {
      line
      .row(Is(true))
      .height(Is(Some(slider_track_h)))
      .margin(Is((slider_thumb_d / 2.0, 0.0, slider_thumb_d / 2.0, 0.0)))
      |> ignore
      line.box(fn(f) {
        f.grow(By(at)).basis(Is(Some(0.0))).ground(By(fn() { p().accent })) |> ignore
      })
      |> ignore
      line.box(fn(f) {
        f.grow(By(fn() { desk_whole - at() })).basis(Is(Some(0.0))).ground(By(fn() { alpha(p().ink, slider_rest) })) |> ignore
      })
      |> ignore
    })
    |> ignore
    // its knob, over the line where the value is along it
    s.box(fn(o) {
      o.over(Is(true)).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      o.box(fn(b) { b.grow(By(at)).basis(Is(Some(0.0))) |> ignore }) |> ignore
      o.box(fn(k) {
        k.width(Is(Some(slider_thumb_d))).height(Is(Some(slider_thumb_d))).lines_up(Is(Some(Middle))).lies_along(Is(Middle))
        |> ignore
        let side = fn() { if held.get() { slider_thumb_d + slider_held_more } else { slider_thumb_d } }
        k.box(fn(dot) {
          dot
          .width(By(fn() { Some(side()) }))
          .height(By(fn() { Some(side()) }))
          .radius(By(fn() { side() / 2.0 }))
          .ground(By(fn() { p().accent }))
          .edge(By(fn() { (slider_ring, p().ground) }))
          |> ignore
        })
        |> ignore
        // (the keyboard's focus on it: a ring round the knob, its gap and width the theme's: focus_ring's)
        k.show(fn() { s.focus_shown() }, fn(ring) {
          let out = fn() {
            let t = @ui.tree_theme()
            t.focus_gap + t.focus_w
          }
          ring
          .over(Is(true))
          .margin(By(fn() { (-out(), -out(), -out(), -out()) }))
          .radius(By(fn() { slider_thumb_d / 2.0 + out() }))
          .edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) }))
          |> ignore
        })
      })
      |> ignore
      o.box(fn(b) { b.grow(By(fn() { desk_whole - at() })).basis(Is(Some(0.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The slider's sizes (@kit.slider_look_of's): the knob 22 across, 6 more of room round it, 4 more while held, its ring
/// 3; the line 2 high, the ink at 16% after the knob; how much of its width the knob's middle does not run along
/// (@kit.slider's thumb_room).
let slider_thumb_d : Double = 22.0

///|
let slider_room : Double = 6.0

///|
let slider_held_more : Double = 4.0

///|
let slider_ring : Double = 3.0

///|
let slider_track_h : Double = 2.0

///|
let slider_rest : Double = 0.16

///|
let slider_thumb_room : Double = 22.0

///|
/// The layout's sheet's title's row (the host's reader sheet's, dv_sheet_frame: 18 in, 4 over, 10 under).
// kept across runs: a value (no field of it changes)
let layout_sheet_head : @ui.Style = @ui.css("row w=Full px=S4_5 pt=S1 pb=S2_5 align=ACenter")
