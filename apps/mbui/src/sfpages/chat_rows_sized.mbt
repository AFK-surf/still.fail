// A chat's rows (sfbase ChatRows) as its windowed list keeps them: each row's room as it comes, goes or changes
// height (mbui ui's ListRows), the rows going kept where they were till their rooms close, read by index.
// FIXME(chat-rows-list): over ListRows::in_node, every row made into an array each change, till
// ListRows::in_node_indexed lands; the page reads only what this gives.

///|
/// A chat's rows as its list lays them out (rows_sized).
priv struct SizedRows {
  /// the rows and those going, for the list to lay out (View::scrolls_anchored's `indexed`)
  source : @view.AnchoredSource[String]
  /// the row keyed so and where it is among them (a row going too), followed by what it shows
  item_of : (String) -> (Entry, Int)?
  room_now : () -> (String, Double) -> @view.ListRoom
  moving : () -> Array[String]
  lend : (@view.View, String) -> Unit
  opening : () -> Bool
}

///|
/// Chat rows `rows` (the ChatRows now, followed) kept in `v` by `sizes`, each message's row keyed by `key_of`.
fn rows_sized(
  sizes : @ui.ListRows[Entry],
  v : @view.View,
  rows : () -> @sfbase.ChatRows,
  key_of : (Entry) -> String,
  version : (Entry) -> String,
  watched~ : () -> Bool,
  ms~ : (String) -> Double?,
  from~ : (String) -> Double?,
  comes~ : (Entry) -> Bool,
  middle~ : (Entry) -> Bool,
  grown~ : (Entry) -> Bool,
  lead~ : (Entry, Int) -> Double,
  lead_in_layout~ : (Entry, Int) -> (() -> Double),
  own~ : (Entry) -> Bool,
) -> SizedRows {
  let items = fn() {
    let cr = rows()
    let n = cr.length()
    // (what each row shows: the list compares their versions)
    for i in 0..<n {
      cr.version_of(cr.key(i)) |> ignore
    }
    @signals.untracked(fn() { Array::makei(n, fn(i) { cr.entry(i) }) })
  }
  let sized = sizes.in_node(v, items, key_of, version, watched~, ms~, from~, comes~, middle~, grown~, lead~, lead_in_layout~, own~)
  let shape = Ref(0)
  let was : Ref[Array[String]] = Ref([])
  let index = @signals.computed(fn(_) {
    let m : Map[String, Int] = {}
    for i, k in (sized.read)().1 {
      m[k] = i
    }
    m
  })
  let source : @view.AnchoredSource[String] = {
    snapshot: fn() {
      let keys = (sized.read)().1
      if !physical_equal(keys, was.val) {
        was.val = keys
        shape.val += 1
      }
      (shape.val, keys.length())
    },
    key: fn(i) { @signals.untracked(fn() { (sized.read)().1[i] }) },
    find: fn(k, _) { @signals.untracked(fn() { index.get().get(k) }) },
    removed_since: fn(_) { None },
    contains: fn(k) { @signals.untracked(fn() { index.get().contains(k) }) },
  }
  {
    source,
    item_of: fn(k) {
      let cr = rows()
      cr.version_of(k) |> ignore
      index.get().get(k).map(fn(i) { ((sized.read)().0[i], i) })
    },
    room_now: sized.room_now,
    moving: sized.moving,
    lend: sized.lend,
    opening: sized.opening,
  }
}
