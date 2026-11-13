// A segmented choice as the web's narrow pages have it (web/src/mobile/parts.tsx Seg): mbui's
// sliding toggle group in Seg's look. Not a part of its own: `segmented` (parts.mbt) draws it on a narrow page, the
// web's Segmented on a wide one.

///|
/// How much larger than the thumb its lens is, a finger on it: past the track's edges.
let seg_lens_grow : Double = 1.3

///|
/// A segmented choice (Seg): mbui's sliding toggle group (@kit.toggle_group: the arrows move along it, a screen reader
/// reads its options) in Seg's look: a track the ink at 6%, a thumb lifted out of it (the theme's lifted, a hairline round it) sliding to the one
/// chosen. `fill`: as wide as where it is, each option an equal share, none narrower than its words (one that needs
/// more keeps that, the others sharing what is left); where they all need more than its width, as option_widths has
/// them: their sides narrower, else their words smaller alike (to the system's own size of words), else the chosen one
/// alone, the others in a pick (choice_pick). Always one line, each one's words whole: nothing wrapped, cut or scrolled.
/// `pill`: the web's wide pill
/// (controls.css.ts seg: options as wide as their words, 105 at least, `compact` as wide as their words alone; 36
/// high). Answers the one chosen (a tap's, this frame).
fn seg(
  c : @ui.Ctx,
  key : String,
  options : Array[String],
  selected : Int,
  fill? : Bool = false,
  height? : Double = 30.0,
  radius? : Double = 10.0,
  pill? : Bool = false,
  compact? : Bool = false,
  on_pick? : (Int) -> Unit,
) -> Int {
  let t = theme()
  let fill = fill && !pill
  let height = if pill { 36.0 } else { height }
  let radius = if pill { 18.0 } else { radius }
  let inset = 2.0
  let thumb = c.theme().lifted
  let items = options.mapi(fn(i, l) { @kit.item(i.to_string(), label=l) })
  let words_size : @ui.TextSize = if pill { Lg } else if fill { Base } else { Sm }
  // filling: where its options' words with their sides need more than the track (as last laid out: read back), as
  // option_widths has them in it (as alike as the flex has them till then)
  let track = c.id(key + "/track")
  let base = c.text_size(words_size).0
  let fit = if fill {
    match c.laid_size(track) {
      Some((w, _)) => {
        let size = c.sp(base)
        let words = options.map(fn(l) { choice_words_w(c, l, size) })
        let room = w - 2.0 * inset
        if words.fold(init=0.0, fn(s, x) { s + x + 2.0 * seg_side }) > room + 0.5 {
          Some(fitted(c, options, room, base, 400, seg_side, seg_least))
        } else {
          None
        }
      }
      None => None
    }
  } else {
    None
  }
  // its track: round its options, or round the chosen one's words where they do not fit side by side
  let track_box = fn(inner : () -> Unit) -> Int {
    // det-ok(box-loose): its height and corner said where it is used (34 on a page), the ink at 6%
    c.box(
      style=if fill { seg_track_full } else { seg_track },
      id=track,
      h=Px(height),
      radius~,
      // det-ok(style-literal): the ink at 6%, Seg's own
      bg=alpha(t.p.text, 0.06),
      inner,
    )
  }
  // (not side by side: the chosen one in its track, as wide; all of them in a pick)
  if fit is Some({ fit: Menu, .. }) {
    return choice_pick(c, key, track, options, selected, on_pick?, fn(c, _, words) {
      track_box(fn() {
        c.box(style=seg_menu, fn() {
          c.text(words, style=seg_menu_words) |> ignore
          icon(c, "chevron-down", size=seg_chevron, color=t.p.muted) |> ignore
        })
        |> ignore
      })
    })
  }
  // (made smaller to fit: their words drawn that much smaller)
  let smaller = match fit {
    Some({ fit: Smaller(k), .. }) => k
    _ => 1.0
  }
  let now = c.words_smaller(smaller, fn() {
    @kit.toggle_group(
      c,
      key,
      items,
      [selected.to_string()],
      slide=true,
      grow=fill,
      widths=fit.map(fn(f) { f.widths.map(fn(w) { (w, w) }) }).unwrap_or([]),
      look=fn(c, st) {
        c.box(
          style=if pill && !compact {
            seg_pill_option
          } else if fit is Some(_) {
            seg_squeezed_option
          } else if fill {
            seg_full_option
          } else {
            seg_option
          },
          keep=fill,
          fn() {
            // Parts.kt:424 (14sp filling, else 13sp; the pill the wide pages' 13)
            c.text(st.label, style=@ui.text_style(size=words_size, color=if st.on { Fg } else { Muted }, wrap=false))
            |> ignore
          },
        )
        |> ignore
      },
      // the thumb behind the options, over the one chosen: to another on its spring, placed at once the first time (as
      // Seg's first placement jumps)
      thumb=fn(c, w, h) {
        // det-ok(box-loose, style-literal): the thumb's size the group works out, its corner concentric in the track's
        c.box(w=Px(w), h=Px(h), radius=@ui.concentric(radius, inset), bg=thumb, border=0.5, border_color=t.p.line, fn() {  })
        |> ignore
      },
      // a finger on an option: the thumb there as a lens of liquid glass over them (iOS 26's), a capsule
      lens=glass_knob(),
      // (larger than the track, out over its edges: lifted off it, as iOS 26's)
      lens_grow=seg_lens_grow,
      on_change?=on_pick.map(fn(f) { fn(now : Array[String]) { picked_of(now, options, selected, f) } }),
      ground=fn(c, _, options) {
        // (in a row, as wide as its options: not stretched to its parent's width)
        if pill {
          c.box(style=seg_pill_line, fn() { track_box(options) |> ignore }) |> ignore
        } else {
          track_box(options) |> ignore
        }
      },
    ).value
  })
  // the chosen one tapped again stays chosen
  match now {
    [v] => items.search_by(fn(it) { it.value == v }).unwrap_or(selected)
    _ => selected
  }
}

