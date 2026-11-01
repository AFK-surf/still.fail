// A file of a station's drive as a viewer opens it (@sf.ViewerFile; the web's web/src/drive/viewerFile.ts): read
// through the core a part at a time (`drive.read`, 4 MB a part, bytes beside the answer), kept on the device as its
// folder lists it (drive_keep: read whole as `file`, played as `played`); where it was left on this device the core's
// (the drivePlace topic, `drive.place`); saved as the drive's 下载 saves it. A text of it read in the library's reader,
// a video or a song played in its player, for a page of either frame (the phone's DriveRead and DrivePlay, the
// desktop's over the whole window).

///|
/// The file `at.path` of `at.root` on `at.station`, as its folder (the `drive` topic, as last read) lists it.
pub fn drive_viewer_file(c : @ui.Ctx, src : Source, at : DriveAt) -> @sf.ViewerFile {
  let root = at.root.unwrap_or("")
  let dir = dv_parent(at.path)
  let name = dv_name(at.path)
  let entry = dv_entries(src, at.station, root, dir).unwrap_or([]).iter().find_first(fn(e) { e.name == name && !e.dir })
  let (by_kind, by_name, _) = preview_kind(name)
  let listed = entry.map(fn(e) { (e.mtime, e.size) })
  // what it is played by: kept as played, as the folder lists it (Player.kt: DriveCache.played by its mtime and
  // size; one not in it played without being kept), its parts' offset and length each read's own
  let played = fn() {
    let p = drive_params(at.station, root, at.path)
    match listed {
      Some((mtime, size)) => {
        drive_keep(p, "played", mtime, size)
        // (opened here, where it is: brought after everything else once let go)
        p["from"] = { "root": Json::string(root), "path": Json::string(at.path) }
      }
      None => ()
    }
    p
  }
  let size = listed.map(fn(l) { l.1 }).unwrap_or(0.0)
  {
    name,
    size: match entry {
      Some(e) => e.size
      None => 0.0
    },
    mtime: match entry {
      Some(e) => e.mtime
      None => 0.0
    },
    mime: match entry {
      Some(e) if e.mime != "" => e.mime
      _ => by_name
    },
    kind: match entry {
      Some(e) => e.kind
      None =>
        match by_kind {
          Some(KAudio) => "audio"
          Some(KVideo) => "video"
          Some(KMarkdown) => "markdown"
          Some(KText) => "text"
          _ => ""
        }
    },
    title: at.path,
    key: reader_key(at),
    bytes: None,
    read: fn(max, progress, done) {
      drive_read_all(src, at.station, root, at.path, max, "file", listed~, progress~, fn(r) {
        done(
          match r {
            Ok(b) => Ok(b)
            Err(e) => Err(dv_error(e))
          },
        )
      })
    },
    stream: Some(fn(offset, length, answer) {
      let p = played()
      p["offset"] = Json::number(offset)
      p["length"] = Json::number(length.to_double())
      stream_part(src, "drive.read", p, size, answer, ended=fn(r) {
        match r {
          Ok(_) => ()
          Err(e) => @ui.log("player: \{name} @\{offset.to_int()} failed: \{e.stringify()}")
        }
      })
    }),
    direct: direct_part("drive.read", played(), size),
    beside: Some(fn(e, done) {
      drive_read_all(src, at.station, root, dv_join(dir, e.name), subtitle_limit, "played", listed=Some((e.mtime, e.size)), fn(r) {
        done(
          match r {
            Ok(b) => Ok(b)
            Err(e) => Err(dv_error(e))
          },
        )
      })
    }),
    place: fn() {
      // where it was left, held on this device (the core's: no wait for a station)
      let place = (src.topic)("drivePlace", drive_params(at.station, root, at.path))
      match place.value {
        Some(v) => {
          let left = number(Some(v), "at")
          if left > 0.0 {
            LeftAt(left, number(Some(v), "of"))
          } else {
            NeverLeft
          }
        }
        None => if place.error is Some(_) { NeverLeft } else { NotKnown }
      }
    },
    keep_place: fn(left, of) {
      let p = drive_params(at.station, root, at.path)
      p["at"] = Json::number(left)
      p["of"] = Json::number(of)
      (src.call)("drive.place", Json::object(p), fn(r) {
        match r {
          Ok(_) => ()
          Err(e) => @ui.log("drive: \{name}: where it was left not kept: \{e.stringify()}")
        }
      })
    },
    save: fn() {
      say(c, @sf.t("android-misc.drive.downloading", args=[("name", name)]))
      download_drive_file(c, src, at.station, root, at.path, name, listed=listed)
    },
    facts: @sf.no_facts,
  }
}

