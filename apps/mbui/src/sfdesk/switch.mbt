// Between a chat and a new chat in the wide frame, by the sidebar's 新建对话 or a chat's row (ember web/src/dock.tsx
// useComposerMove, styles/global.css.ts's view transition): the composer goes from its place on the one to its place
// on the other (340 ms, the ease out: its own layout motion, composer.mbt) and the rest crossfades (260 ms, CSS's ease): the new chat's scene
// fading as a chat comes in, or a new chat's coming in. Between two chats nothing moves (the web leaves those to the
// link); a new chat become its chat has its own (newchat.mbt new_chat_after).

///|
/// The page the pane showed as the last frame was built (what a switch is from), whether the switch is away from a new
/// chat, and that new chat's view as it last showed (what fades as it is left).
priv struct WideSwitch {
  mut was : Page?
  mut from_new : Bool
  mut new_view : Json?
}

///|
let page_switch : WideSwitch = { was: None, from_new: false, new_view: None }

///|
fn page_switch_reset() -> Unit {
  page_switch.was = None
  page_switch.from_new = false
  page_switch.new_view = None
}

///|
/// How long the rest crossfades (global.css.ts: the root's view transition).
pub let page_cross_ms : Double = 260.0

///|
/// How far the crossfade has come (0 … 1, CSS's ease).
fn switch_anim(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "wide/switch", 1.0, global=true)
}

///|
/// As the pane's page is built: a switch between a chat and a new chat begins, from now.
fn page_switch_frame(c : @ui.Ctx, pages : Pages) -> Unit {
  let top = app.nav.top()
  let switched = match (page_switch.was, top) {
    (Some(NewChat), Chat(r)) =>
      match fresh.became {
        Some(b) if b == r => false
        _ => true
      }
    (Some(Chat(_)), NewChat) => true
    _ => false
  }
  if switched && !@ui.reduced_motion() {
    page_switch.from_new = page_switch.was == Some(NewChat)
    if page_switch.from_new {
      fresh.room = @motion.measured(c, "new/composer").unwrap_or(0.0)
    }
    let a = switch_anim(c)
    a.snap(0.0)
    a.animate(1.0, @motion.tween(page_cross_ms, ease=Css))
  }
  // a new chat come to: nothing made for it yet (NewChat.tsx useEnsureChat: once a page)
  if top == NewChat && page_switch.was != Some(NewChat) {
    fresh_reset()
  }
  page_switch.was = Some(top)
}

///|
/// How much of what comes in shows (1: all of it, no switch under way).
fn switch_in(c : @ui.Ctx) -> Double {
  let a = switch_anim(c)
  if a.moving() {
    a.get()
  } else {
    1.0
  }
}

///|
/// Over a chat come in from a new chat: what it showed under the composer's place, fading (its look of the page's
/// grounds, so what is under it comes in as it goes).
pub fn switch_veil(c : @ui.Ctx) -> Unit {
  let p = switch_in(c)
  if p >= 1.0 || !page_switch.from_new {
    return
  }
  let l = c.layer(fn() { c.box(style=switch_veil_box, fn() {  }) |> ignore })
  c.look(l, @ui.look(alpha=1.0 - p))
  c.draw_only(l)
}

///|
/// The new chat left for a chat, fading over it (drawn only, its composer gone to the chat's).
fn switch_new_out(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let p = switch_in(c)
  if p >= 1.0 || !page_switch.from_new {
    return
  }
  let v = page_switch.new_view
  let l = c.layer(fn() { new_page(c, src, w, pages, v, field(v, "station"), Some((0.0, 0.0))) })
  c.look(l, @ui.look(alpha=1.0 - p))
  c.draw_only(l)
}

///|
/// Node `i` of a new chat come in from a chat, fading in as it comes.
fn switch_appear(c : @ui.Ctx, i : Int) -> Unit {
  let p = switch_in(c)
  if p < 1.0 && !page_switch.from_new {
    c.look(i, @ui.look(alpha=p))
  }
}

///|
/// The page's ground, over what comes in while it fades in.
// kept across runs: a value (no field of it changes)
let switch_veil_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")