///|
/// What a `stops` keeps between builds: the level its caller last said, the level it shows, the level last picked in
/// it that its caller has yet to say back (-1 none), and while one is, the levels its caller may still say that are
/// not news (what it said as each was picked, and what was picked before); a finger on it: its track as the press went
/// down (where along it each step of that press is) and the stop last felt under it.
pub struct Stops {
  mut said : Int
  mut shown : Int
  mut expect : Int
  stale : Array[Int]
  mut track_x : Double
  mut track_w : Double
  mut felt : Int
}

///|
pub fn Stops::new() -> Stops {
  { said: -2, shown: -1, expect: -1, stale: [], track_x: 0.0, track_w: 0.0, felt: -1 }
}

///|
/// What was picked in it did not take (its caller's: a save refused): it shows what its caller says again.
pub fn Stops::reset(self : Stops) -> Unit {
  self.said = -2
  self.expect = -1
  self.stale.clear()
}

///|
/// How far toward a finger its thumb leans from the stop it is drawn to (the bar's ball's `lean`).
let stops_lean : Double = 0.25

///|
/// How much larger its thumb is held, and its lens over that (the bar's ball's 6%, its lens's 18%).
let stops_held_grow : Double = 0.06

///|
let stops_lens_grow : Double = 0.18

///|
/// One of a few levels in order (how hard a model thinks), as many as there are on one line whatever they are called:
/// a capsule track on the words' tint, as a search field's and a panel's capsules beside it are, a stop for each level
/// across it, a dot each; over the one it is at its thumb, saying that level's name, as wide as the name needs.
///
/// Its thumb is the bottom bar's ball in small (the user, 2026-11-10: 「选择条需要能滑动」「手感跟小屏下边栏差不多」
/// 「玻璃效果也要重做」): a finger takes it along the track, to the stop under the finger and leaning a quarter of the
/// way on toward the finger itself, on the ball's spring (@kit.follow_spring), each stop come to under the finger
/// felt; let go, the level under the finger is picked. At
/// rest it is no glass, a lifted capsule (「按下边栏做，平时应该不是玻璃，按住才是玻璃，然后效果也按下边栏来，不要乱画」,
/// of a thumb of frosted glass with a lit rim at rest and a knob's lens held); held it is a little larger and the
/// bar's lens of liquid glass, its rim as narrow as a knob's (glass_knob), grows over it as it fades under the lens, by as much as the ball's does,
/// gone as it is let go; where glass is solid, the capsule alone. No shadow (「为啥有阴影」). A tap on a stop is a press let go there. Of what came before: a segmented choice of the names
/// (「分级再多点不就放不下了吗」), a line with a knob (「动效和 ui 都不符合整体风格」), Seg's track of corners (「这个选择
/// 控件本身就不符合整体风格」), and the sliding group's lens, which took the thumb to the stop pressed and left the
/// name of the one it was at on the bare track (「这又是什么鬼」).
///
/// `state`: what it keeps (its caller's, one for each of them). The level it shows is its own between builds: a level
/// picked is shown from then on whatever its caller says meanwhile that is not news (the level it had, an earlier
/// pick's: a caller whose save is answered before its value is told says the old level again for a few frames, and
/// the thumb went back and out again on a person's phone) until its caller says that level back; a level its caller
/// says that is news is shown as it is said. `said`: what a screen reader calls it. `on_pick`: what choosing another
/// level does, given its index, as it is chosen, outside any build; where that does not take, its caller says so
/// (Stops::reset). Returns the level it shows.
pub fn stops(
  c : @ui.Ctx,
  key : String,
  labels : Array[String],
  chosen : Int,
  state : Stops,
  said? : String = "",
  on_pick? : (Int) -> Unit,
) -> Int {
  if state.expect >= 0 {
    if chosen == state.expect {
      // (what was picked here said back)
      state.expect = -1
      state.stale.clear()
      state.said = chosen
    } else if !state.stale.contains(chosen) {
      // (news from elsewhere while a pick was on its way)
      state.expect = -1
      state.stale.clear()
      state.said = chosen
      state.shown = chosen
    }
  } else if chosen != state.said {
    state.said = chosen
    state.shown = chosen
  }
  let shown = state.shown
  let n = labels.length()
  let last = dmax(0.0, (n - 1).to_double())
  let id = c.id(key)
  let r = c.interact(id, keys=0, focus_on_press=true)
  let pad = @ui.Space::px(S1)
  let high = button_height()
  // the stop `px` across the window is over, on a track at `x` and `w` wide: which, and how far along counted in stops
  let along = fn(px : Double, x : Double, w : Double) -> Double? {
    if n > 0 && w > 2.0 * pad {
      Some(dclamp((px - x - pad) / (w - 2.0 * pad) * n.to_double() - 0.5, -0.5, last + 0.5))
    } else {
      None
    }
  }
  let stop_of = fn(p : Double) -> Int {
    let i = p.round().to_int()
    if i < 0 { 0 } else if i > n - 1 { n - 1 } else { i }
  }
  // a finger on it, as it is built: where along it (its track as last laid out)
  let (rx, _, rw, _) = r.rect()
  let finger = match c.drag_of(id) {
    Some(d) if d.down => along(d.x, rx, rw)
    _ => None
  }
  let at = match finger {
    Some(fp) => stop_of(fp)
    None => shown
  }
  // told as it comes, outside any build: each stop come to under the finger felt, the one it is let go over picked
  c.follow_press(id, fn(s) {
    let over = fn(px : Double) -> Int {
      match along(px, state.track_x, state.track_w) {
        Some(p) => stop_of(p)
        None => -1
      }
    }
    match s {
      Down(x, _, box) => {
        match box {
          Some((bx, _, bw, _)) => {
            state.track_x = bx
            state.track_w = bw
          }
          None => ()
        }
        state.felt = over(x)
      }
      Moving(x, _) => {
        let i = over(x)
        if i >= 0 && i != state.felt {
          state.felt = i
          @ui.haptic(TextHandleMove)
        }
      }
      Up(x, _) => {
        let i = over(x)
        state.felt = -1
        if i >= 0 && i != state.shown {
          // (what its caller may say meanwhile that is no news: what it says now, what was shown, an earlier pick)
          // (none of them, -1, is what its caller says too, of what has no level yet: no news either, or its thumb
          // went from the stop picked back to none until the save was told)
          for old in [(state.said, -1), (state.shown, -1), (state.expect, 0)] {
            if old.0 >= old.1 && old.0 != i && !state.stale.contains(old.0) {
              state.stale.push(old.0)
            }
          }
          state.stale.retain(fn(x) { x != i })
          state.expect = i
          state.shown = i
          match on_pick {
            Some(f) => {
              @signals.start_batch()
              @signals.untracked(fn() { f(i) })
              @signals.end_batch()
            }
            None => ()
          }
        }
      }
      Off => state.felt = -1
    }
  })
  // where its thumb goes, counted in stops: the stop it is at, leaning toward a finger. Told as it is built, on the
  // ball's spring, and read where it is drawn, as each frame is painted (nothing built again as it goes); held, the same
  let goal = match finger {
    Some(fp) => dclamp(at.to_double() + (fp - at.to_double()) * stops_lean, 0.0, last)
    None => dmax(0.0, at.to_double())
  }
  let pa = @motion.told(c, "sf-stops-p/" + key, goal, spec=@kit.follow_spring)
  let ha = @motion.told(c, "sf-stops-held/" + key, if finger is Some(_) { 1.0 } else { 0.0 }, spec=@motion.lift_spring)
  let cell = if n > 0 && rw > 2.0 * pad { (rw - 2.0 * pad) / n.to_double() } else { 0.0 }
  let thumb_h = high - 2.0 * pad
  let solid = c.glass_solid()
  let node = c.drag_area(id, axis=Horizontal, w=Fill(1.0), fn() {
    c.box(style=stops_track.then(@ui.style(h=Fixed(high))), fn() {
      // its stops, a dot each, the one under its thumb gone
      for i, l in labels {
        let a = @motion.told(c, "sf-stops/" + key + "/" + l, if i == at { 0.0 } else { 1.0 }, spec=@motion.tween(dur_ms, ease=Out))
        c.box(style=stops_cell, fn() {
          let d = c.box(style=stops_dot, fn() {  })
          c.look_by(d, fn() { @ui.look(alpha=a.get(c)) })
        })
        |> ignore
      }
      // its thumb over them, the bar's ball's way: at rest a lifted capsule, no glass, the name of the stop it is at
      // in it; held, a little larger, and the lens of liquid glass grown over it as it fades under the lens. Laid out
      // at the stop it goes to and drawn where its spring has it on the way. (Not drawn longer and lower by its
      // speed, as the ball is: the ball is laid out by its speed each frame it moves, which nothing new is.)
      if at >= 0 && n > 0 {
        if cell > 0.0 {
          let inner = rw - 2.0 * pad
          let tw = dmin(inner, dmax(cell, c.words_across(labels[at], stops_words) + 2.0 * @ui.Space::px(S3)))
          let left_at = fn(p : Double) -> Double { dclamp(pad + (p + 0.5) * cell - tw / 2.0, pad, pad + inner - tw) }
          let laid = left_at(goal)
          let off = fn() -> Double { left_at(dclamp(pa.get(c), 0.0, last)) - laid }
          let held = fn() -> Double { dmax(0.0, ha.get(c)) }
          let lensed = fn() -> Double { if solid { 0.0 } else { dmin(1.0, held()) } }
          let size = @ui.style(w=Fixed(tw), h=Fixed(thumb_h))
          let ball = c.box(style=stops_ball.then(size), left=laid, top=pad, fn() {  })
          c.look_by(ball, fn() { @ui.look(alpha=1.0 - lensed(), dx=off(), scale=1.0 + stops_held_grow * held()) })
          let name = c.box(style=stops_name.then(@ui.style(w=Fixed(tw), h=Fixed(high))), left=laid, top=0.0, fn() {
            c.text(labels[at], style=stops_words) |> ignore
          })
          c.look_by(name, fn() { @ui.look(dx=off()) })
          if !solid {
            // (the bar's lens as the library has it for a knob this small, glass_knob: the bar's own rim, 16, is more
            // than half this thumb's height, all of it rim then, its name drawn tall with coloured ends, 2026-11-10;
            // not drawn at all while it is not held: its look's opacity none)
            let lens = c.box(style=stops_ball_room.then(size), left=laid, top=pad, glass=glass_knob(), fn() {  })
            c.look_by(lens, fn() {
              let l = lensed()
              @ui.look(alpha=l, dx=off(), scale=(1.0 + stops_held_grow * held()) * (1.0 + stops_lens_grow * l))
            })
          }
        } else {
          // (not laid out yet: its thumb a stop's share of the track, where it goes)
          c.box(style=stops_over, left=pad, right=pad, top=pad, bottom=pad, fn() {
            c.box(style=@ui.style(w=Grow(goal)), fn() {  }) |> ignore
            c.box(style=stops_thumb, keep=true, fn() { c.text(labels[at], style=stops_words) |> ignore }) |> ignore
            c.box(style=@ui.style(w=Grow(last - goal)), fn() {  }) |> ignore
          })
          |> ignore
        }
      }
    })
    |> ignore
  })
  c.semantics(node, Slider, id~, label=said, value=if at >= 0 && at < n { labels[at] } else { "" }, range=(0.0, dmax(0.0, at.to_double()), last))
  state.shown
}

