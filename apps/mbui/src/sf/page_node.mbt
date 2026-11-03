// A page's parts (page.mbt) as nodes of the window's tree, made once: its frame (back over its large title, what it is
// for, its blocks in the page's room, all of it scrolling), a heading, a group's card and the rows on it that go
// somewhere (link_row's), each as page.mbt draws it, its styles the same (their words through @ui.style_words), what
// changes bound to what it is told: the frame's back and room, the words, the language, the theme. A page made so is
// laid out as wide as its frame gives it (look_for that width), made again only as that arrangement changes; it lends
// it to all it holds (View::lends), and each part reads it from where it is made (look_node, part_of), never as it is
// drawn: narrow here, wide in page_wide_node.mbt.

///|
/// Whether the hand is on `v` as the theme answers it: a mouse over it or pressing it, a finger pressing it; the
/// keyboard's focus shown on it (what lights a row, a button: c.lit's).
pub fn lit_node(v : @view.View) -> Bool {
  v.focus_shown() ||
  (match @ui.pointing() {
    Mouse => v.pointed() || v.pressed()
    Finger => v.pressed()
  })
}

///|
/// `v` pressed as an old view's box with an id is (a tap on it, a mouse's let go on it, Enter or Space with the
/// keyboard's focus on it, a screen reader's Activate), `press` done then; while `on` says so (a box given no id: none
/// of these). Nothing drawn of it: what it draws as the hand is on it is its own (lit_node).
pub fn presses_node(v : @view.View, press : () -> Unit, on? : () -> Bool = fn() { true }) -> Unit {
  // (taken by the keyboard's focus as it is pressed: an old view's box with an id)
  v.presses(By(on)).focusable(By(on)).on_press(press) |> ignore
  let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
  v.gesture(
    @ui.touch_slop(),
    tap=fn(d) { if on_it(d) { press() } },
    drag=fn(d) { if d.kind == Up && @ui.pointing() is Mouse && on_it(d) { press() } },
  )
  |> ignore
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
    // (cut short where their line has not the room across: given way along a row, never squeezed down, View::cuts)
    w.cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
  }
  w
}

///|
/// What a page made once holds, in its order (page_node's): what stands over it, back, its large title, what it is for,
/// its blocks by their keys, the room at its foot.
priv enum PageItem {
  Top
  Back
  Title
  Lead
  Block(String)
  Foot
} derive(Eq, Hash)

///|
/// A page titled `title` in node `v` (page's, as nodes), laid out as a page as wide as its frame gives it is (`width`:
/// look_for that width, never what it holds as last laid out; none given, narrow): narrow (narrow_page_node) or wide
/// (wide_page_node), made again only as the arrangement changes, what it shows in either bound to what it is told.
/// Its arrangement lent to all of it, what comes to be shown in it later as well (look_node, part_of): its parts take
/// their form from where they are made, nothing said round their making. In either: back where the frame says it goes
/// (`on_back` as it is pressed), its title, what it is for (`lead`) under it, what it does (`actions`) at its title's
/// line's end, then its blocks, those `blocks` names now by their keys, each made by `block`, then the frame's room at
/// its foot; all of it scrolling in the page, each part made only while it shows (View::scrolls_window). What it says
/// of itself told `said` as that changes (a frame's bar that names it: its title, and what it is for by a mark beside
/// it, `about`). Where its list is scrolled to its own, the same through its arrangements, or kept by whoever holds it
/// (`scroll`: a page of parts, each part's page its own as it was left).
pub fn page_node(
  v : @view.View,
  title : () -> String,
  blocks : () -> Array[String],
  block : (@view.View, String) -> Unit,
  on_back~ : () -> Unit,
  frame? : () -> PageFrame = fn() { no_frame },
  lead? : () -> String = fn() { "" },
  about? : () -> String = fn() { "" },
  actions? : (@view.View) -> Unit,
  said? : (PageSaid) -> Unit,
  width? : () -> Double,
  scroll? : @view.Scroll,
  tips? : TipLayer,
) -> Unit {
  // (what it says of itself to the frame's bar that names it, as that changes, whole: the frame's own to keep)
  match said {
    Some(f) => v.reacts(fn() { { title: title(), about: about() } }, f)
    None => ()
  }
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  let look = match width {
    Some(w) => fn() { look_for(w()) }
    None => fn() { Narrow }
  }
  // (a page's list: it moves as the platform's lists do, its slop the host's)
  let own_scroll = @view.Scroll::list()
  // (what is said of what the pointer rests on, its about's mark's: in a layer of its own over the page, past its list,
  // which cuts what it holds to it)
  // (the frame's, over all of the window where it gives one; else its own)
  let tips_at : Ref[@view.View?] = Ref(None)
  let own_tips = tips is None
  let tips = match tips {
    Some(t) => t
    None => TipLayer::new(fn() { tips_at.val })
  }
  v.pick(look, fn(p, l) {
    p.grow(Is(1.0)).min_height(Is(Some(0.0))).lends(part_at, { look: l, section: false, list: false }) |> ignore
    // (where its list is scrolled to, kept by whoever holds the page where it says (a part of a page a page each,
    // each as it was left), else the page's own; the same through its arrangements)
    let scroll = match scroll {
      Some(s) => s
      None => own_scroll
    }
    match l {
      Narrow => narrow_page_node(p, title, blocks, block, on_back, frame, lead, actions, scroll)
      Wide => wide_page_node(p, title, blocks, block, on_back, frame, lead, actions, scroll, about, tips)
    }
  })
  // (its own layer only where it has what is for by a mark to say: nothing over a page that has none)
  if own_tips {
    v.show(fn() { about() != "" }, fn(t) {
      t.over(Is(true)) |> ignore
      tips_at.val = Some(t)
    })
  }
}

