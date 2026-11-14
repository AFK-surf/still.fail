// The files of the share card's looks the app does not carry (web/public/share-looks/<drawing>/: a look's pictures,
// the face its words are in), each had through the core on its own (`fonts.share {file}`: kept on the device once it is
// the file the site's table says, how far each is on the `fonts` topic's `share`), so a look is drawn, and handed out,
// only once all of its are here (2026-11-03 用户：「在没有准备好资源的时候不让保存」「每张独立下载并提供进度」, of a beta
// app given the site's page for each of 千恋＊万花's files, saved without its pictures and in the carried face).

///|
/// How a file of the looks stands: on its way, here (its size), or not had (why, in the core's words).
#derive(Eq)
pub(all) enum LooksFile {
  LooksComing
  LooksHere(Int)
  LooksFailed(String)
}

///|
/// The looks' files asked for this run, by name (`<drawing>/<name>`).
let looks_files : @sf.LiveMap[String, LooksFile] = @sf.LiveMap::new()

///|
/// What is told each file's bytes once it is here, by name: asked again with it after it failed (looks_files_again).
// kept across runs: put back as a run begins (faces_reset)
let looks_files_here : Map[String, (Bytes) -> Unit] = Map([])

///|
fn looks_files_reset() -> Unit {
  looks_files.clear()
  looks_files_here.clear()
}

///|
/// File `file` of the looks: asked of the core the first time (`here` told its bytes once it is), how it stands since.
pub fn looks_file(src : Source, file : String, here : (Bytes) -> Unit) -> LooksFile {
  match looks_files.get(file) {
    Some(s) => s
    None => {
      looks_files_here[file] = here
      looks_file_ask(src, file)
      looks_files.get(file).unwrap_or(LooksComing)
    }
  }
}

///|
fn looks_file_ask(src : Source, file : String) -> Unit {
  looks_files[file] = LooksComing
  (src.read_bytes)("fonts.share", Json::object({ "file": ToJson::to_json(file) }), fn(r) {
    match r {
      Ok((_, bytes)) => {
        match looks_files_here.get(file) {
          Some(here) => here(bytes)
          None => ()
        }
        looks_files[file] = LooksHere(bytes.length())
      }
      Err(e) => looks_files[file] = LooksFailed(text(Some(e), "message"))
    }
  })
}

///|
/// Those of `files` that failed asked for again.
pub fn looks_files_again(src : Source, files : Array[String]) -> Unit {
  for file in files {
    if looks_files.get(file) is Some(LooksFailed(_)) {
      looks_file_ask(src, file)
    }
  }
}

///|
/// How `files` (asked with looks_file) stand together: all here (Ready), one failed (Failed: the first one's why), else
/// on their way, how far (the share of their bytes here: None while one's size is not known yet).
#derive(Eq)
pub(all) enum LooksStand {
  LooksReady
  LooksGoing(Double?)
  LooksNotHad(String)
}

///|
pub fn looks_stand(src : Source, files : Array[String]) -> LooksStand {
  let going = field(src.topic("fonts", Map([])).get().value, "share")
  let mut got = 0.0
  let mut whole = 0.0
  let mut known = true
  let mut coming = false
  for file in files {
    match looks_files.get(file) {
      Some(LooksFailed(why)) => return LooksNotHad(why)
      Some(LooksHere(n)) => {
        got += n.to_double()
        whole += n.to_double()
      }
      _ => {
        coming = true
        match field(going, file) {
          Some(Object(_)) as f => {
            got += number(f, "got")
            whole += number(f, "bytes")
          }
          _ => known = false
        }
      }
    }
  }
  if !coming {
    LooksReady
  } else if known && whole > 0.0 {
    LooksGoing(Some(got / whole))
  } else {
    LooksGoing(None)
  }
}