///|
/// A stop: an equal share of the track, its dot in its middle.
// kept across runs: a value (no field of it changes)
let stops_cell : @ui.Style = @ui.css("row h=Full align=ACenter justify=JCenter").then(@ui.style(w=grow))

///|
/// Its thumb's row over the stops, out of their flow: what is before it, it, what is after.
// kept across runs: a value (no field of it changes)
let stops_over : @ui.Style = @ui.css("row align=ACenter")

///|
/// Its thumb before its track is laid out: as tall as the row, a stop's share of it across, the name in its middle
/// 12 in.
// kept across runs: a value (no field of it changes)
let stops_thumb : @ui.Style = @ui.css("row h=Full px=S3 align=ACenter justify=JCenter radius=Full bg=Lifted").then(@ui.style(w=grow))

///|
/// Its thumb at rest, a lifted capsule; and a capsule's room alone, its lens's.
// kept across runs: a value (no field of it changes)
let stops_ball : @ui.Style = @ui.css("radius=Full bg=Lifted")

///|
// kept across runs: a value (no field of it changes)
let stops_ball_room : @ui.Style = @ui.css("radius=Full")

///|
/// A stop's dot: 4 across, the ink at 30% on the track's tint.
// kept across runs: a value (no field of it changes)
let stops_dot : @ui.Style = @ui.css("w=S1 h=S1 radius=Full bg=A(Fg,O30)")

