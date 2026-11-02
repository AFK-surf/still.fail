// The presenters (docs/architecture.md, Presenters): a menu, a pick (one of a list, searched when long), a small panel,
// a confirm and a question with a line to write. A page says what it shows and what opened it, once, as it is pressed;
// the presenter decides how, by the screen alone (docs/architecture.md, rule 3: the steps one after another near each
// other): on Small (@sf.layout) a sheet from the window's foot (the phone's: its grabber, dragged down or back to
// close); on Medium and Large, with either hand, the web's, a small panel beside what opened it (a menu, a pick, a
// panel) or a dialog in the middle of the window (a confirm, a question). One host draws them all over
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
/// What opened a menu or a pick, which stand beside it on Medium and Large (docs/architecture.md, rule 3: the steps one
/// after another near each other): the box pressed (its id) or a rectangle of the window (a right click's point). Never
/// nothing: no page can open one beside nothing, as a dialog in the middle of the window.
pub(all) enum Beside {
  Of(Int)
  At(Double, Double, Double, Double)
} derive(Eq)

///|
/// What opened it, as the presenters keep it.
pub fn Beside::anchor(self : Beside) -> Anchor {
  match self {
    Of(id) => Anchor::Of(id)
    At(x, y, w, h) => Anchor::At(x, y, w, h)
  }
}

///|
/// The point (`x`, `y`) of the window as what opened a presenter (a right click's).
pub fn at_point(x : Double, y : Double) -> Beside {
  At(x, y, 0.0, 0.0)
}

///|
/// One to pick (`pick`): what it is known by, its words, what it is (`note`: a sentence, a line under its words), what
/// it is at now (`value`: a word or two, a state, a count, at its row's end on its line), its icon (by name), or its
/// mark (`mark`: what marks it elsewhere, drawn as large as the row's mark column says: a station's, a maker's). A page
/// says which each is; the presenter lays each out as what it is, on every screen.
pub(all) struct Choice {
  key : String
  label : String
  note : String
  value : String
  icon : String
  mark : ((@ui.Ctx, Double) -> Unit)?
}

///|
pub fn choice(
  key : String,
  label : String,
  note? : String = "",
  value? : String = "",
  icon? : String = "",
  mark? : (@ui.Ctx, Double) -> Unit,
) -> Choice {
  { key, label, note, value, icon, mark }
}

///|
/// What a presenter shows.
priv enum Shows {
  /// a menu: its items (None a line between), its title ("" none), where a small panel lines up with what opened it
  Menu(Array[MenuItem?], String, @ui.Along)
  /// a pick: its title, the choices, the one chosen now, what choosing one does; whether a long one has a line to
  /// search them by
  Pick(String, Array[Choice], String, (String) -> Unit, @ui.Along, Bool)
  /// a small panel, or with nothing that opened it a dialog (PanelOf)
  Panel(PanelOf)
  /// a confirm: its title, what it does, its action, whether that cannot be undone, what goes on once it is said
  Confirm(String, String, String, Bool, () -> Unit)
  /// a question: its title, the line at first, its placeholder, its action, the hint under it, whether a secret,
  /// whether an empty line can be said, what goes on with the line (trimmed)
  Ask(String, String, String, String, String, Bool, Bool, (String) -> Unit)
}

///|
/// A panel: its title ("" none), what it is about ("" nothing), what it holds and what is at its foot (each given
/// what closes it), how wide beside what opened it (or at most, where it `fits` what it holds), whether a wide dialog;
/// its title, its step's count and what it is about as they are now (a wizard's), over those given.
priv struct PanelOf {
  title : String
  description : String
  body : (@ui.Ctx, () -> Unit) -> Unit
  foot : ((@ui.Ctx, () -> Unit) -> Unit)?
  w : Double
  fits : Bool
  wide : Bool
  live : (() -> (String, String, String))?
  tall : Double
  grows : Bool
  focus : Bool
  ruled : Bool
  lists : Bool
  /// fade the panel and its contents together as it leaves
  fade_out_together : Bool
  form : Bool
  /// the field given the keyboard's focus as it opens where it is not a sheet ("" none: panel's `field`)
  field : String
  /// a picture shown alone over the window, its buttons under it (panel's `stage`)
  stage : Bool
  /// on a stage, what is chosen of the picture between it and its buttons (panel's `above`)
  above : ((@ui.Ctx) -> Unit)?
  /// beside what opened it, what stands at its head's end, beside its title (panel's `head_end`)
  head_end : ((@ui.Ctx) -> Unit)?
  /// beside what opened it: on which side of it, along it where, how far from it (panel's `side`, `along`, `offset`)
  side : @ui.Side
  along : @ui.Along
  offset : Double
  /// what it holds goes in steps in it (panel's `steps`: panel_go, panel_back)
  steps : Bool
  /// what back does on its first step where its steps follow a flow kept elsewhere (panel's `back`: panel_go's)
  on_back : (() -> Unit)?
}

///|
/// A step of a panel that goes in steps (panel_go): its title, what it is about ("" nothing), what it holds and what is
/// at its foot (each given what closes the panel), what is let go of as it is left for good (gone back from, or the
/// panel closed: what it holds with it); `n` its count in the panel (0 the panel's own, the first); `count`, beside its
/// title, which of a flow's steps it is ("" none: a wizard's 2 / 4); `on_back`, what back does on it where the steps
/// follow a flow kept elsewhere (the core's wizard: told to go back, the panel going back a step as it does), in place
/// of taking it off.
priv struct PanelStep {
  n : Int
  title : String
  description : String
  body : (@ui.Ctx, () -> Unit) -> Unit
  foot : ((@ui.Ctx, () -> Unit) -> Unit)?
  left : () -> Unit
  count : String
  on_back : (() -> Unit)?
  /// its title, count and what it is about as they are now, where they change while it shows (a wizard's)
  live : (() -> (String, String, String))?
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
  /// beside what opened it as wide as what it holds (`fits`): the widest it has been laid out, never narrower from then
  /// on
  mut widest : Double
  /// a panel that goes in steps (`steps`): its steps, the first its own (a stack's: each slides in over the one before,
  /// and back, its back key, Escape and the system's back take it off), how many it has gone to, how tall what shows
  /// is (as the step on top is laid out, going there with the slide as it comes or goes: `step_h_of` the step it is
  /// that tall for; -1 none yet)
  steps : @ui.Nav[PanelStep]?
  mut steps_made : Int
  step_h : @motion.Anim
  mut step_h_of : Int
  /// as a sheet: how tall it is drawn (its sheet's height, as present_sheet works it out), how far it has gone up out
  /// of the way of a sheet over it (0 … 1 of `pushed`: @kit.sheet's `raised`), whether one is, and how far up that takes it
  sheet_h : @signals.Signal[Double]
  recede : @motion.Anim
  mut receded : Bool
  pushed : @signals.Signal[Double]
  /// as a sheet closing, how far it sinks at least: as far as every sheet closing with it, sinking as one with them
  mut sinks : Double
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
/// Told as one is presented or let go: the host (presented) built again for it, wherever it was asked from.
// kept across runs: only counts on
let presented_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// Which are drawn (open, or going), by their serials: told each as it comes or is gone (presented_drawn_of).
// kept across runs: put back by presenters_reset
let presented_drawn_said : @signals.Keyed[Int] = @signals.keyed()

///|
fn presented_told() -> Unit {
  presented_said.set(@signals.untracked(fn() { presented_said.get() }) + 1)
}

///|
/// What one presented shows changed where it is kept (a menu's items given anew as they are now): the host told.
pub fn presented_changed() -> Unit {
  presented_told()
}

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
  tree_presented.clear()
  presented_drawn_said.set([])
  lists_of.clear()
  presented_count.val = 0
  presented_alone.val = false
  presented_how.clear()
}

///|
fn present(shows : Shows, from : Anchor, line? : String = "", gone? : () -> Unit = fn() {  }) -> Unit {
  presented_count.val += 1
  // (a panel that goes in steps: its own the first of them)
  let steps = match shows {
    Panel(x) if x.steps =>
      Some(
        @ui.Nav::new(
          {
            n: 0,
            title: x.title,
            description: x.description,
            body: x.body,
            foot: x.foot,
            left: fn() {  },
            count: "",
            on_back: x.on_back,
            live: x.live,
          },
          on_leave=fn(s) { (s.left)() },
        ),
      )
    _ => None
  }
  // (what is presented written whole, then told as one change: what reads it as it is told finds it there)
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
    widest: 0.0,
    steps,
    steps_made: 0,
    step_h: @motion.Anim::new(0.0),
    step_h_of: -1,
    sheet_h: @signals.signal(0.0),
    recede: @motion.Anim::new(0.0),
    receded: false,
    pushed: @signals.signal(0.0),
    sinks: 0.0,
  })
  @signals.start_batch()
  presented_told()
  presented_drawn_said.set(presented_now.map(fn(p) { p.serial }))
  @signals.end_batch()
}

