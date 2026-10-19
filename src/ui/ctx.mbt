// The per-window context: views build a fresh tree into it every frame,
// widget state persists in maps keyed by widget id, and input arrives from
// the host between frames.

///|
struct ListState {
  mut anchor : Int
  mut anchor_off : Double
  heights : Array[Double]
  // the rows' heights (est for those not measured) summed as a Fenwick
  // tree (1-based: sums[i] holds rows i - lowbit(i) until i): what is
  // above a row and the whole, without adding every row up (list.mbt)
  sums : Array[Double]
  est : Double
  mut count : Int
  mut vp_h : Double
  mut vel : Double
  mut at_end : Bool
  stick_end : Bool
  mut last_scroll : Double
  mut pending : Double
  // how to build a row, and the id scope it is built in
  mut row : (Int) -> Unit
  mut seed : Int
  // rows in view after the last layout, first to last (-1 when none)
  mut vis_first : Int
  mut vis_last : Int
  // the page its state belongs to (Ctx::own), which its rows' states do too
  mut owner : Int
  // how far the last row's bottom was below the view's after the last
  // layout (1e9 when it was not laid out)
  mut below : Double
  // gliding to its end (Ctx::list_to_end), until there or scrolled
  mut glide : Bool
  // a fling (scroll.mbt): its kind (0 the desktop's, coasting on `vel`; 1
  // Android's spline; 2 iOS's deceleration), its velocity at the start (px
  // per ms, positive down the list), when it started (-1: at the next
  // frame), the spline's distance and duration, how far it has gone
  mut fling : Int
  mut fling_v : Double
  mut fling_t0 : Double
  mut fling_dist : Double
  mut fling_dur : Double
  mut fling_done : Double
  // what a finger scrolled since the last layout, and whether one drags it
  mut drag_pending : Double
  mut held : Bool
  // past an end: how far (Android: in the view's heights; iOS: points,
  // pulled while held, shown while springing back), at which end (1 the
  // top, -1 the bottom, 0 none), held (1) or springing back (2), its
  // velocity outward (Android: pixels per second; iOS: points per ms), the
  // spring's last step
  mut over : Double
  mut over_edge : Int
  mut over_state : Int
  mut over_v : Double
  mut over_t : Double
  // a wheel's notches not yet scrolled by (eased in over the next frames: Ctx::ease_list)
  mut ease : Double
  // the size its rows are built for: the Ctx's as the list was (Ctx::sized), its rows built later, as it is laid out
  mut vw : Double
  mut vh : Double
  // whether its rows' words are picked with the pointer (Ctx::selectable), as where the list was
  mut sel : Bool
}

///|
struct EditorState {
  mut text : String
  mut caret : Int
  mut anchor : Int
  mut marked : String
  mut msel_a : Int
  mut msel_b : Int
  mut blink0 : Double
  mut tl : TextLayout?
  mut ox : Double
  mut oy : Double
  mut submitted : String?
  mut pref_x : Double
  /// how far its words are scrolled up (taller than the field: the caret's line kept in view)
  mut scroll : Double
  /// what was put in at once that was `limit` characters or more, not put in (a long paste the app takes instead)
  mut pasted : String?
  mut limit : Int
  /// Enter sends (the words go to `submitted`); else it is a new line
  mut enter_sends : Bool
  /// its look, as the last frame said it: the line's height (0: the font's), the words', the placeholder's, the
  /// caret's and the selection's colours
  mut line : Double
  mut color : Int64
  mut ph_color : Int64
  mut caret_color : Int64
  mut sel_color : Int64
  /// what it holds is a secret (a key, a token, a password): drawn as dots, never copied or cut out of it
  mut secret : Bool
}

///|
struct Spring {
  mut x : Double
  mut v : Double
  mut target : Double
  mut frame : Int
}

