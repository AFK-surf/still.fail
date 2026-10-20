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
  // gliding to its end (Ctx::list_to_end), until there or scrolled: set out at `glide_t0` (+inf: at its next layout)
  // from `glide_l0` px above its end, what is left of it e^(-t/list_glide_ms) of that, at its end at `glide_rest`;
  // how far it was above its end at the last layout
  mut glide : Bool
  mut glide_t0 : Double
  mut glide_l0 : Double
  mut glide_rest : Double
  mut glide_left : Double
  // the frame it was last built in (one not built is shown by nothing: at rest)
  mut built : Int
  // the last scroll to a row asked of it (Ctx::list_scroll_to): the frame, the row and the offset (asked again as the
  // frame is built again, the same: done already)
  mut scroll_asked : (Int, Int, Double)
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
  // velocity outward (Android: pixels per second; iOS: points per ms); going
  // back, its path (scroll_path.mbt)
  mut over : Double
  mut over_edge : Int
  mut over_state : Int
  mut over_v : Double
  mut back : BackPath
  // a wheel's notches eased in (Ctx::ease_list): what they come to all told (0 none), from when, how much of it has
  // come by the last frame, and what it is said to move by (Ctx::moving)
  mut ease : Double
  mut ease_t0 : Double
  mut ease_done : Double
  ease_mover : Mover
  // the size its rows are built for: the Ctx's as the list was (Ctx::sized), its rows built later, as it is laid out
  mut vw : Double
  mut vh : Double
  // whether its rows' words are picked with the pointer (Ctx::selectable), as where the list was
  mut sel : Bool
  // the theme and the direction in force where the list was (Ctx::with_theme, with_direction): its rows, built later,
  // as it is laid out, are built in them, as what is built beside the list is
  mut theme : Theme
  mut direction : Direction
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
  /// the earliest wake asked for this frame that what is shown waits for (not `later`): -1 none
  mut wake_waited : Double
  /// who asked for the next frame first this frame (Ctx::request_frame's caller), and for the wake it waits for
  /// (Ctx::wake_in's): what Tester::assert_idle says of what is left
  mut frame_by : SourceLoc?
  mut wake_by : SourceLoc?
  // hit targets of the last frame, in paint order, and those being collected
  mut hit_ids : Array[Int]
  mut hit_rects : Array[Double]
  mut next_hit_ids : Array[Int]
  mut next_hit_rects : Array[Double]
  // what cut each hit target where it was drawn, 12 numbers each (scene.mbt clip_stack): a press in a corner its
  // rounded clip cut away misses it
  mut hit_clips : Array[Double]
  mut next_hit_clips : Array[Double]
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
  /// what scrolls or is dragged under the press, innermost first (claim.mbt): until one claims it (`claimed`), the
  /// press is none of theirs; `drag_scroll` is the innermost meanwhile
  mut press_chain : Array[Int]
  mut claimed : Bool
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
  springs : Map[Int, SpringPath]
  /// what is said to move (motion_data.mbt), the last id given to one, and whether a cycle was read this frame
  movers : Array[MoverEntry]
  mut cycling : Bool
  /// the cycles read this frame (their periods, who reads them), whether a motion said was not at rest at its end, and
  /// the latest rest of the stacks (Ctx::nav) built this frame: what a test asks (Tester::assert_idle, nav_rest)
  cycles : Array[(Double, SourceLoc)]
  /// what comes again every so often while shown this frame (Ctx::every): its period, who reads it
  periodic : Array[(Double, SourceLoc)]
  mut motion_left : Bool
  /// a fiber of the window's runtime waits for the next frame (@effect.next_frame): it comes as the clock goes, not at
  /// this moment, as a motion going on
  mut fiber_frame : Bool
  /// a motion said that has not started yet (its rest +inf: it starts at its first step, a frame to come)
  mut motion_unstarted : Bool
  /// inputs came before this frame (a frame more, for what they changed late in it)
  mut took_input : Bool
  /// what the view read changed as the frame was built or laid out (Ctx::read_changed: words laid out elsewhere, the
  /// focus given, a list scrolled): built again in this frame (frame_body); the last that changed (what it is)
  mut read_back_moved : Bool
  mut read_back_key : String
  mut nav_rest : Double
  /// what is under everything the frame draws (0-1: what the host clears to as it presents it)
  clear : (Double, Double, Double)
  /// what of the host's answers is being recorded (hostrec.mbt)
  host_rec : HostRec
  /// covers by their ids, and those asked for this frame (cover.mbt)
  covers : Map[Int, CoverState]
  cover_asks : Array[CoverAsk]
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
  // the theme and the direction in force where the view builds (theme.mbt); the themes set, wide and narrow, the
  // width below which it is the narrow one, and whether this frame's is
  mut theme : Theme
  mut theme_wide : Theme
  mut theme_narrow : Theme?
  mut narrow_below : Double
  mut narrow : Bool
  // the boxes built this frame whose corner is `Inner` (style.mbt): worked out once laid out (corners.mbt), and
  // those that could not be (Tester::corner_faults says them)
  inners : Array[Int]
  inner_faults : Array[String]
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
  /// the layers this frame has given the focus as they opened (their ids): once a frame, at the first build they are in
  layers_opened : Array[Int]
  /// what the view tells outside of what it built, by key, this build's (Ctx::after_build): done once the frame's
  /// builds are over
  tells : Array[(Int, () -> Unit)]
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
    wake_waited: -1.0,
    frame_by: None,
    wake_by: None,
    hit_ids: [],
    hit_rects: [],
    next_hit_ids: [],
    next_hit_rects: [],
    hit_clips: [],
    next_hit_clips: [],
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
    press_chain: [],
    claimed: true,
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
    movers: [],
    cycling: false,
    cycles: [],
    periodic: [],
    motion_left: false,
    fiber_frame: false,
    motion_unstarted: false,
    took_input: false,
    read_back_moved: false,
    read_back_key: "",
    nav_rest: -1.0,
    clear: (0.961, 0.961, 0.969),
    host_rec: HostRec::new(),
    covers: Map::new(),
    cover_asks: [],
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
    theme_wide: Theme::light(),
    theme_narrow: None,
    narrow_below: 700.0,
    narrow: false,
    inners: [],
    inner_faults: [],
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
    layers_opened: [],
    tells: [],
    layer_cur: 0,
    dismissals: Map::new(),
    layer_return: Map::new(),
    press_down: None,
    inst: FixedArray::make(inst_size * 4096, 0.0),
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
  mix(self.id_seed, stable_hash(key).to_int())
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
///
/// `style` (style.mbt) says how it looks, its state blocks picked by its own state: pressed, hovered, focused by `id`
/// (as Ctx::pressed, hovered, focus_shown read them), `selected` and `disabled` as said, dark and narrow by the theme
/// (Ctx::set_theme). What is said here besides (`pad=`, `bg=`…) wins over the style's same property; what neither
/// says is as without either (no padding, no ground). A padding below 0 is not said (Ctx::row passes -1).
pub fn Ctx::box(
  self : Ctx,
  style? : Style,
  selected? : Bool = false,
  disabled? : Bool = false,
  dir? : Dir,
  w? : Size,
  h? : Size,
  pad? : Double,
  padx? : Double,
  pady? : Double,
  pl? : Double,
  pr? : Double,
  pt? : Double,
  pb? : Double,
  gap? : Double,
  align? : Align,
  justify? : Justify,
  bg? : Int64,
  radius? : Double,
  border? : Double,
  border_color? : Int64,
  shadow? : Double,
  shadow_color? : Int64,
  shadow_y? : Double,
  min_w? : Double,
  max_w? : Double,
  min_h? : Double,
  max_h? : Double,
  clip? : Bool,
  tx? : Double = 0.0,
  ty? : Double = 0.0,
  opacity? : Double,
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
  // the style's look in this node's states, the tokens looked up in the theme in force
  let st : Patch = match style {
    None => no_patch
    Some(s) =>
      s.resolve(
        self.narrow,
        self.theme.dark,
        selected,
        id != 0 && self.hovered(id),
        id != 0 && self.focus_shown(id),
        id != 0 && self.pressed(id),
        disabled,
      )
  }
  let th = self.theme
  n.dir = first(
    dir,
    match st.row {
      Some(true) => Some(Row)
      Some(false) => Some(Column)
      None => None
    },
  ).unwrap_or(Column)
  n.rtl = self.direction == Rtl
  n.aspect = aspect
  n.w = first(
    w,
    match st.w {
      Some(l) => Some(l.size())
      None => None
    },
  ).unwrap_or(Auto)
  n.h = first(
    h,
    match st.h {
      Some(l) => Some(l.size())
      None => None
    },
  ).unwrap_or(Auto)
  // one side said on its own wins over both sides, both over all four; said here over the style's
  let pad = said(pad)
  let px = first(said(padx), pad)
  let py = first(said(pady), pad)
  let s_x = opt_px(first(st.px, st.p))
  let s_y = opt_px(first(st.py, st.p))
  n.pad_l = first(said(pl), first(px, first(opt_px(st.pl), s_x))).unwrap_or(0.0)
  n.pad_r = first(said(pr), first(px, first(opt_px(st.pr), s_x))).unwrap_or(0.0)
  // right to left, the start (left said) is the right
  if n.rtl {
    let l = n.pad_l
    n.pad_l = n.pad_r
    n.pad_r = l
  }
  n.pad_t = first(said(pt), first(py, first(opt_px(st.pt), s_y))).unwrap_or(0.0)
  n.pad_b = first(said(pb), first(py, first(opt_px(st.pb), s_y))).unwrap_or(0.0)
  n.min_w = first(min_w, opt_bound(st.min_w, 0.0)).unwrap_or(0.0)
  n.max_w = first(max_w, opt_bound(st.max_w, 1.0e9)).unwrap_or(1.0e9)
  n.min_h = first(min_h, opt_bound(st.min_h, 0.0)).unwrap_or(0.0)
  n.max_h = first(max_h, opt_bound(st.max_h, 1.0e9)).unwrap_or(1.0e9)
  let (sh_blur, sh_y) = match st.shadow {
    Some(s) => {
      let (b, y) = s.blur_y()
      (Some(b), Some(y))
    }
    None => (None, None)
  }
  n.shadow_c = first(
    shadow_color,
    match st.shadow {
      Some(_) => Some(th.shadow)
      None => None
    },
  ).unwrap_or(0x0000002EL)
  n.shadow_y = first(shadow_y, sh_y).unwrap_or(-1.0)
  n.gap = first(gap, opt_px(st.gap)).unwrap_or(0.0)
  n.align = first(align, st.align).unwrap_or(AStretch)
  n.justify = first(justify, st.justify).unwrap_or(JStart)
  n.bg = first(bg, opt_color(th, st.bg)).unwrap_or(0L)
  n.radius = first(
    radius,
    match st.radius {
      Some(r) => Some(th.corner(r))
      None => None
    },
  ).unwrap_or(0.0)
  // a corner said `Inner` (and not said here): worked out once laid out (corners.mbt)
  if radius is None && st.radius is Some(Inner) {
    self.inners.push(i)
  }
  n.border_w = first(
    border,
    match st.border {
      Some(b) => Some(b.px())
      None => None
    },
  ).unwrap_or(0.0)
  n.border_c = first(border_color, opt_color(th, st.border_color)).unwrap_or(0L)
  n.shadow = first(shadow, sh_blur).unwrap_or(0.0)
  n.clip = first(clip, st.clip).unwrap_or(false)
  n.tx = tx
  n.ty = ty
  // (placed by its own size only when told so this frame, Ctx::place_by_size: a slot a menu was placed in last
  // frame is not where a box built there now goes)
  n.place = None
  n.opacity = first(
    opacity,
    match st.opacity {
      Some(o) => Some(o.value())
      None => None
    },
  ).unwrap_or(1.0)
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
/// A padding said in a call: one below 0 is not (the -1 Ctx::row and the like pass on).
fn said(v : Double?) -> Double? {
  match v {
    Some(x) if x >= 0.0 => v
    _ => None
  }
}

///|
fn opt_px(v : Space?) -> Double? {
  match v {
    Some(v) => Some(v.px())
    None => None
  }
}

///|
fn opt_color(th : Theme, v : Color?) -> Int64? {
  match v {
    Some(v) => Some(th.color(v))
    None => None
  }
}

///|
fn opt_bound(v : Len?, none_is : Double) -> Double? {
  match v {
    Some(v) => Some(v.bound(none_is))
    None => None
  }
}

///|
/// A style that says nothing.
// kept across runs: a value (no field of it changes)
let no_patch : Patch = patch()

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
/// Words, in the theme's colour unless `color`. `style` (style.mbt) says how they look, its dark and narrow blocks by
/// the theme; what is said here besides wins over the style's same property (a size said here keeps the style's line).
/// `tracking`: letter spacing in pixels; `max_lines`: wrapped words cut after that many lines, ending in an ellipsis.
pub fn Ctx::text(
  self : Ctx,
  s : String,
  style? : TextStyle,
  size? : Double,
  weight? : Int,
  color? : Int64,
  wrap? : Bool,
  w? : Size,
  line? : Double,
  center? : Bool,
  tracking? : Double,
  max_lines? : Int,
) -> Int {
  let st = self.text_patch(style)
  let (s_size, s_line) = self.text_sizes(st)
  let i = self.alloc_part(kind_text, true, false)
  let n = self.nodes[i]
  n.center = first(center, st.center).unwrap_or(false)
  n.line_h = first(line, s_line).unwrap_or(0.0)
  n.text = s
  n.font_size = first(size, s_size).unwrap_or(15.0)
  n.weight = first(weight, opt_weight(st.weight)).unwrap_or(400)
  n.color = first(color, opt_color(self.theme, st.color)).unwrap_or(self.theme.fg)
  n.wrap = first(wrap, st.wrap).unwrap_or(true)
  n.w = first(w, opt_size(st.w)).unwrap_or(Auto)
  n.spacing = match (tracking, st.tracking) {
    (Some(v), _) => v
    (None, Some(t)) => t.px(n.font_size)
    (None, None) => 0.0
  }
  n.max_lines = first(max_lines, st.max_lines).unwrap_or(0)
  i
}

///|
/// Words' style in this frame's states (dark, narrow).
fn Ctx::text_patch(self : Ctx, style : TextStyle?) -> TextPatch {
  match style {
    None => no_text_patch
    Some(t) => t.resolve(self.narrow, self.theme.dark)
  }
}

///|
/// The size and the line a style's words have, in the theme in force: the line its `leading` when it says one, else
/// its size's. (A node's line_h 0 is the font's own: `Font`.)
fn Ctx::text_sizes(self : Ctx, st : TextPatch) -> (Double?, Double?) {
  let (size, line) = match st.size {
    Some(z) => {
      let (size, line) = self.theme.text_size(z)
      (Some(size), Some(line))
    }
    None => (None, None)
  }
  match st.leading {
    Some(l) => (size, Some(self.theme.leading(l).unwrap_or(0.0)))
    None => (size, line)
  }
}

///|
fn opt_weight(v : Weight?) -> Int? {
  match v {
    Some(v) => Some(v.value())
    None => None
  }
}

///|
fn opt_size(v : Len?) -> Size? {
  match v {
    Some(v) => Some(v.size())
    None => None
  }
}

///|
/// Words' style that says nothing.
// kept across runs: a value (no field of it changes)
let no_text_patch : TextPatch = text_patch()

// ---------------------------------------------------------------------------
// Interaction

///|
pub fn Ctx::clicked(self : Ctx, id : Int) -> Bool {
  // (what a click changes is drawn by the next frame wherever it was seen, as every input's: on_frame)
  self.clicked.contains(id)
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
/// Whether a frame is being built now (on_frame): a frame asked for outside one is the host's to be told of.
let in_frame : Ref[Bool] = Ref::new(false)

///|
/// What the view reads changed (`what`: said by an unsettled frame that never stops changing it): while the frame is
/// built or laid out, it is built again in it before it is drawn (frame_body), so no frame shows the state as it
/// was; between frames (a host's callback), the next frame builds from it.
#callsite(autofill(loc))
fn Ctx::read_changed(self : Ctx, what : String, loc~ : SourceLoc) -> Unit {
  if building.val {
    self.read_back_moved = true
    self.read_back_key = what
  } else {
    self.request_frame(loc~)
  }
}

///|
#callsite(autofill(loc))
pub fn Ctx::request_frame(self : Ctx, loc~ : SourceLoc) -> Unit {
  self.wants_frame = true
  // asked between frames (a host's callback, a timer's): the frame's own asking (on_frame's end) is past, so the
  // host is told now, else nothing comes (the next frame's start clears wants_frame)
  if !in_frame.val {
    h_request_frame()
  }
  if self.frame_by is None {
    self.frame_by = Some(loc)
  }
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
  let clips = if physical_equal(rects, g().hit_rects) { g().hit_clips } else { [] }
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] &&
      in_round_clip(clips, k, x, y) {
      return ids[k]
    }
    k = k - 1
  }
  0
}

