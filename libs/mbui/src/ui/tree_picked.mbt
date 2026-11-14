// What of the window's tree's words is picked with the pointer (tree_select.mbt), as a page made of nodes reads it to
// do something with it (a chat's quote of what is picked in its messages, as an old page reads Ctx::selected_text and
// Ctx::selection_end): followed as a signal (picked_now), once the pointer has let it go; what each paragraph's words are
// of, as what holds them says (picked_of); where it ends, as a piece of the node it ends in for what goes beside it
// (picked_end_piece: placed as the tree is laid out, never read back); let go by a handler (picked_let_go), kept by a
// press on what says so (keeps_picked).

///|
/// What of the window's tree's words is picked with the pointer, once the pointer has let it go (picked_now).
#derive(Eq, Debug)
pub struct WordsPicked {
  /// the words picked, each paragraph's on a line of its own in the page's order (Ctx::selected_text's)
  text : String
  /// what each paragraph picked is of, as what holds it said (picked_of), in the page's order, one said by paragraphs
  /// next to each other once; those whose holders said none left out
  of : Array[String]
  /// the node of the tree's whose words it ends in (where the pointer let it go: dragged down, its last; dragged up,
  /// its first), as it was shown when that paragraph was last found (picked_end_piece: where in it)
  ends_in : @view.NodeId
  /// picked by a finger (held on its words: its handles and the system's text menu over it)
  finger : Bool
  /// which selection it is (Ctx::selection_made): another number for each a press begins
  made : Int
}

///|
/// What of kind `of` the words node `v` holds are of, said for what is picked of them (WordsPicked's `of`: a message's
/// id, by its row). The nearest that says it, it or what holds it.
// kept across runs: what each node lends (View::lends), let go with it
let picked_ofs : @view.Lent[String] = @view.Lent::new()

///|
/// A press on what node `v` holds, or on it, keeps what is picked with the pointer (keeps_picked).
// kept across runs: what each node lends (View::lends), let go with it
let keeps_picks : @view.Lent[Bool] = @view.Lent::new()

///|
/// The words node `v` holds (its own and those of what it holds that are picked with the pointer: words_picked) are
/// of `of` (a message's id), said for what is picked of them (WordsPicked's `of`). `v`.
pub fn picked_of(v : @view.View, of : String) -> @view.View {
  v.lends(picked_ofs, of)
}

///|
/// A press on node `v` or on what it holds (the mouse's down, a finger's tap) keeps what is picked with the pointer, as
/// an old view's Ctx::keeps_selection: a control that does something with it (a quote of it). `v`.
pub fn keeps_picked(v : @view.View) -> @view.View {
  v.lends(keeps_picks, true)
}

///|
/// Whether a press at (x, y) in the window goes to what keeps what is picked (keeps_picked): the node of the tree's it
/// is for, or what holds it, says so.
fn tree_keeps_picked_at(tree : @view.Tree, x : Double, y : Double) -> Bool {
  let id = match tree.target_at(x, y) {
    Pressed(id) | Dragged(id) => id
    _ => return false
  }
  match tree.view_of(id) {
    Some(v) => v.lent(keeps_picks) == Some(true)
    None => false
  }
}

///|
/// What node of the tree's last showed each paragraph that can be picked, and what its words were said to be of
/// (picked_of), as they were found (tree_sels): what is picked is told by them, those scrolled away as they were.
// kept across runs: said as paragraphs are found, those picked kept, the rest let go past a few hundred
let picked_shown : Map[SelKey, (@view.NodeId, String?)] = Map([])

///|
/// Paragraph `base` found shown by node `v` (tree_sels).
fn picked_shown_by(base : SelKey, v : @view.View) -> Unit {
  picked_shown[base] = (v.id(), v.lent(picked_ofs))
  if picked_shown.length() > 512 {
    let gone : Array[SelKey] = []
    picked_shown.each(fn(k, _) {
      if !picked.spans.contains(k) {
        gone.push(k)
      }
    })
    for k in gone {
      picked_shown.remove(k)
    }
  }
}

///|
/// What is picked of each paragraph (those of which some is), in the page's order, and the paragraph it ends in (where
/// the pointer let it go: dragged down, the last; dragged up, the first); None where none is.
fn picked_in_order() -> (Array[(SelKey, SelSpan)], SelKey)? {
  let spans : Array[(SelKey, SelSpan)] = []
  picked.spans.each(fn(k, s) {
    if s.a < s.b {
      spans.push((k, s))
    }
  })
  guard !spans.is_empty() else { return None }
  spans.sort_by(fn(p, q) { order_cmp(p.1.at, q.1.at) })
  let down = spot_cmp(picked.from, picked.to) <= 0
  Some((spans, if down { spans[spans.length() - 1].0 } else { spans[0].0 }))
}

