// Films and series, over wherever they come from (src/coredemo: the media
// service's `media.videos`, `media.video`, `media.video.poster`): a Source
// answers what the views ask each frame (None while it is still being read).

///|
pub(all) enum Kind {
  Movie
  Show
} derive(Eq)

///|
/// Where one was left: seconds in, and whether it was seen to the end.
pub(all) struct Place {
  position : Double
  done : Bool
}

///|
pub(all) struct Title {
  id : String
  kind : Kind
  title : String
  year : Int?
  /// ThumbHash of its poster, base64
  thumbhash : String
  place : Place?
  /// a series': how many seasons and episodes, how many not seen
  seasons : Int
  episodes : Int
  unwatched : Int
}

///|
pub(all) struct Library {
  /// 继续观看
  recent : Array[Title]
  movies : Array[Title]
  shows : Array[Title]
}

///|
pub(all) struct Episode {
  id : String
  episode : Int
  title : String
  /// seconds
  duration : Double
  place : Place?
}

///|
pub(all) struct Season {
  season : Int
  episodes : Array[Episode]
}

///|
pub(all) struct Detail {
  kind : Kind
  title : String
  original : String
  year : Int?
  plot : String
  genres : Array[String]
  /// a film's, in seconds
  duration : Double
  place : Place?
  seasons : Array[Season]
}

///|
pub(all) struct Source {
  library : () -> Result[Library, String]?
  detail : (String) -> Result[Detail, String]?
  /// the poster of a film or series (an image source)
  poster : (Title) -> String
  /// play a film or an episode, by its id, from `at` seconds
  play : (String, Double) -> Unit
}
