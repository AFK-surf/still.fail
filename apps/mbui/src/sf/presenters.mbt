// The presenters (docs/architecture.md, Presenters): a menu, a pick (one of a list, searched when long), a small panel,
// a confirm and a question with a line to write. A page says what it shows and what opened it, once, as it is pressed;
// the presenter decides how: with a finger short of the Large tier (@sf.layout), a sheet from the window's foot (the
// phone's: its grabber, dragged down or back to close); otherwise the web's, a small panel beside what opened it (a
// menu, a pick, a panel) or a dialog in the middle of the window (a confirm, a question). One host draws them all over
// the shell (`presented`), after the pages, each frame: it keeps what is open, one over another, the topmost taking
// back, Escape and a press outside, and the focus going into it as it opens.

///|
/// What opened a presenter: the box pressed (its id, `c.id(key)`), a rectangle of the window (x, y, w, h: a point
/// is one 0 by 0, where a right click was), or nothing (what is asked by no press of the person's).
pub(all) enum Anchor {
  Of(Int)
  At(Double, Double, Double, Double)
  Unanchored
} derive(Eq)

///|
/// The point (`x`, `y`) of the window as what opened a presenter (a right click's).
pub fn at_point(x : Double, y : Double) -> Anchor {
  At(x, y, 0.0, 0.0)
}

///|
/// One to pick (`pick`): what it is known by, its words, a line under or beside them (`note`), its icon.
pub(all) struct Choice {
  key : String
  label : String
  note : String
  icon : String
}

///|
pub fn choice(key : String, label : String, note? : String = "", icon? : String = "") -> Choice {
  { key, label, note, icon }
}

///|
/// What a presenter shows.
priv enum Shows {
  /// a menu: its items (None a line between), its title ("" none), where a small panel lines up with what opened it
  Menu(Array[MenuItem?], String, @ui.Along)
  /// a pick: its title, the choices, the one chosen now, what choosing one does
  Pick(String, Array[Choice], String, (String) -> Unit)
  /// a small panel: its title ("" none), what it holds (given what closes it), how wide beside what opened it
  Panel(String, (@ui.Ctx, () -> Unit) -> Unit, Double)
  /// a confirm: its title, what it does, its action, whether that cannot be undone, what goes on once it is said
  Confirm(String, String, String, Bool, () -> Unit)
  /// a question: its title, the line at first, its placeholder, its action, the hint under it, whether a secret, what
  /// goes on with the line (trimmed)
  Ask(String, String, String, String, String, Bool, (String) -> Unit)
}

///|
/// One presented: what it shows, what opened it, whether it is open (closed, it is drawn as it goes); the line written
/// in it (a question's, a pick's search), whether its field had the focus given yet.
priv struct Presented {
  serial : Int
  shows : Shows
  from : Anchor
  mut open : Bool
  line : @ui.Field
  mut typed : String
  mut focused : Bool
}

///|
/// How a presenter is drawn this frame (what a test reads).
priv enum How {
  AsSheet
  AsPopover
  AsDialog
} derive(Eq, Show, Debug)

///|
/// What is presented, the lowest first; how many were opened (each one's keys its own).
// kept across runs: put back by presenters_reset (parts_reset)
let presented_now : Array[Presented] = []

///|
// kept across runs: put back by presenters_reset (parts_reset)
let presented_count : Ref[Int] = Ref(0)

///|
/// How each one open was drawn in the last frame, the lowest first.
// kept across runs: put back by presenters_reset (parts_reset)
let presented_how : Array[How] = []

///|
/// Nothing presented (the app begun again).
pub fn presenters_reset() -> Unit {
  presented_now.clear()
  presented_count.val = 0
  presented_how.clear()
}

///|
fn present(shows : Shows, from : Anchor, line? : String = "") -> Unit {
  presented_count.val += 1
  presented_now.push({
    serial: presented_count.val,
    shows,
    from,
    open: true,
    line: @ui.Field::new(text=line),
    typed: line,
    focused: false,
  })
}