///|
/// Its name over its thumb: in the thumb's middle.
// kept across runs: a value (no field of it changes)
let stops_name : @ui.Style = @ui.css("row align=ACenter justify=JCenter")

///|
/// Its track: a capsule on the words' tint, its stops in a line across it, 4 in.
// kept across runs: a value (no field of it changes)
let stops_track : @ui.Style = @ui.css("row w=Full p=S1 radius=Full bg=Tint")

///|
/// The name of the level it is at.
// kept across runs: a value (no field of it changes)
let stops_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// How wide a filling Seg of `options` is with its options' words whole at their size with their sides, and how
/// narrow it may go: the chosen one's (the widest's) words with the chevron, as it is when they do not fit side by
/// side (seg's pick). A filling one as wide as its options (at a head's end: @sf.segmented) is laid in that.
fn seg_room(c : @ui.Ctx, options : Array[String]) -> (Double, Double) {
  let size = c.sp(c.text_size(Base).0)
  let whole = options.fold(init=2.0 * seg_inset, fn(s, l) { s + choice_words_w(c, l, size) + 2.0 * seg_side })
  let menu = c.sp(c.text_size(Body).0)
  let widest = options.fold(init=0.0, fn(m, l) { dmax(m, choice_words_w(c, l, menu)) })
  (whole, 2.0 * seg_inset + 2.0 * seg_menu_in + widest + seg_menu_gap + seg_chevron)
}

