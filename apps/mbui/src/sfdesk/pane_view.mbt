// Laid out Large (or Medium with no sidebar to show: a device waiting to be confirmed in the workspace's safe mode, 连接,
// 用量), the wide frame off the tape as nodes of the window's tree (mbui's view package; docs/retained.md, the way
// there's 4), made once:
//
//   - a row: the rail and the sidebar's column (as wide as the block takes, open or folded: col), the page's pane in
//     what it leaves (the page an island, built for the room the tree gives it);
//   - over them, the block (the rail and the sidebar on one ground, shell.css.ts dock) an island of its own, taking
//     presses where it draws them alone: shown a while (folded, peeking) it reaches over the page; with it the
//     sidebar's edge and 更新 where the closed bar leaves room for it.
//
// The block's move (brand.tsx moveSidebar: folded or opened as chosen, shown a while or no longer, a place with no
// sidebar of its own come to or left, another place's sidebar at its own width; and the tape left for one of those) is a
// trajectory committed at its cause (fold_moves_from): of each thing it moves where the move before had it then and
// where it goes (FoldLook), one way from 0 to 1, read where it is drawn. What is no cause of a move (the window, the
// edge dragged, the window's room folding it, a fold's place) puts things where they go at once.
//
// Still the old view's (the way there): what the block and the page hold (their islands), the edge's drag and the
// pointer coming on the closed bar to show it a while (read as their islands build), back (the frame's in the island
// under all of it).

///|
/// What the block and the page beside it are shown as, in one state of the block (fold_look_of) or where a move between
/// two has got (fold_along): the column the page starts after; how far the page is moved aside (shown a while); the
/// page's bars' padding at their start and their margins; the sidebar's top row's height, its bands' ground (0 the
/// sidebar's, 1 the closed bar's), the lists' marks on the rail; the block's margins in its column, its line, how much of
/// the sidebar shows, its shadow (blur, fall, how much of its colour), its corner (0 open), its ground; the sidebar's
/// box's width; the rail's width and padding (left, top, bottom) and its top row's height; where the edge's strip starts.
priv struct FoldLook {
  col : Double
  aside : Double
  bar_pl : Double
  bar_ml : Double
  bar_mr : Double
  brand : Double
  band : Double
  mark : Double
  ml : Double
  mt : Double
  mr : Double
  mb : Double
  line : Double
  showing : Double
  blur : Double
  fall : Double
  shade : Double
  corner : Double
  ground : Int64
  side_w : Double
  rail_w : Double
  rail_pl : Double
  rail_pt : Double
  rail_pb : Double
  rail_top : Double
  edge : Double
} derive(Eq)

///|
/// `a` at `k` of the way to `b`.
fn fold_mix(a : FoldLook, b : FoldLook, k : Double) -> FoldLook {
  let m = fn(x : Double, y : Double) { x + (y - x) * k }
  {
    col: m(a.col, b.col),
    aside: m(a.aside, b.aside),
    bar_pl: m(a.bar_pl, b.bar_pl),
    bar_ml: m(a.bar_ml, b.bar_ml),
    bar_mr: m(a.bar_mr, b.bar_mr),
    brand: m(a.brand, b.brand),
    band: m(a.band, b.band),
    mark: m(a.mark, b.mark),
    ml: m(a.ml, b.ml),
    mt: m(a.mt, b.mt),
    mr: m(a.mr, b.mr),
    mb: m(a.mb, b.mb),
    line: m(a.line, b.line),
    showing: m(a.showing, b.showing),
    blur: m(a.blur, b.blur),
    fall: m(a.fall, b.fall),
    shade: m(a.shade, b.shade),
    corner: m(a.corner, b.corner),
    ground: if k >= 1.0 { b.ground } else if k <= 0.0 { a.ground } else { @sf.mix(b.ground, k, a.ground) },
    side_w: m(a.side_w, b.side_w),
    rail_w: m(a.rail_w, b.rail_w),
    rail_pl: m(a.rail_pl, b.rail_pl),
    rail_pt: m(a.rail_pt, b.rail_pt),
    rail_pb: m(a.rail_pb, b.rail_pb),
    rail_top: m(a.rail_top, b.rail_top),
    edge: m(a.edge, b.edge),
  }
}

