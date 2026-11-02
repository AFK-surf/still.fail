// A page's parts (page.mbt) as nodes of the window's tree, made once: its frame (back over its large title, what it is
// for, its blocks in the page's room, all of it scrolling), a heading, a group's card and the rows on it that go
// somewhere (link_row's), each as page.mbt draws it narrow, its styles the same (their words through @ui.style_words),
// what changes bound to what it is told: the frame's back and room, the words, the language, the theme. What a page
// made so holds is laid out as the page's look has it as it is made (look_for its width then: Narrow); the parts read
// it as they are made, never as they are drawn.

///|
/// Whether the hand is on `v` as the theme answers it: a mouse over it or pressing it, a finger pressing it; the
/// keyboard's focus shown on it (what lights a row, a button: c.lit's).
fn lit_node(v : @view.View) -> Bool {
  v.focus_shown() ||
  (match @ui.pointing() {
    Mouse => v.pointed() || v.pressed()
    Finger => v.pressed()
  })
}

///|
/// `v` pressed as an old view's box with an id is (Ctx::clicked: a tap, a mouse's click, Enter or Space with the focus,
/// a screen reader's press): `press` done then; its ripple and sink as `corner` rounds it (press_look); read out as
/// `role` named `label`.
fn pressed_node(
  v : @view.View,
  press : () -> Unit,
  corner : @view.Live[Double],
  role : @view.Role,
  label : () -> String,
) -> Unit {
  v
  .presses(Is(true))
  .focusable(Is(true))
  .says(By(fn() { Some(@view.said(role, label=label())) }))
  .on_press(press)
  |> ignore
  let rippled = press_look(v, corner, fn() { false })
  let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
  v.gesture(
    @ui.touch_slop(),
    press=rippled,
    tap=fn(d) { if on_it(d) { press() } },
    drag=fn(d) {
      // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
      if d.kind == Up && @ui.pointing() is Mouse && on_it(d) {
        press()
      }
    },
  )
  |> ignore
}

