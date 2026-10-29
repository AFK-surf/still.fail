///|
test "the search read last is let go of as the next words are read and as the search closes" {
  let read : Array[String] = []
  let left : Array[String] = []
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic: fn(name, params) {
      if name == "search" {
        read.push(params.get("query").unwrap().as_string().unwrap())
      }
      (made.topic)(name, params)
    },
    leave: fn(name, params) {
      if name == "search" {
        left.push(params.get("query").unwrap().as_string().unwrap())
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