///|
/// Where a part of a page made once is (page_node's, lent to all of it): how the page is laid out, whether it is in a
/// section of a wide page (wide_alone's), and whether on a list's card (its rows a wide list's: wide_in_list's).
priv struct PartAt {
  look : Look
  section : Bool
  list : Bool
}

///|
// kept across runs: what each page made once lends (View::lends), let go with it
let part_at : @view.Lent[PartAt] = @view.Lent::new()

///|
/// Where node `v` of a page made once is (page_node's: lent it); narrow, in nothing, outside one.
fn part_of(v : @view.View) -> PartAt {
  v.lent(part_at).unwrap_or({ look: Narrow, section: false, list: false })
}

///|
/// What is made in node `v` laid out as a page laid out `look` lays out its parts (what a frame puts by a page made once,
/// as its page is: a bar's actions), in no section or list of it.
pub fn look_lent(v : @view.View, look : Look) -> Unit {
  v.lends(part_at, { look, section: false, list: false }) |> ignore
}

///|
/// What a page made once does, put in a pane's bar by the frame (the tape's), made in node `v`: laid out as a wide
/// page's are whatever the page's width (the old pane bar called them outside the page's look: Wide where none is said).
pub fn pane_bar_actions_lent(v : @view.View) -> Unit {
  look_lent(v, Wide)
}

///|
/// How tall what a page made once does stands in a pane's bar (pane_bar_actions_lent's look), as the page says it
/// (`side`, by the look it is laid out in).
pub fn pane_bar_actions_side(side : (Look) -> Double) -> Double {
  side(Wide)
}

///|
/// What a page made once does, put in a phone's top bar at its end by the frame (a place's), made in node `v`: laid out
/// as a narrow page's at a head's end are (the old top bar's with_look(Narrow, …), head_end's).
pub fn top_bar_actions_lent(v : @view.View) -> Unit {
  look_lent(v, Narrow)
}

///|
/// How the page node `v` is in is laid out (page_node's), narrow outside one: what a part made in it reads as it is
/// made, however late.
pub fn look_node(v : @view.View) -> Look {
  part_of(v).look
}

