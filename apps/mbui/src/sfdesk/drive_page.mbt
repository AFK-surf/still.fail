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
/// page says its name under the way (the files' page's tabs). `front_it`:
/// what is pressed in a side puts it in front first.
pub fn folder_page(
  c : @ui.Ctx,
  src : Source,
  f : FolderOf,
  bar : NarrowOf?,
  front_it? : () -> Unit = fn() {  },
) -> Unit {
  let actions_most = c.width / 2.0 - bar_title_half
  c.box(style=folder_page_box, fn() {
    match bar {
      Some(n) =>
        // (what can be done to it at the bar's end, as far as half the bar less the title's half: the rest in its ⋯)
        if narrow_bar(c, n, folder_name(f.st, f.at), fn() {
            c.box(style=@ui.style(max_w=Fixed(actions_most)), fn() {
              folder_actions(c, src, f, style=bar_actions_row())
            })
            |> ignore
          }) {
          (n.back)()
        }
      None => ()
    }
    folder_view(c, src, f, head=fn() { folder_head(c, src, f, front_it, bar is None) }, foot=match bar {
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
fn folder_head(c : @ui.Ctx, src : Source, f : FolderOf, front_it : () -> Unit, titled : Bool) -> Unit {
  let at = f.at
  let root = at.root.unwrap_or("")
  let (value, error) = drive_folder(src, at.station, root, at.path)
  let stations = dv_stations(src, f.ws).0.unwrap_or([])
  let (name, _) = pane_parts(at, stations)
  // (in as far as its rows' words, as the page is arranged; the first under the pane's tools)
  @sf.rows_head(c, first=true, fn() {
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
        @sf.way_line(c, "files/way/" + f.key + "/" + at.station + "/" + root, levels.map(fn(l) { l.0 }), folder_crumb_way(), fn(i) {
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
      // what it holds while it is read, in its bones: the line's room kept, as the columns under it stay
      (None, None) =>
        @sf.bones(c, fn() { c.text(@sf.sample_words(8), style=@sf.theme().rows.note) |> ignore })
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
    let b = c.box(style=head_link, id~, fn() { c.text(@sf.t("web-pages.drive.retry"), style=note.then(head_link_words)) |> ignore })
    c.semantics(b, Button, id~, label=@sf.t("web-pages.drive.retry"))
  })
  |> ignore
}

///|
/// The way's look (the crumbs): a step 4 round under the pointer, the way's words the row's note's (muted), where it
/// is in the words' colour, the chevrons subtle.
fn folder_crumb_way() -> @sf.WayLook {
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
let bar_title_half : Double = 40.0

///|
/// What can be done to it in its own bar: at its end, as far as its room, as a bar's keys apart (@sf.keys_gap).
fn bar_actions_row() -> @ui.Style {
  bar_actions_look.then(@ui.style(gap=@sf.keys_gap()))
}

///|
// kept across runs: a value (no field of it changes)
let bar_actions_look : @ui.Style = @ui.css("row align=ACenter justify=JEnd")




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
let head_title : @ui.TextStyle = @ui.text_style(size=Heading, weight=Semibold, color=Fg)

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

// ── a station's folders pinned ──────────────────────────────────────────

///|
/// A station's drive with no folder to show (Roots; the phone's RootsPage): one page on every screen, made of the
/// library's page parts (its frame laid out by its width: back over a large title, or its head). What it is for: which
/// of the station's folders can be gone into, and what is wrong with one. 文件, the station's name under it; ⋯ 管理
/// for one who may; what it holds in a line, then a row each (its name, where it is, or what is wrong with it in red);
/// pressed, gone into; held or right clicked, for one who may: no longer pinned, asked first. Read, says so; none,
/// says so (选择文件夹 for one who may); from before drives, says so. `n`: the frame it is drawn in (back, the room
/// over and under it).
pub fn roots_page(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  st : DvStation?,
  reading : Bool,
  error : String?,
  manage : Bool,
  n : NarrowOf,
  go : (DriveAt) -> Unit,
) -> Unit {
  let name = match st {
    Some(s) => s.name
    None => ""
  }
  let empty = fn(words : String, pick : DvStation?) {
    @sf.empty(c, fn() {
      c.text(words, style=roots_empty_words) |> ignore
      match pick {
        Some(s) =>
          if @sf.button(c, @sf.t("web-pages.drive.pick"), key="files-roots/pick", tone=Primary) {
            add_folder(src, ws, [s])
          }
        None => ()
      }
    })
  }
  let body = fn() {
    match st {
      _ if reading => @sf.waiting(c, fn() { roots_sample(c) }, error=error.unwrap_or(""))
      None => empty(@sf.t("web-pages.workspace.noSuchStation"), None)
      Some(s) if !s.overview => @sf.waiting(c, fn() { roots_sample(c) })
      Some(s) if !s.drive => empty(@sf.t("web-pages.drive.oldStation"), None)
      Some(s) if s.roots.length() == 0 =>
        empty(@sf.t(if manage { "web-pages.drive.noneManage" } else { "web-pages.drive.noneMember" }), if manage {
          Some(s)
        } else {
          None
        })
      Some(s) => roots_section(c, src, s, manage, go)
    }
  }
  @sf.page(
    c,
    "files-roots/" + (match st { Some(s) => s.station; None => "" }),
    @sf.t("web-pages.drive.title"),
    [body],
    on_back=n.back,
    frame=n.frame,
    lead=name,
    actions?=match st {
      Some(s) if manage && s.drive && s.roots.length() > 0 =>
        Some(fn() {
          if @sf.icon_button(c, "more", key="files-roots/manage", round=true, label=@sf.t("web-pages.drive.manage")) {
            manage_roots(src, ws, s.station)
          }
        })
      _ => None
    },
  )
}

///|
/// The folders station `s` pins: how many, the title over their card (as far over it as any card's), a row each.
fn roots_section(c : @ui.Ctx, src : Source, s : DvStation, manage : Bool, go : (DriveAt) -> Unit) -> Unit {
  @sf.section(c, @sf.t("web-pages.drive.rootsCount", args=[("n", s.roots.length().to_string())]), fn() {
    @sf.group(c, fn() {
      for r in s.roots {
        root_row(c, src, s, r, manage, go)
      }
    })
  })
}

///|
/// The folders to come while the station is read (the library's Waiting, in its bones): roots_section of made-up ones.
fn roots_sample(c : @ui.Ctx) -> Unit {
  let roots : Array[DvRoot] = [(5, 18), (3, 24), (6, 15), (4, 21)].map(fn(r) {
    { path: @sf.sample_words(r.1), name: @sf.sample_words(r.0), state: "ok" }
  })
  let s = @sfbase.dv_station({ "station": "sample", "name": Json::string(@sf.sample_words(4)) })
  roots_section(c, @sfbase.sample_source, { ..s, roots }, false, fn(_) {  })
}

///|
/// A folder pinned (RootRow): its mark, its name, where it is (which disk, which folder: what finding it again turns
/// on), what is wrong with it and what to do in red under that where it cannot be browsed now, a chevron; pressed, gone into; held or right clicked, for one who may, no longer pinned.
fn root_row(c : @ui.Ctx, src : Source, s : DvStation, r : DvRoot, manage : Bool, go : (DriveAt) -> Unit) -> Unit {
  let t = @sf.theme()
  let key = "files-root/" + s.station + "/" + r.path
  let id = c.id(key)
  match c.menu_asked(id) {
    Some((x, y)) if manage =>
      @sf.menu(
        [Some(@sf.menu_item_of(@sf.t("web-pages.drive.unshare"), icon="close", danger=true, fn() { ask_unpin(c, src, s, r) }))],
        from=@sf.at_point(x, y),
        title=r.name,
      )
    _ => ()
  }
  let trouble = match dv_trouble(r.state) {
    Some((what, hint)) => what + " · " + hint
    None => ""
  }
  if @sf.link_row(c, key, r.name, note=r.path, trouble~, lead=fn() {
      @sf.icon(c, "folder", size=t.items.mark, color=t.p.muted) |> ignore
    }) {
    go({ station: s.station, root: Some(r.path), path: "" })
  }
}

///|
// kept across runs: a value (no field of it changes)
let roots_empty_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)
