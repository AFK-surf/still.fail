// A height change declared makes its way (View::resizes); what draws a ground by how tall a node shows is given that
// (View::shown_by). Taken, nothing done yet: the scenes that hold them first.

///|
/// In the change the handler it is said in commits, this node coming out another height is for that change's cause
/// (`spec`: how long, ms, and on what curve). Nothing done yet.
pub fn View::resizes(self : View, spec? : (Double, (Double) -> Double)) -> View {
  ignore(spec)
  self
}

///|
/// What draws this node's ground given how tall node `of` shows, where it is drawn. Nothing done yet.
pub fn View::shown_by(self : View, of : View, f : (Double) -> GroundShape) -> View {
  ignore(of)
  ignore(f)
  self
}
