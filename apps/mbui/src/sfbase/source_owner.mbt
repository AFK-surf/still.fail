// A source owned by a view keeps the topics it has read while that view remains alive. A view can explicitly leave
// a topic sooner; different views keep independent readers of the same core subscription.

///|
priv struct ViewSourceTopic {
  key : String
  reading : String
  state : @signals.Computed[TopicState]
  watch : @signals.Watch
}

///|
priv struct ViewSourceOwner {
  base : Source
  live : @signals.Signal[Bool]
  mut reading : TopicReadMode
  mut topics : Array[ViewSourceTopic]
  leaving : Map[String, Bool]
}

///|
fn view_source_forget(owner : ViewSourceOwner, name : String, params : Map[String, Json]) -> Unit {
  let key = (owner.base.topic_key)(name, params)
  let leaving = owner.topics.filter(fn(t) { t.key == key })
  owner.topics = owner.topics.filter(fn(t) { t.key != key })
  for t in leaving {
    t.watch.stop()
  }
}

///|
fn view_owner_follow(owner : ViewSourceOwner, name : String, params : Map[String, Json], mode : TopicReadMode) -> @signals.Computed[TopicState]? {
  // The lease has its own view cleanup; while being transferred it can move independently of this source's view.
  // Keep the call through the source so wrappers can still remap the topic and its parameters.
  if mode is Lease {
    return Some(scoped_topic(owner.base, name, params, independent=true))
  }
  if !owner.live.get() {
    return None
  }
  // A graph owns its own dependencies. Only an untracked read needs a separate watch belonging to the view.
  if mode is Graph {
    return Some(scoped_topic(owner.base, name, params))
  }
  let key = (owner.base.topic_key)(name, params)
  let reading = exact_topic_key(name, params)
  // Equal wire identities may still have different source-side projections, so only reuse the same raw read's value.
  match owner.topics.iter().find_first(fn(t) { t.reading == reading }) {
    Some(topic) => return Some(topic.state)
    None => ()
  }
  // The owner's watch follows the underlying source, so it does not recursively acquire itself.
  let state = scoped_topic(owner.base, name, params)
  let watch = held_watch()
  owner.topics.push({ key, reading, state, watch })
  watch.read(fn() { state.get() }) |> ignore
  Some(state)
}

///|
/// A source whose reads belong to `view`. A topic is released when this view explicitly leaves it or is let go;
/// another view or graph reader may still hold the same core subscription.
pub fn Source::owned_by(src : Source, view : @view.View) -> Source {
  let owner : ViewSourceOwner = { base: src, live: @signals.signal(view.alive()), reading: Raw, topics: [], leaving: {} }
  let owned : Source = {
    ..src,
    topic_alive: fn() { owner.live.get() && (src.topic_alive)() },
    topic_lease_own: Some(fn(stop) {
      let parent = match src.topic_lease_own { Some(own) => Some(own(stop)); None => None }
      let here = view.owns_while(stop)
      fn() {
        here()
        match parent { Some(unkeep) => unkeep(); None => () }
      }
    }),
    topic_scope: Some(fn(mode, read) {
      let was = owner.reading
      owner.reading = mode
      let value = read()
      owner.reading = was
      value
    }),
    topic_read: fn(name, params) {
      // Only this delegated read is part of the caller's graph. A callback it invokes may itself make a raw prefetch.
      let mode = owner.reading
      owner.reading = Raw
      let value = match view_owner_follow(owner, name, params, mode) {
        Some(state) => {
          let topic = state.get()
          { value: topic.value, error: topic.error, version: topic.version }
        }
        None => { value: None, error: None, version: 0 }
      }
      owner.reading = mode
      value
    },
    waits: fn(name, params) {
      let mode = owner.reading
      owner.reading = Raw
      let value = match view_owner_follow(owner, name, params, mode) {
        Some(state) => state.get().waiting
        None => false
      }
      owner.reading = mode
      value
    },
    leave: fn(name, params, reason) {
      let key = (src.topic_key)(name, params)
      let ended = Ref(false)
      let stop = fn() {
        if ended.val { return }
        ended.val = true
        match reason {
          Legacy => view_source_forget(owner, name, params)
          Owned(release) => release()
        }
      }
      // A legacy leave has no handle by which to recognize a recursive call. Owned capabilities have distinct
      // identities and can be cancelled independently even when they cover the same topic.
      let legacy = reason is Legacy
      if legacy && owner.leaving.contains(key) {
        stop()
        return
      }
      if legacy { owner.leaving[key] = true }
      // The base observes the leave, but is given only this owner's release capability.
      (src.leave)(name, params, Owned(stop))
      if legacy { owner.leaving.remove(key) }
      stop()
    },
  }
  if !view.alive() {
    return owned
  }
  view.owns(fn() {
    owner.live.set(false)
    let topics = owner.topics
    owner.topics = []
    for t in topics {
      t.watch.stop()
    }
  }) |> ignore
  owned
}

