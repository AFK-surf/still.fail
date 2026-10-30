// The app keeping itself current, for both frames (ember apps/android app/Updates.kt, Install.kt; the desktop app's
// appUpdate): a newer build is asked of the update source the app is given (`set_update_source`), and one found is
// downloaded, checked against its sha256 and handed to the host's installer (@ui.update_install), which puts it in
// place of this one. Asked at the start; the phone's Home (sfapp updates.mbt) and the desktop's sidebar (sfdesk
// brand.mbt) offer one found with the update key, pressed installed. Asked now (the menu bar's 检查更新…, 关于's version
// row), one dialog says it all as it goes (update_dialog, below): asking, none newer or why it could not ask, the newer
// build and what it brings, how far it has come and what went wrong, in place, not in a toast that goes. Hosts that do
// not update themselves (a version code of 0, or no source: iOS) never ask, and 关于 offers no check.
//
// Where a build comes from is the source's: `cloud_updates(feed)` is still.fail cloud's (the core's `app.update`, at
// most hourly unless asked now: /releases/<feed>/latest.json, an AppRelease; its `file` under /releases/). No source
// is given by default: src/stillfail gives the cloud's for MBUI_UPDATE_FEED=<feed> (the local cloud's in e2e). A
// source of a release elsewhere answers the same AppRelease (versionCode, versionName, file: a path under the source's
// releases or a whole https URL, sha256, size, news).