///|
/// A menu of `items` (None: a line between; parts.tsx Menu), opened by `from`: chosen, it closes and the item's
/// `select` goes on. `title` over them ("" none); `along`: how it lines up with what opened it beside it.
pub fn menu(items : Array[MenuItem?], from~ : Anchor, title? : String = "", along? : @ui.Along = Start) -> Unit {
  present(Menu(items, title, along), from)
}

///|
/// A pick of one of `choices` (`chosen` the one now), titled `title`, opened by `from`: chosen, it closes and `choose`
/// goes on with its key. Longer than pick_search_from, a line to search them by is over them.
pub fn pick(title : String, choices : Array[Choice], chosen : String, choose : (String) -> Unit, from~ : Anchor) -> Unit {
  present(Pick(title, choices, chosen, choose), from)
}

///|
/// A small panel (parts.tsx PanelHead and its rows, fields) titled `title` ("" none), opened by `from`: `body` draws
/// what it holds each frame, given what closes it. `w`: how wide beside what opened it.
pub fn panel(title : String, body : (@ui.Ctx, () -> Unit) -> Unit, from~ : Anchor, w? : Double = panel_w) -> Unit {
  present(Panel(title, body, w), from)
}

///|
/// Asks before `action` (parts.tsx Confirm; PageParts.kt confirm): `title`, what it does (`words`), the cancel and
/// `action` (in red when `danger`: what cannot be undone). Said, it closes and `run` goes on.
pub fn confirm(
  title : String,
  words : String,
  action : String,
  run : () -> Unit,
  danger? : Bool = false,
  from? : Anchor = Unanchored,
) -> Unit {
  present(Confirm(title, words, action, danger, run), from)
}

///|
/// Asks for a line (PageParts.kt ask): `title`, a field (`value` in it at first, `placeholder` while it is empty,
/// `hint` under it, as dots when `secret`), the cancel and `action`, which can be pressed once the line has words that
/// differ from `value` (Enter too). Said, it closes and `run` goes on with the line, trimmed.
pub fn ask(
  title : String,
  action : String,
  run : (String) -> Unit,
  value? : String = "",
  placeholder? : String = "",
  hint? : String = "",
  secret? : Bool = false,
  from? : Anchor = Unanchored,
) -> Unit {
  present(Ask(title, value, placeholder, action, hint, secret, run), from, line=value)
}

///|
/// Whether anything is presented now (the shell's own back waits while it is).
pub fn presenting() -> Bool {
  presented_now.iter().any(fn(p) { p.open })
}

///|
/// Closes the topmost presented, as back does.
pub fn close_presented() -> Unit {
  for i = presented_now.length() - 1; i >= 0; i = i - 1 {
    if presented_now[i].open {
      close_from(i)
      return
    }
  }
}

///|
/// Closes the one at `i` and all over it (a pick a panel opened goes with the panel).
fn close_from(i : Int) -> Unit {
  for k in i..<presented_now.length() {
    presented_now[k].open = false
  }
}

///|
/// The host (see the file's head): what is presented, drawn over everything the app shows. Called by the shell once a
/// frame, at the window's top level, after the pages: it is sized by the window (a sheet spans it whichever pane
/// opened it), and anchored to what opened it wherever that is.
pub fn presented(c : @ui.Ctx) -> Unit {
  presented_how.clear()
  let (ww, _) = c.window_size()
  // a sheet with a finger short of the Large tier, the web's otherwise (docs/architecture.md)
  let sheet = @ui.pointing() is Finger && layout(ww) != Large
  let gone : Array[Int] = []
  for i, p in presented_now.copy() {
    let was = p.open
    let mut open = false
    let mut built = false
    c.scope(p.serial, fn() {
      let (o, b) = draw_presented(c, p, sheet)
      open = o
      built = b
    })
    if was && !open {
      close_from(i)
    }
    if was && open {
      presented_how.push(how_of(p.shows, sheet))
    }
    if !p.open && !built {
      gone.push(p.serial)
    }
  }
  if !gone.is_empty() {
    let left = presented_now.filter(fn(p) { !gone.contains(p.serial) })
    presented_now.clear()
    presented_now.append(left)
  }
}

