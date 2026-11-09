// A panel's stage (the card to share) as nodes of the window's tree: the presenters' dialog layer
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
  dialog_layer_node(parent, open, cancel, outside=true, scrim=fn() { stage_scrim }, night_with_ground=true, shown~, gone~, covered~, fn(across, layer, look, _veil) {
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
    // (how wide what it holds is drawn (whole_fitted's, told as it is built) and how wide what is under it is laid out
    // (old's `fits`): the column as wide as the wider, as stage_box is, each in its middle)
    let body_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
    let under_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
    // (how wide it is laid out: its old view as wide, wider than the column where it is drawn smaller, cut by nothing)
    let laid_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
    let widest = fn() { dmin(room().0, dmax(body_w.get().unwrap_or(0.0), under_w.get().unwrap_or(0.0))) }
    // (one of its parts `w` wide in the column's middle: as far in from either side)
    let in_middle = fn(w : @signals.Signal[Double?]) {
      let m = (widest() - w.get().unwrap_or(0.0)) / 2.0
      (m, 0.0, m, 0.0)
    }
    across.box(fn(d) {
      d
      .width(By(fn() { Some(widest()) }))
      .max_height(By(fn() { Some(dmax(0.0, room().1)) }))
      .gap(Is(stage_gap))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      // (going, read out no more: as an old layer on its way out is hidden from what reads the screen)
      .says(By(fn() { if layer.leaving() { None } else { Some(@view.said(Dialog, label=title())) } }))
      // (a press on it its own: not beside it)
      .presses(Is(true))
      .on_press(fn() {  })
      |> ignore
      // (what it holds: as tall as it is laid out at the stage's width, giving way to what the column leaves it)
      // (the room the column gives it, as the tree laid it out: what it is drawn smaller to)
      @ui.old(d, natural=true, gives=true, key=fn() { key + "/body" }, fn(c) {
          let (sw, sh) = room()
          let given = match @ui.old_given() {
            Some((_, g)) if g > 0.0 => g
            _ => sh
          }
          let was = (stage_room.val, stage_gives.val)
          stage_room.val = Some((sw, sh))
          stage_gives.val = true
          stage_given.val = given
          stage_drawn_w.val = 0.0
          stage_laid_w.val = 0.0
          panel_whole_now.val += 1
          let held = c.box(style=stage_box.then(@ui.style(w=Full)), fn() { draw_panel_body(x, c, close, keyed~) })
          panel_whole_now.val -= 1
          stage_room.val = was.0
          stage_gives.val = was.1
          // (as wide as it is drawn: told as that changes, the column laid out again)
          let (w, lw) = (stage_drawn_w.val, stage_laid_w.val)
          if body_w.untracked() != Some(w) {
            body_w.set(Some(w))
          }
          if laid_w.untracked() != Some(lw) {
            laid_w.set(Some(lw))
          }
          words_look(c, held)
        })
      .width(By(fn() { laid_w.get() }))
      .margin(By(fn() { in_middle(laid_w) }))
      .shrink(Is(1.0))
      .min_height(Is(Some(0.0)))
      |> ignore
      // (under it: what is chosen of it over 关闭 and its foot's buttons, on the night)
      @ui.old(d, natural=true, fits=(stage_fits_most, under_w), key=fn() { key + "/foot" }, fn(c) {
          let night = on_night.val
          on_night.val = true
          let held = c.box(style=stage_under, fn() {
            match x.above {
              Some(f) => f(c)
              None => ()
            }
            c.box(style=stage_foot, fn() {
              button(c, t("common.close"), key=key + "/stage-close", on_press=fn() {
                cancel()
              }) |> ignore
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
      .width(By(fn() { under_w.get() }))
      .margin(By(fn() { in_middle(under_w) }))
      |> ignore
    })
  })
}

///|
/// The most a stage's parts are laid out as wide as (old's `fits`): past any window, what each holds deciding.
let stage_fits_most : Double = 100000.0

