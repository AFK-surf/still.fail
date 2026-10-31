// Marking's tools as nodes of the window's tree (marks_foot's MarksTools, ImageMarks.kt): the tools, the colour and
// its palette, the picked one's removal, undo and redo, each done at the moment it is pressed (its press let go on
// it), as the picture's own drawing is (Viewer::finger_on): the tool a stroke is drawn with the one taken up, whatever
// frames came between. The note being written too (note_box_node): its pin and what it is, 删除 and 完成 nodes, done as
// their press is let go; what is written in it an old view's field, the note as tall as it lays out. The notes' cards
// over the tools are the old view's still (marks_foot).

///|
/// How a marking tool is drawn (picture_button's, in the viewer's dark): its icon in the quieter white, near white on
/// white at 16% while it is the tool in use; no ground of its own besides.
fn marks_ink() -> @sf.ViewerInk {
  { ground: 0x000000FFL, ink: dark_text, muted: dark_muted, line: 0L, hover: 0L, chosen: 0xFFFFFF29L }
}

///|
/// Marking's foot in `h` (a layer over the viewer's, all of it), as marks_foot lays it out, one column: the notes
/// (the old view's, marks_foot with no tools: the cards, or the note being written) as far down as what is under them
/// lets them; under them, while no note is written, the colours' row while asked for over the row of tools on dark
/// glass (选择, 框, 箭头, 画笔, 文字 · the colour · 删除 the picked · 撤销, 重做), each a picture_button's 32, in its
/// middle, 8 over `foot` (the navigation bar's room) at the bottom. Each as marking says as it changes; each pressed
/// (its press let go on it), done then. Their tips in a layer of their own over all of it.
fn marks_foot_node(h : @view.View, foot : () -> Double) -> Unit {
  h.over(Is(true)) |> ignore
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  h.box(fn(col) {
    col.over(Is(true)).padding(By(fn() { (0.0, 0.0, 0.0, foot()) })) |> ignore
    // (the notes, the old view's: down to the tools, as far as it holds them)
    // (taking a press only where it has something to press: the rest the picture's)
    @ui.old(col, fn(c) {
      // (marking as it is: built again as it changes, as image_bars' was)
      marks_said()
      c.spacer()
      marks_foot(c, tools=false, note=false)
    })
    .grow(Is(1.0))
    |> @ui.old_takes_own
    |> ignore
    // (the note being written, over the tools' room: note_box_node)
    col.show(
      fn() {
        marks_said()
        marks_note_shown() is Some(_)
      },
      fn(n) { note_box_node(n) },
    )
    col.show(
      fn() {
        marks_said()
        marking.note < 0
      },
      fn(t) { marks_tools_node(t, tips) },
    )
  })
  |> ignore
  tips_at.val = Some(h.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// The colours' row while asked for over the row of tools, in `col`'s middle, 12 between, 8 under them.
fn marks_tools_node(col : @view.View, tips : @sf.TipLayer) -> Unit {
  let ink = marks_ink
  let round : @view.Live[Double] = Is(picture_key)
  let glass = fn() { Some(dark_glass()) }
  col.lines_up(Is(Some(Middle))).gap(Is(12.0)).padding(Is((0.0, 0.0, 0.0, 8.0))) |> ignore
  col.show(
    fn() {
      marks_said()
      marking.palette
    },
    fn(row) {
      row
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .padding(Is((4.0, 4.0, 4.0, 4.0)))
      .gap(Is(2.0))
      .radius(Is(20.0))
      .glass(By(glass))
      |> ignore
      for col_ in mark_colors {
        let color = col_.0
        row.box(fn(b) {
          b
          .width(Is(Some(32.0)))
          .height(Is(Some(32.0)))
          .radius(Is(16.0))
          .lines_up(Is(Some(Middle)))
          .ground(By(fn() {
            marks_said()
            if color == marks_shown_color() {
              0xFFFFFF29L
            } else {
              0L
            }
          }))
          .presses(Is(true))
          .on_press(fn() { marks_pick_color(color) })
          |> ignore
          swatch_node(b, fn() { color })
        })
        |> ignore
      }
    },
  )
  col.box(fn(row) {
    row
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .height(Is(Some(44.0)))
    .padding(Is((6.0, 0.0, 6.0, 0.0)))
    .gap(Is(2.0))
    .radius(Is(picture_bar_corner))
    .glass(By(glass))
    |> ignore
    for x in [(Select, "cursor", "select"), (Rect, "square", "rect"), (Arrow, "arrow-up-right", "arrow"), (Pen, "scribble", "pen"), (Words, "text", "text")] {
      let (tool, icon, name) = x
      @sf.tool_node(
        row,
        fn() {
          marks_said()
          { icon, label: pv("android-chat.marks.tool." + name), on: marking.tool == tool, disabled: false }
        },
        ink,
        round,
        fn() {
          marks_put_down(@ui.current())
          marking.note = -1
          marking.tool = tool
          if tool != Select {
            marking.picked = -1
          }
          marks_changed()
        },
        tip=tips,
        lights=false,
        ripples=true,
      )
      |> ignore
    }
    gap_node(row)
    // the colour, its palette asked for or put away
    row.box(fn(b) {
      b
      .width(Is(Some(32.0)))
      .height(Is(Some(32.0)))
      .radius(Is(picture_key))
      .lines_up(Is(Some(Middle)))
      .presses(Is(true))
      .says(Is(Some(@view.said(Button, label=pv("android-chat.marks.color")))))
      .on_press(fn() {
        marking.palette = !marking.palette
        marks_changed()
      })
      |> ignore
      swatch_node(b, fn() {
        marks_said()
        marks_shown_color()
      })
      @sf.tip_node(tips, b, fn() { pv("android-chat.marks.color") }) |> ignore
    })
    |> ignore
    row.show(
      fn() {
        marks_said()
        marking.picked >= 0
      },
      fn(r) {
        @sf.tool_node(
          r,
          fn() { { icon: "trash", label: pv("common.delete"), on: false, disabled: false } },
          ink,
          round,
          fn() {
            if marking.picked >= 0 {
              marks_remove(marking.picked)
            }
          },
          tip=tips,
          lights=false,
          ripples=true,
        )
        |> ignore
      },
    )
    gap_node(row)
    @sf.tool_node(
      row,
      fn() {
        marks_said()
        { icon: "retry", label: pv("android-chat.marks.undo"), on: false, disabled: marking.past.length() == 0 }
      },
      ink,
      round,
      fn() { marks_undo() },
      tip=tips,
      lights=false,
      ripples=true,
    )
    |> ignore
    @sf.tool_node(
      row,
      fn() {
        marks_said()
        { icon: "redo", label: pv("android-chat.marks.redo"), on: false, disabled: marking.future.length() == 0 }
      },
      ink,
      round,
      fn() { marks_redo() },
      tip=tips,
      lights=false,
      ripples=true,
    )
    |> ignore
  })
  |> ignore
}

///|
/// Between the tools' groups (mark_gap's): a line 1 by 18, white at 10%, 4 either side.
fn gap_node(row : @view.View) -> Unit {
  row.box(fn(g) {
    g.padding(Is((4.0, 0.0, 4.0, 0.0))) |> ignore
    g.box(fn(l) { l.width(Is(Some(1.0))).height(Is(Some(18.0))).ground(Is(0xFFFFFF1AL)) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// A colour's swatch in `b`'s middle (mark_swatch's): a disc of it 16 across, ringed 1.5 inside its edge in white at
/// 50% (the ring the white over what is under it, as the old box's edge is: its ground within its edge; the disc
/// within it the colour).
fn swatch_node(b : @view.View, color : () -> Int64) -> Unit {
  b.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  b.box(fn(ring) {
    ring
    .width(Is(Some(16.0)))
    .height(Is(Some(16.0)))
    .radius(Is(8.0))
    .padding(Is((1.5, 1.5, 1.5, 1.5)))
    .ground(Is(0xFFFFFF80L))
    |> ignore
    ring.box(fn(d) { d.grow(Is(1.0)).radius(Is(6.5)).ground(By(color)) |> ignore }) |> ignore
  })
  |> ignore
  b.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
}

///|
/// Marking's actions in the bar across the top of viewer `vw` (marks_actions_node, as vf_tools has marks_actions there):
/// as marking says as it changes; 取消 leaves marking, 下载 makes the marked picture to keep, 添加到对话 (where there is
/// a chat's draft) to put in it, each at the moment its press is let go (Viewer::finish_marks).
fn marks_actions_node_of(row : @view.View, vw : Viewer, ink : () -> @sf.ViewerInk, tips : @sf.TipLayer) -> Unit {
  @sf.marks_actions_node(
    row,
    fn() {
      marks_said()
      {
        error: marking.error,
        ready: !marking.busy && marks_any(),
        busy: marking.busy,
        can_put: vw.draft_key() != "",
        cancel: pv("common.cancel"),
        download: pv("android-chat.marks.downloadMarked"),
        put: pv("android-chat.preview.put"),
        making: pv("android-chat.marks.making"),
      }
    },
    ink,
    // (round as marking's own actions are, picture_key: not as the bar's tools at the window's corner)
    Is(picture_key),
    fn() { marks_leave() },
    fn() { vw.finish_marks(@ui.current(), false) },
    fn() { vw.finish_marks(@ui.current(), true) },
    tip=tips,
  )
  |> ignore
}

///|
/// The note being written, as marking says (marks_foot's: none, a note asked for of no numbered mark).
fn marks_note_shown() -> (Int, Int, String, Int64)? {
  if marking.note < 0 {
    return None
  }
  mark_notes().iter().find_first(fn(x) { x.0 == marking.note })
}

///|
/// The note being written in `w` (note_box's, Notes.kt NoteBox, in the dark), 12 in at its sides and 8 over the
/// navigation bar: a frosted card (26 round, its round buttons' room in from its sides and foot, 10 over, 6 between),
/// its pin and what it is, muted; then 删除批注 (a bin, 36 round), the field (16 on 21, 添加批注（可选） till something
/// is written, 8 lines at most: an old view's, the card as tall as it lays out), 完成 (a tick on the ink, 36 round), at
/// their row's foot. Coming in from nothing and 97% of its size about its middle (note_pop_ms, ease out) as a note is
/// asked for, from that moment, and again as another is. 删除 and 完成 done as their press is let go on them.
fn note_box_node(w : @view.View) -> Unit {
  let keys_in = @sf.capsule_in(note_box_corner, 36.0)
  let pop = NotePop::new()
  w.padding(Is((12.0, 0.0, 12.0, 8.0))) |> ignore
  w.box(fn(b) {
    // (its coming in, from the moment the note was asked for: another asked for, from then again)
    b.reacts(
      fn() {
        marks_said()
        marking.note
      },
      fn(id) {
        if id >= 0 {
          pop.again(b)
        }
      },
    )
    b.owns(fn() { (pop.due)() }) |> ignore
    let shown = fn() { pop.shown(b) }
    b
    .padding(Is((keys_in, 10.0, keys_in, keys_in)))
    .gap(Is(6.0))
    .radius(Is(note_box_corner))
    .ground(Is(note_ground))
    .shadow(Is((@sf.floating.sigma, @sf.floating.dy, @sf.floating.color)))
    .alpha(By(shown))
    .scale(By(fn() { 0.97 + 0.03 * shown() }))
    |> ignore
    // its pin and what it is
    b.box(fn(head) {
      head
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .padding(Is((@ui.Space::px(S2), 0.0, @ui.Space::px(S2), 0.0)))
      .gap(Is(@ui.Space::px(S1_5)))
      |> ignore
      note_pin_node(head, fn() {
        match marks_note_shown() {
          Some((_, n, _, color)) => (n, color)
          None => (0, 0L)
        }
      })
      head.box(fn(t) {
        t
        .words(By(fn() {
          marks_said()
          match marks_note_shown() {
            Some((_, _, what, _)) => what
            None => ""
          }
        }))
        .words_look(By(fn() {
          let (size, _) = @ui.tree_theme().text_size(Meta)
          { size, weight: 400, line: 18.0, wrap: false }
        }))
        .ink(Is(note_muted))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    b.box(fn(row) {
      row.row(Is(true)).lines_up(Is(Some(End))).gap(Is(@ui.Space::px(S0_5))) |> ignore
      // 删除批注
      note_key_node(row, "trash", 17.0, 0L, note_muted, pv("android-chat.annotate.remove"), fn() {
        let id = marking.note
        if id >= 0 {
          marking.note = -1
          marks_remove(id)
          @ui.current().blur()
        }
      })
      // the field, an old view's: as tall as it lays out (at least as a key is, its words in its middle)
      row.box(fn(f) {
        // (the room its row leaves between its keys, as note_box's Fill: none of its own before it is shared out, giving
        // way as they do)
        f.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).padding(Is((8.0, 7.0, 8.0, 7.0))) |> ignore
        @ui.old(f, fn(c) {
          c.box(w=Fill(1.0), h=Fill(1.0), justify=JCenter, fn() {
            c.editor(
              "marks/note",
              placeholder=pv("android-chat.annotate.write"),
              font_size=16.0,
              line=21.0,
              max_lines=8,
              plain=true,
              color=note_ink,
              placeholder_color=note_subtle,
              caret_color=note_accent,
              enter_sends=false,
              field=marking.note_field,
            )
            |> ignore
          })
          |> ignore
        })
        .grow(Is(1.0))
        .measured(By(fn() { marking.note_field.laid(font_size=16.0, line=21.0, max_lines=8) }), fn(l, w) {
          let (lw, lh) = l.size(w)
          // (as tall as a key at least, its 7 over and under round it: the old box's min_h)
          (lw, if lh > 36.0 - 14.0 { lh } else { 36.0 - 14.0 })
        })
        |> ignore
      })
      |> ignore
      // 完成
      note_key_node(row, "check", 18.0, note_ink, note_bg, pv("android-chat.annotate.done"), fn() {
        marks_note_done(@ui.current())
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far a note's box has come in (note_box_node's): its way, from nothing to all of it over note_pop_ms, and the
/// moment it is all there (a moment of its node's: what reads it told then, the clock read no more), let go as it
/// comes in again and as the node is.
priv struct NotePop {
  way : @motion.Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
}

///|
fn NotePop::new() -> NotePop {
  { way: @motion.Way::new(0.0), ended: @signals.signal(0), due: fn() {  } }
}

///|
/// Coming in anew from nothing, from `n`'s cause's moment.
fn NotePop::again(self : NotePop, n : @view.View) -> Unit {
  (self.due)()
  self.way.put(0.0)
  self.way.go(1.0, @motion.tween(note_pop_ms, ease=Out), at=n.cause_at())
  self.due = n.at_moment(self.way.end(), fn() { self.ended.set(@signals.untracked(fn() { self.ended.get() }) + 1) })
}

///|
/// How far it has come in as `n` is drawn: at the moment it is drawn at while it comes, all of it once it is there.
fn NotePop::shown(self : NotePop, n : @view.View) -> Double {
  self.way.said()
  self.ended.get() |> ignore
  if self.way.goes_at(n.logic_at()) {
    self.way.value_at(n.drawn_at())
  } else {
    self.way.target()
  }
}

///|
/// One of a note's round keys (note_box's) in `row`: 36 across and round, on `ground` (0: none), icon `icon` `size`
/// across in `ink` in its middle, read out as a button `label`; pressed (its press let go on it), `press`.
fn note_key_node(row : @view.View, icon : String, size : Double, ground : Int64, ink : Int64, label : String, press : () -> Unit) -> Unit {
  let inset = (36.0 - size) / 2.0
  row.box(fn(k) {
    k
    .width(Is(Some(36.0)))
    .height(Is(Some(36.0)))
    .radius(Is(18.0))
    .ground(Is(ground))
    .padding(Is((inset, inset, inset, inset)))
    .presses(Is(true))
    .says(Is(Some(@view.said(Button, label~))))
    .on_press(press)
    |> ignore
    @sf.icon_node(k, icon, size, Is(ink)) |> ignore
  })
  |> ignore
}

///|
/// A note's pin (picture_pin's small one, 16): round in the mark's colour but for its corner at the foot towards the
/// mark (2), its number in white in its middle (10, 650), as `pin` says (its number, its colour) as it changes.
fn note_pin_node(parent : @view.View, pin : () -> (Int, Int64)) -> Unit {
  let color = fn() {
    marks_said()
    pin().1
  }
  parent.box(fn(p) {
    p.width(Is(Some(16.0))).height(Is(Some(16.0))).radius(Is(8.0)).ground(By(color)) |> ignore
    // its pointed corner: a square over the round one at the foot towards the mark
    p.box(fn(q) {
      q.over(Is(true)).offset(Is((0.0, 8.0))).width(Is(Some(8.0))).height(Is(Some(8.0))).radius(Is(2.0)).ground(By(color))
      |> ignore
    })
    |> ignore
    // its number, in its middle
    p.box(fn(m) {
      m.over(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      m.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
      m.box(fn(t) {
        t
        .words(By(fn() {
          marks_said()
          "\{pin().0}"
        }))
        .words_look(By(fn() { { size: 10.0, weight: 650, line: @ui.tree_theme().text_line * 10.0, wrap: false } }))
        .ink(Is(0xFFFFFFFFL))
        |> ignore
      })
      |> ignore
      m.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    })
    |> ignore
  })
  |> ignore
}
