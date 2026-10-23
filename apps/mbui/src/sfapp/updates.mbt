// The app keeping itself current (ember apps/android app/Updates.kt, Install.kt; Home.kt's update button,
// SettingsHome.kt Version): a newer build is asked of the update source the app is given (`set_update_source`), and
// one found is downloaded, checked against its sha256 and handed to the system's installer (@hostapi.update_install:
// Android's Updates.java), which installs it over this one once the person agrees. Asked at the start; Home offers a
// build that brings something the changelog says (a download key with its dot; how far while it downloads), the
// settings' version row any (更新到 …; 检查更新 asks now, 已是最新 said when none). Hosts that do not update
// themselves (a version code of 0: all but Android) never ask.
//
// Where a build comes from is the source's: `cloud_updates(feed)` is still.fail cloud's, as the Android app has it (the
// core's `app.update`, at most hourly unless asked now: /releases/<feed>/latest.json, an AppRelease; its `file` under
// /releases/). The mbui build ships apart from still.fail's (its own package and key, a release of its own), so no
// source is given by default: src/stillfail gives the cloud's for MBUI_UPDATE_FEED=<feed> (the local cloud's in e2e).
// A source of a release elsewhere answers the same AppRelease (versionCode, versionName, file: a path under the
// source's releases or a whole https URL, sha256, size, news).

///|
// kept across runs: a table, never written
let up_zh : Map[String, String] = {
  "android-chat.home.update": "更新到 {version}",
  "android-misc.updates.allowInstall": "允许 {app} 安装应用后，再点一次更新",
  "android-misc.updates.checkFailed": "检查更新失败：{error}",
  "android-misc.updates.checking": "正在检查最新版本",
  "android-misc.updates.downloading": "下载中",
  "android-misc.updates.downloadingPercent": "下载中 {percent}%",
  "android-misc.updates.failed": "无法更新：{error}",
  "android-misc.updates.incomplete": "下载的文件不完整，请重试",
  "android-misc.updates.httpStatus": "下载返回 {status}",
  "android-misc.updates.installing": "正在安装",
  "android-misc.updates.latest": "已是最新",
  "android-misc.updates.retrying": "网络中断，正在继续下载",
  "android-settings.version.check": "检查更新",
  "android-settings.version.checking": "正在检查",
  "android-settings.version.update": "更新到 {version}",
}

///|
fn up(key : String, args? : Array[(String, String)] = []) -> String {
  let mut s = match english(key, args~) {
    Some(w) => w
    None => up_zh.get(key).unwrap_or(key)
  }
  for a in args {
    s = s.replace_all(old="{" + a.0 + "}", new=a.1)
  }
  s
}

///|
/// Where newer builds come from: `check(version, now, done)` answers the newest build when newer than `version` (an
/// AppRelease, or null), asking again at once when `now` (else it may answer what it last heard); `url(file)` is where
/// a build's file is downloaded from.
pub(all) struct UpdateSource {
  check : (Int, Bool, (Result[Json, String]) -> Unit) -> Unit
  url : (String) -> String
}

///|
/// How an update stands: the newer build found, a check under way (the person's, or one before installing), the
/// host's phase last seen, the source.
priv struct Update {
  mut available : Json?
  mut asked : Bool
  mut checking : Bool
  mut installing : Bool
  mut phase : String
  mut source : UpdateSource?
}

///|
let update : Update = {
  available: None,
  asked: false,
  checking: false,
  installing: false,
  phase: "idle",
  source: None,
}

///|
/// This build's version code as tests have it (0: the host's).
let update_version : Ref[Int] = Ref(0)

///|
/// The source newer builds are asked of (none: the app never asks).
pub fn set_update_source(s : UpdateSource?) -> Unit {
  update.source = s
}

///|
/// still.fail cloud's feed `feed` (the Android app's is `android`), asked through the core (`app.update`) of `src`;
/// its files under `origin`/releases/.
pub fn cloud_updates(src : Source, feed : String, origin : String) -> UpdateSource {
  {
    check: fn(version, now, done) {
      let params : Map[String, Json] = {
        "platform": Json::string(feed),
        "versionCode": Json::number(version.to_double()),
        "now": Json::boolean(now),
      }
      (src.call)("app.update", Json::object(params), fn(r) {
        match r {
          Ok(v) => done(Ok(v))
          Err(e) => done(Err(text(Some(e), "message")))
        }
      })
    },
    url: fn(file) {
      if file.has_prefix("https://") || file.has_prefix("http://") {
        file
      } else {
        origin + "/releases/" + file
      }
    },
  }
}

///|
/// Asks the source for a newer build; `done` gets what to say when it was asked now (none newer, or why it failed),
/// "" otherwise.
fn update_check(src : Source, now : Bool, done? : (String) -> Unit = fn(_) {  }) -> Unit {
  let version = if update_version.val > 0 { update_version.val } else { @hostapi.app_version() }
  let source = match update.source {
    Some(s) => s
    None => return
  }
  if version <= 0 || src.read_only {
    return
  }
  (source.check)(version, now, fn(r) {
    match r {
      Ok(Object(_) as v) => {
        update.available = Some(v)
        @hostapi.log("update: \{text(Some(v), "versionName")} (\{number(Some(v), "versionCode").to_int()}) is newer than this build (\{version})")
        done("")
      }
      Ok(_) => {
        update.available = None
        done(if now { up("android-misc.updates.latest") } else { "" })
      }
      Err(e) => done(if now { up("android-misc.updates.checkFailed", args=[("error", e)]) } else { "" })
    }
  })
}

