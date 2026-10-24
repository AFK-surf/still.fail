// A settings page drawn into whatever box it is given, one page for every frame and input (docs/architecture.md
// Pages). It is laid out by its own width, as the web lays its pages out by the window's:
// - narrower than the web's narrow app (640), as the web's mobile pages are (web/src/mobile/parts.tsx TopBack,
//   LargeTitle, SectionHeader, ListCard, ListRow): back over a large title, its rows on rounded cards;
// - wider, as the web's desktop pages are (web/src/styles/pages.css.ts page, pageHead, list, card; ui.tsx Section):
//   their head, a column 760 wide at most in the pane's middle, sections with their titles, lists and cards
//   (settings_page.mbt).
// How it answers the hand is the input's: what lights under a mouse lights under a finger's press (a style's
// `hovered`, `c.lit`), and a finger's press ripples.

///|
/// How a page is laid out, by its own width: as the web's narrow app is (`Narrow`), or its desktop pages (`Wide`).
enum Look {
  Narrow
  Wide
} derive(Eq)

///|
/// How the page being drawn is laid out, by the width of its box.
fn look_of(c : @ui.Ctx) -> Look {
  if c.width < narrow_most {
    Narrow
  } else {
    Wide
  }
}

///|
/// The widest a page is laid out as the narrow app is (the web's: max-width 640, where its narrow app takes over).
let narrow_most : Double = 640.0

///|
/// A page of the settings: `title`'s, holding `content` a block at a time (each laid out as it comes into view), in the
/// frame it is given (`frame`: back where there is somewhere to go back to, the room over and under it). `lead`: what
/// it is for, under its title; `about`: what it is for said by a mark beside its title (wide); `actions`: what it does,
/// at its title's end.
fn look_page(
  c : @ui.Ctx,
  core : Core,
  frame : PageFrame,
  look : Look,
  key : String,
  title : String,
  content : Array[() -> Unit],
  lead? : String = "",
  about? : String = "",
  actions? : () -> Unit,
  head? : () -> Unit,
) -> Unit {
  match look {
    Wide =>
      desk_page(
        c,
        core,
        key,
        title,
        content,
        about~,
        lead~,
        back=frame.back.unwrap_or(""),
        deep=frame.back is Some(_),
        actions?,
        head?,
        top=frame.top,
        foot=frame.foot,
      )
    Narrow => {
      let blocks : Array[() -> Unit] = []
      if frame.top > 0.0 {
        blocks.push(fn() { c.box(style=@ui.style(w=Full, h=Fixed(frame.top)), fn() {  }) |> ignore })
      }
      // back to where it was opened from (TopBack), then its large title (LargeTitle), what it is for under it
      match frame.back {
        Some(label) =>
          blocks.push(fn() {
            c.box(style=narrow_back_line, fn() {
              if @sf.nav_back(c, "settings-back", label) {
                (core.pop)()
              }
            })
            |> ignore
          })
        None => ()
      }
      // (a place's top page: the frame's bar over it names it, and holds what it does at its end)
      if frame.named {
        match actions {
          Some(f) => @settings.root_bar_actions.val = Some(f)
          None => ()
        }
      }
      if !frame.named {
        blocks.push(fn() {
          c.box(style=narrow_title_box, fn() {
            c.box(style=narrow_title_line, fn() {
              c.box(style=narrow_title_words, fn() { c.text(title, style=narrow_title) |> ignore }) |> ignore
              match actions {
                Some(f) => f()
                None => ()
              }
            })
            |> ignore
          })
          |> ignore
        })
      }
      if lead != "" {
        blocks.push(fn() { c.box(style=narrow_lead_box, fn() { c.text(lead, style=narrow_lead) |> ignore }) |> ignore })
      }
      for b in content {
        blocks.push(b)
      }
      // 30 under what it shows (the narrow pages' foot), then the frame's room
      let foot = narrow_foot + frame.foot
      blocks.push(fn() { c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore })
      c.list("settings/" + key, blocks.length(), 80.0, fn(i) { (blocks[i])() }) |> ignore
    }
  }
}

///|
/// Back's line over the large title (TopBack: 10 in, 6 over, 4 under).
// kept across runs: a value (no field of it changes)
let narrow_back_line : @ui.Style = @ui.css("row w=Full px=S2_5 pt=S1_5 pb=S1 align=ACenter")

