// The presenters (Presenters): a menu, a pick (one of a list, searched when long), a small panel,
// a confirm and a question with a line to write. A page says what it shows and what opened it, once, as it is pressed;
// the presenter decides how, by the screen alone (rule 3: the steps one after another near each
// other): on Small (@sf.layout) a sheet from the window's foot (the phone's: its grabber, dragged down or back to
// close); on Medium and Large, with either hand, the web's, a small panel beside what opened it (a menu, a pick, a
// panel) or a dialog in the middle of the window (a confirm, a question). One host draws them all over
// the shell (`presented`), after the pages, each frame: it keeps what is open, one over another, the topmost taking
// back, Escape and a press outside, and the focus going into it as it opens.
//
// A step further in changes page in the panel rather than stacking (the user, 2026-11-02: 「现有的多重弹窗太垃圾了」
// ); stacking is for what is asked and returned from.
// That is the host's to keep, not each page's (the user, 2026-11-09: 「小屏上多级抽屉感觉动效和交互有问题」, 2026-11-10:
// 「系统性全修一下」: only two flows had been put on panel_go, the rest closed one and opened the next). What is
// presented while one closed has had no frame drawn of its going is what that one closed for:
// - on a sheet it comes in that one's place: one sheet all along, where that one stood, on to its own height, the
//   scrim as it was, never one sinking as the next rises across it (`in_place`);
// - a menu for a menu's item is a level of the same sheet, sliding in, back taking it off (menu_level);
// - a panel for what a panel held is a step further in from it on every screen (`under`): a back key before its
//   title, back, Escape and the system's back back to the one before (back_under, panel_back), a press outside, its
//   close button or the sheet dragged down closing all of it.

///|
/// What opened a presenter: the box pressed (its id, `c.id(key)`; a node of the window's tree, `Node`: a row of a
/// panel whose body is nodes), a rectangle of the window (x, y, w, h: a point is one 0 by 0, where a right click was),
/// or nothing (what is asked by no press of the person's).
pub(all) enum Anchor {
  Of(Int)
  Node(@view.View)
  At(Double, Double, Double, Double)
  Unanchored
}

///|
/// The same opener: the same box, the same node, the same rectangle, or both nothing.
pub impl Eq for Anchor with equal(self, other) {
  match (self, other) {
    (Of(a), Of(b)) => a == b
    (Node(a), Node(b)) => a.id() == b.id()
    (At(x, y, w, h), At(x2, y2, w2, h2)) => x == x2 && y == y2 && w == w2 && h == h2
    (Unanchored, Unanchored) => true
    _ => false
  }
}

///|
/// What opened a menu or a pick, which stand beside it on Medium and Large (rule 3: the steps one
/// after another near each other): the box pressed (its id), a node of the window's tree pressed (`Node`: beside it
/// where it is drawn, following it as it moves, the focus given back to it as it closes), or a rectangle of the window
/// (a right click's point). Never nothing: no page can open one beside nothing, as a dialog in the middle of the window.
pub(all) enum Beside {
  Of(Int)
  Node(@view.View)
  At(Double, Double, Double, Double)
}

///|
/// The same opener: the same box, the same node, the same rectangle (Anchor's).
pub impl Eq for Beside with equal(self, other) {
  self.anchor() == other.anchor()
}

