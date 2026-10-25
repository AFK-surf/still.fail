// The app keeping itself current, for both frames (ember apps/android app/Updates.kt, Install.kt; the desktop app's
// appUpdate): a newer build is asked of the update source the app is given (`set_update_source`), and one found is
// downloaded, checked against its sha256 and handed to the host's installer (@ui.update_install), which puts it in
// place of this one. Asked at the start; 关于's version row offers it (update_stands, below), the phone's
// Home (sfapp updates.mbt) and the desktop's 更新 over the sidebar's top (sfdesk brand.mbt). Hosts that do not update
// themselves (a version code of 0) never ask.
//
// Where a build comes from is the source's: `cloud_updates(feed)` is still.fail cloud's (the core's `app.update`, at
// most hourly unless asked now: /releases/<feed>/latest.json, an AppRelease; its `file` under /releases/). No source
// is given by default: src/stillfail gives the cloud's for MBUI_UPDATE_FEED=<feed> (the local cloud's in e2e). A
// source of a release elsewhere answers the same AppRelease (versionCode, versionName, file: a path under the source's
// releases or a whole https URL, sha256, size, news).

///|
/// As at the start (the app's reset).
pub fn update_reset() -> Unit {
  update.available = None
  update.asked = false
  update.checking = false
  update.installing = false
  update.phase = "idle"
  update.source = None
  update_version.val = 0
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
pub(all) struct Update {
  mut available : Json?
  mut asked : Bool
  mut checking : Bool
  mut installing : Bool
  mut phase : String
  mut source : UpdateSource?
}

///|
pub let update : Update = {
  available: None,
  asked: false,
  checking: false,
  installing: false,
  phase: "idle",
  source: None,
}

///|
/// This build's version code as tests have it (0: the host's).
pub let update_version : Ref[Int] = Ref(0)

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
pub fn update_check(src : Source, now : Bool, done? : (String) -> Unit = fn(_) {  }) -> Unit {
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
        done(if now { @sf.t("android-misc.updates.latest") } else { "" })
      }
      Err(e) => done(if now { @sf.t("android-misc.updates.checkFailed", args=[("error", e)]) } else { "" })
    }
  })
}

///|
/// The newer build downloaded and handed to the installer (Updates.kt install): asked again now first; none newer
/// said so.
pub fn update_install(src : Source) -> Unit {
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
      _ => update_say(said)
    }
  })
}

///|
/// What an update has to say (none newer, why it failed), in the toast.
pub fn update_say(words : String) -> Unit {
  if words != "" {
    toast_later(words)
  }
}

///|
/// What went wrong with an update as the host said it, in the words Android's Updates.kt says it in: a download cut
/// short, the download's answer ("status 404", as Updates.java says it: 下载返回 404), else as said.
pub fn update_error(e : String) -> String {
  match e {
    "incomplete" => @sf.t("android-misc.updates.incomplete")
    e if e.has_prefix("status ") =>
      @sf.t("android-misc.updates.httpStatus", args=[("status", e.view(start_offset=7).to_string())])
    e => e
  }
}

///|
/// What an update under way is doing ("下载中 40%"), "" when none is; what went wrong said once.
pub fn update_progress() -> String {
  if update.installing {
    return @sf.t("android-misc.updates.checking")
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
        update_say(
          @sf.t("android-misc.updates.failed", args=[
            ("error", update_error(text(v, "error"))),
          ]),
        )
      "allow" => update_say(@sf.t("android-misc.updates.allowInstall", args=[("app", "still.fail")]))
      _ => ()
    }
  }
  match phase {
    "downloading" => {
      let p = number(v, "percent").to_int()
      if p >= 0 {
        @sf.t("android-misc.updates.downloadingPercent", args=[("percent", p.to_string())])
      } else {
        @sf.t("android-misc.updates.downloading")
      }
    }
    "retrying" => @sf.t("android-misc.updates.retrying")
    "installing" => @sf.t("android-misc.updates.installing")
    _ => ""
  }
}

///|
pub fn update_busy() -> Bool {
  match update.phase {
    "downloading" | "retrying" | "installing" => true
    _ => false
  }
}

///|
/// Whether an update is under way, as the update key shows it: still.fail cloud asked again before it is downloaded,
/// downloading, going on after the network came back, being installed.
pub fn update_under_way() -> Bool {
  update.installing || update_busy()
}

///|
/// How far the update under way has come (0 to 1) while it downloads and the host says how far; None otherwise (asked
/// again first, going on after the network came back, being installed: how far is not known).
pub fn update_part() -> Double? {
  if update.phase != "downloading" {
    return None
  }
  let v = try Some(@json.parse(@ui.update_state())) catch { _ => None }
  let p = number(v, "percent")
  if p >= 0.0 {
    Some(p / 100.0)
  } else {
    None
  }
}

///|
/// Asked once the app is signed in (MainActivity's check at the start).
pub fn update_first(src : Source) -> Unit {
  if !update.asked {
    update.asked = true
    update_check(src, false)
  }
}

///|
/// How this build's update stands, as 关于's version row says it (SettingsHome.kt Version): what is under way (how an
/// update goes; 正在检查 while the person's check is) and the newer build known.
pub fn update_stands() -> @settings.VersionNow {
  let progress = update_progress()
  let doing = if progress == "" && update.checking { @sf.t("android-settings.version.checking") } else { progress }
  let newer = match update.available {
    Some(v) => text(Some(v), "versionName")
    None => ""
  }
  { doing, newer }
}

///|
/// The version row's button pressed: with a newer build known, installed; with none, still.fail cloud asked now.
pub fn update_row_tapped(src : Source) -> Unit {
  if update.checking || update.installing || update_busy() {
    return
  }
  match update.available {
    Some(_) => update_install(src)
    None => {
      update.checking = true
      update_check(src, true, done=fn(said) {
        update.checking = false
        update_say(said)
      })
    }
  }
}

///|
/// 检查更新 chosen in the menu bar (menu_bar.mbt), as the desktop app's checkFromMenu: the settings' 关于 opened, where
/// how it goes is shown and a newer build is offered (更新到 …), and still.fail cloud asked now unless one is known
/// already (what it says, 已是最新 or why it failed, said as the row's button says it).
pub fn update_from_menu(src : Source) -> Unit {
  if !(app.nav.top() is Setting(@settings.Route::About)) {
    open_setting("about")
  }
  if update.available is None {
    update_row_tapped(src)
  }
}