///|
/// How wide a choice's words `s` are on one line at `size` and `weight`, as they are drawn: the app's own words, their
/// digits all one width where the theme they are drawn in says so (@ui.Theme `tabular`: 「7 天」's 7 as wide as 30's
/// digits each): an old view's, `c`'s (a node's: node_words_w).
fn choice_words_w(c : @ui.Ctx, s : String, size : Double, weight? : Int = 400) -> Double {
  words_w(c.theme().tabular, s, size, weight~)
}

///|
/// The same of a node's words: in the theme the window's tree's words are drawn in (@ui.tree_theme, view_host's
/// words_style), whatever theme an old view was left in.
pub fn node_words_w(s : String, size : Double, weight? : Int = 400) -> Double {
  words_w(@ui.tree_theme().tabular, s, size, weight~)
}

///|
/// How wide words `s` are on one line at `size` and `weight`, their digits all one width where `tabular`.
fn words_w(tabular : Bool, s : String, size : Double, weight? : Int = 400) -> Double {
  @ui.text_advance(s, size~, weight~, style=if tabular { @hostapi.style_tabular } else { 0 })
}

///|
/// How far its track stands round its options (seg_track's p=S0_5).
let seg_inset : Double = @ui.Space::px(S0_5)

///|
/// How far the chosen one's words stand in from its track's side, and from the chevron, when they do not fit side by
/// side (seg_menu's px=S2_5, gap=S2).
let seg_menu_in : Double = @ui.Space::px(S2_5)

