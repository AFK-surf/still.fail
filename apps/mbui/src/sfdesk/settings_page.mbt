// A settings page on the desktop as the web's frames one (ember web/src/styles/pages.css.ts page, pageNarrow,
// pageHead; brand.css.ts: the narrow page's column): its head, then what it holds in the 760 column in the pane's
// middle, 28 under the head, 80 room at its foot. The pages ported from the web's onto the library's parts
// (notifications.mbt, …) are laid out in it, their words in the library's true sizes.

///|
/// `title`'s page holding `content`, a block at a time (each laid out as it comes into view), `about` what it is for
/// said by a mark beside its title, or `lead` under it; back over it on a page under another (`back` where it goes).
fn desk_page(
  c : @ui.Ctx,
  core : Core,
  key : String,
  title : String,
  content : Array[() -> Unit],
  about? : String = "",
  lead? : String = "",
  back? : String = @sf.t("android-settings.title"),
  actions? : () -> Unit,
  head? : () -> Unit,
  on_back? : () -> Unit,
) -> Unit {
  let blocks : Array[() -> Unit] = []
  // a head of its own in place of the title (an account's: who it is), as the page's first block
  match head {
    // as far down as a title's head stands
    Some(h) =>
      blocks.push(fn() {
        let deep = settings_deep.val || on_back is Some(_)
        c.box(style=if deep { desk_own_head_deep } else { desk_own_head }, fn() {
          // back over it on a page under another (BackLink), as a title's head has it
          if deep {
            desk_back(c, core, back, on_back)
          }
          h()
        })
        |> ignore
      })
    None =>
      blocks.push(fn() {
        // (a step of the page's own: its back goes to the step before)
        @settings.wide_head(c, core, back, title, trailing?=actions, inside=true, about~, lead~, on_back?, deep=settings_deep.val || on_back is Some(_))
      })
  }
  for i, b in content {
    blocks.push(fn() { c.box(style=if i == 0 { desk_first } else { desk_block }, fn() { b() }) |> ignore })
  }
  desk_lanes(c, key, blocks)
}

///|
/// The way back over a page's own head (BackLink): its chevron and where it goes, the ink under the pointer.
fn desk_back(c : @ui.Ctx, core : Core, back : String, on_back : (() -> Unit)?) -> Unit {
  let t = @sf.theme()
  let id = c.id("settings-back")
  c.cursor(id, Hand)
  if c.clicked(id) {
    match on_back {
      Some(f) => f()
      None => (core.pop)()
    }
  }
  let lit = c.hovered(id)
  let b = c.box(style=desk_back_line, id~, fn() {
    @sf.icon(c, "chevron-left", size=desk_back_icon, color=if lit { t.p.text } else { t.p.muted }) |> ignore
    c.text(back, style=if lit { desk_back_lit } else { desk_back_words }) |> ignore
  })
  c.semantics(b, Link, id~, label=back)
}

