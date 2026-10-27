// The app's presets (docs/motion.md, Presets: each kind's few, every motion one of them), the web's at the same place:
// its ease-out, what comes into and goes from a list, the spring what makes way moves by, a shape, the list's glide,
// the most a motion waits for what is here already, a control answering the hand, what is woken, the breath, copied.
// Those the framework makes are mbui's, named there and in the table (kit's pop_in, dialog_in, switch_ms,
// progress_ms, zoom_glide_ms, media's; @motion's springs; ui's pages pushed); motion as data is mbui's (@motion,
// Ctx::move_state: the web's moveState, 380 ms on the ease-out by default).

///|
/// The page's --ease-out (EASE_OUT: cubic-bezier(0.2, 0.7, 0.2, 1)).
pub let ease_out : @ui.Ease = Out

///|
/// What comes into a message list (ENTER, ENTER_FROM): 220 ms on the ease-out, up from 6 below as it fades in.
pub let enter_ms : Double = 220.0

///|
pub let enter_rise : Double = 6.0

///|
/// What goes from a list (LEAVE, LEAVE_TO: listMotion.ts, settling.tsx): a copy where it was, shrinking to 0.9 as it
/// fades over 200 ms on CSS's ease-out (`leave`).
pub let leave_ms : Double = 200.0

///|
pub let leave_scale : Double = 0.9

///|
// kept across runs: a value (no field of it changes)
pub let leave : @motion.Trans = @motion.trans(fade=0.0, scale=leave_scale, spec=@motion.tween(leave_ms, ease=CssOut))

///|
/// What is put in the composer to go with the message, a file's card, a picture's tile, a quote's card (Chat.css.ts
/// fileCard, composerQuote; Jobs.css.ts composerThumb: enterUpKeyframes): up from 6 below as it fades in, over 180 ms
/// on the ease-out.
// kept across runs: a value (no field of it changes)
pub let waiting_in : @motion.Trans = @motion.trans(fade=0.0, dy=enter_rise, spec=@motion.tween(180.0, ease=Out))

///|
/// A page over the whole window, a picture to share (FilePreview.css.ts fp: fadeInKeyframes): faded in over 140 ms on
/// the ease-out; gone by kit's pop_out, as a dialog.
// kept across runs: a value (no field of it changes)
pub let window_page_in : @motion.Trans = @motion.trans(fade=0.0, spec=@motion.tween(140.0, ease=Out))

///|
/// A row new to a list (listMotion.ts): grown in where it is from 0.9 and clear over 240 ms on the ease-out, 100 ms
/// after the list changed (what makes way for it moves first).
// kept across runs: a value (no field of it changes)
pub let row_grown_in : @motion.Trans = @motion.trans(
  fade=0.0,
  scale=leave_scale,
  spec=@motion.tween(240.0, ease=Out, delay=100.0),
)

///|
/// A shape changed for what it holds (morph.ts useMorph: the composer, a card): from the shape it had to its new one
/// over 260 ms on the ease-out.
pub let shape_ms : Double = 260.0

///|
/// The composer going with its page to another (dock.tsx, the view transition): 340 ms on the ease-out.
pub let composer_page_ms : Double = 340.0

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
/// How a message list's pane goes to where it follows (GLIDE_TAU: a share of what is left each moment, e^(-t/τ)),
/// and that law as a motion of fixed length (GLIDE_MS: to 99.75% of the way).
pub let glide_tau : Double = 100.0

///|
pub let glide_ms : Double = 600.0

///|
/// The most a motion, or a page moved to, waits for what is here already (LOCAL_MS): the core's answer from what it
/// holds, a picture decoded. Never for the network.
pub let local_ms : Double = 100.0

///|
/// moveState's run (motion.ts moveState's default transition: 380 ms on the ease-out), Ctx::move_state's default.
pub let move_state_ms : Double = 380.0

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
/// One breath of what waits (waiting.css.ts breathe, Jobs.css.ts jobBreathe): 1.4 s, from whole to `low` and back on
/// CSS's ease-in-out each way.
pub let breath_ms : Double = 1400.0