///|
fn how_of(shows : Shows, sheet : Bool) -> How {
  match (sheet, shows) {
    (true, _) => AsSheet
    (false, Menu(_, _, _) | Pick(_, _, _, _) | Panel(_, _, _)) => AsPopover
    (false, Confirm(_, _, _, _, _) | Ask(_, _, _, _, _, _, _)) => AsDialog
  }
}

///|
/// `p` drawn as a sheet or as the web's: whether it is open now, and whether it is drawn at all (still going).
fn draw_presented(c : @ui.Ctx, p : Presented, sheet : Bool) -> (Bool, Bool) {
  let key = "sf-present"
  if sheet {
    return present_sheet(c, key, p)
  }
  match p.shows {
    Menu(items, title, along) => menu_popover(c, key, p, items, title, along)
    Pick(title, choices, chosen, choose) => pick_popover(c, key, p, title, choices, chosen, choose)
    Panel(title, body, w) => panel_popover(c, key, p, title, body, w)
    Confirm(title, words, action, danger, run) => confirm_centred(c, key, p, title, words, action, danger, run)
    Ask(title, value, placeholder, action, hint, secret, run) =>
      ask_centred(c, key, p, title, value, placeholder, action, hint, secret, run)
  }
}

///|
/// What chosen or said in `p` does, once the frame is built: `p` closes (and what is over it), then `f` goes on.
fn done_with(c : @ui.Ctx, p : Presented, f : () -> Unit) -> Unit {
  match presented_now.search_by(fn(q) { q.serial == p.serial }) {
    Some(i) => close_from(i)
    None => ()
  }
  c.tell("sf-present/\{p.serial}", f)
}

///|
/// The box opened by and the rectangle to put a small panel beside (`at`): what opened it, or the window's middle a
/// third down when nothing did.
fn anchor_of(c : @ui.Ctx, from : Anchor) -> (Int, (Double, Double, Double, Double)?) {
  match from {
    Of(id) => (id, None)
    At(x, y, w, h) => (0, Some((x, y, w, h)))
    Unanchored => {
      let (ww, wh) = c.window_size()
      (0, Some((ww / 2.0, wh / 3.0, 0.0, 0.0)))
    }
  }
}

///|
/// Whether a pick of `n` has its search (the phone's run picker's and the web's chooser's, past a screenful).
pub let pick_search_from : Int = 8

///|
/// A small panel's width beside what opened it, by default (parts.css.ts popover: 280).
pub let panel_w : Double = 280.0

///|
/// What a pick's list holds at most before it scrolls in a small panel (the web's chooser: 320).
pub let pick_list_most : Double = 320.0

///|
/// The choices whose words or note hold every word of `query` (case aside), in their order; all of them for none.
fn pick_found(choices : Array[Choice], query : String) -> Array[Choice] {
  let words = query.split(" ").filter(fn(w) { !w.is_empty() }).map(fn(w) { w.to_string() }).collect()
  if words.is_empty() {
    return choices
  }
  choices.filter(fn(x) {
    let hay = (x.label + "\n" + x.note).to_lower()
    words.iter().all(fn(w) { hay.contains(w.to_lower()) })
  })
}

// ---------------------------------------------------------------------------
// The web's: a small panel beside what opened it, a dialog in the middle of the window

///|
/// A menu beside what opened it (@sf.dropdown: its arrows, letters, Enter and Escape, a press outside closing it).
fn menu_popover(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  items : Array[MenuItem?],
  title : String,
  along : @ui.Along,
) -> (Bool, Bool) {
  let entries : Array[@kit.Entry] = []
  let icons : Map[String, String] = {}
  let danger : Array[String] = []
  if title != "" {
    entries.push(@kit.menu_label(title))
  }
  for i, x in items {
    match x {
      None => entries.push(@kit.menu_separator())
      Some(item) => {
        let v = i.to_string()
        entries.push(@kit.menu_item(v, label=item.label, disabled=item.disabled))
        if item.icon != "" {
          icons[v] = item.icon
        }
        if item.danger {
          danger.push(v)
        }
      }
    }
  }
  let (trigger, at) = anchor_of(c, p.from)
  let offset = match p.from {
    At(_, _, 0.0, 0.0) => 0.0
    _ => 6.0
  }
  // (it goes at once as the web's does, pop_out: gone as it closes)
  let m = dropdown(c, key, p.open, trigger, entries, icons, menu_w, along~, offset~, at?, danger~)
  match m.chosen {
    Some(v) => {
      let i = v.iter().fold(init=0, fn(n, ch) { n * 10 + (ch.to_int() - 48) })
      match items.get(i) {
        Some(Some(item)) => done_with(c, p, item.select)
        _ => ()
      }
    }
    None => ()
  }
  (m.open && m.chosen is None, p.open)
}