///|
let desk_back_icon : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let desk_back_line : @ui.Style = @ui.css("row pb=S2 gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_back_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_back_lit : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Fg, wrap=false)

///|
/// A page's blocks in a list, each laid out as it comes into view: in the pane's middle, 24 from its sides at least,
/// 80 room at its foot.
fn desk_lanes(c : @ui.Ctx, key : String, blocks : Array[() -> Unit]) -> Unit {
  c.list("settings/" + key, blocks.length() + 1, 80.0, fn(i) {
    if i == blocks.length() {
      c.box(style=desk_foot, fn() {  }) |> ignore
    } else {
      c.box(style=desk_lane, fn() { c.box(style=desk_lane_column, fn() { (blocks[i])() }) |> ignore }) |> ignore
    }
  })
  |> ignore
}

///|
/// A place's page across the pane (连接: Connects.tsx's page): its head standing over what scrolls, its title, what it
/// is for by a mark beside it, what it does at its end; what it shows 8 under it.
fn desk_place(
  c : @ui.Ctx,
  core : Core,
  title : String,
  body : () -> Unit,
  about? : String = "",
  actions? : () -> Unit,
) -> Unit {
  c.box(style=desk_place_fill, fn() {
    c.box(style=desk_lane, fn() {
      c.box(style=desk_lane_column, fn() {
        @settings.wide_head(c, core, "", title, trailing?=actions, inside=true, about~, deep=false)
      })
      |> ignore
    })
    |> ignore
    c.box(style=desk_place_body, fn() { body() }) |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_place_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let desk_place_body : @ui.Style = desk_place_fill.then(@ui.css("pt=S2"))

///|
/// How wide the page's column is (pageNarrow: 760 at most), for what is drawn to its width before it is laid out.
fn desk_column(c : @ui.Ctx) -> Double {
  dmin(desk_column_most, dmin(c.width - 2.0 * desk_lane_in, desk_lane_most) - 2.0 * desk_column_in)
}

///|
/// A block's lane across the pane, its column in the middle: 792 at most, 24 from the pane's sides at least (its blocks'
/// own 16 inside it: the 760 column).
// kept across runs: a value (no field of it changes)
let desk_lane : @ui.Style = @ui.css("w=Full px=S6 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_lane_column : @ui.Style = @ui.style(w=Full, max_w=Fixed(desk_lane_most))

///|
let desk_lane_most : Double = 792.0

///|
let desk_lane_in : Double = 24.0

///|
/// The room at the page's foot.
// kept across runs: a value (no field of it changes)
let desk_foot : @ui.Style = @ui.css("w=Full h=S20")

///|
/// A page's head of its own (an account's): where a title's head would stand.
// kept across runs: a value (no field of it changes)
let desk_own_head : @ui.Style = @ui.css("w=Full px=S4 pt=S10")

///|
/// (with the way back over it: as high as a title's head with it stands)
// kept across runs: a value (no field of it changes)
let desk_own_head_deep : @ui.Style = @ui.css("w=Full px=S4 pt=S5")

///|
let desk_column_most : Double = 760.0

///|
let desk_column_in : Double = 16.0

///|
/// A block of the page, at the column's edges; the first 28 under the head (its own 12 and these 16).
// kept across runs: a value (no field of it changes)
let desk_block : @ui.Style = @ui.css("w=Full px=S4")

///|
// kept across runs: a value (no field of it changes)
let desk_first : @ui.Style = desk_block.then(@ui.css("pt=S4"))

///|
/// What the option chosen above it does (chat.css.ts appearanceHint: 8 under it, the meta's 12 muted, 52em at most).
fn desk_hint(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=desk_hint_box, fn() { c.text(words, style=desk_hint_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_hint_box : @ui.Style = @ui.style(w=Full, max_w=Fixed(desk_hint_most), pt=S2)

///|
let desk_hint_most : Double = 624.0

///|
// kept across runs: a value (no field of it changes)
let desk_hint_words : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
/// A hint and its link in a line (8 under what is over it).
// kept across runs: a value (no field of it changes)
let desk_hint_line : @ui.Style = @ui.css("w=Full pt=S2 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let desk_said_line : @ui.Style = @ui.css("row w=Full align=ACenter")

///|
/// A card of words (pages.css.ts card: 20 in, its rows 14 apart, the settings' corner on the card's ground; a row of
/// it: cardRow, 12 apart in its middle; its words cardRowText, 2 apart, the ui's 13 on 20, the title in 600).
// kept across runs: a value (no field of it changes)
let desk_card : @ui.Style = @ui.css("w=Full p=S5 gap=S3_5 radius=Xl3 bg=Card")

///|
// kept across runs: a value (no field of it changes)
let desk_card_row : @ui.Style = @ui.css("row w=Full gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_card_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let desk_strong : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Semibold, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Fg, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_muted : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, w=Full)

///|
/// A list (pages.css.ts list, listRow: reaching 12 past the column, its rows 2 apart, each 52 high at least, 10 by 12 in,
/// 12 apart, the field's corner; one that opens on the list's ground under the pointer; its title in 500, what is under
/// it the meta's 12 muted, red where it is wrong; a station's mark before its name, 6 apart; a chevron 16).
let desk_row_least : Double = 52.0

///|
let desk_chevron : Double = 16.0

///|
let desk_mark : Double = 14.0

///|
// kept across runs: a value (no field of it changes)
let desk_list : @ui.Style = @sf.outset(desk_list_out).then(@ui.css("gap=S0_5"))

///|
let desk_list_out : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  min_h=Fixed(desk_row_least),
  px=S3,
  py=S2_5,
  gap=S3,
  align=ACenter,
  radius=Xl,
)

///|
// kept across runs: a value (no field of it changes)
let desk_list_link : @ui.Style = desk_list_row.then(@ui.css("hovered{bg=Hover}"))

///|
// kept across runs: a value (no field of it changes)
let desk_list_text : @ui.Style = @ui.style(w=@sf.grow, gap=S0_5)

///|
// kept across runs: a value (no field of it changes)
let desk_named : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_list_title : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, weight=Medium, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_note_bad : @ui.TextStyle = desk_note.then(@ui.text_style(color=Danger))

///|
/// A choice of a few (Segmented) as wide as its options, at the column's start.
fn desk_choice(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=desk_choice_row, fn() { body() }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let desk_choice_row : @ui.Style = @ui.css("row w=Full")

///|
/// A list's filter on the wide page (components.tsx MineFilter, not compact; History.css.ts mineFilterBtn,
/// mineFilterWide): a 32 high button 8 in, the field's line round it, 12 over what it filters; its funnel 16 and what
/// it shows in the muted ink, the words' under the pointer or while open, the accent's on its ground while it narrows;
/// pressed, its menu of choices under it (all or the viewer's, the shown checked), at its end. `of`: what it filters
/// (`connects`), as its words name it.
fn mine_filter(c : @ui.Ctx, key : String, of : String, mine : Bool, set : (Bool) -> Unit) -> Unit {
  let t = @sf.theme()
  let id = c.id(key)
  c.cursor(id, Hand)
  let open = mine_filter_open.get(key).unwrap_or(false)
  if c.clicked(id) {
    mine_filter_open[key] = !open
  }
  let named = if mine { @sf.t("web-main.filter." + of + ".mine") } else { @sf.t("web-main.filter.all") }
  let lit = c.lit(id) || open
  let ink = if mine {
    t.p.accent_text
  } else if lit {
    t.p.text
  } else {
    t.p.muted
  }
  let b = c.box(style=if mine { mine_filter_on } else { mine_filter_box }, selected=open, id~, fn() {
    @sf.icon(c, "filter", size=mine_filter_icon, color=ink) |> ignore
    c.text(named, style=if mine { mine_filter_on_words } else if lit { mine_filter_lit_words } else { mine_filter_words })
    |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-main.filter." + of + ".named", args=[("named", named)]), expanded=open)
  let entries = [
    @kit.menu_radio("all", !mine, label=@sf.t("web-main.filter." + of + ".all")),
    @kit.menu_radio("mine", mine, label=@sf.t("web-main.filter." + of + ".mine")),
  ]
  let m = @sf.menu(c, key + "/menu", open, id, entries, {}, mine_filter_menu_w)
  if open && !m.open {
    mine_filter_open[key] = false
  }
  match m.chosen {
    Some(v) => {
      mine_filter_open[key] = false
      if (v == "mine") != mine {
        set(v == "mine")
      }
    }
    None => ()
  }
}

///|
/// Which filter's menu is open, by its key.
// kept across runs: said again by each press; settings_reset empties it
let mine_filter_open : Map[String, Bool] = {}

///|
let mine_filter_icon : Double = 16.0

///|
/// A menu of choices (controls.css.ts chooserMenu: 220 wide at least).
let mine_filter_menu_w : Double = 220.0

///|
// kept across runs: a value (no field of it changes)
let mine_filter_box : @ui.Style = @ui.css(
  #|row h=S8 min_w=S8 px=S2 gap=S1_5 align=ACenter radius=Xl border=B1 border_color=Line hovered{bg=Hover}
  #|selected{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let mine_filter_on : @ui.Style = mine_filter_box.then(@ui.css("bg=AccentBg"))

///|
// kept across runs: a value (no field of it changes)
let mine_filter_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let mine_filter_lit_words : @ui.TextStyle = mine_filter_words.then(@ui.text_style(color=Fg))

///|
// kept across runs: a value (no field of it changes)
let mine_filter_on_words : @ui.TextStyle = mine_filter_words.then(@ui.text_style(color=AccentText))

///|
/// A dialog over a desktop page (parts.tsx Dialog: the library's): its title, what it is about, what it holds, its
/// buttons at its foot; each given what closes it.
priv struct DeskDialog {
  key : String
  title : String
  description : String
  wide : Bool
  /// its title, its step's count beside it and what it is about as they are now (a wizard's), over those given
  live : (() -> (String, String, String))?
  /// what is let go of as it closes by its ✕, Esc or a press outside
  gone : (() -> Unit)?
  body : (@ui.Ctx, () -> Unit) -> Unit
  foot : (@ui.Ctx, () -> Unit) -> Unit
}

///|
/// The dialog up ("None": none), and the last one put up, drawn as it goes.
// kept across runs: said by open_dialog and its close; settings_reset empties them
let desk_dialog : Ref[DeskDialog?] = Ref(None)

///|
// kept across runs: said by open_dialog; settings_reset empties it
let desk_dialog_last : Ref[DeskDialog?] = Ref(None)

///|
/// How many dialogs were put up (a dialog's fields' keys, new each time it opens).
// kept across runs: counted by open_dialog; settings_reset puts it back
let desk_dialogs : Ref[Int] = Ref(0)

///|
/// Puts up a dialog over the page.
fn open_dialog(
  key : String,
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  foot : (@ui.Ctx, () -> Unit) -> Unit,
  description? : String = "",
  wide? : Bool = false,
  live? : () -> (String, String, String),
  gone? : () -> Unit,
) -> Unit {
  let d = { key, title, description, wide, live, gone, body, foot }
  desk_dialogs.val += 1
  desk_dialog.val = Some(d)
  desk_dialog_last.val = Some(d)
}

///|
/// The dialog, over everything the page shows (sheet.mbt overlay): while up, and as it goes.
fn desk_dialog_overlay(c : @ui.Ctx) -> Unit {
  match desk_dialog_last.val {
    Some(d) => {
      let shut = fn() { desk_dialog.val = None }
      let open = match desk_dialog.val {
        Some(now) => now.key == d.key
        None => false
      }
      let (title, step, description) = match d.live {
        Some(f) => f()
        None => (d.title, "", d.description)
      }
      let still = @sf.dialog(c, d.key, open, title, fn() { (d.body)(c, shut) }, description~, wide=d.wide, close_label=@sf.t("common.close"), step~, footer=fn() {
        (d.foot)(c, shut)
      })
      if open && !still {
        shut()
        match d.gone {
          Some(f) => f()
          None => ()
        }
      }
    }
    None => ()
  }
}

///|
/// What a list still waits on (the core's `wait`: stations not read yet, each failure said): `count` rows' shapes.
fn desk_waiting_rows(c : @ui.Ctx, wait : Json?, count? : Int = 3) -> Unit {
  let failing = failing_of(wait)
  @sf.waiting(c, shape=Rows, count~, note={ reading: failing.length() == 0, text: "", failing })
}