///|
/// A narrow page made once (narrow_page's) in node `v`: under what stands over it as the frame says (`frame`'s top),
/// back where the frame says it goes (TopBack: its chevron and its words), its large title (as far down as a wide
/// page's head where nothing is over it), what it is for under it, what it does in its title's line after the title,
/// at its end, scrolling with it, then its blocks in the page's room (page_block), and 30 under the last, then the
/// frame's room at its foot; each part made only while it shows (as narrow_list's old list builds only the rows in
/// view).
fn narrow_page_node(
  v : @view.View,
  title : () -> String,
  blocks : () -> Array[String],
  block : (@view.View, String) -> Unit,
  on_back : () -> Unit,
  frame : () -> PageFrame,
  lead : () -> String,
  actions : ((@view.View) -> Unit)?,
  scroll : @view.Scroll,
) -> Unit {
  let items = fn() -> Array[PageItem] {
    let f = frame()
    let out = []
    if f.top > 0.0 {
      out.push(Top)
    }
    if f.back is Some(_) {
      out.push(Back)
    }
    if !f.named {
      out.push(Title)
    }
    if lead() != "" {
      out.push(Lead)
    }
    for k in blocks() {
      out.push(Block(k))
    }
    out.push(Foot)
    out
  }
  v.box(fn(sc) {
    sc.grow(Is(1.0)) |> ignore
    sc.scrolls_window(scroll, items, bar=@ui.tree_scroll_bar(), est=pg_block_est, fn(s, item) {
      with_look(Narrow, fn() {
        match item {
          // under what stands over it (a status bar)
          Top => s.height(By(fn() { Some(frame().top) })) |> ignore
          // back to where it was opened from
          Back => {
            s.row(Is(true)).padding(Is((pg_back_x, pg_back_top, pg_back_x, pg_back_foot))).lines_up(Is(Some(Middle)))
            |> ignore
            nav_back_node(s, fn() { frame().back.unwrap_or("") }, on_back)
          }
          // its large title (a place's top page: none, the frame's bar names it)
          Title => {
            s
            .padding(By(fn() {
              let f = frame()
              let alone = f.back is None && f.top <= 0.0
              (pg_title_x, if alone { pg_title_alone_top } else { 0.0 }, pg_title_x, pg_title_foot)
            }))
            |> ignore
            s.box(fn(l) {
              // (one line while its title at its least and what it does at the least that comes to have the room
              // beside each other; else what it does, all of it, under the title at the same end, the line's end:
              // View::wraps_at_least, from the least each part says of itself as it is laid out)
              l
              .row(Is(true))
              .gap(Is(pg_title_gap))
              .wraps(Is(Some(pg_title_lines)))
              .wraps_at_least(Is(true))
              .lies_along(Is(End))
              .lines_up(Is(Some(Middle)))
              |> ignore
              l.box(fn(w) {
                // (as wide as its words, sharing the line's lack with what is at its end by their widths, 80 at least:
                // pg_title_words' in a row; alone in its line, all of it)
                w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(pg_title_least))) |> ignore
                w.box(fn(t) { styled_words(t, title, fn() { pg_title }) |> ignore }) |> ignore
              })
              |> ignore
              // what it does at its line's end (head_end's: a row of them each 10 apart, as the title's line has them),
              // giving way first where the line has not the room, each down to the least it says: its title kept whole
              match actions {
                Some(f) =>
                  l.box(fn(a) {
                    a.row(Is(true)).gap(Is(pg_title_gap)).lines_up(Is(Some(Middle))).shrink(Is(1.0)) |> ignore
                    f(a)
                  })
                  |> ignore
                None => ()
              }
            })
            |> ignore
          }
          // what it is for
          // (a block of the page's, in its room as the rest: narrow_page's)
          Lead =>
            page_block(s, fn(room) {
              room.box(fn(l) {
                l.padding(Is((pg_lead_x, 0.0, pg_lead_x, pg_lead_foot))) |> ignore
                l.box(fn(w) { styled_words(w, lead, fn() { pg_lead }) |> ignore }) |> ignore
              })
              |> ignore
            })
          // what it holds, each block in the page's room
          Block(k) => page_block(s, fn(room) { block(room, k) })
          // 30 under the last, then the frame's room
          Foot => s.height(By(fn() { Some(pg_foot + frame().foot) })) |> ignore
        }
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// How tall a page's part is counted before it was first laid out (narrow_list's old list's).
let pg_block_est : Double = 80.0

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
/// How far under its title's line what a page does is where that line has not the room for both (page_node's).
let pg_title_lines : Double = 6.0

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
/// Rows together on a list card (group's), `rows` made in it: narrow, ListCard (10 under it, its rows `list_pad` in, its
/// corner the list card's); wide, wide_group_node's (a list card, or a `card` of words).
pub fn group_node(parent : @view.View, rows : (@view.View) -> Unit, card? : Bool = false) -> Unit {
  let at = part_of(parent)
  if at.look is Wide {
    wide_group_node(parent, at, rows, card)
    return
  }
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
/// What a row says after its title of whose or what it is (a tag: link_row_node's `title_after`), `words` as it says
/// it now: the meta's size, subtle, on one line (memoryTag).
pub fn row_tag_node(parent : @view.View, words : () -> String) -> Unit {
  words_node(parent, words, fn() { row_tag }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let row_tag : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Subtle, wrap=false)

///|
/// A row on a group's card that goes somewhere (link_row's, narrow, in a card): `lead` before its title (`strong`
/// where it names who or what it is), what it says at its end (`value`, in red where `value_bad`, a red dot before it
/// where `value_dot`) and a chevron (none where not `chevron`; an arrow out where it goes `out` of the app); `note` under
/// its title, a line of its own as wide as its words, its end then on its first line, its lead across that line's
/// middle; `below` under that while `below_open` says it is any of the way open (a room opening on it, its row growing
/// round it: @motion.reveal's). One that `acts` (does something at once where it is): its title in the link's ink, no
/// chevron. Lit under the hand, rippling under a finger, `press` done as it is pressed; going nowhere where not `goes`
/// (a value said: none of that). `note_cut`: its note one line, cut short (what is in a memory). `title_after` after its
/// title on its line while `title_after_shown` says (a tag: whose it is), its title cut short where the line has not
/// the room for both. `folds`: it
/// folds open what follows it, its chevron down, up while that is open (as it says), read out so. Its words as they are
/// said.
pub fn link_row_node(
  parent : @view.View,
  title : () -> String,
  press : () -> Unit,
  value? : () -> String = fn() { "" },
  value_bad? : () -> Bool = fn() { false },
  value_dot? : () -> Bool = fn() { false },
  note? : () -> String = fn() { "" },
  wide_note? : () -> String,
  trouble? : () -> String = fn() { "" },
  strong? : Bool = false,
  lead? : RowLead = NoLead,
  goes? : Bool = true,
  chevron? : Bool = true,
  out? : Bool = false,
  acts? : Bool = false,
  below? : (@view.View) -> Unit,
  below_open? : () -> Double = fn() { 0.0 },
  note_cut? : Bool = false,
  title_after? : (@view.View) -> Unit,
  title_after_shown? : () -> Bool = fn() { true },
  folds? : () -> Bool,
) -> Unit {
  // (words under its first line: a note, what is wrong, what may be below it, open or not: link_row's `under`)
  let under = fn() { note() != "" || trouble() != "" || below is Some(_) }
  let titled = if strong { pg_row_title.then(row_strong) } else { pg_row_title }
  let titled_in = if strong { pg_row_title_in.then(row_strong) } else { pg_row_title_in }
  // (its chevron: down where it folds what follows it, up while that is open, as link_row's `folds`)
  let mark = fn() {
    match (out, folds) {
      (true, _) => "arrow-up-right"
      (false, Some(open)) => if open() { "chevron-up" } else { "chevron-down" }
      (false, None) => "chevron-right"
    }
  }
  let ends = goes && (out || (chevron && !acts))
  if look_node(parent) is Wide {
    // (its note as a wide page says it, where it says it otherwise: `wide_note`)
    let note = match wide_note {
      Some(w) => w
      None => note
    }
    wide_link_row_node(
      parent, title, press, value, value_bad, value_dot, note, trouble, strong, lead, goes, ends, mark, acts, below, below_open,
      note_cut, title_after, title_after_shown, folds,
    )
    return
  }
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
      row_folds_said(r, title, folds)
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
      // (as wide as the row leaves it, narrower where what it holds is wider: its words wrapped there, as a row's are)
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words.box(fn(first) {
        first.row(Is(true)).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
        // with words under it, its title and what it says in a line, what it says under the title where the line has not
        // the room (pg_title_value, a row in lines: its ends the title's and what it says'); else all of it on one line,
        // its title giving way (link_row's `!under`)
        first.box(fn(tv) {
          tv
          .grow(Is(1.0))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          .row(Is(true))
          .gap(Is(12.0))
          .wraps(By(fn() { if under() && value() != "" { Some(0.0) } else { None } }))
          .lines_up(Is(Some(Middle)))
          |> ignore
          tv.box(fn(t) {
            // (giving way to what it says where the line has not the room, cut short, as link_row's title in a row does;
            // beside what it says, its words' own (pg_row_title_in), the line's room left between them: its line's ends
            // the title's and what it says')
            t.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
            let plain = fn() { if under() && value() != "" { titled_in } else { titled } }
            // (what follows its title on its line while it is said, 8 apart across their middle: the title cut short
            // where the line leaves it less, link_row's title_line; its title the same words all along)
            let after_now = fn() { title_after is Some(_) && title_after_shown() }
            t.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
            t.box(fn(w) {
              w.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              styled_words(w, title, fn() {
                if after_now() || (note_cut && value() == "") { plain().then(cut_words) } else { plain() }
              })
              |> ignore
              if acts {
                w.ink(By(fn() { link_ink() })) |> ignore
              }
            })
            |> ignore
            match title_after {
              Some(after) =>
                t.show(title_after_shown, fn(a) {
                  a.margin(Is((8.0, 0.0, 0.0, 0.0))) |> ignore
                  after(a)
                })
              None => ()
            }
          })
          |> ignore
          tv.show(fn() { value() != "" }, fn(said) {
            said.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
            said.show(value_dot, fn(d) { status_dot_node(d) })
            said.box(fn(w) {
              styled_words(w, value, fn() { if value_bad() { pg_value.then(bad) } else { pg_value } }) |> ignore
            })
            |> ignore
          })
        })
        |> ignore
        if ends {
          icon_node(first, mark(), pg_chevron, By(fn() { theme().p.subtle }), name_now=mark) |> ignore
        }
      })
      |> ignore
      words.show(fn() { note() != "" }, fn(n) {
        styled_words(n, note, fn() { if note_cut { pg_link_note.then(cut_words) } else { pg_link_note } }) |> ignore
      })
      // (what is wrong, in red under it: link_row's `trouble`)
      words.show(fn() { trouble() != "" }, fn(n) { styled_words(n, trouble, fn() { pg_link_note.then(bad) }) |> ignore })
      match below {
        Some(f) => row_below_node(words, f, below_open)
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row that `folds` what follows it read out as open or not, as it says (link_row's `expanded`), named `title`.
fn row_folds_said(r : @view.View, title : () -> String, folds : (() -> Bool)?) -> Unit {
  match folds {
    Some(open) => r.says(By(fn() { Some(@view.said(Link, label=title(), expanded=open())) })) |> ignore
    None => ()
  }
}

///|
/// What a row has below its note (row_below's: 6 under it, as wide as its words, what is in it 6 apart), `make` making
/// it, there while `open` says it is any of the way open, its room opening with it (@motion.reveal's).
fn row_below_node(words : @view.View, make : (@view.View) -> Unit, open : () -> Double) -> Unit {
  words.show(fn() { open() > 0.0 }, fn(room) {
    // (cut by nothing of its own as it opens, as @motion.reveal's room is not: by the card it is on)
    room.opens(By(fn() { Some(dmin(1.0, open())) })) |> ignore
    room.box(fn(b) {
      b.row(Is(true)).padding(Is((0.0, 6.0, 0.0, 0.0))).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
      make(b)
    })
    |> ignore
  })
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
/// A row on a group's card that turns something on or off (switch_row's; narrow, in a card: its title, `note` quieter
/// under it, its switch at its end across their middle; wide: wide_switch_row_node's); the switch alone answers. `on`,
/// `turn`: switch_node's.
pub fn switch_row_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  if look_node(parent) is Wide {
    wide_switch_row_node(parent, title, on, turn, note)
    return
  }
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
      // (as wide as the row leaves it, narrower where what it holds is wider: its words wrapped there, as a row's are)
      words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
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

///|
/// What the part over it does, in a line or two (page_note's), as `words` says it now: narrow, mSegNote (12 in, 8 over
/// and 4 under, the meta's muted); wide, desk_hint (8 over, 624 at most, the meta's muted); in red where it says what is
/// wrong, `bad`.
pub fn page_note_node(parent : @view.View, words : () -> String, bad? : () -> Bool = fn() { false }) -> Unit {
  match look_node(parent) {
    Narrow =>
      parent.box(fn(n) {
        n.padding(Is((pg_note_x, pg_note_top, pg_note_x, pg_note_foot))) |> ignore
        n.box(fn(w) { styled_words(w, words, fn() { if bad() { pg_note_bad } else { pg_note } }) |> ignore }) |> ignore
      })
      |> ignore
    Wide =>
      parent.box(fn(n) {
        n.padding(Is((0.0, pg_note_top, 0.0, 0.0))).max_width(Is(Some(desk_hint_most))) |> ignore
        n.box(fn(w) { styled_words(w, words, fn() { if bad() { desk_note_bad } else { desk_hint_words } }) |> ignore })
        |> ignore
      })
      |> ignore
  }
}

///|
/// What a page says in place of what it lists where it has none, `words` as it says it now: narrow, as what the page is
/// for is said (pg_lead_box: 12 in, 10 under, the secondary's words); wide, as it is, the UI's muted (up_said's).
pub fn page_none_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(n) {
    match look_node(n) {
      Narrow => {
        n.padding(Is((pg_lead_x, 0.0, pg_lead_x, pg_lead_foot))) |> ignore
        words_node(n, words, fn() { pg_lead }) |> ignore
      }
      Wide => words_node(n, words, fn() { desk_muted }) |> ignore
    }
  })
  |> ignore
}

///|
/// pg_note_box's room (px=S3, pt=S2, pb=S1).
let pg_note_x : Double = 12.0

///|
let pg_note_top : Double = 8.0

///|
let pg_note_foot : Double = 4.0

///|
/// A choice of a few on the page (page_choice's; narrow: Seg as wide as the page's room, seg_fill_node, 10 under it; wide:
/// as wide as its options, each `item_w` at least, at the line's start, standing as a section does), `labels` as they
/// are now, `chosen()` the one chosen, `choose` told the one a person chooses (the caller says it chosen then:
/// `chosen` follows it).
pub fn page_choice_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  item_w? : Double = 0.0,
) -> Unit {
  let at = part_of(parent)
  if at.look is Wide {
    // (a wide page's: as wide as its options, each `item_w` at least, at the line's start (desk_choice_row), standing as
    // a section does where it is in none: page_choice's wide_alone)
    let make = fn(p : @view.View) {
      p.box(fn(row) {
        row.row(Is(true)) |> ignore
        seg_node(row, labels, chosen, choose, item_w~) |> ignore
      })
      |> ignore
    }
    if at.section {
      make(parent)
    } else {
      parent.box(fn(r) {
        r.padding(Is((0.0, 0.0, 0.0, section_foot))) |> ignore
        make(r)
      })
      |> ignore
    }
    return
  }
  parent.box(fn(b) {
    b.padding(Is((0.0, 0.0, 0.0, pg_choice_foot))) |> ignore
    // (a narrow page's: Seg filling the page's room, as segmented's on a narrow page; `item_w` a wide page's alone)
    seg_fill_node(b, labels, chosen, choose) |> ignore
  })
  |> ignore
}

///|
/// pg_choice_box's room under it (pb=S2_5).
let pg_choice_foot : Double = 10.0

///|
/// Words that do something when tapped (tap_text's, as a node): a link's ink, `size` (15) on 1.4 its size, one line,
/// rippled round its words (6 past them on each side, 3 over and under, 8 round) as it is pressed; `press` done then.
pub fn tap_text_node(parent : @view.View, label : () -> String, press : () -> Unit, size? : Double = 15.0) -> Unit {
  parent.box(fn(b) {
    // (its ripple's room round its words, taking none of the line's: tap_text's press_out)
    b
    .row(Is(true))
    .padding(Is((tap_out, tap_out / 2.0, tap_out, tap_out / 2.0)))
    .margin(Is((-tap_out, -tap_out / 2.0, -tap_out, -tap_out / 2.0)))
    |> ignore
    pressed_node(b, press, Is(tap_corner), Link, label)
    b.box(fn(w) {
      w
      .words(By(label))
      .words_look(Is({ size, weight: 400, line: size * 1.4, wrap: false, tracking: @view.letters_own }))
      .ink(By(fn() { link_ink() }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// tap_text's ripple past its words (press_out) and its corner (press_corner).
let tap_out : Double = 6.0

///|
let tap_corner : Double = 8.0

///|
/// How big a station's mark stands before a row's name (desk_mark's, on every width).
pub let row_mark : Double = desk_mark

///|
/// A card of a page's (page_card's) in `parent`: as wide as the page's room, 20 in, what `body` puts on it 14 apart,
/// round as a card is (Xl3), on the card's ground; under it to what follows, narrow 10 (pg_card_room), wide a section's
/// 28 where it stands alone on the page (wide_alone's) and none in a section, none where it is a layer of one thing
/// (`layered`: page_card in layers, the card alone). `footed`: a button at its foot, the card's
/// room under it the capsule's that stands in its corner (foot_pad). What is on it is a card's words (page_card's
/// `in_words`): a row on it that has a card's form (a switch's row) is told so where it is made, by whoever makes it on
/// the card (`body` given the card's node), as what is made later on it is.
pub fn page_card_node(parent : @view.View, body : (@view.View) -> Unit, footed? : Bool = false, layered? : Bool = false) -> Unit {
  let card = fn(v : @view.View) {
    v.box(fn(k) {
      k
      .padding(Is((card_pad, card_pad, card_pad, if footed { card_foot_in(button_height()) } else { card_pad })))
      .gap(Is(page_card_gap))
      .radius(By(fn() { @ui.tree_theme().corner(Xl3) }))
      .ground(By(fn() { @ui.tree_theme().color(Card) }))
      |> ignore
      body(k)
    })
    |> ignore
  }
  let at = part_of(parent)
  if layered || at.look is Wide && at.section {
    card(parent)
  } else {
    // (narrow, 10 under it; wide, alone on the page, a section's 28 (wide_alone's))
    parent.box(fn(room) {
      room.padding(Is((0.0, 0.0, 0.0, if at.look is Wide { section_foot } else { page_card_foot }))) |> ignore
      card(room)
    })
    |> ignore
  }
}

///|
/// A page's card's room between what is on it (desk_card's gap=S3_5) and under it (pg_card_room's pb=S2_5).
let page_card_gap : Double = 14.0

///|
let page_card_foot : Double = 10.0

///|
/// Words of `style` in a node of `parent`'s (styled_words': cut short on their line where `style` says so), `words` as
/// they are said: the node.
pub fn words_node(parent : @view.View, words : () -> String, style : () -> @ui.TextStyle) -> @view.View {
  parent.box(fn(w) { styled_words(w, words, style) |> ignore })
}

///|
/// A round key in a bar (nav_button's, Parts.kt NavButton) as a node: `side` across, round, its icon `icon_size` in the
/// ink in its middle, no disc behind it (a ground while pressed: its ripple), read out a button named `label`; `press`
/// done as it is pressed.
pub fn round_key_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  side? : Double = 34.0,
  icon_size? : Double = 22.0,
) -> Unit {
  parent.box(fn(k) {
    k
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .radius(Is(side / 2.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    |> ignore
    pressed_node(k, press, Is(side / 2.0), Button, label)
    icon_node(k, icon, icon_size, By(fn() { theme().p.text })) |> ignore
  })
  |> ignore
}

///|
/// A top bar's title (top_bar_title_look, in the tree theme's ink), on one line, giving way in its row where it has not
/// the room (the line then ends in an ellipsis, as every one-line words' do).
pub fn top_bar_title_node(parent : @view.View, words : () -> String) -> @view.View {
  parent.box(fn(w) {
    w
    .words(By(words))
    .words_look(Is(top_bar_title_look))
    .ink(By(fn() { @ui.tree_theme().color(Fg) }))
    .cuts(Is(true))
    .min_width(Is(Some(0.0)))
    |> ignore
  })
}
