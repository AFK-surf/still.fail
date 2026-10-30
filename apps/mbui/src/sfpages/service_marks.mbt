// What marking a service's page shows on the phone (ember apps/android chat/screens/Preview.kt: MarkMode, MarksOver,
// Note): the bar's edit key, the mode's bar, each mark's box, pin and bubble, its note; what marking does is sfbase's
// (service_marks.mbt).

///|
/// The bar's edit key (Preview.kt BarIcon(Icons.Edit, pressed)): 28 round, a 14 icon; picking, the accent's 14% under
/// it and its icon in the accent's ink. Named 标注 for a screen reader, what it does said on hover (Marks.tsx: 停止点选
/// while picking).
fn page_mark_key(c : @ui.Ctx, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("service/mark")
  let b = c.box(style=if on { mark_key_on } else { mark_key }, id~, fn() {
    @sf.icon(c, "edit", size=bar_icon_size, color=if on { t.p.accent_text } else { t.p.text }) |> ignore
    // Preview.kt BarKey: clip(CircleShape).clickable
    @motion.ripple(c, id, 14.0)
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.annotate.mark"))
  @sf.tip(c, "service/mark/tip", id, @sf.t(if on { "web-main.annotate.stopPicking" } else { "web-main.annotate.pageTip" }))
  c.clicked(id)
}

///|
/// A bar key's icon (Preview.kt BarIcon: 14).
let bar_icon_size : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let mark_key : @ui.Style = @ui.css("w=S7 h=S7 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let mark_key_on : @ui.Style = mark_key.then(@ui.style(bg=@sf.mark_key_on))

///|
/// The address's place while marking (Preview.kt Bar's `instead`: 4 in at each side, all the room there is).
// kept across runs: a value (no field of it changes)
let mark_mode_place : @ui.Style = @ui.css("w=Full px=S1")

///|
/// MarkMode's capsule: 30 high, round, the chip's ground a tenth of the way to the accent, what is in its ends
/// concentric with them (the dot's ring at its start, 添加到对话 at its end), 8 apart.
// kept across runs: a value (no field of it changes)
let mark_mode_bar : @ui.Style = @ui.style(
  row=true,
  w=Full,
  h=@sf.mark_bar_h,
  radius=Full,
  bg=Over(A(Accent, O10), Faint),
  pl=@sf.mark_bar_start,
  pr=@sf.mark_bar_end,
  gap=S2,
  align=ACenter,
)

///|
/// Its dot (7, the accent while picking, else muted), in the middle of a 13 ring's room, the ring the accent's 22% while
/// picking (so the dot stands where the ring's middle is, concentric with the bar's end, either way).
// kept across runs: a value (no field of it changes)
let mark_dot_box : @ui.Style = @ui.style(w=@sf.mark_ring, h=@sf.mark_ring, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let mark_dot_ring : @ui.Style = mark_dot_box.then(@ui.style(bg=@sf.mark_ring_bg))

///|
// kept across runs: a value (no field of it changes)
let mark_dot : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full, bg=Muted)

///|
// kept across runs: a value (no field of it changes)
let mark_dot_on : @ui.Style = mark_dot.then(@ui.css("bg=Accent"))

///|
/// What it says: how many (or what to do), 13 medium in the ink; 可继续点选 muted; why it failed in red; all on one line,
/// in what the bar leaves, cut short with an ellipsis where that is less (Marks.css.ts modeText: flex 1, min-width 0),
/// four of its characters kept (what is beside it in the page's bar gives way first: service.mbt bar_drop_nav).
// kept across runs: a value (no field of it changes)
let mark_words_box : @ui.Style = @ui.css("row w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let mark_count_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let mark_more_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let mark_error_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, wrap=false, w=Cut)

///|
/// Its × (24 round, a 12 icon) and 添加到对话 (24 high, round, the ink's ground, 10 in, 5 apart; 12 medium, the
/// surface's colour: faint while it cannot be pressed).
// kept across runs: a value (no field of it changes)
let mark_close : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let mark_put_pill : @ui.Style = @ui.style(
  row=true,
  h=S6,
  radius=Full,
  bg=Fg,
  px=S2_5,
  gap=@sf.mark_put_gap,
  align=ACenter,
)

///|
// kept across runs: a value (no field of it changes)
let mark_put_off : @ui.Style = mark_put_pill.then(@ui.css("bg=A(Fg,O40)"))

///|
// kept across runs: a value (no field of it changes)
let mark_put_words : @ui.TextStyle = @ui.text_style(
  size=Meta,
  weight=Medium,
  color=Card,
  wrap=false,
  dark=@ui.text_patch(color=Bg),
)

///|
/// A small icon in marking's bar (Preview.kt: 12).
let mark_small_icon : Double = 12.0

///|
/// In the address's place while marking (Preview.kt MarkMode): what to do or how many, then putting them into the
/// chat.
fn page_mark_mode(c : @ui.Ctx, src : Source, p : ServicePage, site : @ui.NativeView) -> Unit {
  let t = @sf.theme()
  let m = p.marks
  let n = m.marks.length()
  let busy = m.shot.get() is Some(_)
  c.box(style=mark_mode_bar, keep=true, fn() {
    c.box(style=if m.marking.get() { mark_dot_ring } else { mark_dot_box }, fn() {
      c.box(style=if m.marking.get() { mark_dot_on } else { mark_dot }, fn() {  }) |> ignore
    })
    |> ignore
    c.box(style=mark_words_box, keep=true, fn() {
      if m.error.get() != "" {
        c.text(m.error.get(), style=mark_error_words) |> ignore
      } else {
        let said = if n > 0 {
          svc("android-chat.preview.marked", args=[("n", n.to_string())])
        } else {
          svc("android-chat.preview.pick")
        }
        c.text(said, style=mark_count_words) |> ignore
        if m.marking.get() && n > 0 {
          c.text(svc("android-chat.preview.pickMore"), style=mark_more_words) |> ignore
        }
      }
    })
    |> ignore
    // ×: marking left
    let close = c.id("service/mark-close")
    if !busy && c.clicked(close) {
      page_marks_leave(p, site)
    }
    c.box(style=mark_close, id=if busy { 0 } else { close }, fn() {
      @sf.icon(c, "close", size=mark_small_icon, color=t.p.muted) |> ignore
    })
    |> ignore
    // 添加到对话 (正在截图 while it is)
    let able = !busy && n > 0
    let put = c.id("service/mark-put")
    if able && c.clicked(put) {
      page_marks_put(p, site, src)
    }
    let ink = if t.dark { t.p.bg } else { 0xFFFFFFFFL }
    c.box(style=if able { mark_put_pill } else { mark_put_off }, id=if able { put } else { 0 }, fn() {
      @sf.icon(c, "send", size=mark_small_icon, color=ink) |> ignore
      let words = svc(if busy { "android-chat.preview.shooting" } else { "android-chat.preview.put" })
      c.text(words, style=mark_put_words) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A mark's box on its element (Preview.kt MarksOver): 4 round, its edge the accent's 55% (1.5), open the accent (2)
/// over its 8%.
// kept across runs: a value (no field of it changes)
let mark_box_open : @ui.Style = @ui.style(radius=Base, border=B2, border_color=Accent, bg=@sf.mark_open_bg)

///|
/// A mark's box not open: 4 round, its edge 1.5 of the accent's 55%.
let mark_box_r : Double = 4.0

///|
let mark_edge : Double = 1.5

///|
let mark_edge_a : Double = 0.55

///|
/// A mark's pin: 24, round, white, 2 in, a shadow; the accent inside, its number 11 bold in white.
// kept across runs: a value (no field of it changes)
let mark_pin : @ui.Style = @ui.style(w=S6, h=S6, radius=Full, bg=OnAccent, p=S0_5, shadow=@sf.pin_raised.cast())

///|
// kept across runs: a value (no field of it changes)
let mark_pin_in : @ui.Style = @ui.css("w=Full h=Full radius=Full bg=Accent align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let mark_pin_words : @ui.TextStyle = @ui.text_style(size=@sf.mark_pin_size, weight=Bold, color=OnAccent, wrap=false)

///|
/// What is said of a mark beside its pin: 26 high, round, frosted, a shadow, 10 in; 12 in the ink, one line.
// kept across runs: a value (no field of it changes)
let mark_said : @ui.Style = @ui.style(
  h=@sf.mark_said_h,
  radius=Full,
  bg=@sf.mark_bubble,
  shadow=@sf.pin_raised.cast(),
  px=S2_5,
  justify=JCenter,
  clip=true,
  dark=@ui.patch(bg=@sf.mark_bubble_dark),
)

///|
// kept across runs: a value (no field of it changes)
let mark_said_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// The marks over the page, where it is drawn (Preview.kt MarksOver): each a box on its element, a numbered pin on its
/// corner (kept in sight at the page's edges), what is said of it beside the pin, or its note open. `ox`, `oy`: the
/// page's top left on the stage; `view_w` its width there before its scale; `stage_w` the stage's width.
fn page_marks_over(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  ox : Double,
  oy : Double,
  view_w : Double,
  scale : Double,
  stage_w : Double,
) -> Unit {
  let t = @sf.theme()
  let m = p.marks
  // CSS pixels to the stage's: the page's own ratio, then the stage's scale
  let k = if m.css_w.get() > 0.0 { view_w / m.css_w.get() * scale } else { scale }
  c.layer(fn() {
    for mark in m.marks {
      let (bx, by, bw, bh) = m.at.get(mark.n).unwrap_or(mark.rect)
      let x = ox + bx * k
      let y = oy + by * k
      let open = m.editing.get() == Some(mark.n)
      let size = @ui.style(w=Fixed(bw * k), h=Fixed(bh * k))
      if open {
        c.box(style=mark_box_open.then(size), tx=x, ty=y, fn() {  }) |> ignore
      } else {
        // (its edge 1.5, which no Stroke of the scale says: said loosely)
        c.box(style=size, tx=x, ty=y, radius=mark_box_r, border=mark_edge, border_color=@sf.alpha(t.p.accent, mark_edge_a), fn() {  })
        |> ignore
      }
      // the pin's point on the element's top-left corner
      let pin_x = dmax(pin_edge, x)
      let pin_y = dmax(pin_top, y)
      let pin = c.id("service/pin/\{mark.n}")
      if c.clicked(pin) {
        m.editing.set(if open { None } else { Some(mark.n) })
        if !open {
          m.note.set(mark.comment.get())
          c.focus_editor("service/note")
        }
      }
      c.box(style=mark_pin, tx=pin_x - pin_edge, ty=pin_y - pin_rise, id=pin, fn() {
        c.box(style=mark_pin_in, fn() { c.text("\{mark.n}", style=mark_pin_words) |> ignore }) |> ignore
      })
      |> ignore
      if open {
        page_mark_note(c, p, site, mark, pin_x, pin_y, stage_w)
      } else if mark.comment.get() != "" {
        // beside the pin, on its left when the right has too little room
        let right = stage_w - pin_x - said_from >= dmin(said_room, pin_x - said_left)
        let max_w = dmax(said_least, if right { stage_w - pin_x - said_from } else { pin_x - said_left })
        let said = c.id("service/said/\{mark.n}")
        if c.clicked(said) {
          m.editing.set(Some(mark.n))
          m.note.set(mark.comment.get())
          c.focus_editor("service/note")
        }
        let row = @ui.style(row=true, w=Fixed(if right { max_w } else { pin_x - said_beside }), justify=if right {
          JStart
        } else {
          JEnd
        })
        c.box(style=row, tx=if right { pin_x + pin_w + pin_edge * 2.0 } else { 0.0 }, ty=pin_y - pin_rise - 1.0, fn() {
          c.box(style=mark_said.then(@ui.style(max_w=Fixed(max_w))), id=said, fn() {
            c.text(mark.comment.get(), style=mark_said_words) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// Where a pin sits (Preview.kt MarksOver): 24 wide, its point 2 in from its left and 22 down, kept 2 from the
/// stage's left and 24 from its top; what is said 36 right of its point (28 past it), 220 wanted there, else left of it
/// (14 clear, 6 from the pin), 40 at least.
let pin_w : Double = 24.0

///|
let pin_edge : Double = 2.0

///|
let pin_rise : Double = 22.0

///|
let pin_top : Double = 24.0

///|
let said_from : Double = 36.0

///|
let said_room : Double = 220.0

///|
let said_left : Double = 14.0

///|
let said_beside : Double = 6.0

///|
let said_least : Double = 40.0

///|
/// A mark's note (Preview.kt Note): 280 wide at most (8 clear of the stage's sides), 36 high, round, frosted, a
/// stronger shadow, 12 in at its start and 4 at its end, 6 apart; 28 right of the pin's point and 28 above it (8 from
/// the stage's top at least).
// kept across runs: a value (no field of it changes)
let mark_note : @ui.Style = @ui.style(
  row=true,
  h=S9,
  radius=Full,
  bg=@sf.mark_bubble,
  shadow=@sf.bubble_raised.cast(),
  pl=S3,
  pr=S1,
  gap=S1_5,
  align=ACenter,
  dark=@ui.patch(bg=@sf.mark_bubble_dark),
)

///|
// kept across runs: a value (no field of it changes)
let mark_note_field : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let mark_note_remove : @ui.Style = @ui.css("w=S7 h=S7 radius=Full align=ACenter justify=JCenter")

///|
let note_most : Double = 280.0

///|
let note_clear : Double = 8.0

///|
let note_off : Double = 28.0

///|
/// The note's words (13) and its remove key's icon (14).
let note_font : Double = 13.0

///|
let note_icon : Double = 14.0

///|
/// What is said about one mark, in a bubble beside its pin (Preview.kt Note): what it is for while empty; done, closed;
/// its remove key takes the mark off the page too.
fn page_mark_note(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  mark : PageMark,
  x : Double,
  y : Double,
  stage_w : Double,
) -> Unit {
  let t = @sf.theme()
  let width = dmin(note_most, stage_w - 2.0 * note_clear)
  let left = dmin(dmax(note_clear, x + note_off), dmax(note_clear, stage_w - width - note_clear))
  let top = dmax(note_clear, y - note_off)
  c.box(style=mark_note.then(@ui.style(w=Fixed(width))), tx=left, ty=top, fn() {
    c.box(style=mark_note_field, fn() {
      let r = c.editor(
        "service/note",
        font_size=note_font,
        max_lines=1,
        plain=true,
        color=t.p.text,
        caret_color=t.p.accent,
        placeholder=svc("android-chat.preview.mark.comment", args=[("kind", mark.kind)]),
        placeholder_color=t.p.muted,
        field=p.marks.note,
      )
      mark.comment.set(r.text)
      match r.submitted {
        Some(_) => {
          p.marks.editing.set(None)
          c.blur()
        }
        None => ()
      }
    })
    |> ignore
    let remove = c.id("service/note-remove")
    if c.clicked(remove) {
      page_marks_remove(p, site, mark.n)
      c.blur()
    }
    c.box(style=mark_note_remove, id=remove, fn() {
      @sf.icon(c, "trash", size=note_icon, color=t.p.muted) |> ignore
    })
    |> ignore
  })
  |> ignore
}
