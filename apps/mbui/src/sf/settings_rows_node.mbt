// The settings pages' small parts made once (the web's parts.tsx StatusDot; a note with its way after it; a station's
// row's lead; the first of something to add, EmptyState's), laid out by the width the page's frame gives it (look_node): the page gives what they say, these how.

///|
/// How something stands, at a glance (status_dot's, as a node): a dot 7 round, online the online green, busy amber,
/// error red, waiting the muted ink, else (offline) a ring 1.5 in it; `state` as it is now.
#callsite(autofill(loc))
pub fn state_dot_node(parent : @view.View, state : () -> String, loc~ : SourceLoc) -> Unit {
  let look = fn() {
    let p = theme().p
    match state() {
      "online" => (p.online, no_ground)
      "busy" => (p.warn_ink, no_ground)
      "error" => (p.red, no_ground)
      "waiting" => (p.muted, no_ground)
      _ => (no_ground, p.muted)
    }
  }
  parent.box(made_for=loc, fn(d) {
    d
    .width(Is(Some(dot_across)))
    .height(Is(Some(dot_across)))
    // (round as a pill is said to be, Full: as round as it can be)
    .radius(Is(1.0e6))
    .ground(By(fn() { look().0 }))
    .edge(By(fn() {
      match look() {
        (_, ring) if ring != no_ground => (status_ring, ring)
        _ => (0.0, 0L)
      }
    }))
    |> ignore
  })
  |> ignore
}

///|
/// status_dot's across (dot_size).
let dot_across : Double = 7.0

///|
/// What is before a station's name in its row (the web's StationRow): wide, whether it is online, then its mark where it
/// has one; narrow, its mark alone; 8 apart, across the middle of its name's line; each as it is now.
pub fn station_lead(online : () -> Bool, emoji : () -> String, icon : () -> String, stint : () -> Int) -> RowLead {
  LeadMade(fn(l) {
    l.row(Is(true)).gap(Is(station_lead_gap)).lines_up(Is(Some(Middle))) |> ignore
    match look_node(l) {
      // (wide: as tall as a list's title's line at least, a lead icon's row_lead's)
      Wide => {
        l
        .min_height(By(fn() {
          l.words_redone() |> ignore
          Some(node_sp(l, @ui.tree_theme().leading(L6).unwrap_or(@ui.tree_theme().text_size(Ui).1)))
        }))
        |> ignore
        state_dot_node(l, fn() { if online() { "online" } else { "offline" } })
      }
      // (narrow: as tall as its name's line at least, the system's size of words applied as it changes)
      Narrow =>
        l
        .min_height(By(fn() {
          l.words_redone() |> ignore
          Some(node_sp(l, @ui.tree_theme().text_size(Body).1))
        }))
        |> ignore
    }
    l.show(fn() { has_station_mark(emoji(), icon()) }, fn(m) {
      station_mark_node(m, emoji, icon, row_mark, fn() { theme().p.text }, stint)
    })
  })
}

///|
let station_lead_gap : Double = 8.0