///|
/// The large title (LargeTitle: 16 in, 6 under it), what it does at its end.
// kept across runs: a value (no field of it changes)
let narrow_title_box : @ui.Style = @ui.css("w=Full px=S4 pb=S1_5")

///|
// kept across runs: a value (no field of it changes)
let narrow_title_line : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_title_words : @ui.Style = @ui.style(w=@sf.grow, min_w=S20)

///|
// kept across runs: a value (no field of it changes)
let narrow_title : @ui.TextStyle = @sf.large_title.then(@ui.text_style(w=Cut))

///|
/// What the page is for under its title (PageNote: 24 in, 10 under it, the secondary words).
// kept across runs: a value (no field of it changes)
let narrow_lead_box : @ui.Style = @ui.css("w=Full px=S6 pb=S2_5")

///|
// kept across runs: a value (no field of it changes)
let narrow_lead : @ui.TextStyle = @sf.secondary.then(@sf.full_words)

///|
let narrow_foot : Double = 30.0

///|
/// A section of the page: its title over what it holds, `note` what it holds said by it (wide: the web's Section;
/// narrow: SectionHeader where `heads`, else what it holds alone, as the web's mobile pages leave a group's title out).
fn look_section(
  c : @ui.Ctx,
  look : Look,
  title : String,
  body : () -> Unit,
  heads? : Bool = false,
  note? : String = "",
) -> Unit {
  match look {
    Wide => @sf.section(c, title, body, note~)
    Narrow => {
      if heads && title != "" {
        look_heading(c, look, title, note~)
      }
      body()
    }
  }
}