///|
/// As at the start (the app's reset).
pub fn update_reset() -> Unit {
  update.available.set(None)
  update.asked = false
  update.checking.set(false)
  update.installing.set(false)
  update.source.set(None)
  update.said.set(Unsaid)
  update.dialog = 0
  update_version.val = 0
  update_say_follows()
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
/// What the last check asked now answered, where it found no newer build: nothing yet (or a newer one), none newer, or
/// why it could not ask.
pub(all) enum UpdateSaid {
  Unsaid
  NoneNewer
  CouldNot(String)
} derive(Eq, Debug)

///|
/// How an update stands: the newer build found, a check under way (the person's, or one before installing), what
/// the last check asked now answered, each a signal (what shows them follows them as they change, as the host's word of
/// how it goes is followed: update_how); whether it was asked at the start, the source, the update dialog (its
/// presenter's serial, 0 none yet).
pub(all) struct Update {
  available : @signals.Signal[Json?]
  // (asked, dialog plain: asked once at the start; the dialog's presenter serial, read only to close it)
  mut asked : Bool
  checking : @signals.Signal[Bool]
  installing : @signals.Signal[Bool]
  source : @signals.Signal[UpdateSource?]
  said : @signals.Signal[UpdateSaid]
  mut dialog : Int
}

///|
// kept across runs: put back by update_reset
pub let update : Update = {
  available: @signals.signal(None),
  asked: false,
  checking: @signals.signal(false, same=fn(a, b) { a == b }),
  installing: @signals.signal(false, same=fn(a, b) { a == b }),
  source: @signals.signal(None),
  said: @signals.signal(Unsaid, same=fn(a, b) { a == b }),
  dialog: 0,
}

///|
/// This build's version code as tests have it (0: the host's).
pub let update_version : Ref[Int] = Ref(0)

///|
/// The source newer builds are asked of (none: the app never asks).
pub fn set_update_source(s : UpdateSource?) -> Unit {
  update.source.set(s)
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
      // release keys taken beside the app's own (the core's app-release.ts): its environment's STILLFAIL_RELEASE_KEYS,
      // comma-separated, as the station and the desktop app take them (a test's own releases, a dev cloud's)
      let keys = @ui.env("STILLFAIL_RELEASE_KEYS")
        .split(",")
        .map(fn(k) { k.trim().to_string() })
        .filter(fn(k) { k != "" })
        .map(Json::string)
        .collect()
      if keys.length() > 0 {
        params["keys"] = Json::array(keys)
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
/// This build's version code (a test's, else the host's: 0 where it has none).
fn this_version() -> Int {
  if update_version.val > 0 {
    update_version.val
  } else {
    @hostapi.app_version()
  }
}

///|
/// Whether newer builds are asked for here: a source given and a version code (none on iOS, nor run from the sources).
pub fn update_asks() -> Bool {
  update.source.get() is Some(_) && this_version() > 0
}

///|
/// Asks the source for a newer build; `done` gets what to say when it was asked now (none newer, or why it failed),
/// "" otherwise. Asked now, what it answered is kept (`update.said`) for the dialog; where it cannot be asked, why.
pub fn update_check(src : Source, now : Bool, done? : (String) -> Unit = fn(_) {  }) -> Unit {
  let version = this_version()
  let source = match update.source.get() {
    Some(s) if version > 0 && !src.read_only => s
    _ => {
      if now {
        let why = @sf.t("desktop.update.dev")
        update.said.set(CouldNot(why))
        done(@sf.t("android-misc.updates.checkFailed", args=[("error", why)]))
      }
      return
    }
  }
  (source.check)(version, now, fn(r) {
    match r {
      Ok(Object(_) as v) => {
        update.available.set(Some(v))
        if now {
          update.said.set(Unsaid)
        }
        @hostapi.log("update: \{text(Some(v), "versionName")} (\{number(Some(v), "versionCode").to_int()}) is newer than this build (\{version})")
        done("")
      }
      Ok(_) => {
        update.available.set(None)
        if now {
          update.said.set(NoneNewer)
        }
        done(if now { @sf.t("android-misc.updates.latest") } else { "" })
      }
      Err(e) => {
        if now {
          update.said.set(CouldNot(e))
        }
        done(if now { @sf.t("android-misc.updates.checkFailed", args=[("error", e)]) } else { "" })
      }
    }
  })
}

///|
/// The newer build downloaded and handed to the installer (Updates.kt install): asked again now first; none newer
/// said so.
pub fn update_install(src : Source) -> Unit {
  if update.checking.get() || update.installing.get() || update_busy() {
    return
  }
  update.installing.set(true)
  update_check(src, true, done=fn(said) {
    match update.available.get() {
      Some(v) if said == "" => {
        let file = text(Some(v), "file")
        let name = match file.rev_find("/") {
          Some(i) => file.view(start_offset=i + 1).to_owned()
          None => file
        }
        @hostapi.log("update: \{file} asked for")
        match update.source.get() {
          Some(source) =>
            @ui.update_install((source.url)(file), text(Some(v), "sha256"), number(Some(v), "size"), name)
          None => ()
        }
        // (no longer asking once the host has it, as it says it downloads: 正在检查 goes on to 下载中, nothing between)
        update.installing.set(false)
      }
      _ => {
        update.installing.set(false)
        update_say(said)
      }
    }
  })
}

///|
/// What an update has to say (none newer, why it failed), in the toast; not while the dialog is open, which says it.
pub fn update_say(words : String) -> Unit {
  if words != "" && !update_dialog_open() {
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
/// How the update goes as the host tells it (@ui.update_state's JSON): its phase (idle, allow, downloading, retrying,
/// installing, handed, failed), how far (-1 not known) and what went wrong.
priv struct UpdateHow {
  phase : String
  percent : Int
  error : String
} derive(Eq)

///|
/// How the update goes, worked out of the host's word as that changes (a computed of @ui.update_state, a signal the
/// host's events set): what shows it reads it here and follows it, never a copy one reader refreshed (2026-10-27: the
/// small screen's update row read such a copy, which said idle while the host downloaded, and offered 更新 again after
/// its check). Nothing told (a Tester, a host that does not update itself): idle.
// kept across runs: worked out of a signal the Tester puts back
let update_how : @signals.Computed[UpdateHow] = @signals.computed(
  fn(_) {
    let v = try Some(@json.parse(@ui.update_state())) catch { _ => None }
    match v {
      Some(_) => { phase: text(v, "phase"), percent: number(v, "percent").to_int(), error: text(v, "error") }
      None => { phase: "idle", percent: -1, error: "" }
    }
  },
  same=fn(a, b) { a == b },
)

///|
/// The update's phase as the host tells it (update_how).
pub fn update_phase() -> String {
  update_how.get().phase
}

///|
/// How far the download has come as the host tells it, in percent (-1 not known).
pub fn update_percent() -> Int {
  update_how.get().percent
}

///|
/// What went wrong with the update, in the words it is said in (update_error), "" where nothing has.
pub fn update_why() -> String {
  let how = update_how.get()
  if how.phase == "failed" {
    update_error(how.error)
  } else {
    ""
  }
}

///|
/// What follows the host's word to say what went wrong, or that the leave to install apps is asked, once as it comes
/// (update_say: in a toast where the dialog is not open to say it); let go of as the app begins again.
// kept across runs: made anew by update_reset
let update_saying : Ref[(() -> Unit)?] = { val: None }

///|
fn update_say_follows() -> Unit {
  match update_saying.val {
    Some(stop) => stop()
    None => ()
  }
  let seen = Ref(update_how.peek().map(fn(h) { h.phase }).unwrap_or("idle"))
  update_saying.val = Some(
    @signals.effect(fn() {
      let how = update_how.get()
      if how.phase != seen.val {
        seen.val = how.phase
        @signals.untracked(fn() {
          match how.phase {
            "failed" =>
              update_say(@sf.t("android-misc.updates.failed", args=[("error", update_error(how.error))]))
            "allow" => update_say(@sf.t("android-misc.updates.allowInstall", args=[("app", "still.fail")]))
            _ => ()
          }
        })
      }
    }),
  )
}

///|
/// What an update under way is doing ("下载中 40%"), "" when none is.
pub fn update_progress() -> String {
  if update.installing.get() {
    return @sf.t("android-misc.updates.checking")
  }
  let how = update_how.get()
  match how.phase {
    "downloading" => {
      let p = how.percent
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
  match update_phase() {
    "downloading" | "retrying" | "installing" => true
    _ => false
  }
}

///|
/// Whether an update is under way, as the update key shows it: still.fail cloud asked again before it is downloaded,
/// downloading, going on after the network came back, being installed.
pub fn update_under_way() -> Bool {
  update.installing.get() || update_busy()
}

///|
/// How far the update under way has come (0 to 1) while it downloads and the host says how far; None otherwise (asked
/// again first, going on after the network came back, being installed: how far is not known).
pub fn update_part() -> Double? {
  let how = update_how.get()
  if how.phase == "downloading" && how.percent >= 0 {
    Some(how.percent.to_double() / 100.0)
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
  let doing = if progress == "" && update.checking.get() { @sf.t("android-settings.version.checking") } else { progress }
  let newer = match update.available.get() {
    Some(v) => text(Some(v), "versionName")
    None => ""
  }
  { doing, part: update_part(), newer, asks: update_asks() }
}

///|
/// The version row pressed: with a newer build known (更新到 …), installed; the dialog opened, saying how it goes (with
/// none known, still.fail cloud asked now).
pub fn update_row_tapped(src : Source) -> Unit {
  if update.available.get() is Some(_) {
    update_install(src)
  }
  update_dialog(src)
}

///|
/// 检查更新 chosen in the menu bar (menu_bar.mbt), as the desktop app's checkFromMenu: the dialog over what is open,
/// still.fail cloud asked now unless a newer build is known already (offered: 更新 or 稍后).
pub fn update_from_menu(src : Source) -> Unit {
  update_dialog(src)
}

///|
/// Whether the update dialog is open.
pub fn update_dialog_open() -> Bool {
  update.dialog > 0 && @sf.presented_open_of(update.dialog)
}

///|
/// The update dialog (a sheet with a finger short of Large), over what is open: still.fail cloud asked now where no
/// newer build is known and nothing is under way; then, as it goes, what it answered (none newer, why it could not
/// ask: 重试), the newer build and what it brings (更新 or 稍后), how far it has come and what went wrong. Open
/// already, it stays the one.
pub fn update_dialog(src : Source) -> Unit {
  if update.available.get() is None && !update.checking.get() && !update_under_way() {
    update_ask_now(src)
  }
  if update_dialog_open() {
    return
  }
  let (title, lead) = update_dialog_words()
  @sf.panel(
    title,
    fn(c, _) { update_dialog_body(c) },
    from=Unanchored,
    description=lead,
    live=fn() {
      let (title, lead) = update_dialog_words()
      (title, "", lead)
    },
    foot=fn(c, close) { update_dialog_foot(c, src, close) },
  )
  update.dialog = @sf.last_presented()
}

///|
/// still.fail cloud asked now, by the person (what it answers kept: update_check).
fn update_ask_now(src : Source) -> Unit {
  update.checking.set(true)
  update.said.set(Unsaid)
  update_check(src, true, done=fn(_) { update.checking.set(false) })
}

///|
/// What the dialog is about: still.fail cloud being asked, none newer, why it could not ask, the newer build.
priv enum UpdateTalk {
  Asking
  Latest
  Failed(String)
  Newer(Json)
}

///|
fn update_talk() -> UpdateTalk {
  match update.available.get() {
    Some(v) => Newer(v)
    None if update.checking.get() || update.installing.get() => Asking
    None =>
      match update.said.get() {
        NoneNewer => Latest
        CouldNot(why) => Failed(why)
        Unsaid => Asking
      }
  }
}

///|
/// The dialog's title and the line under it: what it is about, this build's version under it (why it could not ask
/// in its place).
fn update_dialog_words() -> (String, String) {
  let current = @sf.t("web-pages.changelog.build", args=[("build", this_version().to_string())])
  match update_talk() {
    Asking => (@sf.t("android-misc.updates.checking"), current)
    Latest => (@sf.t("desktop.update.latest"), current)
    Failed(why) => (@sf.t("desktop.update.checkFailed"), why)
    Newer(v) => (@sf.t("desktop.update.available", args=[("version", text(Some(v), "versionName"))]), current)
  }
}

///|
/// How many of what a newer build brings the dialog says before 还有 n 项 (the changelog page has them all).
let update_news_most : Int = 5

///|
/// What the dialog holds: while still.fail cloud is asked, a bar going to and fro; for a newer build, what it brings
/// (its first few, 还有 n 项), then how its update goes (how far, in words under the bar) or what went wrong (red), each
/// whole on its line.
fn update_dialog_body(c : @ui.Ctx) -> Unit {
  match update_talk() {
    Asking => c.box(style=update_body.then(@sf.panel_words_in()), fn() { @sf.progress(c, "update/asking", None) }) |> ignore
    Newer(v) => {
      let news : Array[String] = []
      for n in items(Some(v), "news") {
        if n is String(line) {
          news.push(line)
        }
      }
      let doing = update_progress()
      let (trouble, bad) = update_trouble()
      if news.is_empty() && doing == "" && trouble == "" {
        return
      }
      c.box(style=update_body.then(@sf.panel_words_in()), fn() {
        for i, line in news {
          if i >= update_news_most {
            c.text(@sf.t("android-settings.changelog.more", args=[("n", (news.length() - i).to_string())]), style=@sf.pg_note) |> ignore
            break
          }
          c.text(line, style=update_news_line) |> ignore
        }
        if doing != "" {
          c.box(style=update_going, fn() {
            @sf.progress(c, "update/part", update_part())
            c.text(doing, style=@sf.pg_note) |> ignore
          })
          |> ignore
        } else if trouble != "" {
          c.box(style=update_going, fn() {
            c.text(trouble, style=if bad { @sf.pg_note_bad } else { @sf.pg_note }) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    Latest | Failed(_) => ()
  }
}

///|
/// What the dialog's foot offers: 取消 while still.fail cloud is asked; 确定 where none is newer; 重试 where it could not
/// ask; 更新 for a newer build (turning while it goes; again where it failed), and 稍后 (关闭 once it goes on by itself).
fn update_dialog_foot(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  match update_talk() {
    Asking =>
      if @sf.button(c, @sf.t("common.cancel"), key="update/cancel", tone=Ghost) {
        close()
      }
    Latest =>
      if @sf.button(c, @sf.t("common.confirm"), key="update/ok", tone=Primary) {
        close()
      }
    Failed(_) => {
      if @sf.button(c, @sf.t("common.cancel"), key="update/cancel", tone=Ghost) {
        close()
      }
      if @sf.button(c, @sf.t("common.retry"), key="update/retry", tone=Primary) {
        update_ask_now(src)
      }
    }
    Newer(_) => {
      let going = update_under_way()
      if @sf.button(c, @sf.t(if going { "common.close" } else { "desktop.update.later" }), key="update/later", tone=Ghost) {
        close()
      }
      if @sf.button(c, @sf.t("desktop.update.update"), key="update/go", tone=Primary, busy=going) {
        update_install(src)
      }
    }
  }
}

///|
/// What went wrong with the update as the host says it (无法更新：…, red), or what it waits for (Android's leave to
/// install apps); "" while nothing has.
fn update_trouble() -> (String, Bool) {
  let how = update_how.get()
  match how.phase {
    "failed" => (@sf.t("android-misc.updates.failed", args=[("error", update_why())]), true)
    "allow" => (@sf.t("android-misc.updates.allowInstall", args=[("app", "still.fail")]), false)
    _ => ("", false)
  }
}

///|
/// One of what a newer build brings, whole, wrapping.
// kept across runs: a value (no field of it changes)
let update_news_line : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
/// What the dialog holds, in a column (8 apart); how the update goes, 8 more over it.
// kept across runs: a value (no field of it changes)
let update_body : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let update_going : @ui.Style = @ui.css("w=Full pt=S2 gap=S1_5")
