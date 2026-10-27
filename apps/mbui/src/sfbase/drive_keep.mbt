// Files kept on the device (still.fail's Android app: FileKinds.kt download, DriveScreen.kt saveToDownloads,
// saveZip, DriveFetches, Parts.kt DownloadChip): a drive's file fetched a part at a time through the core
// (`drive.read`), each part handed to the host as it comes (@ui.keep_begin: a file of its temporary directory, never
// whole in memory), how far it has come on its row (n% in the accent's filling box), then kept where the system keeps
// downloads (MediaStore's Downloads on Android, ~/Downloads on macOS, the Files sheet on iOS, Downloads on Windows):
// 正在下载「名字」 as it starts, 已保存到「下载」 or 下载失败 once the host has answered, 无法获取「名字」：… when the
// station could not give it. A folder is zipped on the station first (`drive.zip`: where the zip is, read as any file
// of the drive). Several chosen are fetched side by side, each said. The chat's preview keeps its file the same
// way (preview.mbt).

///|
/// The part of a file read at most (Calls.kt DRIVE_PART).
pub let drive_part : Int = 4 * 1024 * 1024

///|
/// A drive's files being fetched to keep or hand to another app: how far each has come (0–100), by dv_fetch_key
/// (DriveScreen.kt DriveFetches).
pub let dv_fetches : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
pub fn dv_fetch_key(station : String, root : String, path : String) -> String {
  station + "\n" + root + "\n" + path
}

///|
/// A `drive.read`'s part kept on the device and answered from there when it is kept (the core's drive-kept.ts, as
/// DriveCache.kt keeps a drive's files on the phone): `keep` a file read whole or from its start (`file`) or a video's
/// or song's ranges as played (`played`), the file as its folder lists it (`mtime`, `size`: changed since, read anew).
pub fn drive_keep(p : Map[String, Json], keep : String, mtime : Double, size : Double) -> Unit {
  p["keep"] = Json::string(keep)
  p["mtime"] = Json::number(mtime)
  p["size"] = Json::number(size)
}

///|
/// A keep the host has not answered yet, its file's name, what is said once it is kept and once it failed, and what is
/// done once the host has answered (a chat's download said done to the core, downloads.mbt).
priv struct Keeping {
  keep : @ui.Keep
  name : String
  saved : String
  failed : String
  then : (@hostapi.Kept) -> Unit
}

///|
let keepings : @sf.LiveArray[Keeping] = @sf.LiveArray::new()

///|
/// Each frame (app.mbt): the keeps the host has answered, said in a toast.
pub fn keeps_frame(c : @ui.Ctx) -> Unit {
  // (what the host says of its keeps, the same in each build of the frame; each said once, then let go)
  if keepings.is_empty() {
    return
  }
  let left = []
  for i, k in keepings {
    let kept = k.keep.kept()
    match kept {
      Keeping => left.push(k)
      KeptAt(at) => {
        @hostapi.log("kept \{k.name}: \{at}")
        k.keep.end()
        say(c, k.saved)
      }
      // the person called the panel or the sheet off: nothing to say
      CalledOff => k.keep.end()
      Failed => {
        @hostapi.log("keep \{k.name}: failed")
        k.keep.end()
        say(c, k.failed)
      }
    }
    if !(kept is Keeping) {
      // (told once the frame's builds are over, as the answer is the build's that took it)
      c.tell("keep-then/\{i}/\{k.name}", fn() { (k.then)(kept) })
    }
  }
  keepings.clear()
  keepings.push_iter(left.iter())
}

///|
/// Bytes all here (a chat's file the preview has read, a picture made to share) kept `way` (where the system keeps
/// downloads, or a picture into the photo album): `saved` or `failed` said once the host has answered (已保存到「下载」,
/// 下载失败), `failed` at once where the host keeps nothing.
pub fn keep_bytes(
  c : @ui.Ctx,
  name : String,
  mime : String,
  bytes : Bytes,
  way? : @hostapi.KeepWay = Downloads,
  saved? : String = @sf.t("android-chat.file.saved"),
  failed? : String = @sf.t("android-chat.file.saveFailed"),
) -> Unit {
  // (asked of the host once the frame's builds are over: its callers' bytes, given once)
  c.tell("keep/" + name, fn() {
    match @ui.keep(name, mime, bytes, way~) {
      Some(k) => keepings.push({ keep: k, name, saved, failed, then: fn(_) {  } })
      None => say(c, failed)
    }
  })
}

