// Films and series over the core's media module (ember docs/media-service.md,
// the third part): `media.videos` for the library, `media.video` for one's
// page, `media.video.poster` for the posters. Playing (`media.video.play`)
// waits for the player (the host's).

///|
let posters_asked : Map[String, Bool] = {}

///|
fn place_of(v : Json?) -> @videos.Place? {
  match v {
    Some(Object(m)) =>
      Some({
        position: num(Some(Json::object(m)), "position").unwrap_or(0.0),
        done: match m.get("done") {
          Some(True) => true
          _ => false
        },
      })
    _ => None
  }
}

///|
fn title_of(v : Json, kind : @videos.Kind) -> @videos.Title {
  let m = match v {
    Object(m) => m
    _ => {}
  }
  let year = num(Some(v), "year").map(fn(y) { y.to_int() })
  {
    id: str(Some(v), "id"),
    kind,
    title: str(Some(v), "title"),
    year,
    thumbhash: str(Some(v), "thumbhash"),
    place: place_of(m.get("progress")),
    seasons: num(Some(v), "seasons").unwrap_or(0.0).to_int(),
    episodes: num(Some(v), "episodes").unwrap_or(0.0).to_int(),
    unwatched: num(Some(v), "unwatched").unwrap_or(0.0).to_int(),
  }
}

///|
fn titles(m : Map[String, Json], key : String, kind : @videos.Kind) -> Array[@videos.Title] {
  match m.get(key) {
    Some(Array(list)) =>
      list.map(fn(v) {
        // what is being watched may be either: its own kind if it says
        let k = match str(Some(v), "kind") {
          "show" => @videos.Kind::Show
          "movie" => @videos.Kind::Movie
          _ => kind
        }
        title_of(v, k)
      })
    _ => []
  }
}

///|
fn error_text(e : Json, what : String) -> String {
  let status = num(Some(e), "status").unwrap_or(0.0)
  if str(Some(e), "code") == "forbidden" || status == 403.0 {
    "只读成员看不到" + what
  } else {
    what + "读不到：" + str(Some(e), "message")
  }
}

///|
fn video_library() -> Result[@videos.Library, String]? {
  guard media_station() is Some(station) else { return None }
  let s = @core.subscribe("media.videos", params={ "station": Json::string(station) })
  match (s.value, s.error) {
    (Some(Object(m)), _) =>
      Some(
        Ok({
          recent: titles(m, "recent", Movie),
          movies: titles(m, "movies", Movie),
          shows: titles(m, "shows", Show),
        }),
      )
    (_, Some(e)) if str(Some(e), "code") == "module_starting" => None
    (_, Some(e)) => Some(Err(error_text(e, "影视")))
    _ => None
  }
}

///|
fn video_detail(id : String) -> Result[@videos.Detail, String]? {
  guard media_station() is Some(station) else { return None }
  let s = @core.subscribe("media.video", params={
    "station": Json::string(station),
    "id": Json::string(id),
  })
  match (s.value, s.error) {
    (Some(Object(m) as v), _) => {
      let strings = fn(key : String) -> Array[String] {
        match m.get(key) {
          Some(Array(list)) => list.map(fn(x) {
            match x {
              String(s) => s
              _ => ""
            }
          })
          _ => []
        }
      }
      let seasons = match m.get("seasons") {
        Some(Array(list)) =>
          list.map(fn(sv) {
            let eps = match sv {
              Object(sm) =>
                match sm.get("episodes") {
                  Some(Array(es)) =>
                    es.map(fn(e) {
                      let em = match e {
                        Object(x) => x
                        _ => {}
                      }
                      let ep : @videos.Episode = {
                        id: str(Some(e), "id"),
                        episode: num(Some(e), "episode").unwrap_or(0.0).to_int(),
                        title: str(Some(e), "title"),
                        duration: num(Some(e), "duration").unwrap_or(0.0),
                        place: place_of(em.get("progress")),
                      }
                      ep
                    })
                  _ => []
                }
              _ => []
            }
            let season : @videos.Season = {
              season: num(Some(sv), "season").unwrap_or(1.0).to_int(),
              episodes: eps,
            }
            season
          })
        _ => []
      }
      Some(
        Ok({
          kind: if str(Some(v), "kind") == "show" { Show } else { Movie },
          title: str(Some(v), "title"),
          original: str(Some(v), "originalTitle"),
          year: num(Some(v), "year").map(fn(y) { y.to_int() }),
          plot: str(Some(v), "plot"),
          genres: strings("genres"),
          duration: num(Some(v), "duration").unwrap_or(0.0),
          place: place_of(m.get("progress")),
          seasons,
        }),
      )
    }
    (_, Some(e)) if str(Some(e), "code") == "module_starting" => None
    (_, Some(e)) => Some(Err(error_text(e, "影视")))
    _ => None
  }
}

///|
fn video_poster(t : @videos.Title) -> String {
  let key = "mem:poster/\{t.id}"
  if !posters_asked.contains(key) {
    posters_asked[key] = true
    match media_station() {
      Some(station) => {
        let params : Map[String, Json] = {
          "station": Json::string(station),
          "id": Json::string(t.id),
        }
        @core.call_bytes("media.video.poster", params=Json::object(params), on_done=fn(r) {
          match r {
            Ok((_, Some(bytes))) => {
              @ui.add_image(key, bytes)
            }
            _ => ()
          }
        })
      }
      None => posters_asked.remove(key)
    }
  }
  key
}

///|
fn video_play(id : String, at : Double) -> Unit {
  @hostapi.log("VIDEO play \{id} at \{at} (the player is not in yet)")
}

///|
let video_source : @videos.Source = {
  library: video_library,
  detail: video_detail,
  poster: video_poster,
  play: video_play,
}
