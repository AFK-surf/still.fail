// What a page's list has in sight, told to handlers (ListPlace::on_sight, ListPlace::sight_now): for what keeps
// accounts and tells the core of them (what is read, the way back to its foot, a table of contents following), never
// for what is made or bound (its result is no layout's: detlint's layout-told, by name). Counted by its keys' blocks
// as they come to rest (each as tall as it is counted, not as a way has it on its way), the scroll where it rests (at
// its foot where it follows it, where a wheel's notch eases to, where it is as a fling goes): what is told at a cause is
// where that cause leaves it, not a frame on its way there. Told at the moments what is under a still pointer is found
// again (Tree::hand_at_end's): the change of an input or of data, as it is told whole, one at its moment
// (View::at_moment), a glide's or a way's end, the window given another size, its first layout; never on a frame as a
// glide or a way goes; only as it differs from what was told last; and once the layout that does what its place asked
// (ListPlace::bring, centre, to_end) is done. It is read off the blocks as they are counted (one not measured yet as
// `est`, told again with its height at its way's end) and the scroll: telling lays out and measures nothing. A list
// none listens to (no ListPlace::on_sight) has nothing of it worked out or owed, at any moment. A key coming by data
// on its way in is not seen whole, nor the list at its foot with all of it there whole, till that key is drawn whole:
// at its way's end, told then once (its way's end a moment the hand is found again at); where it comes at once (an
// answer's, an at_once list's, motion reduced), in the change (the coordinator of the migration, 2026-11-14: a chat
// told a message read before its words showed). Where the list is (`at_foot`, `from_foot`) is as it lays out.

///|
/// What a page's list (View::scrolls_window) has in sight, counted by its keys' blocks (its head and its foot never
/// the first or the last): `first` the first key that shows under what covers its top (Scroll::top_covered: the bar it
/// runs under; none, its own top) and `into` how far that edge is down its block's top (less than 0 where its head
/// shows under it: as much as the head shows, a table of contents telling that from its first key at the top), `last`
/// the last that shows, `whole` the last wholly in what shows (its top no higher than the edge under what covers its
/// top, its foot over the foot's top, where it has them; none where none is) and drawn whole (before the first in
/// sight still on its way in), `from_foot` how far it is scrolled from its foot, `shows` how tall what shows is,
/// `at_foot` whether it is at its foot (where the list is, as it lays out: what follows it, a way back to it),
/// `foot_whole` whether it is at its foot with none from the first in sight on still on its way in (its end seen).
#derive(Eq, Debug)
pub(all) struct Sight[K] {
  first : K
  into : Double
  last : K
  whole : K?
  from_foot : Double
  shows : Double
  at_foot : Bool
  foot_whole : Bool
}

///|
/// `f` told what the list has in sight as that changes (the file's head): at an input, at the end of a glide or a way
/// that moved what shows, at a change of data, its first layout; never as a frame is drawn on a way; never twice the
/// same in a row. For a handler's accounts, never for what is made.
pub fn[K] ListPlace::on_sight(self : ListPlace[K], f : (Sight[K]) -> Unit) -> Unit {
  self.sight_fns.push(f)
  // (its list told it from now: none listening, nothing of it is worked out or owed)
  (self.sight_listened)()
}

///|
/// What was last told of what the list has in sight (ListPlace::on_sight), for a handler to read; where none is told
/// it, what it has in sight as it is counted now; none before its first layout.
pub fn[K] ListPlace::sight_now(self : ListPlace[K]) -> Sight[K]? {
  if self.sight_fns.is_empty() {
    (self.sight_of)()
  } else {
    self.sight
  }
}

///|
/// What the list has in sight now told to what is told it, where it differs from what was told last.
fn[K : Eq] ListPlace::sight_tell(self : ListPlace[K]) -> Unit {
  guard (self.sight_of)() is Some(now) else { return }
  if self.sight == Some(now) {
    return
  }
  self.sight = Some(now)
  for f in self.sight_fns {
    f(now)
  }
}

///|
/// What blocks `all` (as they are counted) have in sight in scroll `s` at moment `t`, the foot's room `foot` under them
/// and the room kept under the last block `room` over that (View::scrolls_window's foot_room: at its foot is at that
/// room's foot), the blocks at `coming` (by where each is among them) on their way in (Sight's); none where none is or
/// nothing shows yet.
fn[K] sight_counted(
  all : Places[K],
  s : Scroll,
  t : Double,
  foot : Double,
  room : Double,
  coming : Array[Int],
) -> Sight[K]? {
  let n = all.length()
  guard n > 0 && s.seen.get() is Some((_, vh)) && vh > 0.0 else { return None }
  let most = dmax(0.0, all.foot() + room + foot + s.tuck_room.get() - vh)
  // (where it rests: at its foot where it follows it; where a notch eases to; else where it is now)
  let x = if s.x.get() == @double.infinity {
    most
  } else {
    match s.notch.get() {
      Some(nt) if s.fling.get() is None && s.edge.get() is None => nt.x0 + nt.total
      _ => s.where_at(t)
    }
  }
  let x = dclamp(x, 0.0, most)
  let below = x + vh
  // (the first with something showing under what covers its top (Scroll::top_covered: the bar it runs under), how far
  // down it that edge is)
  let under = x + s.top_covered()
  let i = all.first_past(under).min(n - 1)
  let j = (all.first_past(below - 1.0e-6).min(n - 1)).max(i)
  // (wholly in what shows: its foot no lower than the foot's top, its top no higher than the edge under what covers its
  // top)
  // (and drawn whole: before the first from the first in sight on still on its way in)
  let mut c = n
  for q in coming {
    if q >= i && q < c {
      c = q
    }
  }
  let k = (all.first_past(below - foot + 1.0e-6) - 1).min(c - 1)
  let whole = if k >= 0 && k >= i && all.top(k) >= under - 1.0e-6 { Some(all.key(k)) } else { None }
  Some({
    first: all.key(i),
    into: under - all.top(i),
    last: all.key(j),
    whole,
    from_foot: most - x,
    shows: vh,
    at_foot: most - x <= 1.0e-6,
    foot_whole: most - x <= 1.0e-6 && c == n,
  })
}