///|
/// A menu of `items` (None: a line between; parts.tsx Menu), opened by `from`: chosen, it closes and the item's
/// `select` goes on. `title` over them ("" none); `along`: how it lines up with what opened it beside it. `gone`: what
/// is let go of as it closes with nothing chosen (back, Escape, a press outside).
pub fn menu(
  items : Array[MenuItem?],
  from~ : Beside,
  title? : String = "",
  along? : @ui.Along = Start,
  gone? : () -> Unit = fn() {  },
) -> Unit {
  present(Menu(items, title, along), from.anchor(), gone~)
}

///|
/// A link's menu (`href`), opened by `from`: open it (a web address's), copy it, each going on with `open` or `copy`.
/// Its words the screen's: touch's the phone's (Links.kt), keyboard and mouse's its context menu's.
pub fn link_menu(href : String, from~ : Beside, open : () -> Unit, copy : () -> Unit) -> Unit {
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
/// goes on with its key. Longer than pick_search_from, a line to search them by is over them, unless not `search`
/// (a few steps of a number: nothing to look for, and no keyboard up for it).
pub fn pick(
  title : String,
  choices : Array[Choice],
  chosen : String,
  choose : (String) -> Unit,
  from~ : Beside,
  along? : @ui.Along = Start,
  search? : Bool = true,
) -> Unit {
  present(Pick(title, choices, chosen, choose, along, search), from.anchor())
}

///|
/// A small panel (parts.tsx PanelHead and its rows, fields) titled `title` ("" none), opened by `from`: `body` draws
/// what it holds each frame, given what closes it. `w`: how wide beside what opened it; `fits`: as wide there as what
/// it holds, `w` at most (columns of choices, the run picker's: no wider than its words). Opened by nothing
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
/// picker's models: what goes with the one picked beside them). `form`: what is filled in and said (its fields, its
/// own buttons to say it: the web's AddStationDialog, adding people), a dialog in the middle whatever opened it (a sheet
/// with touch short of Large), as the web's are; what is only chosen from or looked at (a pick, a card) stands beside
/// what opened it. `field`: the editor (by its key) given the keyboard's focus as it opens, where the keyboard is at hand
/// (a dialog's, beside what opened it), not in a sheet (a phone's keyboard raised over what it shows): typed into at
/// once with keyboard and mouse, looked at first with touch. `stage`: a picture to hand out shown alone, on every screen
/// the same (stage_centred): no panel round it, the window under it the night (stage_scrim), what it holds in the
/// middle drawn as large as the window lets it (whole_fitted), 关闭 and its `foot`'s buttons under it on the night;
/// a press beside it, Escape and the back close it too; `above`, over those buttons, what is chosen of the picture (the
/// card to share's looks). `side`, `along`, `offset`: where it stands beside what opened it (under it by default, its
/// start at the start of it); what opens from a bar down the window's side (the rail) stands beside the bar, out of
/// it, as everything opened from there does. `head_end`: beside what opened it, what stands at the end of its head's
/// line, beside its title (the model panel's search: a sheet, its head the sheet's own, leaves it to what it holds).
/// `fade_out_together`: its ground and contents leave as one instead of the usual staged fade; what is behind it may
/// show through while it goes (the model picker, 2026-11-02).
pub fn panel(
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  from~ : Anchor,
  w? : Double = panel_w,
  fits? : Bool = false,
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
  fade_out_together? : Bool = false,
  form? : Bool = false,
  field? : String = "",
  stage? : Bool = false,
  above? : (@ui.Ctx) -> Unit,
  head_end? : (@ui.Ctx) -> Unit,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = panel_offset,
  steps? : Bool = false,
  back? : () -> Unit,
) -> Unit {
  present(
    Panel({
      title,
      description,
      body,
      foot,
      w,
      fits,
      wide,
      live,
      tall,
      grows,
      focus,
      ruled,
      lists,
      fade_out_together,
      form,
      field,
      stage,
      above,
      head_end,
      side,
      along,
      offset,
      steps,
      on_back: back,
    }),
    from,
    gone~,
  )
}

///|
/// In a panel that goes in steps (panel's `steps`), as what it shows is drawn or pressed: a step in, in the same panel,
/// titled `title` (`description` under it), what it holds `body` and what is at its foot `foot` (each given what closes
/// the panel): it slides in over the step it is in, the panel as tall as it from then on, going there as it comes; its
/// head a back key at its start. Back (that key, Escape, the system's back, its left edge swiped) takes it off, back to
/// the step before; from the first, back closes the panel. A press outside, the sheet dragged down, its close button:
/// the panel closes, all its steps with it. `left`: what is let go of as it is left for good (gone back from, or the
/// panel closed), once. `count`: which of a flow's steps it is, beside its title. `back`: where the steps follow a
/// flow kept elsewhere (the core's wizard), what back does on it in place of taking it off (told to that flow, which
/// sends the panel back a step as it goes: panel_back). `live`: its title, count and what it is about as they are now,
/// where they change while it shows.
pub fn panel_go(
  title : String,
  body : (@ui.Ctx, () -> Unit) -> Unit,
  description? : String = "",
  foot? : (@ui.Ctx, () -> Unit) -> Unit,
  left? : () -> Unit = fn() {  },
  count? : String = "",
  back? : () -> Unit,
  live? : () -> (String, String, String),
) -> Unit {
  match stepping() {
    Some(p) =>
      match p.steps {
        Some(nav) => {
          p.steps_made += 1
          nav.push({ n: p.steps_made, title, description, body, foot, left, count, on_back: back, live })
        }
        None => ()
      }
    None => ()
  }
}

///|
/// In a panel that goes in steps, as what it shows is drawn or pressed: back to the step before (its back key's), or to
/// the step `to` deep (1 the first: a step's work done, back where it began), the one on top sliding away over it.
/// Whether there was one to go back to.
pub fn panel_back(to? : Int) -> Bool {
  match stepping() {
    Some({ steps: Some(nav), .. }) =>
      match to {
        Some(d) => nav.pop_to(d)
        None => nav.pop()
      }
    _ => false
  }
}

///|
/// How many steps in the panel that goes in steps being drawn is (1: its own, the first); 0 in none.
pub fn panel_depth() -> Int {
  match stepping() {
    Some({ steps: Some(nav), .. }) => nav.depth()
    _ => 0
  }
}

///|
/// The panel that goes in steps a step is told to (panel_go, panel_back): the one whose step is being drawn, or the
/// topmost open one that goes in steps (what was pressed in it told between frames).
fn stepping() -> Presented? {
  let serial = steps_drawn_now.val
  for i = presented_now.length() - 1; i >= 0; i = i - 1 {
    let p = presented_now[i]
    if p.steps is Some(_) && (p.serial == serial || (serial == 0 && p.open)) {
      return Some(p)
    }
  }
  None
}

///|
/// The serial of the panel whose step is being drawn (0 none).
// kept across runs: said round each step drawn, 0 between
let steps_drawn_now : Ref[Int] = Ref(0)

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
/// A panel's body drawn (its `body` given what closes it), saying meanwhile that what is drawn is a panel's (in_panel).
fn draw_panel_body(x : PanelOf, c : @ui.Ctx, close : () -> Unit, keyed? : Presented) -> Unit {
  panel_body_now.val += 1
  (x.body)(c, close)
  panel_body_now.val -= 1
  // (its field given the focus as it opens, where it is `keyed`: a dialog, beside what opened it, not a sheet)
  match keyed {
    Some(p) if x.field != "" => focus_once(c, p, x.field)
    _ => ()
  }
}

///|
/// Whether what is drawn now is a panel's body (the presenters', in whatever way it shows): what lays itself out as a
/// page's (a page's column in the window, the room over and under it the frame leaves) lays itself out in the panel's
/// room instead.
pub fn in_panel() -> Bool {
  panel_body_now.val > 0
}

///|
// kept across runs: counted up and down round what a panel's body draws (0 between them)
let panel_body_now : Ref[Int] = Ref(0)

///|
/// While the body of a panel a share of the window caps (`tall`) is drawn: whether its lists say what they hold, and
/// what they said (each its box, as tall as its rows laid end to end).
// kept across runs: said by measured_body round a capped panel's body
let lists_said_now : Ref[Bool] = { val: false }

///|
// kept across runs: said by panel_list as it is drawn in a capped panel's body
let lists_now : Array[(Int, Double)] = []

///|
/// A capped panel's lists as its body was last drawn, by the presented's serial: each its box and what it holds.
// kept across runs: said by measured_body, let go of by presenters_reset
let lists_of : Map[Int, Array[(Int, Double)]] = {}

///|
/// A capped panel's body (filling its share: `style`), its lists saying what they hold as it is drawn.
fn measured_body(c : @ui.Ctx, serial : Int, id : Int, style : @ui.Style, body : () -> Unit) -> Unit {
  let (said_was, were) = (lists_said_now.val, lists_now.copy())
  lists_said_now.val = true
  lists_now.clear()
  c.box(style~, id~, body) |> ignore
  lists_of[serial] = lists_now.copy()
  lists_now.clear()
  lists_now.append(were)
  lists_said_now.val = said_was
}

///|
/// How tall a capped panel's body would be, its lists as tall as what they hold (none: no list in it says, it fills
/// its share): what else it held as the last layout had it, and its lists' rows laid end to end.
fn capped_want(c : @ui.Ctx, serial : Int, id : Int) -> Double? {
  let lists = lists_of.get(serial).unwrap_or([])
  guard lists.length() > 0 else { return None }
  guard c.laid_size(id) is Some((_, body)) else { return None }
  let mut laid = 0.0
  let mut holds = 0.0
  for l in lists {
    match c.laid_size(l.0) {
      Some((_, h)) => laid = laid + h
      None => ()
    }
    holds = holds + l.1
  }
  Some(dmax(body - laid, 0.0) + holds)
}

///|
/// A long list in a panel's body (its rows laid out as they come into view: `Ctx::list`), its rows drawn as the panel
/// has what it holds (its sides, its words' line, its rows' reach): they are drawn after the panel's body has said it.
/// The list spans the room the panel leaves its rows to reach across (rows_out: a list clips what it holds to itself),
/// its rows' words that much further in from its edge, so a row's ground reaches the panel's sides as it does outside
/// a list. `stick_end`: it starts at its end and stays there as rows come (Ctx::list's). `fills`: in a panel a share of
/// the window caps, it says not what it holds, the panel its share whatever it holds (one gone about in, a folder after
/// another, each holding more or less: not a sheet growing and shrinking at each step).
pub fn panel_list(
  c : @ui.Ctx,
  key : String,
  count : Int,
  est : Double,
  row : (Int) -> Unit,
  stick_end? : Bool = false,
  fills? : Bool = false,
) -> Int {
  let (sides, out, words, body, small) = (
    panel_sides_in.val,
    rows_out.val,
    words_in_now.val,
    panel_body_now.val,
    small_panel_now.val,
  )
  let mut list = 0
  // in a panel a share of the window caps: what it holds said, its rows laid end to end (those built at their height,
  // the rest at `est`: none laid out to be measured), for the panel to be as tall as that up to its share
  // (measured_body); it fills the room it is given
  let room_id = c.id(key + "/room")
  if lists_said_now.val && !fills {
    let holds = match c.list_info_as(key, fn(i) { i.map(fn(x) { x.content }) }) {
      Some(i) => i.content
      None => est * count.to_double()
    }
    lists_now.push((room_id, holds))
  }
  c.box(style=sheet_grows.then(@ui.style(mx=room(-out))), id=room_id, taps=false, fn() {
    list = c.list(key, count, est, stick_end~, fn(i) {
      let was = (panel_sides_in.val, rows_out.val, words_in_now.val, panel_body_now.val, small_panel_now.val)
      panel_sides_in.val = sides - out
      rows_out.val = 0.0
      words_in_now.val = words + out
      panel_body_now.val = body
      small_panel_now.val = small
      row(i)
      panel_sides_in.val = was.0
      rows_out.val = was.1
      words_in_now.val = was.2
      panel_body_now.val = was.3
      small_panel_now.val = was.4
    })
  })
  |> ignore
  list
}

///|
/// What a panel's body holds that is seen whole, never scrolled through nor cut: a picture to share (sfpages'
/// stations_now.mbt), laid out `most` wide (the room's width where that is less) by `draw` (given the id its box takes,
/// answering the box: Ctx::box's node) and shown as large as the room the panel gives it lets it, never larger than it
/// is, at the top of that room in its middle. In a panel a share of the window caps (`tall`) it says how tall it is, as
/// a list says its rows (measured_body), so the panel is as tall as all of it while the window has the room and no
/// taller; past that it is drawn smaller (a look over its layout: what it is laid out as stays as it is, its words in
/// their places). Put where it is in the room out of its flow, so the room is as large as the panel gives it, not as
/// what it holds (which would hold it as large as the picture, never smaller). On a stage (a panel's `stage`), laid out
/// `most` wide whatever the stage's (as what is handed out is: one picture everywhere), drawn smaller where the stage
/// leaves it less (stage_room), its room as large as it is drawn, in the stage's middle. `id`: a box over it as large
/// as it is drawn.
pub fn whole_fitted(c : @ui.Ctx, key : String, id : Int, most : Double, draw : (Int) -> Int) -> Unit {
  let room_id = c.id(key + "/room")
  let whole_id = c.id(key + "/whole")
  let h = match c.laid_size(whole_id) {
    Some((_, h)) => h
    None => 0.0
  }
  // the room and how much smaller it is drawn: on a stage (stage_room) laid out `most` wide whatever the stage's (as
  // it is handed out: the same picture on every screen), drawn smaller where the stage has not its width or its
  // height, the room as large as it is drawn; else the room the panel gives it, laid out as wide as that up to `most`,
  // drawn smaller where it has not its height
  let (room, room_w, w, k) = match stage_room.val {
    Some((sw, sh)) => {
      let k = dmin(1.0, dmin(sw / most, if h > 0.0 { sh / h } else { 1.0 }))
      let drawn_h = if h > 0.0 { h * k } else { sh }
      (@ui.style(w=Fixed(most * k), h=Fixed(drawn_h)), most * k, most, k)
    }
    None => {
      let (rw, rh) = c.laid_size(room_id).unwrap_or((most, 0.0))
      (whole_room, rw, dmin(most, rw), if h > 0.0 && rh > 0.0 { dmin(1.0, rh / h) } else { 1.0 })
    }
  }
  if lists_said_now.val && h > 0.0 {
    lists_now.push((room_id, h))
  }
  c.box(style=room, id=room_id, taps=false, fn() {
    // (as wide as it is laid out, in the room's middle, drawn smaller from its top's middle)
    let at = c.box(style=whole_box.then(@ui.style(w=Fixed(w))), left=(room_w - w) / 2.0, top=0.0, taps=false, fn() {
      draw(whole_id) |> ignore
    })
    c.look(at, @ui.look(scale=k, ox=0.5, oy=0.0))
    // (over it, as large as it is drawn)
    c.box(style=whole_box.then(@ui.style(w=Fixed(w * k), h=Fixed(h * k))), id~, left=(room_w - w * k) / 2.0, top=0.0, fn() {  })
    |> ignore
  })
  |> ignore
}

///|
/// The room a stage gives what it shows (stage_centred), while it is drawn: as wide and as tall as that may be.
// kept across runs: set only while a stage's body is built, and put back
let stage_room : Ref[(Double, Double)?] = Ref(None)

///|
/// The room a fitted picture is given: what the panel leaves.
// kept across runs: a value (no field of it changes)
let whole_room : @ui.Style = @ui.style(w=Full, h=grow)

///|
// kept across runs: a value (no field of it changes)
let whole_box : @ui.Style = @ui.css("")

///|
/// Whether the panel whose body is drawn now is as tall as what it holds (a dialog: its body scrolls in itself), so
/// what would scroll in a room of its own (a page's list) lays itself out whole instead.
pub fn panel_whole() -> Bool {
  panel_whole_now.val > 0
}

///|
// kept across runs: counted up and down round what a dialog's body draws (0 between them)
let panel_whole_now : Ref[Int] = Ref(0)

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
/// `most` (the web's run picker's models, 360 high at most), and as tall as the row it stands in where that is taller
/// (a column beside it taller: what it holds runs as far down as that one, not stopping at `most` over empty room); in
/// a sheet past the room the sheet gives it (as tall as all of it while the sheet has the room for that, the sheet as
/// tall as what it holds; the sheet at its most, the room left in it: a panel of `lists`), what is beside it staying
/// in view; all of it where the panel scrolls as one (a small panel held short of what it holds: panel_held), never
/// one scroll in another.
pub fn panel_column(c : @ui.Ctx, key : String, most : Double, style : @ui.Style, body : () -> Unit) -> Unit {
  if panel_held_now.val {
    c.box(style~, body) |> ignore
  } else if small_panel_now.val {
    // (asking its row for `most` at most, stretched by it past that: Ctx::capped `past_most`, in a row of its own that
    // takes all of the column it stands in)
    c.box(style=column_past_most, fn() { c.capped(key, most, past_most=true, fn() { c.box(style~, body) |> ignore }) |> ignore })
    |> ignore
  } else {
    // (in a sheet as tall as all of it while the sheet has the room, scrolling by itself in what the sheet gives it once
    // it is held to its most: a panel of `lists`)
    c.capped(key, wh_of(c), shrinks=true, fn() { c.box(style~, body) |> ignore }) |> ignore
  }
}

///|
/// panel_column's row beside what opened it: across its column and down all of it.
// kept across runs: a value (no field of it changes)
let column_past_most : @ui.Style = @ui.style(row=true, w=Full, h=grow)

///|
/// A sheet's column of its own (a sheet a page lays out itself: the settings' adding people, joining a station): what
/// it holds as far in from its sides as a sheet's words are (sheet_panel_sides), its rows' grounds reaching out across
/// that room, their words on the column's line, as in a sheet the presenters lay out.
pub fn sheet_column(c : @ui.Ctx, body : () -> Unit) -> Unit {
  // (in a panel that stands what it holds in such a column already, a dialog's: in it as it is)
  if column_given.val {
    body()
    return
  }
  let (was, rows_were, words_were) = (panel_sides_in.val, rows_out.val, words_in_now.val)
  // (in a panel that says its words' line, that far in: a dialog's; else a sheet's; its rows reaching out across it)
  let sides = if words_in_now.val > 0.0 { words_in_now.val } else { sheet_panel_sides }
  panel_sides_in.val = sides
  rows_out.val = sides
  words_in_now.val = 0.0
  c.box(style=sheet_column_box.then(@ui.style(px=room(sides))), body) |> ignore
  panel_sides_in.val = was
  rows_out.val = rows_were
  words_in_now.val = words_were
}

///|
// kept across runs: a value (no field of it changes)
let sheet_column_box : @ui.Style = @ui.css("w=Full")

///|
/// Whether what is drawn now stands in a column on its panel's words' line already (a dialog's body: panel_centred),
/// so a sheet's column in it is that one.
// kept across runs: said by panel_centred round what a dialog holds
let column_given : Ref[Bool] = { val: false }

///|
/// How far in from its padding the column a dialog's body stands in is (its words' line: panel_centred), 0 elsewhere:
/// what reaches out to the dialog's sides and corners from it reaches across this too (dialog_rows, dialog_foot_rows).
// kept across runs: said by panel_centred round what a dialog holds
let column_in_now : Ref[Double] = { val: 0.0 }

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
/// Whether the panel whose body is drawn now stands above what opened it: a small panel gone up from it (asked to, or
/// flipped there for want of room below), or a sheet risen from the screen's foot. What a panel keeps nearest what
/// opened it is at its foot then, else at its top.
pub fn panel_opens_up() -> Bool {
  !small_panel_now.val || beside_given.val.side is Top
}

///|
/// How far in from the column a panel's body stands in its words go (each block of them, a row's), so they stand on
/// the panel's words' line wherever it is drawn: a row's padding in a small panel (its column at its padding: text_in),
/// what a sheet's rows leave of its words' 20 in a sheet a press opened (sheet_held: its column at its rows'), none
/// where the column is at the words' line already (a sheet opened by nothing) or outside a panel.
pub fn panel_words_in() -> @ui.Style {
  @ui.style(px=room(words_in_now.val))
}

///|
/// Something standing `by` out of a panel's words' line at its start (a round button whose mark is on the line): its
/// margin the line less `by`.
pub fn panel_words_out_by(by : Double) -> @ui.Style {
  @ui.style(ml=room(words_in_now.val - by))
}

///|
/// A row to press that a page lays out itself in a panel's body: its ground out across the room the panel leaves at its
/// sides (rows_out: a dialog's column), its words on the panel's words' line (as row_line has the library's rows).
pub fn panel_row_reach() -> @ui.Style {
  let out = rows_out.val
  @ui.style(mx=room(-out), px=room(out + words_in_now.val))
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
  // (read so: what reads it built again as it is presented or gone, not as others are)
  presented_drawn_said.has(serial) |> ignore
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
/// differ from `value` (Enter too); `empty`: an empty line too, where that says something (`hint` says what: a name
/// cleared to be given again). Said, it closes and `run` goes on with the line, trimmed.
pub fn ask(
  title : String,
  action : String,
  run : (String) -> Unit,
  value? : String = "",
  placeholder? : String = "",
  hint? : String = "",
  secret? : Bool = false,
  empty? : Bool = false,
  from? : Anchor = Unanchored,
) -> Unit {
  present(Ask(title, value, placeholder, action, hint, secret, empty, run), from, line=value)
}

///|
/// Whether a question's line can be said (ask): words other than it had at first, or none where `empty` lets it.
fn ask_can(words : String, value : String, empty : Bool) -> Bool {
  (words != "" || empty) && words != value
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
  // (read: what asks is built again as one is presented or let go)
  presented_said.get() |> ignore
  presented_now.iter().any(fn(p) { p.open })
}

///|
/// Whether a presenter still occupies the screen, including its declared exit transition.
pub fn presenter_visible() -> Bool {
  presented_said.get() |> ignore
  !presented_now.is_empty()
}

///|
/// Closes everything presented, each going as it goes (a page opened from a link over all of it).
pub fn close_all_presented() -> Unit {
  close_from(0)
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
  // (what is closed written first, then told once: what reads it finds it whole)
  for k in i..<presented_now.length() {
    presented_now[k].open = false
  }
  presented_told()
}

///|
/// The one presented as `serial` dismissed by the hand at that moment (back, Escape, a press outside it: its layer told so,
/// @ui.Ctx::with_dismissed): where it is open still, it closes, and what is over it, and what it holds is let go of, once,
/// then; its view draws it going from the next frame on.
fn dismissed_now(serial : Int) -> Unit {
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    Some(i) if presented_now[i].open => {
      // (it and what is over it, each closed unsaid let go of once, from the top)
      let closing = presented_now[i:].to_array().filter(fn(q) { q.open && !q.ended }).rev()
      close_from(i)
      for q in closing {
        q.ended = true
        (q.gone)()
      }
    }
    _ => ()
  }
}

///|
/// Which one presented dims what is under it (its serial; 0 none): one scrim however many are over one another (the
/// person's 2026-11-02: no darker for each). The lowest of those that dim (a sheet; a dialog in the middle, not a
/// stage, whose night is its own) open now, so what is over it is no darker and, it closed under one still open, the
/// one over it dims at once as it goes; none open, the lowest still drawn as it goes, its scrim fading with it. Read
/// as one is presented, closed or let go (`sheet`: whether they are drawn as sheets, the window Small).
fn scrim_owner(sheet : Bool) -> Int {
  presented_said.get() |> ignore
  let dims = fn(p : Presented) {
    match p.shows {
      Panel(x) if x.stage => false
      _ => how_of(p.shows, p.from, sheet) != AsPopover
    }
  }
  for p in presented_now {
    if p.open && dims(p) {
      return p.serial
    }
  }
  for p in presented_now {
    // (still drawn: told as it is let go)
    if dims(p) && presented_drawn_said.has(p.serial) {
      return p.serial
    }
  }
  0
}

///|
/// Whether the one presented as `serial` is a dialog with another open over it (it takes nothing then: dimmed over
/// itself, dialog_veil), read as one is presented or closed.
fn dialog_covered(serial : Int) -> Bool {
  presented_said.get() |> ignore
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    Some(i) =>
      presented_now[i].open &&
      presented_now[i + 1:].iter().any(fn(q) { q.open && how_of(q.shows, q.from, false) == AsDialog })
    None => false
  }
}

