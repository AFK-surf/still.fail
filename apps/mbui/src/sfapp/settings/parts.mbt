// The settings pages' parts, as the Android app draws them (shared/ui/Parts.kt: NavBack, NavBar, LargeTitle,
// SectionHeader, Card, ListCard, ListRow, Seg, Avatar; screens/SettingParts.kt GoRow, PageNote; PageParts.kt Switch,
// PresenceDot; Controls.kt Button, PickRow, DoingMark; Waiting.kt Waiting, WaitLine; PlaceRows.kt PlaceEmpty;
// Stations.kt TopBack). Sizes in dp as there; colours src/sf's narrow palette (Theme.kt's).

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
/// under what stays at its top. `key` keeps its place while it is on the stack.
fn scroll_page(c : @ui.Ctx, key : String, blocks : Array[() -> Unit]) -> Unit {
  if wide.val {
    let side = wide_side(c)
    c.list("settings/" + key, blocks.length() + 1, 80.0, fn(i) {
      if i == blocks.length() {
        gap(c, 80.0)
      } else {
        c.box(style=@sf.full_width, pl=side, pr=side, fn() { (blocks[i])() }) |> ignore
      }
    })
    |> ignore
    return
  }
  c.list("settings/" + key, blocks.length(), 80.0, fn(i) { (blocks[i])() }) |> ignore
  fixture_scroll(c, "settings/" + key)
}

