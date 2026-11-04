// A panel's stage (stage_centred's: the card to share) as nodes of the window's tree: the presenters' dialog layer
// (dialog_layer_node: a press beside what it shows closes it, as a dialog's does) dimmed by the stage's own night
// (stage_scrim); no panel round what it shows, no title drawn (said as its name alone) and no close button over it: a
// column in the window's middle, stage_margin and the system's bars clear of the window's edges, of what it holds and,
// stage_gap under it, what is chosen of it (`above`) over 关闭 and its foot's buttons, on the night (on_night). What
// it holds is laid out as wide as what it shows is handed out (whole_fitted's `most`) and drawn smaller where the
// stage has not the room: as tall as that at the stage's width, giving way to the room the column leaves it under what
// is under it (the tree's layout, stage_gives). Escape, back, 关闭 and a press beside it close it (its gone told); what
// its foot is given closes it as done.

///|
/// A stage `x` in `parent` while `open()` (going over pop_out_ms once not); `key`: what its old views are named by (the
/// presented's); `close`: what its foot is given to close it (done); `cancel` as it is closed by 关闭, Escape, back or a
/// press beside it. `shown`, `gone`: as dialog_layer_node's.
fn stage_node(
  parent : @view.View,
  key : String,
  open : () -> Bool,
  x : PanelOf,
  close : () -> Unit,
  cancel : () -> Unit,
  keyed : Presented,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  covered? : () -> Bool = fn() { false },
) -> Unit {
  // (its night its own, whoever else dims what is under it (scrim_owner leaves a stage out): as kit's dialog draws a
  // stage's scrim)
  dialog_layer_node(parent, open, cancel, outside=true, scrim=fn() { stage_scrim }, ground_ms=stage_night_ms, shown~, gone~, covered~, fn(across, layer, look, _veil) {
    // (its name as it is now: `live`'s first, said, never drawn)
    let title = fn() {
      match x.live {
        Some(f) => f().0
        None => x.title
      }
    }
    // (the room the stage has: the window less stage_margin and the system's bars round it)
    let room = fn() {
      let (ww, wh) = layer.window()
      let bars = @ui.system_bars()
      (ww - 2.0 * stage_margin - bars.left - bars.right, wh - 2.0 * stage_margin - bars.top - bars.bottom)
    }
    // (its old views' words as far in as its look says, as kit's dialog's look gives them: read as they are painted)
    let words_look = fn(c : @ui.Ctx, held : Int) {
      c.look_by(held, fn() {
        { alpha: 1.0, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: look().words }
      })
    }
    // The stage owns the available room. Its layout measures the controls and the whole picture, then places both
    // at the size that fits; neither child's measured size is published as another layout input.
    let picture_w = Ref(0.0)
    let shell_size : Ref[(Double, Double)?] = Ref(None)
    let picture_scale = Ref(1.0)
    across.box(fn(d) {
      d
      .width(By(fn() { Some(dmax(0.0, room().0)) }))
      .height(By(fn() { Some(dmax(0.0, room().1)) }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      |> ignore
      // The ground covers only the actual stage, so pressing beside it still dismisses the layer.
      let shell = d.box(fn(n) {
        n.says(By(fn() { if layer.leaving() { None } else { Some(@view.said(Dialog, label=title())) } }))
        .presses(Is(true)).on_press(fn() { }) |> ignore
      })
      let body = @ui.old(d, natural=true, key=fn() { key + "/body" }, fn(c) {
          let was = (stage_natural.val, stage_natural_scale.val)
          stage_natural.val = true
          stage_natural_scale.val = fn() { picture_scale.val }
          stage_laid_w.val = 0.0
          panel_whole_now.val += 1
          let held = c.box(style=stage_box.then(@ui.style(w=Full)), fn() { draw_panel_body(x, c, close, keyed~) })
          panel_whole_now.val -= 1
          if stage_laid_w.val > 0.0 { picture_w.val = stage_laid_w.val }
          stage_natural.val = was.0
          stage_natural_scale.val = was.1
          words_look(c, held)
        })
      // (under it: what is chosen of it over 关闭 and its foot's buttons, on the night)
      let under = @ui.old(d, natural=true, fits=stage_fits_most, key=fn() { key + "/foot" }, fn(c) {
          let night = on_night.val
          on_night.val = true
          let held = c.box(style=stage_under, fn() {
            match x.above {
              Some(f) => f(c)
              None => ()
            }
            c.box(style=stage_foot, fn() {
              if button(c, t("common.close"), key=key + "/stage-close") {
                cancel()
              }
              match x.foot {
                Some(f) => f(c, close)
                None => ()
              }
            })
            |> ignore
          })
          on_night.val = night
          words_look(c, held)
        })
      d.layout_box(By(room), fn(l, _) {
        let first_w = if picture_w.val > 0.0 { picture_w.val } else { l.width }
        let first = l.measure(body, first_w)
        let natural_w = if picture_w.val > 0.0 { picture_w.val } else { first.0 }
        let (bw, bh) = if natural_w != first_w { l.measure(body, natural_w) } else { first }
        // The picture discovers its required files before the controls decide whether it can be saved.
        let (uw, uh) = l.fit(under, stage_fits_most)
        let available = dmax(0.0, l.height - uh - stage_gap)
        let scale = dmin(1.0, dmin(if bw > 0.0 { l.width / bw } else { 1.0 }, if bh > 0.0 { available / bh } else { 1.0 }))
        let (drawn_w, drawn_h) = (bw * scale, bh * scale)
        let sw = dmin(l.width, dmax(drawn_w, uw))
        let sh = drawn_h + stage_gap + uh
        let left = (l.width - sw) / 2.0
        let top = (l.height - sh) / 2.0
        if shell_size.val != Some((sw, sh)) {
          shell_size.val = Some((sw, sh))
          shell.width(Is(Some(sw))).height(Is(Some(sh))) |> ignore
        }
        l.measure(shell, sw, height=sh) |> ignore
        l.place(shell, left, top)
        picture_scale.val = scale
        l.place(body, (l.width - bw) / 2.0, top)
        l.place(under, (l.width - uw) / 2.0, top + drawn_h + stage_gap)
      }) |> ignore
    })
  })
}

///|
/// The most a stage's parts are laid out as wide as (old's `fits`): past any window, what each holds deciding.
let stage_fits_most : Double = 100000.0

///|
/// How long a stage's night takes to come: its surface, the night in by the time what it holds begins to come (kit's
/// dialog_in, its ground first: the first half of its way in), all it holds coming on it at once after (Ctx::surface;
/// its picture's words never over the page's words seen through a night not in yet).
let stage_night_ms : Double = @kit.dialog_ms / 2.0
