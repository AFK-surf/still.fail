// The made-up drive of the fixture's stations (the core's shapes: Overview.drive, the `drive` topic's DriveFolder,
// `drivePlace`, `drive.read`'s parts), for the drive's screenshots (scripts/shots.sh drive) and tests: Studio lends
// 文档 and a disk that is gone, its home browsable; MBA (away) lends 照片. Its folders take what the pages do to them
// (rename, delete, a new folder, a file put up) while the app runs. Every word in it is made up.
//
// MBUI_FIXTURE: files (文件), drive (Studio's 文档), drive-sub (a folder in it), drive-upload (files going up, one whose
// name is taken, one failed), drive-download (a file and a folder being downloaded), drive-empty, reader
// (a novel read), reader-bars (with its bars), reader-contents, reader-layout, reader-md (a Markdown file read);
// chat-station-files (＋'s Station 文件 in a folder, a file ticked), chat-station-ref (a station's file in the draft),
// chat-station-file (one sent as a file, a folder as a zip going up), chat-station-sheet (its card's sheet).

///|
let fix_home : String = "/Users/lin"

///|
let fix_docs : String = "/Users/lin/文档"

///|
fn fixture_station_drive(up : Bool) -> Json {
  if up {
    {
      "viewer": { "via": "mesh", "role": "owner" },
      "drive": {
        "roots": [
          { "path": fix_docs, "name": "文档", "state": "ok" },
          { "path": "/Volumes/备份盘", "name": "备份盘", "state": "missing" },
        ],
        "anywhere": true,
        "transfers": true,
        "home": fix_home,
        "trash": true,
        "watch": true,
        "zip": true,
      },
      // its disk: 380 GB of 1 TB left
      "disk": { "freeBytes": 380000000000.0, "totalBytes": 1000000000000.0 },
    }
  } else {
    {
      "viewer": { "via": "mesh", "role": "owner" },
      "drive": { "roots": [{ "path": "/Users/lin/照片", "name": "照片", "state": "ok" }], "transfers": true },
    }
  }
}

///|
/// A made-up entry: its name, a folder or not, its size, how long ago it changed (its time in words).
fn fix_entry(name : String, dir : Bool, size : Int, time : String) -> Json {
  let kind = if dir { "folder" } else { fix_kind(name) }
  {
    "name": Json::string(name),
    "dir": Json::boolean(dir),
    "size": Json::number(size.to_double()),
    "mtime": Json::number(1792300000000.0 - size.to_double()),
    "type": "",
    "kind": Json::string(kind),
    "sizeText": Json::string(if dir { "" } else { @sf.file_size(size.to_double()) }),
    "timeText": Json::string(time),
  }
}

///|
/// A made-up file's extension, lower case (what its kind is made up from).
fn fix_ext(name : String) -> String {
  match name.rev_find(".") {
    Some(i) if i > 0 => name.view(start_offset=i + 1).to_owned().to_lower()
    _ => ""
  }
}

///|
fn fix_kind(name : String) -> String {
  match fix_ext(name) {
    "md" => "markdown"
    "txt" | "log" => "text"
    "png" | "jpg" | "jpeg" | "heic" => "image"
    "mp4" | "mov" => "video"
    "mp3" | "m4a" => "audio"
    "pdf" => "pdf"
    "csv" => "csv"
    "json" | "py" | "ts" => "code"
    _ => "other"
  }
}

///|
/// The fixture's folders as the pages left them: by root and path, their entries.
let fix_folders : Map[String, Array[Json]] = {}

