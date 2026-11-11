///|
/// What `Show` wrote for an option, an array and four numbers of plain values, written out: for a text that is a value
/// (a key, a line a script or a test reads, what a test compares as it was written), kept as it was when the `Show` of
/// a composed value went. A value shown for a person who debugs is `Repr(x)`, not these.
pub fn[T : Show] some_text(o : T?) -> String {
  match o {
    Some(v) => "Some(\{v})"
    None => "None"
  }
}

///|
pub fn[T : Show] list_text(xs : Array[T]) -> String {
  "[" + xs.map(fn(x) { x.to_string() }).join(", ") + "]"
}

///|
pub fn rect_text(r : (Double, Double, Double, Double)) -> String {
  "(\{r.0}, \{r.1}, \{r.2}, \{r.3})"
}
