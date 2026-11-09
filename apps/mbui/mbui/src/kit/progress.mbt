// A progress bar (Radix's Progress): how far something has gone, `value` of `max`, or not known (None: a band runs
// along it). And an avatar (Radix's Avatar): a picture, or its fallback (initials) while it has none.

///|
/// What a progress bar's look is given: how far (0 … 1, as told: laid out there at once), or None not known; how far
/// it has gone from not known to known (`known`, 0 … 1: what runs along it while it is not known draws itself together
/// into the part come, and back, not changed from one to the other in a frame); and its key, what the part come is
/// reshaped by as how far is told anew (@motion.reshape: its ground from the width it had to the one it is laid out
/// at). What runs while it is not known is a cycle of the look's own (Ctx::cycle_look: drawn on as each frame is drawn,
/// frames while it is shown).
pub(all) struct ProgressState {
  t : Double?
  known : Double
  key : String
}

///|
/// `key`'s progress bar at `value` of `max` (None: not known), `w` wide, named `label` for the semantics tree. A value
/// told anew is laid out at once, the part come reshaped to it over progress_ms on the ease-out from the width it was
/// drawn (there at once the first time: progress_look_of); from not known to known (and back) over progress_known_ms,
/// what ran along it drawn into the part come.
pub fn progress(
  c : @ui.Ctx,
  key : String,
  value : Double?,
  max? : Double = 100.0,
  w? : @ui.Size = Fill(1.0),
  label? : String = "",
  look? : (@ui.Ctx, ProgressState) -> Unit = progress_look,
) -> Unit {
  let t = match value {
    Some(v) => Some(if max <= 0.0 { 0.0 } else if v <= 0.0 { 0.0 } else if v >= max { 1.0 } else { v / max })
    None => None
  }
  // (how far, as told: kept while it is not known, what it draws together into as it becomes known again)
  let at = @motion.anim(c, key + "/progress", t.unwrap_or(0.0))
  if t is Some(k) {
    at.snap(c, k)
  }
  let known = @motion.anim(c, key + "/progress/known", if t is Some(_) { 1.0 } else { 0.0 })
  known.follow(c, if t is Some(_) { 1.0 } else { 0.0 }, @motion.tween(progress_known_ms, ease=InOut))
  // (read as it is built: the band running along it while it is not known is drawn into the part come by it, its ends
  // where the look's cycle has them, which no reshape of a laid box goes from)
  let k = known.get(c)
  // (a band runs while it is not known: the look's cycle, Ctx::cycle_look; motion reduced, it stands where the look
  // puts it. How far shown while it is known or on its way from known: till its declared end)
  let shown = if t is Some(_) || !known.over(c) { Some(at.target()) } else { None }
  let i = c.box(w~, fn() { look(c, { t: shown, known: k, key }) })
  match (value, t) {
    (Some(v), Some(k)) =>
      c.semantics(i, ProgressBar, label~, value="\{(k * 100.0).round().to_int()}%", range=(0.0, v, max))
    _ => c.semantics(i, ProgressBar, label~)
  }
}

///|
/// How long a progress bar's fill takes to a value told anew (still.fail's: waiting.css.ts progress, its width 200 ms
/// on the ease-out).
pub let progress_ms : Double = 200.0

///|
/// How long what runs along a progress bar while it is not known takes to draw itself into the part come (and back).
pub let progress_known_ms : Double = 360.0

///|
/// How long the band of a progress bar not known takes to sweep across once (its look's `period`).
pub let progress_sweep_ms : Double = 1400.0

