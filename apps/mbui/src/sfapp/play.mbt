// A video or a song of a station's drive, played (ember apps/android drive/Player.kt PlayerScreen, Screen.DrivePlay;
// pushed from a folder's row: DriveScreen.kt open): src/player's player over the page, its bytes read through the core a
// part at a time (`drive.read`, bytes beside the answer: never the whole file first, a seek far ahead one more ranged
// read), the folder (the `drive` topic, as last read) giving what plays before and after it and the subtitle beside it
// (E01.srt for E01.mp4, read whole and shown by the player). Where it was left is kept on this device (`drive.place`
// with its time and length in ms, every 5 s while it plays and as the page goes; the drivePlace topic) and played on
// from next time, unless it was left within 5 s of its end. The next or the one before replace this page in place.

///|
/// A file played, kept while its page is in the stack.
priv struct Playing {
  player : @player.Player
  mut opened : Bool
  mut subtitle_asked : Bool
  mut kept_at : Double
  /// a read logged, the first times
  mut reads : Int
}

///|
let playing : Map[String, Playing] = Map([])

///|
let play_srcs : Map[String, Source] = Map([])

///|
/// The longest subtitle read (a SubRip of a long film is a few hundred KB).
let subtitle_limit : Int = 4 * 1024 * 1024

///|
fn playing_for(key : String) -> Playing {
  match playing.get(key) {
    Some(p) => p
    None => {
      let p : Playing = {
        player: @player.Player::new(key="drive-play"),
        opened: false,
        subtitle_asked: false,
        kept_at: 0.0,
        reads: 0,
      }
      playing[key] = p
      p
    }
  }
}

///|
fn play_params(at : DriveAt, path : String) -> Map[String, Json] {
  {
    "station": Json::string(at.station),
    "root": Json::string(at.root.unwrap_or("")),
    "path": Json::string(path),
  }
}

///|
/// How long where a file was left is waited on before it plays from the start.
let play_place_ms : Double = 1000.0

///|
/// How often where it is is kept while it plays.
let play_keep_ms : Double = 5000.0

///|
/// The file `at.path` of `at.root` on `at.station`, played (Player.kt PlayerScreen).

pub fn play_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let key = reader_key(at)
  play_srcs[key] = src
  let pl = playing_for(key)
  let now = c.now()
  let dir = dv_parent(at.path)
  let name = dv_name(at.path)
  let folder = (src.topic)("drive", play_params(at, dir)).value
  let entries = items(folder, "entries").map(dv_entry)
  let place = (src.topic)("drivePlace", play_params(at, at.path))
  // where it was left, held on this device: waited on a moment at most from when it is first drawn (`after` asks for
  // the frame it is up on)
  let waited = @kit.after(c, "play-place", !pl.opened, play_place_ms)
  if !pl.opened {
    if place.value is Some(_) || place.error is Some(_) || waited {
      pl.opened = true
      let left = number(place.value, "at")
      let of = number(place.value, "of")
      // left near its end: from the start again
      let start = if left > 0.0 && (of <= 0.0 || left < of - 5000.0) { left } else { 0.0 }
      let entry = entries.iter().find_first(fn(e) { e.name == name && !e.dir })
      let (kind, by_name, _) = preview_kind(name)
      let audio = match entry {
        Some(e) => e.kind == "audio"
        None => kind == Some(KAudio)
      }
      let mime = match entry {
        Some(e) if e.mime != "" => e.mime
        _ => by_name
      }
      pl.player.open(
        {
          name,
          mime,
          audio,
          read: fn(offset, length, answer) {
            let p = play_params(at, at.path)
            p["offset"] = Json::number(offset)
            p["length"] = Json::number(length.to_double())
            (src.read_bytes)("drive.read", Json::object(p), fn(r) {
              match r {
                Ok((answer_json, bytes)) => {
                  let total = match field(Some(answer_json), "total") {
                    Some(Number(t, ..)) => t
                    _ => -1.0
                  }
                  if pl.reads < 3 {
                    @ui.log(
                      "player: \{name} @\{offset.to_int()} \{bytes.length()} bytes through the core (drive.read, total \{total.to_int()})",
                    )
                  }
                  pl.reads += 1
                  answer(bytes, total)
                }
                Err(e) => {
                  @ui.log("player: \{name} @\{offset.to_int()} failed: \{e.stringify()}")
                  answer(b"", -2.0)
                }
              }
            })
          },
        },
        start~,
      )
    }
  }
  // the subtitle beside it, once the folder is known
  if !pl.subtitle_asked && folder is Some(_) {
    pl.subtitle_asked = true
    let names = entries.filter(fn(e) { !e.dir }).map(fn(e) { e.name })
    match @player.pick_subtitle(name, names) {
      Some(sub) => {
        pl.player.set_subtitle(true, [])
        drive_read_all(src, at.station, at.root.unwrap_or(""), dv_join(dir, sub), subtitle_limit, fn(r) {
          match r {
            Ok(bytes) => {
              let cues = @player.parse_subtitles(sub, bytes)
              @ui.log("player: subtitle \{sub}: \{cues.length()} lines")
              pl.player.set_subtitle(true, cues)
            }
            Err(e) => @ui.log("player: subtitle \{sub} not read: \{e.stringify()}")
          }
        })
      }
      None => ()
    }
  }
  // where it is, kept every 5 s while it is open
  if pl.player.started() && pl.player.duration() > 0.0 {
    // every 5 s from when it started (Player.kt: every 20 ticks of 250 ms)
    if pl.kept_at <= 0.0 {
      pl.kept_at = now
    }
    if now - pl.kept_at >= play_keep_ms {
      play_keep(src, at, pl)
      pl.kept_at = now
    }
    // (the place kept now and then: nothing shown waits for it)
    c.wake_in(play_keep_ms - (now - pl.kept_at), later=true)

  }
  let list = @player.playlist_of(
    entries
    .filter(fn(e) { !e.dir && (e.kind == "video" || e.kind == "audio") })
    .map(fn(e) { e.name }),
    fn(_) { true },
  )
  pl.player.view(c, list~, fn() { app.nav.pop() |> ignore }, fn(other) {
    app.nav.replace(DrivePlay({ station: at.station, root: at.root, path: dv_join(dir, other) }))
  })
}