///|
/// What opened it, as the presenters keep it.
pub fn Beside::anchor(self : Beside) -> Anchor {
  match self {
    Of(id) => Anchor::Of(id)
    Node(v) => Anchor::Node(v)
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
  /// a confirm: its title, what it does, a warning, its action, whether that cannot be undone, what goes on once said
  Confirm(String, String, String, String, Bool, () -> Unit)
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
  /// in the middle of the window, what its title's row holds in its title's place, its close button at its end (panel's
  /// `title_row`)
  title_row : ((@ui.Ctx) -> Unit)?
  /// beside what opened it, no head: what it holds draws its own (panel's `heads_itself`)
  heads_itself : Bool
  /// beside what opened it: on which side of it, along it where, how far from it (panel's `side`, `along`, `offset`),
  /// or flush with another small panel's outer box (`match_panel`: its serial, 0 none)
  side : @ui.Side
  along : @ui.Along
  offset : Double
  match_panel : Int
  /// what it holds goes in steps in it (panel's `steps`: panel_go, panel_back)
  steps : Bool
  /// what back does on its first step where its steps follow a flow kept elsewhere (panel's `back`: panel_go's)
  on_back : (() -> Unit)?
  /// what it holds and its foot as nodes of the window's tree (panel_nodes), `body` and `foot` then nothing
  nodes : PanelNodes?
}

///|
/// What a panel presented by panel_nodes holds and what is at its foot, each made once as nodes of the window's tree in
/// the node the panel gives it, given what closes it.
priv struct PanelNodes {
  body : (@view.View, () -> Unit) -> Unit
  foot : ((@view.View, () -> Unit) -> Unit)?
  /// a share of the window tall (`tall`): as tall as what it holds up to that share, not that share whatever it holds
  hugs : Bool
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
  /// the field given the keyboard's focus as it opened (focus_once's; its id, 0 none): let go of as what it holds
  /// closes it (field_let_go)
  mut field_id : Int
  /// what is let go of as it closes unsaid (back, Escape, a press outside, its close button), and whether it closed
  /// so or was said
  gone : () -> Unit
  mut ended : Bool
  /// as a sheet, the natural height last laid out for what it holds (0 none yet): capped to a sheet's most while
  /// taller than the sheet's window height, un-capped again when the window grows back; whether an editor in it has
  /// raised the soft keyboard, and the window height it was last laid out for while open
  mut natural_h : Double
  mut in_ime : Bool
  mut win_h : Double
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
  /// as a sheet: how tall it stood over the window's foot as last drawn (0 not drawn as one: @kit.sheet's `stands`);
  /// a sheet of the window's tree (sheet_node), as it closed: what says so then (`stands_now`, asked by close_from)
  mut stands : Double
  mut stands_now : (() -> Double)?
  /// closed, no frame drawn of it since (close_from; unsaid as presented draws it going): what is presented meanwhile
  /// (what was chosen or pressed in it opened another) comes in its place
  mut closed_now : Bool
  /// presented as a sheet closed, none drawn of that going yet: how tall that one stood. As a sheet too, this one comes
  /// in its place (present_sheet, sheet_node: there at once that tall, on to its own height, the scrim as it was), not
  /// from below as that one sinks across it
  in_place : Double?
  /// the serial of the one presented in its place (`in_place`'s; 0 none): drawn no more once that one is a sheet in it
  mut taken_by : Int
  /// a menu on a sheet whose item opened a menu (分享…): that one a level of this, in the same sheet (menu_level), as
  /// a panel's steps are (a stack's: each slides in over the one before, its back key, Escape, the system's back and
  /// its left edge swiped take it off); the first its own. None: no level gone to yet
  mut levels : @ui.Nav[PanelStep]?
  /// closed by what was chosen in it (done_with), not unsaid: its levels' `gone` not told
  mut chosen : Bool
  /// a panel on a sheet presented by what a panel on a sheet held, which closed for it (a row of the chat's own sheet,
  /// its agent's card): a step further in from that one (the file's head: 弹层里往里走), which is kept here, drawn no
  /// more; back from this one (its back key, the system's back, Escape) puts that one back in its place (back_under),
  /// a press outside or the sheet dragged down closes all of it
  mut under : Presented?
  /// a panel of nodes on a sheet: the panels of nodes a step further in from it that it closed for, each a page of the
  /// same sheet (panel_page: sheet_node's pages, each kept as it was left, sliding in over the one before); back takes
  /// the last off (panel_pop), a press outside or the sheet dragged down closes all of it
  more : @signals.Signal[Array[PanelPage]]
}

///|
/// A page of a sheet past its first (Presented's `more`): its number in it, its panel, what opened it, what is let go
/// of as it is left unsaid (gone back from, or the sheet closed with nothing chosen).
priv struct PanelPage {
  n : Int
  x : PanelOf
  from : Anchor
  gone : () -> Unit
}

///|
/// How a presenter is drawn this frame (what a test reads).
// Debug for its tests
#warnings("-unused_value")
#derive(Eq, Debug)
priv enum How {
  AsSheet
  AsPopover
  AsDialog
}

///|
/// What is presented, the lowest first; how many were opened (each one's keys its own).
// kept across runs: put back by presenters_reset (parts_reset)
let presented_now : Array[Presented] = []

///|
// kept across runs: put back by presenters_reset (parts_reset)
let presented_count : Ref[Int] = Ref(0)

///|
/// What is presented as it was last told (presented_told): each one's serial, whether it is open, closed whether the
/// window's tree draws it still going out, the lowest first. What reads what is presented (the host, presented; presenting, the scrim's
/// owner, what of them the tree draws) built again as that changes, wherever it was asked from, not as what one of
/// them shows does (presented_items_of).
// kept across runs: put back by presenters_reset
let presented_said : @signals.Signal[Array[(Int, Bool, Bool)]] = @signals.signal([], same=fn(a, b) { a == b })

///|
/// What each menu presented offers, as it was last told (presented_changed), by its serial: its items as they show
/// (label, icon, danger, disabled, chosen, heading), so that what draws them is built again as they show otherwise.
// kept across runs: put back by presenters_reset; one let go as it is
let presented_items_said : Map[Int, @signals.Signal[Array[(String, String, Bool, Bool, Bool?, Bool)?]]] = Map([])

///|
/// How `items` show, compared as they are given anew (presented_changed).
fn items_shown(items : Array[MenuItem?]) -> Array[(String, String, Bool, Bool, Bool?, Bool)?] {
  items.map(fn(x) { x.map(fn(m) { (m.label, m.icon, m.danger, m.disabled, m.chosen, m.heading) }) })
}

///|
/// The items of the menu presented as `serial` (`items`, where it keeps them), read: what reads them built again as
/// they are given anew showing otherwise (presented_changed).
fn presented_items_of(serial : Int, items : Array[MenuItem?]) -> Array[MenuItem?] {
  let s = match presented_items_said.get(serial) {
    Some(s) => s
    None => {
      let s = @signals.signal(items_shown(items), same=fn(a, b) { a == b })
      presented_items_said[serial] = s
      s
    }
  }
  s.get() |> ignore
  items
}

///|
/// The serial of the sheet presented in the place of each sheet (present's `in_place`), by that one's serial: what is
/// marked while one is drawn (a row held, lifted while its menu is up: presented_drawn_of) stays so while what took
/// its place is, and what took that one's.
// kept across runs: put back by presenters_reset; one let go as what it leads to is gone
let took_place : Map[Int, Int] = Map([])

///|
/// Which are drawn (open, or going), by their serials: told each as it comes or is gone (presented_drawn_of).
// kept across runs: put back by presenters_reset
let presented_drawn_said : @signals.Keyed[Int] = @signals.keyed()

///|
fn presented_told() -> Unit {
  // (one closed, whether the tree draws it still going out: what the host lets go of as it is gone)
  presented_said.set(presented_now.map(fn(p) { (p.serial, p.open, !p.open && tree_presented.contains(p.serial)) }))
}

///|
/// What one presented shows changed where it is kept (a menu's items given anew as they are now): what draws it told,
/// where they show otherwise.
pub fn presented_changed() -> Unit {
  for p in presented_now {
    match (p.shows, presented_items_said.get(p.serial)) {
      (Menu(items, _, _), Some(s)) => s.set(items_shown(items))
      _ => ()
    }
  }
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
  took_place.clear()
  tree_presented.clear()
  tree_as_sheet.clear()
  presented_popovers.clear()
  presented_drawn_said.set([])
  presented_items_said.clear()
  presented_told()
  lists_of.clear()
  presented_count.val = 0
  presented_alone.val = false
  presented_how.clear()
  presented_sheet_rests.clear()
  presented_sheet_next.val = 0
  presented_sheet_ended.val = -1.0
  sheet_win_h.val = 0.0
}

///|
fn present(shows : Shows, from : Anchor, line? : String = "", gone? : () -> Unit = fn() {  }) -> Unit {
  // (presented as a sheet closed, none drawn of that going yet (what was chosen or pressed in it presents this): in
  // that one's place, the topmost of them's; a menu by what was chosen in a menu, a level of that one)
  let chosen_in = presented_now.iter().filter(fn(q) { q.closed_now && q.stands > 0.0 && q.taken_by == 0 }).last()
  match (chosen_in, shows) {
    (Some(old), Menu(items, title, _)) if old.chosen && old.shows is Menu(_, _, _) => {
      menu_level(old, title, items, gone)
      return
    }
    _ => ()
  }
  // (a panel by what a panel on a sheet of the window's tree held, which closed for it: a page of that sheet)
  match (chosen_in, shows) {
    (Some(old), Panel(x)) if old.chosen &&
      old.steps is None &&
      old.stands_now is Some(_) &&
      // (that sheet drawn still: not one the window's tree let go of as the window came to another screen)
      tree_presented.contains(old.serial) &&
      tree_as_sheet.get(old.serial).unwrap_or(false) &&
      sheet_panel_of(x) &&
      old.shows is Panel(_) => {
      panel_page(old, x, from, gone)
      return
    }
    _ => ()
  }
  presented_count.val += 1
  match chosen_in {
    Some(old) => {
      old.taken_by = presented_count.val
      took_place[old.serial] = presented_count.val
    }
    None => ()
  }
  // (a panel by what a panel held, which closed for it, no frame drawn of that going yet: a step further in from that
  // one, on a sheet or not)
  let under = match (presented_now.iter().filter(fn(q) { q.closed_now }).last(), shows) {
    (Some(old), Panel(x)) if old.chosen && !x.stage && old.steps is None && old.shows is Panel(_) => Some(old)
    _ => None
  }
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
    field_id: 0,
    gone,
    ended: false,
    natural_h: 0.0,
    in_ime: false,
    win_h: 0.0,
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
    stands: 0.0,
    stands_now: None,
    closed_now: false,
    in_place: chosen_in.map(fn(old) { old.stands }),
    taken_by: 0,
    levels: None,
    chosen: false,
    under,
    more: @signals.signal([]),
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
/// Its words the screen's: touch's the phone's, keyboard and mouse's its context menu's.
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
/// the same (stage_node): no panel round it, the window under it the night (stage_scrim), what it holds in the
/// middle drawn as large as the window lets it (whole_fitted), 关闭 and its `foot`'s buttons under it on the night;
/// a press beside it, Escape and the back close it too; `above`, over those buttons, what is chosen of the picture (the
/// card to share's looks). `side`, `along`, `offset`: where it stands beside what opened it (under it by default, its
/// start at the start of it); what opens from a bar down the window's side (the rail) stands beside the bar, out of
/// it, as everything opened from there does. `title_row`: in the middle of the window, its title's row drawn by it in the title's place (a chat's name with its ✎
/// after it, an agent's mark, name and where it stands), its close button at that row's end as a title's is; `title`
/// still what it is called. What it holds asks Ctx-free `title_row_given` whether to draw that row itself (elsewhere:
/// a sheet, a panel beside what opened it).
/// `heads_itself`: beside what opened it, no head drawn for it: what it holds draws its title where it wants it (the
/// model panel's, a title over each of its columns; a sheet's head is the sheet's own still).
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
  title_row? : (@ui.Ctx) -> Unit,
  heads_itself? : Bool = false,
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
      title_row,
      heads_itself,
      side,
      along,
      offset,
      match_panel: 0,
      steps,
      on_back: back,
      nodes: None,
    }),
    from,
    gone~,
  )
}

