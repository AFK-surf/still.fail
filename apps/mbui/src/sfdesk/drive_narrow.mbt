// A station's folders pinned laid out narrow, as the web's narrow app has them (ember web/src/mobile/Drive.tsx
// RootsPage, RootRow, Empty; Drive.css.ts m*), in a box narrower than @sf.page_narrow_most, in whichever frame (the
// phone's stack, a tablet's pane); and what a narrow page is given of its frame (NarrowOf), its bar, the rows on a
// card. A folder's own page is one on every screen (drive_page.mbt).

///|
/// What a narrow page is given of its frame and what it opens: the frame's (back's words, the room over and under),
/// back (the frame's own way), and a folder shown in place of this one (the frame's: pushed on a stack, the side in
/// front of the files' page).
pub(all) struct NarrowOf {
  frame : PageFrame
  back : () -> Unit
}

///|
/// The narrow app's frame where nothing is said of it (a pane beside a list: no back, no room over or under).
pub fn narrow_bare() -> NarrowOf {
  { frame: { back: None, top: 0.0, foot: 0.0, named: false }, back: fn() {  } }
}

///|
/// The narrow bar (NavBar): back where the frame says (its words), the title in the middle, what it does at its end;
/// true on the frame back was pressed.
fn narrow_bar(c : @ui.Ctx, n : NarrowOf, title : String, trailing : () -> Unit) -> Bool {
  // (in a panel of its own on the tape: a chat's bar, as a settings page's there; back only where there is somewhere
  // to go)
  if @sf.in_pane() {
    pane_bar(c, n.frame.back.map(fn(label) { (label, n.back) }), title, actions=trailing)
    return false
  }
  @sf.nav_bar(
    c,
    "files/narrow/back",
    n.frame.back.unwrap_or(""),
    title,
    trailing~,
    back_max=if c.width / 2.0 - narrow_back_room > narrow_back_least {
      c.width / 2.0 - narrow_back_room
    } else {
      narrow_back_least
    },
    bg=@sf.theme().p.bg,
    top=n.frame.top,
  )
}

///|
/// A round button of the bar (NavButton): 34 across, its icon 18 (`size`), what it is said to be.
fn narrow_bar_button(c : @ui.Ctx, key : String, icon : String, label : String, size? : Double = narrow_bar_icon) -> Bool {
  @sf.icon_button(c, icon, key~, size=narrow_bar_button_w, icon_size=size, round=true, label~)
}

///|
/// The crumbs (mCrumbs): 20 in, a crumb 4 round, the way's muted, where it is in the words' colour, the chevrons
/// subtle.
fn narrow_way() -> @sf.WayLook {
  {
    line: narrow_crumbs_row,
    step: narrow_crumb,
    words: narrow_crumb_words,
    here: narrow_crumb_here,
    chevron: narrow_crumb_chevron,
    chevron_ink: @sf.theme().p.subtle,
  }
}

