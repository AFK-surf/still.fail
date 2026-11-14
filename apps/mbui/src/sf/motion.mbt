// The app's presets (sf/motion.mbt, Presets: each kind's few, every motion one of them), the web's at the same place:
// its ease-out, what comes into and goes from a list, the spring what makes way moves by, a shape, the list's glide,
// the most a motion waits for what is here already, a control answering the hand, what is woken, the breath, copied.
// Those the framework makes are mbui's, named there and in the table (kit's pop_in, dialog_in, switch_ms,
// progress_ms, media's; @motion's springs; ui's pages pushed); motion as data is mbui's (@motion, Ctx::move_state:
// the web's moveState). What moves (a shape, the composer to another page, a state moved) is a Move as long as its
// way is far (@ui.move_ms, @motion.moved), never a length of its own.
//
// Every motion is set off by its cause, never found by comparing frames (the user, 2026-10-25: 「我感觉现在有不少动
// 效 bug 是因为用了类似 css 的"过渡"效果，而没有准确地去控制什么时候应该去哪，而是直接检测差值」): a difference
// cannot know why it happened, so a resize, a dragged sidebar or a keyboard would move what only typing should.

///|
/// What comes into a message list (ENTER, ENTER_FROM): 220 ms on the ease-out, up from 6 below as it fades in.
pub let enter_ms : Double = 220.0

///|
pub let enter_rise : Double = 6.0

///|
/// What goes from a list (LEAVE): a copy where it was, shrinking to 0.9 as it
/// fades over 200 ms on CSS's ease-out (`leave`).
pub let leave_ms : Double = 200.0

///|
pub let leave_scale : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
pub let leave : @motion.Trans = @motion.trans(fade=0.0, scale=leave_scale, spec=@motion.tween(leave_ms, ease=Leave))

///|
/// What is put in the composer to go with the message, a file's card, a picture's tile, a quote's card (Chat.css.ts
/// fileCard, composerQuote; Jobs.css.ts composerThumb: enterUpKeyframes): up from 6 below as it fades in, over 180 ms
/// on the ease-out.
// kept across runs: a value (no field of it changes)
pub let waiting_in : @motion.Trans = @motion.trans(fade=0.0, dy=enter_rise, spec=@motion.tween(180.0, ease=Out))

///|
/// A page over the whole window, a picture to share: faded in over 140 ms on
/// the ease-out, its ground first, whole before its words begin over what it is put over (ground_first: none of the
/// page's words over the chat's under it); gone by kit's pop_out, as a dialog.
// kept across runs: a value (no field of it changes)
pub let window_page_in : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.tween(140.0, ease=Out), ground_first=true)

///|
/// The composer's hint, gone at once as words sent leave its field, back once they are out of it (madeChat.css.ts:
/// the placeholder's colour over 200 ms on cubic-bezier(.2, .8, .2, 1), the arrival's curve).
pub let hint_back_ms : Double = 200.0

///|
/// How what makes way for a small service moves (MOVE): a spring of 0.28 s, no bounce, so a goal that moves on is
/// followed, not started again.
// kept across runs: a value (no field of it changes)
pub let move_spring : @motion.Spec = @motion.move_spring

///|
/// The most a motion, or a page moved to, waits for what is here already (LOCAL_MS): the core's answer from what it
/// holds, a picture decoded. Never for the network.
pub let local_ms : Double = 100.0

///|
/// A control answering the hand (--dur, global.css.ts): pointed at, pressed, a switch turned, over this long on the
/// ease-out.
pub let dur_ms : Double = 140.0

///|
/// What says a thing was copied (a check for the copy button, 已复制) shows this long (parts.tsx CopyButton: 1.6 s).
pub let copied_ms : Double = 1600.0

///|
/// What is woken by the hand over a picture or a film (the viewer's bars, the player's controls) comes in over this
/// long, and fades as it rests over `sleep_ms`, on the ease-out (FilePreview.css.ts floating, viewer/media.css.ts: 120,
/// 320): kit's media controls' own.
pub let wake_ms : Double = @kit.media_wake_ms

///|
pub let sleep_ms : Double = @kit.media_sleep_ms

///|
/// One breath of what waits (waiting.css.ts breathe): 1.4 s, from whole to `low` and back on
/// CSS's ease-in-out each way.
pub let breath_ms : Double = 1400.0

///|
/// How clear a thing coming or going is drawn at `scale` of its size: not at all at half of it or less, wholly at its
/// size, as a list's row coming or going is (@ui.row_gone_at, the user, 2026-10-31: 缩到 50% 左右的时候就变成完全看不见).
/// A fade of its own goes on top of this.
pub fn seen_at(scale : Double) -> Double {
  if scale <= @ui.row_gone_at {
    0.0
  } else if scale >= 1.0 {
    1.0
  } else {
    (scale - @ui.row_gone_at) / (1.0 - @ui.row_gone_at)
  }
}