///|
pub struct Ctx {
  nodes : Array[Node]
  mut count : Int
  mut cur : Int
  mut id_seed : Int
  id_stack : Array[Int]
  mut width : Double
  mut height : Double
  mut scale : Double
  mut now : Double
  mut dt : Double
  mut last_now : Double
  mut frame_no : Int
  // the layout epoch: when it moves on, nothing laid out before is reused
  // (Ctx::flex_tree)
  mut epoch : Int
  mut wants_frame : Bool
  mut wake_at : Double
  // hit targets of the last frame, in paint order, and those being collected
  mut hit_ids : Array[Int]
  mut hit_rects : Array[Double]
  mut next_hit_ids : Array[Int]
  mut next_hit_rects : Array[Double]
  mut scroll_ids : Array[Int]
  mut scroll_rects : Array[Double]
  mut next_scroll_ids : Array[Int]
  mut next_scroll_rects : Array[Double]
  // pointer
  mut px : Double
  mut py : Double
  mut down : Bool
  mut hover : Int
  mut active : Int
  mut focus : Int
  clicked : Array[Int]
  mut drag_scroll : Int
  mut dragging : Bool
  mut press_x : Double
  /// when the press under way went down (ms), and the press a link's hold was last told of
  mut press_at : Double
  mut held_told : Double
  /// a tap this frame (a press let go without dragging, not taken by the app: Ctx::tapped_anywhere), and the press
  /// the app took (Ctx::take_press)
  mut tapped : (Double, Double)?
  mut taken_at : Double
  mut press_y : Double
  mut last_y : Double
  mut last_x : Double
  mut vel_x : Double
  mut last_t : Double
  mut vel : Double
  mut editor_drag : Bool
  // persistent widget state
  lists : Map[Int, ListState]
  editors : Map[Int, EditorState]
  springs : Map[Int, Spring]
  // the page being built (a page of a Nav, by its serial; 0 none), and the
  // ids of the state each page's widgets made, forgotten with the page
  mut owner : Int
  owned : Map[Int, Array[Int]]
  // back: where it goes this frame (the Nav drawn that can go back) and the
  // node it is drawn in, as the last frame had them; whether the host was
  // told that the app takes back; a finger on the left edge (1: there, 2:
  // moving the page)
  mut back : ((Int, Double, Double, Double) -> Unit)?
  mut back_node : Int
  mut back_edge : Double
  mut back_next : ((Int, Double, Double, Double) -> Unit)?
  mut back_node_next : Int
  mut back_edge_next : Double
  mut back_told : Bool
  mut edge : Int
  // the theme and the direction in force where the view builds (theme.mbt)
  mut theme : Theme
  mut direction : Direction
  // what the widgets built this frame say they are (semantics.mbt), and how deep in a part hidden from it the view
  // builds; the actions asked of them (by the host's accessibility, a test) for the next frame, and this frame's
  sems : Array[Sem]
  mut sem_hide : Int
  sem_hidden : Array[(Int, Int)]
  asked_actions : Array[(Int, Action)]
  actions : Array[(Int, Action)]
  // the keyboard's focus beyond a field's (focus.mbt): whether it shows (it came by the keyboard), what had it as the
  // frame started; what can take it, as this frame builds it and as the last one did; roving groups' state, and the
  // group being built
  mut focus_visible : Bool
  mut focus_roved : Bool
  mut focus_before : Int
  mut focusables : Array[Focusable]
  mut last_focusables : Array[Focusable]
  groups : Map[Int, Group]
  mut group_cur : Int
  // what lies over the page (overlay.mbt): its layers as this frame builds them and as the last one did, the one
  // being built, the dismissals asked for since, where a press went down since the last frame
  mut layers : Array[Layer]
  mut last_layers : Array[Layer]
  mut layer_cur : Int
  dismissals : Map[Int, Dismiss]
  layer_return : Map[Int, Int]
  mut press_down : (Double, Double)?
  // output
  mut inst : FixedArray[Double]
  mut ninst : Int
  mut ime_sig : String
  // stats
  mut t_build : Double
  mut t_layout : Double
  mut t_paint : Double
  mut t_present : Double
  mut bench_list : Int
}

///|
fn Ctx::new() -> Ctx {
  {
    nodes: [],
    count: 0,
    cur: -1,
    id_seed: 17,
    id_stack: [],
    width: 800.0,
    height: 600.0,
    scale: 2.0,
    now: 0.0,
    dt: 16.0,
    last_now: -1.0,
    frame_no: 0,
    epoch: 0,
    wants_frame: false,
    wake_at: -1.0,
    hit_ids: [],
    hit_rects: [],
    next_hit_ids: [],
    next_hit_rects: [],
    scroll_ids: [],
    scroll_rects: [],
    next_scroll_ids: [],
    next_scroll_rects: [],
    px: -1.0,
    py: -1.0,
    down: false,
    hover: 0,
    active: 0,
    focus: 0,
    clicked: [],
    drag_scroll: 0,
    dragging: false,
    press_x: 0.0,
    press_at: -1.0,
    held_told: -1.0,
    tapped: None,
    taken_at: -1.0,
    press_y: 0.0,
    last_y: 0.0,
    last_x: 0.0,
    vel_x: 0.0,
    last_t: 0.0,
    vel: 0.0,
    editor_drag: false,
    lists: Map::new(),
    editors: Map::new(),
    springs: Map::new(),
    owner: 0,
    owned: Map::new(),
    back: None,
    back_node: -1,
    back_edge: 20.0,
    back_next: None,
    back_node_next: -1,
    back_edge_next: 20.0,
    back_told: false,
    edge: 0,
    theme: Theme::light(),
    direction: Ltr,
    sems: [],
    sem_hide: 0,
    sem_hidden: [],
    asked_actions: [],
    actions: [],
    focus_visible: false,
    focus_roved: false,
    focus_before: 0,
    focusables: [],
    last_focusables: [],
    groups: Map::new(),
    group_cur: 0,
    layers: [],
    last_layers: [],
    layer_cur: 0,
    dismissals: Map::new(),
    layer_return: Map::new(),
    press_down: None,
    inst: FixedArray::make(24 * 4096, 0.0),
    ninst: 0,
    ime_sig: "",
    t_build: 0.0,
    t_layout: 0.0,
    t_paint: 0.0,
    t_present: 0.0,
    bench_list: 0,
  }
}

