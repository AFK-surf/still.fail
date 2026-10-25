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
  /// a small panel, or with nothing that opened it a dialog (PanelOf)
  Panel(PanelOf)
  /// a confirm: its title, what it does, its action, whether that cannot be undone, what goes on once it is said
  Confirm(String, String, String, Bool, () -> Unit)
  /// a question: its title, the line at first, its placeholder, its action, the hint under it, whether a secret, what
  /// goes on with the line (trimmed)
  Ask(String, String, String, String, String, Bool, (String) -> Unit)
}

///|
/// A panel: its title ("" none), what it is about ("" nothing), what it holds and what is at its foot (each given
/// what closes it), how wide beside what opened it, whether a wide dialog; its title, its step's count and what it
/// is about as they are now (a wizard's), over those given.
priv struct PanelOf {
  title : String
  description : String
  body : (@ui.Ctx, () -> Unit) -> Unit
  foot : ((@ui.Ctx, () -> Unit) -> Unit)?
  w : Double
  wide : Bool
  live : (() -> (String, String, String))?
  tall : Double
  grows : Bool
  focus : Bool
  ruled : Bool
  lists : Bool
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
  mut focused : Bool
  /// what is let go of as it closes unsaid (back, Escape, a press outside, its close button), and whether it closed
  /// so or was said
  gone : () -> Unit
  mut ended : Bool
  /// as a sheet, found taller than a sheet's most: that tall from then on, what it holds scrolling in it
  mut over : Bool
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
/// Whether the host draws over nothing of the app's this frame (presented's `alone`).
// kept across runs: said by the host each frame; put back by presenters_reset (parts_reset)
let presented_alone : Ref[Bool] = Ref(false)

///|
/// How each one open was drawn in the last frame, the lowest first.
// kept across runs: put back by presenters_reset (parts_reset)
let presented_how : Array[How] = []

///|
/// Nothing presented (the app begun again).
pub fn presenters_reset() -> Unit {
  presented_now.clear()
  presented_count.val = 0
  presented_alone.val = false
  presented_how.clear()
}

///|
fn present(shows : Shows, from : Anchor, line? : String = "", gone? : () -> Unit = fn() {  }) -> Unit {
  presented_count.val += 1
  presented_now.push({
    serial: presented_count.val,
    shows,
    from,
    open: true,
    line: @ui.Field::new(text=line),
    focused: false,
    gone,
    ended: false,
    over: false,
  })
}

///|
/// A menu of `items` (None: a line between; parts.tsx Menu), opened by `from`: chosen, it closes and the item's
/// `select` goes on. `title` over them ("" none); `along`: how it lines up with what opened it beside it.
pub fn menu(items : Array[MenuItem?], from~ : Anchor, title? : String = "", along? : @ui.Along = Start) -> Unit {
  present(Menu(items, title, along), from)
}

///|
/// A link's menu (`href`), opened by `from`: open it (a web address's), copy it, each going on with `open` or `copy`.
/// Its words the screen's: touch's the phone's (Links.kt), keyboard and mouse's its context menu's.
pub fn link_menu(href : String, from~ : Anchor, open : () -> Unit, copy : () -> Unit) -> Unit {
  let touch = native_input() is Finger
  let items : Array[MenuItem?] = []
  if href.has_prefix("https://") || href.has_prefix("http://") {
    items.push(
      Some(menu_item_of(t(if touch { "common.link.open" } else { "desktop.contextMenu.openLink" }), open, icon="external")),
    )
  }
  items.push(Some(menu_item_of(t(if touch { "common.link.copy" } else { "desktop.contextMenu.copyLink" }), copy, icon="copy")))
  menu(items, from~)
}

///|
/// A pick of one of `choices` (`chosen` the one now), titled `title` ("" none), opened by `from`: chosen, it closes and `choose`
/// goes on with its key. Longer than pick_search_from, a line to search them by is over them.
pub fn pick(title : String, choices : Array[Choice], chosen : String, choose : (String) -> Unit, from~ : Anchor) -> Unit {
  present(Pick(title, choices, chosen, choose), from)
}

///|
/// A small panel (parts.tsx PanelHead and its rows, fields) titled `title` ("" none), opened by `from`: `body` draws
/// what it holds each frame, given what closes it. `w`: how wide beside what opened it. Opened by nothing
/// (Unanchored), a dialog in the middle of the window (parts.tsx Dialog: `description` under its title, `foot`'s
/// buttons at its foot, given what closes it, `wide` 640 wide in place of 520; `live`: its title, its step's count and
/// what it is about as they are now, a wizard's). `gone`: what is let go of as it closes unsaid (back, Escape, a press
/// outside, its close button), not by what `close` was given to. `tall`: what it holds fills the room it is given, this
/// share of the window (as a sheet that tall, beside what opened it at most that tall; 0: as tall as what it holds);
/// `grows`: a long list's, a sheet of it is dragged between half and nearly all of the window. Not `focus`: beside what
/// opened it, the focus stays where it is as it opens, not on its first field (Radix's onOpenAutoFocus prevented: the
/// web's page sizes). `ruled`: its foot under a line across the panel, out to its sides (a panel of columns, the run
/// picker's: kept, 2026-10-25 用户「这两个的分割线可以保留，第一个分割线边上不要留空」), over the foot where what it holds
/// scrolls. `lists`: what it holds scrolls in lists of its own (panel_column), what is beside them staying in view: a
/// sheet of it held to its most gives it the room it has, its lists scrolling in that, not all of it as one (the run
/// picker's models: what goes with the one picked beside them).
pub fn panel(
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  from~ : Anchor,
  w? : Double = panel_w,
  description? : String = "",
  foot? : (@ui.Ctx, () -> Unit) -> Unit,
  wide? : Bool = false,
  live? : () -> (String, String, String),
  gone? : () -> Unit = fn() {  },
  tall? : Double = 0.0,
  grows? : Bool = false,
  focus? : Bool = true,
  ruled? : Bool = false,
  lists? : Bool = false,
) -> Unit {
  present(Panel({ title, description, body, foot, w, wide, live, tall, grows, focus, ruled, lists }), from, gone~)
}

///|
/// What reaches a panel's sides on purpose (a strip that scrolls under them, attach's photos): out across the room
/// the panel leaves at its sides where it is drawn (beside what opened it small_panel's pad, in a sheet as far as its
/// rows are in), what it holds laying out its own sides. All else in a panel stands in that room by itself.
pub fn panel_bleed() -> @ui.Style {
  @ui.style(mx=room(-panel_sides_in.val))
}

///|
/// The room a panel leaves at its sides while its body is drawn (the presenters set it): what panel_bleed reaches across,
/// and what a row's ground reaches out across, its words on the column's line (choice_row).
let panel_sides_in : Ref[Double] = { val: 0.0 }

///|
/// Whether the panel whose body is drawn now is held shorter than what it holds (beside what opened it, to the room on
/// its side; a sheet, to its most), its body scrolling in it as one: what would scroll in itself there (a list held to
/// a height of its own) lays itself out whole instead, so that one scroll, not one in another, takes the wheel.
pub fn panel_held() -> Bool {
  panel_held_now.val
}

///|
// kept across runs: said by the presenters while a panel's body is drawn
let panel_held_now : Ref[Bool] = { val: false }

///|
/// How far under what a ruled panel holds (`panel`'s `ruled`) the line over its foot is, while its body is drawn (0
/// where it has none): for a line of its own going down to meet it (a column's line beside another).
pub fn panel_rule_over() -> Double {
  rule_over_now.val
}

///|
// kept across runs: said by the presenters while a panel's body is drawn
let rule_over_now : Ref[Double] = { val: 0.0 }

///|
/// A column of a panel's body in a column of `style`, its rows `body`, scrolling by itself: beside what opened it past
/// `most` (the web's run picker's models, 360 high at most); in a sheet past the room the sheet gives it (as tall as
/// all of it while the sheet has the room for that, the sheet as tall as what it holds; the sheet at its most, the
/// room left in it: a panel of `lists`), what is beside it staying in view; all of it where the panel scrolls as one
/// (a small panel held short of what it holds: panel_held), never one scroll in another.
pub fn panel_column(c : @ui.Ctx, key : String, most : Double, style : @ui.Style, body : () -> Unit) -> Unit {
  if panel_held_now.val {
    c.box(style~, body) |> ignore
  } else {
    // (in a sheet as tall as all of it while the sheet has the room, scrolling by itself in what the sheet gives it once
    // it is held to its most: a panel of `lists`)
    let most = if small_panel_now.val { most } else { wh_of(c) }
    c.capped(key, most, shrinks=true, fn() { c.box(style~, body) |> ignore }) |> ignore
  }
}

///|
/// A sheet's column of its own (a sheet a page lays out itself: the settings' adding people, joining a station): what
/// it holds as far in from its sides as a sheet's words are (sheet_panel_sides), its rows' grounds reaching out across
/// that room, their words on the column's line, as in a sheet the presenters lay out.
pub fn sheet_column(c : @ui.Ctx, body : () -> Unit) -> Unit {
  let (was, rows_were) = (panel_sides_in.val, rows_out.val)
  panel_sides_in.val = sheet_panel_sides
  rows_out.val = sheet_panel_sides
  c.box(style=sheet_column_box, body) |> ignore
  panel_sides_in.val = was
  rows_out.val = rows_were
}

///|
// kept across runs: a value (no field of it changes)
let sheet_column_box : @ui.Style = @ui.css("w=Full px=S5")

///|
/// How far a row's ground reaches out of the column it stands in, its words on the column's line: as far as its own
/// words are in from its ground (`own`), no further than the room the panel leaves at its sides (none outside a panel;
/// none beside what opened it, where the panel's padding is where its rows' grounds stand: rows_out).
fn row_reach(own : Double) -> Double {
  dmin(rows_out.val, own)
}

///|
/// What the small panel beside what opened it that is drawn now was given by its popover (the side it went on, the
/// room there), for what it holds to keep within (@kit.in_room).
// kept across runs: said by the presenters' looks as each is drawn, before what it holds
let beside_given : Ref[@kit.PopState] = { val: { side: Bottom, room: 1.0e9, panel: 0 } }

///|
/// The room at a panel's sides its rows' grounds reach out across while its body is drawn: a sheet's (its column's
/// sides), none in a small panel (its rows at its padding, as a menu's are).
let rows_out : Ref[Double] = { val: 0.0 }

///|
/// Whether the panel whose body is drawn now is a small panel beside what opened it (a popover's): its rows stand as
/// a menu's do, at its padding, their words a row's padding in (text_in), concentric with it.
pub fn in_small_panel() -> Bool {
  small_panel_now.val
}

///|
// kept across runs: said by the presenters while a panel's body is drawn
let small_panel_now : Ref[Bool] = { val: false }

///|
/// How far in from the column a panel's body stands in its words go (each block of them, a row's), so they stand on
/// the panel's words' line wherever it is drawn: a row's padding in a small panel (its column at its padding: text_in),
/// what a sheet's rows leave of its words' 20 in a sheet a press opened (sheet_held: its column at its rows'), none
/// where the column is at the words' line already (a sheet opened by nothing) or outside a panel.
pub fn panel_words_in() -> @ui.Style {
  @ui.style(px=room(words_in_now.val))
}

///|
/// A row of a panel's body, its words so (panel_words_in), concentric with a small panel where it is in one; one to
/// press (a box with an id), its ground under the hand (parts.css.ts panelRow: a button's :hover).
pub fn panel_row_in() -> @ui.Style {
  if small_panel_now.val {
    small_panel_row_in
  } else {
    panel_words_in().then(panel_row_lit)
  }
}

///|
// kept across runs: a value (no field of it changes)
let small_panel_row_in : @ui.Style = @ui.style(px=room(text_in), radius=Inner, hovered=@ui.patch(bg=Hover))

///|
// kept across runs: a value (no field of it changes)
let panel_row_lit : @ui.Style = @ui.css("hovered{bg=Hover}")

///|
// kept across runs: said by the presenters while a panel's body is drawn
let words_in_now : Ref[Double] = { val: 0.0 }

///|
/// The one presented last (what `close_presented_of` is given to close it).
pub fn last_presented() -> Int {
  presented_count.val
}

///|
/// Closes the one presented as `serial` (last_presented), and what is over it, as back does; nothing when it is gone
/// or going (closed already: what was opened over it since is not its).
pub fn close_presented_of(serial : Int) -> Unit {
  close_from_serial(serial)
}

///|
/// Whether anything presented is still drawn (open, or going).
pub fn presented_drawn() -> Bool {
  !presented_now.is_empty()
}

///|
/// Whether the one presented as `serial` is open (not going, nor gone).
pub fn presented_open_of(serial : Int) -> Bool {
  presented_now.iter().any(fn(p) { p.serial == serial && p.open })
}

///|
/// Whether the one presented as `serial` is still drawn (open, or going).
pub fn presented_drawn_of(serial : Int) -> Bool {
  presented_now.iter().any(fn(p) { p.serial == serial })
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
/// Words asked of a thing that can take them where it is (a row's title renamed): with touch asked over the
/// page as `ask` does (the keyboard rising over the list would cover the row), with keyboard and mouse where it is: `here` makes
/// the thing its own field (Rename.tsx TitleInput), which says the words itself.
pub fn ask_here(
  title : String,
  action : String,
  run : (String) -> Unit,
  here : () -> Unit,
  value? : String = "",
  placeholder? : String = "",
  hint? : String = "",
) -> Unit {
  if native_input() is Finger {
    ask(title, action, run, value~, placeholder~, hint~)
  } else {
    here()
  }
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
/// `alone`: nothing of the app's is under it (a share over another app): a sheet on the page's paper, not frosted.
pub fn presented(c : @ui.Ctx, alone? : Bool = false) -> Unit {
  presented_alone.val = alone
  presented_how.clear()
  let (ww, _) = c.window_size()
  // a sheet with touch short of the Large tier, the web's otherwise (docs/architecture.md): by the screen, never
  // the hand
  let sheet = (native_input() is Finger) && layout(ww) != Large
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
    // closed by the hand as it was drawn (back, Escape, a press outside, dragged down): it and what is over it go (one
    // closed by the app meanwhile, and what is over it then, went as it was closed: what was opened since stays)
    if p.open && !open {
      close_from(i)
    }
    // closed unsaid: what it holds let go of, once
    if !p.open && !p.ended {
      p.ended = true
      c.tell("sf-present/gone/\{p.serial}", p.gone)
    }
    if was && open {
      presented_how.push(how_of(p.shows, p.from, sheet))
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
fn how_of(shows : Shows, from : Anchor, sheet : Bool) -> How {
  match (sheet, shows) {
    (true, _) => AsSheet
    (false, Panel(_)) if from == Unanchored => AsDialog
    (false, Menu(_, _, _) | Pick(_, _, _, _) | Panel(_)) => AsPopover
    (false, Confirm(_, _, _, _, _) | Ask(_, _, _, _, _, _, _)) => AsDialog
  }
}

///|
/// `p` drawn as a sheet or as the web's: whether it is open now, and whether it is drawn at all (still going).
fn draw_presented(c : @ui.Ctx, p : Presented, sheet : Bool) -> (Bool, Bool) {
  // what it holds laid out as its kind is: a sheet's as a narrow page's, the web's as a wide one's (page.mbt)
  let mut drawn = (false, false)
  with_look(if sheet { Narrow } else { Wide }, fn() { drawn = draw_presented_as(c, p, sheet) })
  drawn
}

///|
fn draw_presented_as(c : @ui.Ctx, p : Presented, sheet : Bool) -> (Bool, Bool) {
  let key = "sf-present"
  if sheet {
    return present_sheet(c, key, p)
  }
  match p.shows {
    Menu(items, title, along) => menu_popover(c, key, p, items, title, along)
    Pick(title, choices, chosen, choose) => pick_popover(c, key, p, title, choices, chosen, choose)
    Panel(x) if p.from == Unanchored => panel_centred(c, key, p, x)
    Panel(x) => panel_popover(c, key, p, x)
    Confirm(title, words, action, danger, run) => confirm_centred(c, key, p, title, words, action, danger, run)
    Ask(title, value, placeholder, action, hint, secret, run) =>
      ask_centred(c, key, p, title, value, placeholder, action, hint, secret, run)
  }
}

///|
/// What chosen or said in `p` does, once the frame is built: `p` closes (and what is over it), then `f` goes on.
fn done_with(c : @ui.Ctx, p : Presented, f : () -> Unit) -> Unit {
  p.ended = true
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
        entries.push(
          match item.chosen {
            Some(on) => @kit.menu_radio(v, on, label=item.label, disabled=item.disabled)
            None => @kit.menu_item(v, label=item.label, disabled=item.disabled)
          },
        )
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
  // (it goes at once as the web's does, @kit.pop_out: gone as it closes)
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
  // short: a menu of choices (controls.css.ts chooserMenu: the one chosen checked before its words, the arrows,
  // letters and Enter a menu's), a choice's note at its end
  if choices.length() < pick_search_from {
    // (its title over the choices, as a menu's is)
    let entries : Array[@kit.Entry] = if title != "" { [@kit.menu_label(title)] } else { [] }
    for x in choices {
      entries.push(@kit.menu_radio(x.key, x.key == chosen, label=x.label))
    }
    let icons : Map[String, String] = {}
    let notes : Map[String, String] = {}
    for x in choices {
      if x.icon != "" {
        icons[x.key] = x.icon
      }
      if x.note != "" {
        notes[x.key] = x.note
      }
    }
    let offset = match p.from {
      At(_, _, 0.0, 0.0) => 0.0
      _ => 6.0
    }
    let m = dropdown(c, key, p.open, anchor, entries, icons, chooser_menu_w, offset~, at?, row_end=fn(c, s) {
      match notes.get(s.entry.value) {
        Some(n) => c.text(n, style=pick_note) |> ignore
        None => ()
      }
    })
    match m.chosen {
      Some(k) => done_with(c, p, fn() { choose(k) })
      None => ()
    }
    return (m.open && m.chosen is None, p.open)
  }
  let r = @kit.popover(
    c,
    key,
    p.open,
    anchor,
    along=Start,
    at?,
    label=title,
    modal=true,
    look=fn(c, s, body) {
      beside_given.val = s
      small_panel(c, w=Px(chooser_menu_w), body) |> ignore
    },
    fn() {
      let found = {
        let f = input(c, key + "/search", placeholder=t("common.search"), small=true, field=p.line)
        focus_once(c, p, key + "/search")
        let found = pick_found(choices, f.text)
        if f.submitted && !found.is_empty() {
          done_with(c, p, fn() { choose(found[0].key) })
        }
        found
      }
      if found.is_empty() {
        c.box(style=panel_empty_at, fn() { c.text(t("common.noMatch"), style=panel_empty) |> ignore }) |> ignore
      }
      // (scrolling past pick_list_most, or what the room it has leaves it)
      @kit.in_room(c, beside_given.val, key=key + "/list", most=pick_list_most, fn() {
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
/// A small panel beside what opened it (parts.tsx's: @sf.small_panel, PanelHead), what is at its foot in its foot
/// corner (panel_corner_foot); as tall as `tall` of the window, what it holds takes what the foot leaves. Within the
/// window (@kit.in_room: flipped, else moved over what opened it, it is made shorter only past the window's height),
/// what it holds then scrolling between its title and its foot.
fn panel_popover(c : @ui.Ctx, key : String, p : Presented, x : PanelOf) -> (Bool, Bool) {
  let (anchor, at) = anchor_of(c, p.from)
  let close = fn() { done_with(c, p, fn() {  }) }
  let r = @kit.popover(
    c,
    key,
    p.open,
    anchor,
    along=Start,
    at?,
    label=x.title,
    modal=true,
    focus=x.focus,
    look=fn(c, s, inner) {
      beside_given.val = s
      // (a share of the window no taller than the room it has)
      let h : @ui.Size = if x.tall > 0.0 { Px(dmin(x.tall * wh_of(c), s.room)) } else { Auto }
      small_panel(c, w=Px(x.w), h~, inner) |> ignore
    },
    fn() {
      if x.title != "" {
        panel_head(c, x.title)
      }
      // (small_panel's pad round it: what reaches its sides on purpose goes out past that, panel_bleed; its rows stand
      // at it)
      panel_sides_in.val = panel_pad
      small_panel_now.val = true
      words_in_now.val = text_in
      rule_over_now.val = if x.ruled && x.foot is Some(_) { panel_pad } else { 0.0 }
      if x.tall > 0.0 {
        c.box(style=panel_grows, fn() { (x.body)(c, close) }) |> ignore
      } else {
        // (scrolling, where it does, out to the panel's sides, what it holds as far in as without: what reaches them
        // still does; told so as it is drawn, panel_held)
        let k = key + "/panel"
        panel_held_now.val = @kit.held_in_room(c, beside_given.val, key=k)
        @kit.in_room(c, beside_given.val, key=k, reach=held_reach(), style=held_in(), fn() { (x.body)(c, close) }) |> ignore
        panel_held_now.val = false
      }
      panel_sides_in.val = 0.0
      small_panel_now.val = false
      words_in_now.val = 0.0
      rule_over_now.val = 0.0
      match x.foot {
        Some(f) => {
          if x.ruled {
            // (out past small_panel's pad to its sides, as far under what it holds as its rows are in from them)
            c.box(style=foot_rule.then(@ui.style(mx=room(-panel_pad), mt=room(panel_pad))), fn() {  }) |> ignore
          }
          // (its buttons as far under the line over them as over the panel's foot, where they stand in its corner)
          let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
          c.box(style=panel_foot_at.then(at), fn() { f(c, close) }) |> ignore
        }
        None => ()
      }
    },
  )
  (r.value, p.open)
}

///|
/// A panel opened by nothing, in the middle of the window (parts.tsx Dialog: @sf.dialog, its close button).
fn panel_centred(c : @ui.Ctx, key : String, p : Presented, x : PanelOf) -> (Bool, Bool) {
  let close = fn() { done_with(c, p, fn() {  }) }
  let (title, step, description) = match x.live {
    Some(f) => f()
    None => (x.title, "", x.description)
  }
  let still = dialog(
    c,
    key,
    p.open,
    title,
    fn() {
      // (the dialog's padding round what it holds: what reaches its sides on purpose goes out across it, panel_bleed;
      // its rows' grounds stand at it, concentric with its corner as the last is with its foot's, their words a row's
      // padding in, and its words that are not a row's as far in, panel_words_in, as a small panel's)
      let (was, words_were) = (panel_sides_in.val, words_in_now.val)
      panel_sides_in.val = dialog_pad
      words_in_now.val = card_pad - corner_inset
      // a tall one's body fills its share of the window (what it holds lays itself out in the room it is given)
      if x.tall > 0.0 {
        let room = x.tall * wh_of(c)
        c.box(style=@ui.style(w=Full, h=Fixed(room)), fn() { (x.body)(c, close) }) |> ignore
      } else {
        (x.body)(c, close)
      }
      panel_sides_in.val = was
      words_in_now.val = words_were
    },
    description~,
    footer?=match x.foot {
      Some(f) => Some(fn() { f(c, close) })
      None => None
    },
    wide=x.wide,
    close_label=t("common.close"),
    step~,
  )
  (still && p.open, dialog_built(c, key, p.open))
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
      words.val = f.text.trim(chars=" \t\n").to_string()
      focus_once(c, p, key + "/line")
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
/// `p`'s field (`key`'s editor) given the keyboard's focus as it opens, until it has it once (what it opened over
/// letting go of the focus as it goes, a frame later, does not take it away); after that the person's. Closed, the
/// field lets go of it (the keyboard goes down as `p` goes).
fn focus_once(c : @ui.Ctx, p : Presented, key : String) -> Unit {
  if let_go(c, p, key) {
    return
  }
  if p.focused {
    return
  }
  if c.has_focus(c.id(key)) {
    p.focused = true
  } else {
    c.focus_editor(key)
  }
}

///|
/// `p` closed: its field (`key`'s editor) lets go of the keyboard's focus if it has it. Whether it is closed.
fn let_go(c : @ui.Ctx, p : Presented, key : String) -> Bool {
  if p.open {
    return false
  }
  if c.has_focus(c.id(key)) {
    c.blur()
  }
  true
}

///|
/// Whether a dialog by `key` is still drawn (coming or there: @kit.dialog_drawn).
fn dialog_built(c : @ui.Ctx, key : String, open : Bool) -> Bool {
  @kit.dialog_drawn(c, key, open)
}

///|
fn close_from_serial(serial : Int) -> Unit {
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    // (one closed already, going: what was opened over it since is not its, as one opened as it went)
    Some(i) if presented_now[i].open => close_from(i)
    _ => ()
  }
}

///|
/// Under a pick's search, when nothing is found (menuEmpty: 13, muted, a row's padding).
// kept across runs: a value (no field of it changes)
let panel_empty_at : @ui.Style = @ui.css("w=Full px=S2_5 py=S2")

///|
/// A choice's note at its row's end in a menu of choices (13, muted).
// kept across runs: a value (no field of it changes)
let pick_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let panel_empty : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

// ---------------------------------------------------------------------------
// The phone's: a sheet from the window's foot (Sheet.kt SheetHost, mbui's @kit.sheet)

///|
/// How much of the window a sheet takes at most: nearly all of it, up to just under the status bar (Sheet.kt's
/// largest detent), what it holds past that scrolling in it; and a long pick's (the run picker's: 66%), a confirm's
/// (36%) and a question's (42%: PageParts.kt confirm, ask).
pub let sheet_most : Double = 0.94

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
  // what it holds, as tall as this frame lays it out (read back: laid out another height, the frame is built again),
  // so the sheet is as tall as that in the frame it shows, and with it as it changes: placed by its size, not chased
  // to the size the frame before measured (docs/motion.md)
  let fit = c.id("sf-present/fit/\{p.serial}")
  let natural = match c.laid_size(fit) {
    Some((_, h)) => Some(h)
    None => None
  }
  // a panel taller than a sheet's most: the sheet that tall from then on, what it holds scrolling in it (as a dialog's
  // body does), its foot in reach
  if natural is Some(m) && m > wh * sheet_most {
    p.over = true
  }
  let over = p.over
  let share = match p.shows {
    Pick(_, choices, _, _) if choices.length() >= pick_search_from => Some(sheet_long_pick)
    Confirm(_, _, _, _, _) => Some(sheet_confirm)
    Ask(_, _, _, _, _, _, _) => Some(sheet_ask)
    Panel(x) if x.tall > 0.0 => Some(x.tall)
    Panel(_) if over => Some(sheet_most)
    _ => None
  }
  let grows = match p.shows {
    Panel(x) => x.grows
    _ => false
  }
  let h = match (share, natural) {
    (Some(s), _) => s * wh
    (None, Some(m)) => dmin(m, wh * sheet_most)
    // (before what it holds is first laid out: built again at once, as tall as it is)
    (None, None) => wh * 0.5
  }
  let look = if presented_alone.val { sheet_look(ground=theme().p.bg) } else { sheet_look() }
  let r = @kit.sheet(c, key, p.open, h~, detents=if grows { sheet_grows_to } else { [] }, scrim=sheet_scrim, look~, fn() {
    match share {
      Some(_) =>
        c.box(style=sheet_whole, fn() {
          sheet_grab(c)
          sheet_body(c, key, p, scrolls=over)
          sheet_foot(c)
        })
        |> ignore
      None =>
        // (named to be read back, not to be pressed: a tap goes to what is in it)
        c.box(style=full_width, id=fit, taps=false, fn() {
          sheet_grab(c)
          sheet_body(c, key, p)
          sheet_foot(c)
        })
        |> ignore
    }
  })
  // what it comes to, for scripted runs (e2e: a sheet opened and closed by dragging)
  match r.dragged {
    Some(DraggedClosed) => @hostapi.log("SHEET dragged closed")
    Some(DraggedBack) => @hostapi.log("SHEET dragged back")
    Some(DraggedTo(f)) => @hostapi.log(if f > 0.72 { "SHEET dragged to 94%" } else { "SHEET dragged to 55%" })
    None => ()
  }
  (r.open && p.open, r.shown)
}

///|
/// Where a long list's sheet settles as it is dragged (Sheet.kt SheetHost: half, and nearly all of the window).
// kept across runs: a table, never written
let sheet_grows_to : Array[Double] = [0.55, sheet_most]

///|
/// Under what a sheet shows, the navigation bar's room (Sheet.kt: windowInsetsPadding(navigationBars)).
fn sheet_foot(c : @ui.Ctx) -> Unit {
  let foot = @ui.system_bars().bottom
  if foot > 0.0 {
    c.box(style=@ui.style(w=Full, h=Fixed(foot)), fn() {  }) |> ignore
  }
}

///|
/// What a sheet shows of `p` (`scrolls`: a panel's body scrolling in the room left it, its foot under it in reach).
fn sheet_body(c : @ui.Ctx, key : String, p : Presented, scrolls? : Bool = false) -> Unit {
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
              if sheet_row(
                  c,
                  key + "/" + i.to_string(),
                  item.label,
                  icon=item.icon,
                  on=item.chosen == Some(true),
                  danger=item.danger,
                  disabled=item.disabled,
                ) {
                done_with(c, p, item.select)
              }
          }
        }
      })
      |> ignore
    }
    Pick(title, choices, chosen, choose) => {
      if title != "" {
        sheet_title(c, title)
      }
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
          let_go(c, p, key + "/search") |> ignore
          text = f.text
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
    Panel(x) => {
      let close = fn() { done_with(c, p, fn() {  }) }
      let (title, _, description) = match x.live {
        Some(f) => f()
        None => (x.title, "", x.description)
      }
      if title != "" {
        sheet_title(c, title)
      }
      if description != "" {
        c.box(style=sheet_words_at, fn() { c.text(description, style=sheet_lead) |> ignore }) |> ignore
      }
      // what it holds in from the sheet's sides as its words are, opened by nothing (a form, a question); one opened
      // by a press as far in as a pick's rows are, as small_panel's pad has it beside what opened it (what reaches
      // the sides on purpose says so: panel_bleed); one filling a share lays out its own; the sheet's foot under it
      // unless its buttons are (sheet_foot_at): the sheet's, as a panel's padding beside what opened it is the
      // panel's, not what it holds
      let pressed = p.from != Unanchored
      let room = if x.tall > 0.0 {
        sheet_grows
      } else if pressed {
        if x.foot is None {
          sheet_held
        } else {
          sheet_held_sides
        }
      } else {
        sheet_panel
      }
      let body = fn() {
        // (filling its share, it lays out its own sides)
        panel_sides_in.val = if x.tall > 0.0 { 0.0 } else if pressed { sheet_row_sides } else { sheet_panel_sides }
        rows_out.val = panel_sides_in.val
        words_in_now.val = if x.tall <= 0.0 && pressed { sheet_panel_sides - sheet_row_sides } else { 0.0 }
        rule_over_now.val = if x.ruled && x.foot is Some(_) { sheet_rule_over } else { 0.0 }
        (x.body)(c, close)
        panel_sides_in.val = 0.0
        rows_out.val = 0.0
        words_in_now.val = 0.0
        rule_over_now.val = 0.0
      }
      if scrolls && x.tall <= 0.0 && x.lists {
        // (its own lists scroll in the room the sheet has: what it holds fills it)
        c.box(style=sheet_grows, fn() { c.box(style=room.then(sheet_fills), body) |> ignore }) |> ignore
      } else if scrolls && x.tall <= 0.0 {
        c.box(style=sheet_grows, fn() {
          c.capped(key + "/panel", wh_of(c), shrinks=true, fn() {
            panel_held_now.val = true
            c.box(style=room, body) |> ignore
            panel_held_now.val = false
          })
          |> ignore
        })
        |> ignore
      } else {
        c.box(style=room, body) |> ignore
      }
      match x.foot {
        Some(f) => {
          if x.ruled {
            c.box(style=sheet_foot_rule, fn() {  }) |> ignore
          }
          c.box(style=sheet_foot_at, fn() {
            // its buttons across it, each its share (in a thumb's reach)
            foot_fills.val = true
            f(c, close)
            foot_fills.val = false
          })
          |> ignore
        }
        None => ()
      }
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
        focus_once(c, p, key + "/line")
        let words = f.text.trim(chars=" \t\n").to_string()
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
  // (a list's item on this screen: Theme.items, as a folder's entries are)
  c.box(style=sheet_row_box.then(@ui.style(min_h=Fixed(th.items.least))), id=if disabled { 0 } else { id }, fn() {
    if icon != "" {
      draw_icon(c, icon, th.items.mark, if danger { ink } else { th.p.muted })
    }
    c.box(style=sheet_row_words_at, fn() {
      c.text(label, style=th.items.name.then(sheet_row_words).then(@ui.text_style(color=Data(ink)))) |> ignore
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
/// A sheet's row's check (14).
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
let sheet_title_words : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Fg, wrap=false)

///|
/// A sheet's rows: 12 in at its sides, 24 under the last.
// kept across runs: a value (no field of it changes)
let sheet_rows : @ui.Style = @ui.css("w=Full px=S3 pb=S6")

///|
/// How far in from a sheet's sides its rows are (sheet_rows' px).
let sheet_row_sides : Double = 12.0

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
let sheet_row_words : @ui.TextStyle = @ui.text_style(wrap=false)

///|
// kept across runs: a value (no field of it changes)
let sheet_row_note : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// A long pick's search: 20 in, 10 under.
// kept across runs: a value (no field of it changes)
let sheet_search_at : @ui.Style = @ui.css("w=Full px=S5 pb=S2_5")

///|
/// What a panel holds in a sheet: 20 in from its sides as the phone's sheets' words are (PageParts.kt confirm, ask;
/// Composer.kt askToShare), 24 under.
// kept across runs: a value (no field of it changes)
let sheet_panel : @ui.Style = @ui.css("w=Full px=S5 pb=S6 gap=S2_5")

///|
/// What a panel opened by a press holds in a sheet: as far in as a pick's rows (sheet_rows), 24 under.
// kept across runs: a value (no field of it changes)
let sheet_held : @ui.Style = @ui.css("w=Full px=S3 pb=S6")

///|
/// The same with a foot under it (the foot's room under it, not its own).
// kept across runs: a value (no field of it changes)
let sheet_held_sides : @ui.Style = @ui.css("w=Full px=S3")

///|
/// How far in from a sheet's sides what a panel opened by nothing holds is (sheet_panel's px).
let sheet_panel_sides : Double = 20.0

///|
/// A confirm's and a question's words (PageParts.kt confirm, ask): 20 in, 10 apart.
// kept across runs: a value (no field of it changes)
let sheet_words_at : @ui.Style = @ui.css("w=Full px=S5 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let sheet_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let sheet_hint : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted)

///|
/// A panel's buttons in a sheet (its foot): 20 in, as far under what is over them (the line over a run picker's foot,
/// a form's last field) as over the sheet's foot, 24, across it (each its share: parts.mbt foot_fills), 8 apart.
// kept across runs: a value (no field of it changes)
let sheet_foot_at : @ui.Style = @ui.css("row w=Full px=S5 pt=S6 pb=S6 gap=S2 justify=JEnd")

///|
/// What a panel of `lists` holds in a sheet held to its most: all the room left in it.
// kept across runs: a value (no field of it changes)
let sheet_fills : @ui.Style = @ui.css("h=Full")

///|
/// The line over a ruled panel's foot (`panel`'s `ruled`), across the panel.
// kept across runs: a value (no field of it changes)
let foot_rule : @ui.Style = @ui.css("w=Full h=SPx bg=Line")

///|
/// The same in a sheet: as far under what it holds as its rows are in from its sides (sheet_held_sides: 12).
// kept across runs: a value (no field of it changes)
let sheet_foot_rule : @ui.Style = @ui.style(w=Full, h=SPx, mt=room(sheet_rule_over), bg=Line)

///|
let sheet_rule_over : Double = 12.0

///|
/// A small panel's foot (beside what opened it): a row, its buttons at its end, 8 apart, 8 under what is over them;
/// what it holds over it, as tall as the panel is made, the rest.
// kept across runs: a value (no field of it changes)
let panel_foot_at : @ui.Style = @ui.css("row w=Full pt=S2 gap=S2 align=ACenter justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let panel_grows : @ui.Style = @ui.style(w=Full, h=grow)

///|
/// Its buttons at its end: 6 over, 24 under, 8 apart.
// kept across runs: a value (no field of it changes)
let sheet_actions : @ui.Style = @ui.css("row w=Full pt=S1_5 pb=S6 gap=S2 justify=JEnd")