///|
let seg_menu_gap : Double = @ui.Space::px(S2)

///|
/// Seg's track (its height and corner said where it is used): its options in a line, 2 in; as wide as where it is
/// (`fill`) or as they are.
// kept across runs: a value (no field of it changes)
let seg_track : @ui.Style = @ui.css("row p=S0_5")

///|
// kept across runs: a value (no field of it changes)
let seg_track_full : @ui.Style = seg_track.then(@ui.css("w=Full"))

///|
/// An option: its words in its middle, 10 in (in a row: as wide as its words at least); where the track fills, an
/// equal share, 8 in at least (the web's narrow Seg: five parts' English words in a phone's 320); the pill's 101 at
/// least.
// kept across runs: a value (no field of it changes)
let seg_option : @ui.Style = @ui.css("row h=Full px=S2_5 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let seg_full_option : @ui.Style = seg_option.then(@ui.css("w=Full px=S2"))

///|
/// A filling option short of room (option_widths): its words its least in from its sides (seg_least).
// kept across runs: a value (no field of it changes)
let seg_squeezed_option : @ui.Style = seg_full_option.then(@ui.css("px=S1"))

///|
/// A filling Seg whose options do not fit side by side (choice_pick), in its track: the chosen one's words at its
/// start (as far in as an option's, the same size, in ink, cut short where they must be), a chevron at its end; a
/// press on the track opens the pick.
// kept across runs: a value (no field of it changes)
let seg_menu : @ui.Style = @ui.css("row w=Full h=Full px=S2_5 gap=S2 align=ACenter justify=JBetween")

///|
// kept across runs: a value (no field of it changes)
let seg_menu_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Cut, wrap=false)

///|
let seg_chevron : Double = 16.0

///|
/// A filling option's words' sides (seg_full_option's px=S2), and how little they go to where the room is short
/// (seg_squeezed_option's px=S1).
let seg_side : Double = @ui.Space::px(S2)

///|
let seg_least : Double = @ui.Space::px(S1)

///|
/// How a choice's options fit the room option_widths gives them: their words at their size; their words made smaller
/// alike, by this much (down to the system's own size of words, as the systems' own segmented controls make theirs);
/// or not side by side at all, the chosen one alone and the others offered in a pick (choice_pick).
// Eq, Show and Debug for its tests
#warnings("-unused_value")
#derive(Eq, Debug)
priv enum Fit {
  Whole
  Smaller(Double)
  Menu
}