///|
/// What is picked now, as picked_now says it.
// kept across runs: said again as what is picked changes
let picked_now_said : @signals.Signal[WordsPicked?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
/// What of the window's tree's words is picked with the pointer, followed as it changes: once the pointer has let it go
/// (a mouse's button let up, a finger lifted off it or its handle); None while it is dragged, where none is, or where
/// what is picked is an old view's.
pub fn picked_now() -> WordsPicked? {
  picked_now_said.get()
}

///|
/// What is picked with the pointer told to what follows it (picked_now), as it changes and as the pointer lets it go.
fn picked_now_tell() -> Unit {
  picked_now_said.set(picked_now_worked())
}

///|
/// What picked_now says, worked out of what is picked.
fn picked_now_worked() -> WordsPicked? {
  guard tree_picking() && !picked.dragging else { return None }
  guard picked_in_order() is Some((spans, end)) else { return None }
  guard picked_shown.get(end) is Some((ends_in, _)) else { return None }
  let of : Array[String] = []
  for e in spans {
    match picked_shown.get(e.0) {
      Some((_, Some(o))) if of.last() != Some(o) => of.push(o)
      _ => ()
    }
  }
  Some({ text: selected_words(), of, ends_in, finger: picked.finger, made: picked.made })
}

///|
/// Where what `p` says is picked ends (where the pointer let it go: dragged down, the right end of its last line;
/// dragged up, the left end of its first), as a piece of the node it ends in (`p.ends_in`) for what goes beside it
/// (View::beside's `piece`): the end's place on its line and the line's top and height, no wide, laid out as wide as
/// that node is as it is placed, in its own terms. None where its words hold no end of what is picked now (let go, or
/// another picked).
pub fn picked_end_piece(p : WordsPicked) -> (Double, Double) -> (Double, Double, Double, Double)? {
  fn(w, _h) {
    guard picked.made == p.made && view_app.val is Some(tree) else { return None }
    guard tree.view_of(p.ends_in) is Some(v) else { return None }
    let base = tree_key(v)
    guard picked_in_order() is Some((_, end)) && base == end else { return None }
    let (rs, look, set) = v.runs_set_now()
    guard !rs.is_empty() else { return None }
    let (_, lay, _) = view_runs_laid(rs, look, set, w, tree.words_scale_of(v.id()), kept=v.words_breaks_now())
    let rects = selected_rects(base, lay)
    guard !rects.is_empty() else { return None }
    let down = spot_cmp(picked.from, picked.to) <= 0
    let mut r = rects[0]
    for q in rects {
      let later = q.1 > r.1 || (q.1 == r.1 && q.0 > r.0)
      if later == down {
        r = q
      }
    }
    let shift = rich_shift_at(lay, r.1 + r.3 / 2.0, if v.words_centered_now() { w } else { -1.0 })
    Some((r.0 + shift + (if down { r.2 } else { 0.0 }), r.1, 0.0, r.3))
  }
}

///|
/// What a node offers to do with words a finger picked in what it holds, in the system's floating text menu
/// (picked_menu): its items for what is picked, each its words and what choosing it does.
// kept across runs: what each node lends (View::lends), let go with it
let picked_menus : @view.Lent[(WordsPicked) -> Array[(String, () -> Unit)]] = @view.Lent::new()

///|
/// Words a finger picked in what node `v` holds (the node they end in, or what holds it) offer the items `items` says
/// for them in the system's floating text menu over them, in its order, after its copy and select all
/// (@hostapi.text_menu_own: Android's text toolbar, its overflow where they do not fit; iOS's edit menu, paged; the
/// web's bar), each its words and what choosing it does (a quote of them, reading picked_now and letting them go with
/// picked_let_go; the message's share; its link copied), the menu then gone; none (picked across messages, where only
/// one's are quoted), nothing added; @hostapi.text_menu_own_most at most, the rest left out, and those whose words are
/// none. Asked, untracked, as the menu is put up and as what is picked changes. A mouse's pick offers none: no such
/// menu comes over it (what a page shows by it is its own). `v`.
pub fn picked_menu(v : @view.View, items : (WordsPicked) -> Array[(String, () -> Unit)]) -> @view.View {
  v.lends(picked_menus, items)
}

///|
/// What the system's floating text menu offers of the app's own over words a finger picked of the tree's (picked_menu),
/// in its order: what holds the node they end in says; none where nothing does, or where they are not a finger's, not
/// let go, or an old view's.
fn picked_menu_own() -> Array[(String, () -> Unit)] {
  guard picked.finger && picked_now_worked() is Some(p) && view_app.val is Some(tree) else { return [] }
  guard tree.view_of(p.ends_in) is Some(v) && v.lent(picked_menus) is Some(items) else { return [] }
  let all = @signals.untracked(fn() { items(p) }).filter(fn(i) { i.0 != "" && !i.0.contains("\n") })
  if all.length() > @hostapi.text_menu_own_most {
    all.truncate(@hostapi.text_menu_own_most)
  }
  all
}

///|
/// What is picked with the pointer let go, by a handler (a quote taken of it), as Ctx::selection_clear.
pub fn picked_let_go() -> Unit {
  select_none()
}