///|
/// What `p` dims what is under it with, where it is not the one that does (scrim_owner): nothing; where it is, the
/// theme's (None).
fn scrim_of(p : Presented, sheet : Bool) -> Int64? {
  if scrim_owner(sheet) == p.serial {
    None
  } else {
    Some(0L)
  }
}

///|
/// The dimming over a sheet pushed up under another (present_sheet): all of it.
// kept across runs: a value (no field of it changes)
let sheet_veil_at : @ui.Style = @ui.css("w=Full h=Full")

///|
/// How far apart a sheet pushed up and the sheet over it that pushed it stand (the scrim between them).
let pushed_gap : Double = 8.0

///|
/// How far up a sheet goes for a sheet `over` tall risen under it (the person's 2026-11-02: 「把上一层整个挤上去」,
/// 「往上推到上面被遮盖」, 「为啥叠着」): its foot, which reaches on under the window's (sheet_under), all of it over that
/// one, `pushed_gap` apart, its own foot's corners shown; what of it that takes past the window's top is cut off there.
fn push_of(over : Double) -> Double {
  over + sheet_under + pushed_gap
}

///|
/// The host (see the file's head): what is presented, drawn over everything the app shows. Called by the shell once a
/// frame, at the window's top level, after the pages: it is sized by the window (a sheet spans it whichever pane
/// opened it), and anchored to what opened it wherever that is.
/// `alone`: nothing of the app's is under it (a share over another app): a sheet on the page's paper, not frosted.
pub fn presented(c : @ui.Ctx, alone? : Bool = false) -> Unit {
  presented_said.get() |> ignore
  presented_alone.val = alone
  presented_how.clear()
  let (ww, _) = c.window_size()
  // a sheet on Small, the web's otherwise (docs/architecture.md, rule 3): by the screen, never the hand
  let sheet = layout(ww) is Small
  let gone : Array[Int] = []
  // (sheets closing at once, one pushed up under another (a confirm's 删除 closing what it was asked from): all as far
  // as the furthest of them goes, sinking as one, none over another on their way)
  let sinks = if sheet {
    presented_now.fold(init=0.0, fn(most, q) {
      if q.open || how_of(q.shows, q.from, true) != AsSheet {
        most
      } else {
        @signals.untracked(fn() { dmax(most, q.sheet_h.get() + q.recede.get() * q.pushed.get()) })
      }
    })
  } else {
    0.0
  }
  for i, p in presented_now.copy() {
    p.sinks = sinks
    // (a sheet with another sheet open over it steps back, coming forward again as that one goes: its cause the one
    // over it opened or closed)
    let covered = if sheet {
      p.open && presented_now[i + 1:].iter().any(fn(q) { q.open && how_of(q.shows, q.from, true) == AsSheet })
    } else {
      // (a dialog with another over it: dimmed over itself, nothing moving)
      how_of(p.shows, p.from, false) == AsDialog && dialog_covered(p.serial)
    }
    // (how far up: by the topmost sheet over it as tall as it is now; once none is, as far as it went, to come down
    // from there)
    if covered {
      let over = presented_now[i + 1:].iter().filter(fn(q) { q.open && how_of(q.shows, q.from, true) == AsSheet }).last()
      match over {
        Some(q) =>
          p.pushed.set(push_of(@signals.untracked(fn() { q.sheet_h.get() })))
        None => ()
      }
    }
    // (one closing goes from where it is: pushed up still where it closes with the one over it, both going down; where
    // the one over it closed first that same moment, held where it had got to as it closes too)
    if !p.open && !p.recede.over() {
      p.recede.snap(@signals.untracked(fn() { p.recede.get() }))
    }
    if p.open && covered != p.receded {
      p.receded = covered
      let to = if covered { 1.0 } else { 0.0 }
      if sheet {
        let way = dmax(@signals.untracked(fn() { p.pushed.get() }), 1.0)
        p.recede.animate(to, @motion.move(points=way))
      } else {
        // (dimmed as a dialog's ground comes and goes)
        p.recede.animate(to, @motion.tween(confirm_ground_ms, ease=if covered { Out } else { Leave }))
      }
    }
    let was = p.open
    let mut open = false
    let mut built = false
    c.scope(p.serial, fn() {
      // (at its place in the window's stack of layers, what it opens in it there too: one presented as nodes of the
      // window's tree, at its own, over it or under it as each was presented)
      c.stacked(p.serial, fn() {
        // (dismissed by the hand, at that moment: dismissed_now)
        c.with_dismissed(fn(_) { dismissed_now(p.serial) }, fn() {
          let (o, b) = draw_presented(c, p, sheet)
          open = o
          built = b
        })
      })
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
    // (a panel that goes in steps gone: the steps it was in let go of, the last first)
    for p in presented_now {
      match p.steps {
        Some(nav) if gone.contains(p.serial) => for st in nav.pages().rev() { (st.left)() }
        _ => ()
      }
    }
    let left = presented_now.filter(fn(p) { !gone.contains(p.serial) })
    presented_now.clear()
    presented_now.append(left)
    // (what read whether one of them is drawn told: a row marked while its menu is, built again unmarked)
    presented_drawn_said.set(presented_now.map(fn(p) { p.serial }))
  }
}

///|
fn how_of(shows : Shows, from : Anchor, sheet : Bool) -> How {
  match (sheet, shows) {
    (_, Panel(x)) if x.stage => AsDialog
    (true, _) => AsSheet
    (false, Panel(x)) if from == Unanchored || x.form => AsDialog
    (false, Menu(_, _, _) | Pick(_, _, _, _, _, _) | Panel(_)) => AsPopover
    (false, Confirm(_, _, _, _, _) | Ask(_, _, _, _, _, _, _, _)) => AsDialog
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
  match p.shows {
    Panel(x) if x.stage => return stage_centred(c, key, p, x)
    _ => ()
  }
  // (a confirm the window's tree draws: its node's, open as said, drawn till its way out is over: presented_node.mbt)
  if tree_draws(p, sheet) {
    return (p.open, p.open || tree_presented.contains(p.serial))
  }
  if sheet {
    return present_sheet(c, key, p)
  }
  match p.shows {
    Menu(items, title, along) => menu_popover(c, key, p, items, title, along)
    Pick(title, choices, chosen, choose, along, search) =>
      pick_popover(c, key, p, title, choices, chosen, choose, along, search)
    Panel(x) if p.from == Unanchored || x.form => panel_centred(c, key, p, x)
    Panel(x) => panel_popover(c, key, p, x)
    Confirm(title, words, action, danger, run) => confirm_centred(c, key, p, title, words, action, danger, run)
    Ask(title, value, placeholder, action, hint, secret, empty, run) =>
      ask_centred(c, key, p, title, value, placeholder, action, hint, secret, empty, run)
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
/// How far a small panel stands from what opened it, by default (the web's popovers' sideOffset: 6).
pub let panel_offset : Double = 6.0

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
    let hay = (x.label + "\n" + x.note + "\n" + x.value).to_lower()
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
          if item.heading { @kit.menu_label(item.label) } else { match item.chosen {
            Some(on) => @kit.menu_radio(v, on, label=item.label, disabled=item.disabled)
            None => @kit.menu_item(v, label=item.label, disabled=item.disabled)
          } },
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
  along : @ui.Along,
  search : Bool,
) -> (Bool, Bool) {
  let (anchor, at) = anchor_of(c, p.from)
  // short: a menu of choices (controls.css.ts chooserMenu: the one chosen checked before its words, the arrows,
  // letters and Enter a menu's; none chosen, each its icon there), what each is under its words
  if choices.length() < pick_search_from || !search {
    // (its title over the choices, as a menu's is)
    let entries : Array[@kit.Entry] = if title != "" { [@kit.menu_label(title)] } else { [] }
    let one_chosen = choices.iter().any(fn(x) { x.key == chosen })
    for x in choices {
      entries.push(
        if one_chosen {
          @kit.menu_radio(x.key, x.key == chosen, label=x.label)
        } else {
          @kit.menu_item(x.key, label=x.label)
        },
      )
    }
    let icons : Map[String, String] = {}
    let marks : Map[String, (@ui.Ctx, Double) -> Unit] = {}
    let notes : Map[String, String] = {}
    let values : Map[String, String] = {}
    for x in choices {
      if x.icon != "" {
        icons[x.key] = x.icon
      }
      match x.mark {
        Some(m) => marks[x.key] = m
        None => ()
      }
      if x.note != "" {
        notes[x.key] = x.note
      }
      if x.value != "" {
        values[x.key] = x.value
      }
    }
    let offset = match p.from {
      At(_, _, 0.0, 0.0) => 0.0
      _ => 6.0
    }
    let m = dropdown(c, key, p.open, anchor, entries, icons, chooser_menu_w, along~, offset~, at?, marks~, notes~, row_end=fn(c, s) {
      match values.get(s.entry.value) {
        Some(v) => c.text(v, style=pick_value) |> ignore
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
    along~,
    at?,
    label=title,
    modal=true,
    look=fn(c, s, body) {
      beside_given.val = s
      small_panel(c, w=Px(chooser_menu_w), body) |> ignore
    },
    fn() {
      let found = {
        // (a capsule in the panel's top corners: as far in as makes it concentric with them, menu_row_reach)
        let r = menu_row_reach(theme().rows.pick)
        let mut got : @kit.Field? = None
        c.box(style=@ui.style(w=Full, mx=room(-r), mt=room(-r)), fn() {
          got = Some(input(c, key + "/search", placeholder=t("common.search"), small=true, field=p.line))
        })
        |> ignore
        let f = got.unwrap()
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
        for i, x in found {
          if menu_item(c, x.label, key=key + "/" + x.key, icon=x.icon, mark?=x.mark, on=x.key == chosen, note=x.value, under=x.note, panel=x.icon != "" || x.mark is Some(_), at_foot=i == found.length() - 1) {
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
  let mut drawn = false
  let r = @kit.popover(
    c,
    key,
    p.open,
    anchor,
    side=x.side,
    along=x.along,
    offset=x.offset,
    at?,
    label=x.title,
    modal=true,
    focus=x.focus,
    look=fn(c, s, inner) {
      drawn = true
      beside_given.val = s
      // (a share of the window no taller than the room it has)
      let h : @ui.Size = if x.tall > 0.0 { Px(dmin(x.tall * wh_of(c), s.room)) } else { Auto }
      if x.fits {
        // (never narrower than it has been since it opened: what it holds changing as it is chosen in, a column of it
        // coming and going, it keeps its sides where they were)
        if c.laid_size(s.panel) is Some((w, _)) {
          p.widest = dmax(p.widest, w)
        }
        small_panel(c, min_w?=if p.widest > 0.0 { Some(p.widest) } else { None }, max_w=x.w, h~, inner) |> ignore
      } else {
        small_panel(c, w=Px(x.w), h~, inner) |> ignore
      }
    },
    fn() {
      // (its title as it is now, `live`'s, as a dialog's and a sheet's are)
      let title = match x.live {
        Some(f) => f().0
        None => x.title
      }
      if title != "" {
        panel_head(c, title, end?=x.head_end)
      }
      // (small_panel's pad round it: what reaches its sides on purpose goes out past that, panel_bleed; its rows stand
      // at it)
      panel_sides_in.val = panel_pad
      small_panel_now.val = true
      words_in_now.val = text_in
      rule_over_now.val = if x.ruled && x.foot is Some(_) { panel_pad } else { 0.0 }
      if x.tall > 0.0 {
        c.box(style=panel_grows, fn() { draw_panel_body(x, c, close, keyed=p) }) |> ignore
      } else {
        // (scrolling, where it does, out to the panel's sides, what it holds as far in as without: what reaches them
        // still does; told so as it is drawn, panel_held)
        let k = key + "/panel"
        panel_held_now.val = @kit.held_in_room(c, beside_given.val, key=k)
        @kit.in_room(c, beside_given.val, key=k, reach=held_reach(), style=held_in(), fn() { draw_panel_body(x, c, close, keyed=p) }) |> ignore
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
  (r.value, drawn)
}

///|
/// A panel opened by nothing, in the middle of the window (parts.tsx Dialog: @sf.dialog, its close button).
fn panel_centred(c : @ui.Ctx, key : String, p : Presented, x : PanelOf) -> (Bool, Bool) {
  let close = fn() { done_with(c, p, fn() {  }) }
  match p.steps {
    Some(nav) => return steps_centred(c, key, p, x, nav, close)
    None => ()
  }
  let (title, step, description) = match x.live {
    Some(f) => f()
    None => (x.title, "", x.description)
  }
  // (the dialog's padding round what it holds: what reaches its sides on purpose goes out across it, panel_bleed;
  // its rows' grounds stand at it, concentric with its corner as the last is with its foot's, their words a row's
  // padding in, and its words that are not a row's as far in, its title's and what it says too, panel_words_in, as a
  // small panel's)
  let words_were = words_in_now.val
  words_in_now.val = card_pad - corner_inset
  let still = dialog(
    c,
    key,
    p.open,
    title,
    fn() {
      // what it holds in a column on its words' line, as its title is (what is not a row: its fields, what it says, a
      // switch), its rows' grounds reaching out across that to the dialog's padding, their words on the line, as
      // sheet_column has a sheet's
      let words = words_in_now.val
      let (was, rows_were, given_was, in_was) = (panel_sides_in.val, rows_out.val, column_given.val, column_in_now.val)
      panel_sides_in.val = dialog_pad + words
      rows_out.val = words
      words_in_now.val = 0.0
      column_given.val = true
      column_in_now.val = words
      // as tall as what it holds (the dialog's body scrolls in itself where it is taller than the window leaves it):
      // what would scroll in itself lays itself out whole (panel_whole); one a share of the window caps (`tall`, not a
      // form) filling it, as tall as what it holds where its lists say so (measured_body), as in a sheet
      if x.tall > 0.0 && !x.form {
        let (_, wh) = c.window_size()
        let id = c.id("sf-present/capped/\{p.serial}")
        let share = x.tall * wh - dialog_frame_h
        let h = match capped_want(c, p.serial, id) {
          Some(want) => dmin(want, share)
          None => share
        }
        // (no taller than the dialog shows besides its title and buttons: all of it in view, not scrolled)
        let h = match dialog_body_most(c, key, id) {
          Some(most) => dmin(h, most)
          None => h
        }
        measured_body(c, p.serial, id, @ui.style(w=Full, h=Fixed(h)), fn() { draw_panel_body(x, c, close, keyed=p) })
      } else {
        panel_whole_now.val += 1
        draw_panel_body(x, c, close, keyed=p)
        panel_whole_now.val -= 1
      }
      panel_sides_in.val = was
      rows_out.val = rows_were
      words_in_now.val = words
      column_given.val = given_was
      column_in_now.val = in_was
    },
    description~,
    footer?=match x.foot {
      Some(f) => Some(fn() { f(c, close) })
      None => None
    },
    wide=x.wide,
    close_label=t("common.close"),
    step~,
    column_in=card_pad - corner_inset,
    scrim?=scrim_of(p, false),
    veil=p.recede.get(),
  )
  words_in_now.val = words_were
  (still && p.open, dialog_built(c, key, p.open))
}

///|
/// A panel that goes in steps opened by nothing, in the middle of the window (panel_centred's): the dialog bare, its
/// close button in its corner, each step whole in it (its head, what it is about, what it holds, its foot), sliding in
/// over the one before out to the dialog's edges. Escape and back go back a step before they close it.
fn steps_centred(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  x : PanelOf,
  nav : @ui.Nav[PanelStep],
  close : () -> Unit,
) -> (Bool, Bool) {
  let words_were = words_in_now.val
  let column = card_pad - corner_inset
  words_in_now.val = column
  let still = dialog(
    c,
    key,
    p.open,
    "",
    fn() {
      // (out past its padding and its column to its edges, where a step sliding is cut off)
      steps_shown(c, p, nav, false, dialog_pad + column, fn(s, back) {
        dialog_page(c, key, p, { ..x, body: s.body, foot: s.foot }, s, close, back)
      })
    },
    wide=x.wide,
    close_label=t("common.close"),
    column_in=column,
    bare=true,
    on_escape=fn() { steps_escape(p) },
    scrim?=scrim_of(p, false),
    veil=p.recede.get(),
  )
  words_in_now.val = words_were
  (still && p.open, dialog_built(c, key, p.open))
}

///|
/// A step `s` of panel `x` in a dialog (steps_centred): its head (its back key, `back`, at its start past the first; its
/// title), what it is about, what it holds (its fields' focus given as it opens), its buttons at its foot in its corner;
/// as a titled dialog's are, on its words' line.
fn dialog_page(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  x : PanelOf,
  s : PanelStep,
  close : () -> Unit,
  back : (() -> Unit)?,
) -> Unit {
  let line = c.text_size(Heading).1
  let (title, count, description) = words_of_step(s)
  step_head(c, key, title, count, back, dialog_step_head.then(untitled_clear()), dialog_title, line)
  if description != "" {
    c.box(style=dialog_lead_at, fn() { c.text(description, style=dialog_lead) |> ignore }) |> ignore
  }
  c.box(style=if s.foot is None { dialog_body_end } else { dialog_body }, gone_empty=true, fn() {
    let (was, rows_were, given_was, in_was) = (panel_sides_in.val, rows_out.val, column_given.val, column_in_now.val)
    let words = words_in_now.val
    panel_sides_in.val = dialog_pad + words
    rows_out.val = words
    words_in_now.val = 0.0
    column_given.val = true
    column_in_now.val = words
    panel_whole_now.val += 1
    draw_panel_body(x, c, close, keyed=p)
    panel_whole_now.val -= 1
    panel_sides_in.val = was
    rows_out.val = rows_were
    words_in_now.val = words
    column_given.val = given_was
    column_in_now.val = in_was
  })
  |> ignore
  match s.foot {
    // (in its foot corner as a titled dialog's are, from the step's column: its padding and the words' line in)
    Some(f) =>
      c.box(style=dialog_foot.then(dialog_corner_foot(dialog_pad + words_in_now.val)), fn() { f(c, close) }) |> ignore
    None => ()
  }
}

///|
/// A step's head in a dialog: as high as a titled dialog's head (dialog_head's, its close button over its corner now).
// kept across runs: a value (no field of it changes)
let dialog_step_head : @ui.Style = @ui.style(row=true, w=Full, align=ACenter, min_h=Fixed(dialog_close), pt=room(dialog_head_over))

///|
/// A panel's `stage` (panel), the same on every screen: no panel round what it holds; the window under it the night
/// (stage_scrim, coming and going as a dialog's ground does), what it holds in the window's middle as large as the
/// window lets it (whole_fitted, in stage_room: stage_margin and the system's bars clear of the window's edges, the room
/// its foot takes under it), 关闭 and its foot's buttons under it on the night (on_night), stage_gap apart. Escape, the
/// back, 关闭 and a press beside it close it.
fn stage_centred(c : @ui.Ctx, key : String, p : Presented, x : PanelOf) -> (Bool, Bool) {
  let close = fn() { done_with(c, p, fn() {  }) }
  let title = match x.live {
    Some(f) => f().0
    None => x.title
  }
  let (ww, wh) = c.window_size()
  let bars = @ui.system_bars()
  let foot_id = c.id(key + "/stage-foot")
  let foot_h = match c.laid_size(foot_id) {
    Some((_, h)) => h
    None => button_height()
  }
  let room_w = ww - 2.0 * stage_margin - bars.left - bars.right
  let room_h = wh - 2.0 * stage_margin - bars.top - bars.bottom - foot_h - stage_gap
  let mut closed = false
  let d = @kit.dialog(
    c,
    key,
    p.open,
    title,
    w=room_w,
    close_label="",
    scrim=stage_scrim,
    look=fn(c, _, inner) { c.box(style=stage_box, id=c.id(key + "/frame"), inner) |> ignore },
    fn() {
      let was = stage_room.val
      stage_room.val = Some((room_w, room_h))
      panel_whole_now.val += 1
      draw_panel_body(x, c, close, keyed=p)
      panel_whole_now.val -= 1
      stage_room.val = was
      c.box(style=stage_under, id=foot_id, fn() {
        let night = on_night.val
        on_night.val = true
        match x.above {
          Some(f) => f(c)
          None => ()
        }
        c.box(style=stage_foot, fn() {
          if button(c, t("common.close"), key=key + "/stage-close") {
            closed = true
          }
          match x.foot {
            Some(f) => f(c, close)
            None => ()
          }
        })
        |> ignore
        on_night.val = night
      })
      |> ignore
    },
  )
  (d.value && !closed && p.open, dialog_built(c, key, p.open))
}

///|
/// A stage (stage_centred): what it holds over its buttons, stage_gap apart, each in the stage's middle.
// kept across runs: a value (no field of it changes)
let stage_box : @ui.Style = @ui.css("align=ACenter gap=S5")

///|
// kept across runs: a value (no field of it changes)
let stage_foot : @ui.Style = @ui.css("row gap=S2 align=ACenter justify=JCenter")

///|
/// Under what a stage holds: what is chosen of it (`above`) over its buttons, as far apart as the stage's parts.
// kept across runs: a value (no field of it changes)
let stage_under : @ui.Style = @ui.css("gap=S5 align=ACenter")

///|
/// How far what a stage holds stands from its buttons (stage_box's gap), and the stage from the window's edges.
let stage_gap : Double = @ui.Space::px(S5)

///|
let stage_margin : Double = @ui.Space::px(S6)

///|
/// A capped panel's body in a sheet and the sheet's whole, as present_sheet names them for sheet_body.
// kept across runs: said by present_sheet round what a sheet holds
let sheet_capped : Ref[Int] = { val: 0 }

///|
/// The share of the window a sheet of `shows` comes to at most (a capped panel's, else a sheet's most).
fn sheet_cap(shows : Shows) -> Double {
  match shows {
    Panel(x) if x.tall > 0.0 && !x.form => x.tall
    _ => sheet_most
  }
}

///|
/// How near its cap a sheet's measured height counts as at it (a sheet's height and its body's measured apart).
let sheet_cap_slack : Double = 1.0

///|
/// What a dialog takes of a share of the window besides what it holds: the window's room round it, its padding over and
/// under (dialog_room, dialog_pad).
let dialog_frame_h : Double = dialog_room + dialog_pad + dialog_pad

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
  let r = confirm_dialog(c, key, p.open, title, words, action, cancel=t("common.cancel"), danger~, scrim?=scrim_of(p, false), veil=p.recede.get())
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
  empty : Bool,
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
      if f.submitted && ask_can(words.val, value, empty) {
        said = true
      }
    },
    footer=fn() {
      if button(c, t("common.cancel"), key=key + "/cancel", tone=Ghost) {
        close_from_serial(p.serial)
      }
      if button(c, action, key=key + "/go", tone=Primary, disabled=!ask_can(words.val, value, empty)) {
        said = true
      }
    },
    scrim?=scrim_of(p, false),
    veil=p.recede.get(),
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
/// What a choice is at now at its row's end (a word or two: 当前, 离线; 13, muted).
// kept across runs: a value (no field of it changes)
let pick_value : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let panel_empty : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted)

// ---------------------------------------------------------------------------
// The phone's: a sheet from the window's foot (Sheet.kt SheetHost, mbui's @kit.sheet)

///|
/// How much of the window a sheet takes at most: nearly all of it, up to just under the status bar (Sheet.kt's
/// largest detent), what it holds past that scrolling in it; and a long pick's (the run picker's: 66%). A confirm and a
/// question are as tall as what they hold, their buttons straight under their words (the person's 2026-11-02: 「为啥弹出
/// 的面板按钮跑那么高」, under a share of the window, PageParts.kt's 36% and 42%, they stood high over empty room).
pub let sheet_most : Double = 0.94

///|
let sheet_long_pick : Double = 0.66

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
  // a panel a share of the window caps (tall, not a form): that share, or as tall as what it holds where its lists say
  // so (measured_body), what the sheet takes besides its body as the last layout had it
  let capped = match p.shows {
    Panel(x) => x.tall > 0.0 && !x.form
    _ => false
  }
  let body_id = c.id("sf-present/capped/\{p.serial}")
  let whole_id = c.id("sf-present/whole/\{p.serial}")
  sheet_capped.val = body_id
  let want = match (capped, capped_want(c, p.serial, body_id), c.laid_size(whole_id), c.laid_size(body_id)) {
    (true, Some(w), Some((_, whole)), Some((_, body))) => Some(w + dmax(whole - body, 0.0))
    _ => None
  }
  let over = p.over
  let share = match p.shows {
    Pick(_, choices, _, _, _, _) if choices.length() >= pick_search_from => Some(sheet_long_pick)
    Panel(x) if x.tall > 0.0 && !x.form => Some(x.tall)
    Panel(_) if over => Some(sheet_most)
    _ => None
  }
  let grows = match p.shows {
    Panel(x) => x.grows
    _ => false
  }
  let h = match (share, natural) {
    (Some(s), _) =>
      match want {
        Some(w) => dmin(w, s * wh)
        None => s * wh
      }
    (None, Some(m)) => dmin(m, wh * sheet_most)
    // (before what it holds is first laid out: built again at once, as tall as it is)
    (None, None) => wh * 0.5
  }
  // (how tall it is, for a sheet under it pushed up out of its way: presented)
  p.sheet_h.set(h)
  let base = if presented_alone.val { sheet_look(ground=theme().p.bg) } else { sheet_look() }
  // (pushed up under a sheet over it, it takes nothing (a press on it closes that one): dimmed as the window under it
  // is, as far as it has gone up, the person's 2026-11-02 「是不是应该遮罩一下」; what is under them all dimmed once)
  let look = fn(c : @ui.Ctx, st : @kit.SheetState, body : () -> Unit) {
    base(c, st, fn() {
      body()
      let veil = @ui.alpha(sheet_scrim, p.recede.get())
      if (veil & 0xFFL) != 0L {
        c.layer(fn() { c.box(style=sheet_veil_at.then(@ui.style(bg=Data(veil))), fn() {  }) |> ignore }) |> ignore
      }
    })
  }
  // (dragged between half and nearly all of the window; one its share caps, only where what it holds comes to that)
  let grows = grows &&
    (match want {
      Some(w) => w >= wh * sheet_cap(p.shows) - sheet_cap_slack
      None => true
    })
  // (Escape in one that goes in steps: back a step first)
  let on_escape = if p.steps is Some(_) { Some(fn() { steps_escape(p) }) } else { None }
  // (dimming what is under it only where nothing under it does: scrim_owner; pushed up out of the way of a sheet over
  // it, as far as it has gone, closing from there)
  let scrim = scrim_of(p, true).unwrap_or(sheet_scrim)
  let r = @kit.sheet(c, key, p.open, h~, detents=if grows { sheet_grows_to } else { [] }, scrim~, look~, on_escape?, raised=p.recede.get() * p.pushed.get(), sinks=p.sinks, fn() {
    match share {
      Some(_) =>
        c.box(style=sheet_whole, id=whole_id, fn() {
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
              if item.heading { sheet_title(c, item.label) } else if sheet_row(
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
    Pick(title, choices, chosen, choose, _, search) => {
      if title != "" {
        sheet_title(c, title)
      }
      let many = choices.length() >= pick_search_from
      let long = search && many
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
          if sheet_row(c, key + "/" + x.key, x.label, note=x.note, value=x.value, icon=x.icon, mark?=x.mark, on=x.key == chosen) {
            done_with(c, p, fn() { choose(x.key) })
          }
        }
      }
      if many {
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
      match p.steps {
        // (one that goes in steps: each its own title, what it holds and its foot, sliding in over the one before)
        Some(nav) =>
          steps_shown(c, p, nav, scrolls, 0.0, fn(s, back) {
            let (title, count, description) = words_of_step(s)
            sheet_step(c, key, p, { ..x, body: s.body, foot: s.foot }, title, description, close, scrolls, back?, count~)
          })
        None => {
          let (title, _, description) = match x.live {
            Some(f) => f()
            None => (x.title, "", x.description)
          }
          sheet_step(c, key, p, x, title, description, close, scrolls)
        }
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
    Ask(title, value, placeholder, action, hint, secret, empty, run) => {
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
        let can = ask_can(words, value, empty)
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
/// A panel `x` in a sheet: its title (with `back`, a back key at its start: a step's of one that goes in steps), what it
/// is about, what it holds and its foot (sheet_body's).
fn sheet_step(
  c : @ui.Ctx,
  key : String,
  p : Presented,
  x : PanelOf,
  title : String,
  description : String,
  close : () -> Unit,
  scrolls : Bool,
  back? : () -> Unit,
  count? : String = "",
) -> Unit {
  if back is Some(_) || count != "" {
    step_head(c, key, title, count, back, sheet_title_row, sheet_title_words, c.text_size(Title).1)
  } else if title != "" {
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
  // (one a share of the window caps fills it, as tall as what it holds where its lists say so: measured_body; a form
  // lays out its own sides as it does, and is as tall as it is)
  let capped = x.tall > 0.0 && !x.form
  let room = if capped {
    // (the sheet's foot under what it holds, as a panel's in a sheet: sheet_panel_foot)
    sheet_capped_room
  } else if x.tall > 0.0 {
    full_width
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
    // (filling its share, it lays out its own sides: its words as far in as a sheet's, panel_words_in)
    panel_sides_in.val = if x.tall > 0.0 { 0.0 } else if pressed { sheet_row_sides } else { sheet_panel_sides }
    rows_out.val = panel_sides_in.val
    words_in_now.val = if x.tall > 0.0 {
      sheet_panel_sides
    } else if pressed {
      sheet_panel_sides - sheet_row_sides
    } else {
      0.0
    }
    rule_over_now.val = if x.ruled && x.foot is Some(_) { sheet_rule_over } else { 0.0 }
    // (as tall as what it holds, what would scroll in itself laid out whole, as a dialog's body: panel_whole)
    if capped {
      draw_panel_body(x, c, close)
    } else {
      panel_whole_now.val += 1
      draw_panel_body(x, c, close)
      panel_whole_now.val -= 1
    }
    panel_sides_in.val = 0.0
    rows_out.val = 0.0
    words_in_now.val = 0.0
    rule_over_now.val = 0.0
  }
  if scrolls && !capped && x.lists {
    // (its own lists scroll in the room the sheet has: what it holds fills it)
    c.box(style=sheet_grows, fn() { c.box(style=room.then(sheet_fills), body) |> ignore }) |> ignore
  } else if scrolls && !capped {
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
    // (holding nothing this time, none of its room: its title and what it says straight over its foot; one a share
    // caps measured, its lists saying what they hold: measured_body)
    if capped {
      measured_body(c, p.serial, sheet_capped.val, room, body)
    } else {
      c.box(style=room, gone_empty=true, body) |> ignore
    }
  }
  match x.foot {
    Some(f) => {
      if x.ruled {
        c.box(style=sheet_foot_rule, fn() {  }) |> ignore
      }
      c.box(style=sheet_foot_at, flow=true, line_gap=ask_foot_lines(), fn() {
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

///|
/// What a panel that goes in steps shows: its steps a stack (Ctx::nav: the one on top, and the one beside it as one
/// slides in or away, its left edge swiped back), each drawn by `draw` given its back key's (none on the first), as tall
/// as the step on top is laid out: going there with the slide as another comes or goes, there at once as what one
/// holds changes; filling what holds it where it `fills` (a sheet held to its most). It reaches `out` past its column on
/// each side (where a step sliding is cut off: the panel's edge), each step back on the column by that.
fn steps_shown(
  c : @ui.Ctx,
  p : Presented,
  nav : @ui.Nav[PanelStep],
  fills : Bool,
  out : Double,
  draw : (PanelStep, (() -> Unit)?) -> Unit,
) -> Unit {
  // (each step's box measured by its count, as it is laid out: @motion.measure)
  let key_of = fn(s : PanelStep) { "sf-present/step/\{p.serial}/\{s.n}" }
  let top = nav.top()
  // (its height on its way with the slide: as long as the slide's way across the panel is far)
  let slide = @motion.move(over=c.width)
  match @motion.measured(c, key_of(top)) {
    Some(h) =>
      if p.step_h_of < 0 {
        p.step_h.snap(h)
        p.step_h_of = top.n
      } else if p.step_h_of != top.n {
        // (another step come or gone back to: its height reached with its slide)
        p.step_h.animate(h, slide)
        p.step_h_of = top.n
      } else if p.step_h.target() != h {
        // (what the step holds changed: that height at once, or, before its slide's declared end, where it goes on its
        // way there)
        if p.step_h.over() {
          p.step_h.snap(h)
        } else {
          p.step_h.animate(h, slide)
        }
      }
    None => ()
  }
  let tall = if fills {
    sheet_grows
  } else if p.step_h_of < 0 {
    full_width
  } else {
    @ui.style(w=Full, h=Fixed(p.step_h.get()))
  }
  c.box(style=tall.then(@ui.style(mx=room(-out))), fn() {
    // (a flow kept elsewhere takes back on its step: no edge of the panel swiped back past it)
    let follows = top.on_back is Some(_)
    c.nav(nav, edge=if follows { 0.0 } else { step_edge }, fn(s) {
      let was = steps_drawn_now.val
      steps_drawn_now.val = p.serial
      let back = match s.on_back {
        Some(f) if s.n > 0 => Some(f)
        _ => if s.n > 0 { Some(fn() { nav.pop() |> ignore }) } else { None }
      }
      // (back on the step on top told to the flow it follows, before the panel's own)
      match s.on_back {
        Some(f) if s.n == top.n => c.take_back(f)
        _ => ()
      }
      let i = c.box(style=@ui.style(w=Full, px=room(out)), fn() { draw(s, back) })
      @motion.measure(c, i, key_of(s))
      steps_drawn_now.val = was
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far in from a panel's left edge a swipe takes a step back (Ctx::nav's, as a page's).
let step_edge : Double = 20.0

///|
/// Escape in a panel that goes in steps: back a step, where it is past its first (taken so, the panel open still).
fn steps_escape(p : Presented) -> Bool {
  match p.steps {
    Some(nav) =>
      match nav.top().on_back {
        // (a flow kept elsewhere: told, the panel going as it goes; its first step's back closing it there)
        Some(f) => {
          f()
          true
        }
        None => nav.depth() > 1 && nav.pop()
      }
    None => false
  }
}

///|
/// A step's title, which of its flow's it is and what it is about: as they are now where it says (`live`: the first's
/// the panel's, a wizard's), else as it was given.
fn words_of_step(s : PanelStep) -> (String, String, String) {
  match s.live {
    Some(f) => f()
    None => (s.title, s.count, s.description)
  }
}

///|
/// A step's head: its back key at its start (its chevron on the words' line, the line no taller for it) and its title
/// (`words`, `line` high) beside it, in `row`.
fn step_head(
  c : @ui.Ctx,
  key : String,
  title : String,
  count : String,
  back : (() -> Unit)?,
  row : @ui.Style,
  words : @ui.TextStyle,
  line : Double,
) -> Unit {
  c.box(style=row.then(step_head_gap), fn() {
    match back {
      Some(f) =>
        c.box(style=in_line(step_back_side - line).then(@ui.style(ml=room(-step_back_in))), fn() {
          if icon_button(c, "chevron-left", key=key + "/back", size=step_back_side, round=true, label=t("common.back")) {
            f()
          }
        })
        |> ignore
      None => ()
    }
    // (which of its flow's steps beside its title: Connect.css.ts dialogStep)
    c.box(style=dialog_title_line, fn() {
      c.text(title, style=words) |> ignore
      if count != "" {
        c.text(count, style=dialog_step) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A step's back key (a dialog's close button's size), and how far its chevron (16) stands in from its edge: so far out
/// of the words' line it stands, its chevron on it.
let step_back_side : Double = dialog_close

///|
let step_back_in : Double = (dialog_close - 16.0) / 2.0

///|
// kept across runs: a value (no field of it changes)
let step_head_gap : @ui.Style = @ui.css("gap=S1")

///|
/// The window's height (what a long pick's list is capped by before the sheet's room shrinks it).
fn wh_of(c : @ui.Ctx) -> Double {
  c.window_size().1
}

///|
/// A sheet's title (Sheet.kt SheetHead): 17 bold, on its words' line (sheet_panel_sides in), 4 over and 10 under.
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
  value? : String = "",
  icon? : String = "",
  mark? : (@ui.Ctx, Double) -> Unit,
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
    let leads = fn() {
      match mark {
        Some(m) => m(c, th.items.mark)
        None =>
          if icon != "" {
            draw_icon(c, icon, th.items.mark, if danger { ink } else { th.p.muted })
          }
      }
    }
    let first = fn() {
      c.box(style=sheet_row_words_at, fn() {
        c.text(label, style=th.items.name.then(sheet_row_words).then(@ui.text_style(color=Data(ink)))) |> ignore
      })
      |> ignore
      // (what it is at now, a word or two, at its end)
      if value != "" {
        c.text(value, style=pick_value) |> ignore
      }
      if on {
        draw_icon(c, "check", sheet_row_check, th.p.accent)
      }
    }
    if note == "" {
      leads()
      first()
    } else {
      // what it is under its words, what leads it by its first line (lead_by_first_line)
      let lead_w = if mark is Some(_) || icon != "" { th.items.mark } else { 0.0 }
      lead_by_first_line(c, lead_w, sheet_row_gap, leads, first, fn() { c.text(note, style=sheet_row_note) |> ignore })
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
let sheet_title_row : @ui.Style = @ui.css("row w=Full pt=S1 pb=S2_5 align=ACenter").then(@ui.style(px=room(sheet_panel_sides)))

///|
// kept across runs: a value (no field of it changes)
let sheet_title_words : @ui.TextStyle = @ui.text_style(size=Title, weight=Bold, color=Fg)

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
/// Between a sheet's row's mark and its words (sheet_row_box's S3).
let sheet_row_gap : Double = 12.0

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
let sheet_panel : @ui.Style = @ui.style(w=Full, px=room(sheet_panel_sides), pb=room(sheet_panel_foot), gap=S2_5)

///|
/// What a sheet's panel leaves under what it holds, its foot (sheet_panel): 24.
pub let sheet_panel_foot : Double = 24.0

///|
/// What a panel a share of the window caps holds in a sheet: the room the sheet leaves it, its foot under it.
// kept across runs: a value (no field of it changes)
let sheet_capped_room : @ui.Style = sheet_grows.then(@ui.style(pb=room(sheet_panel_foot)))

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