///|
/// How far apart two looks are where a move goes (in points: the column, the page, the block's margins, the sidebar,
/// the rail, the edge): how long a Move between them takes.
fn fold_far(a : FoldLook, b : FoldLook) -> Double {
  let mut far = 0.0
  for d in [
    a.col - b.col,
    a.aside - b.aside,
    a.bar_pl - b.bar_pl,
    a.bar_ml - b.bar_ml,
    a.bar_mr - b.bar_mr,
    a.brand - b.brand,
    a.ml - b.ml,
    a.mt - b.mt,
    a.mr - b.mr,
    a.mb - b.mb,
    a.side_w - b.side_w,
    a.rail_w - b.rail_w,
    a.rail_top - b.rail_top,
    a.edge - b.edge,
  ] {
    far = dmax(far, d.abs())
  }
  far
}

///|
/// The block's state, as what it is moved for (frame.mbt's `cause`): folded as chosen, shown a while, a place with no
/// sidebar of its own (or none to show: gated), which sidebar (its workspace and group), beside the system's tabs.
priv struct FoldIs {
  folded : Bool
  peeking : Bool
  bare : Bool
  side : String
  native : Bool
} derive(Eq)

///|
/// What the frame off the tape is laid out by now, a window `ww` by `wh`: the place's sidebar gated or bare, its
/// sidebar folded for the page's room, on a fold standing upright, closed to the bar, shown a while; the sidebar's
/// width; the bars' room at the top and the foot.
priv struct PaneRoom {
  gated : Bool
  bare : Bool
  own : Bool
  crowded : Bool
  on_fold : Double?
  bar : Bool
  peek : Bool
  s : Double
  top : Double
  foot : Double
}

///|
fn pane_room(src : Source, w : Workspace, ww : Double) -> PaneRoom {
  let gated = lit_place() != "settings" && @settings.lock_waiting(settings_core(src, w), w.id)
  let bare = place_bare(lit_place())
  let own = !gated && !bare
  let crowded = own &&
    (@sf.native_input() is Finger) &&
    ww - rail_left() - side_on_fold().unwrap_or(wide.side_w.get()) < page_beside_least
  let folded = (wide.folded.get() && !wide.tape) || crowded
  let on_fold = if folded { None } else { side_on_fold() }
  let bar = (own && folded) || bare
  let s = if gated { 0.0 } else { on_fold.unwrap_or(wide.side_w.get()) }
  let bars = @ui.system_bars()
  let foot = if @sf.native_side() { cards_foot } else { bars.bottom }
  {
    gated,
    bare,
    own,
    crowded,
    on_fold,
    bar,
    peek: own && folded && wide.peeking.get(),
    s,
    top: bars.top,
    foot,
  }
}

