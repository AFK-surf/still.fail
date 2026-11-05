// A picture's fit is a drawing rule. Its allocated box belongs to layout;
// fitting the decoded picture into that box never publishes geometry to state.

///|
pub(all) enum Fit {
  FitCover
  FitCoverAt(Double)
  FitContain
  FitFill
} derive(Eq, Debug)

///|
/// Fit the picture to its allocated box, with a matte around a contained image.
/// The host resolves the crop from the current box and the decoded dimensions.
pub fn View::image_fits(self : View, fit : Live[(Fit, Int64)]) -> View {
  self.bind(ImageFit, fit, Paint, fn(fit) { self.tree.nodes[self.at].look.image_fit = fit })
  self
}