///|
/// A panel as @sf.panel's (`title`, `from`, `w`, `description`, `wide`, `live`, `gone`, `tall`, `focus`, `ruled`, `form`,
/// `grows`, `side`, `along`, `offset` as there; `hugs`: one `tall` as tall as what it holds up to that share, as a sheet
/// and a dialog in the middle of the window draw it, not that share whatever it holds; `match_panel`: serial of a small
/// panel whose outer box it goes beside while keeping its own width `w`), what it holds (`body`) and what
/// is at its foot (`foot`) made once as nodes of the window's tree, each in the node the panel gives it, laid out there
/// as the old frame's body and foot are (beside what opened it: panel_node; in the middle of the window, opened by
/// nothing or a form: panel_centred_node), given what closes it.
/// The window's tree draws it on every screen: on 小屏 a sheet from the window's foot (sheet_node), as the host draws an
/// old-bodied panel there. Beside @sf.panel only while panels with old bodies are left (detlint's old-panel):
/// as the last goes, the old body's path goes and this takes the name `panel`.
pub fn panel_nodes(
  title : String,
  body : (@view.View, () -> Unit) -> Unit,
  from~ : Anchor,
  w? : Double = panel_w,
  description? : String = "",
  foot? : (@view.View, () -> Unit) -> Unit,
  wide? : Bool = false,
  live? : () -> (String, String, String),
  gone? : () -> Unit = fn() {  },
  tall? : Double = 0.0,
  focus? : Bool = true,
  ruled? : Bool = false,
  form? : Bool = false,
  grows? : Bool = false,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = panel_offset,
  hugs? : Bool = false,
  match_panel? : Int = 0,
) -> Unit {
  present(
    Panel({
      title,
      description,
      body: fn(_, _) {  },
      foot: None,
      w,
      fits: false,
      wide,
      live,
      tall,
      grows,
      focus,
      ruled,
      lists: false,
      fade_out_together: false,
      form,
      field: "",
      stage: false,
      above: None,
      title_row: None,
      heads_itself: false,
      side,
      along,
      offset,
      match_panel,
      steps: false,
      on_back: None,
      nodes: Some({ body, foot, hugs }),
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
    // (a page of a sheet past its first: taken off; a panel a step further in from another, which closed for it: back
    // to that one; to the step `to` deep, a step back at a time till it is that deep, in the same change)
    _ => {
      let back_one = fn() {
        match presented_now.iter().filter(fn(q) { q.open && (q.more.untracked().length() > 0 || q.under is Some(_)) }).last() {
          Some(p) => panel_pop(p) || back_under(p)
          None => false
        }
      }
      match to {
        None => back_one()
        Some(d) => {
          let mut went = false
          @signals.start_batch()
          while steps_in_now() > d && back_one() {
            went = true
          }
          @signals.end_batch()
          went
        }
      }
    }
  }
}

///|
/// How many steps deep the topmost open panel of nodes stands (1 its first): its sheet's pages, and the panels it is a
/// step further in from, each with its own.
fn steps_in_now() -> Int {
  fn deep(p : Presented) -> Int {
    1 +
    p.more.untracked().length() +
    (match p.under {
      Some(u) => deep(u)
      None => 0
    })
  }

  match presented_now.iter().filter(fn(q) { q.open }).last() {
    Some(p) => deep(p)
    None => 0
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
/// While the body of a panel a share of the window caps is drawn by the window's tree (panel_centred_node): each list
/// that says what it holds as tall as that, giving way where what holds it is laid out shorter (scrolling in itself
/// there), so what holds them asks to be as tall as all of it: laid out, not measured after.
// kept across runs: said by panel_centred_node round a tall panel's body
let lists_sized_now : Ref[Bool] = { val: false }

///|
// kept across runs: said by panel_list as it is drawn in a capped panel's body
let lists_now : Array[(Int, Double)] = []

///|
/// A capped panel's lists as its body was last drawn, by the presented's serial: each its box and what it holds.
// kept across runs: said by measured_body, let go of by presenters_reset
let lists_of : Map[Int, Array[(Int, Double)]] = Map([])

///|
/// A capped panel's body (filling its share: `style`), its lists saying what they hold as it is drawn. Its box.
fn measured_body(c : @ui.Ctx, serial : Int, id : Int, style : @ui.Style, body : () -> Unit) -> Int {
  let (said_was, were) = (lists_said_now.val, lists_now.copy())
  lists_said_now.val = true
  lists_now.clear()
  let held = c.box(style~, id~, body)
  lists_of[serial] = lists_now.copy()
  lists_now.clear()
  lists_now.append(were)
  lists_said_now.val = said_was
  held
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
    // A list has not been laid out yet. Wait for all the body's lists to say what they hold.
    guard l.1 >= 0.0 else { return None }
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
/// has what it holds (its arrangement, its sides, its words' line, its rows' reach): they are drawn after the panel's
/// body has said it.
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
  rows? : @ui.RowCauses,
) -> Int {
  let arrangement = look()
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
  let mut sized = None
  if lists_said_now.val && !fills {
    match c.list_info_as(key, fn(i) { i.map(fn(x) { x.content }) }) {
      Some(i) => {
        lists_now.push((room_id, i.content))
        // (drawn by the window's tree: as tall as it says, giving way: lists_sized_now)
        if lists_sized_now.val {
          sized = Some(i.content)
        }
      }
      // An estimate here would first size the panel to an unmeasured row, then size it again when the row is laid out.
      None => lists_now.push((room_id, -1.0))
    }
  }
  let room_at = match sized {
    Some(holds) => @ui.style(w=Full, h=Fixed(holds), mx=room(-out))
    None => sheet_grows.then(@ui.style(mx=room(-out)))
  }
  let room_box = c.box(style=room_at, id=room_id, taps=false, fn() {
    list = c.list(key, count, est, stick_end~, sized?=rows, fn(i) {
      with_look(arrangement, fn() {
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
  })
  if sized is Some(_) {
    c.gives_way(room_box)
  }
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
    // (drawn by the window's tree, stage_gives: as tall as it is laid out at the stage's width, giving way to the room
    // the stage's column leaves it under what is under it, drawn smaller to that room as the tree gave it its old view
    // (stage_given): its own height measured as before, the room given it from outside, not read back from in it)
    Some((sw, sh)) if stage_gives.val => {
      let kw = dmin(1.0, sw / most)
      let k = dmin(kw, if h > 0.0 { stage_given.val / h } else { 1.0 })
      stage_drawn_w.val = most * k
      stage_laid_w.val = most
      // (as tall as it is laid out at the stage's width; before that is known, all the stage has)
      let asks = if h > 0.0 { h * kw } else { sh }
      (@ui.style(w=Fixed(most * k), h=Fixed(asks)), most * k, most, k)
    }
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
  // (drawn by the window's tree: as tall as it says, giving way: lists_sized_now)
  let sized = lists_said_now.val && lists_sized_now.val && h > 0.0 && stage_room.val is None
  let room = if sized { @ui.style(w=Full, h=Fixed(h)) } else { room }
  let room_box = c.box(style=room, id=room_id, taps=false, fn() {
    // (as wide as it is laid out, in the room's middle, drawn smaller from its top's middle)
    let at = c.box(style=whole_box.then(@ui.style(w=Fixed(w))), left=(room_w - w) / 2.0, top=0.0, taps=false, fn() {
      draw(whole_id) |> ignore
    })
    c.look(at, @ui.look(scale=k, ox=0.5, oy=0.0))
    // (over it, as large as it is drawn)
    c.box(style=whole_box.then(@ui.style(w=Fixed(w * k), h=Fixed(h * k))), id~, left=(room_w - w * k) / 2.0, top=0.0, fn() {  })
    |> ignore
  })
  if sized || (stage_room.val is Some(_) && stage_gives.val) {
    c.gives_way(room_box)
  }
}

///|
/// Whether the stage whole_fitted is drawn on is the window's tree's (stage_node): what it holds gives way to the room
/// its column leaves it.
// kept across runs: set only while a stage's body is built by the window's tree, and put back
let stage_gives : Ref[Bool] = Ref(false)

///|
/// How wide what a stage the window's tree draws shows was drawn, as it was last built (stage_node's column as wide).
// kept across runs: set as a stage's body is built, read just after
let stage_drawn_w : Ref[Double] = Ref(0.0)

///|
/// How wide what that stage shows is laid out (whole_fitted's `most`, whatever it is drawn as): its old view as wide,
/// what it holds cut by nothing at its sides.
// kept across runs: set as a stage's body is built, read just after
let stage_laid_w : Ref[Double] = Ref(0.0)

///|
/// The height the window's tree gave a stage's body as it last laid it out (its old view's node's: stage_node).
// kept across runs: set as a stage's body is built, read in it
let stage_given : Ref[Double] = Ref(0.0)

///|
/// The room a stage gives what it shows (stage_node), while it is drawn: as wide and as tall as that may be.
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
  rows_out.val = dmax(0.0, sides - panel_card_in)
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
/// A card a page lays out itself in a panel's body: out across the room the panel leaves at its sides as its rows'
/// grounds are (rows_out), `panel_card_in` (16) in from its sides, concentric with its corners (the user, 2026-11-03:
/// 面板里可以放卡片; 第二套感觉还行); none outside a panel.
pub fn panel_card_out() -> @ui.Style {
  // (none in a small panel: what it holds stands at its padding already)
  if small_panel_now.val {
    return no_card_out
  }
  // (from the column it stands in, `panel_sides_in` from the panel's sides (a list's in a dialog nearer them, the
  // list out across the room its rows reach), out or in to `panel_card_in` from them)
  if panel_sides_in.val <= 0.0 && words_in_now.val <= 0.0 {
    return no_card_out
  }
  @ui.style(mx=room(panel_card_in - panel_sides_in.val))
}

///|
/// Under the last of what a dialog with no buttons holds where that is a card: the room its foot leaves less what a
/// card at its foot stands in (`panel_card_in`, concentric with its foot corners as with its sides: panel_card_out);
/// none elsewhere (a sheet's foot is the screen's).
pub fn panel_card_foot() -> @ui.Style {
  if column_given.val && !small_panel_now.val {
    @ui.style(mt=room(-(dialog_pad - panel_card_in)))
  } else {
    no_card_out
  }
}

///|
/// The same on the last of what a dialog holds itself, where that is a card (or holds one at its foot): its margin under
/// it, what follows it in a column with a gap between not pushed further down by that gap.
pub fn panel_card_last() -> @ui.Style {
  if column_given.val && !small_panel_now.val {
    @ui.style(mb=room(-(dialog_pad - panel_card_in)))
  } else {
    no_card_out
  }
}

///|
// kept across runs: a value (no field of it changes)
let no_card_out : @ui.Style = @ui.css("")

///|
/// Something standing `by` out of a panel's words' line at its start (a round button whose mark is on the line): its
/// margin the line less `by`, no further out than the panel's rows reach (rows_out: `panel_card_in` from its sides, the
/// room of a list it is in): a mark is no button's words, its ground no nearer the sides than a row's (the user,
/// 2026-11-03: 只有按钮的字考虑跟卡片/面板的字对齐).
pub fn panel_words_out_by(by : Double) -> @ui.Style {
  @ui.style(ml=room(dmax(words_in_now.val - by, -rows_out.val)))
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
  } else if words_in_now.val > 0.0 {
    let inset = dmax(0.0, panel_card_in - panel_sides_in.val)
    let pad = dmax(0.0, words_in_now.val - inset)
    @ui.style(mx=room(inset), px=room(pad), radius=row_radius, hovered=@ui.patch(bg=Hover))
  } else if rows_out.val > 0.0 {
    let out = dmin(rows_out.val, text_in)
    @ui.style(mx=room(-out), px=room(out), radius=row_radius, hovered=@ui.patch(bg=Hover))
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
  // (it, or the sheet that took its place, or the one that took that one's: a row's menu, then what its item opened)
  let mut s = serial
  while true {
    // (read so: what reads it built again as it is presented or gone, not as others are)
    presented_drawn_said.has(s) |> ignore
    if presented_now.iter().any(fn(p) { p.serial == s }) {
      return true
    }
    match took_place.get(s) {
      Some(n) => s = n
      None => break
    }
  }
  false
}

///|
/// Asks before `action` (parts.tsx Confirm): `title`, what it does (`words`), the cancel and
/// `action` (in red when `danger`: what cannot be undone). A `warning`, if given, is shown in red. Said, it closes and
/// `run` goes on.
pub fn confirm(
  title : String,
  words : String,
  action : String,
  run : () -> Unit,
  danger? : Bool = false,
  warning? : String = "",
  from? : Anchor = Unanchored,
) -> Unit {
  present(Confirm(title, words, warning, action, danger, run), from)
}

///|
/// Asks for a line: `title`, a field (`value` in it at first, `placeholder` while it is empty,
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
/// the thing its own field, which says the words itself.
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
    let q = presented_now[k]
    if q.open {
      q.open = false
      q.closed_now = true
      // (a sheet of the window's tree: how tall it stands now, for what comes in its place)
      match q.stands_now {
        Some(f) => q.stands = f()
        None => ()
      }
    }
  }
  presented_told()
}

///|
/// The one presented as `serial` dismissed by the hand at that moment (back, Escape, a press outside it: its layer told so,
/// @ui.Ctx::with_dismissed): where it is open still, it closes, and what is over it, and what it holds is let go of, once,
/// then; its view draws it going from the next frame on.
fn dismissed_now(serial : Int, back? : Bool = false) -> Unit {
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    // (a step further in, gone back from: a page of its sheet taken off; a panel's from another's, that one back)
    Some(i) if back && presented_now[i].open && (panel_pop(presented_now[i]) || back_under(presented_now[i])) => ()
    Some(i) if presented_now[i].open => {
      // (it and what is over it, each closed unsaid let go of once, from the top)
      let closing = presented_now[i:].to_owned().filter(fn(q) { q.open && !q.ended }).rev()
      close_from(i)
      for q in closing {
        q.ended = true
        gone_all(q)
      }
    }
    _ => ()
  }
}

///|
/// Panel `x` (opened by `from`, `gone` as panel_nodes') presented by what a page of sheet `p` held, which closed the
/// sheet for it: a page of `p`, a step further in. `p`, closed as its page said so, is open again.
fn panel_page(p : Presented, x : PanelOf, from : Anchor, gone : () -> Unit) -> Unit {
  p.open = true
  p.closed_now = false
  p.ended = false
  p.chosen = false
  p.steps_made += 1
  // (how tall it stands now, for the page put on to set out from: sheet_node's `stood`, as panel_pop has it)
  match p.stands_now {
    Some(f) => p.stands = f()
    None => ()
  }
  @signals.start_batch()
  p.more.set([..p.more.untracked(), { n: p.steps_made, x, from, gone }])
  presented_told()
  @signals.end_batch()
}

///|
/// The last page of sheet `p` taken off, back to the one before, where it is past its first: what it held let go of.
/// Whether one was.
fn panel_pop(p : Presented) -> Bool {
  let more = p.more.untracked()
  guard p.open && more.length() > 0 else { return false }
  let last = more[more.length() - 1]
  // (how tall it stands now, for the page before to set out from: sheet_node's `stood`)
  match p.stands_now {
    Some(f) => p.stands = f()
    None => ()
  }
  p.more.set(more[:more.length() - 1].to_owned())
  (last.gone)()
  true
}

///|
/// What `p` holds let go of as it closes unsaid: its pages', the last first, then its own.
fn gone_all(p : Presented) -> Unit {
  for pg in p.more.untracked().rev() {
    (pg.gone)()
  }
  (p.gone)()
}

///|
/// Back from `p`, a step further in from a panel (`under`): `p` closes unsaid (what it holds let go of), and the panel
/// it came from is presented again as it was presented (on a sheet, in `p`'s place), what that one came from under it
/// still. Whether it went back so.
fn back_under(p : Presented) -> Bool {
  guard p.under is Some(u) && p.open else { return false }
  guard presented_now.search_by(fn(q) { q.serial == p.serial }) is Some(i) else { return false }
  let closing = presented_now[i:].to_owned().filter(fn(q) { q.open && !q.ended }).rev()
  // (closed and the one before presented as one change: what draws `p` going finds that one in its place already)
  @signals.start_batch()
  close_from(i)
  for q in closing {
    q.ended = true
    gone_all(q)
  }
  let before = presented_count.val
  present(u.shows, u.from, gone=u.gone)
  match presented_now.last() {
    Some(q) if presented_count.val > before => {
      q.under = u.under
      // (the pages it had past its first, with it)
      q.steps_made = u.steps_made
      q.more.set(u.more.untracked())
    }
    _ => ()
  }
  @signals.end_batch()
  true
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
/// How tall the topmost sheet open over the one presented as `serial` is, while it is open and one is (present_sheet's
/// covered, its `over`'s height): None otherwise.
fn sheet_over(serial : Int) -> Double? {
  presented_said.get() |> ignore
  match presented_now.search_by(fn(q) { q.serial == serial }) {
    Some(i) if presented_now[i].open =>
      presented_now[i + 1:].iter().filter(fn(q) { q.open && how_of(q.shows, q.from, true) == AsSheet }).last().map(fn(q) {
        q.sheet_h.get()
      })
    _ => None
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
/// Whether the one presented in sheet `p`'s place (`taken_by`) is a sheet too (the host's, present_sheet, or the
/// tree's, sheet_node), so in its place indeed: `p` is drawn no more.
fn taken_as_sheet(p : Presented) -> Bool {
  p.taken_by != 0 &&
  presented_now.iter().any(fn(q) {
    q.serial == p.taken_by && q.in_place is Some(_) && how_of(q.shows, q.from, true) == AsSheet
  })
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
  // a sheet on Small, the web's otherwise (rule 3): by the screen, never the hand
  let sheet = layout(ww) is Small
  let gone : Array[Int] = []
  // (sheets closing at once, one pushed up under another (a confirm's 删除 closing what it was asked from): all as far
  // as the furthest of them goes, sinking as one, none over another on their way)
  let sinks = if sheet {
    presented_now.fold(init=0.0, fn(most, q) {
      if q.open || how_of(q.shows, q.from, true) != AsSheet {
        most
      } else {
        @signals.untracked(fn() { dmax(most, q.sheet_h.get() + q.recede.get(c) * q.pushed.get()) })
      }
    })
  } else {
    0.0
  }
  for i, p in presented_now.copy() {
    p.sinks = sinks
    // (closed and drawn going from here on: what is presented later is no more in its place)
    p.closed_now = false
    // (a sheet another took the place of, that one a sheet here too: drawn no more from then, that one there)
    if sheet && !p.open && p.stands > 0.0 && taken_as_sheet(p) {
      gone.push(p.serial)
      continue
    }
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
          p.pushed.set(push_of(q.sheet_h.untracked()))
        None => ()
      }
    }
    // (one closing goes from where it is: pushed up still where it closes with the one over it, both going down; where
    // the one over it closed first that same moment, held where it had got to as it closes too)
    if !p.open && !p.recede.over(c) {
      p.recede.snap(c, @signals.untracked(fn() { p.recede.get(c) }))
    }
    if p.open && covered != p.receded {
      p.receded = covered
      let to = if covered { 1.0 } else { 0.0 }
      if sheet {
        let way = dmax(p.pushed.untracked(), 1.0)
        p.recede.animate(c, to, @motion.moved(points=way))
      } else {
        // (dimmed as a dialog's ground comes and goes)
        p.recede.animate(c, to, @motion.tween(confirm_ground_ms, ease=if covered { Out } else { Leave }))
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
        c.with_dismissed(fn(why) { dismissed_now(p.serial, back=why is (Back | Escape)) }, fn() {
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
      c.tell("sf-present/gone/\{p.serial}", fn() { gone_all(p) })
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
      // (a menu's levels the same)
      match p.levels {
        Some(nav) if gone.contains(p.serial) => for st in nav.pages().rev() { (st.left)() }
        _ => ()
      }
    }
    for serial in gone {
      presented_items_said.remove(serial)
      // (gone with none in its place: what led to it leads nowhere)
      if !took_place.contains(serial) {
        let mut end = serial
        while true {
          match took_place.iter().find_first(fn(e) { e.1 == end }) {
            Some((from, _)) => {
              took_place.remove(from)
              end = from
            }
            None => break
          }
        }
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
    (false, Confirm(_, _, _, _, _, _) | Ask(_, _, _, _, _, _, _, _)) => AsDialog
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
  // (what the window's tree draws: its node's, open as said, drawn till its way out is over: presented_node.mbt)
  if tree_draws(p, sheet) {
    p.stands = 0.0
    return (p.open, p.open || tree_presented.contains(p.serial))
  }
  if sheet {
    return present_sheet(c, key, p)
  }
  p.stands = 0.0
  // (what is left of the web's here: a panel the tree does not draw yet, one that goes in steps or as wide as what it
  // holds)
  match p.shows {
    Panel(x) if p.from == Unanchored || x.form => panel_centred(c, key, p, x)
    Panel(x) => panel_popover(c, key, p, x)
    _ => (p.open, false)
  }
}

///|
/// What chosen or said in `p` does: `p` closes (and what is over it), then `f` goes on, at once (as it is chosen: its
/// handler's, outside any build).
fn done_with(p : Presented, f : () -> Unit) -> Unit {
  p.ended = true
  p.chosen = true
  match presented_now.search_by(fn(q) { q.serial == p.serial }) {
    // (one closed already (the hand's, going): what was opened over it since is not its, as close_from_serial's)
    Some(i) if presented_now[i].open => close_from(i)
    _ => ()
  }
  // (on a sheet, what `f` presents comes in its place, a menu's menu as a level of it: present)
  f()
}

///|
/// A menu (`title`, `items`, `gone` as menu's) presented by what was chosen in menu `p` on a sheet: a level of `p`, in
/// the same sheet (a row held and its 分享…: the menu sank as the next rose across it, the scrim gone and back, and back
/// closed both). `p`, closed as it was chosen in, is open again, what opened it marked still; back from the level is
/// back to the one before.
fn menu_level(p : Presented, title : String, items : Array[MenuItem?], gone : () -> Unit) -> Unit {
  p.open = true
  p.closed_now = false
  p.ended = false
  p.chosen = false
  let level = fn(n : Int, title : String, items : Array[MenuItem?], gone : () -> Unit) -> PanelStep {
    {
      n,
      title,
      description: "",
      body: fn(c, _) { menu_rows(c, "sf-present/\{n}", p, items) },
      foot: None,
      left: fn() {
        if !p.chosen {
          gone()
        }
      },
      count: "",
      on_back: None,
      live: None,
    }
  }
  let nav = match p.levels {
    Some(nav) => nav
    None => {
      let (own_title, own) = match p.shows {
        Menu(own, own_title, _) => (own_title, own)
        _ => ("", [])
      }
      let nav = @ui.Nav::new(level(0, own_title, own, fn() {  }), on_leave=fn(s) { (s.left)() })
      p.levels = Some(nav)
      nav
    }
  }
  p.steps_made += 1
  nav.push(level(p.steps_made, title, items, gone))
  presented_told()
}

///|
/// `p` closed by what it holds, nothing more done (its close button, its back).
fn closed_by(p : Presented) -> Unit {
  done_with(p, fn() {  })
}

///|
/// The box opened by and the rectangle to put a small panel beside (`at`): what opened it, or the window's middle a
/// third down when nothing did.
fn anchor_of(c : @ui.Ctx, from : Anchor) -> (Int, (Double, Double, Double, Double)?) {
  match from {
    Of(id) => (id, None)
    // (a node of the window's tree: where it was placed last, as an old box's is read where it was drawn)
    Node(v) => (0, Some(v.placed_window_now()))
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
/// A small panel's width beside what opened it, by default (parts.css.ts popover: 280, and what its rows' words came
/// further in by from their grounds when that went from 8 to text_in's 16, so they keep the room they had: a station's
/// row its tags, 2026-11-03).
pub let panel_w : Double = 280.0 + 2.0 * (text_in - corner_inset)

///|
/// What a pick's list holds at most before it scrolls in a small panel (the web's chooser: 320).
pub let pick_list_most : Double = 320.0

///|
/// The choices whose words or note hold every word of `query` (case aside), in their order; all of them for none.
fn pick_found(choices : Array[Choice], query : String) -> Array[Choice] {
  let words = query.split(" ").filter(fn(w) { !w.is_empty() }).map(fn(w) { w.to_owned() }).collect()
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
/// A small panel beside what opened it (parts.tsx's: @sf.small_panel, PanelHead), what is at its foot in its foot
/// corner (panel_corner_foot); as tall as `tall` of the window, what it holds takes what the foot leaves. Within the
/// window (@kit.in_room: flipped, else moved over what opened it, it is made shorter only past the window's height),
/// what it holds then scrolling between its title and its foot.
fn panel_popover(c : @ui.Ctx, key : String, p : Presented, x : PanelOf) -> (Bool, Bool) {
  let (anchor, at) = anchor_of(c, p.from)
  let close = fn() { closed_by(p) }
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
      if title != "" && !x.heads_itself {
        panel_head(c, title)
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
          let at = if x.ruled { panel_corner_foot().then(@ui.style(pt=room(@ui.capsule_in(r_menu, button_height())))) } else { panel_corner_foot() }
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
  let close = fn() { closed_by(p) }
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
  words_in_now.val = panel_words - dialog_pad
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
      rows_out.val = panel_words - panel_card_in
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
        measured_body(c, p.serial, id, @ui.style(w=Full, h=Fixed(h)), fn() { draw_panel_body(x, c, close, keyed=p) }) |> ignore
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
    on_close=close,
    step~,
    column_in=panel_words - dialog_pad,
    scrim?=scrim_of(p, false),
    veil=p.recede,
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
  let column = panel_words - dialog_pad
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
    on_close=close,
    column_in=column,
    bare=true,
    on_escape=fn() { steps_escape(p) },
    scrim?=scrim_of(p, false),
    veil=p.recede,
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
    rows_out.val = panel_words - panel_card_in
    words_in_now.val = 0.0
    column_given.val = true
    column_in_now.val = words
    if x.tall > 0.0 && !x.form {
      // (a share of the window tall, as a dialog that goes in no steps has it (panel_centred): each step that tall,
      // or as tall as what it holds where its lists say so, laid out in it)
      let (_, wh) = c.window_size()
      let id = c.id("sf-present/capped/\{p.serial}/\{s.n}")
      let share = x.tall * wh - dialog_frame_h
      let h = match capped_want(c, p.serial, id) {
        Some(want) => dmin(want, share)
        None => share
      }
      measured_body(c, p.serial, id, @ui.style(w=Full, h=Fixed(h)), fn() { draw_panel_body(x, c, close, keyed=p) }) |> ignore
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
/// A stage (stage_node): what it holds over its buttons, stage_gap apart, each in the stage's middle.
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
/// `p`'s field (`key`'s editor) given the keyboard's focus as it opens, until it has it once (what it opened over
/// letting go of the focus as it goes, a frame later, does not take it away); after that the person's. Closed by
/// what it holds, the field lets go of it (field_let_go).
fn focus_once(c : @ui.Ctx, p : Presented, key : String) -> Unit {
  // (closed, as the old frame builds it closed: its field let go of, field_let_go)
  if !p.open {
    field_let_go(p)
    return
  }
  if p.focused {
    return
  }
  p.field_id = c.id(key)
  if c.has_focus(c.id(key)) {
    p.focused = true
  } else {
    c.focus_editor(key)
  }
}

///|
/// `p` closed: its field (focus_once's, a sheet's search) lets go of the keyboard's focus if it still has it, the
/// keyboard going down, and none gives it back (Ctx::blur). Asked as it closes, where each way of drawing it closes it:
/// as the old frame builds it closed (focus_once, a sheet's search: after a close that gave the focus back already,
/// Escape's, nothing to let go), and, drawn by the window's tree, as what it holds says it (its `done`: before its
/// layer gives the focus back and before what it says goes on, what that does with the focus its own) or its close
/// button closes it (built before what it holds, which the old frame builds closed in that build: panel_centred_node).
fn field_let_go(p : Presented) -> Unit {
  let c = @ui.current()
  if p.field_id != 0 && c.has_focus(p.field_id) {
    c.blur()
  }
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
/// What a choice is at now at its row's end (a word or two: 当前, 离线; 13, muted).
// kept across runs: a value (no field of it changes)
let pick_value : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Muted, wrap=false)

///|
/// How much of the window a sheet takes at most: nearly all of it, up to just under the status bar (Sheet.kt's
/// largest detent), what it holds past that scrolling in it; and a long pick's (the run picker's: 66%). A confirm and a
/// question are as tall as what they hold, their buttons straight under their words (the person's 2026-11-02: 「为啥弹出
/// 的面板按钮跑那么高」, under a share of the window, PageParts.kt's 36% and 42%, they stood high over empty room).
pub let sheet_most : Double = 0.94

///|
let sheet_long_pick : Double = 0.66

///|
/// The window height in force while building what a sheet holds (0 outside a sheet).
// kept across runs: put back by presenters_reset
let sheet_win_h : Ref[Double] = Ref(0.0)

///|
/// The height of the window for what a sheet holds (`present_sheet`, `sheet_node`): the screen's full height while no
/// field in the sheet has the focus, or the room over the soft keyboard while one does. Outside a sheet, `c.window_size().1`.
pub fn sheet_window_h(c : @ui.Ctx) -> Double {
  if sheet_win_h.val > 0.0 {
    sheet_win_h.val
  } else {
    c.window_size().1
  }
}

///|
/// `p` as a sheet: as tall as what it shows (measured as it is laid out), or its share of the window; the scrim (black
/// at 28%) closing it when tapped, back, Escape, its top dragged down. Whether it is open, and whether it is drawn.
fn present_sheet(c : @ui.Ctx, key : String, p : Presented) -> (Bool, Bool) {
  let sheet_id = c.id(key)
  let now_open = p.open && !c.will_dismiss(sheet_id)
  let in_ime = now_open && (c.focused_editor_in_layer(sheet_id) || (p.in_ime && c.ime_inset() > 0.0))
  let wh = if now_open {
    p.in_ime = in_ime
    p.win_h = c.window_size().1 + (if in_ime { 0.0 } else { c.ime_inset() })
    p.win_h
  } else if p.win_h > 0.0 {
    p.win_h
  } else {
    c.window_size().1 + c.ime_inset()
  }
  // what it holds, as tall as this frame lays it out (read back: laid out another height, the frame is built again),
  // so the sheet is as tall as that in the frame it shows, and with it as it changes: placed by its size, not chased
  // to the size the frame before measured (sf/motion.mbt)
  let fit = c.id("sf-present/fit/\{p.serial}")
  let natural = match c.laid_size(fit) {
    Some((_, h)) => Some(h)
    None => None
  }
  // a panel taller than a sheet's most: the sheet that tall while taller, what it holds scrolling in it (as a dialog's
  // body does), its foot in reach; un-capped again when the window grows back
  if natural is Some(m) {
    p.natural_h = m
  }
  let over = match natural {
    Some(m) => m > wh * sheet_most
    None => p.natural_h > wh * sheet_most
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
      // (dimmed as it is drawn, not built again as it goes: built while it dims or comes back, till its declared end)
      if p.recede.target() > 0.0 || !p.recede.over(c) {
        c.layer(fn() {
          let v = c.box(style=sheet_veil_at, fn() {  })
          c.bg_by(v, fn() { @ui.alpha(sheet_scrim, dmax(0.0, p.recede.get(c))) })
        })
        |> ignore
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
  let on_escape = if p.steps is Some(_) {
    Some(fn() { steps_escape(p) })
  } else if p.levels is Some(nav) {
    // (in a menu gone a level deeper: back a level)
    Some(fn() { nav.depth() > 1 && nav.pop() })
  } else {
    None
  }
  // (dimming what is under it only where nothing under it does: scrim_owner; pushed up out of the way of a sheet over
  // it, as far as it has gone, closing from there)
  let scrim = scrim_of(p, true).unwrap_or(sheet_scrim)
  let r = @kit.sheet(c, key, p.open, h~, detents=if grows { sheet_grows_to } else { [] }, scrim~, look~, on_escape?, raised=p.recede.get(c) * p.pushed.get(), sinks=p.sinks, in_place=p.in_place.unwrap_or(-1.0), fn() {
    let prev_wh = sheet_win_h.val
    sheet_win_h.val = wh
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
    sheet_win_h.val = prev_wh
  })
  // what it comes to, for scripted runs (e2e: a sheet opened and closed by dragging)
  match r.dragged {
    Some(DraggedClosed) => @hostapi.log("SHEET dragged closed")
    Some(DraggedBack) => @hostapi.log("SHEET dragged back")
    Some(DraggedTo(f)) => @hostapi.log(if f > 0.72 { "SHEET dragged to 94%" } else { "SHEET dragged to 55%" })
    None => ()
  }
  // (how tall it stands, for what comes in its place: present)
  p.stands = r.stands
  (r.open && p.open, r.shown)
}

///|
/// Where a long list's sheet settles as it is dragged (and nearly all of the window).
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
    Menu(items, title, _) =>
      match p.levels {
        // (gone a level deeper: its levels a stack in the sheet, each its title, the first's as it was, a back key
        // before those after it, as tall as the one on top, going there with the slide: a panel's steps')
        Some(nav) =>
          steps_shown(c, p, nav, false, 0.0, fn(s, back) {
            if back is Some(_) {
              step_head(c, "\{key}/\{s.n}", s.title, "", back, sheet_title_row, sheet_title_words, c.text_size(Title).1)
            } else if s.title != "" {
              sheet_title(c, s.title)
            }
            (s.body)(c, fn() { closed_by(p) })
          })
        None => {
          // (how tall it is kept as its first level's: where its way to the next level's height sets out, steps_shown)
          let own = c.box(style=full_width, fn() {
            if title != "" {
              sheet_title(c, title)
            }
            menu_rows(c, key, p, items)
          })
          @motion.measure(c, own, step_key(p, 0))
        }
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
          // (its field, let go of as it closes: field_let_go)
          p.field_id = c.id(key + "/search")
          if !p.open {
            field_let_go(p)
          }
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
          sheet_row(c, key + "/" + x.key, x.label, note=x.note, value=x.value, icon=x.icon, mark?=x.mark, on=x.key == chosen, on_press=fn() {
            done_with(p, fn() { choose(x.key) })
          })
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
      let close = fn() { closed_by(p) }
      match p.steps {
        // (one that goes in steps: each its own title, what it holds and its foot, sliding in over the one before)
        Some(nav) =>
          // (one a share of the window tall: its steps fill what the sheet leaves them, each laid out in it)
          steps_shown(c, p, nav, scrolls || (x.tall > 0.0 && !x.form), 0.0, fn(s, back) {
            let (title, count, description) = words_of_step(s)
            sheet_step(c, key, p, { ..x, body: s.body, foot: s.foot }, title, description, close, scrolls, back?, count~)
          })
        None => {
          let (title, _, description) = match x.live {
            Some(f) => f()
            None => (x.title, "", x.description)
          }
          // (a step further in from a panel: its back key before its title, back to that one)
          let back = if p.under is Some(_) { Some(fn() { back_under(p) |> ignore }) } else { None }
          sheet_step(c, key, p, x, title, description, close, scrolls, back?)
        }
      }
    }
    Confirm(title, words, warning, action, danger, run) => {
      sheet_title(c, title)
      c.box(style=sheet_words_at, fn() {
        c.text(words, style=sheet_lead) |> ignore
        if warning != "" {
          c.text(warning, style=sheet_warning) |> ignore
        }
        c.box(style=sheet_actions, fn() {
          button(c, t("common.cancel"), key=key + "/cancel", on_press=fn() { close_from_serial(p.serial) }) |> ignore
          button(c, action, key=key + "/go", tone=if danger { DangerSolid } else { Primary }, on_press=fn() {
            done_with(p, run)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
    Ask(title, value, placeholder, action, hint, secret, empty, run) => {
      sheet_title(c, title)
      c.box(style=sheet_words_at, fn() {
        // (said, by Enter or its action: what it says done with its words as they are then)
        let say = fn(typed : String) {
          let line = typed.trim(chars=" \t\n").to_owned()
          if ask_can(line, value, empty) {
            done_with(p, fn() { run(line) })
          }
        }
        let f = @kit.text_field(
          c,
          key + "/line",
          placeholder~,
          secret~,
          size=text_scale.lg.0,
          line=text_scale.lg.1,
          look=field_look,
          field=p.line,
          on_submit=say,
        )
        focus_once(c, p, key + "/line")
        let words = f.text.trim(chars=" \t\n").to_owned()
        if hint != "" {
          c.text(hint, style=sheet_hint) |> ignore
        }
        let can = ask_can(words, value, empty)
        c.box(style=sheet_actions, fn() {
          button(c, t("common.cancel"), key=key + "/cancel", on_press=fn() { close_from_serial(p.serial) }) |> ignore
          button(c, action, key=key + "/go", tone=Primary, disabled=!can, on_press=fn() { say(p.line.text()) }) |> ignore
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
  // (a step further in whose title's row is its own (an agent's mark, name and where it stands): that row after the
  // back key, in the title's place, what it holds not drawing it again: title_row_given)
  let own_row = match (back, x.title_row) {
    (Some(b), Some(row)) => {
      c.box(style=sheet_title_row.then(step_head_gap), fn() {
        c.box(style=step_back_out, fn() {
          icon_button(c, "chevron-left", key=key + "/back", size=step_back_side, round=true, label=t("common.back"), on_press=fn() {
            b()
          }) |> ignore
        })
        |> ignore
        c.box(style=sheet_row_words_at, fn() { row(c) }) |> ignore
      })
      |> ignore
      true
    }
    _ => false
  }
  if own_row {
    ()
  } else if back is Some(_) || count != "" {
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
    rows_out.val = dmax(0.0, panel_sides_in.val - panel_card_in)
    words_in_now.val = if x.tall > 0.0 {
      sheet_panel_sides
    } else if pressed {
      sheet_panel_sides - sheet_row_sides
    } else {
      0.0
    }
    rule_over_now.val = if x.ruled && x.foot is Some(_) { sheet_rule_over } else { 0.0 }
    let row_was = title_row_given.val
    title_row_given.val = own_row
    // (as tall as what it holds, what would scroll in itself laid out whole, as a dialog's body: panel_whole)
    if capped {
      draw_panel_body(x, c, close)
    } else {
      panel_whole_now.val += 1
      draw_panel_body(x, c, close)
      panel_whole_now.val -= 1
    }
    title_row_given.val = row_was
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
      measured_body(c, p.serial, sheet_capped.val, room, body) |> ignore
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
  let key_of = fn(s : PanelStep) { step_key(p, s.n) }
  let top = nav.top()
  // (a menu gone to its next level, its first drawn outside a stack till then: as tall as that was laid out, its way
  // to the level's height from there)
  if p.step_h_of < 0 && top.n != 0 {
    match @motion.measured(c, step_key(p, 0)) {
      Some(h) => {
        p.step_h.snap(c, h)
        p.step_h_of = 0
      }
      None => ()
    }
  }
  // (its height on its way with the slide: as long as the slide's way across the panel is far)
  let slide = @motion.moved(over=c.width)
  match @motion.measured(c, key_of(top)) {
    Some(h) =>
      if p.step_h_of < 0 {
        p.step_h.snap(c, h)
        p.step_h_of = top.n
      } else if p.step_h_of != top.n {
        // (another step come or gone back to: its height reached with its slide)
        p.step_h.animate(c, h, slide)
        p.step_h_of = top.n
      } else if p.step_h.target() != h {
        // (what the step holds changed: that height at once, or, before its slide's declared end, where it goes on its
        // way there)
        if p.step_h.over(c) {
          p.step_h.snap(c, h)
        } else {
          p.step_h.animate(c, h, slide)
        }
      }
    None => ()
  }
  let tall = if fills {
    sheet_grows
  } else if p.step_h_of < 0 {
    full_width
  } else {
    @ui.style(w=Full, h=Fixed(p.step_h.get(c)))
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
      // (filling what holds the stack, each step fills it too: what it holds laid out in that room)
      let page = if fills { @ui.style(w=Full, h=Full, px=room(out)) } else { @ui.style(w=Full, px=room(out)) }
      let i = c.box(style=page, fn() { draw(s, back) })
      @motion.measure(c, i, key_of(s))
      steps_drawn_now.val = was
    })
    |> ignore
  })
  |> ignore
}

///|
/// What step `n` of `p` (a panel's that goes in steps, a menu's levels) is measured as, as it is laid out.
fn step_key(p : Presented, n : Int) -> String {
  "sf-present/step/\{p.serial}/\{n}"
}

///|
/// A menu's rows in a sheet (`items`: None a line between, a heading a title's): one pressed, the sheet `p` closes and
/// what it does goes on (done_with).
fn menu_rows(c : @ui.Ctx, key : String, p : Presented, items : Array[MenuItem?]) -> Unit {
  c.box(style=sheet_rows, fn() {
    for i, x in items {
      match x {
        None => c.box(style=sheet_rule, fn() {  }) |> ignore
        Some(item) =>
          if item.heading {
            sheet_title(c, item.label)
          } else {
            sheet_row(
              c,
              key + "/" + i.to_string(),
              item.label,
              icon=item.icon,
              on=item.chosen == Some(true),
              danger=item.danger,
              disabled=item.disabled,
              on_press=fn() { done_with(p, item.select) },
            )
          }
      }
    }
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
          icon_button(c, "chevron-left", key=key + "/back", size=step_back_side, round=true, label=t("common.back"), on_press=fn() {
            f()
          }) |> ignore
        })
        |> ignore
      None => ()
    }
    // 
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
/// A step's back key before a title's row of its own: as far out of the words' line as before a title (step_head).
// kept across runs: a value (no field of it changes)
let step_back_out : @ui.Style = @ui.style(ml=room(-step_back_in))

///|
/// A step's back key before a dialog's title in its head's row (dialog_head, its parts S3 apart): as far out of the
/// words' line, its chevron as near the title as a step's head has it (step_head_gap).
// kept across runs: a value (no field of it changes)
let dialog_back_at : @ui.Style = @ui.style(ml=room(-step_back_in), mr=room(@ui.Space::px(S1) - @ui.Space::px(S3)))

///|
// kept across runs: a value (no field of it changes)
let step_head_gap : @ui.Style = @ui.css("gap=S1")

///|
/// The window's height (what a long pick's list is capped by before the sheet's room shrinks it).
fn wh_of(c : @ui.Ctx) -> Double {
  sheet_window_h(c)
}

///|
/// A sheet's title: 17 bold, on its words' line (sheet_panel_sides in), 4 over and 10 under.
fn sheet_title(c : @ui.Ctx, title : String) -> Unit {
  c.box(style=sheet_title_row, fn() { c.text(title, style=sheet_title_words) |> ignore }) |> ignore
}

///|
/// A row of a sheet: its icon, its words (15), the note under them
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
  on_press~ : () -> Unit,
) -> Unit {
  let th = theme()
  let id = c.id(key)
  if !disabled {
    c.on_press(id, on_press)
  }
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
let sheet_rows : @ui.Style = @ui.style(w=Full, px=room(sheet_row_sides), pb=S6)

///|
/// How far in from a sheet's sides its rows are (sheet_rows' px).
let sheet_row_sides : Double = panel_card_in

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
let sheet_search_at : @ui.Style = @ui.style(w=Full, px=room(sheet_row_sides), pb=S2_5)

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
let sheet_held : @ui.Style = @ui.style(w=Full, px=room(sheet_row_sides), pb=S6)

///|
/// The same with a foot under it (the foot's room under it, not its own).
// kept across runs: a value (no field of it changes)
let sheet_held_sides : @ui.Style = @ui.style(w=Full, px=room(sheet_row_sides))

///|
/// How far in from a sheet's sides what a panel opened by nothing holds is (sheet_panel's px).
let sheet_panel_sides : Double = panel_words

///|
/// A confirm's and a question's words (ask): 20 in, 10 apart.
// kept across runs: a value (no field of it changes)
let sheet_words_at : @ui.Style = @ui.style(w=Full, px=room(sheet_panel_sides), gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let sheet_lead : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Muted)

///|
// kept across runs: a value (no field of it changes)
let sheet_warning : @ui.TextStyle = @ui.text_style(size=Meta, leading=L6, color=Danger)

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
