// A texture owned by the host, drawn with the tree's ordinary composition.

///|
pub(all) enum TextureFit {
  TextureFill
  TextureCover(Double)
  TextureContain
} derive(Eq, Debug)

///|
/// The host's texture, its natural pixel size and how it fits the node. `direct` permits a host-provided layer where
/// the whole picture can be presented as it is. `revision` changes when its pixels change without a new handle.
pub(all) struct Texture {
  id : Int
  width : Int
  height : Int
  fit : TextureFit
  direct : Bool
  revision : Int64
} derive(Eq, Debug)

///|
/// A host texture over this node's ground, under what it holds. Its place, opacity, corners and ancestor clips are the
/// node's. The host owns the texture; removing the node does not dispose of it.
pub fn View::texture(self : View, texture : Live[Texture?]) -> View {
  self.bind(Texture, texture, Paint, fn(t) { self.tree.nodes[self.at].look.texture = t })
  self
}
