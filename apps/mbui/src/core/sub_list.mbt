// A subscription's keyed lists read by their index (stillfail/rows' TopicList, mbui docs/retained.md rule 12): a
// list asked for is its own, the core's keyed ops on it done to it alone (no copy of the whole value, no item's key
// made again to find one); the rest of the value changes as delta.mbt applies the ops, and the whole value, its lists
// in their places, is made only as it is read (Sub::value).

///|
/// The list at `path` of its value (fields of objects from its top) as a list read by index, by the keys its `fields`
/// make (core-ts collections.ts: a chat's messages `["seq", "outgoing"]`): made as it is first asked for, from the
/// value as it is, the same one after.
pub fn Sub::list(self : Sub, path : Array[String], fields : Array[String]) -> @rows.TopicList {
  for l in self.lists {
    if l.path() == path {
      return l
    }
  }
  let l = @signals.untracked(fn() { @rows.TopicList::new(path, fields, self.value()) })
  self.lists.push(l)
  l
}

///|
/// Its value (None until the first, and after an error until the next), its lists asked for in their places: put in
/// as it is read, where they changed since.
pub fn Sub::value(self : Sub) -> Json? {
  if !self.lists_in {
    self.lists_in = true
    match self.whole {
      Some(v) => {
        let mut now = v
        for l in self.lists {
          now = @rows.with_at(now, l.path(), l.to_json())
        }
        self.whole = Some(now)
      }
      None => ()
    }
  }
  self.whole
}

///|
/// A message's delta `ops` taken (Client::take): each op done to the list it is of, else applied to `was`; the value
/// after them (its lists put in only as it is read: Sub::value).
fn Sub::lists_take(self : Sub, was : Json, ops : Array[Json]) -> Json {
  if self.lists.is_empty() {
    return @rows.apply_delta(was, ops)
  }
  let mut now = was
  @signals.untracked(fn() {
    for op in ops {
      guard op is Object(o) else { continue }
      let mut took = false
      for l in self.lists {
        match l.take(o) {
          @rows.NotMine => ()
          @rows.Done => {
            took = true
            self.lists_in = false
          }
          @rows.Anew => {
            // (the list or what holds it set: the value as it was, its lists in, the op on it, the list from that)
            for m in self.lists {
              m.come_in()
            }
            self.whole = Some(now)
            now = @rows.apply_delta(self.value().unwrap(), [op])
            l.given(Some(now))
            took = true
          }
        }
        if took {
          break
        }
      }
      if !took {
        now = @rows.apply_delta(now, [op])
      }
    }
    for l in self.lists {
      l.come_in()
    }
  })
  now
}

///|
/// Its value given whole (or none: an error): each list given whole.
fn Sub::lists_given(self : Sub) -> Unit {
  self.lists_in = true
  if self.lists.is_empty() {
    return
  }
  @signals.untracked(fn() {
    for l in self.lists {
      l.given(self.whole)
    }
  })
}

///|
/// Its value with each list asked for (Sub::list) left out (null in its place), as what reads the rest of it reads it:
/// made as the value changes, only along the lists' paths (none of a list gone through), the same one till then.
pub fn Sub::rest(self : Sub) -> Json? {
  if self.lists.is_empty() {
    return self.whole
  }
  match self.rest {
    Some((version, v)) if version == self.version => return v
    _ => ()
  }
  let v = match self.whole {
    Some(w) => {
      let mut now = w
      for l in self.lists {
        now = @rows.with_at(now, l.path(), Json::null())
      }
      Some(now)
    }
    None => None
  }
  self.rest = Some((self.version, v))
  v
}