///|
/// A heading over a group (narrow: SectionHeader, 24 in, its words strong; wide: a section's title).
fn look_heading(c : @ui.Ctx, look : Look, title : String, note? : String = "") -> Unit {
  match look {
    // what the group holds said at its end (SectionHeader's trailing)
    Narrow =>
      c.box(style=narrow_heading_line, fn() {
        c.text(title, style=narrow_heading) |> ignore
        c.spacer()
        if note != "" {
          c.text(note, style=narrow_heading_note) |> ignore
        }
      })
      |> ignore
    Wide =>
      c.box(style=wide_heading_line, fn() {
        c.text(title, style=wide_heading) |> ignore
        if note != "" {
          c.text(note, style=wide_value) |> ignore
        }
      })
      |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let narrow_heading_note : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
/// SectionHeader's line: 24 in, 20 at its end, 14 over, 6 under.
// kept across runs: a value (no field of it changes)
let narrow_heading_line : @ui.Style = @ui.css("row w=Full pl=S6 pr=S5 pt=S3_5 pb=S1_5 gap=S2 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let narrow_heading : @ui.TextStyle = @sf.body.then(@sf.strong)

///|
// kept across runs: a value (no field of it changes)
let wide_heading_line : @ui.Style = @ui.css("w=Full pt=S5")

///|
// kept across runs: a value (no field of it changes)
let wide_heading : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Semibold, color=Fg, w=Full)

///|
/// Rows together: narrow, on a rounded card (ListCard: 12 from the page's sides, 10 under it, its rows 8 in); wide, the
/// web's list on the page (its rows on nothing but the pointer's ground), or on a card where `card` (pages.css.ts card).
fn look_group(c : @ui.Ctx, look : Look, body : () -> Unit, card? : Bool = false) -> Unit {
  match look {
    Narrow => c.box(style=narrow_card_room, fn() { c.box(style=narrow_card, body) |> ignore }) |> ignore
    Wide => c.box(style=if card { desk_card } else { desk_list }, body) |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let narrow_card_room : @ui.Style = @ui.css("w=Full px=S3 pb=S2_5")

///|
/// ListCard: its rows 8 in, its corner concentric round theirs.
// kept across runs: a value (no field of it changes)
let narrow_card : @ui.Style = @ui.style(w=Full, p=S2, radius=@sf.list_card_radius, bg=Card, clip=true)

///|
/// A choice of a few (narrow: Seg as wide as the page less 12 each side, 34 high; wide: the web's Segmented at the
/// column's start). Answers the one chosen (a press's, this frame).
fn look_choice(c : @ui.Ctx, look : Look, key : String, labels : Array[String], at : Int) -> Int {
  let mut picked = at
  match look {
    Narrow =>
      c.box(style=narrow_choice_box, fn() { picked = @sf.seg(c, key, labels, at, fill=true, height=narrow_choice_h) })
      |> ignore
    Wide => desk_choice(c, fn() { picked = @sf.segmented(c, key, labels, at) })
  }
  picked
}

///|
// kept across runs: a value (no field of it changes)
let narrow_choice_box : @ui.Style = @ui.css("w=Full px=S3")

///|
let narrow_choice_h : Double = 34.0

///|
/// What the choice over it does, in a line or two (narrow: mSegNote, 24 in, 8 over; wide: the web's hint under it).
fn look_note(c : @ui.Ctx, look : Look, words : String, bad? : Bool = false) -> Unit {
  match look {
    Narrow =>
      c.box(style=narrow_note_box, fn() { c.text(words, style=if bad { narrow_note_bad } else { narrow_note }) |> ignore })
      |> ignore
    Wide =>
      if bad {
        c.box(style=desk_hint_box, fn() { c.text(words, style=desk_note_bad) |> ignore }) |> ignore
      } else {
        desk_hint(c, words)
      }
  }
}

///|
// kept across runs: a value (no field of it changes)
let narrow_note_box : @ui.Style = @ui.css("w=Full px=S6 pt=S2 pb=S1")

///|
// kept across runs: a value (no field of it changes)
let narrow_note : @ui.TextStyle = @sf.secondary.then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
let narrow_note_bad : @ui.TextStyle = narrow_note.then(@sf.bad)

///|
/// A note's words in a line, as wide as they are (a link after them).
// kept across runs: a value (no field of it changes)
let narrow_note_inline : @ui.TextStyle = @sf.secondary.then(@sf.one_line)

///|
// kept across runs: a value (no field of it changes)
let desk_hint_inline : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// A card of words on the page (narrow: Card, 12 from the page's sides, 10 under it; wide: pages.css.ts card, at the
/// column's edges), its rows 14 apart, 20 in.
fn look_card(c : @ui.Ctx, look : Look, body : () -> Unit) -> Unit {
  match look {
    Narrow => c.box(style=narrow_card_room, fn() { c.box(style=desk_card, body) |> ignore }) |> ignore
    Wide => c.box(style=desk_card, body) |> ignore
  }
}

///|
/// A row that goes somewhere: its title (and `note` under it), what it says at its end (`value`, in the link's ink where `value_lit`), and
/// a chevron (none where not `chevron`: what it does is done here), or an arrow out where it goes `out` of the app.
/// True on the frame it is pressed.
fn look_link(
  c : @ui.Ctx,
  look : Look,
  key : String,
  title : String,
  value? : String = "",
  value_lit? : Bool = false,
  out? : Bool = false,
  chevron? : Bool = true,
  note? : String = "",
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let icon = if out { "arrow-up-right" } else { "chevron-right" }
  let b = match look {
    Narrow =>
      c.box(style=narrow_row, id~, fn() {
        if note == "" {
          c.text(title, style=narrow_row_title) |> ignore
        } else {
          c.box(style=narrow_row_words, fn() {
            c.text(title, style=narrow_row_title) |> ignore
            c.text(note, style=narrow_link_note) |> ignore
          })
          |> ignore
        }
        if value != "" {
          c.text(value, style=narrow_value, color?=if value_lit { Some(@sf.link_ink()) } else { None }) |> ignore
        }
        if chevron || out {
          @sf.icon(c, icon, size=narrow_chevron, color=t.p.subtle) |> ignore
        }
        finger_ripple(c, id)
      })
    Wide =>
      c.box(style=desk_list_link, id~, fn() {
        c.box(style=desk_list_text, fn() {
          c.text(title, style=desk_list_title) |> ignore
          if note != "" {
            c.text(note, style=desk_note) |> ignore
          }
        })
        |> ignore
        if value != "" {
          c.text(value, style=wide_value, color?=if value_lit { Some(t.p.accent_text) } else { None }) |> ignore
        }
        if chevron || out {
          @sf.icon(c, icon, size=desk_chevron, color=t.p.muted) |> ignore
        }
      })
  }
  c.semantics(b, Link, id~, label=title)
  c.clicked(id)
}

///|
/// A row that turns something on or off: its title, a note under it, the switch at its end; the whole row takes the
/// press (narrow), or the switch and its words (wide: the library's switch row). Answers whether it is on now.
fn look_switch(c : @ui.Ctx, look : Look, key : String, title : String, on : Bool, note? : String = "") -> Bool {
  match look {
    Wide => @sf.switch_row(c, key, title, on, note~)
    Narrow => {
      let id = c.id(key)
      let b = c.box(style=narrow_row, id~, fn() {
        c.box(style=narrow_row_words, fn() {
          c.text(title, style=narrow_switch_title) |> ignore
          if note != "" {
            c.text(note, style=@sf.meta.then(@sf.full_words)) |> ignore
          }
        })
        |> ignore
        @settings.switch(c, key, on)
        finger_ripple(c, id)
      })
      c.semantics(b, Switch, id~, label=title, check=if on { @ui.Check::On } else { @ui.Check::Off })
      if c.clicked(id) {
        !on
      } else {
        on
      }
    }
  }
}

///|
/// A row that says how something stands, going nowhere: its title, a note under it (narrow: on its card; wide: the
/// web's list row, no ground under the pointer).
fn look_said_row(c : @ui.Ctx, look : Look, title : String, note : String) -> Unit {
  match look {
    Narrow =>
      c.box(style=narrow_said_row, fn() {
        c.box(style=narrow_row_words, fn() {
          c.text(title, style=narrow_row_title) |> ignore
          if note != "" {
            c.text(note, style=@sf.secondary.then(@sf.full_words)) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    Wide =>
      c.box(style=desk_list_row, fn() {
        c.box(style=desk_list_text, fn() {
          c.text(title, style=desk_list_title) |> ignore
          if note != "" {
            c.text(note, style=desk_note) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
  }
}

///|
// kept across runs: a value (no field of it changes)
let narrow_said_row : @ui.Style = @ui.css("row w=Full px=S3 py=S3 gap=S3 radius=Inner align=ACenter")

///|
/// A finger's press rippling over a row (ListRow's, its corner concentric with its card's).
fn finger_ripple(c : @ui.Ctx, id : Int) -> Unit {
  if @ui.pointing() is Finger {
    @motion.ripple(c, id, @sf.row_corner)
  }
}

///|
/// A row of a card (ListRow): 12 by 12 in, what it holds 12 apart, its ground concentric with the card's; lit under
/// the pointer, or a finger's press.
// kept across runs: a value (no field of it changes)
let narrow_row : @ui.Style = @ui.css("row w=Full px=S3 py=S3 gap=S3 radius=Inner align=ACenter hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let narrow_row_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let narrow_row_title : @ui.TextStyle = @sf.body.then(@sf.one_line).then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
let narrow_switch_title : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
// kept across runs: a value (no field of it changes)
let narrow_value : @ui.TextStyle = @sf.value

///|
let narrow_chevron : Double = 14.0

///|
/// The words under a row's title (the secondary's, in lines).
// kept across runs: a value (no field of it changes)
let narrow_link_note : @ui.TextStyle = @sf.secondary.then(@sf.full_words)

///|
/// What a wide row says at its end (the meta's 12, muted, on one line).
// kept across runs: a value (no field of it changes)
let wide_value : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, wrap=false)

///|
/// What back over a page says: the title of the page it goes back to.
pub fn back_label(p : Page) -> String {
  match p {
    Home => @sf.t("android-misc.bar.place.chats")
    Settings | Setting(Route::Home) => @sf.t("android-settings.title")
    Setting(Route::About) => @sf.t("web-pages.settings.nav.about")
    Setting(Route::Permissions) => @sf.t("web-pages.settings.nav.permissions")
    Setting(Route::Version) => @sf.t("web-pages.settings.nav.version")
    Setting(Route::Memories) => @sf.t("web-pages.settings.memory.title")
    Setting(Route::AutoDecisions) => @sf.t("web-pages.automaticDecisions.title")
    Setting(Route::Archiving) => @sf.t("web-pages.archiving.title")
    Setting(Route::Shortcuts) => @sf.t("web-main.shortcuts.title")
    Setting(Route::Usage) => @sf.t("web-pages.settings.nav.usage")
    Setting(Route::Security) => @sf.t("web-pages.security.title")
    Setting(Route::Vault) => @sf.t("web-pages.vault.title")
    Place("usage") => @sf.t("web-pages.settings.nav.usage")
    _ => @sf.t("common.back")
  }
}
