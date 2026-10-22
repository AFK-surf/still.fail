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
/// A drive's files being fetched to keep or hand to another app: how far each has come (0–100), by dv_fetch_key
/// (DriveScreen.kt DriveFetches).
let dv_fetches : Map[String, Int] = Map([])

///|
fn dv_fetch_key(station : String, root : String, path : String) -> String {
  station + "\n" + root + "\n" + path
}

///|
/// A `drive.read`'s part kept on the device and answered from there when it is kept (the core's drive-kept.ts, as
/// DriveCache.kt keeps a drive's files on the phone): `keep` a file read whole or from its start (`file`) or a video's
/// or song's ranges as played (`played`), the file as its folder lists it (`mtime`, `size`: changed since, read anew).
fn drive_keep(p : Map[String, Json], keep : String, mtime : Double, size : Double) -> Unit {
  p["keep"] = Json::string(keep)
  p["mtime"] = Json::number(mtime)
  p["size"] = Json::number(size)
}

///|
/// A keep the host has not answered yet, and its file's name.
priv struct Keeping {
  keep : @ui.Keep
  name : String
}

///|
let keepings : Array[Keeping] = []

///|
/// Each frame (app.mbt): the keeps the host has answered, said in a toast.
fn keeps_frame(c : @ui.Ctx) -> Unit {
  // (what the host says of its keeps, the same in each build of the frame; each said once, then let go)
  if keepings.is_empty() {
    return
  }
  let left = []
  for k in keepings {
    match k.keep.kept() {
      Keeping => left.push(k)
      KeptAt(at) => {
        @hostapi.log("kept \{k.name}: \{at}")
        k.keep.end()
        say(c, tr("android-chat.file.saved"))
      }
      // the person called the panel or the sheet off: nothing to say
      CalledOff => k.keep.end()
      Failed => {
        @hostapi.log("keep \{k.name}: failed")
        k.keep.end()
        say(c, tr("android-chat.file.saveFailed"))
      }
    }
  }
  keepings.clear()
  keepings.push_iter(left.iter())
}

///|
/// Bytes all here (a chat's file the preview has read) kept: said once the host has answered; 下载失败 at once where
/// the host keeps nothing.
fn keep_bytes(c : @ui.Ctx, name : String, mime : String, bytes : Bytes) -> Unit {
  // (asked of the host once the frame's builds are over: its callers' bytes, given once)
  c.tell("keep/" + name, fn() {
    match @ui.keep(name, mime, bytes) {
      Some(k) => keepings.push({ keep: k, name })
      None => say(c, tr("android-chat.file.saveFailed"))
    }
  })
}

///|
/// A drive's file read a part at a time (`drive.read`, drive_part each), each handed to `part` as it comes (false: no
/// more wanted), its row's progress kept in dv_fetches meanwhile; `done` with None once it is all read (or `part`
/// refused one), else the core's error. `row`: the row that shows how far, when not the file's own (a folder zipped).
/// `listed`: the file as its folder lists it (its mtime, its size), what is read kept in the core as that (drive_keep).
fn drive_fetch(
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
/// A drive's file downloaded to the device (DriveScreen.kt saveToDownloads): fetched into a keep, then kept. `listed`:
/// the file as its folder lists it (its mtime, its size), what is read kept in the core as that (drive_keep).
fn download_drive_file(
  c : @ui.Ctx,
  src : Source,
  station : String,
  root : String,
  path : String,
  name : String,
  mime : String,
  row? : String,
  listed? : (Double, Double)?,
) -> Unit {
  match @ui.keep_begin(name, mime) {
    None => say(c, tr("android-chat.file.saveFailed"))
    Some(k) =>
      drive_fetch(src, station, root, path, row?=row, listed?, fn(b) { k.append(b) }, fn(err) {
        match err {
          None => {
            k.finish()
            keepings.push({ keep: k, name })
          }
          Some(e) => {
            k.end()
            app.toast = fill("android-misc.drive.fetchFailed", [("name", name), ("error", dv_error(e))])
            app.toast_n += 1
          }
        }
      })
  }
}

///|
/// Several files downloaded, each at once and each said (DriveScreen.kt: a saveToDownloads each).
fn download_drive_files(
  c : @ui.Ctx,
  src : Source,
  station : String,
  root : String,
  dir : String,
  files : Array[DvEntry],
) -> Unit {
  for e in files {
    download_drive_file(c, src, station, root, dv_join(dir, e.name), e.name, e.mime, listed=Some((e.mtime, e.size)))
  }
}

///|
/// A folder zipped on the station and downloaded (DriveScreen.kt saveZip): `drive.zip` says where the zip is (a root
/// of its own, its path, name and size), then it is fetched as any file is. The folder's row shows it under way
/// meanwhile (0% while the station zips it, then how far the zip has come; the Android app shows nothing there).
fn download_drive_zip(c : @ui.Ctx, src : Source, station : String, root : String, path : String) -> Unit {
  let p : Map[String, Json] = {
    "station": Json::string(station),
    "root": Json::string(root),
    "path": Json::string(path),
  }
  // the folder's row shows it under way while the station zips it
  let key = dv_fetch_key(station, root, path)
  dv_fetches[key] = 0
  (src.call)("drive.zip", Json::object(p), fn(r) {
    dv_fetches.remove(key)
    match r {
      Ok(z) => {
        let zv = Some(z)
        // how far it comes shown on the folder's row (the zip is no row of the drive's)
        download_drive_file(c, src, station, text(zv, "root"), text(zv, "path"), text(zv, "name"), "application/zip", row=key)
      }
      Err(e) => {
        app.toast = fill("android-misc.drive.fetchFailed", [("name", dv_name(path)), ("error", dv_error(e))])
        app.toast_n += 1
      }
    }
  })
}


///|
/// The corner of a chip whose ground fills from the left (how far a download or a use has come): its fill a plain
/// rectangle the chip's clip cuts along its corners (FillChip's drawRect in its clip), its end square where it stops.
let fill_chip_radius : Double = 6.0

///|
/// How far a file of the drive has come while it is fetched (Parts.kt DownloadChip, FillChip's `progress`): the
/// allowance's rounded box, its ground filled in the accent from the left as it comes (moving smoothly to each new
/// share over 500 ms), n% on it.
fn download_chip(c : @ui.Ctx, key : String, percent : Int) -> Unit {
  let t = @sf.theme()
  let p = if percent < 0 {
    0
  } else if percent > 100 {
    100
  } else {
    percent
  }
  // (at its first share at once, as animateFloatAsState starts)
  let drawn = @motion.animate(c, "fetch/" + key, p.to_double(), spec=@motion.tween(500.0))
  c.box(h=Px(20.0), radius=fill_chip_radius, bg=t.p.chip, clip=true, justify=JCenter, fn() {
    if drawn > 0.0 {
      c.layer(fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(drawn), h=Fill(1.0), bg=@sf.alpha(t.p.accent, 0.2), fn() {  }) |> ignore
          if drawn < 100.0 {
            c.box(w=Fill(100.0 - drawn), h=Fill(1.0), fn() {  }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
    c.box(dir=Row, padx=8.0, align=ACenter, fn() {
      c.text("\{p}%", size=11.0, weight=600, color=t.p.text, wrap=false, line=13.0) |> ignore
    })
    |> ignore
  })
  |> ignore
}
