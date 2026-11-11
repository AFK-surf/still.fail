// What every card of an agent's request in a chat shares once it is answered (vault_ask.mbt's answered_in_place and
// ask_outcome: the rig's, the phone's, the vault's, a sign-in's), as nodes of the window's tree, made once, following
// the card as the core changes it: answered while the card shows, its answer fades out where it is and how it went
// fades in over the room it leaves; once decided, one line saying how it went, a dot beside it, pressed for the card
// read again where it has a history.

///|
/// A card's answer at its foot, made by `answer` in `v` (answered_in_place's, as nodes), as `ended` says it now (whether
/// it was granted, and how it went in words): answered, the answer fades out where it is (answered_fade_ms, Leave),
/// taking no press, then how it went fades in after it over the room it leaves (as long, eased out), its dot and its
/// words in the middle of it. The answer stays laid out, unseen: the card keeps its size to the point. Answered before
/// it is made, how it went is there at once.
pub fn answered_in_place_node(
  v : @view.View,
  ended : () -> (Bool, Array[@ui.Run])?,
  answer : (@view.View) -> Unit,
) -> Unit {
  let gone = fn() { ended() is Some(_) }
  let first = @signals.untracked(gone)
  let was = @sf.EdgeWay::new(if first { 0.0 } else { 1.0 })
  let now = @sf.EdgeWay::new(if first { 1.0 } else { 0.0 })
  v.box(fn(whole) {
    @sf.style_node(whole, fn() { answered_whole })
    whole.reacts(gone, fn(g) {
      if g {
        was.go(whole, 0.0, answered_fade_ms, ease=Leave)
        now.go_by(whole, 1.0, @motion.tween(answered_fade_ms, ease=Out, delay=answered_fade_ms))
      } else {
        now.put(0.0)
        was.put(1.0)
      }
    })
    whole.box(fn(a) {
      @sf.style_node(a, fn() { answered_room })
      a.alpha(By(fn() { was.shown(a) })).presses(By(fn() { !gone() })) |> ignore
      answer(a)
    })
    |> ignore
    // (over the answer's room, the whole of it)
    whole.box(fn(o) {
      o.over(Is(true)).alpha(By(fn() { now.shown(o) })) |> ignore
      o.box(fn(r) {
        @sf.style_node(r, fn() { answered_over })
        r.box(fn(d) {
          @sf.style_node(d, fn() {
            match ended() {
              Some((true, _)) => ask_dot_on
              _ => ask_dot
            }
          })
        })
        |> ignore
        r.box(fn(w) {
          w
          .words_runs(By(fn() { ended().map(fn(e) { e.1 }).unwrap_or([]) }))
          .words_look(Is(@ui.style_words(ask_ended_words)))
          .ink(By(fn() { @ui.style_ink(ask_ended_words) }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A request's outcome line in `v` (ask_outcome's, as nodes), as they say it now: a dot (green while `granted`) and its
/// `words`; the dot in the middle of the words' first line, under the message's picture as wide as it where the
/// message's head is `inline`, else out in the margin where the picture is, the words at the row's start. `history`:
/// pressed, the card read again (given what it opens from).
pub fn ask_outcome_node(
  v : @view.View,
  granted : () -> Bool,
  words : () -> Array[@ui.Run],
  inline : () -> Bool,
  history? : ((@view.View) -> Unit)? = None,
) -> Unit {
  let th = @sf.ui_theme()
  let line = th.leading(ask_ended_leading).unwrap_or(th.text_size(ask_ended_size).1)
  v.box(fn(o) {
    @sf.style_node(o, fn() { ask_ended })
    o.box(fn(w) {
      @sf.style_node(w, fn() {
        let base = if inline() { ask_ended_past } else { ask_ended_at }
        if history is Some(_) {
          base.then(ask_ended_start)
        } else {
          base
        }
      })
      match history {
        Some(open) => @sf.ask_history_trigger_node(w, words, fn() { ask_ended_words }, line, open) |> ignore
        None =>
          w.box(fn(t) {
            t
            .words_runs(By(words))
            .words_look(Is(@ui.style_words(ask_ended_words)))
            .ink(By(fn() { @ui.style_ink(ask_ended_words) }))
            |> ignore
          })
          |> ignore
      }
    })
    |> ignore
    // (over the line, the whole of it: the dot's room)
    o.box(fn(l) {
      l.over(Is(true)) |> ignore
      l.box(fn(d) {
        @sf.style_node(d, fn() {
          (if inline() { ask_dot_line } else { ask_dot_line_out }).then(@ui.style(h=Fixed(@sf.node_sp(d, line))))
        })
        d.box(fn(x) { @sf.style_node(x, fn() { if granted() { ask_dot_on } else { ask_dot } }) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