///|
/// What the block and the page are shown as in room `r`, the page moved aside `shift` while the block is shown a while
/// (shell.css.ts and brand.css.ts as the frame had them: frame.mbt's dock and its bars' room).
fn fold_look_of(r : PaneRoom, shift : Double) -> FoldLook {
  let bar = r.bar
  let peek = r.peek
  let s = r.s
  let inset = @ui.window_inset()
  let keys_left = @ui.window_keys_left()
  let over_bars = peek && !inset
  let updating = !r.gated && update_shown()
  let shift = if peek { shift } else { 0.0 }
  // (under the window's buttons where they are the system's, at its left: macOS's)
  let above = if keys_left { closed_bar_top } else { bar_in_now() }
  let (blur, fall, shade) = if peek {
    closed_peek_shadow
  } else if bar {
    closed_shadow
  } else {
    open_shadow
  }
  {
    col: rail_left() + (if bar { 0.0 } else { s }),
    aside: shift,
    bar_pl: if !bar || over_bars {
      bar_in
    } else if updating {
      if keys_left {
        bar_update_inset
      } else {
        bar_update_in
      }
    } else if keys_left {
      bar_closed_inset
    } else {
      bar_in
    },
    bar_ml: if over_bars {
      dmax(0.0, s - bar_gap_now() - shift)
    } else if peek {
      -shift
    } else {
      0.0
    },
    bar_mr: shift,
    brand: side_brand_h(bar, r.top),
    band: if bar { 1.0 } else { 0.0 },
    mark: if bar { 1.0 } else { 0.0 },
    ml: if bar { bar_in_now() } else { 0.0 },
    mt: if bar { above } else { 0.0 },
    mr: if !bar {
      0.0
    } else if peek {
      bar_gap_now() - s
    } else {
      bar_gap_now()
    },
    mb: if bar { bar_in_now() } else { 0.0 },
    line: if bar { 1.0 } else { 0.0 },
    showing: if !bar || peek { 1.0 } else { 0.0 },
    blur,
    fall,
    shade,
    corner: if bar { @sf.closed_bar_of(rail_closed_ground_in).radius() } else { 0.0 },
    ground: dock_ground(bar),
    side_w: if bar || @sf.native_on() { s } else { s + side_into_rail },
    rail_w: if bar { rail_closed_w } else { rail_shown_w },
    rail_pl: if bar { rail_closed_pad } else { rail_in_px },
    rail_pt: if bar { rail_closed_pad } else { 0.0 },
    rail_pb: if bar { rail_closed_pad } else { rail_in_px },
    rail_top: rail_top_h(bar),
    edge: if !bar {
      rail_left() + s - edge_half
    } else if peek {
      closed_edge + s
    } else {
      closed_edge
    },
  }
}

///|
/// What the block is shown as on the tape (a panel of its own, apart from the page: 6 from the window's edges, 8 from
/// the page's panel, its line and the closed bar's shadow), the sidebar `s` wide in its column `col`, the bars `top` and
/// `foot` clear: where it closes from as the tape is left for a place with no sidebar of its own (pane_view).
fn fold_look_tape(s : Double, col : Double, top : Double, foot : Double) -> FoldLook {
  {
    ..fold_look_of(
      { gated: false, bare: false, own: true, crowded: false, on_fold: None, bar: false, peek: false, s, top, foot },
      0.0,
    ),
    col,
    ml: bar_in_now(),
    mt: bar_in_now(),
    mr: bar_gap_now(),
    mb: bar_in_now(),
    line: 1.0,
    blur: closed_shadow.0,
    fall: closed_shadow.1,
    shade: closed_shadow.2,
    ground: apart_ground(),
  }
}

///|
/// The block's move, committed at its cause: its way (0 as it set out, 1 there), where it set out from and where it
/// goes; the state it was moved for last (None: not yet, the frame just made); how far the page moves aside shown a
/// while (worked out once as it is shown: frame.mbt peek_shift); told as a move is committed or where things go is put.
/// What the tape last showed of the block as it was left (a place with no sidebar of its own come to from it: the
/// block closes from there). The frame's node while it shows, its page's id among the old views'.
priv struct FoldGoes {
  way : @motion.Way
  mut from : FoldLook?
  mut to : FoldLook?
  mut was : FoldIs?
  mut shift : Double
  said : @signals.Signal[Int]
  mut left_tape : FoldLook?
  mut node : @view.View?
  mut page_id : Int
  /// whether the core has given what the page shows of a page (sfapp's pane_ready), waited for that long at most
  mut ready : (Page) -> Bool
  mut most : Double
}

///|
// kept across runs: put back as a run begins (fold_goes_reset)
let fold_goes : FoldGoes = {
  way: @motion.Way::new(1.0),
  from: None,
  to: None,
  was: None,
  shift: 0.0,
  said: @signals.signal(0),
  left_tape: None,
  node: None,
  page_id: 0,
  ready: fn(_) { true },
  most: 0.0,
}

///|
fn fold_goes_reset() -> Unit {
  fold_goes.way.put(1.0)
  fold_goes.from = None
  fold_goes.to = None
  fold_goes.was = None
  fold_goes.shift = 0.0
  fold_goes.left_tape = None
  fold_goes.node = None
  fold_goes.page_id = 0
}

///|
/// What is committed of the block's move told.
fn fold_said() -> Unit {
  fold_goes.said.set(@signals.untracked(fn() { fold_goes.said.get() }) + 1)
}