// ---------------------------------------------------------------------------
// Ids

///|
fn mix(a : Int, b : Int) -> Int {
  let mut h = a ^ (b * 0x5bd1e995)
  h = h ^ (h >> 15)
  h = h * 0x27d4eb2d
  h = h ^ (h >> 13)
  if h == 0 {
    1
  } else {
    h
  }
}

///|
/// A widget id from a key, unique within the current scope.
pub fn Ctx::id(self : Ctx, key : String) -> Int {
  mix(self.id_seed, key.hash())
}

///|
/// Runs `body` with ids scoped by `key` (rows of a list use their index).
pub fn Ctx::scope(self : Ctx, key : Int, body : () -> Unit) -> Unit {
  self.id_stack.push(self.id_seed)
  self.id_seed = mix(self.id_seed, key + 1)
  body()
  self.id_seed = self.id_stack.pop().unwrap()
}

// ---------------------------------------------------------------------------
// Building

///|
fn Ctx::alloc(self : Ctx, kind : Int) -> Int {
  self.alloc_part(kind, true, true)
}

///|
/// A node of `kind` under the current one; its look and its words reset
/// only when asked: a box sets all of its look, a text all of its words,
/// and only texts, rich text and editors read words (an image only its
/// source, which it sets).
fn Ctx::alloc_part(self : Ctx, kind : Int, look : Bool, words : Bool) -> Int {
  let i = self.count
  if i < self.nodes.length() {
    let n = self.nodes[i]
    n.reset_rest()
    if look {
      n.reset_look()
    }
    if words {
      n.reset_words()
    }
  } else {
    self.nodes.push(Node::new())
  }
  self.count = i + 1
  let n = self.nodes[i]
  n.kind = kind
  n.parent = self.cur
  if self.cur >= 0 {
    let p = self.nodes[self.cur]
    if p.last >= 0 {
      self.nodes[p.last].next = i
    } else {
      p.first = i
    }
    p.last = i
  }
  i
}

///|
fn Ctx::with_parent(self : Ctx, i : Int, body : () -> Unit) -> Unit {
  let saved = self.cur
  self.cur = i
  body()
  self.cur = saved
}