///|
fn fix_folder(root : String, path : String) -> Array[Json] {
  let key = root + "\n" + path
  match fix_folders.get(key) {
    Some(a) => a
    None => {
      let a : Array[Json] = if root == fix_docs && path == "" {
        [
          fix_entry("设计稿", true, 0, "10/12"),
          fix_entry("会议记录", true, 0, "昨天"),
          fix_entry("长篇小说.txt", false, novel_text().length() * 3, "14:05"),
          fix_entry("发布清单.md", false, 4210, "09:30"),
          fix_entry("首页截图.png", false, 812345, "10/16"),
          fix_entry("演示录屏.mp4", false, 48211000, "10/02"),
          fix_entry("季度数据.csv", false, 23110, "9/27"),
          fix_entry("合同草稿.pdf", false, 1260000, "2025/12/30"),
          fix_entry(".草稿缓存", false, 120, "10/18"),
        ]
      } else if root == fix_docs && path == "设计稿" {
        [
          fix_entry("旧版", true, 0, "8/03"),
          fix_entry("图标.png", false, 30211, "10/12"),
          fix_entry("配色说明.md", false, 1880, "10/12"),
        ]
      } else if path == "空文件夹" {
        []
      } else if root == fix_home && path == "" {
        [
          fix_entry("文档", true, 0, "14:05"),
          fix_entry("下载", true, 0, "昨天"),
          fix_entry("项目", true, 0, "10/11"),
        ]
      } else {
        [fix_entry("说明.txt", false, 320, "10/01")]
      }
      fix_folders[key] = a
      a
    }
  }
}

///|
fn fix_folder_json(root : String, path : String) -> Json {
  let entries = fix_folder(root, path)
  let folders = entries.filter(fn(e) { flag(Some(e), "dir") }).length()
  let files = entries.length() - folders
  let parts = []
  if folders > 0 {
    parts.push("\{folders} 个文件夹")
  }
  if files > 0 {
    parts.push("\{files} 个文件")
  }
  {
    "path": Json::string(path),
    "entries": Json::array(entries),
    "folders": Json::number(folders.to_double()),
    "files": Json::number(files.to_double()),
    "countText": Json::string(if parts.length() == 0 { "空文件夹" } else { dv_words(parts, " · ") }),
  }
}

///|
/// Where the made-up texts were left (drivePlace), by path.
let fix_places : Map[String, Json] = {}

///|
/// The copies asked (`drive.transfer`), as the `driveTransfers` topic shows them, newest first: each copying, 38% on.
let fix_transfers : Array[Json] = []

///|
fn fixture_drive_topic(f : Fixture, name : String, params : Map[String, Json]) -> Json? {
  let p = Some(Json::object(params))
  match name {
    "workspace" => Some({ "id": "ws1", "name": "星火工作室", "manager": true, "role": "owner" })
    "driveTransfers" =>
      Some({ "supported": true, "loaded": true, "transfers": Json::array(fix_transfers.copy()) })
    "drive" =>
      if f.mode == "drive-loading" {
        None
      } else {
        Some(fix_folder_json(text(p, "root"), text(p, "path")))
      }
    "drivePlace" => {
      let path = text(p, "path")
      match fix_places.get(path) {
        Some(v) => Some(v)
        None =>
          if path == "长篇小说.txt" && f.mode != "reader" {
            Some({ "at": 2400, "of": Json::number(novel_text().length().to_double()), "changed": 1 })
          } else if path == "长篇小说.txt" {
            Some({ "at": 0, "of": Json::number(novel_text().length().to_double()), "changed": 1 })
          } else {
            Some(Json::null())
          }
      }
    }
    _ => None
  }
}

///|
/// A copy asked (`drive.transfer`), shown in the `driveTransfers` topic as going: 38% on.
fn fix_transfer(params : Json) -> Unit {
  let p = Some(params)
  let from = field(p, "from")
  let to = field(p, "to")
  let names = items(from, "names").map(fn(n) {
    match n {
      String(s) => s
      _ => ""
    }
  })
  let title = names.get(0).unwrap_or("")
  let way = dv_name(dv_absolute(text(to, "root"), text(to, "path")))
  fix_transfers.insert(0, {
    "id": Json::string("t\{fix_transfers.length() + 1}"),
    "station": Json::string(text(to, "station")),
    "stationName": "MBA",
    "fromStation": Json::string(text(from, "station")),
    "fromStationName": "Studio",
    "fromRoot": Json::string(text(from, "root")),
    "fromPath": Json::string(text(from, "path")),
    "names": Json::array(names.map(fn(n) { Json::string(n) })),
    "toRoot": Json::string(text(to, "root")),
    "toPath": Json::string(text(to, "path")),
    "toText": Json::string("MBA › " + way),
    "title": Json::string(title),
    "move": Json::boolean(flag(p, "move")),
    "state": "copying",
    "active": true,
    "progress": 0.38,
    "total": 50541773,
    "copied": 19205873,
    "count": 1,
    "files": 1,
    "statusText": "18.3 MB / 48.2 MB",
    "createdAt": 1792300000000,
  })
}

