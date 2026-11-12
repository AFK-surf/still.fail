// What a page's list has in sight, told to handlers (ListPlace::on_sight, ListPlace::sight_now): STUB, the acceptance
// tests' commit alone, nothing of it done.

///|
/// What a page's list (View::scrolls_window) has in sight, counted by its keys' blocks (its head and its foot never
/// the first or the last): `first` the first key that shows and `into` how far the top of what shows is down its
/// block's top (less than 0 where its head shows over it: how much of the head shows), `last` the last that shows,
/// `whole` the last wholly in what shows (over the foot's top, where it has one; none where none is), `from_foot` how
/// far it is scrolled from its foot, `shows` how tall what shows is, `at_foot` whether it is at its foot.
#derive(Eq, Debug)
pub(all) struct Sight[K] {
  first : K
  into : Double
  last : K
  whole : K?
  from_foot : Double
  shows : Double
  at_foot : Bool
}

///|
/// `f` told what the list has in sight as that changes: at an input, at the end of a glide or a way that moved what
/// shows, at a change of data at rest; never as a frame is drawn on a way. STUB: taken, never told.
pub fn[K] ListPlace::on_sight(self : ListPlace[K], f : (Sight[K]) -> Unit) -> Unit {
  self.sight_fns.push(f)
}

///|
/// What was last told of what the list has in sight (ListPlace::on_sight), for a handler to read; none before its
/// first layout. STUB: none.
pub fn[K] ListPlace::sight_now(self : ListPlace[K]) -> Sight[K]? {
  self.sight
}