///|
/// A box laying out its children in a row or a column, flexbox style. `notch_r` > 0 cuts a notch into its top edge
/// (its ground, border and glass alike): a circle of that radius about the middle of its top, `notch_y` below the edge
/// (above it when negative), met by the edge through fillets of `notch_fillet` (Bar.kt's notch). `aspect` > 0: its
/// width over its height, the side not said following the other (CSS's aspect-ratio). Built where the direction is
/// right to left (Ctx::rtl), a row runs from the right and its left and right padding swap.
pub fn Ctx::box(
  self : Ctx,
  dir? : Dir = Column,
  w? : Size = Auto,
  h? : Size = Auto,
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  pl? : Double = -1.0,
  pr? : Double = -1.0,
  pt? : Double = -1.0,
  pb? : Double = -1.0,
  gap? : Double = 0.0,
  align? : Align = AStretch,
  justify? : Justify = JStart,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  border? : Double = 0.0,
  border_color? : Int64 = 0L,
  shadow? : Double = 0.0,
  shadow_color? : Int64 = 0x0000002EL,
  shadow_y? : Double = -1.0,
  min_w? : Double = 0.0,
  max_w? : Double = 1.0e9,
  min_h? : Double = 0.0,
  max_h? : Double = 1.0e9,
  clip? : Bool = false,
  tx? : Double = 0.0,
  ty? : Double = 0.0,
  opacity? : Double = 1.0,
  glass? : Glass,
  glass_group? : Bool = false,
  notch_y? : Double = 0.0,
  notch_r? : Double = 0.0,
  notch_fillet? : Double = 0.0,
  aspect? : Double = 0.0,
  id? : Int = 0,
  body : () -> Unit,
) -> Int {
  let i = self.alloc_part(kind_box, false, false)
  let n = self.nodes[i]
  n.dir = dir
  n.rtl = self.direction == Rtl
  n.aspect = aspect
  n.w = w
  n.h = h
  let px = if padx >= 0.0 { padx } else { pad }
  let py = if pady >= 0.0 { pady } else { pad }
  // one side said on its own wins over both sides
  n.pad_l = if pl >= 0.0 { pl } else { px }
  n.pad_r = if pr >= 0.0 { pr } else { px }
  // right to left, the start (left said) is the right
  if n.rtl {
    let l = n.pad_l
    n.pad_l = n.pad_r
    n.pad_r = l
  }
  n.pad_t = if pt >= 0.0 { pt } else { py }
  n.pad_b = if pb >= 0.0 { pb } else { py }
  n.min_w = min_w
  n.max_w = max_w
  n.min_h = min_h
  n.max_h = max_h
  n.shadow_c = shadow_color
  n.shadow_y = shadow_y
  n.gap = gap
  n.align = align
  n.justify = justify
  n.bg = bg
  n.radius = radius
  n.border_w = border
  n.border_c = border_color
  n.shadow = shadow
  n.clip = clip
  n.tx = tx
  n.ty = ty
  n.opacity = opacity
  n.glass = glass
  n.glass_group = glass_group
  n.notch_y = notch_y
  n.notch_r = notch_r
  n.notch_f = notch_fillet
  if id != 0 {
    n.id = id
    n.hit = true
  }
  self.with_parent(i, body)
  i
}

///|
pub fn Ctx::row(
  self : Ctx,
  w? : Size = Auto,
  h? : Size = Auto,
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  gap? : Double = 0.0,
  align? : Align = ACenter,
  justify? : Justify = JStart,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  self.box(
    dir=Row,
    w~,
    h~,
    pad~,
    padx~,
    pady~,
    gap~,
    align~,
    justify~,
    bg~,
    radius~,
    body,
  )
}

///|
pub fn Ctx::column(
  self : Ctx,
  w? : Size = Auto,
  h? : Size = Auto,
  pad? : Double = 0.0,
  padx? : Double = -1.0,
  pady? : Double = -1.0,
  gap? : Double = 0.0,
  align? : Align = AStretch,
  justify? : Justify = JStart,
  bg? : Int64 = 0L,
  radius? : Double = 0.0,
  body : () -> Unit,
) -> Int {
  self.box(
    dir=Column,
    w~,
    h~,
    pad~,
    padx~,
    pady~,
    gap~,
    align~,
    justify~,
    bg~,
    radius~,
    body,
  )
}

///|
/// A column laid over its parent, the whole of it, in front of what the
/// parent holds before it: for bars and menus over a page. Taps go through
/// to what is under it except on what it holds that takes them.
pub fn Ctx::layer(
  self : Ctx,
  pad? : Double = 0.0,
  align? : Align = AStretch,
  body : () -> Unit,
) -> Int {
  let i = self.box(pad~, align~, body)
  self.nodes[i].layer = true
  i
}

///|
pub fn Ctx::spacer(self : Ctx) -> Unit {
  let i = self.alloc_part(kind_box, true, false)
  self.nodes[i].w = Fill(1.0)
  self.nodes[i].h = Fill(1.0)
}

///|
/// Words, in the theme's colour unless `color`.
pub fn Ctx::text(
  self : Ctx,
  s : String,
  size? : Double = 15.0,
  weight? : Int = 400,
  color? : Int64,
  wrap? : Bool = true,
  w? : Size = Auto,
  line? : Double = 0.0,
  center? : Bool = false,
) -> Int {
  let color = color.unwrap_or(self.theme.fg)
  let i = self.alloc_part(kind_text, true, false)
  let n = self.nodes[i]
  n.center = center
  n.line_h = line
  n.text = s
  n.font_size = size
  n.weight = weight
  n.color = color
  n.wrap = wrap
  n.w = w
  i
}

// ---------------------------------------------------------------------------
// Interaction

///|
pub fn Ctx::clicked(self : Ctx, id : Int) -> Bool {
  if self.clicked.contains(id) {
    // what a click changes is drawn by the next frame, wherever it was seen: a list's row is built after the rest of
    // the frame has been, so what it changes there would wait for some other frame (a tap in a reader's text that
    // brings its bars)
    self.wants_frame = true
    true
  } else {
    false
  }
}

