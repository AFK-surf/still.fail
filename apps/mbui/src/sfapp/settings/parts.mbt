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
        c.box(w=Fill(1.0), pl=side, pr=side, fn() { (blocks[i])() }) |> ignore
      }
    })
    |> ignore
    return
  }
  c.list("settings/" + key, blocks.length(), 80.0, fn(i) { (blocks[i])() }) |> ignore
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
  c.box(w=Fill(1.0), pl=side, pr=side, pt=if wide_deep.val { 20.0 } else { 40.0 }, pb=12.0, bg=t.p.bg, fn() {
    if wide_deep.val {
      let id = c.id("settings-back")
      c.cursor(id, Hand)
      c.box(dir=Row, pb=8.0, gap=4.0, align=ACenter, id~, fn() {
        @sf.icon(c, "chevron-left", size=14.0, color=t.p.muted) |> ignore
        c.text(back, size=13.0, color=if c.hovered(id) { t.p.text } else { t.p.muted }, wrap=false) |> ignore
      })
      |> ignore
      if hit(c, id) {
        (core.pop)()
      }
    }
    c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
      c.box(w=Fill(1.0), fn() {
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
/// A gap of `h` (Spacer).
fn gap(c : @ui.Ctx, h : Double) -> Unit {
  c.box(w=Fill(1.0), h=Px(h), fn() {  }) |> ignore
}

///|
/// Back, in the accent colour, with where it goes back to (Parts.kt NavBack). True on the frame after a tap.
fn nav_back(c : @ui.Ctx, label : String) -> Bool {
  let t = @sf.theme()
  let id = c.id("settings-back")
  c.box(
    dir=Row,
    pr=6.0,
    pt=4.0,
    pb=4.0,
    radius=8.0,
    align=ACenter,
    opacity=if c.pressed(id) { 0.6 } else { 1.0 },
    id~,
    fn() {
      @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore
      c.text(label, size=17.0, color=t.p.accent, wrap=false) |> ignore
    },
  )
  |> ignore
  hit(c, id)
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
  c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, align=ACenter, justify=JBetween, fn() {
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
  let t = @sf.theme()
  if wide.val {
    ignore(sub)
    match trailing {
      Some(f) => wide_head(c, core, back, title, trailing=f)
      None => wide_head(c, core, back, title)
    }
    return
  }
  c.box(w=Fill(1.0), pl=10.0, pr=16.0, pt=6.0, pb=10.0, bg=t.p.bg, fn() {
    c.box(dir=Row, w=Fill(1.0), h=Px(32.0), align=ACenter, justify=JBetween, fn() {
      if nav_back(c, back) {
        (core.pop)()
      }
      match trailing {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
    c.layer(align=ACenter, fn() {
      c.box(pl=84.0, pr=84.0, align=ACenter, fn() {
        c.box(h=Px(30.0), justify=JCenter, fn() {
          c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false) |> ignore
        })
        |> ignore
        gap(c, 2.0)
        match sub {
          Some(f) =>
            c.box(dir=Row, ty=-4.0, gap=5.0, align=ACenter, fn() { f() }) |> ignore
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
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
) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    match actions {
      // (at the root its actions at the end of a row of their own, over what it shows)
      Some(a) if at_root.val =>
        c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pt=8.0, gap=10.0, align=ACenter, justify=JEnd, fn() { a() })
        |> ignore
      None if at_root.val => ()
      Some(a) =>
        nav_bar(c, core, under_label(core, back), title, trailing=fn() {
          c.box(dir=Row, gap=10.0, align=ACenter, fn() { a() }) |> ignore
        })
      None => nav_bar(c, core, under_label(core, back), title)
    }
    c.box(w=Fill(1.0), h=Fill(1.0), pt=4.0, fn() { body() }) |> ignore
  })
  |> ignore
}

///|
/// A page's large title (Parts.kt LargeTitle): the big word, after `lead` when there is one (a workspace's mark).
fn large_title(c : @ui.Ctx, big : String, lead? : () -> Unit) -> Unit {
  let t = @sf.theme()
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
  c.box(dir=Row, w=Fill(1.0), pl=16.0, pr=16.0, pb=6.0, gap=10.0, align=ACenter, fn() {
    match lead {
      Some(f) => f()
      None => ()
    }
    c.text(big, size=32.0, weight=700, color=t.p.text, wrap=false, line=44.0) |> ignore
  })
  |> ignore
}

///|
/// A section's heading (Parts.kt SectionHeader): its title, what it holds at its end.
fn section_header(c : @ui.Ctx, title : String, trailing? : String = "", start? : Double = 24.0) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=start, pr=20.0, pt=14.0, pb=6.0, align=AEnd, gap=8.0, fn() {
    c.text(title, size=15.0, weight=600, color=t.p.text, wrap=false, line=21.0) |> ignore
    c.spacer()
    if trailing != "" {
      c.text(trailing, size=13.0, color=t.p.muted, wrap=false, line=18.0) |> ignore
    }
  })
  |> ignore
}

///|
/// A page's note under its title, in a line or two (SettingParts.kt PageNote).
fn page_note(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=24.0, pr=24.0, pb=10.0, fn() {
    c.text(words, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
  })
  |> ignore
}

///|
/// A card's corner, and how far in from every edge what it holds stands (what is in its corners as far from both
/// edges: docs/ui-panels.md); what has a ground of its own there takes @sf.concentric(card_radius, card_pad).
let card_radius : Double = 20.0

///|
let card_pad : Double = 16.0

///|
/// A card on the page (Parts.kt Card): 12 in from the sides, 10 under it, its words card_pad in; tapped when `key`
/// is given. True on the frame after a tap.
fn card(c : @ui.Ctx, body : () -> Unit, key? : String = "") -> Bool {
  let t = @sf.theme()
  let id = if key == "" { 0 } else { c.id(key) }
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=10.0, fn() {
    c.box(
      w=Fill(1.0),
      pad=card_pad,
      radius=card_radius,
      bg=if id != 0 && c.pressed(id) {
        @sf.over(t.p.card, @sf.alpha(t.p.text, 0.05))
      } else {
        t.p.card
      },
      clip=true,
      id~,
      body,
    )
    |> ignore
  })
  |> ignore
  id != 0 && hit(c, id)
}

///|
/// Rows on one rounded card, no lines between them (Parts.kt ListCard).
fn list_card(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=12.0, pr=12.0, pb=10.0, fn() {
    c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, body) |> ignore
  })
  |> ignore
}

///|
/// A row of a list card (Parts.kt ListRow): 16 and 12 in, what it holds 12 apart; tapped when `key` is given. True on
/// the frame after a tap.
fn list_row(c : @ui.Ctx, body : () -> Unit, key? : String = "") -> Bool {
  let t = @sf.theme()
  let id = if key == "" { 0 } else { c.id(key) }
  c.box(
    dir=Row,
    w=Fill(1.0),
    padx=16.0,
    pady=12.0,
    gap=12.0,
    align=ACenter,
    bg=if id != 0 && c.pressed(id) { @sf.alpha(t.p.text, 0.05) } else { 0L },
    id~,
    body,
  )
  |> ignore
  id != 0 && hit(c, id)
}

///|
/// A row's main words, as wide as the row lets them, cut to one line.
fn row_title(c : @ui.Ctx, words : String, color? : Int64, size? : Double = 15.0) -> Unit {
  let t = @sf.theme()
  c.text(words, size~, color=color.unwrap_or(t.p.text), wrap=false, w=Fill(1.0), line=21.0) |> ignore
}

///|
/// A row's title with a line under it, as wide as the row lets them.
fn row_lines(
  c : @ui.Ctx,
  title : String,
  sub : String,
  sub_color? : Int64,
  title_color? : Int64,
  wrap_sub? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), fn() {
    c.text(title, size=15.0, color=title_color.unwrap_or(t.p.text), wrap=false, w=Fill(1.0), line=21.0)
    |> ignore
    if sub != "" {
      c.text(sub, size=13.0, color=sub_color.unwrap_or(t.p.muted), wrap=wrap_sub, w=Fill(1.0), line=18.0)
      |> ignore
    }
  })
  |> ignore
}

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
  let t = @sf.theme()
  list_row(c, key~, fn() {
    match lead {
      Some(f) => f()
      None => ()
    }
    row_title(c, title)
    if value != "" {
      c.box(dir=Row, max_w=220.0, gap=6.0, align=ACenter, fn() {
        if dot {
          presence_dot(c, "error")
        }
        c.text(value, size=14.0, color=if bad { t.p.red } else { t.p.muted }, wrap=false, line=20.0)
        |> ignore
      })
      |> ignore
    }
    chevron(c)
  })
}

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
  let t = @sf.theme()
  match state {
    "online" => c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.green, fn() {  }) |> ignore
    "busy" => c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.accent, fn() {  }) |> ignore
    "error" => c.box(w=Px(7.0), h=Px(7.0), radius=3.5, bg=t.p.red, fn() {  }) |> ignore
    _ =>
      c.box(w=Px(7.0), h=Px(7.0), radius=3.5, border=1.5, border_color=t.p.subtle, fn() {  })
      |> ignore
  }
}

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
/// A check's tone as a colour (PageParts.kt toneColor).
fn tone_color(tone : String) -> Int64 {
  let t = @sf.theme()
  match tone {
    "green" => t.p.green
    "red" => t.p.red
    "blue" => t.p.blue
    "accent" => t.p.accent
    _ => t.p.muted
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
      dir=Row,
      w=if fill { Fill(1.0) } else { Auto },
      h=Px(height),
      pad=inset,
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
            w=if fill { Fill(1.0) } else { Auto },
            h=Fill(1.0),
            min_w=if pill { 101.0 } else { 0.0 },
            padx=if fill { 12.0 } else { 10.0 },
            align=ACenter,
            justify=JCenter,
            id~,
            fn() {
              c.text(
                label,
                size=if fill { 14.0 } else { 13.0 },
                color=if i == picked { t.p.text } else { t.p.muted },
                wrap=false,
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
            radius=@sf.concentric(radius, inset),
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
    c.box(dir=Row, w=Fill(1.0), fn() { track() }) |> ignore
  } else {
    track()
  }
  picked
}

///|
/// A person's picture (Parts.kt Avatar): theirs once it is here, else their initial on their colour.
fn avatar(c : @ui.Ctx, core : Core, id : String, name : String, size : Double, picture? : String = "") -> Unit {
  let key = if picture == "" { "" } else { (core.picture)(picture) }
  c.box(
    w=Px(size),
    h=Px(size),
    radius=size / 2.0,
    bg=avatar_color(id),
    align=ACenter,
    justify=JCenter,
    clip=true,
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
  let t = @sf.theme()
  c.box(padx=6.0, radius=6.0, bg=t.p.accent_bg, fn() {
    c.text(words, size=12.0, color=t.p.accent_text, wrap=false, line=17.0) |> ignore
  })
  |> ignore
}

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
  let t = @sf.theme()
  c.box(dir=Row, padx=if pad { 20.0 } else { 0.0 }, pady=if pad { 8.0 } else { 0.0 }, gap=8.0, align=ACenter, fn() {
    if !error {
      spinner(c, inline=true)
    }
    c.text(words, size=13.0, color=if error { t.p.red } else { t.p.muted }, line=18.0) |> ignore
  })
  |> ignore
}

///|
/// The shapes of a settings page's cards to come (Waiting.kt Waiting, WaitShape.Cards), breathing; what could not be
/// read over them in red (the shapes then still).
fn waiting_cards(c : @ui.Ctx, count? : Int = 3, error? : String = "", failing? : Array[String] = []) -> Unit {
  let t = @sf.theme()
  let pills = if error != "" { [error] } else { [] }
  pills.append(failing)
  c.box(w=Fill(1.0), fn() {
    if pills.length() > 0 {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=14.0, pb=4.0, gap=8.0, align=ACenter, fn() {
        for f in pills {
          c.box(padx=12.0, pady=6.0, radius=15.0, bg=t.p.chip, fn() {
            c.text(f, size=13.0, color=t.p.red, line=18.0, center=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    let breath = if pills.length() == 0 { @sf.breath(c) } else { 0.6 }
    c.box(w=Fill(1.0), padx=12.0, gap=16.0, opacity=breath, fn() {
      for i in 0..<count {
        c.box(w=Fill(1.0), h=Px(wait_cards[i % wait_cards.length()]), radius=20.0, bg=t.p.neutral_bg, fn() {  })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

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
  let t = @sf.theme()
  let pills = if error != "" { [error] } else { [] }
  pills.append(failing)
  c.box(w=Fill(1.0), fn() {
    if pills.length() > 0 {
      c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=14.0, pb=4.0, gap=8.0, align=ACenter, fn() {
        for f in pills {
          c.box(padx=12.0, pady=6.0, radius=15.0, bg=t.p.chip, fn() {
            c.text(f, size=13.0, color=t.p.red, line=18.0, center=true) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    let breath = if pills.length() == 0 { @sf.breath(c) } else { 0.6 }
    c.box(w=Fill(1.0), opacity=breath, fn() {
      for i in 0..<count {
        c.box(dir=Row, w=Fill(1.0), h=Px(66.0), pl=22.0, pr=16.0, gap=12.0, align=ACenter, fn() {
          c.box(w=Fill(1.0), gap=10.0, fn() {
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
  let t = @sf.theme()
  c.box(w=Fill(1.0), padx=32.0, pady=40.0, gap=8.0, align=ACenter, fn() {
    c.text(words, size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0) |> ignore
    if note != "" {
      c.text(note, size=13.0, color=t.p.subtle, center=true, w=Fill(1.0), line=18.0) |> ignore
    }
  })
  |> ignore
}

///|
/// A button (Controls.kt Button): 38 high, round; primary in ink (red when `danger`), else the chip's grey; a spinner
/// before its words while `busy`. True on the frame after a tap (not while busy or off).
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
  let ink = if primary && danger && enabled {
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
  c.box(
    dir=Row,
    h=Px(38.0),
    padx=16.0,
    gap=8.0,
    radius=19.0,
    align=ACenter,
    bg=if c.pressed(id) && enabled && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      c.text(label, size=14.0, weight=600, color=ink, wrap=false) |> ignore
    },
  )
  |> ignore
  enabled && !busy && hit(c, id)
}

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
  c.box(
    dir=Row,
    w=Fill(1.0),
    h=Px(46.0),
    radius=23.0,
    gap=8.0,
    align=ACenter,
    justify=JCenter,
    bg=if c.pressed(id) && enabled && !busy { @sf.over(ground, @sf.alpha(ink, 0.12)) } else { ground },
    id~,
    fn() {
      if busy {
        @sf.spinner(c, size=14.0, ring=@sf.alpha(ink, 0.3), arc=ink) |> ignore
      }
      c.text(label, size=15.0, weight=600, color=ink, wrap=false) |> ignore
    },
  )
  |> ignore
  enabled && !busy && hit(c, id)
}

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
  c.box(w=Fill(1.0), padx=12.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      padx=8.0,
      pady=12.0,
      gap=12.0,
      align=ACenter,
      bg=if c.pressed(id) && enabled { @sf.alpha(t.p.text, 0.05) } else { 0L },
      id~,
      fn() {
        c.box(w=Fill(1.0), fn() {
          c.box(dir=Row, w=Fill(1.0), gap=6.0, align=ACenter, fn() {
            match mark {
              Some(f) => f()
              None => ()
            }
            c.text(
              label,
              size=15.0,
              color=if enabled { color.unwrap_or(t.p.text) } else { t.p.subtle },
              wrap=false,
              w=Fill(1.0),
              line=21.0,
            )
            |> ignore
          })
          |> ignore
          if sub != "" {
            c.text(sub, size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
          }
        })
        |> ignore
        if busy {
          spinner(c)
        } else if checked {
          @sf.icon(c, "check", size=14.0, color=t.p.accent) |> ignore
        }
      },
    )
    |> ignore
  })
  |> ignore
  enabled && !busy && hit(c, id)
}

///|
/// A word at a row's end that does something (Settings.kt RowAction: 移除, 撤回): a spinner in its place while it is
/// under way, a red mark before it a moment after it failed. True on the frame after a tap.
fn row_action(c : @ui.Ctx, key : String, label : String, busy : Bool, failed : String?) -> Bool {
  let t = @sf.theme()
  if busy {
    spinner(c)
    return false
  }
  let id = c.id(key)
  c.box(dir=Row, gap=6.0, align=ACenter, fn() {
    doing_mark(c, false, failed)
    c.box(id~, opacity=if c.pressed(id) { 0.6 } else { 1.0 }, fn() {
      c.text(label, size=14.0, color=t.p.accent, wrap=false) |> ignore
    })
    |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// Words that do something when tapped (a link's look). True on the frame after a tap.
fn tap_text(c : @ui.Ctx, key : String, label : String, color? : Int64, size? : Double = 15.0) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(id~, opacity=if c.pressed(id) { 0.6 } else { 1.0 }, fn() {
    c.text(label, size~, color=color.unwrap_or(t.p.accent), wrap=false) |> ignore
  })
  |> ignore
  hit(c, id)
}

///|
/// A round button in a bar (Parts.kt NavButton): its icon alone, 34 round. True on the frame after a tap.
fn nav_button(c : @ui.Ctx, key : String, icon : String, size? : Double = 18.0) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    w=Px(34.0),
    h=Px(34.0),
    radius=17.0,
    align=ACenter,
    justify=JCenter,
    bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.08) } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size~, color=t.p.text) |> ignore },
  )
  |> ignore
  hit(c, id)
}

///|
/// A body of words in a list card (PageParts.kt Body): 16 and 14 in, 12 apart.
fn body(c : @ui.Ctx, f : () -> Unit) -> Unit {
  c.box(w=Fill(1.0), padx=16.0, pady=14.0, gap=12.0, f) |> ignore
}

///|
/// A paragraph and a quieter one under it (Security.kt Para).
fn para(c : @ui.Ctx, main : String, sub? : String = "") -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), fn() {
    c.text(main, size=15.0, color=t.p.text, w=Fill(1.0), line=22.0) |> ignore
    if sub != "" {
      c.text(sub, size=15.0, color=t.p.subtle, w=Fill(1.0), line=22.0) |> ignore
    }
  })
  |> ignore
}

///|
/// A quiet note (Security.kt Note).
fn note(c : @ui.Ctx, words : String) -> Unit {
  let t = @sf.theme()
  c.text(words, size=12.0, color=t.p.subtle, w=Fill(1.0), line=18.0) |> ignore
}

///|
/// A small dot: on green, else warn or the line's grey (Security.kt Dot).
fn dot(c : @ui.Ctx, on : Bool, warned? : Bool = false) -> Unit {
  let t = @sf.theme()
  c.box(
    w=Px(7.0),
    h=Px(7.0),
    radius=3.5,
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
/// A tone's words in a pill of its colour (Profiles.kt TonePill).
fn tone_pill(c : @ui.Ctx, words : String, tone : String) -> Unit {
  let ink = tone_color(tone)
  c.box(padx=8.0, pady=2.0, radius=9.0, bg=@sf.alpha(ink, 0.12), fn() {
    c.text(words, size=12.0, weight=500, color=ink, wrap=false, line=16.0) |> ignore
  })
  |> ignore
}

///|
/// Words in the code face (CodeFont: a code, a key, a variable), one line unless `wrap`.
fn mono(
  c : @ui.Ctx,
  words : String,
  size? : Double = 13.0,
  weight? : Int = 400,
  color? : Int64,
  line? : Double = 0.0,
  wrap? : Bool = false,
  center? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let ink = color.unwrap_or(t.p.text)
  if center {
    c.box(w=Fill(1.0), align=ACenter, fn() {
      c.rich([@ui.span(words, mono=true)], size~, weight~, color=ink, line~, wrap~) |> ignore
    })
    |> ignore
  } else {
    c.rich([@ui.span(words, mono=true)], size~, weight~, color=ink, line~, wrap~, w=if wrap { Fill(1.0) } else { Auto })
    |> ignore
  }
}