///|
/// A page's head in the wide frame (pages.css.ts pageHead): back above it only on a page under another, the title,
/// what it does at its end.
fn wide_head(
  c : @ui.Ctx,
  core : Core,
  back : String,
  title : String,
  trailing? : () -> Unit,
  inside? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  // (inside a block of the page, which stands in already)
  let side = if inside { 16.0 } else { wide_side(c) + 16.0 }
  c.box(style=if wide_deep.val { wide_head_deep } else { wide_head_top }, pl=side, pr=side, fn() {
    if wide_deep.val {
      let id = c.id("settings-back")
      c.cursor(id, Hand)
      c.box(style=wide_back, id~, fn() {
        @sf.icon(c, "chevron-left", size=14.0, color=t.p.muted) |> ignore
        c.text(back, size=13.0, color=if c.hovered(id) { t.p.text } else { t.p.muted }, wrap=false) |> ignore
      })
      |> ignore
      if hit(c, id) {
        (core.pop)()
      }
    }
    c.box(style=title_line, fn() {
      c.box(style=@sf.full_width, fn() {
        c.text(title, size=22.0, weight=600, color=t.p.text, wrap=false, line=34.0) |> ignore
      })
      |> ignore
      match trailing {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The wide frame's head: on a page under another (back over its title) 20 down, else 40; 12 under it.
// kept across runs: a value (no field of it changes)
let wide_head_top : @ui.Style = @ui.style(w=Full, pt=S10, pb=S3, bg=Bg)

///|
// kept across runs: a value (no field of it changes)
let wide_head_deep : @ui.Style = wide_head_top.then(@ui.style(pt=S5))

///|
/// The wide frame's back, over the head's title.
// kept across runs: a value (no field of it changes)
let wide_back : @ui.Style = @ui.style(row=true, pb=S2, gap=S1, align=ACenter)

///|
/// A title and what is at its end, in a line (LargeTitle's lead and big word too).
// kept across runs: a value (no field of it changes)
let title_line : @ui.Style = @ui.style(row=true, w=Full, gap=S2_5, align=ACenter)

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
/// Back at the top of a large-title page (Stations.kt TopBack); `trailing` at its other end (a ＋).
fn top_back(c : @ui.Ctx, core : Core, label : String, trailing? : () -> Unit) -> Unit {
  if wide.val {
    // (the large title under it is the head's: large_title)
    top_trailing.val = trailing
    top_label.val = label
    return
  }
  c.box(style=top_back_line, fn() {
    if nav_back(c, label) {
      (core.pop)()
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
let top_back_line : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S2_5,
  pt=S1_5,
  pb=S1,
  align=ACenter,
  justify=JBetween,
)

///|
/// What a large-title page's top had (top_back), for its head in the wide frame (large_title).
let top_trailing : Ref[(() -> Unit)?] = Ref(None)

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
) -> Unit {
  if wide.val {
    ignore(sub)
    match trailing {
      Some(f) => wide_head(c, core, back, title, trailing=f)
      None => wide_head(c, core, back, title)
    }
    return
  }
  if @sf.nav_bar(c, "settings-back", back, title, sub?=sub, trailing?=trailing, bg=@sf.theme().p.bg) {
    (core.pop)()
  }
}

///|
/// Whether the page being drawn is a place of the bottom bar's at the stack's root (`page`'s `root`).
let at_root : Ref[Bool] = Ref(false)

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
/// over it instead, and only what it shows is drawn here.
fn place_page(
  c : @ui.Ctx,
  core : Core,
  title : String,
  body : () -> Unit,
  back? : String = tr("android-settings.title"),
  actions? : () -> Unit,
  primary? : (String, () -> Unit),
) -> Unit {
  c.box(style=page_fill, fn() {
    match (actions, primary) {
      // (at the root its actions at the end of a row of their own, over what it shows; its primary one is the bar's
      // notch's)
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
              Some((key, run)) => if nav_button(c, key, "plus", size=20.0) { run() }
              None => ()
            }
          })
          |> ignore
        })
    }
    c.box(style=place_body, fn() { body() }) |> ignore
  })
  |> ignore
}

///|
/// All of where it is.
// kept across runs: a value (no field of it changes)
let page_fill : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// A place's page's actions, 10 apart: in the bar, or at the root at the end of a line of their own, 16 in, 8 down.
// kept across runs: a value (no field of it changes)
let bar_actions : @ui.Style = @ui.style(row=true, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let root_actions : @ui.Style = bar_actions.then(@ui.style(w=Full, px=S4, pt=S2, justify=JEnd))

///|
/// What a place's page shows, 4 under its bar.
// kept across runs: a value (no field of it changes)
let place_body : @ui.Style = page_fill.then(@ui.style(pt=S1))

///|
/// A page's large title (Parts.kt LargeTitle): `small`'s line over the big word when it is said, the word after `lead`
/// when there is one (a workspace's mark). (LargeTitle's letterSpacing -0.6sp: mbui's words have no spacing.)
fn large_title(c : @ui.Ctx, big : String, small? : String = "", lead? : () -> Unit) -> Unit {
  if wide.val {
    ignore(lead)
    match frame_core.val {
      Some(core) =>
        match top_trailing.val {
          Some(f) => wide_head(c, core, top_label.val, big, trailing=f, inside=true)
          None => wide_head(c, core, top_label.val, big, inside=true)
        }
      None => ()
    }
    top_trailing.val = None
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
let large_title_box : @ui.Style = @ui.style(w=Full, px=S4, pb=S1_5)

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
let section_line : @ui.Style = @ui.style(row=true, w=Full, pl=S5, pr=S5, pt=S3_5, pb=S1_5, align=AEnd, gap=S2)

///|
/// A marked SectionHeader's mark and title, 6 apart, on the middle of its words.
// kept across runs: a value (no field of it changes)
let section_marked : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
/// A page's note under its title, in a line or two (SettingParts.kt PageNote).
fn page_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=page_note_box, fn() {
    // SettingParts.kt:266 (13sp)
    c.text(words, style=@sf.secondary.then(@sf.full_words)) |> ignore
  })
  |> ignore
}

///|
/// PageNote's room: 24 in, 10 under it.
// kept across runs: a value (no field of it changes)
let page_note_box : @ui.Style = @ui.style(w=Full, px=S6, pb=S2_5)

///|
/// A card on the page (Parts.kt Card): 12 in from the sides, 10 under it, its words 20 in; its corner 22, or concentric
/// with a button in its corner (`foot`), or `corner` (taken from what else has a ground there: a Seg at its top);
/// tapped when `key` is given. True on the frame after a tap.
fn card(c : @ui.Ctx, body : () -> Unit, key? : String = "", foot? : Bool = false, corner? : @ui.Radius) -> Bool {
  let id = if key == "" { 0 } else { c.id(key) }
  let ground = match corner {
    Some(r) => card_ground.then(@ui.style(radius=r))
    None => if foot { card_foot_ground } else { card_ground }
  }
  c.box(style=card_room, fn() { c.box(style=ground, id~, body) |> ignore }) |> ignore
  id != 0 && hit(c, id)
}

///|
/// A card's room on the page: 12 from its sides, 10 under it.
// kept across runs: a value (no field of it changes)
let card_room : @ui.Style = @ui.style(w=Full, px=S3, pb=S2_5)

///|
/// A card: 20 in (CARD_PAD), 22 round (CARD_CORNER), the ink at 5% over it while pressed (tapped: an id).
// kept across runs: a value (no field of it changes)
let card_ground : @ui.Style = @ui.style(
  w=Full,
  p=S5,
  radius=Xl3,
  bg=Card,
  clip=true,
  pressed=@ui.patch(bg=Over(Card, A(Fg, O5))),
)

///|
/// A card with a button in its corner: 20 + 19 round.
// kept across runs: a value (no field of it changes)
let card_foot_ground : @ui.Style = card_ground.then(@ui.style(radius=@sf.card_foot_radius))

///|
/// Rows on one rounded card, no lines between them (Parts.kt ListCard, RowsCard): its rows know they are on one
/// (`on_card`, LocalOnCard).
fn list_card(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=card_room, fn() {
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
/// Whether what is being drawn is on a list card (Parts.kt LocalOnCard): a PickRow's ground is then the card's
/// padding in from its edge already. Set only while a list card's rows are drawn.
let on_card : Ref[Bool] = Ref(false)

///|
/// A list card: its rows 8 in (LIST_PAD), its corner concentric round theirs (LIST_CARD_CORNER).
// kept across runs: a value (no field of it changes)
let list_ground : @ui.Style = @ui.style(w=Full, p=S2, radius=@sf.list_card_radius, bg=Card, clip=true)

///|
/// A row of a list card (Parts.kt ListRow): its ground concentric with the card's (LIST_ROW_CORNER), its words 12 and
/// 12 in (CARD_PAD less LIST_PAD: 20 from the card's edge), what it holds 12 apart; tapped when `key` is given. True on
/// the frame after a tap.
fn list_row(c : @ui.Ctx, body : () -> Unit, key? : String = "") -> Bool {
  let id = if key == "" { 0 } else { c.id(key) }
  c.box(style=list_line, id~, body) |> ignore
  id != 0 && hit(c, id)
}

///|
/// ListRow's line: 12 and 12 in, 12 apart, rounded concentric with its card, the ink at 5% under it while pressed.
// kept across runs: a value (no field of it changes)
let list_line : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S3,
  py=S3,
  gap=S3,
  radius=Inner,
  align=ACenter,
  pressed=@ui.patch(bg=A(Fg, O5)),
)

///|
/// A row's main words, as wide as the row lets them, cut to one line.
fn row_title(c : @ui.Ctx, words : String, color? : Int64) -> Unit {
  // SettingParts.kt:255 (15sp)
  c.text(words, style=row_title_words, color?) |> ignore
}

///|
/// A row's title: the body's words on one line, as wide as the row lets them.
// kept across runs: a value (no field of it changes)
let row_title_words : @ui.TextStyle = @sf.body.then(@sf.one_line).then(@sf.full_words)

///|
/// A row's title in lines where it is long.
// kept across runs: a value (no field of it changes)
let row_title_lines : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
/// A row's title with a line under it, as wide as the row lets them; the title in lines where it is long, or cut to
/// one (`wrap_title` false: where Android says maxLines = 1). `title_color`, `sub_color`: in place of the roles' (a
/// warning's, worked out where it is called).
fn row_lines(
  c : @ui.Ctx,
  title : String,
  sub : String,
  sub_color? : Int64,
  title_color? : Int64,
  wrap_title? : Bool = true,
  wrap_sub? : Bool = false,
) -> Unit {
  c.box(style=@sf.full_width, fn() {
    // Connects.kt:231, Security.kt:191 (15sp)
    c.text(title, style=if wrap_title { row_title_lines } else { row_title_words }, color?=title_color) |> ignore
    if sub != "" {
      // Connects.kt:232, Security.kt:192 (13sp)
      c.text(sub, style=if wrap_sub { row_sub_lines } else { row_sub_line }, color?=sub_color) |> ignore
    }
  })
  |> ignore
}

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
/// A row that opens a page (SettingParts.kt GoRow): its name, how things stand at its end (`bad` in red; `dot`, a red
/// dot before it), a chevron. True on the frame after a tap.
fn go_row(
  c : @ui.Ctx,
  key : String,
  title : String,
  value? : String = "",
  bad? : Bool = false,
  dot? : Bool = false,
  lead? : () -> Unit,
) -> Bool {
  list_row(c, key~, fn() {
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
        c.text(value, style=if bad { @sf.value.then(@sf.bad) } else { @sf.value }) |> ignore
      })
      |> ignore
    }
    chevron(c)
  })
}

///|
/// Things in a line, centred across it, 6 apart (a dot and its words, a mark and a word).
// kept across runs: a value (no field of it changes)
let near_beside : @ui.Style = @ui.style(row=true, gap=S1_5, align=ACenter)

///|
/// A switch (PageParts.kt Switch): 44 by 26, green when on, its knob white: mbui's switch's look (@kit.switch_look_of)
/// in still.fail's colours; the row it is in takes the tap.
fn switch(c : @ui.Ctx, on : Bool) -> Unit {
  let t = @sf.theme()
  @kit.switch_look_of(w=44.0, h=26.0, inset=3.0, on_color=t.p.green, off_color=t.p.line, knob=0xFFFFFFFFL, shadow=false)(
    c,
    {
      on,
      t: if on { 1.0 } else { 0.0 },
      hovered: false,
      pressed: false,
      focus_shown: false,
      disabled: false,
      rect: (0.0, 0.0, 44.0, 26.0),
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
let dot_online : @ui.Style = dot_shape.then(@ui.style(bg=Positive))

///|
// kept across runs: a value (no field of it changes)
let dot_busy : @ui.Style = dot_shape.then(@ui.style(bg=Accent))

///|
// kept across runs: a value (no field of it changes)
let dot_error : @ui.Style = dot_shape.then(@ui.style(bg=Danger))

///|
// kept across runs: a value (no field of it changes)
let dot_ring : @ui.Style = dot_shape.then(@ui.style(border_color=Subtle))

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
/// A segmented choice (Parts.kt Seg): a track the ink at 6%, a light thumb (a hairline round it) sliding to the one
/// chosen. `fill`: as wide as where it is, each option an equal share. Answers the one chosen (a tap's, this frame).
fn seg(
  c : @ui.Ctx,
  key : String,
  options : Array[String],
  selected : Int,
  fill? : Bool = false,
  height? : Double = 30.0,
  radius? : Double = 10.0,
) -> Int {
  let t = @sf.theme()
  // in the wide frame the web's (controls.css.ts seg): a pill of options as wide as their words, 105 at least, 36 high
  let pill = wide.val
  let fill = fill && !pill
  let height = if pill { 36.0 } else { height }
  let radius = if pill { 18.0 } else { radius }
  let base = c.id(key)
  let mut picked = selected
  for i, _ in options {
    if hit(c, base + i + 1) {
      picked = i
    }
  }
  let inset = 2.0
  let thumb = if t.dark { 0x3A3B40FFL } else { 0xFFFFFFFFL }
  let track = fn() {
    c.box(
      style=if fill { seg_track_full } else { seg_track },
      h=Px(height),
      radius~,
      bg=@sf.alpha(t.p.text, 0.06),
      id=base,
      fn() {
        // the thumb behind the options, laid out over the one chosen in the frame they are (Ctx::cover): to another
        // on its spring, placed at once the first time (as Seg's first placement jumps)
        let holder = c.layer(fn() {  })
        let items : Array[Int] = []
        for i, label in options {
          let id = base + i + 1
          let item = c.box(
            style=if pill {
              seg_pill_option
            } else if fill {
              seg_full_option
            } else {
              seg_option
            },
            id~,
            fn() {
              // Parts.kt:424 (14sp filling, else 13sp)
              c.text(
                label,
                style=@ui.text_style(
                  size=if fill { Base } else { Sm },
                  color=if i == picked { Fg } else { Muted },
                  wrap=false,
                ),
              )
              |> ignore
            },
          )
          items.push(item)
        }
        c.cover(key + "/thumb", holder, items, picked, fn(c, w, h) {
          c.box(
            w=Px(w),
            h=Px(h),
            radius=@ui.concentric(radius, inset),
            bg=thumb,
            border=0.5,
            border_color=t.p.line,
            fn() {  },
          )
          |> ignore
        })
      },
    )
    |> ignore
  }
  // (in a row, as wide as its options: not stretched to its parent's width)
  if pill {
    c.box(style=seg_pill_line, fn() { track() }) |> ignore
  } else {
    track()
  }
  picked
}

///|
/// Seg's track (its height and corner said where it is used): its options in a line, 2 in; as wide as where it is
/// (`fill`) or as they are.
// kept across runs: a value (no field of it changes)
let seg_track : @ui.Style = @ui.style(row=true, p=S0_5)

///|
// kept across runs: a value (no field of it changes)
let seg_track_full : @ui.Style = seg_track.then(@ui.style(w=Full))

///|
/// An option: its words in its middle, 10 in; 12 in and an equal share where the track fills; the wide frame's pill,
/// 101 at least.
// kept across runs: a value (no field of it changes)
let seg_option : @ui.Style = @ui.style(h=Full, px=S2_5, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let seg_full_option : @ui.Style = seg_option.then(@ui.style(w=Full, px=S3))

///|
// kept across runs: a value (no field of it changes)
let seg_pill_option : @ui.Style = seg_option.then(@ui.style(min_w=@sf.seg_pill_min))

///|
/// The wide frame's pill in a line of its own, not stretched to its width.
// kept across runs: a value (no field of it changes)
let seg_pill_line : @ui.Style = @ui.style(row=true, w=Full)

///|
/// A person's picture (Parts.kt Avatar): theirs once it is here, else their initial on their colour.
fn avatar(c : @ui.Ctx, core : Core, id : String, name : String, size : Double, picture? : String = "") -> Unit {
  let key = if picture == "" { "" } else { (core.picture)(picture) }
  c.box(
    style=avatar_disc,
    w=Px(size),
    h=Px(size),
    bg=avatar_color(id),
    fn() {
      if key != "" {
        c.image(key, w=Px(size), h=Px(size), radius=size / 2.0, bg=0L) |> ignore
      } else {
        c.text(initial(name), size=size * 0.5, weight=600, color=0xFFFFFFFFL, wrap=false, line=size * 0.5)
        |> ignore
      }
    },
  )
  |> ignore
}

///|
/// A person's disc (its side and colour said where it is used): round, what it holds in its middle.
// kept across runs: a value (no field of it changes)
let avatar_disc : @ui.Style = @ui.style(radius=Full, align=ACenter, justify=JCenter, clip=true)

///|
/// The people's colours (Parts.kt AVATAR).
// kept across runs: a table, never written
let avatar_colors : Array[Int64] = [
  0x5B7BB2FFL, 0x2F8F5BFFL, 0xB9471FFFL, 0x8A6BB0FFL, 0x3F8C99FFL, 0xB0842FFFL,
]

///|
/// A person's colour, by their id lowered (Parts.kt avatarColor: Java's hashCode, floorMod).
fn avatar_color(id : String) -> Int64 {
  let n = avatar_colors.length()
  let mut h = 0
  for i in 0..<id.length() {
    let k = id.at(i).to_int()
    h = h * 31 + (if k >= 65 && k <= 90 { k + 32 } else { k })
  }
  let m = h % n
  avatar_colors[if m < 0 { m + n } else { m }]
}

///|
/// The first letter of a name, upper case (Parts.kt initial).
fn initial(name : String) -> String {
  for ch in name {
    let k = ch.to_int()
    if k == 32 || k == 9 || k == 10 {
      continue
    }
    return if k >= 97 && k <= 122 {
      (k - 32).unsafe_to_char().to_string()
    } else {
      ch.to_string()
    }
  }
  "?"
}

///|
/// A word in the accent's wash (Settings.kt You: 你, 本机).
fn you(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=you_ground, fn() {
    // Settings.kt:294 (12sp)
    c.text(words, style=you_words) |> ignore
  })
  |> ignore
}

///|
/// You's wash: 6 in at its sides, 6 round.
// kept across runs: a value (no field of it changes)
let you_ground : @ui.Style = @ui.style(px=S1_5, radius=Md, bg=AccentBg)

///|
/// Small words in the accent's ink (in lines where there is no room: Settings.kt:294 has no maxLines).
// kept across runs: a value (no field of it changes)
let you_words : @ui.TextStyle = @sf.caption.then(@ui.text_style(color=AccentText))

///|
/// The turning ring (Waiting.kt Spinner): 14, or 12 in a line of small text.
fn spinner(c : @ui.Ctx, inline? : Bool = false) -> Unit {
  @sf.spinner(c, size=if inline { 12.0 } else { 14.0 }) |> ignore
}

///|
/// Where what someone set going shows how it is (Controls.kt DoingMark): a spinner while it is under way, a small red
/// mark for a few seconds after it failed.
fn doing_mark(c : @ui.Ctx, running : Bool, failed : String?, inline? : Bool = false) -> Unit {
  let t = @sf.theme()
  if running {
    spinner(c, inline~)
  } else if failed is Some(_) {
    @sf.icon(c, "info", size=if inline { 12.0 } else { 14.0 }, color=t.p.red) |> ignore
  }
}

///|
/// A wait said in a line of its own (Waiting.kt WaitLine): a spinner before it; what is wrong in red.
fn wait_line(c : @ui.Ctx, words : String, error? : Bool = false, pad? : Bool = false) -> Unit {
  c.box(style=if pad { wait_line_padded } else { @sf.beside }, fn() {
    if !error {
      spinner(c, inline=true)
    }
    c.text(words, style=if error { @sf.meta.then(@sf.bad) } else { @sf.meta }) |> ignore
  })
  |> ignore
}

///|
/// A wait's line in a page's flow: in from its sides as a card's words.
// kept across runs: a value (no field of it changes)
let wait_line_padded : @ui.Style = @sf.beside.then(@ui.style(px=S5, py=S2))

///|
/// The shapes of a settings page's cards to come (Waiting.kt Waiting, WaitShape.Cards), breathing; what could not be
/// read over them in red (the shapes then still).
fn waiting_cards(c : @ui.Ctx, count? : Int = 3, error? : String = "", failing? : Array[String] = []) -> Unit {
  let pills = if error != "" { [error] } else { [] }
  pills.append(failing)
  c.box(style=@sf.full_width, fn() {
    if pills.length() > 0 {
      wait_pills(c, pills)
    }
    let breath = if pills.length() == 0 { @sf.breath(c) } else { 0.6 }
    c.box(style=wait_card_list, opacity=breath, fn() {
      for i in 0..<count {
        c.box(style=wait_card, h=Px(wait_cards[i % wait_cards.length()]), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// What could not be read, each in a pill of the chip's grey (Waiting.kt WaitPill), over the shapes: 20 in, 14 down.
fn wait_pills(c : @ui.Ctx, pills : Array[String]) -> Unit {
  let t = @sf.theme()
  c.box(style=wait_pill_list, fn() {
    for f in pills {
      // (the chip's grey: the wide frame's light one is not mbui's Faint)
      c.box(style=wait_pill, bg=t.p.chip, fn() {
        // Waiting.kt:119 (13sp, line 18, two lines at most, the second ending in an ellipsis)
        c.text(f, style=wait_pill_words) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let wait_pill_list : @ui.Style = @ui.style(w=Full, px=S5, pt=S3_5, pb=S1, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wait_pill : @ui.Style = @ui.style(px=S3, py=S1_5, radius=Full)

///|
// kept across runs: a value (no field of it changes)
let wait_pill_words : @ui.TextStyle = @sf.meta.then(@sf.bad).then(@ui.text_style(center=true, max_lines=2))

///|
/// The cards to come: 12 from the page's sides, 16 apart, each a card's corner on the placeholders' grey.
// kept across runs: a value (no field of it changes)
let wait_card_list : @ui.Style = @ui.style(w=Full, px=S3, gap=S4)

///|
// kept across runs: a value (no field of it changes)
let wait_card : @ui.Style = @ui.style(w=Full, radius=Xl3, bg=Neutral)

///|
// kept across runs: a table, never written
let wait_cards : Array[Double] = [120.0, 88.0, 152.0, 104.0]

///|
// kept across runs: a table, never written
let wait_titles : Array[Double] = [150.0, 110.0, 170.0, 130.0, 96.0, 160.0, 120.0]

///|
// kept across runs: a table, never written
let wait_lines : Array[Double] = [230.0, 190.0, 250.0, 170.0, 210.0, 200.0, 180.0]

///|
/// A list's rows to come (Waiting.kt WaitShape.Rows): a title and a line, a picture at the end, 66 high.
fn waiting_rows(c : @ui.Ctx, count? : Int = 3, error? : String = "", failing? : Array[String] = []) -> Unit {
  let pills = if error != "" { [error] } else { [] }
  pills.append(failing)
  c.box(style=@sf.full_width, fn() {
    if pills.length() > 0 {
      wait_pills(c, pills)
    }
    let breath = if pills.length() == 0 { @sf.breath(c) } else { 0.6 }
    c.box(style=@sf.full_width, opacity=breath, fn() {
      for i in 0..<count {
        // (66 high, 22 in at its start: off the scale)
        c.box(style=wait_row, h=Px(66.0), pl=22.0, fn() {
          c.box(style=wait_row_lines, fn() {
            @sf.bar(c, Px(wait_titles[i % 7]), 13.0)
            @sf.bar(c, Px(wait_lines[i % 7]), 10.0)
          })
          |> ignore
          @sf.bar(c, Px(22.0), 22.0)
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A row to come: 16 in at its end, its lines and its picture 12 apart; its lines 10 apart.
// kept across runs: a value (no field of it changes)
let wait_row : @ui.Style = @ui.style(row=true, w=Full, pr=S4, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let wait_row_lines : @ui.Style = @ui.style(w=Full, gap=S2_5)

///|
/// What could not be read of a list, by the stations that failed (a ListNote's `failing`).
fn failing_of(note : Json?) -> Array[String] {
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
let place_empty_box : @ui.Style = @ui.style(w=Full, px=S8, py=S10, gap=S2, align=ACenter)

///|
/// A button (Controls.kt Button): 38 high, round; primary in ink (red when `danger`; off: the line's grey, its words
/// muted), else the chip's grey; a spinner before its words while `busy`. True on the frame after a tap (not while
/// busy or off).
fn button(
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
  // (a solid one not yet to be pressed: its words muted on its pale ground, not paper on paper)
  let ink = if primary && !enabled {
    t.p.muted
  } else if primary && danger {
    0xFFFFFFFFL
  } else if primary {
    t.p.bg
  } else {
    t.p.text
  }
  let ground = if primary {
    if !enabled {
      t.p.line
    } else if danger {
      t.p.red
    } else {
      t.p.text
    }
  } else {
    t.p.chip
  }
  // (38 high, off the scale; its ground and ink from what it is)
  c.box(
    style=button_box,
    h=Px(38.0),
    bg=if c.pressed(id) && enabled && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      // Controls.kt:126 (14sp)
      c.text(label, style=button_words, color=ink) |> ignore
    },
  )
  |> ignore
  enabled && !busy && hit(c, id)
}

///|
/// A button: a capsule, 16 in, a spinner 8 before its words, they in its middle (where it is made wider).
// kept across runs: a value (no field of it changes)
let button_box : @ui.Style = @ui.style(row=true, px=S4, gap=S2, radius=Full, align=ACenter, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let button_words : @ui.TextStyle = @sf.value.then(@sf.strong)

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
  c.box(
    style=wide_button_box,
    h=Px(46.0),
    bg=if c.pressed(id) && enabled && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      // Security.kt:127 (15sp)
      c.text(label, style=@sf.body.then(@sf.strong).then(@sf.one_line), color=ink) |> ignore
    },
  )
  |> ignore
  enabled && !busy && hit(c, id)
}

///|
/// WideButton: a capsule as wide as where it is, its words in its middle.
// kept across runs: a value (no field of it changes)
let wide_button_box : @ui.Style = @ui.style(row=true, w=Full, radius=Full, gap=S2, align=ACenter, justify=JCenter)

///|
/// A row of a picking sheet (Controls.kt PickRow): what, a line under it, a check on the one chosen; `mark` before
/// what. True on the frame after a tap.
fn pick_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  sub? : String = "",
  checked? : Bool = false,
  enabled? : Bool = true,
  color? : Int64,
  mark? : () -> Unit,
  busy? : Bool = false,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let line = match (on_card.val, enabled) {
    (true, true) => pick_card_line
    (true, false) => pick_card_line_off
    (false, true) => pick_line
    (false, false) => pick_line_off
  }
  c.box(style=if on_card.val { @sf.full_width } else { pick_room }, fn() {
    c.box(style=line, id~, fn() {
      c.box(style=@sf.full_width, fn() {
        c.box(style=pick_label_line, fn() {
          match mark {
            Some(f) => f()
            None => ()
          }
          // Controls.kt:69, 72 (15sp, in lines where it is long)
          c.text(label, style=row_title_lines, color=if enabled { color.unwrap_or(t.p.text) } else { t.p.subtle })
          |> ignore
        })
        |> ignore
        if sub != "" {
          // Controls.kt:74 (12sp)
          c.text(sub, style=@sf.caption.then(@sf.full_words)) |> ignore
        }
      })
      |> ignore
      if busy {
        spinner(c)
      } else if checked {
        @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
  enabled && !busy && hit(c, id)
}

///|
/// PickRow: 12 from the sheet's sides; its line 8 and 12 in, 12 apart, the ink at 5% under it while pressed (not
/// when off); its label after its mark, 6 apart. On a list card (Controls.kt:62 onCard) to the card's padding, its line
/// 12 in and rounded concentric with the card, as a ListRow.
// kept across runs: a value (no field of it changes)
let pick_room : @ui.Style = @ui.style(w=Full, px=S3)

///|
// kept across runs: a value (no field of it changes)
let pick_line_off : @ui.Style = @ui.style(row=true, w=Full, px=S2, py=S3, gap=S3, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let pick_line : @ui.Style = pick_line_off.then(@ui.style(pressed=@ui.patch(bg=A(Fg, O5))))

///|
// kept across runs: a value (no field of it changes)
let pick_card_line_off : @ui.Style = pick_line_off.then(@ui.style(px=S3, radius=Inner))

///|
// kept across runs: a value (no field of it changes)
let pick_card_line : @ui.Style = pick_line.then(@ui.style(px=S3, radius=Inner))

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
    c.box(style=press_fade, id~, fn() {
      // Settings.kt:288 (14sp)
      c.text(label, style=@sf.value.then(@sf.accent)) |> ignore
    })
    |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// Words to tap, faded while pressed.
// kept across runs: a value (no field of it changes)
let press_fade : @ui.Style = @ui.style(pressed=@ui.patch(opacity=O60))

///|
/// Words that do something when tapped (a link's look: Theme.kt link). True on the frame after a tap.
fn tap_text(c : @ui.Ctx, key : String, label : String, color? : Int64, size? : Double = 15.0) -> Bool {
  let id = c.id(key)
  c.box(style=press_fade, id~, fn() {
    // Settings.kt:447 (15sp), Profiles.kt:794, Vault.kt:365 (14sp): the theme's line, 1.4 its size (its size the
    // caller's)
    c.text(label, style=@sf.link.then(@sf.one_line), size~, line=size * 1.4, color?) |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// A round button in a bar (Parts.kt NavButton): its icon alone, 34 round. True on the frame after a tap.
fn nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  // (34 round, off the scale; the ink at 8% while pressed, off the scale of opacities)
  c.box(
    style=round_button,
    w=Px(34.0),
    h=Px(34.0),
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.08) } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size~, color=t.p.text) |> ignore },
  )
  |> ignore
  hit(c, id)
}

///|
/// NavButton: round, its icon in its middle.
// kept across runs: a value (no field of it changes)
let round_button : @ui.Style = @ui.style(radius=Full, align=ACenter, justify=JCenter)

///|
/// A body of words (PageParts.kt Body): on a list card 12 and 12 in (its words 20 from the card's edge, as its rows'),
/// else 16 and 14; 12 apart.
fn body(c : @ui.Ctx, f : () -> Unit) -> Unit {
  c.box(style=if on_card.val { body_on_card } else { body_box }, f) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let body_box : @ui.Style = @ui.style(w=Full, px=S4, py=S3_5, gap=S3)

///|
// kept across runs: a value (no field of it changes)
let body_on_card : @ui.Style = body_box.then(@ui.style(px=S3, py=S3))

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
let tone_pill_box : @ui.Style = @ui.style(px=S1_5, py=SPx, radius=Md)

///|
// kept across runs: a value (no field of it changes)
let tone_pill_words : @ui.TextStyle = @sf.caption.then(@sf.one_line)

///|
/// Words in the code face (CodeFont: a code, a key, a variable), one line unless `wrap`.
/// With `style` (a role of @sf's styles.mbt), that, and what is said besides over it.
fn mono(
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
let centre_column : @ui.Style = @ui.style(w=Full, align=ACenter)