///|
/// Where the block's move has it at `t`: from where it set out to where it goes, as far as its way has got; there, at
/// rest (or none committed yet: `now`, as the state has it).
fn fold_along(t : Double, now : FoldLook) -> FoldLook {
  match (fold_goes.from, fold_goes.to) {
    (Some(a), Some(b)) => {
      let k = fold_goes.way.value_at(t)
      // (there: as the state has it now)
      if k >= 1.0 || !fold_goes.way.goes_at(t) {
        now
      } else {
        fold_mix(a, b, k)
      }
    }
    _ => now
  }
}

///|
/// Whether the block's move goes at `t`.
fn fold_going(t : Double) -> Bool {
  fold_goes.way.goes_at(t)
}

///|
/// The room and the look of the block now, in the workspace in view, a window `ww` wide.
fn fold_target(src : Source, w : Workspace, ww : Double) -> (PaneRoom, FoldLook) {
  let r = pane_room(src, w, ww)
  (r, fold_look_of(r, fold_goes.shift))
}

///|
/// The block's move committed at `at` (its cause's moment): from where the move before had it then (`was_look` where none
/// was committed: the tape's, as it was left) to `to`, one way as long as the furthest of what it moves goes.
fn fold_moves_from(at : Double, to : FoldLook, was_look? : FoldLook) -> Unit {
  // (where the move before has it then; at rest, where it was put: the state before this one, as it was drawn)
  let from = match (fold_goes.from, fold_goes.to) {
    (Some(a), Some(b)) =>
      if fold_goes.way.goes_at(at) {
        fold_mix(a, b, fold_goes.way.value_at(at))
      } else {
        b
      }
    _ => was_look.unwrap_or(to)
  }
  fold_goes.from = Some(from)
  fold_goes.to = Some(to)
  fold_goes.way.put(0.0)
  fold_goes.way.go(1.0, @motion.move(over=fold_far(from, to)), at~)
  fold_said()
}

///|
/// Where the block goes put there at once, no move (the window, the edge dragged, the room folding it): what goes on of
/// a move goes on for the rest of it to there.
fn fold_put(to : FoldLook) -> Unit {
  match (fold_goes.from, fold_goes.to) {
    (Some(_), Some(was)) if was == to => return
    _ => ()
  }
  if fold_goes.way.goes_at(@ui.current().moment()) {
    fold_goes.to = Some(to)
  } else {
    fold_goes.from = Some(to)
    fold_goes.to = Some(to)
  }
  fold_said()
}

///|
/// The moment the block is drawn at by what reads it in node `n`: the frame's while its move goes, else after it.
fn fold_drawn_at(n : @view.View) -> Double {
  fold_goes.said.get() |> ignore
  fold_goes.way.said()
  if fold_goes.way.goes_at(n.logic_at()) {
    n.drawn_at()
  } else {
    @double.infinity
  }
}

///|
/// Where the block is as an island builds (`now` where nothing is committed): read again each frame its move goes (its
/// way read so), at rest no more.
fn fold_built(c : @ui.Ctx, now : FoldLook) -> FoldLook {
  fold_goes.said.get() |> ignore
  fold_goes.way.said()
  if fold_goes.way.goes_at(c.moment()) {
    fold_goes.way.get() |> ignore
    fold_along(c.moment(), now)
  } else {
    // (at rest, as the state has it now: what it is worked out from that no move follows, the theme, the window's
    // buttons, read as the island is built)
    now
  }
}

