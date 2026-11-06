// A chat's rows (sfbase ChatRows) as its windowed list keeps them (mbui ui's ListRows::in_node_indexed): read by index,
// each row's room as it comes, goes or changes height, those going kept where they were till their rooms close. The
// rows are another ChatRows as the chat's messages are another list (a made-up core's, each version); their revisions
// go on from the last one's, the new one's first change all of it.

///|
/// Chat rows `rows` kept in `v` by `sizes`. The snapshot follows them; layout reads the rows captured by that snapshot.
fn rows_sized(
  sizes : @ui.ListRows[Entry],
  v : @view.View,
  rows : () -> @sfbase.ChatRows,
  watched~ : () -> Bool,
  ms~ : (String) -> Double?,
  from~ : (String) -> Double?,
  comes~ : (Entry) -> Bool,
  middle~ : (Entry) -> Bool,
  grown~ : (Entry) -> Bool,
  lead~ : (Entry, Int) -> Double,
  lead_in_layout~ : (Entry, Int) -> (() -> Double),
  own~ : (Entry) -> Bool,
) -> @ui.NodeRowsIndexed[Entry] {
  // (the rows whose revisions are counted from `base` on, and the last revision said)
  let counted : Ref[@sfbase.ChatRows?] = Ref(None)
  let base = Ref(0)
  let last = Ref(0)
  // A layout reads no signals, even untracked. Capture the very same rows whose revision and length the snapshot
  // returns, so every later key, index and change read belongs to that snapshot.
  let captured = Ref(@signals.untracked(rows))
  let now = fn() { captured.val }
  let source : @view.AnchoredSource[String] = {
    snapshot: fn() {
      let cr = rows()
      captured.val = cr
      let (shape, n) = cr.snapshot()
      match counted.val {
        Some(was) if physical_equal(was, cr) => ()
        _ => {
          counted.val = Some(cr)
          base.val = last.val + 1
        }
      }
      last.val = base.val + shape
      (last.val, n)
    },
    key: fn(i) { now().key(i) },
    // (from where it was last read, where it was: a row far from the end found again where it is, not past every row
    // after it, as each frame and each event reads it)
    find: fn(k, near) { now().find_read(k, near) },
    removed_since: fn(since) {
      if since < base.val {
        None
      } else {
        now().removed_since(since - base.val)
      }
    },
    contains: fn(k) { now().contains(k) },
  }
  sizes.in_node_indexed(
    v,
    source,
    fn(i) { now().item(i) },
    fn() {
      now().changes().map(fn(c) {
        match c {
          Came(k) => @ui.RowsChange::Came(k)
          Went(k, e, after) => Went(k, e, after)
          Set(k) => Set(k)
          Whole => Whole
        }
      })
    },
    fn(k) { rows().version_of(k) },
    watched~,
    ms~,
    from~,
    comes~,
    middle~,
    grown~,
    lead~,
    lead_in_layout~,
    own~,
  )
}
