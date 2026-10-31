// The settings pages' parts, as the Android app draws them (shared/ui/Parts.kt: NavBack, NavBar, LargeTitle,
// SectionHeader, Card, ListCard, ListRow, Seg, Avatar; screens/SettingParts.kt GoRow, PageNote; PageParts.kt Switch,
// PresenceDot; Controls.kt Button, PickRow, DoingMark; Waiting.kt Waiting, WaitLine; PlaceRows.kt PlaceEmpty;
// Stations.kt TopBack). Sizes in dp as there; colours src/sf's narrow palette (Theme.kt's).

///|
/// Each page's blocks as given and as its list made of them, by the page's key (scroll_page's `keys`).
// kept across runs: put back by settings' reset (parts_reset)
let page_rows : Map[String, @ui.ListRows[() -> Unit]] = {}

///|
/// Each page's blocks' keys as last given.
// kept across runs: put back by settings' reset (parts_reset)
let page_keys : Map[String, Array[String]] = {}

///|
fn page_rows_of(key : String) -> @ui.ListRows[() -> Unit] {
  match page_rows.get(key) {
    Some(l) => l
    None => {
      let l = @ui.ListRows::new()
      page_rows[key] = l
      l
    }
  }
}

///|
/// Theme.kt's `warn`, the same in light and dark.
let warn : Int64 = 0xD9962BFFL

///|
/// Drawn in the wide frame's pane (a desktop's width, src/sfapp/wide.mbt): the pages as the web's settings pages
/// stand (pages.css.ts page: their head's title 22 in 600, no back where the sidebar is the way back, a column 760 wide
/// at most in the middle, 40 from the sides at least); `wide_deep`: a page under another of them (back shown).
pub let wide : Ref[Bool] = Ref(false)

///|
pub let wide_deep : Ref[Bool] = Ref(false)

///|
/// What a page's blocks stand in from the pane's sides in the wide frame (their own 16 inside it).
fn wide_side(c : @ui.Ctx) -> Double {
  dmax(24.0, (c.width - 792.0) / 2.0)
}

///|
/// A page of the settings: what it shows, a block at a time (each laid out only when it comes into view), scrolling
/// under what stays at its top. `key` keeps its place while it is on the stack. `keys`: each block's own (a station's
/// id, a person's), as many as the blocks: what came, went and changed its place among them comes and goes where it is,
/// as a chat's rows do (ListRows, docs/list-motion.md; 2026-10-31 the user: 「有一些是凭空出现的，有一些是凭空消失的」),
/// not at once; a page whose blocks are all others now (what waited, then what came) shows them as they are.
fn scroll_page(c : @ui.Ctx, key : String, blocks : Array[() -> Unit], keys? : Array[String]) -> Unit {
  // (its blocks drawn as its list lays them out, maybe after this returns: in the page's arrangement, @sf.look)
  let l = @sf.look()
  let blocks = blocks.map(fn(b) { fn() { @sf.with_look(l, b) } })
  // (by their keys: those going still among them while they close, each keyed as it was)
  let (blocks, keys, rows) = match keys {
    Some(ks) if ks.length() == blocks.length() && !@sf.in_panel() => {
      let lr = page_rows_of(key)
      let was = page_keys.get(key).unwrap_or([])
      page_keys[key] = ks
      let watched = ks.iter().any(fn(k) { was.contains(k) })
      let (b, k) = lr.rows(c, ks, blocks, fn(_) { "" }, watched~)
      (b, k, Some(lr))
    }
    _ => (blocks, [], None)
  }
  // a block drawn in a box of its own, coming and going where it is by its key
  let block = fn(i : Int, draw : () -> Unit) {
    match rows {
      Some(lr) => {
        let n = c.box(style=@sf.full_width, draw)
        lr.enter(c, n, keys[i])
        lr.leave(c, n, keys[i])
      }
      None => draw()
    }
  }
  let sized = rows.map(fn(lr) { lr.sized() })
  // in a panel (the library's presenters'), in the room the panel gives it: no page's column, no frame's room over or
  // under it
  if @sf.in_panel() {
    // (a dialog's, as tall as what it holds: its blocks one under another, the dialog's body scrolling them)
    if @sf.panel_whole() {
      c.box(style=@sf.full_width, fn() {
        for b in blocks {
          b()
        }
      })
      |> ignore
    } else {
      // (its blocks drawn as the list lays them out, as the panel has what it holds)
      @sf.panel_list(c, "settings/" + key, blocks.length(), 80.0, fn(i) { (blocks[i])() }) |> ignore
    }
    return
  }
  if wide.val {
    let side = wide_side(c)
    c.list("settings/" + key, blocks.length() + 1, 80.0, fn(i) {
      if i == blocks.length() {
        gap(c, 80.0)
      } else {
        block_at.val = i
        block(i, fn() { c.box(style=@sf.full_width, pl=side, pr=side, fn() { (blocks[i])() }) |> ignore })
        block_at.val = -1
      }
    }, sized?)
    |> ignore
    return
  }
  // what it shows ends over the navigation bar (SettingParts.kt pages: windowInsetsPadding(navigationBars)), and at a
  // place's top, over the bottom bar too (Stations.kt BarRoom); there it starts under the app's top bar, scrolling
  // under it (PlacePage.kt: `padding(top = top)` inside what scrolls)
  let foot = nav_foot.val + (if at_root.val { bar_room.val } else { 0.0 })
  let top = top_room()
  let head = if top > 0.0 { 1 } else { 0 }
  let n = head + blocks.length() + (if foot > 0.0 { 1 } else { 0 })
  c.list("settings/" + key, n, 80.0, fn(i) {
    if i < head {
      gap(c, top)
    } else if i - head == blocks.length() {
      gap(c, foot)
    } else {
      block(i - head, blocks[i - head])
    }
  }, sized?)
  |> ignore
  fixture_scroll(c, "settings/" + key)
}