///|
/// The newer build downloaded and handed to the installer (Updates.kt install): asked again now first; none newer
/// said so.
fn update_install(src : Source) -> Unit {
  if update.checking || update.installing || update_busy() {
    return
  }
  update.installing = true
  update_check(src, true, done=fn(said) {
    update.installing = false
    match update.available {
      Some(v) if said == "" => {
        let file = text(Some(v), "file")
        let name = match file.rev_find("/") {
          Some(i) => file.view(start_offset=i + 1).to_owned()
          None => file
        }
        @hostapi.log("update: \{file} asked for")
        match update.source {
          Some(source) =>
            @ui.update_install((source.url)(file), text(Some(v), "sha256"), number(Some(v), "size"), name)
          None => ()
        }
      }
      _ => up_say(said)
    }
  })
}

///|
fn up_say(words : String) -> Unit {
  if words != "" {
    app.toast = words
    app.toast_n += 1
  }
}

///|
/// What went wrong with an update as the host said it, in the words Android's Updates.kt says it in: a download cut
/// short, the download's answer ("status 404", as Updates.java says it: 下载返回 404), else as said.
fn update_error(e : String) -> String {
  match e {
    "incomplete" => up("android-misc.updates.incomplete")
    e if e.has_prefix("status ") =>
      up("android-misc.updates.httpStatus", args=[("status", e.view(start_offset=7).to_string())])
    e => e
  }
}

///|
/// What an update under way is doing ("下载中 40%"), "" when none is; what went wrong said once.
fn update_progress() -> String {
  if update.installing {
    return up("android-misc.updates.checking")
  }
  let st = @ui.update_state()
  if st == "" {
    return ""
  }
  let v = try Some(@json.parse(st)) catch { _ => None }
  let phase = text(v, "phase")
  if phase != update.phase {
    update.phase = phase
    match phase {
      "failed" =>
        up_say(
          up("android-misc.updates.failed", args=[
            ("error", update_error(text(v, "error"))),
          ]),
        )
      "allow" => up_say(up("android-misc.updates.allowInstall", args=[("app", "still.fail")]))
      _ => ()
    }
  }
  match phase {
    "downloading" => {
      let p = number(v, "percent").to_int()
      if p >= 0 {
        up("android-misc.updates.downloadingPercent", args=[("percent", p.to_string())])
      } else {
        up("android-misc.updates.downloading")
      }
    }
    "retrying" => up("android-misc.updates.retrying")
    "installing" => up("android-misc.updates.installing")
    _ => ""
  }
}

///|
fn update_busy() -> Bool {
  match update.phase {
    "downloading" | "retrying" | "installing" => true
    _ => false
  }
}

///|
/// Asked once the app is signed in (MainActivity's check at the start).
fn update_first(src : Source) -> Unit {
  if !update.asked {
    update.asked = true
    update_check(src, false)
  }
}

///|
/// Home's update key (Home.kt): a newer build that brings something the changelog says, quiet like the bar's other
/// keys (the download icon with an accent dot); while it downloads, how far it is instead. Tapped, it is installed.
fn update_button(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let progress = update_progress()
  if progress != "" {
    // (read out whole: Home.kt's contentDescription = progress)
    c.box(label=progress, fn() {
      c.text(
        match progress.find(" ") {
          Some(i) => progress.view(start_offset=i + 1).to_owned()
          None => "…"
        },
        size=13.0,
        color=t.p.muted,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
    return
  }
  match update.available {
    Some(v) if items(Some(v), "news").length() > 0 =>
      c.box(fn() {
        if nav_button(c, "download", 20.0, key="home-update", said=up("android-chat.home.update", args=[("version", text(Some(v), "versionName"))])) {
          update_install(src)
        }
        c.layer(align=AEnd, fn() {
          c.box(pt=3.0, pr=3.0, fn() {
            c.box(w=Px(13.0), h=Px(13.0), radius=6.5, bg=t.p.bg, pad=2.0, fn() {
              c.box(w=Fill(1.0), h=Fill(1.0), radius=4.5, bg=t.p.accent, fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// The settings' version row's words at its end (SettingsHome.kt Version), and whether they are the accent's: how an
/// update goes, 正在检查, 更新到 <version>, or 检查更新.
fn update_row_words() -> (String, Bool) {
  let progress = update_progress()
  if progress != "" {
    return (progress, false)
  }
  if update.checking {
    return (up("android-settings.version.checking"), false)
  }
  match update.available {
    Some(v) => (up("android-settings.version.update", args=[("version", text(Some(v), "versionName"))]), true)
    None => (up("android-settings.version.check"), false)
  }
}

///|
/// The version row tapped: with a newer build known, installed; with none, still.fail cloud asked now.
fn update_row_tapped(src : Source) -> Unit {
  if update.checking || update.installing || update_busy() {
    return
  }
  match update.available {
    Some(_) => update_install(src)
    None => {
      update.checking = true
      update_check(src, true, done=fn(said) {
        update.checking = false
        up_say(said)
      })
    }
  }
}

///|
/// 检查更新 chosen in the menu bar (menu_bar.mbt), as the desktop app's checkFromMenu: the settings' 版本 page
/// opened, where how it goes is shown and a newer build is offered (更新到 …), and still.fail cloud asked now unless
/// one is known already (what it says, 已是最新 or why it failed, said as the row's tap says it).
fn update_from_menu(src : Source) -> Unit {
  if !(app.nav.top() is Setting(@settings.Route::Version)) {
    open_setting("version")
  }
  if update.available is None {
    update_row_tapped(src)
  }
}
