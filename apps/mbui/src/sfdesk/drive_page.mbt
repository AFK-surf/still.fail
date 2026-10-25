// A folder of a station's drive: one page on every screen (docs/architecture.md: the same on every screen, and what
// differs). What it is for: a person comes to find a file and open it (read, played, previewed, saved), and to put
// files in and keep them in order (up, a new folder, a name changed, deleted, dragged into a folder, pinned, 收藏). So,
// top to bottom: its bar (back where its frame has one, its name, what can be done to it), its way down from its root
// (the station's switch first), what it holds in a line (why it could not be read, 重试), the files going up into it,
// its entries in the way it is shown (columns, a tree, a list: drive_views.mbt), the preview beside them where the room
// has it (drive_pane.mbt).
// What differs is not the page's: the sizes are the theme's (Theme.items), the rows on a card or on the page the page's
// arrangement's, whether a press opens or chooses and whether the ⋯ is there the hand's (drive_row), the menus the
// presenters', how many of the bar's actions are out the bar's room (@sf.tools_row), which ways it can be shown and how
// many columns the list's room (views_for), tabs and halves or a stack the frame's (files.mbt, the phone's stack).

///|
/// The folder `f.at`, in the frame it is given: `bar`, the frame's where the page draws its own bar (back, its name
/// and what can be done to it: a stack's, a pane's); None where the frame's bar holds what can be done to it and the
/// page says its name under the way (the files' page's tabs). `split`: a side of a split tab, in less; `front_it`:
/// what is pressed in a side puts it in front first.
pub fn folder_page(
  c : @ui.Ctx,
  src : Source,
  f : FolderOf,
  bar : NarrowOf?,
  split? : Bool = false,
  front_it? : () -> Unit = fn() {  },
) -> Unit {
  let actions_most = c.width / 2.0 - bar_title_half
  c.box(style=folder_page_box, fn() {
    match bar {
      Some(n) =>
        // (what can be done to it at the bar's end, as far as half the bar less the title's half: the rest in its ⋯)
        if narrow_bar(c, n, folder_name(f.st, f.at), fn() {
            c.box(style=@ui.style(max_w=Fixed(actions_most)), fn() {
              folder_actions(c, src, f, style=bar_actions_row)
            })
            |> ignore
          }) {
          (n.back)()
        }
      None => ()
    }
    folder_view(c, src, f, head=fn() { folder_head(c, src, f, split, front_it, bar is None) }, foot=match bar {
      Some(n) => n.frame.foot
      None => 0.0
    })
  })
  |> ignore
}

///|
/// The folder's head (Drive.tsx FolderView's pageHead; the phone's Crumbs and mCount): its way (its station's button,
/// then the way down from its root to it), its name where the frame's bar has not said it (`titled`: h1), what it holds
/// in a line, or why it was not read again (its 重试). In as far as the rows' words are, wherever it is shown.
fn folder_head(c : @ui.Ctx, src : Source, f : FolderOf, split : Bool, front_it : () -> Unit, titled : Bool) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let stations = dv_stations(src, f.ws).0.unwrap_or([])
  let (name, _) = pane_parts(at, stations)
  // (in as far as its rows' words: on the page's card where narrow, past the side's own room where wide)
  c.box(style=if c.width < @sf.page_narrow_most { head_narrow } else if split { head_half } else { head_one }, fn() {
    c.box(style=head_trail, fn() {
      station_switch(c, src, f, front_it)
      // the way down from the root to it (the root alone at the root), each but the last a way back to it
      let parts = at.path.split("/").filter(fn(p) { p != "" }).map(fn(p) { p.to_owned() }).to_array()
      let levels : Array[(String, String)] = [(folder_name(f.st, { ..at, path: "" }), "")]
      let mut so_far = ""
      for p in parts {
        so_far = dv_join(so_far, p)
        levels.push((p, so_far))
      }
      c.box(style=head_way, fn() {
        way_line(c, "files/way/" + f.key + "/" + at.station + "/" + root, levels.map(fn(l) { l.0 }), folder_crumb_way(), fn(i) {
          front_it()
          (f.go)({ ..at, path: levels[i].1 }, false)
        })
      })
      |> ignore
    })
    |> ignore
    if titled {
      c.text(name, style=head_title) |> ignore
    }
    match (value, error) {
      (Some(_), Some(e)) =>
        head_retry(c, @sf.t("android-misc.drive.stale", args=[("error", e)]), false, fn() { refresh_folder(c, src, at) })
      (None, Some(e)) => head_retry(c, e, true, fn() { refresh_folder(c, src, at) })
      (Some(v), None) => {
        let count = text(Some(v), "countText") +
          (if flag(Some(v), "truncated") { " · " + @sf.t("web-pages.drive.truncated") } else { "" })
        if count != "" {
          c.text(count, style=@sf.theme().rows.note) |> ignore
        }
      }
      (None, None) => ()
    }
  })
  |> ignore
}