///|
/// A page's head in the wide frame (pages.css.ts pageHead), the desktop's own pages' too (src/sfdesk): back above it
/// only on a page under another (`deep`; `on_back` when it is said, else the page popped), the title (`about`: what
/// the page is for, said by a mark beside it), what it does at its end.
pub fn wide_head(
  c : @ui.Ctx,
  core : Core,
  back : String,
  title : String,
  trailing? : () -> Unit,
  inside? : Bool = false,
  on_back? : () -> Unit,
  about? : String = "",
  lead? : String = "",
  deep? : Bool = wide_deep.val,
) -> Unit {
  let t = @sf.theme()
  head_block.val = block_at.val
  // (inside a block of the page, which stands in already)
  let side = if inside { 16.0 } else { wide_side(c) + 16.0 }
  c.box(style=if deep { wide_head_deep } else { wide_head_top }, pl=side, pr=side, fn() {
    if deep {
      let id = c.id("settings-back")
      c.box(style=wide_back, id~, fn() {
        @sf.icon(c, "chevron-left", size=14.0, color=t.p.muted) |> ignore
        c.text(back, size=t.t.meta, color=if c.lit(id) { t.p.text } else { t.p.muted }, wrap=false) |> ignore
      })
      |> ignore
      if hit(c, id) {
        match on_back {
          Some(f) => f()
          None => (core.pop)()
        }
      }
    }
    c.box(style=title_line, fn() {
      c.box(style=if about == "" { title_words } else { title_about }, fn() {
        // (short of room, cut short before what is at its end: never under a few words, title_words)
        c.text(title, size=t.t.heading, weight=600, color=t.p.text, wrap=false, line=34.0, w=Cut) |> ignore
        if about != "" {
          @sf.about(c, "settings-about", about, label=tr("web-main.about"))
        }
      })
      |> ignore
      match trailing {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
    // what the page is for, said under its title (pageHead's p: 6 under it, the ui's 13 muted)
    if lead != "" {
      c.box(style=wide_head_lead_box, fn() { c.text(lead, style=wide_head_lead) |> ignore }) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wide_head_lead_box : @ui.Style = @ui.css("w=Full pt=S1_5")

///|
// kept across runs: a value (no field of it changes)
let wide_head_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted, w=Full)

///|
/// Which of a wide page's blocks is being laid out (-1: none, outside its list), and which drew its head (-1: a head
/// over the list): a section's head right under the page's knows it is the first (section_header).
// kept across runs: said again by every block and head as it is laid out (scroll_page, wide_head)
let block_at : Ref[Int] = Ref(-1)

///|
// kept across runs: said again by every head as it is laid out (wide_head)
let head_block : Ref[Int] = Ref(-1)

///|
/// The wide frame's head: on a page under another (back over its title) 20 down, else 40; 12 under it.
// kept across runs: a value (no field of it changes)
let wide_head_top : @ui.Style = @ui.css("w=Full pt=S10 pb=S3 bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let wide_head_deep : @ui.Style = wide_head_top.then(@ui.css("pt=S5"))

///|
/// The wide frame's back, over the head's title.
// kept across runs: a value (no field of it changes)
let wide_back : @ui.Style = @ui.css("row pb=S2 gap=S1 align=ACenter")

///|
/// A title and what is at its end, in a line (LargeTitle's lead and big word too).
// kept across runs: a value (no field of it changes)
let title_line : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
/// A title with what it is for beside it.
// kept across runs: a value (no field of it changes)
let title_about : @ui.Style = title_words.then(@ui.css("row gap=S1_5 align=ACenter"))

///|
/// The title's words, the room its line has left beside what follows them (pageHead: the title grows, its actions at
/// its end).
// kept across runs: a value (no field of it changes)
let title_words : @ui.Style = @ui.style(w=@sf.grow, min_w=S20)

///|
/// A gap of `h` (Spacer).
fn gap(c : @ui.Ctx, h : Double) -> Unit {
  c.box(style=@sf.full_width, h=Px(h), fn() {  }) |> ignore
}

///|
/// Back, a chevron in the accent and where it goes back to in a link's ink (Parts.kt NavBack). True on the frame after a tap.
fn nav_back(c : @ui.Ctx, label : String) -> Bool {
  @sf.nav_back(c, "settings-back", label)
}

///|
/// Back at the top of a large-title page (Stations.kt TopBack): `on_back` when it is said, else the page popped;
/// `trailing` at its other end (a ＋).
fn top_back(c : @ui.Ctx, core : Core, label : String, trailing? : () -> Unit, on_back? : () -> Unit) -> Unit {
  if wide.val {
    // (the large title under it is the head's: large_title)
    top_trailing.val = trailing
    top_on_back.val = on_back
    top_label.val = label
    return
  }
  // under the status bar (TopBack: windowInsetsPadding(statusBars))
  if status_top.val > 0.0 {
    gap(c, status_top.val)
  }
  c.box(style=top_back_line, fn() {
    if nav_back(c, label) {
      match on_back {
        Some(f) => f()
        None => (core.pop)()
      }
    }
    match trailing {
      Some(f) => f()
      None => ()
    }
  })
  |> ignore
}

///|
/// Back's line at the top of a large-title page (Stations.kt TopBack): 10 in, 6 over, 4 under.
// kept across runs: a value (no field of it changes)
let top_back_line : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S1_5 pb=S1 align=ACenter justify=JBetween")

///|
/// What a large-title page's top had (top_back), for its head in the wide frame (large_title).
let top_trailing : Ref[(() -> Unit)?] = Ref(None)

///|
let top_on_back : Ref[(() -> Unit)?] = Ref(None)

///|
let top_label : Ref[String] = Ref("")

///|
/// The core of the page being drawn (its head's back, in the wide frame).
let frame_core : Ref[Core?] = Ref(None)

///|
/// A page's compact bar (Parts.kt NavBar): back, a centred title (and a line under it, `sub`), an action at its end.
fn nav_bar(
  c : @ui.Ctx,
  core : Core,
  back : String,
  title : String,
  sub? : () -> Unit,
  trailing? : () -> Unit,
  on_back? : () -> Unit,
  about? : String = "",
) -> Unit {
  if wide.val {
    ignore(sub)
    wide_head(c, core, back, title, trailing?=trailing, on_back?=on_back, about~)
    return
  }
  if @sf.nav_bar(c, "settings-back", back, title, sub?=sub, trailing?=trailing, bg=@sf.theme().p.bg, top=status_top.val) {
    match on_back {
      Some(f) => f()
      None => (core.pop)()
    }
  }
}

///|
/// How far the status bar and the navigation bar reach in over the view (the app's, src/sfapp/bars.mbt, said each frame):
/// what a page's bar and its foot are padded by.
pub let status_top : Ref[Double] = Ref(0.0)

///|
pub let nav_foot : Ref[Double] = Ref(0.0)

///|
/// A bar's room, `h` high (none when it is 0): the status bar's over a page, the navigation bar's under it.
fn bar_room_gap(c : @ui.Ctx, h : Double) -> Unit {
  if h > 0.0 {
    c.box(style=@ui.style(w=Full, h=Fixed(h)), fn() {  }) |> ignore
  }
}

///|
/// The room a place's top page keeps at its foot for the bottom bar (App.kt LocalBarRoom: none on a wide screen).
pub let bar_room : Ref[Double] = Ref(0.0)

///|
/// Whether the page being drawn is a place of the bottom bar's at the stack's root (`page`'s `root`).
let at_root : Ref[Bool] = Ref(false)

///|
/// Under the app's top bar (`page`'s `top`: a place's top page on a phone, PlacePage.kt), how far down what the page
/// shows starts, scrolling under the bar; 0 where the page has a bar of its own over it.
let root_top : Ref[Double] = Ref(0.0)

///|
/// The room what a page shows keeps at its top for the app's top bar over it (`root_top`), none elsewhere.
fn top_room() -> Double {
  if at_root.val {
    root_top.val
  } else {
    0.0
  }
}

///|
/// What the back of a pushed place's page says (PlacePage.kt underLabel): the chats or settings, else `or_else`.
fn under_label(core : Core, or_else : String) -> String {
  match (core.under)() {
    "chats" => tr("android-misc.bar.place.chats")
    "settings" => tr("android-settings.title")
    _ => or_else
  }
}

///|
/// A place's page pushed (PlacePage.kt, not a bar's top): the compact bar, back to the page under it, its title; its
/// actions at the bar's end; what it shows under it, 4 down. At the bar's top (`page`'s root) the app's top bar is
/// over it instead, holding its actions, and only what it shows is drawn here, from the top of the page.
fn place_page(
  c : @ui.Ctx,
  core : Core,
  title : String,
  body : () -> Unit,
  back? : String = tr("android-settings.title"),
  actions? : () -> Unit,
  primary? : (String, (@sf.Beside) -> Unit),
  about? : String = "",
) -> Unit {
  c.box(style=page_fill, fn() {
    let under_bar = top_room() > 0.0
    // the wide frame's place (连接, 用量: across the pane): the web's head, its title and at its end what it does, its
    // primary one a pill named as what it adds
    if wide.val && at_root.val && !under_bar {
      match frame_core.val {
        Some(core) =>
          wide_head(c, core, "", title, about~, trailing=fn() {
            match actions {
              Some(a) => a()
              None => ()
            }
            match primary {
              Some((key, run)) => {
                let label = match key {
                  "add-station" => tr("android-misc.bar.action.stations")
                  "add-profile" => tr("android-misc.bar.action.profiles")
                  "add-connect" => tr("android-misc.bar.action.connects")
                  _ => ""
                }
                if head_pill(c, key, label) {
                  run(Of(c.id(key)))
                }
              }
              None => ()
            }
          })
        None => ()
      }
      c.box(style=root_body, fn() { body() }) |> ignore
      return
    }
    match (actions, primary) {
      // (at the root its actions in the app's top bar over it; in the wide frame, which has no such bar, at the end of
      // a row of their own over what it shows; its primary one is the bar's notch's)
      (Some(a), _) if under_bar => @sf.named_actions.val = Some(a)
      (Some(a), _) if at_root.val => c.box(style=root_actions, fn() { a() }) |> ignore
      (None, _) if at_root.val => ()
      (None, None) => nav_bar(c, core, under_label(core, back), title)
      _ =>
        nav_bar(c, core, under_label(core, back), title, trailing=fn() {
          c.box(style=bar_actions, fn() {
            match actions {
              Some(a) => a()
              None => ()
            }
            // its ＋, named as what it adds (PlusButton)
            match primary {
              Some((key, run)) =>
                if nav_button(
                    c,
                    key,
                    "plus",
                    size=20.0,
                    said=match key {
                      "add-station" => tr("android-misc.bar.action.stations")
                      "add-profile" => tr("android-misc.bar.action.profiles")
                      "add-connect" => tr("android-misc.bar.action.connects")
                      _ => ""
                    },
                  ) {
                  run(Of(c.id(key)))
                }
              None => ()
            }
          })
          |> ignore
        })
    }
    c.box(
      style=if under_bar {
        page_fill
      } else if at_root.val {
        root_body
      } else {
        place_body
      },
      fn() { body() },
    )
    |> ignore
  })
  |> ignore
}

///|
/// All of where it is.
// kept across runs: a value (no field of it changes)
let page_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A place's page's actions, 10 apart: in the bar, or at the root at the end of a line of their own, 16 in, 8 down.
// kept across runs: a value (no field of it changes)
let bar_actions : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let root_actions : @ui.Style = bar_actions.then(@ui.css("w=Full px=S4 pt=S2 justify=JEnd"))

///|
/// What a place's page shows, 4 under its bar.
// kept across runs: a value (no field of it changes)
let place_body : @ui.Style = page_fill.then(@ui.css("pt=S1"))

///|
/// What a place's page shows at the bar's top in the wide frame, 8 under its page bar (PlacePage.kt: `bar + 8.dp`).
// kept across runs: a value (no field of it changes)
let root_body : @ui.Style = page_fill.then(@ui.css("pt=S2"))

///|
/// A page's large title (Parts.kt LargeTitle): `small`'s line over the big word when it is said, the word after `lead`
/// when there is one (a workspace's mark). (LargeTitle's letterSpacing -0.6sp: mbui's words have no spacing.)
fn large_title(
  c : @ui.Ctx,
  big : String,
  small? : String = "",
  lead? : () -> Unit,
  about? : String = "",
  says? : String = "",
  trailing? : () -> Unit,
) -> Unit {
  if wide.val {
    ignore(lead)
    // what stands at the title's end: given here (a desktop page's actions), else as top_back left it
    let trailing = match trailing {
      Some(f) => Some(f)
      None => top_trailing.val
    }
    match frame_core.val {
      Some(core) =>
        wide_head(c, core, top_label.val, big, trailing?, inside=true, on_back?=top_on_back.val, about~, lead=says)
      None => ()
    }
    top_trailing.val = None
    top_on_back.val = None
    return
  }
  c.box(style=large_title_box, fn() {
    if small != "" {
      // Parts.kt:558 (13sp)
      c.text(small, style=@sf.secondary) |> ignore
    }
    c.box(style=title_line, fn() {
      match lead {
        Some(f) => f()
        None => ()
      }
      // Parts.kt:559 (32sp)
      c.text(big, style=@sf.large_title) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// LargeTitle: 16 in, 6 under it; its small line over its word's.
// kept across runs: a value (no field of it changes)
let large_title_box : @ui.Style = @ui.css("w=Full px=S4 pb=S1_5")

///|
/// A section's heading (Parts.kt SectionHeader): its title, what it holds at its end; `start` its room at its start
/// (20; the settings pages' say 24, S6, as their SectionHeaders do).
fn section_header(
  c : @ui.Ctx,
  title : String,
  trailing? : String = "",
  start? : @ui.Space = S5,
  mark? : (() -> Unit)? = None,
) -> Unit {
  // the wide frame's (ui Section, parts.css.ts sectionHead: its title 14 on 22 in 600 at the column's edge, 28 over
  // it; what it holds said 3 under it in the meta's 12 muted, as the web's Section's description)
  if wide.val {
    // right under the page's head: 28 under it in all (its 12 and 16), as the web's first section is (the page's head's
    // margin and the sections' own between them, not over the first)
    let first = block_at.val >= 0 && block_at.val == head_block.val + 1
    // (with what it holds said here, 10 under that, as the web's head is over its section)
    let said = trailing != ""
    c.box(
      style=match (first, said) {
        (true, true) => wide_section_first_said
        (true, false) => wide_section_first
        (false, true) => wide_section_said
        (false, false) => wide_section_box
      },
      fn() {
        c.box(style=wide_section_line, fn() {
          match mark {
            Some(m) => m()
            None => ()
          }
          c.text(title, style=wide_section_title) |> ignore
        })
        |> ignore
        if said {
          c.text(trailing, style=wide_section_sub) |> ignore
        }
      },
    )
    |> ignore
    return
  }
  c.box(style=section_line.then(@ui.style(pl=start)), fn() {
    match mark {
      // a mark before the title, on the middle of its words (SectionHeader's mark)
      Some(m) =>
        c.box(style=section_marked, fn() {
          m()
          // Parts.kt:585 (15sp; in lines where it is long)
          c.text(title, style=@sf.body.then(@sf.strong)) |> ignore
        })
        |> ignore
      // Parts.kt:585 (15sp; in lines where it is long)
      None => c.text(title, style=@sf.body.then(@sf.strong)) |> ignore
    }
    c.spacer()
    if trailing != "" {
      // Parts.kt:591 (13sp)
      c.text(trailing, style=@sf.secondary.then(@sf.one_line)) |> ignore
    }
  })
  |> ignore
}

///|
/// SectionHeader's line (its start said where it is used, 20 unless said): 20 in at its end, 14 over, 6 under, its
/// words on the line's foot.
// kept across runs: a value (no field of it changes)
let section_line : @ui.Style = @ui.css("row w=Full pl=S5 pr=S5 pt=S3_5 pb=S1_5 align=AEnd gap=S2")

///|
/// A marked SectionHeader's mark and title, 6 apart, on the middle of its words.
// kept across runs: a value (no field of it changes)
let section_marked : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// The wide frame's section head: 16 in as the title is, 28 over it, 2 under (its note, or what it holds, 10 under it
/// then); its mark and title in a line, what it holds 2 under them.
// kept across runs: a value (no field of it changes)
let wide_section_box : @ui.Style = @ui.css("w=Full px=S4 pt=S7 pb=S0_5 gap=S0_5")

///|
// kept across runs: a value (no field of it changes)
let wide_section_first : @ui.Style = wide_section_box.then(@ui.css("pt=S4"))

///|
// kept across runs: a value (no field of it changes)
let wide_section_said : @ui.Style = wide_section_box.then(@ui.css("pb=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let wide_section_first_said : @ui.Style = wide_section_first.then(@ui.css("pb=S2_5"))

///|
// kept across runs: a value (no field of it changes)
let wide_section_line : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// A section's title in the wide frame: its scale's Xl2, 14 on 22 there (page: wide_heading), as the library's section
/// title is, one size for every page's.
// kept across runs: a value (no field of it changes)
let wide_section_title : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let wide_section_sub : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let wide_meta : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// What a section is about, under its head where the wide frame says it (page.css.ts sectionSub: 12, muted, 3 under
/// the head, 10 over what it holds); none on a phone, whose pages say it under what it holds.
fn section_note(c : @ui.Ctx, words : String) -> Unit {
  if !wide.val || words == "" {
    return
  }
  c.box(style=wide_section_note, fn() { c.text(words, style=wide_note_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wide_section_note : @ui.Style = @ui.css("w=Full px=S4 pt=S0_5 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let wide_note_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
/// What stands at the column's edge in the wide frame, 16 in as the title is (a section's control); 12 on a phone.
fn inset(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=if wide.val { wide_inset } else { phone_inset }, body) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wide_inset : @ui.Style = @ui.css("w=Full px=S4")

///|
// kept across runs: a value (no field of it changes)
let phone_inset : @ui.Style = @ui.css("w=Full px=S3")

///|
/// A page's note under its title, in a line or two (SettingParts.kt PageNote).
fn page_note(c : @ui.Ctx, words : String) -> Unit {
  if wide.val {
    c.box(style=wide_page_note, fn() { c.text(words, style=wide_lead) |> ignore }) |> ignore
    return
  }
  c.box(style=page_note_box, fn() {
    // SettingParts.kt:266 (13sp)
    c.text(words, style=@sf.secondary.then(@sf.full_words)) |> ignore
  })
  |> ignore
}

///|
/// The wide frame's lead under the title (pages.css.ts pageHead p: 13, muted).
// kept across runs: a value (no field of it changes)
let wide_page_note : @ui.Style = @ui.css("w=Full px=S4 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let wide_lead : @ui.TextStyle = @ui.text_style(size=Body, color=Muted, w=Full)

///|
/// PageNote's room: 24 in, 10 under it.
// kept across runs: a value (no field of it changes)
let page_note_box : @ui.Style = @ui.css("w=Full px=S6 pb=S2_5")

///|
/// What stands in a card's foot corners (the ladder's: docs/ui-panels.md「圆角阶梯」), so how far in its foot is: a
/// capsule (a button, a field: settings_button_h high), concentric with the card's corner, reaching past its words to there
/// (`foot_across`, `foot_start`); a block (a command's box), the ladder's inset, reaching past them to it
/// (`block_across`), round by the ladder's next step there; or nothing with a ground, its words card_pad in.
priv enum Foot {
  Words
  Capsule
  Block
}

///|
/// A card on the page (Parts.kt Card): 12 in from the sides, 10 under it, its words 20 in; round by the ladder's card
/// corner, whatever stands in its corners concentric with it (`foot`: what stands in its foot corners); tapped when
/// `key` is given. True on the frame after a tap.
fn card(c : @ui.Ctx, body : () -> Unit, key? : String = "", foot? : Foot = Words) -> Bool {
  let id = if key == "" { 0 } else { c.id(key) }
  let ground = match foot {
    Words => card_ground
    Capsule => card_foot_ground
    Block => card_block_ground
  }
  c.box(style=if wide.val { wide_card_room } else { card_room }, fn() {
    c.box(style=ground, id~, fn() {
      body()
      // Parts.kt Card: clickable over its clip (Smooth: its corner)
      if id != 0 {
        @motion.ripple(c, id, @sf.card_corner)
      }
    })
    |> ignore
  })
  |> ignore
  id != 0 && hit(c, id)
}

///|
/// A card's room on the page: 12 from its sides, 10 under it; in the wide frame its edge at the column's, where the
/// title stands (16 in).
// kept across runs: a value (no field of it changes)
let card_room : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let wide_card_room : @ui.Style = @ui.css("w=Full px=S4 pb=S2_5")

///|
/// A card: 20 in (CARD_PAD), round by the ladder's card corner; rippled where it is tapped (an id).
// kept across runs: a value (no field of it changes)
let card_ground : @ui.Style = @ui.css("w=Full p=S5 radius=Xl3 bg=Card clip")

///|
///|
/// A settings button's height (Controls.kt Button: 38).
pub let settings_button_h : Double = 38.0

///|
/// A button (`button`) in a card's foot corners, its ground reaching past the card's words to where it is concentric
/// with the card's corner (@sf.card_foot_in): across the card (what is in it centred), or at its start (a button with
/// words after it: its words where they were).
// kept across runs: a value (no field of it changes)
pub let foot_across : @ui.Style = @sf.foot_across(settings_button_h)

///|
// kept across runs: a value (no field of it changes)
let foot_start : @ui.Style = @sf.foot_start(settings_button_h, button_pad)

///|
/// A block across a card's foot, its ground reaching past the card's words to the ladder's inset.
// kept across runs: a value (no field of it changes)
let block_across : @ui.Style = @sf.block_across

///|
/// A settings button's words in from its ends (button_box: 16).
let button_pad : Double = 16.0

///|
/// A card with a block in its foot corners: its foot the ladder's inset.
// kept across runs: a value (no field of it changes)
let card_block_ground : @ui.Style = card_ground.then(@ui.style(pb=@sf.inset_room))

///|
/// A card with a button in its foot corners: its foot as far in as makes it concentric (@sf.foot_pad).
// kept across runs: a value (no field of it changes)
let card_foot_ground : @ui.Style = card_ground.then(@sf.foot_pad(settings_button_h))

///|
/// Rows on one rounded card, no lines between them (Parts.kt ListCard, RowsCard): its rows know they are on one
/// (`on_card`, LocalOnCard). On every width, as the library's group is (docs/ui-panels.md 页面卡片: a group of rows on
/// a list card wide too; `boxed`, said where a page asked for the card in the wide frame before it was always one).
fn list_card(c : @ui.Ctx, body : () -> Unit, boxed? : Bool = false) -> Unit {
  ignore(boxed)
  c.box(style=if wide.val { wide_card_room } else { card_room }, fn() {
    c.box(style=list_ground, fn() {
      let was = on_card.val
      on_card.val = true
      body()
      on_card.val = was
    })
    |> ignore
  })
  |> ignore
}

///|
/// The rows' card itself, where its page puts it (Parts.kt RowsCard): its rows LIST_PAD in, knowing they are on one.
fn rows_card(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=list_ground, fn() {
    let was = on_card.val
    on_card.val = true
    body()
    on_card.val = was
  })
  |> ignore
}

///|
/// Whether what is being drawn is on a list card (Parts.kt LocalOnCard): a PickRow's ground is then the card's
/// padding in from its edge already. Set only while a list card's rows are drawn.
let on_card : Ref[Bool] = Ref(false)

///|
/// A list card: its rows list_pad in (as a menu's in its panel), round by the ladder's row corner, concentric with it.
// kept across runs: a value (no field of it changes)
let list_ground : @ui.Style = @ui.style(w=Full, p=@sf.list_room, radius=@sf.list_card_radius, bg=Card, clip=true)

///|
/// A row of a list card (Parts.kt ListRow): its ground concentric with the card's (LIST_ROW_CORNER), what it holds
/// CARD_PAD less LIST_PAD in all round (20 from the card's edges, as a card's words), 12 apart; tapped when `key` is given. True on
/// the frame after a tap. `piece`: the row a block of the page's list of its own, a piece of its card (card_piece:
/// whether it is the card's first row, its last).
fn list_row(c : @ui.Ctx, body : () -> Unit, key? : String = "", piece? : (Bool, Bool)) -> Bool {
  let id = if key == "" { 0 } else { c.id(key) }
  let row = fn(style : @ui.Style) {
    // (one that is tapped as high as a press's room at least, whatever it holds)
    c.box(style=if id != 0 { style.then(@sf.row_least_h()) } else { style }, id~, fn() {
      body()
      // Parts.kt ListRow: clickable over its clip, Smooth(LIST_ROW_CORNER)
      if id != 0 {
        @motion.ripple(c, id, @sf.row_corner)
      }
    })
    |> ignore
  }
  match piece {
    None => row(if wide.val { wide_list_line } else { list_line })
    Some((first, last)) => card_piece(c, first, last, fn() { row(list_piece_line) })
  }
  id != 0 && hit(c, id)
}

///|
/// A piece of a list card, a block of a page's list of its own (scroll_page lays out only the blocks in view: a card
/// of many rows, 本机缓存's chats, builds only the rows shown, not all of them each frame): the card's sides and
/// ground, 8 in above its first row and under its last, its corners there (the halves that are no end of the card
/// squared again by a patch of its ground), the card's 10 under it.
fn card_piece(c : @ui.Ctx, first : Bool, last : Bool, body : () -> Unit) -> Unit {
  c.box(style=match (last, wide.val) {
    (true, true) => wide_card_room
    (true, false) => card_room
    (false, true) => wide_card_piece_room
    (false, false) => card_piece_room
  }, fn() {
    let ground = match (first, last) {
      (true, true) => list_ground_open
      (true, false) => list_piece_first
      (false, true) => list_piece_last
      (false, false) => list_piece_ground
    }
    c.box(style=ground, fn() {
      c.layer(fn() { c.box(style=list_piece_fill, fn() {  }) |> ignore }) |> ignore
      // (the card's corner, 30.5 high wholly smooth, is within half of a row's 62: a patch leaves the other end's)
      if !first {
        c.layer(fn() {
          c.box(style=list_piece_patch, fn() {  }) |> ignore
          c.spacer()
        })
        |> ignore
      }
      if !last {
        c.layer(fn() {
          c.spacer()
          c.box(style=list_piece_patch, fn() {  }) |> ignore
        })
        |> ignore
      }
      let was = on_card.val
      on_card.val = true
      body()
      on_card.val = was
    })
    |> ignore
  })
  |> ignore
}

///|
/// A card's piece's room on the page but its last: 12 from its sides, nothing under it.
// kept across runs: a value (no field of it changes)
let card_piece_room : @ui.Style = @ui.css("w=Full px=S3")

///|
/// (in the wide frame, at the column's edge as its other cards: wide_card_room)
// kept across runs: a value (no field of it changes)
let wide_card_piece_room : @ui.Style = @ui.css("w=Full px=S4")

///|
/// A list card's piece: its rows list_pad in from its sides; as far above the card's first, under its last.
// kept across runs: a value (no field of it changes)
let list_piece_ground : @ui.Style = @ui.style(w=Full, px=@sf.list_room)

///|
// kept across runs: a value (no field of it changes)
let list_piece_first : @ui.Style = @ui.style(w=Full, px=@sf.list_room, pt=@sf.list_room)

///|
// kept across runs: a value (no field of it changes)
let list_piece_last : @ui.Style = @ui.style(w=Full, px=@sf.list_room, pb=@sf.list_room)

///|
// kept across runs: a value (no field of it changes)
let list_ground_open : @ui.Style = @ui.style(w=Full, p=@sf.list_room)

///|
/// A list card's piece's ground: the card's, its corners (LIST_CARD_CORNER).
// kept across runs: a value (no field of it changes)
let list_piece_fill : @ui.Style = @ui.style(w=Full, h=Full, radius=@sf.list_card_radius, bg=Card)

///|
/// Half of a card's piece squared again (Full: as the spacer beside it grows), the card's ground.
// kept across runs: a value (no field of it changes)
let list_piece_patch : @ui.Style = @ui.css("w=Full h=Full bg=Card")

///|
/// A row of a card's piece: ListRow's line, its corner the ladder's row corner said (18, Xl2 on the scale: what `Inner`
/// works out on a whole card; a piece's ground is no container of it, squared where it is no end of it).
// kept across runs: a value (no field of it changes)
let list_piece_line : @ui.Style = list_line.then(@ui.css("radius=Xl2"))

///|
/// The wide frame's row (pages.css.ts listRow): 52 high at least, 10 over and under, its words a row's room in
/// (list_words_room), the field's corner under the pointer.
// kept across runs: a value (no field of it changes)
let wide_list_line : @ui.Style = @ui.css("row w=Full min_h=S12 py=S2_5 gap=S3 radius=Inner align=ACenter hovered{bg=Hover}")
  .then(@ui.style(px=@sf.list_words_room))

///|
/// ListRow's line: its words a row's room in all round (list_words_room: 16 from the card's edge, as a menu's), 12
/// apart, rounded concentric with its card.
// kept across runs: a value (no field of it changes)
let list_line : @ui.Style = @ui.css("row w=Full gap=S3 radius=Inner align=ACenter").then(
  @ui.style(p=@sf.list_words_room),
)

///|
/// A row's main words, as wide as the row lets them, cut to one line.
fn row_title(c : @ui.Ctx, words : String, color? : Int64) -> Unit {
  // SettingParts.kt:255 (15sp); the wide frame's 13 (pages.css.ts cardRowText)
  c.text(words, style=if wide.val { wide_row_title } else { row_title_words }, color?) |> ignore
}

///|
/// The wide frame's row words (pages.css.ts listRow, cardRowText: 13; what is under them 12).
// kept across runs: a value (no field of it changes)
let wide_row_title : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let wide_row_title_lines : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let wide_row_sub : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let wide_row_sub_lines : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let wide_value : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
/// A row's title: the body's words on one line, as wide as the row lets them.
// kept across runs: a value (no field of it changes)
let row_title_words : @ui.TextStyle = @sf.body.then(@sf.one_line).then(@sf.full_words)

///|
/// A row's title with a tag after it: its words' width, on one line.
// kept across runs: a value (no field of it changes)
let row_title_tagged : @ui.TextStyle = @sf.body.then(@sf.one_line)

///|
/// A row's title in lines where it is long.
// kept across runs: a value (no field of it changes)
let row_title_lines : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
/// A row's title with a line under it, as wide as the row lets them; the title in lines where it is long, or cut to
/// one (`wrap_title` false: where Android says maxLines = 1). `title_color`, `sub_color`: in place of the roles' (a
/// warning's, worked out where it is called). `end`: what the row has at its end (a size, a chevron), on the title's
/// line, the line under it then as wide as the row (a line of its own: @sf.row_lines).
fn row_lines(
  c : @ui.Ctx,
  title : String,
  sub : String,
  sub_color? : Int64,
  title_color? : Int64,
  wrap_title? : Bool = true,
  wrap_sub? : Bool = false,
  end? : () -> Unit,
) -> Unit {
  c.box(style=@sf.full_width, fn() {
    // Connects.kt:231, Security.kt:191 (15sp)
    let title_words = fn() {
      c.text(
        title,
        style=match (wide.val, wrap_title) {
          (true, true) => wide_row_title_lines
          (true, false) => wide_row_title
          (false, true) => row_title_lines
          (false, false) => row_title_words
        },
        color?=title_color,
      )
      |> ignore
    }
    match end {
      Some(f) =>
        c.box(style=row_head_line, fn() {
          c.box(style=@sf.pg_row_words, title_words) |> ignore
          f()
        })
        |> ignore
      None => title_words()
    }
    if sub != "" {
      // Connects.kt:232, Security.kt:192 (13sp)
      c.text(
        sub,
        style=match (wide.val, wrap_sub) {
          (true, true) => wide_row_sub_lines
          (true, false) => wide_row_sub
          (false, true) => row_sub_lines
          (false, false) => row_sub_line
        },
        color?=sub_color,
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// A row's title and what the row has at its end, 12 apart, across their middle.
// kept across runs: a value (no field of it changes)
let row_head_line : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
/// The line under a row's title: one, or in lines.
// kept across runs: a value (no field of it changes)
let row_sub_lines : @ui.TextStyle = @sf.secondary.then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
let row_sub_line : @ui.TextStyle = row_sub_lines.then(@sf.one_line)

///|
/// The chevron at a row's end.
fn chevron(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  @sf.icon(c, "chevron-right", size=14.0, color=t.p.subtle) |> ignore
}

///|
/// A row that opens a page (SettingParts.kt GoRow): its icon (settings' rows: `icon`, design/icons' name), its name, how
/// things stand at its end (`bad` in red; `dot`, a red dot before it), a chevron. True on the frame after a tap.
fn go_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  value? : String = "",
  bad? : Bool = false,
  dot? : Bool = false,
  icon? : String = "",
  lead? : () -> Unit,
) -> Bool {
  list_row(c, key~, fn() {
    if icon != "" {
      row_icon(c, icon)
    }
    match lead {
      Some(f) => f()
      None => ()
    }
    row_title(c, title)
    if value != "" {
      c.box(style=near_beside, max_w=220.0, fn() {
        if dot {
          presence_dot(c, "error")
        }
        // SettingParts.kt:258 (14sp)
        let look = if wide.val { wide_value } else { @sf.value }
        c.text(value, style=if bad { look.then(@sf.bad) } else { look }) |> ignore
      })
      |> ignore
    }
    chevron(c)
  })
}

///|
/// A settings row's icon, before its name (SettingParts.kt RowIcon): the line art in the muted ink.
fn row_icon(c : @ui.Ctx, name : String) -> Unit {
  let t = @sf.theme()
  @sf.icon(c, name, size=@sf.row_icon, color=t.p.muted) |> ignore
}

///|
/// Things in a line, centred across it, 6 apart (a dot and its words, a mark and a word).
// kept across runs: a value (no field of it changes)
let near_beside : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
/// A switch (PageParts.kt Switch): 44 by 26, green when on, its knob white: mbui's switch's look (@kit.switch_look_of)
/// in still.fail's colours; the row it is in takes the tap. Its knob slides as mbui's switch's does
/// (`@kit.switch_knob` by `key`, unique where it is asked); Android's jumps.
pub fn switch(c : @ui.Ctx, key : String, on : Bool) -> Unit {
  let t = @sf.theme()
  @kit.switch_look_of(w=44.0, h=26.0, inset=3.0, on_color=t.p.green, off_color=t.p.line, knob=0xFFFFFFFFL, shadow=false)(
    c,
    {
      on,
      t: @kit.switch_knob(c, key, on),
      hovered: false,
      pressed: false,
      held: 0.0,
      focus_shown: false,
      disabled: false,
    },
  )
}

///|
/// A connect's presence, a station's state (PageParts.kt PresenceDot): online green, at work the accent, failing red,
/// else a hollow ring.
fn presence_dot(c : @ui.Ctx, state : String) -> Unit {
  match state {
    "online" => c.box(style=dot_online, fn() {  }) |> ignore
    "busy" => c.box(style=dot_busy, fn() {  }) |> ignore
    "error" => c.box(style=dot_error, fn() {  }) |> ignore
    // (its edge 1.5, off the scale of edges)
    _ => c.box(style=dot_ring, border=1.5, fn() {  }) |> ignore
  }
}

///|
/// A small dot (PresenceDot, Dot): 7 round.
// kept across runs: a value (no field of it changes)
let dot_shape : @ui.Style = @ui.style(w=@sf.dot_size, h=@sf.dot_size, radius=Full)

///|
// kept across runs: a value (no field of it changes)
let dot_online : @ui.Style = dot_shape.then(@ui.css("bg=Positive"))

///|
// kept across runs: a value (no field of it changes)
let dot_busy : @ui.Style = dot_shape.then(@ui.css("bg=Accent"))

///|
// kept across runs: a value (no field of it changes)
let dot_error : @ui.Style = dot_shape.then(@ui.css("bg=Danger"))

///|
// kept across runs: a value (no field of it changes)
let dot_ring : @ui.Style = dot_shape.then(@ui.css("border_color=Subtle"))

///|
/// A check's tone as a presence dot (Stations.kt toneDot).
fn tone_dot(tone : String) -> String {
  match tone {
    "green" => "online"
    "red" => "error"
    "neutral" => "offline"
    _ => "busy"
  }
}

///|
/// A person's picture (Parts.kt Avatar): theirs once it is here, else their initial on their colour.
pub fn avatar(c : @ui.Ctx, core : Core, id : String, name : String, size : Double, picture? : String = "") -> Unit {
  @sf.avatar(c, id, name, if picture == "" { "" } else { (core.picture)(picture, c.page_stint()) }, size)
}

///|
/// A word in the accent's wash (Settings.kt You: 你, 本机).
pub fn you(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=you_ground, fn() {
    // Settings.kt:294 (12sp)
    c.text(words, style=you_words) |> ignore
  })
  |> ignore
}

///|
/// You's wash: 6 in at its sides, 6 round.
// kept across runs: a value (no field of it changes)
let you_ground : @ui.Style = @ui.css("px=S1_5 radius=Md bg=AccentBg")

///|
/// Small words in the accent's ink (in lines where there is no room: Settings.kt:294 has no maxLines).
// kept across runs: a value (no field of it changes)
let you_words : @ui.TextStyle = @sf.caption.then(@ui.text_style(color=AccentText))

///|
/// The turning ring (Waiting.kt Spinner): 14, or 12 in a line of small text.
pub fn spinner(c : @ui.Ctx, inline? : Bool = false) -> Unit {
  @sf.spinner(c, size=if inline { 12.0 } else { 14.0 }) |> ignore
}

///|
/// Where what someone set going shows how it is (Controls.kt DoingMark): a spinner while it is under way, a small red
/// mark for a few seconds after it failed, why over it while it is pointed at (DoingMark.tsx DoingShown's tip: the
/// row or the menu that asked may have gone, the toast too). Its tip named by where it is called, as its place is.
#callsite(autofill(loc))
pub fn doing_mark(c : @ui.Ctx, running : Bool, failed : String?, inline? : Bool = false, loc~ : SourceLoc) -> Unit {
  let t = @sf.theme()
  if running {
    spinner(c, inline~)
  } else if failed is Some(why) {
    let key = "doing-mark/" + loc.to_string()
    let id = c.id(key)
    c.box(id~, taps=false, points=true, fn() { @sf.icon(c, "info", size=if inline { 12.0 } else { 14.0 }, color=t.p.red) |> ignore })
    |> ignore
    @sf.tip(c, key, id, if why == "" { @sf.t("web-main.doing.failed") } else { why })
  }
}

///|
/// A wait said in a line of its own (the library's WaitLine: @sf.wait_line, a spinner before it after a moment; what is
/// wrong in red at once); `pad`: in from its sides as a card's words.
pub fn wait_line(c : @ui.Ctx, words : String, error? : Bool = false, pad? : Bool = false) -> Unit {
  if pad {
    c.box(style=wait_line_padded, fn() { @sf.wait_line(c, words, error~) }) |> ignore
  } else {
    @sf.wait_line(c, words, error~)
  }
}

///|
/// A wait's line in a page's flow: in from its sides as a card's words.
// kept across runs: a value (no field of it changes)
let wait_line_padded : @ui.Style = @ui.css("w=Full px=S5 py=S2")

///|
/// A settings page's cards to come (the library's Waiting): `sample`, what the page will show of made-up words, in its
/// bones, 12 in from the page's sides; what could not be read over them in red (the bones then still).
pub fn waiting_cards(c : @ui.Ctx, sample : () -> Unit, error? : String = "", failing? : Array[String] = []) -> Unit {
  c.box(style=wait_cards_in, fn() {
    @sf.waiting(c, sample, error~, note={ reading: failing.length() == 0, text: "", failing })
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wait_cards_in : @ui.Style = @ui.css("w=Full px=S3")

///|
/// A list's rows to come (the library's Waiting): `sample`, its rows of made-up words, in their bones; what could not
/// be read over them in red.
fn waiting_rows(c : @ui.Ctx, sample : () -> Unit, error? : String = "", failing? : Array[String] = []) -> Unit {
  @sf.waiting(c, sample, error~, note={ reading: failing.length() == 0, text: "", failing })
}

///|
/// What could not be read of a list, by the stations that failed (a ListNote's `failing`).
pub fn failing_of(note : Json?) -> Array[String] {
  items(note, "failing").map(fn(f) { text(Some(f), "text") })
}

///|
/// Whether a list's note still waits (a station not read, or one that could not be).
fn note_waits(note : Json?) -> Bool {
  flag(note, "reading") || items(note, "failing").length() > 0
}

///|
/// What the page is for, said where its list is empty (PlaceRows.kt PlaceEmpty).
fn place_empty(c : @ui.Ctx, words : String, note? : String = "") -> Unit {
  c.box(style=place_empty_box, fn() {
    // PlaceRows.kt:55 (14sp)
    c.text(words, style=@sf.value.then(@sf.in_lines).then(@sf.centered)) |> ignore
    if note != "" {
      // PlaceRows.kt:56 (13sp)
      c.text(note, style=@sf.secondary.then(@sf.quieter).then(@sf.centered)) |> ignore
    }
  })
  |> ignore
}

///|
/// PlaceEmpty's room: 32 in, 40 over and under, its lines 8 apart in its middle.
// kept across runs: a value (no field of it changes)
let place_empty_box : @ui.Style = @ui.css("w=Full px=S8 py=S10 gap=S2 align=ACenter")

///|
/// A main action as wide as where it is (Security.kt WideButton): 46 high; primary in ink (red when `danger`), the
/// other the ink at 8%.
fn wide_button(
  c : @ui.Ctx,
  key : String,
  label : String,
  primary : Bool,
  busy? : Bool = false,
  enabled? : Bool = true,
  danger? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ground = if !primary {
    @sf.alpha(t.p.text, 0.08)
  } else if danger {
    if enabled {
      t.p.red
    } else {
      @sf.alpha(t.p.red, 0.4)
    }
  } else if !enabled {
    t.p.line
  } else {
    t.p.text
  }
  let ink = if primary && danger {
    0xFFFFFFFFL
  } else if primary {
    t.p.bg
  } else {
    t.p.text
  }
  // (46 high, off the scale; its ground and ink from what it is)
  c.box(style=wide_button_box, h=Px(wide_button_h), bg=ground, id~, fn() {
    if busy {
      @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
    }
    // Security.kt:127 (15sp)
    c.text(label, style=@sf.body.then(@sf.strong).then(@sf.one_line), color=ink) |> ignore
    // Security.kt WideButton: clickable over its capsule
    if enabled && !busy {
      @motion.ripple(c, id, wide_button_h / 2.0)
    }
  })
  |> ignore
  enabled && !busy && hit(c, id)
}

///|
/// A wide button's height (Security.kt WideButton: 46).
let wide_button_h : Double = 46.0

///|
/// WideButton: a capsule as wide as where it is, its words in its middle, 20 from its ends however narrow it is
/// (Security.kt WideButton: padding(horizontal = 20.dp)).
// kept across runs: a value (no field of it changes)
let wide_button_box : @ui.Style = @ui.css("row w=Full px=S5 radius=Full gap=S2 align=ACenter justify=JCenter")

///|
/// PickRow: 12 from the sheet's sides; its line 8 and 12 in, 12 apart, rippled where it is pressed (not when off);
/// its label after its mark, 6 apart. On a list card (Controls.kt:62 onCard) to the card's padding, its line
/// 12 in and rounded concentric with the card, as a ListRow.
// kept across runs: a value (no field of it changes)
let pick_room : @ui.Style = @ui.css("w=Full px=S3")

///|
// kept across runs: a value (no field of it changes)
let pick_line_off : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let pick_line : @ui.Style = pick_line_off

///|
// kept across runs: a value (no field of it changes)
let pick_card_line_off : @ui.Style = pick_line_off.then(@ui.css("px=S3 radius=Inner"))

///|
// kept across runs: a value (no field of it changes)
let pick_card_line : @ui.Style = pick_line.then(@ui.css("px=S3 radius=Inner"))

///|
// kept across runs: a value (no field of it changes)
let pick_label_line : @ui.Style = near_beside.then(@sf.full_width)

///|
/// A word at a row's end that does something (Settings.kt RowAction: 移除, 撤回): a spinner in its place while it is
/// under way, a red mark before it a moment after it failed. True on the frame after a tap.
fn row_action(c : @ui.Ctx, key : String, label : String, busy : Bool, failed : String?) -> Bool {
  if busy {
    spinner(c)
    return false
  }
  let id = c.id(key)
  c.box(style=near_beside, fn() {
    doing_mark(c, false, failed)
    c.box(id~, fn() {
      // Settings.kt:288 (14sp)
      c.text(label, style=@sf.value.then(@sf.accent)) |> ignore
      // Controls.kt pressText: rippled round its words, 6 past them on each side and 3 above and under, 8 round
      @motion.ripple(c, id, press_corner, out_x=press_out, out_y=press_out / 2.0)
    })
    |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// A text button's ground under the finger past its words (Controls.kt pressText: PRESS_OUT on each side, half that
/// above and under), and its corner (PRESS_CORNER).
let press_out : Double = 6.0

///|
let press_corner : Double = 8.0

///|
/// Words to tap with room round them, what is tapped (BarSettings.kt 设为当前, 删除: padding(4) inside its clickable).
// kept across runs: a value (no field of it changes)
let press_room : @ui.Style = @ui.css("p=S1")

///|
/// Words that do something when tapped (a link's look: Theme.kt link). True on the frame after a tap.
pub fn tap_text(
  c : @ui.Ctx,
  key : String,
  label : String,
  color? : Int64,
  size? : Double = 15.0,
  said? : String = "",
  room? : Bool = false,
) -> Bool {
  let id = c.id(key)
  // `room`: 4 round its words, what it takes (BarSettings.kt's 设为当前, 删除: padding(4) inside what is tapped)
  let b = c.box(style=if room { press_room } else { @ui.style() }, id~, fn() {
    // Settings.kt:447 (15sp), Profiles.kt:794, Vault.kt:365 (14sp): the theme's line, 1.4 its size (its size the
    // caller's)
    c.text(label, style=@sf.link.then(@sf.one_line), size~, line=size * 1.4, color?) |> ignore
    // with room: rippled over it, 6 round (BarSettings.kt: clip(Smooth(6)).clickable); else round its words as
    // Controls.kt pressText
    if room {
      @motion.ripple(c, id, 6.0)
    } else {
      @motion.ripple(c, id, press_corner, out_x=press_out, out_y=press_out / 2.0)
    }
  })
  // `said`: what it says to a screen reader in place of its words (its contentDescription)
  if said != "" {
    c.semantics(b, Button, id~, label=said)
  }
  hit(c, id)
}

///|
/// A round button in a bar (Parts.kt NavButton): its icon alone, 34 round. True on the frame after a tap.
fn nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0, said? : String = "") -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // (34 round, off the scale; rippled over its circle: NavButton's clip(CircleShape).clickable; `said` what it is to a
  // screen reader, a contentDescription round it)
  c.box(style=round_button, w=Px(34.0), h=Px(34.0), id~, label=said, fn() {
    @sf.icon(c, icon, size~, color=t.p.text) |> ignore
    @motion.ripple(c, id, 17.0)
  })
  |> ignore
  hit(c, id)
}

///|
/// NavButton: round, its icon in its middle.
// kept across runs: a value (no field of it changes)
let round_button : @ui.Style = @ui.css("radius=Full align=ACenter justify=JCenter")

///|
/// A body of words (PageParts.kt Body): on a list card 12 and 12 in (its words 20 from the card's edge, as its rows'),
/// else 16 and 14; 12 apart.
fn body(c : @ui.Ctx, f : () -> Unit) -> Unit {
  c.box(style=if on_card.val { body_on_card } else { body_box }, f) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let body_box : @ui.Style = @ui.css("w=Full px=S4 py=S3_5 gap=S3")

///|
// kept across runs: a value (no field of it changes)
let body_on_card : @ui.Style = body_box.then(@ui.css("px=S3 py=S3"))

///|
/// A paragraph and a quieter one under it (Security.kt Para).
fn para(c : @ui.Ctx, main : String, sub? : String = "") -> Unit {
  c.box(style=@sf.full_width, fn() {
    // Security.kt:105 (15sp, line 22)
    c.text(main, style=@sf.paragraph.then(@sf.full_words)) |> ignore
    if sub != "" {
      // Security.kt:106 (15sp, line 22)
      c.text(sub, style=@sf.lead.then(@sf.full_words)) |> ignore
    }
  })
  |> ignore
}

///|
/// A quiet note (Security.kt Note).
fn note(c : @ui.Ctx, words : String) -> Unit {
  // Security.kt:110 (12sp, line 18)
  c.text(words, style=@sf.note.then(@sf.full_words)) |> ignore
}

///|
/// A small dot: on green, else warn or the line's grey (Security.kt Dot).
fn dot(c : @ui.Ctx, on : Bool, warned? : Bool = false) -> Unit {
  let t = @sf.theme()
  c.box(
    style=dot_shape,
    bg=if on {
      t.p.green
    } else if warned {
      warn
    } else {
      t.p.line
    },
    fn() {  },
  )
  |> ignore
}

///|
/// A check's state in its words on a soft pill of its tone (Profiles.kt TonePill): green, the accent and amber in
/// their inks; its ground its colour at 12% (amber's 14%), the chip's grey for neutral.
fn tone_pill(c : @ui.Ctx, words : String, tone : String) -> Unit {
  let t = @sf.theme()
  let ink = match tone {
    "green" => t.p.green_ink
    "red" => t.p.red
    "blue" => t.p.blue
    "accent" => t.p.accent_text
    "amber" => t.p.warn_ink
    _ => t.p.muted
  }
  // (its ground its tone's at 12%, 14%: off the scale of opacities)
  let ground = match tone {
    "neutral" => t.p.chip
    "amber" => @sf.alpha(ink, 0.14)
    _ => @sf.alpha(ink, 0.12)
  }
  c.box(style=tone_pill_box, bg=ground, fn() {
    // Profiles.kt:760 (12sp)
    c.text(words, style=tone_pill_words, color=ink) |> ignore
  })
  |> ignore
}

///|
/// TonePill: 6 in at its sides, 1 over and under, 6 round.
// kept across runs: a value (no field of it changes)
let tone_pill_box : @ui.Style = @ui.css("px=S1_5 py=SPx radius=Md")

///|
// kept across runs: a value (no field of it changes)
let tone_pill_words : @ui.TextStyle = @sf.caption.then(@sf.one_line)

///|
/// Words in the code face (CodeFont: a code, a key, a variable), one line unless `wrap`.
/// With `style` (a role of @sf's styles.mbt), that, and what is said besides over it.
pub fn mono(
  c : @ui.Ctx,
  words : String,
  style? : @ui.TextStyle,
  size? : Double,
  weight? : Int,
  color? : Int64,
  line? : Double,
  wrap? : Bool = false,
  center? : Bool = false,
) -> Unit {
  // without a style, as it always was: 13, 400, the words' colour, the font's own line
  let (size, weight, color, line) = match style {
    Some(_) => (size, weight, color, line)
    None =>
      (
        Some(size.unwrap_or(13.0)),
        Some(weight.unwrap_or(400)),
        Some(color.unwrap_or(@sf.theme().p.text)),
        Some(line.unwrap_or(0.0)),
      )
  }
  if center {
    c.box(style=centre_column, fn() {
      c.rich([@ui.span(words, mono=true)], style?, size?, weight?, color?, line?, wrap~) |> ignore
    })
    |> ignore
  } else {
    c.rich(
      [@ui.span(words, mono=true)],
      style?,
      size?,
      weight?,
      color?,
      line?,
      wrap~,
      w=if wrap { Fill(1.0) } else { Auto },
    )
    |> ignore
  }
}

///|
/// What it holds in the middle of where it is, across.
// kept across runs: a value (no field of it changes)
let centre_column : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The core's done or waiting lead at the start of `s` (ui/StatusText.kt doneLead, waitLead; present.ts: 做完了,
/// 做完了：…; 在等：…, 等待中; Done, Done: …; Waiting, Waiting: …): whether it is done, and how long the lead is.
fn status_lead(s : String) -> (Bool, Int)? {
  for w in ["做完了", "已完成"] {
    if s == w {
      return Some((true, w.length()))
    }
    if s.has_prefix(w + "：") {
      return Some((true, w.length() + 1))
    }
  }
  if s == "Done" {
    return Some((true, 4))
  }
  if s.has_prefix("Done: ") {
    return Some((true, 6))
  }
  for w in ["在等：", "等待："] {
    if s.has_prefix(w) {
      return Some((false, w.length()))
    }
  }
  if s == "等待中" {
    return Some((false, s.length()))
  }
  if s == "Waiting" {
    return Some((false, 7))
  }
  if s.has_prefix("Waiting: ") {
    return Some((false, 9))
  }
  None
}

///|
/// A state in words, its done or waiting lead as a check or the wait mark before what follows it (ui/StatusText.kt).
fn status_text(c : @ui.Ctx, s : String, style~ : @ui.TextStyle) -> Unit {
  let t = @sf.theme()
  match status_lead(s) {
    Some((done, n)) => {
      let reason = s.view(start_offset=n).to_owned()
      c.box(style=status_line, fn() {
        @sf.icon(c, if done { "check" } else { "wait" }, size=status_icon, color=t.p.muted) |> ignore
        if reason != "" {
          c.text(" " + reason, style~) |> ignore
        }
      })
      |> ignore
    }
    None => c.text(s, style~) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let status_line : @ui.Style = @ui.css("row align=ACenter")

///|
/// A state's words, as small as where they stand has them: 11, 12, 13 (Connects.kt), muted, on one line.
// kept across runs: a value (no field of it changes)
let status_xs2 : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let status_xs : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let status_sm : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// A state's lead as an icon, as tall as the words (StatusText.kt: 14).
let status_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let pick_line_ground : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S1,
  py=@sf.pick_line_y,
  gap=S3,
  align=ACenter,
  radius=@sf.pick_line_r,
)

///|
// kept across runs: a value (no field of it changes)
let check_room : @ui.Style = @ui.style(w=@sf.check_room_w, align=ACenter)

///|
/// A page head's own action in the wide frame (ui.tsx Button with Plus): the library's button, its ＋ and words. True on
/// the frame after a press.
fn head_pill(c : @ui.Ctx, key : String, label : String) -> Bool {
  @sf.button(c, label, key~, icon="plus")
}

///|
/// A block of a sheet laid out here (in its column: @sf.sheet_column) after the first, 10 under the one before: room
/// between them, none under the last (its panel's own over its foot).
// kept across runs: a value (no field of it changes)
let sheet_block : @ui.Style = @ui.css("w=Full pt=S2_5")
