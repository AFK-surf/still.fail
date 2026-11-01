// The way in as nodes of the window's tree (way_in's, way_in_page's and their parts' made-once form): a page of the way
// in, its picture's foot a little over the page's middle whatever is under it; its title, what it says, its buttons
// (the ink's pill across a touch screen's page, 300 on a desktop's; a spinner's room opening before their words at
// work, their words changed going to their place; a press's ripple), what it says of signing in under its button
// opening and closing with its room, and what it says last.

///|
/// A page of the way in in `parent` (way_in_page's): its picture (`art`, a drawable) over what `body` says and offers,
/// all of it down the middle of the page, 30 in from its sides; the picture as wide as a button at most and never past
/// the page's sides, its foot 0.42 of the way down the page and 12 more (as the old one's room above it puts it) or,
/// where that leaves no room above it, 52 down. What `body` is given: a column 12 apart, its things in its middle, no
/// wider than a tablet's button. The page's node.
pub fn way_in_page_node(parent : @view.View, art : () -> String, body : (@view.View) -> Unit) -> @view.View {
  parent.box(fn(page) {
    page
    .width_share(Is(1.0))
    .height_share(Is(1.0))
    .padding(Is((sign_in_side_w, 0.0, sign_in_side_w, 0.0)))
    .gap(Is(@ui.Space::px(S3)))
    .lines_up(Is(Some(Middle)))
    |> ignore
    // (where the old one's room above its picture was: nothing tall, the page's gap after it, the picture's foot where
    // the page's share and that gap put it, or as low as its top and its own height do where that is lower)
    page.box(fn(g) { g.height(Is(Some(0.0))) |> ignore }) |> ignore
    page.box(fn(head) {
      head
      .width_share(Is(1.0))
      .min_height_share(Is(Some(way_in_picture_foot)))
      .padding(Is((0.0, way_in_page_top, 0.0, 0.0)))
      .lines_up(Is(Some(Middle)))
      |> ignore
      head.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      // (as wide as the page's column at most and a button's: the picture as wide as that, as tall as it is drawn so)
      head.box(fn(room) {
        room.width_share(Is(1.0)).max_width(Is(Some(sign_in_picture_w))) |> ignore
        room.box(fn(p) {
          p
          .width_share(Is(1.0))
          .aspect(By(fn() { way_in_art_aspect(art()) }))
          .picture(By(fn() { drawable_vector(art()) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    page.box(fn(col) {
      col
      .width_share(Is(1.0))
      .max_width(Is(Some(sign_in_touch_w)))
      .gap(Is(@ui.Space::px(S3)))
      .lines_up(Is(Some(Middle)))
      .padding(Is((0.0, 0.0, 0.0, way_in_page_top)))
      |> ignore
      body(col)
    })
    |> ignore
  })
}

///|
/// How wide drawable `name` is for how tall (1: none so named, drawn square).
fn way_in_art_aspect(name : String) -> Double {
  match drawables.get(name) {
    Some(d) if d.h > 0.0 => d.w / d.h
    _ => 1.0
  }
}

///|
/// The words of a way-in page's part, as `size`, `weight` and `line` say in the window's theme (None: the size's own
/// line; the font's: none said, the font's own, as an old view's text sets it), wrapping or not.
fn way_in_words(size : @ui.TextSize, weight : Int, line : @ui.Leading?, wrap : Bool) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  let line = match line {
    None => own
    Some(l) => th.leading(l).unwrap_or(0.0)
  }
  { size: px, weight, line, wrap }
}

///|
/// A way-in page's title in `body` (way_in_title's): 10 under what is above it, 28, bold, in the ink, in its middle,
/// as wide as the page's column. The node.
pub fn way_in_title_node(body : @view.View, title : () -> String) -> @view.View {
  body.box(fn(b) {
    b.width_share(Is(1.0)).padding(Is((0.0, @ui.Space::px(S2_5), 0.0, 0.0))) |> ignore
    b.box(fn(w) {
      w
      .width_share(Is(1.0))
      .words(By(title), look=way_in_words(sign_in_title_size, 700, Some(Font), true))
      .words_centered(Is(true))
      .ink(By(fn() { @ui.tree_theme().color(Fg) }))
      |> ignore
    })
    |> ignore
  })
}

///|
/// What a way-in page says under its title in `body` (way_in_note's): the body's size, muted, in its middle. The node.
pub fn way_in_note_node(body : @view.View, note : () -> String) -> @view.View {
  body.box(fn(w) {
    w
    .width_share(Is(1.0))
    .words(By(note), look=way_in_words(Body, 400, None, true))
    .words_centered(Is(true))
    .ink(By(fn() { @ui.tree_theme().color(Muted) }))
    |> ignore
  })
}

///|
/// A way-in page's button in `body` (way_in_button's): 50 high, a pill across a touch screen's page (420 at most), 300
/// on a desktop's; `solid` the ink's, the one thing to do, a step towards the page under the pointer or pressed, else
/// the quiet ground of the words' colour, a step darker so; `busy` while what it does is under way: a spinner's room
/// opening before its words (a Move, as a button's), the spinner turning in it, not pressed. A press's ripple from
/// where it went down, the pill sinking under it. Its words changed, they go to their new place (moves_together, by
/// its words). `press` done as it is pressed. Read out a button. The node.
pub fn way_in_button_node(
  body : @view.View,
  label : () -> String,
  press : () -> Unit,
  solid? : Bool = true,
  busy? : () -> Bool = fn() { false },
) -> @view.View {
  let bare = native_input() is Mouse
  body.box(fn(v) {
    let theme = fn() { @ui.tree_theme() }
    let lit = fn() {
      match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      }
    }
    let ground = fn() {
      let t = theme()
      match (solid, lit()) {
        (true, false) => t.color(Fg)
        (true, true) => t.color(Over(Fg, A(Bg, O15)))
        (false, false) => t.color(Tint)
        (false, true) => t.color(TintStrong)
      }
    }
    let ink = fn() { theme().color(if solid { Bg } else { Fg }) }
    let turning = EdgeWay::new(if @signals.untracked(busy) { 1.0 } else { 0.0 })
    let open = EdgeWay::new(if @signals.untracked(busy) { 1.0 } else { 0.0 })
    v.reacts(busy, fn(on) {
      turning.go(v, if on { 1.0 } else { 0.0 }, dur_ms)
      open.go_by(v, if on { 1.0 } else { 0.0 }, button_reshape)
    })
    v.owns(fn() {
      for w in [turning, open] {
        (w.due)()
      }
    })
    |> ignore
    let live = fn() { !busy() }
    v
    .row(Is(true))
    .width_share(Is(1.0))
    .max_width(Is(Some(if bare { sign_in_desk_w } else { sign_in_touch_w })))
    .height(Is(Some(sign_in_button_h)))
    // (a pill: as round as it can be, as the old one's radius=Full)
    .radius(By(fn() { theme().corner(Full) }))
    .lines_up(Is(Some(Middle)))
    .ground(By(ground))
    .presses(By(live))
    .focusable(By(live))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    .on_press(fn() {
      if @signals.untracked(live) {
        press()
      }
    })
    |> ignore
    // (what it holds in its middle: the old one's justify=JCenter)
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    v.show(fn() { busy() || open.shown(v) > 0.0 }, fn(room) {
      room
      .width(By(fn() { Some((button_icon + sign_in_spin_gap) * dmax(open.shown(v), 0.0)) }))
      .height(Is(Some(button_icon)))
      |> ignore
      // (in the library's palette's ink and accent, as the old one's spinner is: way_in_button's p.bg, p.text)
      let spun_ink = fn() {
        let p = library_theme().p
        if solid {
          p.bg
        } else {
          p.text
        }
      }
      let s = spinner_node(
        room,
        size=button_icon,
        ring=fn() { alpha(spun_ink(), 0.3) },
        arc=fn() { if solid { spun_ink() } else { library_theme().p.accent } },
      )
      s.alpha(By(fn() { turning.shown(v) })).scale(By(fn() { dmax(open.shown(v), 0.0) }), about=At(0.0, 0.5)) |> ignore
    })
    let words = v.box(fn(w) {
      w.words(By(label), look=way_in_words(Title, 600, Some(Font), false)).ink(By(ink)) |> ignore
    })
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    // (a press's ripple from where it went down, the pill sinking under it: SignIn.kt's clip(CircleShape).clickable)
    let rippled = press_look(v, Is(sign_in_button_h / 2.0), fn() { true })
    v.gesture(
      @ui.touch_slop(),
      press=fn(d) {
        if @signals.untracked(live) {
          rippled(d)
        }
      },
      tap=fn(d) {
        if v.finger_target(d.wx, d.wy) && @signals.untracked(live) {
          press()
        }
      },
      drag=fn(d) {
        // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
        if d.kind == Up && @ui.pointing() is Mouse && v.finger_target(d.wx, d.wy) && @signals.untracked(live) {
          press()
        }
      },
    )
    |> ignore
    // (its words changed, 登录或注册 to 正在登录: gone to their new place, not at once)
    let g = @motion.moves_together(v, label, spec=button_reshape)
    g.add(words)
  })
}

///|
/// What a way-in page offers last, quietly, in `body` (way_in_link's: 切换账号): a button of words alone, the page's ink,
/// a ground under the pointer. The node.
pub fn way_in_link_node(body : @view.View, label : () -> String, press : () -> Unit, busy? : () -> Bool = fn() { false }) -> @view.View {
  button_node(body, label, press, tone=Ghost, busy~)
}

///|
/// The way into an app, signed out, in `parent` (way_in's): its picture (`art`), what it is (`title`, `note`), its button
/// (`label`; `busy` while it is under way), what to know of it (`foot`), and what there is to say of signing in under
/// the button (`said`: what it waits on, or why it failed, in the red), coming and going with its room (its words kept as
/// it closes). Keyboard and mouse's the picture, the button and what is said of it alone; a touch screen's all of it.
/// `press` done as its button is pressed. The page's node.
pub fn way_in_node(
  parent : @view.View,
  art : () -> String,
  title : () -> String,
  note : () -> String,
  label : () -> String,
  foot : () -> String,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
  said? : () -> (String, Bool) = fn() { ("", false) },
) -> @view.View {
  let bare = native_input() is Mouse
  way_in_page_node(parent, art, fn(col) {
    if !bare {
      way_in_title_node(col, title) |> ignore
      way_in_note_node(col, note) |> ignore
    }
    col.box(fn(g) { g.height(Is(Some(@ui.Space::px(S1_5)))) |> ignore }) |> ignore
    way_in_button_node(col, label, press, busy~) |> ignore
    // (what was last said, kept as its room closes under it)
    let kept = @signals.signal(@signals.untracked(said), same=fn(a, b) { a == b })
    col.reacts(said, fn(s) {
      if s.0 != "" {
        kept.set(s)
      }
    })
    let room = @motion.reveal_node(col, fn() { said().0 != "" }, fn(r) {
      r.box(fn(w) {
        w
        .width_share(Is(1.0))
        .words(By(fn() { kept.get().0 }), look=way_in_words(Meta, 400, None, true))
        .words_centered(Is(true))
        .ink(By(fn() { @ui.tree_theme().color(if kept.get().1 { Danger } else { Muted }) }))
        |> ignore
      })
      |> ignore
    })
    // (as wide as the page's column, as the old one's room: what it holds in its middle, cut at its sides)
    room.width_share(Is(1.0)) |> ignore
    if !bare {
      col.box(fn(f) {
        f.words(By(foot), look=way_in_words(Meta, 400, Some(Font), false)).ink(By(fn() { @ui.tree_theme().color(Muted) })) |> ignore
      })
      |> ignore
    }
  })
}

///|
/// The library's theme (theme's: its palette), where a part calls the window's tree's its `theme`.
fn library_theme() -> Theme {
  theme()
}
