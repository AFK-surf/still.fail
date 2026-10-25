// What the desktop's settings pages share beside the library's page (src/sf page.mbt): a place's page across the
// pane, a hint, a list's filter, a dialog. The web's desktop pieces they still draw themselves (desk_card, desk_list,
// …) are the library's, named here; detlint's page-look counts them in the pages, each file's only falling.

using @sf {
  desk_lanes,
  desk_lane,
  desk_lane_column,
  desk_lane_most,
  desk_lane_in,
  desk_column_most,
  desk_column_in,
  desk_own_head,
  desk_hint_box,
  desk_hint_words,
  desk_card,
  desk_card_row,
  desk_card_text,
  desk_strong,
  desk_words,
  desk_muted,
  desk_row_least,
  desk_chevron,
  desk_mark,
  desk_list,
  desk_list_out,
  desk_list_link,
  desk_list_text,
  desk_named,
  desk_list_title,
  desk_note_line,
  desk_note_bad,
}

///|
// kept across runs: a value (no field of it changes)
let desk_list_row : @ui.Style = @sf.wide_list_row

///|
// kept across runs: a value (no field of it changes)
let desk_note : @ui.TextStyle = @sf.wide_list_note

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
/// What the option chosen above it does (chat.css.ts appearanceHint: 8 under it, the meta's 12 muted, 52em at most).
fn desk_hint(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=desk_hint_box, fn() { c.text(words, style=desk_hint_words) |> ignore }) |> ignore
}

///|
/// A hint and its link in a line (8 under what is over it).
// kept across runs: a value (no field of it changes)
let desk_hint_line : @ui.Style = @ui.css("w=Full pt=S2 gap=S1")

///|
// kept across runs: a value (no field of it changes)
let desk_said_line : @ui.Style = @ui.css("row w=Full align=ACenter")

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
  let m = @sf.dropdown(c, key + "/menu", open, id, entries, {}, mine_filter_menu_w)
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
/// How many dialogs were put up (a dialog's fields' keys, new each time it opens).
// kept across runs: counted by open_dialog; settings_reset puts it back
let desk_dialogs : Ref[Int] = Ref(0)

///|
/// Puts up a dialog over the page (parts.tsx Dialog: the library's panel opened by nothing, @sf.panel): its title,
/// what it is about, what it holds, its buttons at its foot, each given what closes it; `wide`, 640 wide; `live`: its
/// title, its step's count and what it is about as they are now (a wizard's); `gone`: what is let go of as it closes
/// by its ✕, Esc or a press outside.
fn open_dialog(
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  foot : (@ui.Ctx, () -> Unit) -> Unit,
  description? : String = "",
  wide? : Bool = false,
  live? : () -> (String, String, String),
  gone? : () -> Unit = fn() {  },
) -> Unit {
  desk_dialogs.val += 1
  @sf.panel(title, body, from=Unanchored, description~, foot~, wide~, live?, gone~)
}

///|
/// What a list still waits on (the core's `wait`: stations not read yet, each failure said): `count` rows' shapes.
fn desk_waiting_rows(c : @ui.Ctx, wait : Json?, count? : Int = 3) -> Unit {
  let failing = failing_of(wait)
  @sf.waiting(c, shape=Rows, count~, note={ reading: failing.length() == 0, text: "", failing })
}