///|
fn fixture_drive_call(f : Fixture, name : String, params : Json) -> Result[Json, Json]? {
  let p = Some(params)
  let root = text(p, "root")
  match name {
    "drive.transfer" => {
      fix_transfer(params)
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "drive.rename" => {
      let from = text(p, "from")
      let to = text(p, "to")
      let list = fix_folder(root, dv_parent(from))
      for i, e in list {
        if text(Some(e), "name") == dv_name(from) {
          match e {
            Object(m) => {
              let o = m.copy()
              o["name"] = Json::string(dv_name(to))
              list[i] = Json::object(o)
            }
            _ => ()
          }
        }
      }
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "drive.remove" => {
      let path = text(p, "path")
      fix_folder(root, dv_parent(path)).retain(fn(e) { text(Some(e), "name") != dv_name(path) })
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "drive.mkdir" => {
      let path = text(p, "path")
      fix_folder(root, dv_parent(path)).insert(0, fix_entry(dv_name(path), true, 0, "刚刚"))
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "drive.upload.part" => {
      let path = text(p, "path")
      let list = fix_folder(root, dv_parent(path))
      if list.iter().any(fn(e) { text(Some(e), "name") == dv_name(path) }) && !flag(p, "replace") {
        return Some(Err({ "code": "exists", "message": "已存在同名项", "status": 409 }))
      }
      let total = number(p, "total").to_int()
      list.retain(fn(e) { text(Some(e), "name") != dv_name(path) })
      list.push(fix_entry(dv_name(path), false, total, "刚刚"))
      f.version += 1
      Some(Ok({ "have": Json::number(total.to_double()), "entry": { "name": Json::string(dv_name(path)) } }))
    }
    "drive.place" => {
      fix_places[text(p, "path")] = {
        "at": Json::number(number(p, "at")),
        "of": Json::number(number(p, "of")),
        "changed": 1,
      }
      f.version += 1
      Some(Ok(Json::object({})))
    }
    "drive.refresh" | "drive.setRoots" => Some(Ok(Json::object({})))
    // a file put among the station's uploads, as one sent up would be (a folder zipped there)
    "drive.stage" => {
      let name = dv_name(text(p, "path")) + (if flag(p, "zip") { ".zip" } else { "" })
      Some(Ok({ "name": Json::string(name), "path": Json::string("uploads/" + name), "size": 4210 }))
    }
    // a folder zipped (as a station puts it among its zips): read as any file of the drive
    "drive.zip" => {
      let name = dv_name(text(p, "path")) + ".zip"
      Some(Ok({ "root": "/tmp/stillfail-zips/1", "path": Json::string(name), "name": Json::string(name), "size": 21 }))
    }
    "drive.folders" => {
      let path = match text(p, "path") {
        "" => fix_home
        x => x
      }
      let answer : Json = {
        "path": Json::string(path),
        "home": fix_home,
        "crumbs": if path == fix_home {
          [{ "name": "lin", "path": fix_home }]
        } else {
          [{ "name": "lin", "path": fix_home }, { "name": Json::string(dv_name(path)), "path": Json::string(path) }]
        },
        "entries": [
          { "name": "文档", "path": "/Users/lin/文档" },
          { "name": "项目", "path": "/Users/lin/项目" },
          { "name": "下载", "path": "/Users/lin/下载", "unreadable": true },
        ],
        // (as a station offers them: its home, the home's own folders, its disks)
        "places": [
          { "name": "主目录", "path": fix_home },
          { "name": "文档", "path": "/Users/lin/文档" },
          { "name": "下载", "path": "/Users/lin/下载", "unreadable": true },
          { "name": "外接硬盘", "path": "/Volumes/外接硬盘", "disk": true },
        ],
      }
      Some(Ok(answer))
    }
    _ => None
  }
}

///|
/// What `drive.read` was asked, in order (each its params).
let fix_reads : Array[Json] = []

///|
/// A part of a made-up file (`drive.read`): the novel, the Markdown, or a line.
fn fixture_drive_read(name : String, params : Json) -> Result[(Json, Bytes), Json]? {
  if name != "drive.read" {
    return None
  }
  fix_reads.push(params)
  let p = Some(params)
  let path = text(p, "path")
  let whole = if path.has_suffix(".md") {
    @utf8.encode(fixture_markdown())
  } else if path.has_suffix("小说.txt") {
    @utf8.encode(novel_text())
  } else {
    @utf8.encode("这是一个说明文件。\n")
  }
  let offset = number(p, "offset").to_int()
  let length = number(p, "length").to_int()
  let end = if offset + length < whole.length() { offset + length } else { whole.length() }
  let part = if offset >= end {
    Bytes::new(0)
  } else {
    Bytes::makei(end - offset, fn(i) { whole[offset + i] })
  }
  Some(Ok(({ "type": "text/plain", "total": Json::number(whole.length().to_double()) }, part)))
}

///|
/// A made-up novel of a few chapters (every sentence made up here).
fn novel_text() -> String {
  match fix_novel.val {
    Some(s) => s
    None => {
      let titles = ["第一章 雨后的车站", "第二章 旧仓库", "第三章 灯塔的钥匙", "第四章 回程", "尾声"]
      let lines = [
        "雨停的时候，站台上只剩下一盏灯还亮着，他把伞收好，靠在柱子旁边数着远处驶来的车厢。",
        "她说那封信是从北边寄来的，邮戳已经模糊，只能看出一个“七”字，像是某个月份，也像是某条街的门牌。",
        "仓库的门比想象中轻，推开时没有声音，只有一股潮湿的木头味道慢慢涌出来。",
        "他们在角落里找到一只铁皮箱子，箱子上贴着褪色的标签，写着一串谁也看不懂的编号。",
        "风从海面吹过来，把灯塔下的旗子拉得笔直，守塔的老人说今晚不会再有船经过了。",
        "钥匙并不在抽屉里，而是被缝进了一本旧账簿的封皮，摸上去能感到一点细小的凸起。",
        "回程的路上谁都没有说话，车窗外的田野一片一片地向后退去，像翻过的书页。",
        "等到天亮，他终于明白，那串编号指的不是箱子，而是车站里的一排储物柜。",
      ]
      let out = StringBuilder()
      for i, title in titles {
        out.write_string(title)
        out.write_char('\n')
        for k in 0..<14 {
          out.write_string("\u{3000}\u{3000}")
          out.write_string(lines[(i * 3 + k) % lines.length()])
          out.write_string(lines[(i + k * 5 + 1) % lines.length()])
          out.write_char('\n')
        }
        out.write_char('\n')
      }
      let s = out.to_string()
      fix_novel.val = Some(s)
      s
    }
  }
}

///|
// kept across runs: made from the words above alone, the same every time
let fix_novel : Ref[String?] = { val: None }

///|
fn fixture_markdown() -> String {
  "# 发布清单\n\n这份清单在每次发布前过一遍，**每一项**都要有人确认。\n\n## 准备\n\n- 版本号已经改好\n- 更新说明写完，交给 *两个人* 读过\n- 截图换成新的\n\n## 检查\n\n1. 在手机上装一遍，从头点到尾\n2. 看一眼 `release.log` 里有没有报错\n3. 旧版本升级上来，草稿还在\n\n> 有一项不确定，就先不发。\n\n---\n\n最后更新：十月中旬。\n"
}

///|
/// The fixture's drive pages opened as MBUI_FIXTURE says (see the top of this file).
pub fn open_drive_fixture(mode : String) -> Unit {
  let docs : DriveAt = { station: "ws1/st1", root: Some(fix_docs), path: "" }
  match mode {
    "files" => app.nav.push(Files)
    "drive" | "drive-loading" | "drive-upload" | "drive-download" => {
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      // a file being downloaded, a folder being zipped for it (the core's downloads, downloads_fixture.mbt): their rows'
      // progress (keep.mbt)
      if mode == "drive-download" {
        fix_drive_downloads("ws1/st1", fix_docs)
      }
      if mode == "drive-upload" {
        let up = fn(name : String, size : Int, sent : Int, state : String, error : String) {
          ups.serial += 1
          ups.uploads.push({
            serial: ups.serial,
            station: "ws1/st1",
            root: fix_docs,
            dir: "",
            name,
            bytes: Bytes::new(size),
            sent,
            state,
            error,
            replace: false,
            id: "",
          })
        }
        up("旅行照片.zip", 6291456, 2621440, "going", "")
        up("长篇小说.txt", 2048, 0, "taken", "")
        up("会议录音.m4a", 3145728, 0, "failed", "station 已离线")
        ups.pumping = true
      }
    }
    "drive-sub" => {
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      app.nav.push(Drive({ ..docs, path: "设计稿" }))
    }
    "drive-empty" => {
      app.nav.push(Files)
      app.nav.push(Drive({ ..docs, path: "空文件夹" }))
    }
    "reader" | "reader-bars" | "reader-contents" | "reader-layout" | "reader-md" => {
      let path = if mode == "reader-md" { "发布清单.md" } else { "长篇小说.txt" }
      let at = { ..docs, path }
      app.nav.push(Files)
      app.nav.push(Drive(docs))
      app.nav.push(DriveRead(at))
      let r = @sf.reading_for(reader_key(at))
      if mode != "reader" && mode != "reader-md" {
        r.chrome = true
      }
      if mode == "reader-contents" {
        r.panel = @sf.ReaderPanel::Contents
        r.contents_put = false
      }
      if mode == "reader-layout" {
        r.panel = @sf.ReaderPanel::Layout
        r.contents_put = false
      }
    }
    // (chat-station-files: ＋'s Station 文件 put up as the app's source is made, fixture_station_files)
    // (chat-attach-row: put in before the draft's kept files are read, so it is the first of the files' row)
    "chat-station-ref" | "chat-attach-row" =>
      fix_draft_ref("ws1/st1:s-c1", "发布清单.md", false, 4210.0, "path", true)
    // one sent as a file (up at the chat's station), a folder as a zip still going; a card's sheet open
    // (open_fixture_src)
    "chat-station-file" | "chat-station-sheet" => {
      fix_draft_ref("ws1/st1:s-c1", "发布清单.md", false, 4210.0, "file", true)
      fix_draft_ref("ws1/st1:s-c1", "设计稿", true, 0.0, "file", false)
    }
    // the player (play_fixture.mbt), a service's page (service_fixture.mbt)
    _ => {
      open_play_fixture(mode)
      open_service_fixture(mode)
      open_share_fixture(mode)
    }
  }
}

///|
/// Studio's 文档/`name` in draft `key` as ＋'s Station 文件 puts it there (writing_drop: composer.add, the file with
/// where it is, `mode` how it goes: "path", named by it; "file", sent as one), up already (`done`, as the fixture's
/// composer.add has it) or still going.
fn fix_draft_ref(key : String, name : String, dir : Bool, size : Double, mode : String, done : Bool) -> Unit {
  let path = fix_docs + "/" + name
  let one : Map[String, Json] = {
    "id": Json::string("ref-" + name),
    "name": Json::string(name),
    "size": Json::number(size),
    "ref": {
      "station": "ws1/st1",
      "stationName": "Studio",
      "path": Json::string(path),
      "dir": Json::boolean(dir),
      "mode": Json::string(mode),
    },
    "drive": { "station": "ws1/st1", "root": Json::string(fix_docs), "path": Json::string(name) },
  }
  if done {
    one["sent"] = Json::number(size)
    one["done"] = { "name": Json::string(name), "path": Json::string("uploads/" + name), "size": Json::number(size) }
  }
  fix_composers[key] = fix_composers.get(key).unwrap_or([]) + [Json::object(one)]
}