///|
/// A drive's file read a part at a time (`drive.read`, drive_part each), each handed to `part` as it comes (false: no
/// more wanted), its row's progress kept in dv_fetches meanwhile; `done` with None once it is all read (or `part`
/// refused one), else the core's error. `row`: the row that shows how far, when not the file's own (a folder zipped).
/// `listed`: the file as its folder lists it (its mtime, its size), what is read kept in the core as that (drive_keep).
pub fn drive_fetch(
  src : Source,
  station : String,
  root : String,
  path : String,
  part : (Bytes) -> Bool,
  done : (Json?) -> Unit,
  row? : String,
  listed? : (Double, Double)?,
) -> Unit {
  let key = row.unwrap_or(dv_fetch_key(station, root, path))
  dv_fetches[key] = 0
  let got : Ref[Int] = { val: 0 }
  fn next() {
    let p : Map[String, Json] = {
      "station": Json::string(station),
      "root": Json::string(root),
      "path": Json::string(path),
      "offset": Json::number(got.val.to_double()),
      "length": Json::number(drive_part.to_double()),
    }
    match listed {
      Some(Some((mtime, size))) => drive_keep(p, "file", mtime, size)
      _ => ()
    }
    (src.read_bytes)("drive.read", Json::object(p), fn(r) {
      match r {
        Ok((answer, bytes)) => {
          let total = match field(Some(answer), "total") {
            Some(Number(n, ..)) => n.to_int()
            _ => got.val + bytes.length()
          }
          got.val += bytes.length()
          dv_fetches[key] = if total > 0 {
            (got.val.to_double() * 100.0 / total.to_double()).to_int()
          } else {
            0
          }
          let wanted = bytes.length() == 0 || part(bytes)
          if !wanted || bytes.length() == 0 || got.val >= total {
            dv_fetches.remove(key)
            done(None)
          } else {
            next()
          }
        }
        Err(e) => {
          dv_fetches.remove(key)
          done(Some(e))
        }
      }
    })
  }
  next()
}

///|
/// A drive's file downloaded to the device (DriveScreen.kt saveToDownloads): asked of the core (downloads.mbt), which
/// fetches it whatever becomes of the page, how far on its row, kept once all of it is here. `listed`: the file as
/// its folder lists it (its mtime, its size), what is fetched kept in the core as that.
pub fn download_drive_file(
  c : @ui.Ctx,
  src : Source,
  station : String,
  root : String,
  path : String,
  name : String,
  listed? : (Double, Double)?,
) -> Unit {
  let (mtime, size) = match listed {
    Some(Some(l)) => l
    _ => (0.0, 0.0)
  }
  // (told once the frame's builds are over: its pages call it under the press that asks for it)
  c.tell("download/" + station + "/" + root + "/" + path, fn() {
    download_start_drive(src, station, root, path, name, size, mtime)
  })
}

///|
/// Several files downloaded, each at once and each said (DriveScreen.kt: a saveToDownloads each).
pub fn download_drive_files(
  c : @ui.Ctx,
  src : Source,
  station : String,
  root : String,
  dir : String,
  files : Array[DvEntry],
) -> Unit {
  for e in files {
    download_drive_file(c, src, station, root, dv_join(dir, e.name), e.name, listed=Some((e.mtime, e.size)))
  }
}

///|
/// A folder zipped on the station and downloaded (DriveScreen.kt saveZip): asked of the core, which has the station zip
/// it (`drive.zip`) and fetches the zip as any file; the folder's row shows how far meanwhile (正在打包 while the
/// station zips it).
pub fn download_drive_zip(c : @ui.Ctx, src : Source, station : String, root : String, path : String) -> Unit {
  c.tell("download-zip/" + station + "/" + root + "/" + path, fn() {
    download_start_zip(src, station, root, path, dv_name(path) + ".zip")
  })
}


