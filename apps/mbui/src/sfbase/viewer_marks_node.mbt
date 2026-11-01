// Marking's tools as nodes of the window's tree (marks_foot's MarksTools, ImageMarks.kt): the tools, the colour and
// its palette, the picked one's removal, undo and redo, each done at the moment it is pressed (its press let go on
// it), as the picture's own drawing is (Viewer::finger_on): the tool a stroke is drawn with the one taken up, whatever
// frames came between. The note being written too (note_box_node): its pin and what it is, 删除 and 完成 nodes, done as
// their press is let go; what is written in it an old view's field, the note as tall as it lays out. The notes' cards
// over the tools (note_cards_node): each opening its note as its press is let go, those the row has not the room for
// left out of it, the last first, a +N card standing for them (a menu of them).

///|
/// How a marking tool is drawn (picture_button's, in the viewer's dark): its icon in the quieter white, near white on
/// white at 16% while it is the tool in use; no ground of its own besides.
fn marks_ink() -> @sf.ViewerInk {
  { ground: 0x000000FFL, ink: dark_text, muted: dark_muted, line: 0L, hover: 0L, chosen: 0xFFFFFF29L }
}

///|
/// Marking's foot in `h` (a layer over the viewer's, all of it), as marks_foot lays it out, one column: the notes
/// (their cards, note_cards_node, or the note being written, note_box_node) as far down as what is under them lets
/// them; under them, while no note is written, the colours' row while asked for over the row of tools on dark
/// glass (选择, 框, 箭头, 画笔, 文字 · the colour · 删除 the picked · 撤销, 重做), each a picture_button's 32, in its
/// middle, 8 over `foot` (the navigation bar's room) at the bottom. Each as marking says as it changes; each pressed
/// (its press let go on it), done then. Their tips in a layer of their own over all of it.
fn marks_foot_node(h : @view.View, foot : () -> Double) -> Unit {
  h.over(Is(true)) |> ignore
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = @sf.TipLayer::new(fn() { tips_at.val })
  h.box(fn(col) {
    col.over(Is(true)).padding(By(fn() { (0.0, 0.0, 0.0, foot()) })) |> ignore
    // (the room over them the picture's: nothing of the foot's)
    col.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    // (the notes' cards, while no note is written: note_cards_node)
    col.show(
      fn() {
        marks_said()
        marking.note < 0 && mark_notes().length() > 0
      },
      fn(r) { note_cards_node(r) },
    )
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
      // the field, a field of the tree's: as tall as it lays out (at least as a key is, its words in its middle)
      row.box(fn(f) {
        // (the room its row leaves between its keys, as note_box's Fill: none of its own before it is shared out, giving
        // way as they do; as tall as a key at least, its 7 over and under round it, its words in its middle)
        f
        .grow(Is(1.0))
        .basis(Is(Some(0.0)))
        .shrink(Is(1.0))
        .padding(Is((8.0, 7.0, 8.0, 7.0)))
        .min_height(Is(Some(36.0)))
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        |> ignore
        @ui.field(
          f,
          marking.note_field,
          placeholder=pv("android-chat.annotate.write"),
          font_size=16.0,
          line=21.0,
          max_lines=8,
          color=note_ink,
          placeholder_color=note_subtle,
          caret_color=note_accent,
          enter_sends=false,
        )
        .grow(Is(1.0))
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

///|
/// The notes said so far in `r` (marks_foot's, Notes.kt's tray), 10 over the tools: a card each across the foot (16 in
/// at its sides, 8 between), in their numbers' order; where they do not all fit, the last leave the row first, a +N
/// card at its end standing for them (a menu of them, in their order): nothing scrolled, nothing wrapped. Each card,
/// pressed (its press let go on it), opens its note; +N's, its menu. Which are left out, how many +N says and what its
/// menu holds one fact: the row's as it was laid out (View::left_out).
fn note_cards_node(r : @view.View) -> Unit {
  r.padding(Is((0.0, 0.0, 0.0, marks_notes_over_tools))) |> ignore
  // (each card's node by its mark: what +N reads of which are left out)
  let cards : Map[Int, @view.View] = {}
  r.box(fn(row) {
    // (each card as tall as what it holds, +N's its one line: marks_notes_row's, its items at its top)
    row
    .row(Is(true))
    .lines_up(Is(Some(Start)))
    .fits(Is(true))
    .padding(Is((@ui.Space::px(S4), 0.0, @ui.Space::px(S4), 0.0)))
    .gap(Is(@ui.Space::px(S2)))
    |> ignore
    row.each(
      fn() {
        marks_said()
        mark_notes()
      },
      fn(x) { x.0 },
      fn(card, note) {
        let mid = @signals.untracked(fn() { note.get().0 })
        cards[mid] = card
        card.owns(fn() { cards.remove(mid) }) |> ignore
        // (the last in the row leaving it first)
        card.drops(By(fn() {
          marks_said()
          let notes = mark_notes()
          match notes.search_by(fn(x) { x.0 == mid }) {
            Some(i) => notes.length() - i
            None => 1
          }
        }))
        |> ignore
        note_tray_card_node(
          card,
          note_card_w,
          fn(head) {
            note_pin_node(head, fn() {
              let (_, n, _, color) = note.get()
              (n, color)
            })
            note_first_node(head, fn() {
              marks_said()
              note_said(mid)
            }, fn() {
              marks_said()
              marking.comments.get(mid).unwrap_or("").trim(chars=" \n\t").to_string() == ""
            })
          },
          fn(b) {
            b.box(fn(t) {
              t
              .words(By(fn() { note.get().2 }))
              .words_look(By(fn() {
                let (size, _) = @ui.tree_theme().text_size(Caption)
                { size, weight: 400, line: 17.0, wrap: false }
              }))
              .ink(Is(note_muted))
              |> ignore
            })
            |> ignore
          },
          label=fn() {
            let (_, n, _, _) = note.get()
            "\{n}  " + note_said(mid)
          },
          press=fn() { marks_open_note(@ui.current(), mid) },
        )
      },
    )
    // +N, while some are left out: their notes' menu
    row.box(fn(more) {
      more.drops(Is(-1)) |> ignore
      let gone = fn() {
        marks_said()
        mark_notes().filter(fn(x) {
          match cards.get(x.0) {
            Some(v) => v.left_out()
            None => false
          }
        })
      }
      note_tray_card_node(
        more,
        note_more_w,
        fn(head) {
          note_first_node(head, fn() { "+\{gone().length()}" }, fn() { false })
        },
        fn(_) {  },
        label=fn() { "+\{gone().length()}" },
        press=fn() {
          let (x, y, w, h) = more.rect()
          let items : Array[@sf.MenuItem?] = gone().map(fn(x) {
            Some(@sf.menu_item_of("\{x.1}  " + note_said(x.0), fn() { marks_open_note(@ui.current(), x.0) }))
          })
          @sf.menu(items, from=At(x, y, w, h), along=End)
        },
      )
    })
    |> ignore
  })
  |> ignore
}

///|
/// A card of the notes' tray in `card` (note_tray_card's: `w` wide, frosted, round by the ladder's row step, its pin
/// concentric in its corner, its first line level with it): its head row (`head`) over what `body` puts under it,
/// read out as a button `label` says; pressed (its press let go on it), `press`.
fn note_tray_card_node(
  card : @view.View,
  w : Double,
  head : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
  label~ : () -> String,
  press~ : () -> Unit,
) -> Unit {
  let pin_in = @sf.capsule_in(note_card_corner, note_pin)
  card
  .width(Is(Some(w)))
  .padding(Is((pin_in, pin_in - (note_first_line - note_pin) / 2.0, note_card_end, note_card_foot)))
  .gap(Is(3.0))
  .radius(Is(note_card_corner))
  .ground(Is(note_ground))
  .shadow(Is((@sf.floating.sigma, @sf.floating.dy, @sf.floating.color)))
  .presses(Is(true))
  .says(By(fn() {
    marks_said()
    Some(@view.said(Button, label=label()))
  }))
  .on_press(press)
  |> ignore
  card.box(fn(h) {
    h.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S1_5))) |> ignore
    head(h)
  })
  |> ignore
  body(card)
}

///|
/// A tray card's first line (note_first's) in `head`: `words`, muted where `quiet` (only quoting), cut by its card where
/// long, in the meta's size on lines 20 apart.
fn note_first_node(head : @view.View, words : () -> String, quiet : () -> Bool) -> Unit {
  head.box(fn(f) {
    f.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).clips(Is(true)) |> ignore
    f.box(fn(t) {
      t
      .words(By(words))
      .words_look(By(fn() {
        let (size, _) = @ui.tree_theme().text_size(Meta)
        { size, weight: 400, line: 20.0, wrap: false }
      }))
      .ink(By(fn() { if quiet() { note_muted } else { note_ink } }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The numbered marks' pins over viewer `vw`'s picture in `h` (a layer over the viewer's, all of it; marks_draw's,
/// ImageMarks.kt Pins): each picture_pin's 24 at its own size whatever the zoom, up and to the right of its point (a
/// box's corner, an arrow's start; kept 2 in from the picture's sides, 22 down from its top), where the picture is as
/// each frame draws it while the zoom or the lift goes; a little bigger from its point while its note is open. Pressed
/// (its press let go on it): its note opened, or closed where it was the one open. Each read out as 标注 n.
fn marks_pins_node(h : @view.View, vw : Viewer) -> Unit {
  h.over(Is(true)) |> ignore
  h.each(
    fn() {
      marks_said()
      let numbers = mark_numbers(marking.shapes)
      marking.shapes.filter_map(fn(s) {
        match numbers.get(s.id) {
          Some(n) => {
            let (px, py) = if s.kind == "box" {
              let (bx, by, _, _) = s.bounds()
              (bx, by)
            } else {
              (s.pts[0], s.pts[1])
            }
            Some((s.id, n, s.color, px, py))
          }
          None => None
        }
      })
    },
    fn(x) { x.0 },
    fn(p, pin) {
      let color = fn() { pin.get().2 }
      let halo = fn() { halo_of(color()) }
      let open = fn() {
        marks_said()
        marking.note == pin.get().0
      }
      p
      .over(Is(true))
      .width(Is(Some(24.0)))
      .height(Is(Some(24.0)))
      .radius(Is(12.0))
      .ground(By(halo))
      .shadow(Is((@sf.pin_raised.sigma, @sf.pin_raised.dy, @sf.pin_raised.color)))
      // (where the picture is: as each frame draws it while the zoom or the lift goes, else where they have it)
      .offset(By(fn() {
        let (_, _, _, x0, y0) = pin.get()
        match vw.marks_rect_on(p) {
          Some((rx, ry, rw, _)) if vw.zoom.nw > 0.0 => {
            let k = rw / vw.zoom.nw
            let x = dmax(2.0 / k, dmin(dmax(2.0 / k, vw.zoom.nw - 22.0 / k), x0))
            let y = dmax(22.0 / k, dmin(dmax(22.0 / k, vw.zoom.nh - 2.0 / k), y0))
            (rx + x * k - 2.0, ry + y * k - 22.0)
          }
          _ => (0.0, 0.0)
        }
      }))
      .scale(By(fn() { if open() { pin_open_scale } else { 1.0 } }), about=@view.At(2.0 / 24.0, 22.0 / 24.0))
      .presses(Is(true))
      .says(By(fn() { Some(@view.said(Button, label=pv_fill("android-chat.marks.pin", [("n", pin.get().1.to_string())]))) }))
      .on_press(fn() {
        let id = @signals.untracked(fn() { pin.get().0 })
        if marking.note == id {
          marks_put_down(@ui.current())
          marking.picked = -1
          marking.note = -1
          marks_changed()
        } else {
          marks_open_note(@ui.current(), id)
        }
      })
      |> ignore
      // its pointed corner: a square over the round one at the foot towards the mark
      p.box(fn(q) {
        q.over(Is(true)).offset(Is((0.0, 12.0))).width(Is(Some(12.0))).height(Is(Some(12.0))).radius(Is(3.0)).ground(By(halo))
        |> ignore
      })
      |> ignore
      // within its halo's 2, the mark's colour, cornered the same (its corner a square at its own foot, as picture_pin's)
      p.box(fn(q) {
        q.over(Is(true)).offset(Is((2.0, 2.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).radius(Is(10.0)).ground(By(color))
        |> ignore
        q.box(fn(c) {
          c.over(Is(true)).offset(Is((0.0, 10.0))).width(Is(Some(10.0))).height(Is(Some(10.0))).radius(Is(1.5)).ground(By(color))
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // its number, in its middle, in its halo's colour
      p.box(fn(m) {
        m.over(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        m.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
        m.box(fn(t) {
          t
          .words(By(fn() { "\{pin.get().1}" }))
          .words_look(By(fn() { { size: 11.0, weight: 700, line: @ui.tree_theme().text_line * 11.0, wrap: false } }))
          .ink(By(halo))
          |> ignore
        })
        |> ignore
        m.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
      })
      |> ignore
    },
  )
}

///|
/// Where viewer `vw`'s picture is for what node `n` draws over it (Viewer::marks_rect, lifted over the keyboard): as each
/// frame draws it while the zoom or the lift goes, else where they leave it (the clock read no more). As either is told.
fn Viewer::marks_rect_on(self : Viewer, n : @view.View) -> (Double, Double, Double, Double)? {
  self.zoom.told()
  self.lift.said()
  let now = n.logic_at()
  let t = if self.zoom.goes_at(now) || self.lift.goes_at(now) { n.drawn_at() } else { @double.infinity }
  self.marks_rect(t)
}

///|
/// The marks drawn over viewer `vw`'s picture in `h` (a layer over the canvas, all of it; marks_draw's, ImageMarks.kt
/// drawMarks, drawPicked): the lines (a box's rounded edge, an arrow and its barbs, a line drawn by hand, the picked
/// mark's dashed frame: marks_lines), words edged in their halo (eight times a little off each way, the words over
/// them), the picked mark's handles (12 round and white, edged 1.5 in the marking colour), each where the picture is
/// as it is drawn (Viewer::marks_rect_on), at this zoom's size. As marking is now (marks_drawn: what a finger draws now
/// with them).
fn marks_shapes_node(h : @view.View, vw : Viewer) -> Unit {
  h.over(Is(true)) |> ignore
  // (the lines and where the handles are, one working out of them as the picture is drawn)
  let laid = fn(n : @view.View) {
    marks_said()
    match vw.marks_rect_on(n) {
      Some(r) => marks_lines(r, vw.zoom.nw)
      None => ([], [])
    }
  }
  h.box(fn(l) { l.over(Is(true)).lines(By(fn() { laid(l).0 })) |> ignore }) |> ignore
  // words, edged in their halo: each a node for the words and eight for their edge, under them
  h.each(
    fn() {
      marks_said()
      marks_drawn().filter_map(fn(m) {
        if m.kind == "words" {
          Some((m.id, m.text, m.color, m.w, m.pts[0], m.pts[1]))
        } else {
          None
        }
      })
    },
    fn(x) { x.0 },
    fn(w, words) {
      w.over(Is(true)) |> ignore
      for o in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0), (-1.0, -1.0), (1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (0.0, 0.0)] {
        let edge = o != (0.0, 0.0)
        w.box(fn(t) {
          t
          .over(Is(true))
          .words(By(fn() { words.get().1 }))
          .words_look(By(fn() {
            let size = match vw.marks_rect_on(t) {
              Some((_, _, rw, _)) => words.get().3 * rw / dmax(1.0, vw.zoom.nw)
              None => 0.0
            }
            { size, weight: 600, line: size * 1.3, wrap: false }
          }))
          .ink(By(fn() { if edge { halo_of(words.get().2) } else { words.get().2 } }))
          .offset(By(fn() {
            let (_, _, _, ww, x, y) = words.get()
            match vw.marks_rect_on(t) {
              Some((rx, ry, rw, _)) => {
                let k = rw / dmax(1.0, vw.zoom.nw)
                let e = ww * k * 0.08
                (rx + x * k + o.0 * e, ry + y * k + o.1 * e)
              }
              None => (0.0, 0.0)
            }
          }))
          |> ignore
        })
        |> ignore
      }
    },
  )
  // the picked mark's handles
  h.each(
    fn() {
      marks_said()
      let n = match vw.zoom.rect() {
        Some(r) => marks_lines(r, vw.zoom.nw).1.length()
        None => 0
      }
      Array::makei(n, fn(i) { i })
    },
    fn(i) { i },
    fn(d, i) {
      let at = fn() {
        let (_, handles) = laid(d)
        match handles.get(@signals.untracked(fn() { i.get() })) {
          Some((x, y)) => (x - 6.0, y - 6.0)
          None => (0.0, 0.0)
        }
      }
      d
      .over(Is(true))
      .width(Is(Some(12.0)))
      .height(Is(Some(12.0)))
      .radius(Is(6.0))
      .ground(Is(0xFFFFFFFFL))
      .edge(Is((1.5, 0xE5704AFFL)))
      .offset(By(at))
      |> ignore
    },
  )
}


///|
/// The words being written over viewer `vw`'s picture while it marks (marking.writing; ImageMarks.kt WritingField), in
/// `h` (over the canvas, all of it): a field of the tree's where they begin on the picture as it is drawn while the zoom
/// or the lift goes (marks_rect_on), as wide as six of their size at least 120, in their size on the picture and their
/// colour, its placeholder that colour at 55%; given up (Enter), put down (marks_put_down).
fn marks_writing_node(h : @view.View, vw : Viewer) -> Unit {
  h.over(Is(true)) |> ignore
  h.box(fn(b) {
    let at = fn() {
      marks_said()
      match marking.writing {
        Some((_, x, y, w, color)) => Some((x, y, w, color))
        None => None
      }
    }
    // (how big a natural pixel of the picture is drawn)
    let k = fn() {
      match vw.marks_rect_on(b) {
        Some((_, _, rw, _)) if vw.zoom.nw > 0.0 => rw / vw.zoom.nw
        _ => 1.0
      }
    }
    let size = fn() {
      match at() {
        Some((_, _, w, _)) => w * k()
        None => mark_text
      }
    }
    b
    .over(Is(true))
    .offset(By(fn() {
      match (at(), vw.marks_rect_on(b)) {
        (Some((x, y, _, _)), Some((rx, ry, rw, _))) if vw.zoom.nw > 0.0 => {
          let k = rw / vw.zoom.nw
          (rx + x * k, ry + y * k)
        }
        _ => (0.0, 0.0)
      }
    }))
    .width(By(fn() { Some(dmax(size() * 6.0, 120.0)) }))
    |> ignore
    @ui.field(
      b,
      marking.write_field,
      placeholder=pv("android-chat.marks.write"),
      max_lines=1,
      size_by=size,
      colors_by=fn() {
        let color = match at() {
          Some((_, _, _, c)) => c
          None => marking.color
        }
        (color, @sf.alpha(color, 0.55), color)
      },
      submitted=fn(_) { marks_put_down(@ui.current()) },
    )
    |> ignore
  })
  |> ignore
}
