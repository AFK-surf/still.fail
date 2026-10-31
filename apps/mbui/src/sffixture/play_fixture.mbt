// The player over the made-up drive (APP=sffix MBUI_FIXTURE=player-<what>; scripts/shots.sh player, web-player): a folder
// of 文档 that no listing shows (影片: three episodes, a subtitle beside the second, a song), its files' reads never
// answered (the player waits, as on a slow link, the same on every run) but the subtitle's; how the player stands pinned
// for the shot (`@kit.Media::pin`): an episode paused at 5:12 of 23:24 with its subtitle, the song, an episode at its
// end with the next one offered, one that failed, one still opening. Every word in it is made up.

///|
pub let fix_films : String = "影片"

///|
pub fn fix_film_entries() -> Array[Json] {
  [
    fix_entry("第01集.mp4", false, 210331000, "10/02"),
    fix_entry("第02集.mp4", false, 198220000, "10/02"),
    fix_entry("第02集.srt", false, 2210, "10/02"),
    fix_entry("第10集.mp4", false, 201004000, "10/09"),
    fix_entry("片尾曲.m4a", false, 3401000, "9/30"),
  ]
}

///|
pub let fix_srt : String =
  #|1
  #|00:05:08,000 --> 00:05:11,000
  #|站台上的灯还亮着。
  #|
  #|2
  #|00:05:11,200 --> 00:05:14,500
  #|<i>我们再等一班车吧，</i>
  #|反正也不急。
  #|

///|
/// A made-up film's part, or the subtitle (`drive.read`): true when it is one of them (a film's never answered).
pub fn fixture_play_read(params : Json, done : (Result[(Json, Bytes), Json]) -> Unit) -> Bool {
  let path = text(Some(params), "path")
  if !path.has_prefix(fix_films + "/") {
    return false
  }
  fix_reads.push(params)
  if path.has_suffix(".srt") {
    let whole = @utf8.encode(fix_srt)
    let offset = number(Some(params), "offset").to_int()
    let part = if offset >= whole.length() {
      Bytes::new(0)
    } else {
      Bytes::makei(whole.length() - offset, fn(i) { whole[offset + i] })
    }
    done(Ok(({ "type": "", "total": Json::number(whole.length().to_double()) }, part)))
  }
  // a film or the song: the player waits on the network
  true
}

///|
/// The made-up drive's film of a player's mode (player-video, -audio, -ended, -failed, -opening): its folder made up, the film and
/// where its player stands (None: still opening); None for another mode.
pub fn play_fixture(mode : String) -> (DriveAt, @kit.MediaStatus?)? {
  let (file, pin) : (String, @kit.MediaStatus?) = match mode {
    "player-video" =>
      (
        "第02集.mp4",
        Some({
          state: 1,
          duration: 1404000.0,
          position: 312000.0,
          buffered: 420000.0,
          playing: false,
          buffering: false,
          ended: false,
          width: 1280.0,
          height: 720.0,
        }),
      )
    "player-audio" =>
      (
        "片尾曲.m4a",
        Some({
          state: 1,
          duration: 214000.0,
          position: 63000.0,
          buffered: 214000.0,
          playing: false,
          buffering: false,
          ended: false,
          width: 0.0,
          height: 0.0,
        }),
      )
    "player-ended" =>
      (
        "第01集.mp4",
        Some({
          state: 1,
          duration: 1396000.0,
          position: 1396000.0,
          buffered: 1396000.0,
          playing: false,
          buffering: false,
          ended: true,
          width: 1280.0,
          height: 720.0,
        }),
      )
    // (one that could not play on, its card over where it stopped)
    "player-failed" =>
      (
        "第10集.mp4",
        Some({
          state: -1,
          duration: 1404000.0,
          position: 73000.0,
          buffered: 73000.0,
          playing: false,
          buffering: false,
          ended: false,
          width: 1280.0,
          height: 720.0,
        }),
      )
    "player-opening" => ("第10集.mp4", None)
    _ => return None
  }
  fix_folders[fix_docs + "\n" + fix_films] = fix_film_entries()
  let docs : DriveAt = { station: "ws1/st1", root: Some(fix_docs), path: "" }
  Some(({ ..docs, path: fix_films + "/" + file }, pin))
}