///|
/// What could not be read, and 重试.
fn narrow_retry(c : @ui.Ctx, words : String, look : @ui.TextStyle, retry : () -> Unit) -> Unit {
  c.box(style=narrow_problem, fn() {
    c.box(style=narrow_problem_words, fn() { c.text(words, style=look) |> ignore }) |> ignore
    let id = c.id("files/narrow/retry")
    if c.clicked(id) {
      retry()
    }
    c.box(style=narrow_link, id~, fn() { c.text(@sf.t("web-pages.drive.retry"), style=narrow_link_words) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// Nothing here (Empty): a folder's mark (40), why, and what can be done about it (`action`: its words, what it does).
fn narrow_empty(c : @ui.Ctx, words : String, action : (String, () -> Unit)?) -> Unit {
  let t = @sf.theme()
  c.box(style=narrow_empty_box, fn() {
    @sf.icon(c, "folder", size=narrow_empty_icon, color=t.p.subtle) |> ignore
    c.text(words, style=narrow_empty_words) |> ignore
    match action {
      Some((label, go)) => if @sf.button(c, label, key="files/narrow/empty", tone=Ghost) { go() }
      None => ()
    }
  })
  |> ignore
}

///|
/// How far a text has been read on this device, once opened (the core's `drivePlace`): its share, 读完 at its end.
fn read_share(c : @ui.Ctx, src : Source, station : String, root : String, path : String) -> Unit {
  let place = (src.topic)("drivePlace", { "station": Json::string(station), "root": Json::string(root), "path": Json::string(path) }).value
  let of = number(place, "of")
  if of <= 0.0 {
    return
  }
  let at = number(place, "at") / of
  let share = if at < 0.0 { 0.0 } else if at > 1.0 { 1.0 } else { at }
  if share < read_least {
    return
  }
  c.text(if share >= read_whole { @sf.t("android-misc.drive.read.done") } else { "\{(share * 100.0).to_int()}%" }, style=@sf.theme().items.meta)
  |> ignore
}

///|
/// Read so little it says nothing (1%), read to its end (99.5%).
let read_least : Double = 0.01

///|
let read_whole : Double = 0.995

///|
/// How far a file of the drive has come while it is downloaded (FillChip's `progress`): a rounded box, its ground filled
/// in the accent from the left as it comes (moving to each new share over 500 ms), n% on it.
fn download_chip(c : @ui.Ctx, key : String, percent : Int) -> Unit {
  let p = if percent < 0 { 0 } else if percent > 100 { 100 } else { percent }
  let drawn = @motion.animate(c, "files/narrow/fetch/" + key, p.to_double(), spec=chip_fill)
  c.box(style=chip_box, fn() {
    if drawn > 0.0 {
      c.layer(fn() {
        c.box(style=chip_track, fn() {
          c.box(style=chip_done.then(@ui.style(w=Grow(drawn))), fn() {  }) |> ignore
          let rest = chip_whole - drawn
          if rest > 0.0 {
            c.box(style=@ui.style(h=Full, w=Grow(rest)), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(style=chip_words_box, fn() { c.text("\{p}%", style=chip_words) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// How the chip fills (500 ms).
// kept across runs: a value (no field of it changes)
let chip_fill : @motion.Spec = @motion.tween(chip_fill_ms, ease=Out)

///|
let chip_fill_ms : Double = 500.0

///|
/// The whole of the chip, in its percent.
let chip_whole : Double = 100.0

///|
/// The chip: 20 high, a capsule (at a row's end in its middle, round as it is there, by no corner of the row's), on the
/// neutral ground, its fill the accent at 20%, its words 11 bold. Its fill cut to the capsule by the track it is in,
/// not by the chip: a chip cutting what it holds is one its row may take all the room of (its words cut to nothing
/// beside a list's size and time, which leave the row first, 2026-10-26).
// kept across runs: a value (no field of it changes)
let chip_box : @ui.Style = @ui.css("h=S5 radius=Full bg=Neutral justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let chip_track : @ui.Style = @ui.css("row w=Full h=Full radius=Full clip")

///|
// kept across runs: a value (no field of it changes)
let chip_done : @ui.Style = @ui.css("h=Full bg=A(Accent,O20)")

///|
// kept across runs: a value (no field of it changes)
let chip_words_box : @ui.Style = @ui.css("row px=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let chip_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Semibold, color=Fg, wrap=false)


///|
/// How tall a row is taken to be before it is laid out.
let narrow_row_est : Double = 62.0

///|
/// Under the list, 30 over the frame's foot (contentPadding).
let narrow_list_foot : Double = 30.0

///|
/// Back's words at least 80 wide, at most what the bar has beside the title (half less 120).
let narrow_back_least : Double = 80.0

///|
let narrow_back_room : Double = 120.0

///|
/// The bar's buttons (NavButton: 34, its icon 18; ＋'s 20).
let narrow_bar_button_w : Double = 34.0

///|
let narrow_bar_icon : Double = 18.0


///|
/// The rows' marks (22), a folder's chevron (14), a crumb's (12), the empty folder's mark (40), a row's spinner (12), a
/// row's key (34).
let narrow_kind_icon : Double = 22.0

///|
let narrow_chevron_icon : Double = 14.0

///|
let narrow_crumb_chevron : Double = 12.0

///|
let narrow_empty_icon : Double = 40.0








///|
/// Why it could not be read (mProblem): 20 in, 12 over and under, its 重试 in the link's ink.
// kept across runs: a value (no field of it changes)
let narrow_problem : @ui.Style = @ui.css("row w=Full px=S5 py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_problem_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let narrow_link : @ui.Style = @ui.css("p=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let narrow_link_words : @ui.TextStyle = @ui.text_style(size=Body, color=Link, wrap=false)

///|
/// What could not be read (a station's folders): in red, as wide as the line.
// kept across runs: a value (no field of it changes)
let narrow_failed_words : @ui.TextStyle = @ui.text_style(size=Body, color=Danger, w=Full)

///|
/// What it holds in a line (mCount): 28 in, 2 over, 8 under, the meta's words, muted.
// kept across runs: a value (no field of it changes)
let narrow_count_box : @ui.Style = @ui.css("w=Full px=S7 pt=S0_5 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let narrow_count_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The crumbs (mCrumbs): 20 in, a crumb 4 round, the way's muted, where it is in the words' colour.
// kept across runs: a value (no field of it changes)
let narrow_crumbs_row : @ui.Style = @ui.css("row pl=S5 pr=S5 pt=S0_5 pb=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb : @ui.Style = @ui.css("px=S1 py=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let narrow_crumb_here : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)







///|
/// Nothing here (mEmpty): in the middle, 56 by 32 in, 12 apart.
// kept across runs: a value (no field of it changes)
let narrow_empty_box : @ui.Style = @ui.css("w=Full px=S8 py=S14 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true, w=Full)

///|
/// A row (mRow): 12 by 11 in (the card's 8 and its own), its mark, its words, what is at its end 12 apart.
// kept across runs: a value (no field of it changes)
let narrow_entry : @ui.Style = @ui.css("row w=Full px=S2 py=S2_5 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_entry_words : @ui.Style = @ui.style(w=@sf.grow)

///|
/// Its name (mName: the body's 15 on 20), what it is under it (mMeta: 12 on 16, muted).
// kept across runs: a value (no field of it changes)
let narrow_entry_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_entry_meta : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let narrow_trouble : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, weight=Semibold, color=Danger, w=Full)

///|
// kept across runs: a value (no field of it changes)
let narrow_trouble_hint : @ui.TextStyle = @ui.text_style(size=Meta, leading=L4, color=Muted, w=Full)




