///|
/// How wide each of a choice's options is in `room` (all of it, the gaps between them aside), their words `words`
/// wide, and how they fit it: as alike as they can be, none narrower than its words with `side` either side; where
/// those come to more than the room, each its words with their sides narrower alike (to `least`); where even that is
/// too much, their words made smaller alike till they fit with the least either side, `smallest` of their size at the
/// least; else not side by side (Menu, no widths). Always one line, each one's words whole: nothing wrapped, cut or
/// scrolled (the user, 2026-10-25: a sideways scroll and words on two lines alike ugly).
fn option_widths(
  words : Array[Double],
  room : Double,
  side : Double,
  least : Double,
  smallest : Double,
) -> (Array[Double], Fit) {
  let room = dmax(room, 0.0)
  let n = words.length().to_double()
  let total = words.fold(init=0.0, fn(s, w) { s + w })
  if total + 2.0 * side * n <= room {
    return (shares(room, words.map(fn(w) { w + 2.0 * side }), words.map(fn(_) { 1.0 })), Whole)
  }
  if total + 2.0 * least * n <= room {
    let s = (room - total) / (2.0 * n)
    return (words.map(fn(w) { w + 2.0 * s }), Whole)
  }
  let k = if total > 0.0 { (room - 2.0 * least * n) / total } else { 0.0 }
  if k >= smallest && k > 0.0 {
    (words.map(fn(w) { w * k + 2.0 * least }), Smaller(k))
  } else {
    ([], Menu)
  }
}

///|
/// A choice's options fitted to its room (option_widths): their widths, and how they fit (made smaller, their words
/// drawn so: Ctx::words_smaller).
priv struct Fitted {
  widths : Array[Double]
  fit : Fit
}

///|
/// `labels`' options fitted to `room`, their words said in `base` and `weight`, `side` either side and `least` at the
/// least: made smaller, their widths those words' as drawn then, what is left shared alike.
fn fitted(
  c : @ui.Ctx,
  labels : Array[String],
  room : Double,
  base : Double,
  weight : Int,
  side : Double,
  least : Double,
) -> Fitted {
  fitted_by(fn(x) { c.sp(x) }, c.theme().tabular, labels, room, base, weight, side, least)
}

///|
/// The same, their words drawn at `sp` of the size said (Ctx::sp, an old view's; node_sp, a node's), their digits all
/// one width where `tabular` (the theme they are drawn in says so).
fn fitted_by(
  sp : (Double) -> Double,
  tabular : Bool,
  labels : Array[String],
  room : Double,
  base : Double,
  weight : Int,
  side : Double,
  least : Double,
) -> Fitted {
  let size = sp(base)
  let words = labels.map(fn(l) { words_w(tabular, l, size, weight~) })
  // (no smaller than the app says them: the size the system's own size of words draws)
  let smallest = dmin(1.0, base / size)
  let (widths, fit) = option_widths(words, room, side, least, smallest)
  match fit {
    // (their words as drawn that much smaller, what is left shared alike; a face's words narrow not quite as its size
    // does (San Francisco's optical sizes: smaller, set looser), so measured as drawn and made smaller again till they
    // fit with the least either side, else not side by side)
    Smaller(k0) => {
      let most = room - 2.0 * least * labels.length().to_double()
      let mut k = k0
      let mut drawn = labels.map(fn(l) { words_w(tabular, l, size * k, weight~) })
      let mut sum = drawn.fold(init=0.0, fn(s, w) { s + w })
      for _ in 0..<4 {
        if sum <= most + 0.01 || sum <= 0.0 || k < smallest {
          break
        }
        k = k * most / sum
        drawn = labels.map(fn(l) { words_w(tabular, l, size * k, weight~) })
        sum = drawn.fold(init=0.0, fn(s, w) { s + w })
      }
      if k < smallest || sum > most + 0.01 {
        return { widths: [], fit: Menu }
      }
      let left = (room - sum) / labels.length().to_double()
      { widths: drawn.map(fn(w) { w + left }), fit: Smaller(k) }
    }
    _ => { widths, fit }
  }
}

///|
/// A choice whose options do not fit side by side (choice_pick): the pick opened from it (as presented: 0, none yet),
/// and what was picked in it, till its caller has it.
priv struct ChoicePick {
  mut serial : Int
  mut picked : Int?
}

