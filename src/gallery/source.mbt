// The photos and videos, over wherever they come from (src/coredemo: the
// media service's `media.timeline` and `media.thumbs`): a Source answers
// what the views ask each frame (None while it is still being read).

///|
pub(all) struct Item {
  id : String
  video : Bool
  /// when it was taken, as shown ("14:32")
  time : String
  /// its size in pixels, turned as its EXIF says
  w : Double
  h : Double
  /// ThumbHash, base64: its look while its picture comes
  thumbhash : String
  /// a video's length, in seconds
  duration : Double?
}

///|
pub(all) struct Day {
  /// "YYYY-MM-DD"
  day : String
  items : Array[Item]
}

///|
pub(all) struct Source {
  /// the days read so far, newest first, or why they can't be read
  days : () -> Result[Array[Day], String]?
  /// the grid's picture of an item (an image source), asked for as it shows
  thumb : (Item) -> String
  /// the viewer's
  large : (Item) -> String
  /// the timeline scrolled near its end: older days, if there are any
  older : () -> Unit
}