///|
/// A pick beside what opened it (the web's chooser: a small panel, the one chosen in the accent), its search over
/// it when long (Enter picks the first found).
fn pick_popover(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  title : String,
  choices : Array[Choice],
  chosen : String,
  choose : (String) -> Unit,
) -> (Bool, Bool) {
  let (anchor, at) = anchor_of(c, p.from)
  let r = @kit.popover(
    c,
    key,
    p.open,
    anchor,
    along=Start,
    at?,
    label=title,
    modal=true,
    look=fn(c, _, body) { small_panel(c, w=Px(chooser_menu_w), body) |> ignore },
    fn() {
      let found = if choices.length() >= pick_search_from {
        let f = input(c, key + "/search", placeholder=t("common.search"), field=p.line)
        if !p.focused {
          p.focused = true
          c.focus_editor(key + "/search")
        }
        let found = pick_found(choices, line_of(p, f))
        if f.submitted && !found.is_empty() {
          done_with(c, p, fn() { choose(found[0].key) })
        }
        found
      } else {
        choices
      }
      if found.is_empty() {
        c.box(style=panel_empty_at, fn() { c.text(t("common.noMatch"), style=panel_empty) |> ignore }) |> ignore
      }
      c.capped(key + "/list", pick_list_most, fn() {
        for x in found {
          if menu_item(c, x.label, key=key + "/" + x.key, icon=x.icon, on=x.key == chosen, note=x.note, panel=x.icon != "") {
            done_with(c, p, fn() { choose(x.key) })
          }
        }
      })
      |> ignore
    },
  )
  (r.value, p.open)
}

///|
/// A small panel beside what opened it (parts.tsx's: @sf.small_panel, PanelHead).
fn panel_popover(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  w : Double,
) -> (Bool, Bool) {
  let (anchor, at) = anchor_of(c, p.from)
  let r = @kit.popover(
    c,
    key,
    p.open,
    anchor,
    along=Start,
    at?,
    label=title,
    modal=true,
    look=fn(c, _, inner) { small_panel(c, w=Px(w), inner) |> ignore },
    fn() {
      if title != "" {
        panel_head(c, title)
      }
      body(c, fn() { done_with(c, p, fn() {  }) })
    },
  )
  (r.value, p.open)
}

///|
/// A confirm in the middle of the window (parts.tsx Confirm: @sf.confirm_dialog).
fn confirm_centred(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  title : String,
  words : String,
  action : String,
  danger : Bool,
  run : () -> Unit,
) -> (Bool, Bool) {
  let r = confirm_dialog(c, key, p.open, title, words, action, cancel=t("common.cancel"), danger~)
  if r.confirmed {
    done_with(c, p, run)
  }
  (r.open && !r.confirmed, dialog_built(c, key, p.open))
}

///|
/// A question in the middle of the window (parts.tsx Dialog: @sf.dialog, its field @sf.input, the hint under it, the
/// cancel and the action at its foot).
fn ask_centred(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  title : String,
  value : String,
  placeholder : String,
  action : String,
  hint : String,
  secret : Bool,
  run : (String) -> Unit,
) -> (Bool, Bool) {
  let words = Ref(p.line.text().trim(chars=" \t\n").to_string())
  let mut said = false
  let still = dialog(
    c,
    key,
    p.open,
    title,
    fn() {
      let f = input(c, key + "/line", placeholder~, secret~, field=p.line)
      words.val = line_of(p, f).trim(chars=" \t\n").to_string()
      if !p.focused {
        p.focused = true
        c.focus_editor(key + "/line")
      }
      if hint != "" {
        c.text(hint, style=field_hint) |> ignore
      }
      if f.submitted && words.val != "" && words.val != value {
        said = true
      }
    },
    footer=fn() {
      if button(c, t("common.cancel"), key=key + "/cancel", tone=Ghost) {
        close_from_serial(p.serial)
      }
      if button(c, action, key=key + "/go", tone=Primary, disabled=words.val == "" || words.val == value) {
        said = true
      }
    },
  )
  if said {
    let line = words.val
    done_with(c, p, fn() { run(line) })
  }
  (still && !said && p.open, dialog_built(c, key, p.open))
}

