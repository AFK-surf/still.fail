// Marking's tools as nodes of the window's tree (marks_foot's MarksTools, ImageMarks.kt): the tools, the colour and
// its palette, the picked one's removal, undo and redo, each done at the moment it is pressed (its press let go on
// it), as the picture's own drawing is (Viewer::finger_on): the tool a stroke is drawn with the one taken up, whatever
// frames came between. The notes over them, and the note being written, are the old view's still (marks_foot).

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
      marks_foot(c, tools=false)
    })
    .grow(Is(1.0))
    |> @ui.old_takes_own
    |> ignore
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