///|
/// A source whose reads belong to `view` while `shown()` says it shows (a page of a stack: not while one put over it
/// covers it): Source::owned_by's, each topic read through a gate of its own. While it shows, a topic as it stands,
/// followed; once it is covered (at that cause's moment), its subscription let go and what is read of it the last that
/// came before then (none where none had: as a topic not yet answered reads), so nothing of what reads it is worked
/// out again while it is covered; shown again, followed again from that moment, read as it last was until the core
/// answers (no empty list, no waiting between), then as it stands. What it keeps goes with `view`.
pub fn Source::shown_by(src : Source, view : @view.View, shown : () -> Bool) -> Source {
  let owned = src.owned_by(view)
  // (each topic's last value before it was covered, by its key: what it reads as while it is)
  let last : Map[String, TopicState] = {}
  let gates : Map[String, @signals.Computed[TopicState]] = {}
  let gate = fn(name : String, params : Map[String, Json]) -> @signals.Computed[TopicState] {
    let key = (src.topic_key)(name, params)
    match gates.get(key) {
      Some(g) => g
      None => {
        let none : TopicState = { value: None, error: None, version: 0, waiting: false }
        let g = @signals.computed(
          // (what it last read is written only while it shows, from the topic as it stands then: covered, this reads
          // `last` and writes nothing, so nothing worked out while it is covered (it is not, as nothing it reads
          // changes but `shown`) puts an older value back; shown again, the first value the core gives is what it
          // reads from then, `last` only standing in till the core has said something)
          fn(_) {
            if shown() {
              let now = owned.topic(name, params).get()
              // (held now: let go of as it is covered, it is kept and asked again with its version as it shows,
              // whatever the topic: what this page read of it is held here meanwhile, the core's `same` or what changed
              // since all that comes again of it)
              (src.keep_left)(name, params)
              match last.get(key) {
                // (followed again, the core not answered yet: as it was)
                Some(was) if now.value is None && now.error is None => was
                _ => {
                  last[key] = now
                  now
                }
              }
            } else {
              last.get(key).unwrap_or(none)
            }
          },
          // (the same as it was, the very value: what reads it not worked out again)
          same=fn(a, b) { physical_equal(a, b) },
        )
        gates[key] = g
        g
      }
    }
  }
  view.owns(fn() {
    gates.clear()
    last.clear()
  })
  |> ignore
  {
    ..owned,
    topic_alive: fn() { shown() && (owned.topic_alive)() },
    topic_read: fn(name, params) { gate(name, params).get().snapshot() },
    waits: fn(name, params) { gate(name, params).get().waiting },
  }
}

///|
/// What `make` makes of a page of stack `nav` (as nav_view's and nav_flat_view's `made` ask it) with what it reads its own
/// while it shows (Source::shown_by): `make` given, for each page as it is made, `src` held by that page's node while the
/// view holding the stack shows it (Nav::page_shows, at its causes' moments, as a page of the stack's old view is held:
/// its `visible`), so a page covered lets go of what it read and reads it again as it shows; a page of a kind `kept`
/// says (a chat: what it reads held as long as its entry is on the stack, as page_for holds a chat's page) given `src`
/// as it is. The page asks nothing of it.
pub fn[P] shown_made(
  nav : @ui.Nav[P],
  src : Source,
  kept? : (String) -> Bool = fn(_) { false },
  make : (Source) -> (String, (@view.View, () -> P, P?, () -> Int, Int) -> Unit)?,
) -> (String, (@view.View, () -> P, P?, () -> Int, Int) -> Unit)? {
  match make(src) {
    Some((kind, f)) if kept(kind) => Some((kind, f))
    Some((kind, _)) =>
      Some(
        (
          kind,
          fn(outer, page, under, stint, serial) {
            match make(src.shown_by(outer, fn() { nav.page_shows(serial) })) {
              Some((_, f)) => f(outer, page, under, stint, serial)
              None => ()
            }
          },
        ),
      )
    None => None
  }
}