///|
/// Words of `style` in node `w`, `words` as they are said, cut short on their line where `style` says so.
fn styled_words(w : @view.View, words : () -> String, style : () -> @ui.TextStyle) -> @view.View {
  w
  .words(By(words))
  .words_look(By(fn() { @ui.style_words(style()) }))
  .ink(By(fn() { @ui.style_ink(style()) }))
  |> ignore
  if @ui.style_cut(@signals.untracked(style)) {
    w.shrink(Is(1.0)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
  }
  w
}

///|
/// A page titled `title` in node `v` (page's, narrow: page.mbt narrow_page), as nodes: under what stands over it as the
/// frame says (`frame`'s top), back where the frame says it goes (TopBack: its chevron and its words, `on_back` as it
/// is pressed), its large title (as far down as a wide page's head where nothing is over it), what it is for (`lead`)
/// under it, then what `content` makes (its blocks, each in the page's room: page_block; which there are its own to
/// follow, the frame and how far it is scrolled kept) and 30 under the last, then the frame's room at its foot; all of
/// it scrolling in the page. What the frame says is followed as it changes.
pub fn page_node(
  v : @view.View,
  title : () -> String,
  content : (@view.View) -> Unit,
  on_back~ : () -> Unit,
  frame? : () -> PageFrame = fn() { no_frame },
  lead? : () -> String = fn() { "" },
) -> Unit {
  let scroll = @view.Scroll::new()
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  v.box(fn(sc) {
    sc.grow(Is(1.0)) |> ignore
    sc.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
      with_look(Narrow, fn() {
        // under what stands over it (a status bar)
        s.show(fn() { frame().top > 0.0 }, fn(top) { top.height(By(fn() { Some(frame().top) })) |> ignore })
        // back to where it was opened from
        s.show(fn() { frame().back is Some(_) }, fn(line) {
          line.row(Is(true)).padding(Is((pg_back_x, pg_back_top, pg_back_x, pg_back_foot))).lines_up(Is(Some(Middle)))
          |> ignore
          nav_back_node(line, fn() { frame().back.unwrap_or("") }, on_back)
        })
        // its large title (a place's top page: none, the frame's bar names it)
        s.show(fn() { !frame().named }, fn(head) {
          head
          .padding(By(fn() {
            let f = frame()
            let alone = f.back is None && f.top <= 0.0
            (pg_title_x, if alone { pg_title_alone_top } else { 0.0 }, pg_title_x, pg_title_foot)
          }))
          |> ignore
          head.box(fn(l) {
            l.row(Is(true)).gap(Is(pg_title_gap)).lines_up(Is(Some(Middle))) |> ignore
            l.box(fn(w) {
              w.grow(Is(1.0)).min_width(Is(Some(pg_title_least))) |> ignore
              w.box(fn(t) { styled_words(t, title, fn() { pg_title }) |> ignore }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        // what it is for
        s.show(fn() { lead() != "" }, fn(l) {
          l.padding(Is((pg_lead_x, 0.0, pg_lead_x, pg_lead_foot))) |> ignore
          l.box(fn(w) { styled_words(w, lead, fn() { pg_lead }) |> ignore }) |> ignore
        })
        // what it holds (each block in the page's room: page_block)
        content(s)
        // 30 under the last, then the frame's room
        s.box(fn(f) { f.height(By(fn() { Some(pg_foot + frame().foot) })) |> ignore }) |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// Back's line's room (pg_back_line: 10 in, 6 over, 4 under); the large title's (pg_title_box: 16 in, 6 under; 40 over
/// with nothing over it), its line's gap and its words' least (pg_title_line, pg_title_words); what it is for
/// (pg_lead_box: 12 in, 10 under).
let pg_back_x : Double = 10.0

///|
let pg_back_top : Double = 6.0

///|
let pg_back_foot : Double = 4.0

///|
let pg_title_x : Double = 16.0

///|
let pg_title_foot : Double = 6.0

///|
let pg_title_alone_top : Double = 40.0

///|
let pg_title_gap : Double = 10.0

///|
let pg_title_least : Double = 80.0

///|
let pg_lead_x : Double = 12.0

///|
let pg_lead_foot : Double = 10.0

///|
/// Back (nav_back's, as a node): a chevron and where to (`label`) in the link's ink, rippling as it is pressed; `back`
/// done then.
fn nav_back_node(parent : @view.View, label : () -> String, back : () -> Unit) -> Unit {
  parent.box(fn(b) {
    b
    .row(Is(true))
    .padding(Is((0.0, nav_back_y, nav_back_end, nav_back_y)))
    .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    pressed_node(b, back, Is(nav_back_ripple), Link, label)
    icon_node(b, "chevron-left", nav_back_icon, By(fn() { theme().p.accent_text })) |> ignore
    b.box(fn(w) { styled_words(w, label, fn() { nav_back_words }) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// nav_back_box's room (4 over and under, 6 at its end), its chevron's size, its ripple's corner.
let nav_back_y : Double = 4.0

///|
let nav_back_end : Double = 6.0

///|
let nav_back_icon : Double = 22.0

///|
let nav_back_ripple : Double = 8.0

///|
/// A heading over a group (heading's, narrow: SectionHeader, 12 in, its words strong, 14 over it and 6 under).
pub fn heading_node(parent : @view.View, title : () -> String) -> Unit {
  parent.box(fn(l) {
    l.row(Is(true)).padding(Is((12.0, 14.0, 8.0, title_card_narrow))).gap(Is(8.0)).lines_up(Is(Some(End))) |> ignore
    l.box(fn(w) { styled_words(w, title, fn() { pg_heading }) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// Rows together on a list card (group's, narrow: ListCard, 10 under it, its rows `list_pad` in, its corner the list
/// card's), `rows` made in it.
pub fn group_node(parent : @view.View, rows : (@view.View) -> Unit) -> Unit {
  parent.box(fn(room) {
    room.padding(Is((0.0, 0.0, 0.0, 10.0))) |> ignore
    room.box(fn(card) {
      card
      .padding(Is((list_pad, list_pad, list_pad, list_pad)))
      .radius(Is(list_card_corner))
      .ground(By(fn() { @ui.tree_theme().color(Card) }))
      .clips(Is(true))
      |> ignore
      rows(card)
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a row on a card (link_row_node) is by, before its words: one of still.fail's line icons, in the muted ink; or
/// what makes it (a person's picture, a workspace's mark: an old view, hosted).
pub(all) enum RowLead {
  NoLead
  LeadIcon(String)
  LeadMade((@view.View) -> Unit)
}

///|
/// A row on a group's card that goes somewhere (link_row's, narrow, in a card): `lead` before its title (`strong`
/// where it names who or what it is), what it says at its end (`value`, in red where `value_bad`, a red dot before it
/// where `value_dot`) and a chevron (none where not `chevron`; an arrow out where it goes `out` of the app); `note` under
/// its title, a line of its own as wide as its words, its end then on its first line, its lead across that line's
/// middle; `below` under that while `below_open` says it is any of the way open (a room opening on it, its row growing
/// round it: @motion.reveal's). One that `acts` (does something at once where it is): its title in the link's ink, no
/// chevron. Lit under the hand, rippling under a finger, `press` done as it is pressed; going nowhere where not `goes`
/// (a value said: none of that). Its words as they are said.
pub fn link_row_node(
  parent : @view.View,
  title : () -> String,
  press : () -> Unit,
  value? : () -> String = fn() { "" },
  value_bad? : () -> Bool = fn() { false },
  value_dot? : () -> Bool = fn() { false },
  note? : () -> String = fn() { "" },
  strong? : Bool = false,
  lead? : RowLead = NoLead,
  goes? : Bool = true,
  chevron? : Bool = true,
  out? : Bool = false,
  acts? : Bool = false,
  below? : (@view.View) -> Unit,
  below_open? : () -> Double = fn() { 0.0 },
) -> Unit {
  let below_shown = fn() { below is Some(_) && below_open() > 0.0 }
  let under = fn() { note() != "" || below_shown() }
  let titled = if strong { pg_row_title.then(row_strong) } else { pg_row_title }
  let mark = if out { "arrow-up-right" } else { "chevron-right" }
  let ends = goes && (out || (chevron && !acts))
  parent.box(fn(r) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    .padding(Is((text_in, text_in, text_in, text_in)))
    .radius(Is(inner_corner(group_corner, list_pad)))
    .min_height(By(fn() { Some(theme().items.least) }))
    .lines_up(By(fn() { Some(if under() { Start } else { Middle }) }))
    |> ignore
    if goes {
      r.ground(By(fn() { if lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } })) |> ignore
      pressed_node(r, press, Is(row_corner), Link, title)
    }
    // what it is by: on its first line where lines are under it (row_lead: as tall as that line at least, across its
    // middle)
    match lead {
      NoLead => ()
      LeadIcon(name) =>
        r.box(fn(l) {
          // (as tall as its first line is drawn at least, the system's size of words applied as it changes, the icon in
          // its middle up and down: row_lead's)
          l
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .min_height(By(fn() {
            if under() {
              l.words_redone() |> ignore
              Some(@ui.current().sp(@ui.tree_theme().text_size(Body).1))
            } else {
              None
            }
          }))
          |> ignore
          icon_node(l, name, row_icon, By(fn() { theme().p.muted })) |> ignore
        })
        |> ignore
      LeadMade(f) => r.box(fn(l) { f(l) }) |> ignore
    }
    // its words: its title (as wide as the row leaves it) and what it says, then its chevron; its note under them, and
    // what is below
    r.box(fn(words) {
      words.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words.box(fn(first) {
        first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
        first.box(fn(t) {
          styled_words(t.grow(Is(1.0)), title, fn() { titled }) |> ignore
          if acts {
            t.ink(By(fn() { link_ink() })) |> ignore
          }
        })
        |> ignore
        first.show(fn() { value() != "" }, fn(said) {
          said.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          said.show(value_dot, fn(d) { status_dot_node(d) })
          said.box(fn(w) {
            styled_words(w, value, fn() { if value_bad() { pg_value.then(bad) } else { pg_value } }) |> ignore
          })
          |> ignore
        })
        if ends {
          icon_node(first, mark, pg_chevron, By(fn() { theme().p.subtle })) |> ignore
        }
      })
      |> ignore
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { pg_link_note }) |> ignore })
      match below {
        Some(f) =>
          words.show(below_shown, fn(room) {
            // (cut by nothing of its own as it opens, as @motion.reveal's room is not: by the card it is on)
            room.opens(By(fn() { Some(dmin(1.0, below_open())) })) |> ignore
            room.box(fn(b) {
              b.row(Is(true)).padding(Is((0.0, 6.0, 0.0, 0.0))).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
              f(b)
            })
            |> ignore
          })
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A red dot (status_dot's "error", as a node): something there is not right though nothing is wrong to say.
fn status_dot_node(d : @view.View) -> Unit {
  d
  .width(Is(Some(status_dot_side)))
  .height(Is(Some(status_dot_side)))
  // (round as a pill is said to be, Full: as round as it can be)
  .radius(Is(1.0e6))
  .ground(By(fn() { theme().p.red }))
  |> ignore
}

///|
/// status_dot_box's side (dot_size).
let status_dot_side : Double = 7.0

///|
/// A switch (switch's, as a node: @kit.switch's look in the web's, switch_look_for), `on()` as it is, named `label`
/// for a screen reader; turned by a tap, a press held however long and let go on it, Space or Enter, a screen reader's
/// press: `turn` told what it is to be (the caller says it so: `on` follows it), a light tick felt under a finger. Its
/// knob slides to its side (switch_ms, eased out) and its track's colour with it, from where it is at that moment;
/// held by a finger, the knob a lens growing as a lift does. In the room a finger's press takes round it, up and down.
pub fn switch_node(parent : @view.View, on : () -> Bool, turn : (Bool) -> Unit, label : () -> String) -> Unit {
  parent.box(fn(at) {
    at.lines_up(Is(Some(Start))) |> ignore
    at.box(fn(v) {
      // (its track in the middle of that room, up and down: switch_reach's)
      v.min_height(By(fn() { Some(theme().items.least) })).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
      let knob = EdgeWay::new(if @signals.untracked(on) { 1.0 } else { 0.0 })
      let held = EdgeWay::new(0.0)
      v.reacts(on, fn(now) { knob.go(v, if now { 1.0 } else { 0.0 }, @kit.switch_ms) })
      v.reacts(fn() { v.pressed() && @ui.pointing() is Finger }, fn(down) {
        held.go_by(v, if down { 1.0 } else { 0.0 }, @motion.lift_spring)
      })
      let press = fn() {
        let to = !@signals.untracked(on)
        if @ui.pointing() is Finger {
          @ui.haptic(TextHandleMove)
        }
        turn(to)
      }
      v
      .presses(Is(true))
      .focusable(Is(true))
      .says(By(fn() { Some(@view.said(Switch, label=label(), check=if on() { On } else { Off })) }))
      .on_press(press)
      |> ignore
      let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
      v.gesture(
        @ui.touch_slop(),
        tap=fn(d) { if on_it(d) { press() } },
        hold=(@ui.long_press_ms, fn(_) {  }),
        drag=fn(d) { if d.kind == Up && on_it(d) { press() } },
      )
      |> ignore
      let size = fn() {
        let r = theme().rows
        (r.switch_w, r.switch_h)
      }
      v.box(fn(track) {
        track
        .width(By(fn() { Some(size().0) }))
        .height(By(fn() { Some(size().1) }))
        .radius(By(fn() { size().1 / 2.0 }))
        .ground(By(fn() {
          let p = theme().p
          @kit.blend(p.line_strong, p.accent, knob.shown(track))
        }))
        |> ignore
        let d = fn() { size().1 - 2.0 * switch_in }
        let travel = fn() { size().0 - 2.0 * switch_in - d() }
        let k = fn() {
          let t = knob.shown(track)
          if @ui.current().rtl() { 1.0 - t } else { t }
        }
        // (held, the knob a lens: wider and larger about its middle, the knob fading under it)
        let lens = fn() { if @ui.current().glass_solid() { 0.0 } else { held.shown(track) } }
        track.box(fn(o) {
          o.over(Is(true)).lines_up(Is(Some(Start))) |> ignore
          o.box(fn(kn) {
            kn
            .width(By(fn() { Some(d()) }))
            .height(By(fn() { Some(d()) }))
            .radius(By(fn() { d() / 2.0 }))
            .ground(Is(0xFFFFFFFFL))
            .shadow(Is((2.0, 1.0, 0x00000033L)))
            .offset(By(fn() { (switch_in + travel() * k(), switch_in) }))
            .alpha(By(fn() { 1.0 - dmin(1.0, lens()) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
        track.show(fn() { lens() > 0.0 }, fn(o) {
          o.over(Is(true)).lines_up(Is(Some(Start))) |> ignore
          o.box(fn(l) {
            let lens_wh = fn() {
              let h = lens()
              let grow = 1.0 + (@kit.knob_lens_grow - 1.0) * h
              (d() * (1.0 + (switch_lens_w - 1.0) * h) * grow, d() * grow)
            }
            l
            .width(By(fn() { Some(lens_wh().0) }))
            .height(By(fn() { Some(lens_wh().1) }))
            .radius(By(fn() { lens_wh().1 / 2.0 }))
            .glass(By(fn() { Some(glass_knob()) }))
            .offset(By(fn() {
              let (lw, lh) = lens_wh()
              let (w, h) = size()
              let mid = switch_in + d() / 2.0 + travel() * k()
              (dmax(0.0, dmin(mid - lw / 2.0, w - lw)), (h - lh) / 2.0)
            }))
            .alpha(By(fn() { dmin(1.0, lens()) }))
            |> ignore
          })
          |> ignore
        })
        // (the keyboard's focus on it: a ring round it, its gap and width the theme's)
        track.show(fn() { v.focus_shown() }, fn(ring) {
          let out = fn() {
            let t = @ui.tree_theme()
            t.focus_gap + t.focus_w
          }
          ring
          .over(Is(true))
          .margin(By(fn() { (-out(), -out(), -out(), -out()) }))
          .radius(By(fn() { size().1 / 2.0 + out() }))
          .edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) }))
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
/// How wide a held knob's lens is, of the knob (switch_look_of's `lens_w`).
let switch_lens_w : Double = 1.45

///|
/// A row on a group's card that turns something on or off (switch_row's, narrow, in a card): its title, `note` quieter
/// under it, its switch at its end across their middle; the switch alone answers. `on`, `turn`: switch_node's.
pub fn switch_row_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  parent.box(fn(r) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    .padding(Is((text_in, text_in, text_in, text_in)))
    .radius(Is(inner_corner(group_corner, list_pad)))
    .min_height(By(fn() { Some(theme().items.least) }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    r.box(fn(words) {
      words.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words.box(fn(t) { styled_words(t, title, fn() { pg_switch_title }) |> ignore }) |> ignore
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { meta.then(full_words) }) |> ignore })
    })
    |> ignore
    switch_node(r, on, turn, title)
  })
  |> ignore
}

///|
/// A block of a page made once (page_node's `content`), in the page's room: 12 from its sides (pg_room), `make` making
/// what it holds.
pub fn page_block(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  parent.box(fn(room) {
    room.padding(Is((pg_room_in, 0.0, pg_room_in, 0.0))) |> ignore
    make(room)
  })
  |> ignore
}
