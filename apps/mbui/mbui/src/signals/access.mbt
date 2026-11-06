// What a phase may not read: said as the phase begins (set_access_guard, a layout box's: View::layout_box), each read
// and write of a signal checked against it in every build, a test's as an app's. One in it aborts, saying the phase,
// what it was and where: an input the phase reads is taken before it begins.

///|
// kept across runs: said and put back by each phase that keeps its reads to what it took before
let access_guard : Ref[String?] = Ref(None)

///|
/// What no read nor write of a signal may happen in from now (None: any may), what was said before given back.
pub fn set_access_guard(reason : String?) -> String? {
  let was = access_guard.val
  access_guard.val = reason
  was
}

///|
/// A read or write (`kind`) at `loc`: aborted in a phase that may have none, saying which and where.
fn access_checked(kind : String, loc : SourceLoc) -> Unit {
  match access_guard.val {
    Some(reason) => {
      access_guard.val = None
      abort("\{reason}: \{kind} at \{loc}; take this input before the phase begins")
    }
    None => ()
  }
}

///|
/// The signal's value (signalOper read), checked against the phase it is read in (access_checked).
#callsite(autofill(loc))
pub fn[T] Signal::get(self : Signal[T], loc~ : SourceLoc) -> T {
  access_checked("signal read", loc)
  self.read_value()
}

///|
/// The computed's value, worked out again first if what it read changed since (computedOper), checked as a signal's.
#callsite(autofill(loc))
pub fn[T] Computed::get(self : Computed[T], loc~ : SourceLoc) -> T {
  access_checked("computed read", loc)
  self.read_value()
}

///|
/// What the computed made last, not worked out again (none before it was first read), checked as a signal's.
#callsite(autofill(loc))
pub fn[T] Computed::peek(self : Computed[T], loc~ : SourceLoc) -> T? {
  access_checked("computed peek", loc)
  self.1.value
}

///|
/// The tree's phases a read may be guarded in (phase_guard): a build (what a view reads as it is made, a row made in a
/// layout's too), a layout (what measuring reads, a child measured in a layout's too).
pub(all) enum AccessPhase {
  Build
  Layout
} derive(Eq, Show)

///|
// kept across runs: what a build and a layout may not read, as said for each (none yet: each reads what it reads now)
let build_guard : Ref[String?] = Ref(None)

///|
// kept across runs: as build_guard
let layout_guard : Ref[String?] = Ref(None)

///|
/// The guard of `phase`, what a part of another phase that is one of it (a row made in a layout: a build) runs under:
/// set_access_guard's, given back as it ends.
pub fn phase_guard(phase : AccessPhase) -> String? {
  match phase {
    Build => build_guard.val
    Layout => layout_guard.val
  }
}

///|
/// What `phase` may not read from now (None: what it reads now).
pub fn set_phase_guard(phase : AccessPhase, reason : String?) -> Unit {
  match phase {
    Build => build_guard.val = reason
    Layout => layout_guard.val = reason
  }
}

///|
// kept across runs: what a stopped run told and had yet to run, held apart as a run begins (reset_globals) till what of
// it is the stopped run's own is let go (run_told)
let told_held : Array[ReactiveNode] = []

///|
// kept across runs: as told_held, what waited in the stopped run for its change told whole, asked for where something
// owned what was made (an effect running, a scope): each with that owner, and whether it waited for all of the rest
// too (after_all_flushed)
let afters_kept : Array[(ReactiveNode, () -> Unit, Bool)] = []

///|
/// Whether `o` is not stopped: a watch not gone; an effect or a scope following or owning something, or not let go
fn still_kept(o : ReactiveNode) -> Bool {
  match o.own {
    WatchOwned(w) => !w.gone.val
    _ => o.flags != NONE || o.deps is Some(_)
  }
}

///|
/// What a run stopped half way leaves here put back (a run beginning: a Tester's): a phase's guard, a batch, a flush, a
/// read or an effect under way are each put back as they end, but a run stopped in one (a test that aborts there, as it
/// should) leaves it, and every run after it reads under a guard it never set, or holds back what it tells. What waited
/// for the stopped run's change told whole (after_flush, after_all_flushed) is let go with it, never done, but what of
/// it an owner asked for (an effect running, a scope) is held apart with it, as what was told is.
/// What the stopped run told and had yet to run is held apart, for its owner to let go what of it is the stopped run's
/// own (a Tester's tree, its watches stopped) before it runs (run_told). Nothing it made is let go here: its signals and
/// effects are kept, and the one an abort stopped in its own run stays as it stopped.
pub fn reset_globals() -> Unit {
  access_guard.val = None
  build_guard.val = None
  layout_guard.val = None
  let draining = run.draining
  run.run_depth = 0
  run.batch_depth = 0
  run.batch_changed = false
  run.active_sub = None
  run.owner = None
  run.asked_for = None
  run.flushing = 0
  run.afters_held = 0
  run.draining = false
  run.flush_trail.clear()
  run.running = None
  run.computing = 0
  run.effects_held = 0
  run.held_effects.clear()
  run.sampling = 0
  run.sampled_reads.clear()
  check_frames.clear()
  propagate_frames.clear()
  watch_reading.depth = 0
  watch_reading.sets.clear()
  setting.val = None
  // (what waited for a change of the stopped run's told whole, by after_flush or after_all_flushed, there in a batch, a
  // flush or a layout holding them back: asked for where nothing owned what was made, by the stopped run's own steps,
  // let go with it; asked for by what it made (a node's effect, a watch, a scope), held apart with its owner, done as
  // the change it told is (run_told) where its owner is kept, let go where it was let go with the stopped run: done
  // after that, it would act on what is no more. Being done (draining), which of them were done is not known: none
  // done again)
  if !draining {
    for i, f in run.afters {
      if run.afters_by[i] is Some(o) {
        afters_kept.push((o, f, false))
      }
    }
    for i, f in run.lasts {
      if run.lasts_by[i] is Some(o) {
        afters_kept.push((o, f, true))
      }
    }
  }
  run.afters.clear()
  run.afters_by.clear()
  run.lasts.clear()
  run.lasts_by.clear()
  // (what was told and not yet run held apart: the first set as the run begins flushes the queue, and would run it
  // there, before what of it is the stopped run's own is let go)
  for i in run.notify_index..<run.queued_length {
    if run.queued[i] is Some(e) {
      told_held.push(e)
    }
    run.queued[i] = None
  }
  run.notify_index = 0
  run.queued_length = 0
}

///|
/// What a run stopped half way told and had yet to run (reset_globals), run as the batch or the set it was told in would
/// have ended: each effect still following what it read, told again as it changes; one stopped since (what was the
/// stopped run's own, let go) runs no more. Then what waits for a change told whole: what of the stopped run's was held
/// apart where its owner is still kept, and what the effects run here ask.
pub fn run_told() -> Unit {
  for e in told_held {
    // (one stopped since follows nothing: let go, not run)
    if e.deps is Some(_) {
      if run.queued_length < run.queued.length() {
        run.queued[run.queued_length] = Some(e)
      } else {
        run.queued.push(Some(e))
      }
      run.queued_length += 1
    }
  }
  told_held.clear()
  // (what of what waited is still owned, done as the change it told is told whole, in the order it was asked for)
  for k in afters_kept {
    let (o, f, last) = k
    if still_kept(o) {
      if last {
        run.lasts.push(f)
        run.lasts_by.push(Some(o))
      } else {
        run.afters.push(f)
        run.afters_by.push(Some(o))
      }
    }
  }
  afters_kept.clear()
  if run.notify_index < run.queued_length {
    flush()
  } else {
    afters_drained()
  }
}