///|
/// Where it is, told to the core (`drive.place`: its time and its length, in ms).
fn play_keep(src : Source, at : DriveAt, pl : Playing) -> Unit {
  let pos = pl.player.position()
  let dur = pl.player.duration()
  if dur <= 0.0 {
    return
  }
  let p = play_params(at, at.path)
  p["at"] = Json::number(pos.round())
  p["of"] = Json::number(dur.round())
  (src.call)("drive.place", Json::object(p), fn(r) {
    match r {
      Ok(_) => @ui.log("player: place kept, \{pos.to_int()} of \{dur.to_int()} ms")
      Err(e) => @ui.log("player: place not kept: \{e.stringify()}")
    }
  })
}

///|
/// Its page gone: where it was kept, the player stopped.
fn play_left(at : DriveAt) -> Unit {
  let key = reader_key(at)
  match (playing.get(key), play_srcs.get(key)) {
    (Some(pl), Some(src)) => {
      if pl.player.started() {
        play_keep(src, at, pl)
      }
      pl.player.close()
    }
    (Some(pl), None) => pl.player.close()
    _ => ()
  }
  playing.remove(key)
  play_srcs.remove(key)
}

///|
/// Back while the player on top is sideways turns it upright first (Player.kt BackHandler).
fn play_back(c : @ui.Ctx) -> Unit {
  match app.nav.top() {
    DrivePlay(at) =>
      match playing.get(reader_key(at)) {
        Some(pl) if pl.player.is_sideways() => c.on_back(fn() { pl.player.upright() })
        _ => ()
      }
    _ => ()
  }
}

///|
/// Whether what is on top is dark or light whatever the theme (the system bars' icons follow it): the player and the
/// viewer over a picture or a video dark; a reader as its paper. None: as the theme.
fn page_dark(src : Source) -> Bool? {
  match viewer.val {
    Some(v) if v.closing < 0.0 && v.dark() => return Some(true)
    _ => ()
  }
  if app.nav.top() is DrivePlay(_) {
    return Some(true)
  }
  reader_paper_dark(src)
}

///|
/// A file of a drive read whole (`drive.read`, 4 MB a part), `limit` bytes at most.
fn drive_read_all(
  src : Source,
  station : String,
  root : String,
  path : String,
  limit : Int,
  done : (Result[Bytes, Json]) -> Unit,
) -> Unit {
  let parts : Array[Bytes] = []
  let got : Ref[Int] = { val: 0 }
  fn next() {
    let want = if limit - got.val < drive_part { limit - got.val } else { drive_part }
    let p : Map[String, Json] = {
      "station": Json::string(station),
      "root": Json::string(root),
      "path": Json::string(path),
      "offset": Json::number(got.val.to_double()),
      "length": Json::number(want.to_double()),
    }
    (src.read_bytes)("drive.read", Json::object(p), fn(r) {
      match r {
        Ok((answer, bytes)) => {
          let total = match field(Some(answer), "total") {
            Some(Number(n, ..)) => n.to_int()
            _ => got.val + bytes.length()
          }
          parts.push(bytes)
          got.val += bytes.length()
          if bytes.length() == 0 || got.val >= total || got.val >= limit {
            let all = Buffer(size_hint=got.val)
            for b in parts {
              all.write_bytes(b)
            }
            done(Ok(all.to_bytes()))
          } else {
            next()
          }
        }
        Err(e) => done(Err(e))
      }
    })
  }
  next()
}
