// What a node lays what it holds out at, said by what changes it (View::lays_anew): a column held at one width while
// it is drawn at others (a chat's page on its way beside a side panel, laid out as at the narrower end all the way), laid
// out anew at another all at once, in the frame of its cause. As the window made another size lays out anew all it
// holds in the frame it is made so, what this node holds is laid out anew in the frame its width steps: their heights
// and places come out as that width has them there, at once, and a Tester's steadiness judges (ui's sizes_steady.mbt)
// take that frame as that node's step alone, for what it holds alone. Said by the node whose width it is, read where
// it is drawn; nothing else of it is taken so, and a frame it does not step in is judged as any other.

///|
/// The width what it holds is laid out at (points), as what lays it out says it: where it comes out otherwise than it
/// was, all it holds is laid out anew at it in that frame (see the file's head).
#callsite(autofill(loc))
pub fn View::lays_anew(self : View, w : Live[Double], loc~ : SourceLoc) -> View {
  guard self.live() is Some(_) else { return self }
  let tree = self.tree
  let at = self.at
  if !tree.laid_said.contains(at) {
    self.owns(fn() { tree.laid_said.remove(at) }) |> ignore
  }
  self.bind(loc~, LaysAnew, w, Layout, fn(w) { tree.laid_said[at] = w })
  self
}

///|
/// The width node `at` says what it holds is laid out at (View::lays_anew), if it says one and lives.
pub fn Tree::laid_said_of(self : Tree, at : Int) -> Double? {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return None }
  self.laid_said.get(at)
}