///|
/// A drive's place as the core's calls and topics name it.
pub fn drive_params(station : String, root : String, path : String) -> Map[String, Json] {
  { "station": Json::string(station), "root": Json::string(root), "path": Json::string(path) }
}

///|
/// The longest subtitle read (a SubRip of a long film is a few hundred KB).
pub let subtitle_limit : Int = 4 * 1024 * 1024

///|
/// A file of a drive read whole (`drive.read`, drive_part a part), `limit` bytes at most (below 0: all of it), how much
/// has come told as it comes (from the size its folder lists, before the first part); kept as `keep` (drive_keep) as
/// its folder lists it (`listed`: its mtime, its size).
pub fn drive_read_all(
  src : Source,
  station : String,
  root : String,
  path : String,
  limit : Int,
  keep : String,
  listed~ : (Double, Double)?,
  progress? : (@sf.Got) -> Unit = fn(_) {  },
  done : (Result[Bytes, Json]) -> Unit,
) -> Unit {
  let parts : Array[Bytes] = []
  let got : Ref[Int] = { val: 0 }
  match listed {
    Some((_, size)) if size > 0.0 => progress({ loaded: 0.0, total: size })
    _ => ()
  }
  fn next() {
    let left = if limit < 0 { drive_part } else { limit - got.val }
    let want = if left < drive_part { left } else { drive_part }
    let p = drive_params(station, root, path)
    p["offset"] = Json::number(got.val.to_double())
    p["length"] = Json::number(want.to_double())
    match listed {
      Some((mtime, size)) => drive_keep(p, keep, mtime, size)
      None => ()
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
          progress({ loaded: got.val.to_double(), total: total.to_double() })
          if bytes.length() == 0 || got.val >= total || (limit >= 0 && got.val >= limit) {
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

///|
/// Where a drive's file read or played is kept as it is left (the library's reader's and player's key).
pub fn reader_key(at : DriveAt) -> String {
  at.station + "\n" + at.root.unwrap_or("") + "\n" + at.path
}

///|
/// The text `at.path` of `at.root` on `at.station`, read (the web's Reader): back to its folder by name (`back`).
pub fn drive_reader(c : @ui.Ctx, src : Source, at : DriveAt, back : () -> Unit) -> Unit {
  let file = drive_viewer_file(c, src, at)
  @sf.reader(
    c,
    reader_key(at),
    file,
    markdown=@sf.reads_as_markdown(file.name),
    back_label=viewer_folder_label(src, at.station, at.root.unwrap_or(""), dv_parent(at.path)),
    on_back=back,
  )
}

///|
/// The file `at.path` of `at.root` on `at.station`, played (the web's Player: opened where it was left on this device,
/// the subtitle beside it), its folder's others to go to (`go`: by name), back to its folder by name (`back`).
pub fn drive_player(c : @ui.Ctx, src : Source, at : DriveAt, back : () -> Unit, go : (DriveAt) -> Unit) -> Unit {
  let root = at.root.unwrap_or("")
  let dir = dv_parent(at.path)
  let file = drive_viewer_file(c, src, at)
  let entries = dv_entries(src, at.station, root, dir).unwrap_or([])
  let siblings : Array[@sf.ViewerEntry] = entries.map(fn(e) {
    { name: e.name, size: e.size, mtime: e.mtime, mime: e.mime, kind: e.kind, dir: e.dir }
  })
  @sf.player(
    c,
    reader_key(at),
    file,
    siblings,
    back_label=viewer_folder_label(src, at.station, root, dir),
    on_back=back,
    on_go=fn(other) { go({ station: at.station, root: at.root, path: dv_join(dir, other) }) },
  )
}

///|
/// A drive's text read, left: where it was, kept.
pub fn reader_left(at : DriveAt) -> Unit {
  @sf.reader_let_go(reader_key(at))
}

///|
/// A drive's file played, left: where it was kept, the player stopped.
pub fn play_left(at : DriveAt) -> Unit {
  @sf.player_let_go(reader_key(at))
}
