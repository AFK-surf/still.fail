// What an agent at work says it does now, steadied, for its row made as nodes (chat_rows.mbt's steady_words' state
// machine, useSteady): brief routine steps are coalesced, an important one has its turn even if it is over; each step
// shows a while before the next takes its place. Its state is kept by its row's key in what its caller gives
// (ActivitySteadies, a row made again for the same key going on from where it was), what shows a signal; each change
// is worked out at the moment of its cause (what the core said, a row coming into the list) or at a moment declared
// from one (View::at_moment), never at a frame's. How one step's words give way to the next's, glyph by glyph, from the
// moment it began showing: message_working_node.mbt's working_words_node.

///|
/// What an agent says it does, as its row reads it: the step's key, its words, whether in the monospaced face, whether
/// it is important.
#derive(Eq, Debug)
pub(all) struct ActivitySaid {
  key : String
  words : String
  mono : Bool
  important : Bool
}

///|
/// What shows, steadied: the step (`said`), the words it took the place of ("" none: the row's first) and whether in the
/// monospaced face, and the moment it began showing.
#derive(Eq, Debug)
pub(all) struct ActivityShown {
  said : ActivitySaid
  was : String
  was_mono : Bool
  at : Double
}

///|
/// One row's steadying: what shows, and what is waiting to (the latest other step and when it was first said; an
/// important step and when it was first said); when the row came into its list; what is due for it, let go as the next
/// is declared.
struct ActivitySteady {
  shown : @signals.Signal[ActivityShown]
  mut pending : String?
  mut pending_at : Double
  mut important_next : (ActivitySaid, Double)?
  mut came : Double?
  mut due : () -> Unit
}

///|
/// What each row of a chat's list at work shows, steadied, by its row's key: kept by the list (the chat's page), so a
/// row made again for a key goes on from where it was.
pub struct ActivitySteadies {
  rows : Map[String, ActivitySteady]
}

///|
pub fn ActivitySteadies::new() -> ActivitySteadies {
  { rows: {} }
}

///|
/// Row `key`'s steadying, made showing `said` from `at` where it had none.
fn ActivitySteadies::of(self : ActivitySteadies, key : String, said : ActivitySaid, at : Double) -> ActivitySteady {
  match self.rows.get(key) {
    Some(s) => s
    None => {
      let s = {
        shown: @signals.signal({ said, was: "", was_mono: false, at }),
        pending: None,
        pending_at: 0.0,
        important_next: None,
        came: None,
        due: fn() {  },
      }
      self.rows[key] = s
      s
    }
  }
}

///|
/// What shows of row `key` in `v` as its agent says `said` as that changes, the row having come into its list at `came`
/// (None: there as the chat opened), kept in `steadies`: what steady_step works out at each cause and each moment it
/// declares. What shows, as it changes.
fn activity_steady_node(
  v : @view.View,
  steadies : ActivitySteadies,
  key : String,
  said : () -> ActivitySaid,
  came : () -> Double?,
) -> () -> ActivityShown {
  let st = steadies.of(key, @signals.untracked(said), v.cause_at())
  fn step(now : Double) -> Unit {
    (st.due)()
    st.due = fn() {  }
    match steady_step(st, @signals.untracked(said), @signals.untracked(came), now, @ui.reduced_motion()) {
      Some(at) => st.due = v.at_moment(at, fn() { step(at) })
      None => ()
    }
  }
  v.reacts(fn() { (said(), came()) }, fn(_) { step(v.cause_at()) })
  v.owns(fn() { (st.due)() }) |> ignore
  fn() { st.shown.get() }
}

///|
/// Row `st` told `said` at moment `now` (its row having come into its list at `came`), as steady_words worked it out:
/// a new row's arrival starts it anew from that moment; before it, it shows what is said; else the same step's new
/// words at once; an important other step once what shows has had its turn (dwell where that is important, else its
/// own change's time), routine ones once what shows has shown steady_dwell_ms and the step has been said
/// steady_candidate_ms. What shows set (a signal: told only as it changes); the moment it is to be worked out again,
/// where something waits.
fn steady_step(st : ActivitySteady, said : ActivitySaid, came : Double?, now : Double, reduced : Bool) -> Double? {
  let cur = st.shown.untracked()
  // (a row come into its list anew: from that moment, what is said now)
  match came {
    Some(at) if st.came != Some(at) => {
      st.came = Some(at)
      st.pending = None
      st.important_next = None
      st.shown.set({ said, was: "", was_mono: false, at })
      return None
    }
    _ => ()
  }
  // (before the row's turn in its list, what is said then)
  match st.came {
    Some(at) if at > now => {
      st.pending = None
      st.important_next = None
      if cur.said != said {
        st.shown.set({ ..cur, said })
      }
      return Some(at)
    }
    _ => ()
  }
  let mut next : (ActivitySaid, Double)? = None
  let mut wait : Double? = None
  if said.important && said.key != cur.said.key && said.words != cur.said.words {
    let since = match st.important_next {
      Some((old, at)) if old.key == said.key => at
      _ => now
    }
    st.important_next = Some((said, since))
  }
  match st.important_next {
    Some((n, since)) => {
      // (a change under way not started again; an important step not cut short before it can be read)
      let dwell = if cur.said.important {
        steady_dwell_ms
      } else if reduced {
        0.0
      } else if cur.was == "" {
        activity_glyph_in_ms
      } else {
        @sfbase.glyph_change_in_ms
      }
      let at = dmax(cur.at + dwell, since)
      if now < at {
        wait = Some(at)
      } else {
        next = Some((n, at))
        st.important_next = None
        // (what is said now moved on while the important one waited: its turn after it)
        if said.key != n.key && said.words != n.words {
          st.pending = Some(said.key)
          st.pending_at = now
          wait = Some(dmax(at + steady_dwell_ms, now + steady_candidate_ms))
        } else {
          st.pending = None
        }
      }
    }
    None =>
      if said.key == cur.said.key || said.words == cur.said.words {
        st.pending = None
        if said != cur.said {
          st.shown.set({ ..cur, said })
        }
      } else {
        // (a routine step gone before its own change could finish never starts one)
        if st.pending != Some(said.key) {
          st.pending = Some(said.key)
          st.pending_at = now
        }
        let at = dmax(cur.at + steady_dwell_ms, st.pending_at + steady_candidate_ms)
        if now < at {
          wait = Some(at)
        } else {
          next = Some((said, at))
          st.pending = None
        }
      }
  }
  match next {
    Some((n, at)) => {
      st.shown.set({ said: n, was: cur.said.words, was_mono: cur.said.mono, at })
      // (taken: what is said now worked out again from there)
      match wait {
        Some(w) => Some(w)
        None => if said != n { Some(now) } else { None }
      }
    }
    None => wait
  }
}