///|
/// The frame off the tape in node `v` (the signed-in shell's, filling the window: sfapp's paned_shell), in the workspace
/// in view (its file's head).
pub fn pane_view(v : @view.View, src : Source, ready~ : (Page) -> Bool, most~ : Double) -> Unit {
  wide.tape = false
  fold_goes.node = Some(v)
  fold_goes.ready = ready
  fold_goes.most = most
  v.owns(fn() { fold_goes.node = None }) |> ignore
  // the block moved for what it is moved for, at that moment: from where it is then; else what it goes to changed by
  // what is no cause of a move, put there at once
  let first = Ref(true)
  v.reacts(
    fn() {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => {
          let r = pane_room(src, w, v.window().0)
          let group = if @sf.native_on() { "tabs" } else { side_group(src, w.id) }
          let cause : FoldIs = {
            folded: wide.folded.get(),
            peeking: wide.peeking.get(),
            bare: r.gated || r.bare,
            side: w.id + "\n" + group,
            native: @sf.native_on(),
          }
          Some((cause, fold_look_of(r, fold_goes.shift)))
        }
        None => None
      }
    },
    fn(said) {
      guard said is Some((cause, look)) else { return }
      let at = v.cause_at()
      let was = fold_goes.was
      fold_goes.was = Some(cause)
      // (the tape left for a place with no sidebar of its own: the block closes from the tape's panel, as it was)
      let from_tape = fold_goes.left_tape
      fold_goes.left_tape = None
      let made = first.val
      first.val = false
      match (was, from_tape) {
        (Some(w), _) if w != cause && w.native == cause.native && !wide.edge_held.get() => {
          // shown a while from now: how far the page moves aside, worked out once as it starts (Rail.tsx markPeek)
          let look = if cause.peeking && !w.peeking {
            fold_goes.shift = fold_peek_shift(fold_along(at, look))
            match @sfbase.workspace_in_view(src).0 {
              Some(ws) => fold_look_of(pane_room(src, ws, v.window().0), fold_goes.shift)
              None => look
            }
          } else {
            look
          }
          fold_moves_from(at, look)
        }
        (None, Some(t)) if made && cause.bare => fold_moves_from(at, look, was_look=t)
        _ => fold_put(look)
      }
    },
  )
  v.box(fn(row) {
    row.row(Is(true)).grow(Is(1.0)) |> ignore
    // the rail and the sidebar's column: what the block takes of the row, open or folded, where its move has got
    row.box(fn(col) {
      col
      .width(By(fn() {
        match @sfbase.workspace_in_view(src).0 {
          Some(w) => {
            let (_, now) = fold_target(src, w, col.window().0)
            Some(fold_along(fold_drawn_at(col), now).col)
          }
          None => Some(0.0)
        }
      }))
      |> ignore
    })
    |> ignore
    // the page's pane in what the column leaves, under the bars at the top
    row.box(fn(pane) {
      pane
      .grow(Is(1.0))
      .padding(By(fn() { (0.0, @ui.system_bars().top, 0.0, 0.0) }))
      |> ignore
      pane.box(fn(page) {
        page.grow(Is(1.0)) |> ignore
        @ui.old(page, fn(c) { pane_page_built(c, src) }, key=tape_island_key).over(Is(true)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // the block over them (reaching over the page shown a while), its edge, 更新: taking presses where they draw them
  @ui.old(v, fn(c) { pane_block_built(c, src) }, key=tape_island_key).over(Is(true)) |> @ui.old_takes_own |> ignore
}

///|
/// How far the page moves aside for the folded sidebar shown a while, worked out once as it is shown (frame.mbt
/// peek_shift: what the page showed across as the last frame laid it out), the block where it is (`at`).
fn fold_peek_shift(at : FoldLook) -> Double {
  let c = @ui.current()
  let shown = c.shown_across(fold_goes.page_id, but="page-bar")
  match fold_goes.node {
    Some(v) => {
      let s = wide.side_w.get()
      let w = v.window().0
      match shown {
        Some((left, right)) => {
          let moved = (rail_left() - at.col) / 2.0
          let reach = bar_in_now() + rail_closed_w + s + peek_gap
          let room = w - 2.0 * peek_gap - dmin(right + moved, w)
          dmax(0.0, dmin(s, dmin(room, reach - dmax(left + moved, rail_left())))).round()
        }
        None => 0.0
      }
    }
    None => 0.0
  }
}

///|
/// The page's pane off the tape (its island, the room the tree leaves it beside the block's column): the page's bars'
/// room where the block's move has got (page_bar_room), the page moved aside as the block is shown a while.
fn pane_page_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, _, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (r, target) = fold_target(src, w, c.window_size().0)
  let f = fold_built(c, target)
  fold_bars(f)
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = false
  // a page opened in the pane shows once the core has given what it shows, the one before staying till then (`most` ms
  // at most), as a page pushed on a phone slides in then (asked as its stack is drawn)
  app.nav.shows_when(fn() { (fold_goes.ready)(app.nav.top()) }, fold_goes.most)
  let page_id = c.id("main-page")
  fold_goes.page_id = page_id
  // (what the page shows across as it is laid out, its bars left out: where the page moves aside to as the folded sidebar
  // is shown a while, taken as that starts: fold_peek_shift; the old view's layout read so, while the page is one)
  c.shown_across(page_id, but="page-bar") |> ignore
  // a right click in it: what is picked copied (context_menu.mbt)
  context_page(c, page_id)
  let pane = c.box(style=frame_main.then(@ui.style(w=Fixed(c.width))), id=page_id, fn() {
    page_in(c, src, w, r.gated, c.width, c.height, f.aside, pane_finger())
  })
  // (what moves in the page of its own takes its place from the page's foot: a keyboard, the block moving the page
  // aside, move none of it)
  @motion.scope(c, pane, bottom=true)
}

///|
/// What the page's bars and the sidebar's parts work out from, where the block's move has got (page_bar_room, side_top,
/// the lists' bands, the rail's marks).
fn fold_bars(f : FoldLook) -> Unit {
  wide.bar_pl = f.bar_pl
  wide.bar_ml = f.bar_ml
  wide.bar_mr = f.bar_mr
  wide.brand_h = f.brand
  wide.band = f.band
  wide.mark = f.mark
  wide.page_from = f.col
}

///|
/// The block off the tape (its island, the window's whole, taking presses where it draws them): the rail and the
/// sidebar where its move has got; the sidebar's edge (dragged, unless on the fold or folded for the page's room); 更新
/// where the closed bar's start leaves room for it.
fn pane_block_built(c : @ui.Ctx, src : Source) -> Unit {
  let (now, all, _, _) = @sfbase.workspace_in_view(src)
  guard now is Some(w) else { return }
  let (r, target) = fold_target(src, w, c.width)
  let f = fold_built(c, target)
  fold_bars(f)
  wide.closed.set(r.bar)
  wide.crowded = r.crowded
  let moving = fold_going(c.moment())
  let top = if side_full_height(r.bar) { 0.0 } else { r.top }
  dock(c, src, w, all, r.bar, r.peek, r.s, f.col, top, r.foot, 0.0, held=true, fold=Some((f, moving)))
  if !r.bare && r.on_fold is None && !r.crowded {
    sidebar_edge(c, f.edge)
  }
  // (with the sidebar closed, where its first row is not shown: 更新 where the bar's start leaves room for it)
  if !r.gated && update_shown() && r.bar && !r.peek {
    update_button(c, src, @ui.window_inset(), r.top)
  }
}

///|
/// What the frame off the tape does under its page and block with workspace `w` in view (an island under all of it:
/// sfapp's paned_shell): how the lists take the hand, the sidebar of this place and workspace as it was left, the
/// system's tabs where it has its own bars, the folded sidebar shown a while as the pointer comes on the closed bar, the
/// chat landed on, the window's buttons' row, back, the web services' pages let go.
pub fn pane_under(c : @ui.Ctx, src : Source, w : Workspace, all : Array[Workspace]) -> Unit {
  c.mouse_drags_lists(pane_finger())
  wide.side_place = side_place()
  side_follow(c, src, w.id)
  wide.tape = false
  tape_off()
  native_frame(c, src, w, all)
  let r = pane_room(src, w, c.width)
  wide.crowded = r.crowded
  side_crowded()
  let peek_r = rail_left() - bar_gap_now() + (if wide.peeking.get() { r.s } else { 0.0 })
  // (under the window's buttons where they are the system's, at its left: macOS's)
  let peek_top = if @ui.window_keys_left() { closed_bar_top } else { bar_in_now() }
  side_peek(c, bar_in_now(), r.top + peek_top, peek_r, c.height - r.foot - bar_in_now())
  land(src, w)
  if @ui.window_inset() {
    title_row(c, "window-title-row", closed_bar_top)
  }
  if !app.menu {
    match @sfbase.back_step() {
      Some(f) => c.take_back(f)
      None => ()
    }
  }
  sv_sweep(c, src)
}