///|
/// What is written in `p`'s field: Enter in it (a field's own: it sends and empties it) leaves it as it was, and it is
/// what was written that Enter says.
fn line_of(p : Presented, f : @kit.Field) -> String {
  if f.submitted {
    p.line.set(p.typed)
  } else {
    p.typed = f.text
  }
  p.typed
}

///|
/// Whether a dialog by `key` is still drawn (coming, there, or going: @kit.dialog's presence, its own key).
fn dialog_built(c : @ui.Ctx, key : String, open : Bool) -> Bool {
  @kit.presence(c, key, open).built
}

///|
fn close_from_serial(serial : Int) -> Unit {
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    Some(i) => close_from(i)
    None => ()
  }
}

///|
/// Under a pick's search, when nothing is found (menuEmpty: 13, muted, a row's padding).
// kept across runs: a value (no field of it changes)
let panel_empty_at : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
// kept across runs: a value (no field of it changes)
let panel_empty : @ui.TextStyle = @ui.text_style(size=Sm, leading=L5, color=Muted)

// ---------------------------------------------------------------------------
// The phone's: a sheet from the window's foot (Sheet.kt SheetHost, mbui's @kit.sheet)

///|
/// How much of the window a sheet takes at most (Sheet.kt: 90%), and a long pick's (the run picker's: 66%), a
/// confirm's (36%) and a question's (42%: PageParts.kt confirm, ask).
let sheet_most : Double = 0.9

///|
let sheet_long_pick : Double = 0.66

///|
let sheet_confirm : Double = 0.36

///|
let sheet_ask : Double = 0.42

///|
/// `p` as a sheet: as tall as what it shows (measured as it is laid out), or its share of the window; the scrim (black
/// at 28%) closing it when tapped, back, Escape, its top dragged down. Whether it is open, and whether it is drawn.
fn present_sheet(c : @ui.Ctx, key : String, p : Presented) -> (Bool, Bool) {
  let (_, wh) = c.window_size()
  let share = match p.shows {
    Pick(_, choices, _, _) if choices.length() >= pick_search_from => Some(sheet_long_pick)
    Confirm(_, _, _, _, _) => Some(sheet_confirm)
    Ask(_, _, _, _, _, _, _) => Some(sheet_ask)
    _ => None
  }
  let fit_key = "sf-present/fit/\{p.serial}"
  let h = match (share, @motion.measured(c, fit_key)) {
    (Some(s), _) => s * wh
    (None, Some(m)) => dmin(m, wh * sheet_most)
    // (until it is laid out: half the window)
    (None, None) => wh * 0.5
  }
  let r = @kit.sheet(c, key, p.open, h~, scrim=sheet_scrim, look=sheet_look(), fn() {
    match share {
      Some(_) =>
        c.box(style=sheet_whole, fn() {
          sheet_grab(c)
          sheet_body(c, key, p)
          sheet_foot(c)
        })
        |> ignore
      None => {
        let shown = c.box(style=full_width, fn() {
          sheet_grab(c)
          sheet_body(c, key, p)
          sheet_foot(c)
        })
        @motion.measure(c, shown, fit_key)
      }
    }
  })
  if !r.open && p.open {
    // let go of: a field in it is no longer typed into as it goes down
    c.blur()
  }
  (r.open && p.open, r.shown)
}

///|
/// Under what a sheet shows, the navigation bar's room (Sheet.kt: windowInsetsPadding(navigationBars)).
fn sheet_foot(c : @ui.Ctx) -> Unit {
  let foot = @ui.system_bars().bottom
  if foot > 0.0 {
    c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore
  }
}