///|
/// Whether (x, y), in hit target `k`'s rect, is within the rounded corners of what cut it (`clips`, Ctx::hit_clips):
/// a corner as round, and as smooth, as the renderers cut it (smooth.mbt sd_corner; its radius at most half the clip's
/// shorter side).
fn in_round_clip(clips : Array[Double], k : Int, x : Double, y : Double) -> Bool {
  let b = k * clip_n
  if b + clip_n > clips.length() {
    return true
  }
  let (x0, y0, x1, y1) = (clips[b], clips[b + 1], clips[b + 2], clips[b + 3])
  let hx = dmax((x1 - x0) / 2.0, 0.0)
  let hy = dmax((y1 - y0) / 2.0, 0.0)
  let mx = x0 + hx
  let my = y0 + hy
  // the corner of the quarter it is in (top left, then clockwise)
  let j = if x < mx {
    if y < my {
      0
    } else {
      3
    }
  } else if y < my {
    1
  } else {
    2
  }
  let r = dmin(clips[b + 4 + j], dmin(hx, hy))
  r <= 0.0 || sd_corner(x - mx, y - my, hx, hy, r, clips[b + 8 + j]) <= 0.0
}

///|
/// A hit target drawn now: `id` where (x0 y0 x1 y1) shows (cut already to the clip's rect), and the clip itself.
fn Ctx::push_hit(
  self : Ctx,
  id : Int,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> Unit {
  self.next_hit_ids.push(id)
  self.next_hit_rects.push(x0)
  self.next_hit_rects.push(y0)
  self.next_hit_rects.push(x1)
  self.next_hit_rects.push(y1)
  let k = clip_top()
  for j in 0..<clip_n {
    self.next_hit_clips.push(clip_stack[k + j])
  }
}

///|
/// A value that follows `target` with a spring.
#callsite(autofill(loc))
pub fn Ctx::spring(
  self : Ctx,
  key : String,
  target : Double,
  from? : Double,
  stiffness? : Double = 420.0,
  damping? : Double = 32.0,
  loc~ : SourceLoc,
) -> Double {
  let id = self.id(key)
  let s = match self.springs.get(id) {
    Some(s) => s
    None => {
      let s = SpringPath::new(from.unwrap_or(target), k=stiffness, c=damping)
      self.springs[id] = s
      self.own(id)
      s
    }
  }
  // where it is now: a function of the time since it set out (motion_data.mbt); a new target (or one born away from
  // it) sets it out again from here, as fast as it goes
  if target != s.target() {
    s.go(self.now, target, what="c.spring \"" + key + "\"", loc~)
  }
  s.value(self.now)
}

///|
/// When the spring `key` (Ctx::spring, in the same scope) is at rest (the frames' clock; -1: it is, or there is none):
/// what a test runs to.
pub fn Ctx::spring_rest(self : Ctx, key : String) -> Double {
  match self.springs.get(self.id(key)) {
    Some(s) if s.end() > self.now => s.end()
    _ => -1.0
  }
}

///|
fn Ctx::wake_at_time(self : Ctx, t : Double, later? : Bool = false) -> Unit {
  if self.wake_at < 0.0 || t < self.wake_at {
    self.wake_at = t
  }
  if !later && (self.wake_waited < 0.0 || t < self.wake_waited) {
    self.wake_waited = t
  }
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
/// "copied" for a while), without frames in between. `later`: what is shown
/// does not wait for it (Tester::assert_idle does not count it: words going
/// back after a while, a refresh); by default it does (a press held long
/// enough, a menu opening once the pointer rests).
#callsite(autofill(loc))
pub fn Ctx::wake_in(self : Ctx, ms : Double, later? : Bool = false, loc~ : SourceLoc) -> Unit {
  if !later && self.wake_by is None {
    self.wake_by = Some(loc)
  }
  self.wake_at_time(self.now + dmax(ms, 1.0), later~)
}