///|
/// Each choice that has been drawn not side by side, by its key.
let choice_picks : Map[String, ChoicePick] = Map([])

///|
fn init {
  @ui.on_reset(fn() { choice_picks.clear() })
}

///|
/// A choice of a few whose options do not fit side by side (option_widths: Menu): `look` draws the chosen one's words
/// in box `id` (its track's: as wide as where it is, read back as the track is), a chevron beside them; pressed, a pick
/// of them all opens under it (a sheet for a finger), the chosen one marked. What is chosen now: what was picked, from
/// the frame the pick tells it till `chosen` is it.
fn choice_pick(
  c : @ui.Ctx,
  key : String,
  id : Int,
  labels : Array[String],
  chosen : Int,
  on_pick? : (Int) -> Unit,
  look : (@ui.Ctx, Int, String) -> Int,
) -> Int {
  let p = match choice_picks.get(key) {
    Some(p) => p
    None => {
      let p = { serial: 0, picked: None }
      choice_picks[key] = p
      p
    }
  }
  let now = match p.picked {
    Some(i) if i != chosen => i
    _ => {
      p.picked = None
      chosen
    }
  }
  c.on_press(id, fn() {
    let choices = labels.mapi(fn(i, l) { choice(i.to_string(), l) })
    // (a segmented control's options, short words each: nothing to search them by)
    pick("", choices, now.to_string(), fn(k) {
      let i = labels_at(labels, k, now)
      p.picked = Some(i)
      match on_pick {
        Some(f) if i != now => f(i)
        _ => ()
      }
    }, from=Of(id), search=false)
    p.serial = last_presented()
  })
  let words = labels.get(now).unwrap_or("")
  let b = look(c, id, words)
  c.semantics(b, Button, id~, label=words, expanded=p.serial != 0 && presented_drawn_of(p.serial))
  now
}

///|
/// What a segmented choice's group (@kit.toggle_group) pressed to (`now`, its options by their places) chooses, told
/// `f` where it is another than `chosen` (the chosen one pressed again stays chosen).
fn picked_of(now : Array[String], labels : Array[String], chosen : Int, f : (Int) -> Unit) -> Unit {
  match now {
    [v] => {
      let i = labels_at(labels, v, chosen)
      if i != chosen {
        f(i)
      }
    }
    _ => ()
  }
}

///|
/// The option of `labels` a pick's key `k` names (its index), else `none`.
fn labels_at(labels : Array[String], k : String, none : Int) -> Int {
  for i in 0..<labels.length() {
    if i.to_string() == k {
      return i
    }
  }
  none
}

///|
/// `room` shared by `weights`, none given less than its floor: those whose share falls short take their floor, the
/// rest sharing what is left by theirs (as CSS's flex with min-widths). Where the floors come to more than the room,
/// the room shared by them.
fn shares(room : Double, floors : Array[Double], weights : Array[Double]) -> Array[Double] {
  let floored = floors.fold(init=0.0, fn(s, f) { s + f })
  if floored >= room && floored > 0.0 {
    return floors.map(fn(f) { room * f / floored })
  }
  let held = floors.map(fn(_) { false })
  for _ in 0..=floors.length() {
    let mut left = room
    let mut weight = 0.0
    for i, f in floors {
      if held[i] {
        left = left - f
      } else {
        weight = weight + weights[i]
      }
    }
    let mut more = false
    for i, f in floors {
      if !held[i] && left * weights[i] / weight < f {
        held[i] = true
        more = true
      }
    }
    if !more {
      return floors.mapi(fn(i, f) { if held[i] { f } else { left * weights[i] / weight } })
    }
  }
  floors
}

///|
// kept across runs: a value (no field of it changes)
let seg_pill_option : @ui.Style = seg_option.then(@ui.style(min_w=seg_pill_min))

///|
/// The pill in a line of its own, not stretched to its width.
// kept across runs: a value (no field of it changes)
let seg_pill_line : @ui.Style = @ui.css("row w=Full")
