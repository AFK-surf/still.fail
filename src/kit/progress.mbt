// A progress bar (Radix's Progress): how far something has gone, `value` of `max`, or not known (None: a band runs
// along it). And an avatar (Radix's Avatar): a picture, or its fallback (initials) while it has none.

///|
/// What a progress bar's look is given: how far (0 … 1), or None not known; the time. What runs while it is not
/// known is a cycle of the look's own (Ctx::cycle: its phase, and frames while it is shown), not this time.
pub(all) struct ProgressState {
  t : Double?
  now : Double
}

///|
/// A progress bar at `value` of `max` (None: not known), `w` wide, named `label` for the semantics tree.
pub fn progress(
  c : @ui.Ctx,
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
  // (a band runs while it is not known: the look's cycle, Ctx::cycle; where nothing moves, a screenshot or motion
  // reduced, it stands where the look puts it)
  let still = c.still()
  let i = c.box(w~, fn() { look(c, { t, now: if still { 0.0 } else { c.now() } }) })
  match (value, t) {
    (Some(v), Some(k)) =>
      c.semantics(i, ProgressBar, label~, value="\{(k * 100.0).round().to_int()}%", range=(0.0, max, v))
    _ => c.semantics(i, ProgressBar, label~)
  }
}

///|
/// A progress bar's look (still.fail's): `h` high on `track` (18% of the fill), filled in `fill` (the theme's accent);
/// not known, a piece 40% of it sweeps across, eased there and back, once every `period` ms.
pub fn progress_look_of(
  h? : Double = 3.0,
  track? : Int64,
  fill? : Int64,
  period? : Double = 1400.0,
) -> (@ui.Ctx, ProgressState) -> Unit {
  fn(c, s) {
    let th = c.theme()
    let ink = fill.unwrap_or(th.accent)
    c.box(w=Fill(1.0), h=Px(h), radius=h / 2.0, bg=track.unwrap_or(@ui.alpha(ink, 0.18)), clip=true, dir=Row, fn() {
      match s.t {
        Some(k) => {
          // grown in proportion: the filled part `k` of the track, the rest after it
          if k > 0.0 {
            c.box(w=Fill(k), h=Px(h), bg=ink, radius=h / 2.0, fn() {  }) |> ignore
          }
          if k < 1.0 {
            c.box(w=Fill(1.0 - k), fn() {  }) |> ignore
          }
        }
        None => {
          // where the sweep is (still: 0.3 of the way), eased in and out; the piece from -40% to all the way across
          let f = if c.still() {
            0.3
          } else {
            // a cycle of `period` (Ctx::cycle: drawn a frame each frame while shown)
            0.5 - 0.5 * @math.cos(3.141592653589793 * c.cycle(period))
          }
          let start = -0.4 + 1.4 * f
          if start > 0.0 {
            c.box(w=Fill(start), fn() {  }) |> ignore
          }
          let shown = if start < 0.0 { 0.4 + start } else { 0.4 }
          c.box(w=Fill(shown), h=Px(h), bg=ink, radius=h / 2.0, fn() {  }) |> ignore
          let rest = 1.0 - dmax(start, 0.0) - shown
          if rest > 0.0 {
            c.box(w=Fill(rest), fn() {  }) |> ignore
          }
        }
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