///|
/// A progress bar's look (still.fail's): `h` high on `track` (the theme's line: what is empty of what fills, seen on any
/// ground as what is drawn with nothing in it is, @ui's contrast.mbt), filled in `fill` (the theme's accent);
/// not known, a piece 40% of it sweeps across, eased there and back, once every `period` ms (a look by the clock,
/// Ctx::cycle_look: built once, only drawn on as it sweeps); becoming known, that piece's ends go to the fill's (its
/// start to the track's, its end to how far), as far as `known` says. Known, the fill is laid out as far as told and
/// reshaped there by its key over progress_ms on the ease-out (@motion.reshape): its ground from the width it was drawn
/// to the new one, its round ends whole all the way (a capsule's corners are half its height at any width past it).
pub fn progress_look_of(
  h? : Double = 3.0,
  track? : Int64,
  fill? : Int64,
  period? : Double = progress_sweep_ms,
) -> (@ui.Ctx, ProgressState) -> Unit {
  fn(c, s) {
    let th = c.theme()
    let ink = fill.unwrap_or(th.accent)
    let k = s.t.unwrap_or(0.0)
    let b = if s.t is None { 0.0 } else { s.known }
    let sweeps = s.t is None && !c.still()
    // the part drawn, from `lo` to `hi` of the track (sweeping: drawn by the clock, below)
    let (lo, hi) = if sweeps {
      (0.0, 1.0)
    } else if b >= 1.0 {
      (0.0, k)
    } else {
      // where the sweep is (still: 0.3 of the way), eased in and out. Going between known and not (`b` between 0 and
      // 1), where the band is drawn into the part come or out of it: built each frame of that as its motion is, so read
      // there (Ctx::cycle, a clock read as it is built)
      let f = if c.still() {
        0.3
      } else {
        0.5 - 0.5 * @dmath.cos(3.141592653589793 * c.cycle(period))
      }
      let start = sweep_start(f)
      let s0 = dmax(start, 0.0)
      let s1 = if start + sweep_piece > 1.0 { 1.0 } else { start + sweep_piece }
      (s0 + (0.0 - s0) * b, s1 + (k - s1) * b)
    }
    // (sweeping: the piece drawn as wide as the track, rounder by as much as it is drawn narrower, and as each frame is
    // drawn narrowed to its 40% about the point that puts its start where the sweep is: `ox` of the track, what the
    // piece's start keeps of it as it is narrowed about it; where it is past the track's ends, the track cuts it)
    let narrowed = if sweeps { sweep_piece } else { 1.0 }
    c.box(w=Fill(1.0), h=Px(h), radius=h / 2.0, bg=track.unwrap_or(th.line), clip=true, dir=Row, fn() {
      if lo > 0.0 {
        c.box(w=Fill(lo), fn() {  }) |> ignore
      }
      // (known: built at none too, so that it grows from none for its cause)
      if hi > lo || (!sweeps && b >= 1.0) {
        let piece = c.box(w=Fill(hi - lo), h=Px(h), bg=ink, radius=h / 2.0 / narrowed, fn() {  })
        if sweeps {
          c.cycle_look(piece, period, fn(p) {
            @ui.look(sx=narrowed, ox=sweep_start(0.5 - 0.5 * @dmath.cos(3.141592653589793 * p)) / (1.0 - narrowed))
          })
        } else if b >= 1.0 {
          // (how far told anew: laid out there at once, its ground from the width it was drawn; drawn into from the
          // band, said only once it is known, so it is there at once then)
          @motion.reshape(c, piece, "kit-progress/" + s.key, by="\{k}", spec=@motion.tween(progress_ms, ease=Out))
        }
      }
      if hi < 1.0 {
        c.box(w=Fill(1.0 - hi), fn() {  }) |> ignore
      }
    })
    |> ignore
  }
}

///|
/// How much of a progress bar not known its sweeping piece is.
let sweep_piece : Double = 0.4

///|
/// Where the sweeping piece of a progress bar not known starts (of the track) as far as `f` of its way (0 … 1): from
/// wholly before the track to wholly past it.
fn sweep_start(f : Double) -> Double {
  -sweep_piece + (1.0 + sweep_piece) * f
}

///|
/// The default look: 3 high, the accent over 18% of it.
pub let progress_look : (@ui.Ctx, ProgressState) -> Unit = progress_look_of()

///|
/// The initials of `name`: the first letters of its first two words (one word: its first letter), upper-cased.
pub fn initials(name : String) -> String {
  let out = StringBuilder()
  let mut n = 0
  for word in name.split(" ") {
    if n >= 2 {
      break
    }
    for ch in word {
      out.write_char(if ch >= 'a' && ch <= 'z' { (ch.to_int() - 32).unsafe_to_char() } else { ch })
      n += 1
      break
    }
  }
  out.to_string()
}

///|
/// An avatar `size` across: the picture at `src` ("" none) over its fallback, `name`'s initials on `bg` (the
/// theme's faint), round unless `radius` says otherwise; named `name` for the semantics tree.
pub fn avatar(
  c : @ui.Ctx,
  src : String,
  name : String,
  size? : Double = 40.0,
  radius? : Double = -1.0,
  bg? : Int64,
) -> Unit {
  let t = c.theme()
  let r = if radius < 0.0 { size / 2.0 } else { radius }
  let i = c.box(
    w=Px(size),
    h=Px(size),
    radius=r,
    clip=true,
    bg=bg.unwrap_or(t.faint),
    align=ACenter,
    justify=JCenter,
    fn() {
      c.text(initials(name), size=size * 0.4, weight=600, color=t.muted, wrap=false) |> ignore
      if src != "" {
        c.layer(fn() { c.image(src, w=Px(size), h=Px(size), radius=r, bg=0L) |> ignore }) |> ignore
      }
    },
  )
  c.semantics(i, Image, label=name)
}
