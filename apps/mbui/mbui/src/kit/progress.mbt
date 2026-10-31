// A progress bar (Radix's Progress): how far something has gone, `value` of `max`, or not known (None: a band runs
// along it). And an avatar (Radix's Avatar): a picture, or its fallback (initials) while it has none.

///|
/// What a progress bar's look is given: how far (0 … 1), or None not known; and how far it has gone from not known to
/// known (`known`, 0 … 1: what runs along it while it is not known draws itself together into the part come, and back,
/// not changed from one to the other in a frame). What runs while it is not known is a cycle of the look's own
/// (Ctx::cycle: its phase, and frames while it is shown).
pub(all) struct ProgressState {
  t : Double?
  known : Double
}

///|
/// `key`'s progress bar at `value` of `max` (None: not known), `w` wide, named `label` for the semantics tree. Where it
/// is shown goes to a value told anew over progress_ms on the ease-out, from where it was shown (there at once the
/// first time); from not known to known (and back) over progress_known_ms, what ran along it drawn into the part come.
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
  // (how far: kept while it is not known, what it draws together into as it becomes known again)
  let at = @motion.anim(c, key + "/progress", t.unwrap_or(0.0))
  if t is Some(k) {
    at.follow(k, @motion.tween(progress_ms, ease=Out))
  }
  let known = @motion.anim(c, key + "/progress/known", if t is Some(_) { 1.0 } else { 0.0 })
  known.follow(if t is Some(_) { 1.0 } else { 0.0 }, @motion.tween(progress_known_ms, ease=InOut))
  let k = known.get()
  // (a band runs while it is not known: the look's cycle, Ctx::cycle; motion reduced, it stands where the look puts
  // it)
  let shown = if t is Some(_) || k > 0.0 { Some(at.get()) } else { None }
  let i = c.box(w~, fn() { look(c, { t: shown, known: k }) })
  match (value, t) {
    (Some(v), Some(k)) =>
      c.semantics(i, ProgressBar, label~, value="\{(k * 100.0).round().to_int()}%", range=(0.0, max, v))
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
/// A progress bar's look (still.fail's): `h` high on `track` (the theme's line: what is empty of what fills, seen on any
/// ground as what is drawn with nothing in it is, @ui's contrast.mbt), filled in `fill` (the theme's accent);
/// not known, a piece 40% of it sweeps across, eased there and back, once every `period` ms; becoming known, that
/// piece's ends go to the fill's (its start to the track's, its end to how far), as far as `known` says.
pub fn progress_look_of(
  h? : Double = 3.0,
  track? : Int64,
  fill? : Int64,
  period? : Double = 1400.0,
) -> (@ui.Ctx, ProgressState) -> Unit {
  fn(c, s) {
    let th = c.theme()
    let ink = fill.unwrap_or(th.accent)
    let k = s.t.unwrap_or(0.0)
    let b = if s.t is None { 0.0 } else { s.known }
    // the part drawn, from `lo` to `hi` of the track
    let (lo, hi) = if b >= 1.0 {
      (0.0, k)
    } else {
      // where the sweep is (still: 0.3 of the way), eased in and out; the piece from -40% to all the way across
      let f = if c.still() {
        0.3
      } else {
        // a cycle of `period` (Ctx::cycle: a wait, drawn each frame while shown)
        0.5 - 0.5 * @dmath.cos(3.141592653589793 * c.cycle(period))
      }
      let start = -0.4 + 1.4 * f
      let s0 = dmax(start, 0.0)
      let s1 = if start + 0.4 > 1.0 { 1.0 } else { start + 0.4 }
      (s0 + (0.0 - s0) * b, s1 + (k - s1) * b)
    }
    c.box(w=Fill(1.0), h=Px(h), radius=h / 2.0, bg=track.unwrap_or(th.line), clip=true, dir=Row, fn() {
      if lo > 0.0 {
        c.box(w=Fill(lo), fn() {  }) |> ignore
      }
      if hi > lo {
        c.box(w=Fill(hi - lo), h=Px(h), bg=ink, radius=h / 2.0, fn() {  }) |> ignore
      }
      if hi < 1.0 {
        c.box(w=Fill(1.0 - hi), fn() {  }) |> ignore
      }
    })
    |> ignore
  }
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
