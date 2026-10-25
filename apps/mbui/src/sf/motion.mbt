// The page's motion (web/ui motion.ts): its ease-out, the one way in and out of what comes and goes in a list, the
// spring what makes way moves by, the list's glide, and the most a motion waits for what is here already. Motion as
// data is mbui's (@motion, Ctx::move_state: the web's moveState, 380 ms on the ease-out by default).

///|
/// The page's --ease-out (EASE_OUT: cubic-bezier(0.2, 0.7, 0.2, 1)).
pub let ease_out : @ui.Ease = Out

///|
/// What comes into a message list (ENTER, ENTER_FROM): 220 ms on the ease-out, up from 6 below as it fades in.
pub let enter_ms : Double = 220.0

///|
pub let enter_rise : Double = 6.0

///|
/// What goes (LEAVE, LEAVE_TO): a copy where it was, 200 ms, shrinking to 0.9 as it fades.
pub let leave_ms : Double = 200.0

///|
pub let leave_scale : Double = 0.9

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
