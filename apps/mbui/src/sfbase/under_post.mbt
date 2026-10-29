// What comes and goes under a post in a chat's list (its options, how a card went, 忽略; ListMotion.kt, Chat.kt
// ArchiveEase; Decisions.css.ts): its room opening and closing as what is in it comes and goes, each on its own curve,
// in its turn among what changes the list's height (list_turns.mbt).

///|
/// The room under a post going to its new height: a Move as long as its way is far, as every row's height in a chat's
/// list goes (docs/list-motion.md: what changes together moves as one, on one curve from one moment).
// kept across runs: a curve, never written
pub let close_gap : @motion.Spec = @motion.move()

///|
/// How long the archive buttons take to come and go (Chat.kt ArchiveEase's 280 ms), 忽略 too.
pub let archive_ms : Double = 280.0

///|
/// ArchiveEase (Chat.kt): a quick start, a soft landing.
// kept across runs: a curve, never written
pub let archive_ease : @ui.Ease = Out

///|
/// How small the archive buttons (and 忽略) are as they have come or gone: 85%.
pub let archive_scale : Double = 0.85

///|
/// The archive buttons' curve and time (Chat.kt ArchiveEase, `archive_ms`): a quick start, a soft landing.
// kept across runs: a curve, never written
pub let archive_tween : @motion.Spec = @motion.tween(archive_ms, ease=archive_ease)

///|
/// The rooms under the posts as their motions were asked (under_post, by its key), kept to say when they are at rest.
// kept across runs: put back by under_reset (sfbase's reset)
pub let under_ends : Map[String, @motion.Anim] = {}

///|
/// When what comes and goes under the posts (options, how a card went, 忽略, the archive buttons) is at rest, their
/// rooms opening or closing on their springs and tweens (the frames' clock; -1: none moves; +inf: told to go, not
/// started yet): a test runs to it.
pub fn under_rest() -> Double {
  let mut end = -1.0
  under_ends.each(fn(_, a) { if a.ends_at() > end { end = a.ends_at() } })
  end
}

///|
/// What `body` builds under a post, shown or not as `shown` says (Compose's AnimatedVisibility with expandVertically /
/// shrinkVertically from its top): coming by `enter` (None: there at once, EnterTransition.None) as its room opens by
/// `open`, going by `exit` as its room closes by `close`; turned back mid-way from where it is; the first time as it
/// is. Its room is laid out (`@motion.reveal`, as the Android app's shrinkVertically lays it out, so what is under it
/// in the chat closes up); what is in it is only drawn while it goes (a tap is what is under it's). `start_at`: when
/// it was changed in its turn (Turns::in_turn), its motion from then.
pub fn under_post(
  c : @ui.Ctx,
  key : String,
  shown : Bool,
  enter? : @motion.Trans,
  open? : @motion.Spec = close_gap,
  exit~ : @motion.Trans,
  close? : @motion.Spec = close_gap,
  start_at? : Double,
  body : () -> Unit,
) -> Unit {
  let to = if shown { 1.0 } else { 0.0 }
  let h = @motion.anim(c, "under/" + key, to, global=true)
  let look = match enter {
    Some(e) => @motion.presence(c, "under-look/" + key, shown, enter=e, exit~, start_at?)
    None => {
      // there at once as it comes; going, by `exit`
      if shown {
        h.snap(1.0)
      }
      @motion.presence(c, "under-look/" + key, shown, enter=@motion.trans(spec=@motion.Snap(0.0)), exit~, start_at?)
    }
  }
  // (a share of its room: a Move as long as the room is tall)
  let spec = (if shown { open } else { close }).per_unit(@motion.reveal_height("under/" + key))
  match start_at {
    Some(at) if h.target() != to => h.animate(to, spec, start_at=at)
    _ => h.follow(to, spec)
  }
  under_ends[key] = h
  let share = h.get()
  let look = match look {
    Some(l) => l
    None => if share <= 0.0 { return } else { @ui.look(alpha=0.0) }
  }
  // (off where it goes: on its way, for the motion log)
  if share != h.target() {
    @motion.log_frame(c, "under/" + key, "open=\{share} alpha=\{look.alpha} scale=\{look.sx}")
  }
  @motion.reveal(c, "under/" + key, share, fn() {
    let i = c.box(style=under_room, body)
    c.look(i, look)
    @motion.leaving(c, i, shown)
  })
}

// ── the cards in a chat ─────────────────────────────────────────────────

///|
/// Options answered fade out in this long (Decisions.kt DecisionUnder); how it went fades in after them as long.
pub let options_out_ms : Double = 200.0

///|
/// The answered options' curve (CSS's ease-out) and how small they are as they have gone: 90%.
// kept across runs: a curve, never written
pub let options_ease : @ui.Ease = Leave

///|
pub let options_scale : Double = 0.9


///|
/// What is under a post: the column's width.
// kept across runs: a value (no field of it changes)
let under_room : @ui.Style = @ui.css("w=Full")

///|
/// What the rooms under the posts keep put back as the app begins anew (sfbase's reset).
pub fn under_reset() -> Unit {
  under_ends.clear()
}