///|
pub fn Ctx::hovered(self : Ctx, id : Int) -> Bool {
  self.hover == id
}

///|
pub fn Ctx::pressed(self : Ctx, id : Int) -> Bool {
  self.active == id && self.down
}

///|
pub fn Ctx::request_frame(self : Ctx) -> Unit {
  self.wants_frame = true
}

///|
/// The window's size in logical pixels (w, h), as this frame lays it out: what a dialog is put in the middle of.
pub fn Ctx::window_size(self : Ctx) -> (Double, Double) {
  (self.width, self.height)
}

///|
pub fn Ctx::now(self : Ctx) -> Double {
  self.now
}

///|
pub fn Ctx::frame_ms(self : Ctx) -> Double {
  self.t_build + self.t_layout + self.t_paint
}

///|
pub fn Ctx::present_ms(self : Ctx) -> Double {
  self.t_present
}

///|
fn hit_in(ids : Array[Int], rects : Array[Double], x : Double, y : Double) -> Int {
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= rects[r] && x < rects[r + 2] && y >= rects[r + 1] && y < rects[r + 3] {
      return ids[k]
    }
    k = k - 1
  }
  0
}

///|
/// A value that follows `target` with a spring.
pub fn Ctx::spring(
  self : Ctx,
  key : String,
  target : Double,
  from? : Double,
  stiffness? : Double = 420.0,
  damping? : Double = 32.0,
) -> Double {
  let id = self.id(key)
  let s = match self.springs.get(id) {
    Some(s) => s
    None => {
      let x = match from {
        Some(f) => f
        None => target
      }
      let s = { x, v: 0.0, target, frame: -1 }
      self.springs[id] = s
      self.own(id)
      s
    }
  }
  s.target = target
  if s.frame != self.frame_no {
    s.frame = self.frame_no
    let mut t = dmin(self.dt, 64.0) / 1000.0
    let h = 1.0 / 240.0
    while t > 0.0 {
      let step = dmin(h, t)
      let a = -stiffness * (s.x - s.target) - damping * s.v
      s.v = s.v + a * step
      s.x = s.x + s.v * step
      t = t - step
    }
    if (s.x - s.target).abs() < 0.001 && s.v.abs() < 0.001 {
      s.x = s.target
      s.v = 0.0
    } else {
      self.wants_frame = true
    }
  }
  s.x
}

///|
fn Ctx::wake_at_time(self : Ctx, t : Double) -> Unit {
  if self.wake_at < 0.0 || t < self.wake_at {
    self.wake_at = t
  }
}

///|
/// True when the host wants output that is the same on every run (screenshot
/// comparisons): views leave out clocks and timings.
pub fn Ctx::stable(self : Ctx) -> Bool {
  ignore(self)
  bench.mode < 0
}

///|
/// Where the thing with `id` was drawn last frame (x, y, w, h), as far as it
/// showed: for parts that follow the pointer across them (a slider).
pub fn Ctx::rect_of(self : Ctx, id : Int) -> (Double, Double, Double, Double)? {
  let mut k = self.hit_ids.length() - 1
  while k >= 0 {
    if self.hit_ids[k] == id {
      let r = k * 4
      return Some(
        (
          self.hit_rects[r],
          self.hit_rects[r + 1],
          self.hit_rects[r + 2] - self.hit_rects[r],
          self.hit_rects[r + 3] - self.hit_rects[r + 1],
        ),
      )
    }
    k = k - 1
  }
  None
}

///|
/// The pointer, and whether it is down.
pub fn Ctx::pointer(self : Ctx) -> (Double, Double, Bool) {
  (self.px, self.py, self.down)
}

///|
/// `url` handed to the system: its browser, or the app it belongs to (Android's ACTION_VIEW, macOS's NSWorkspace,
/// iOS's UIApplication, Windows' ShellExecute, the browser's window.open). False when nothing took it.
pub fn Ctx::open_url(self : Ctx, url : String) -> Bool {
  ignore(self)
  h_open_url(url)
}

///|
/// `url` handed to the system, outside a frame (an answer that came between frames): as Ctx::open_url.
pub fn open_url(url : String) -> Bool {
  h_open_url(url)
}

///|
/// Puts `s` on the system's clipboard.
pub fn Ctx::copy_text(self : Ctx, s : String) -> Unit {
  ignore(self)
  h_clipboard_set(s)
}

///|
/// A frame again `ms` from now (for what changes then: words that say
/// "copied" for a while), without frames in between.
pub fn Ctx::wake_in(self : Ctx, ms : Double) -> Unit {
  self.wake_at_time(self.now + dmax(ms, 1.0))
}