///|
/// What a part says with the way to more of it after its words (a station's review and 去设置): narrow, in a page
/// note's room (12 in, 8 over, 4 under), its words the note's, the way under them, or `inline` on their line after them
/// (one line, the secondary's); wide, 8 over its words (the meta's muted, 624 at most) and the way under them, or
/// `inline` beside them on one line. The way in the link's ink, 12, pressed `press`. As each says it now.
#callsite(autofill(loc))
pub fn note_link_node(
  parent : @view.View,
  words : () -> String,
  link : () -> String,
  press : () -> Unit,
  inline? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  let narrow = look_node(parent) is Narrow
  parent.box(made_for=loc, fn(n) {
    if narrow {
      n.padding(Is((note_link_x, note_link_top, note_link_x, note_link_foot))) |> ignore
    } else if !inline {
      n.padding(Is((0.0, note_link_top, 0.0, 0.0))).gap(Is(note_link_gap)) |> ignore
    }
    let said = fn(w : @view.View) {
      let style = match (narrow, inline) {
        (true, false) => pg_note
        (true, true) => note_link_inline_narrow
        (false, false) => desk_hint_words
        (false, true) => note_link_inline_wide
      }
      styled_words(w, words, fn() { style }) |> ignore
    }
    if inline {
      n.box(fn(line) {
        line.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        line.box(fn(w) { said(w) }) |> ignore
        tap_text_node(line, link, press, size=note_link_size)
      })
      |> ignore
    } else {
      n.box(fn(w) { said(w) }) |> ignore
      n.box(fn(l) {
        l.lines_up(Is(Some(Start))) |> ignore
        tap_text_node(l, link, press, size=note_link_size)
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// note_link's room narrow (pg_note_box's: px=S3, pt=S2, pb=S1), over it wide (desk_hint_line's pt=S2), between its
/// words and its way wide (gap=S1); its way's size (12).
let note_link_x : Double = 12.0

///|
let note_link_top : Double = 8.0

///|
let note_link_foot : Double = 4.0

///|
let note_link_gap : Double = 4.0

///|
let note_link_size : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let note_link_inline_narrow : @ui.TextStyle = secondary.then(one_line)

///|
// kept across runs: a value (no field of it changes)
let note_link_inline_wide : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// A row on a group's card that undoes what is not got back (关闭安全模式: a page's narrow foot), as an old view's row of
/// the body's words in red: lit under the hand, rippling under a finger, `press` done as it is pressed; while `busy`
/// says, a spinner after its words and pressed none, lit none. Read out a button named `title`.
#callsite(autofill(loc))
pub fn danger_row_node(
  parent : @view.View,
  title : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  @headless.button(made_for=loc, parent, title, fn(_) { press() }, disabled=busy, fn(r, b) {
    r
    .row(Is(true))
    .gap(Is(12.0))
    .padding(Is((text_in, text_in, text_in, text_in)))
    .radius(Is(@ui.concentric(group_corner, list_pad)))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if !b.disabled() && lit_node(r) { @ui.tree_theme().color(Hover) } else { 0L } }))
    |> ignore
    let rippled = press_look(r, Is(row_corner), fn() { false })
    let on_it = fn(d : @view.Drag) { r.finger_target(d.wx, d.wy) }
    r.gesture(
      @ui.touch_slop(),
      press=fn(d) { if !b.disabled() { (rippled.down)(d) } },
      tap=fn(d) {
        (rippled.tapped)(d)
        if on_it(d) {
          b.press()
        }
      },
      drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && on_it(d) { b.press() } },
    )
    |> ignore
    words_node(r, title, fn() { danger_row_words }) |> ignore
    r.show(busy, fn(s) { spinner_node(s, size=danger_row_spin) |> ignore })
  })
  |> ignore
}

///|
/// A danger row's words (the body's in red) and its spinner (14).
// kept across runs: a value (no field of it changes)
let danger_row_words : @ui.TextStyle = body.then(bad)

///|
let danger_row_spin : Double = 14.0

///|
/// The first of something to add (first_one's, as a node: StationsFirst, ProfilesFirst) in `parent`: `art` over its
/// `title` and what it is for (`lead`), the ways to add it (`actions`) under them, all in the middle of the room, as wide
/// as first_most at most.
#callsite(autofill(loc))
pub fn first_one_node(
  parent : @view.View,
  title : () -> String,
  actions : (@view.View) -> Unit,
  art? : (@view.View) -> Unit,
  lead? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { first_room })
    r.box(fn(b) {
      style_node(b, fn() { first_box })
      match art {
        Some(f) => f(b)
        None => ()
      }
      b.box(fn(t) {
        style_node(t, fn() { first_title_at })
        words_node(t, title, fn() { first_title }) |> ignore
      })
      |> ignore
      b.show(fn() { lead() != "" }, fn(l) {
        style_node(l, fn() { first_lead_box })
        words_node(l, lead, fn() { first_lead }) |> ignore
      })
      b.box(fn(a) {
        style_node(a, fn() { first_actions })
        actions(a)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