///|
/// What could not be read (`bad`: in red; else the old list kept, why it was not read again), and 重试.
fn head_retry(c : @ui.Ctx, words : String, bad : Bool, retry : () -> Unit) -> Unit {
  let note = @sf.theme().rows.note
  c.box(style=head_problem, fn() {
    c.text(words, style=if bad { note.then(head_bad) } else { note.then(head_wraps) }) |> ignore
    let id = c.id("files/retry")
    if c.clicked(id) {
      retry()
    }
    c.cursor(id, Hand)
    let b = c.box(style=head_link, id~, fn() { c.text(@sf.t("web-pages.drive.retry"), style=note.then(head_link_words)) |> ignore })
    c.semantics(b, Button, id~, label=@sf.t("web-pages.drive.retry"))
  })
  |> ignore
}

///|
/// The way's look (the crumbs): a step 4 round under the pointer, the way's words the row's note's (muted), where it
/// is in the words' colour, the chevrons subtle.
fn folder_crumb_way() -> WayLook {
  let note = @sf.theme().rows.note
  {
    line: folder_crumb_line,
    step: folder_crumb_step,
    words: note.then(folder_crumb_words),
    here: note.then(folder_crumb_here),
    chevron: folder_crumb_chevron,
    chevron_ink: @sf.theme().p.subtle,
  }
}

///|
/// The page: the frame's ground, its bar over what it holds.
// kept across runs: a value (no field of it changes)
let folder_page_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Half the room its own bar keeps for its title (its name in the middle).
let bar_title_half : Double = 56.0

///|
/// What can be done to it in its own bar: at its end, as far as its room.
// kept across runs: a value (no field of it changes)
let bar_actions_row : @ui.Style = @ui.css("row gap=S1 align=ACenter justify=JEnd")

///|
/// The head: 12 over, 8 under, 6 between its lines; in as far as the rows' words (a list's 12; the folder's own side
/// gives the rest).
// kept across runs: a value (no field of it changes)
let head_one : @ui.Style = @ui.css("w=Full px=S3 pt=S3 pb=S2 gap=S1_5")

///|
// kept across runs: a value (no field of it changes)
let head_half : @ui.Style = @ui.css("w=Full px=S3 pt=S3 pb=S2 gap=S1_5")

///|
/// Narrow: 20 in (the crumbs' mCrumbs), 2 over, 8 under.
// kept across runs: a value (no field of it changes)
let head_narrow : @ui.Style = @ui.css("w=Full px=S5 pt=S0_5 pb=S2 gap=S1_5")

///|
/// Its way: the station's button, 8 to the crumbs, which take what is left of the line.
// kept across runs: a value (no field of it changes)
let head_trail : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_way : @ui.Style = @ui.style(w=@sf.grow, min_w=S0)

///|
/// Its name (h1): 22, 600.
// kept across runs: a value (no field of it changes)
let head_title : @ui.TextStyle = @ui.text_style(size=Xl3, weight=Semibold, color=Fg, wrap=false)

///|
/// Why it was not read: its words, then 重试 in the link's ink, 12 apart.
// kept across runs: a value (no field of it changes)
let head_problem : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let head_bad : @ui.TextStyle = @ui.text_style(color=Danger, wrap=true, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let head_wraps : @ui.TextStyle = @ui.text_style(wrap=true, w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let head_link : @ui.Style = @ui.css("py=S1 radius=Lg")

///|
// kept across runs: a value (no field of it changes)
let head_link_words : @ui.TextStyle = @ui.text_style(color=Link, wrap=false)

///|
/// The crumbs: a step 4 round, its ground under the pointer.
// kept across runs: a value (no field of it changes)
let folder_crumb_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let folder_crumb_step : @ui.Style = @ui.css("px=S1 py=S0_5 radius=Lg hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let folder_crumb_words : @ui.TextStyle = @ui.text_style(wrap=false)

///|
// kept across runs: a value (no field of it changes)
let folder_crumb_here : @ui.TextStyle = @ui.text_style(weight=Medium, color=Fg, wrap=false)

///|
let folder_crumb_chevron : Double = 12.0
