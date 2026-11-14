// Experimental: an independently releasable reader for work started before a page owns its graph.

///|
pub struct TopicLease {
  priv source : Source
  priv state : @signals.Computed[TopicState]
  priv watch : @signals.Watch
  priv name : String
  priv params : Map[String, Json]
  priv mut active : Bool
  priv mut cancelling : Bool
  priv mut unkeep : (() -> Unit)?
  priv mut source_unkeep : (() -> Unit)?
  priv mut revision : Int
}

///|
fn lease_source_alive(src : Source) -> Bool {
  @signals.untracked(fn() { (src.topic_alive)() })
}

///|
pub fn Source::lease_topic(src : Source, name : String, params : Map[String, Json]) -> TopicLease {
  let key = params.copy()
  let state = scoped_topic(src, name, key, independent=true)
  let watch = held_watch()
  let mut active = lease_source_alive(src)
  if active {
    watch.read(fn() { state.get() }) |> ignore
    active = lease_source_alive(src)
    if !active { watch.stop() }
  }
  let lease : TopicLease = { source: src, state, watch, name, params: key, active, cancelling: false, unkeep: None, source_unkeep: None, revision: 0 }
  lease.attach_source_owner(src)
  if lease.active && !lease_source_alive(src) { lease.release() }
  lease
}

///|
fn TopicLease::attach_source_owner(self : TopicLease, src : Source) -> Unit {
  if !self.active { return }
  match src.topic_lease_own {
    Some(own) => {
      let unkeep = own(fn() { self.release() })
      if self.active { self.source_unkeep = Some(unkeep) } else { unkeep() }
    }
    None => ()
  }
}

///|
/// Attach cleanup to a view. This does not change which Source the reader follows.
pub fn TopicLease::bind_to(self : TopicLease, view : @view.View) -> Unit {
  if !self.active || self.cancelling { return }
  self.revision += 1
  match self.unkeep {
    Some(unkeep) => unkeep()
    None => ()
  }
  self.unkeep = None
  if !view.alive() {
    self.release()
    return
  }
  self.unkeep = Some(view.owns_while(fn() { self.release() }))
}

///|
/// Transfer the same reader to another view, invalidating this handle without stopping the shared watch.
pub fn TopicLease::detach_to(self : TopicLease, view : @view.View) -> TopicLease? {
  if !self.active || self.cancelling || !view.alive() { return None }
  let next : TopicLease = {
    source: self.source, state: self.state, watch: self.watch, name: self.name, params: self.params,
    active: true, cancelling: false, unkeep: None, source_unkeep: None, revision: 0,
  }
  next.unkeep = Some(view.owns_while(fn() { next.release() }))
  if !view.alive() {
    match next.unkeep { Some(unkeep) => unkeep(); None => () }
    next.active = false
    return None
  }
  self.active = false
  self.revision += 1
  match self.unkeep {
    Some(unkeep) => { self.unkeep = None; unkeep() }
    None => ()
  }
  match self.source_unkeep {
    Some(unkeep) => { self.source_unkeep = None; unkeep() }
    None => ()
  }
  if !view.alive() { next.release() }
  if next.active { Some(next) } else { None }
}

///|
/// Establish a new reader before ending this one. On success this handle becomes inactive; only the returned
/// handle can end the new reader. A delayed callback holding the old handle therefore cannot cancel the new owner.
pub fn TopicLease::transfer_to(self : TopicLease, source : Source, view : @view.View) -> TopicLease? {
  if !self.active || self.cancelling || !view.alive() { return None }
  let revision = self.revision
  let usable = lease_source_alive(source)
  if !usable || !self.active || self.revision != revision || !view.alive() { return None }
  let next_state = scoped_topic(source, self.name, self.params, independent=true)
  let next_watch = held_watch()
  next_watch.read(fn() { next_state.get() }) |> ignore
  let still_usable = lease_source_alive(source)
  if !still_usable || !self.active || self.revision != revision || !view.alive() {
    next_watch.stop()
    return None
  }
  let next : TopicLease = {
    source, state: next_state, watch: next_watch, name: self.name, params: self.params,
    active: true, cancelling: false, unkeep: None, source_unkeep: None, revision: 0,
  }
  next.attach_source_owner(source)
  next.bind_to(view)
  if !next.active || !self.active || self.revision != revision || !view.alive() {
    next.release()
    return None
  }
  // Invalidate the old handle and detach its view cleanup before stopping its watch. Stopping may call application
  // code, including a late cancel from the old owner, and that callback must not control the new handle.
  let previous = self.watch
  self.active = false
  self.revision += 1
  match self.unkeep {
    Some(unkeep) => { self.unkeep = None; unkeep() }
    None => ()
  }
  match self.source_unkeep {
    Some(unkeep) => { self.source_unkeep = None; unkeep() }
    None => ()
  }
  previous.stop()
  if !next.active || !view.alive() { return None }
  let alive = lease_source_alive(source)
  if !alive { next.release() }
  if alive && next.active && view.alive() { Some(next) } else { None }
}

///|
pub fn TopicLease::read(self : TopicLease) -> TopicState? {
  if !self.active || self.cancelling { return None }
  let revision = self.revision
  let state = self.state
  let value = self.watch.read(fn() { state.get() })
  if self.active && self.revision == revision { Some(value) } else { None }
}

///|
/// The topic as it stands, read where it is read (a binding, an effect: told again as it changes) through this handle's
/// reader, holding nothing more; None once it is let go of. What reads it so holds the reader with it till it stops.
pub fn TopicLease::follow(self : TopicLease) -> TopicState? {
  if !self.active || self.cancelling { return None }
  Some(self.state.get())
}

///|
/// Whether this handle still owns its reader, including after an explicit move to another view.
pub fn TopicLease::alive(self : TopicLease) -> Bool {
  self.active && !self.cancelling
}

///|
/// Cancel an early read and tell the source which independently held reader is ending.
pub fn TopicLease::cancel(self : TopicLease) -> Unit {
  if !self.active || self.cancelling { return }
  self.cancelling = true
  let stop = fn() { self.release() }
  (self.source.leave)(self.name, self.params, Owned(stop))
  stop()
}

///|
pub fn TopicLease::release(self : TopicLease) -> Unit {
  if !self.active { return }
  self.active = false
  self.revision += 1
  match self.unkeep {
    Some(unkeep) => {
      self.unkeep = None
      unkeep()
    }
    None => ()
  }
  match self.source_unkeep {
    Some(unkeep) => { self.source_unkeep = None; unkeep() }
    None => ()
  }
  self.watch.stop()
}