///|
/// What a sheet shows of `p`.
fn sheet_body(c : @ui.Ctx, key : String, p : Presented) -> Unit {
  match p.shows {
    Menu(items, title, _) => {
      if title != "" {
        sheet_title(c, title)
      }
      c.box(style=sheet_rows, fn() {
        for i, x in items {
          match x {
            None => c.box(style=sheet_rule, fn() {  }) |> ignore
            Some(item) =>
              if sheet_row(c, key + "/" + i.to_string(), item.label, icon=item.icon, danger=item.danger, disabled=item.disabled) {
                done_with(c, p, item.select)
              }
          }
        }
      })
      |> ignore
    }
    Pick(title, choices, chosen, choose) => {
      sheet_title(c, title)
      let long = choices.length() >= pick_search_from
      let found = if long {
        let mut text = ""
        c.box(style=sheet_search_at, fn() {
          let f = @kit.text_field(
            c,
            key + "/search",
            placeholder=t("common.search"),
            size=text_scale.lg.0,
            line=text_scale.lg.1,
            look=field_look,
            field=p.line,
          )
          text = line_of(p, f)
        })
        |> ignore
        pick_found(choices, text)
      } else {
        choices
      }
      let rows = fn() {
        if found.is_empty() {
          c.box(style=sheet_words_at, fn() { c.text(t("common.noMatch"), style=sheet_lead) |> ignore }) |> ignore
        }
        for x in found {
          if sheet_row(c, key + "/" + x.key, x.label, note=x.note, icon=x.icon, on=x.key == chosen) {
            done_with(c, p, fn() { choose(x.key) })
          }
        }
      }
      if long {
        // the rest of the sheet, scrolling
        c.box(style=sheet_grows, fn() {
          c.capped(key + "/list", wh_of(c), shrinks=true, fn() { c.box(style=sheet_rows, rows) |> ignore }) |> ignore
        })
        |> ignore
      } else {
        c.box(style=sheet_rows, rows) |> ignore
      }
    }
    Panel(title, body, _) => {
      if title != "" {
        sheet_title(c, title)
      }
      c.box(style=sheet_panel, fn() { body(c, fn() { done_with(c, p, fn() {  }) }) }) |> ignore
    }
    Confirm(title, words, action, danger, run) => {
      sheet_title(c, title)
      c.box(style=sheet_words_at, fn() {
        c.text(words, style=sheet_lead) |> ignore
        c.box(style=sheet_actions, fn() {
          if button(c, t("common.cancel"), key=key + "/cancel") {
            close_from_serial(p.serial)
          }
          if button(c, action, key=key + "/go", tone=if danger { DangerSolid } else { Primary }) {
            done_with(c, p, run)
          }
        })
        |> ignore
      })
      |> ignore
    }
    Ask(title, value, placeholder, action, hint, secret, run) => {
      sheet_title(c, title)
      c.box(style=sheet_words_at, fn() {
        let f = @kit.text_field(
          c,
          key + "/line",
          placeholder~,
          secret~,
          size=text_scale.lg.0,
          line=text_scale.lg.1,
          look=field_look,
          field=p.line,
        )
        if !p.focused {
          p.focused = true
          c.focus_editor(key + "/line")
        }
        let words = line_of(p, f).trim(chars=" \t\n").to_string()
        if hint != "" {
          c.text(hint, style=sheet_hint) |> ignore
        }
        let can = words != "" && words != value
        c.box(style=sheet_actions, fn() {
          if button(c, t("common.cancel"), key=key + "/cancel") {
            close_from_serial(p.serial)
          }
          if button(c, action, key=key + "/go", tone=Primary, disabled=!can) || (can && f.submitted) {
            done_with(c, p, fn() { run(words) })
          }
        })
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// The window's height (what a long pick's list is capped by before the sheet's room shrinks it).
fn wh_of(c : @ui.Ctx) -> Double {
  c.window_size().1
}

///|
/// A sheet's title (Sheet.kt SheetHead): 17 bold, 18 in, 4 over and 10 under.
fn sheet_title(c : @ui.Ctx, title : String) -> Unit {
  c.box(style=sheet_title_row, fn() { c.text(title, style=sheet_title_words) |> ignore }) |> ignore
}

///|
/// A row of a sheet (NewChat.kt pickStation's, Sheet.kt's menu rows): its icon, its words (15), the note under them
/// (12, muted), a check in the accent on the one chosen (`on`); in red when `danger`, quiet when `disabled`; the
/// ripple under the finger. Whether it was tapped.
fn sheet_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  note? : String = "",
  icon? : String = "",
  on? : Bool = false,
  danger? : Bool = false,
  disabled? : Bool = false,
) -> Bool {
  let th = theme()
  let id = c.id(key)
  let ink = if disabled {
    th.p.subtle
  } else if danger {
    th.p.red
  } else {
    th.p.text
  }
  c.box(style=sheet_row_box, id=if disabled { 0 } else { id }, fn() {
    if icon != "" {
      draw_icon(c, icon, sheet_row_icon, if danger { ink } else { th.p.muted })
    }
    c.box(style=sheet_row_words_at, fn() {
      c.text(label, style=sheet_row_words.then(@ui.text_style(color=Data(ink)))) |> ignore
      if note != "" {
        c.text(note, style=sheet_row_note) |> ignore
      }
    })
    |> ignore
    if on {
      draw_icon(c, "check", sheet_row_check, th.p.accent)
    }
    if !disabled {
      @motion.ripple(c, id, row_corner)
    }
  })
  |> ignore
  !disabled && c.clicked(id)
}

///|
/// A sheet's row's icon (22: NewChat.kt's station's) and its check (14).
let sheet_row_icon : Double = 22.0

///|
let sheet_row_check : Double = 14.0

///|
/// What a sheet of a share shows: all of it, a column.
// kept across runs: a value (no field of it changes)
let sheet_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The room left in a sheet of a share (a long pick's list).
// kept across runs: a value (no field of it changes)
let sheet_grows : @ui.Style = @ui.style(w=Full, h=grow)

///|
// kept across runs: a value (no field of it changes)
let sheet_title_row : @ui.Style = @ui.css("row w=Full px=S4_5 pt=S1 pb=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sheet_title_words : @ui.TextStyle = @ui.text_style(size=Xl2, weight=Bold, color=Fg, wrap=false)

///|
/// A sheet's rows: 12 in at its sides, 24 under the last.
// kept across runs: a value (no field of it changes)
let sheet_rows : @ui.Style = @ui.css("w=Full px=S3 pb=S6")

///|
/// A line between a sheet's rows (a menu's None): the line's colour, 8 in from the rows' ground, 4 over and under.
// kept across runs: a value (no field of it changes)
let sheet_rule : @ui.Style = @ui.style(w=Full, h=hairline, mx=S2, my=S1, bg=Line)

///|
/// A row: 8 by 12 in, 12 between its icon, its words and its check, rounded as a list's row.
// kept across runs: a value (no field of it changes)
let sheet_row_box : @ui.Style = @ui.css("row w=Full px=S2 py=S3 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let sheet_row_words_at : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let sheet_row_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sheet_row_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted)

///|
/// A long pick's search: 20 in, 10 under.
// kept across runs: a value (no field of it changes)
let sheet_search_at : @ui.Style = @ui.css("w=Full px=S5 pb=S2_5")

///|
/// What a panel holds in a sheet: its rows' 12 in, 24 under.
// kept across runs: a value (no field of it changes)
let sheet_panel : @ui.Style = @ui.css("w=Full px=S3 pb=S6 gap=S2_5")

///|
/// A confirm's and a question's words (PageParts.kt confirm, ask): 20 in, 10 apart.
// kept across runs: a value (no field of it changes)
let sheet_words_at : @ui.Style = @ui.css("w=Full px=S5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sheet_lead : @ui.TextStyle = @ui.text_style(size=Base, leading=L6, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let sheet_hint : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted)

///|
/// Its buttons at its end: 6 over, 24 under, 8 apart.
// kept across runs: a value (no field of it changes)
let sheet_actions : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")
