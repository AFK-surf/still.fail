///|
test "the search read last is let go of as the next words are read and as the search closes" {
  let read : Array[String] = []
  let left : Array[String] = []
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic_read: fn(name, params) {
      if name == "search" {
        read.push((if params.get("query").unwrap() is String(s) { Some(s) } else { None }).unwrap())
      }
      made.topic(name, params).get().snapshot()
    },
    leave: fn(name, params, __reason) {
      if __reason is @sfbase.TopicLeave::Owned(__stop) { __stop(); return }
      if name == "search" {
        left.push((if params.get("query").unwrap() is String(s) { Some(s) } else { None }).unwrap())
      }
    },
  }
  finder_cleared()
  left.clear()
  // each frame reads the words as they are: the same words are held, others let the last go
  ignore(search_of(src, "w", "u"))
  ignore(search_of(src, "w", "u"))
  ignore(search_of(src, "w", "up"))
  ignore(search_of(src, "w", "upd"))
  assert_eq(left, ["u", "up"])
  finder_cleared()
  assert_eq(left, ["u", "up", "upd"])
  // closed again: nothing more to let go
  finder_cleared()
  assert_eq(left, ["u", "up", "upd"])
  assert_eq(read.length(), 4)
}
