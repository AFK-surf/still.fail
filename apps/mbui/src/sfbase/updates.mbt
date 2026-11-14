// The app keeping itself current, for both frames (still.fail apps/android app/Updates.kt, Install.kt; the desktop app's
// appUpdate). What the person wants is the newest build, not to watch it come: a newer build is asked of the update
// source the app is given (`set_update_source`) as the app starts and each time it is shown again, and one found is
// handed to the host at once (@ui.update_fetch), which downloads it by itself and checks it (on a phone, on a network
// that is not metered): ready. The one thing that is the person's is when the app starts again as it: on Android the
// host puts it in place by itself once the app has been out of sight a while (the app opened next is the newer
// build), elsewhere as the app quits, or at once as the person says (@ui.update_apply: 重启更新, the desktop's sidebar
// key, ⌘K, 关于).
// The sidebar says how a build comes, then offers to restart where it is not put in by itself. On a small screen,
// what wants the person is the leave to install apps that Android wants (a card over the list: sfpages changelog.mbt
// update_card). How it stands is one thing
// for all that show it (update_now). Asked now (the menu bar's 检查更新…, 关于's version row, ⌘K), one dialog says it
// all as it goes (update_dialog, below): asking, none newer or why it could not ask, the newer build and what it
// brings, how it comes and what went wrong, in place. Hosts that do not update themselves (a version code of 0, or no
// source: iOS) never ask, and 关于 offers no check.
//
// Where a build comes from is the source's: `cloud_updates(feed)` is still.fail cloud's (the core's `app.update`, at
// most hourly unless asked now: /releases/<feed>/latest.json, an AppRelease; its `file` under /releases/). No source
// is given by default: src/stillfail gives the cloud's for MBUI_UPDATE_FEED=<feed> (the local cloud's in e2e). A
// source of a release elsewhere answers the same AppRelease (versionCode, versionName, file: a path under the source's
// releases or a whole https URL, sha256, size, news) and may say a delta from this build (`delta`, the core's pick of the
// feed's): handed to the host beside the build, which makes the build of it and downloads it whole if that fails, and
// what the app says is downloaded is the delta's size, since that is what comes.
//
// A person wants the latest version; checking and fetching are not their business (the user, 2026-10-31: 「从第一性
// 原理出发」).

///|
/// As at the start (the app's reset).
pub fn update_reset() -> Unit {
  match update_follow_stop.val {
    Some(stop) => stop()
    None => ()
  }
  update_follow_stop.val = None
  update_pending.set(None)
  update.available.set(None)
  update.asked = false
  update_again_n.val = 0
  update_told.val = -1
  update.checking.set(false)
  update.source = None
  update.said.set(Unsaid)
  update.dialog = 0
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
/// What the last check asked now answered, where it found no newer build: nothing yet (or a newer one), none newer, or
/// why it could not ask.
#derive(Eq, Debug)
pub(all) enum UpdateSaid {
  Unsaid
  NoneNewer
  CouldNot(String)
}

///|
/// How an update stands: the newer build found, the person's check under way, what the last check asked now
/// answered, each a signal (what shows them follows them as they change, as the host's word of how it goes is
/// followed: update_how); whether it was asked at the start, the source, the update dialog (its presenter's serial, 0
/// none yet).
pub(all) struct Update {
  available : @signals.Signal[Json?]
  mut asked : Bool
  checking : @signals.Signal[Bool]
  mut source : UpdateSource?
  said : @signals.Signal[UpdateSaid]
  mut dialog : Int
}

///|
// kept across runs: put back by update_reset
pub let update : Update = {
  available: @signals.signal(None),
  asked: false,
  checking: @signals.signal(false, same=fn(a, b) { a == b }),
  source: None,
  said: @signals.signal(Unsaid, same=fn(a, b) { a == b }),
  dialog: 0,
}

///|
/// This build's version code as tests have it (0: the host's).
pub let update_version : Ref[Int] = Ref(0)

///|
/// A newer build heard of while the host is still downloading another. The current build stays visible until that
/// download ends; then the latest one is handed to the host. The source owns the effect that follows the host.
// kept across runs: put back by update_reset
let update_pending : @signals.Signal[Json?] = @signals.signal(None)

///|
// kept across runs: stopped and put back by update_reset
let update_follow_stop : Ref[(() -> Unit)?] = Ref(None)

///|
/// The source newer builds are asked of (none: the app never asks).
pub fn set_update_source(s : UpdateSource?) -> Unit {
  match update_follow_stop.val {
    Some(stop) => stop()
    None => ()
  }
  update_follow_stop.val = None
  update.source = s
  if s is Some(_) {
    update_follow_stop.val = Some(@signals.effect(fn() {
      match update_pending.get() {
        Some(v) => {
          let how = update_how.get()
          if how.phase != "downloading" && how.phase != "retrying" {
            update_pending.set(None)
            update.available.set(Some(v))
            update_fetch_found(v, false)
          }
        }
        None => ()
      }
    }))
  }
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
        .map(fn(k) { k.trim().to_owned() })
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
  update.source is Some(_) && this_version() > 0
}

///|
/// Asks the source for a newer build; `done` gets what to say when it was asked now (none newer, or why it failed),
/// "" otherwise. Asked now, what it answered is kept (`update.said`) for the dialog; where it cannot be asked, why. A
/// newer build found is handed to the host to be made ready (update_fetch_found): each time, so one that failed is
/// tried again as the app is shown again (the host takes one it has, or has coming, as asked already).
pub fn update_check(src : Source, now : Bool, done? : (String) -> Unit = fn(_) {  }) -> Unit {
  let version = this_version()
  let source = match update.source {
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
        if now {
          update.said.set(Unsaid)
        }
        @hostapi.log("update: \{text(Some(v), "versionName")} (\{number(Some(v), "versionCode").to_int()}) is newer than this build (\{version})")
        let how = update_how.get()
        let pending = update_pending.get()
        if pending is Some(p) && number(Some(p), "versionCode") > number(Some(v), "versionCode") {
          // A slower check answered with an older build than the one already waiting.
          ()
        } else if (how.phase == "downloading" || how.phase == "retrying") && how.file != update_file_name(v) {
          // Hosts take one download at a time. Keep showing the one in flight and give them the newest after it ends
          // (自动更新 off: the person's next word takes it).
          if update_auto(src) {
            update_pending.set(Some(v))
          }
        } else if !update_auto(src) {
          // 自动更新 off: the newer build said, downloaded only at the person's word (update_go)
          update_pending.set(None)
          update.available.set(Some(v))
        } else {
          update_pending.set(None)
          update.available.set(Some(v))
          update_fetch_found(v, false)
        }
        done("")
      }
      Ok(_) => {
        update_pending.set(None)
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
/// Whether newer builds are downloaded by themselves here (the prefs' `appUpdate`: 自动更新, on unless turned off),
/// else only at the person's word.
pub fn update_auto(src : Source) -> Bool {
  text(src.topic("prefs", {}).get().value, "appUpdate") != "off"
}

///|
/// 自动更新 turned on (关于; the prefs keep it): the newer build known and not asked for yet handed to the host as one
/// found by itself is.
pub fn update_auto_on() -> Unit {
  match update_known() {
    Offered(v, waiting=false) => update_fetch_found(v, false)
    _ => ()
  }
}

///|
/// The build `v` (an AppRelease) by the name its file is downloaded as.
fn update_file_name(v : Json) -> String {
  let file = text(Some(v), "file")
  match file.rev_find("/") {
    Some(i) => file.exact_view(start=i + 1).to_owned()
    None => file
  }
}

///|
/// The newer build `v` handed to the host to be downloaded and made ready (@ui.update_fetch): `now`, the person's word,
/// at once on any network.
fn update_fetch_found(v : Json, now : Bool) -> Unit {
  match update.source {
    Some(source) => {
      let file = text(Some(v), "file")
      let delta = match update_delta(v) {
        Some(d) =>
          Json::object({
            "url": Json::string((source.url)(text(Some(d), "file"))),
            "sha256": Json::string(text(Some(d), "sha256")),
            "size": Json::number(number(Some(d), "size")),
            "makes_sha256": Json::string(text(Some(d), "makesSha256")),
            "makes_size": Json::number(number(Some(d), "makesSize")),
          }).stringify()
        None => ""
      }
      @ui.update_fetch(
        (source.url)(file),
        text(Some(v), "sha256"),
        number(Some(v), "size"),
        update_file_name(v),
        now,
        delta,
      )
    }
    None => ()
  }
}

///|
/// The delta from this build the build `v` (an AppRelease) comes with, none where it has none.
fn update_delta(v : Json) -> Json? {
  match v {
    Object(o) =>
      match o.get("delta") {
        Some(Object(_) as d) => Some(d)
        _ => None
      }
    _ => None
  }
}

///|
/// How many bytes the build `v` downloads: its delta's where it comes with one, else its package's.
fn update_size(v : Json) -> Double {
  match update_delta(v) {
    Some(d) => number(Some(d), "size")
    None => number(Some(v), "size")
  }
}

///|
/// How the newer build stands, one thing for all that show it: none known (nothing to say; or, the person's check,
/// under way, none newer, why it could not ask), and for a newer build (`v`): offered (waiting for a network that is
/// not metered: `waiting`; or not asked yet), coming (how far, 0 to 1, where the host says), ready (put in place by itself while
/// the app is out of sight where `away`), the person's leave to install apps wanted, being put in place, failed (why).
pub(all) enum UpdateNow {
  Quiet
  Checking
  Latest
  CouldNot(String)
  Offered(Json, waiting~ : Bool)
  Coming(Json, Double?)
  Ready(Json, away~ : Bool)
  Allow(Json)
  Installing(Json)
  Failed(Json, String)
}

///|
/// How the update stands (update_now's), as the host says how its build goes (update_how) for the newer build known.
pub fn update_now() -> UpdateNow {
  // (the person's check first, whatever is known: what they asked for is the newest there is)
  if update.checking.get() {
    Checking
  } else {
    update_known()
  }
}

///|
/// How the newer build known stands, the person's check aside.
fn update_known() -> UpdateNow {
  match update.available.get() {
    Some(v) => {
      let how = update_how.get()
      if how.file != update_file_name(v) {
        return Offered(v, waiting=false)
      }
      match how.phase {
        "downloading" | "retrying" =>
          Coming(v, if how.percent >= 0 { Some(how.percent.to_double() / 100.0) } else { None })
        "ready" => Ready(v, away=how.away)
        "allow" => Allow(v)
        "installing" => Installing(v)
        "failed" => Failed(v, update_error(how.error))
        "waiting" => Offered(v, waiting=true)
        _ => Offered(v, waiting=false)
      }
    }
    None =>
      match update.said.get() {
        NoneNewer => Latest
        CouldNot(why) => CouldNot(why)
        Unsaid => Quiet
      }
  }
}

///|
/// Whether the update wants the person where they are: a build ready that is not put in place by itself, the leave to
/// install apps wanted, or one being put in place at their word (the sidebar's key, the small screen's card); also while
/// the person's word asks still.fail cloud first (update_go): what they pressed stays, under way, not gone until it answers.
pub fn update_wants_you() -> Bool {
  match update_known() {
    Ready(_, away~) => !away
    Allow(_) | Installing(_) => true
    _ => false
  }
}

///|
/// What the person's word does, wherever they give it: still.fail cloud asked now first (what they asked for is the
/// newest there is, not one heard of a while ago: 2026-10-02 the user, 「更新的不是最新而是当时检查出来的版本」), then a
/// build offered, or one that failed, downloaded now (on any network); one ready put in place now (the app starts
/// again as it; on Android, it ends, the newer build's notification opening it), the system's page for the leave to
/// install apps first where it is wanted. A newer one found meanwhile is the one downloaded. Where it could not ask, what
/// is known is gone on with.
pub fn update_go(src : Source) -> Unit {
  if update.checking.get() {
    return
  }
  update.checking.set(true)
  update_check(src, true, done=fn(_) {
    update.checking.set(false)
    match update_now() {
      Offered(v, ..) | Failed(v, _) => update_fetch_found(v, true)
      Ready(v, ..) | Allow(v) =>
        @ui.update_apply(
          @sf.t("android-misc.updates.updated", args=[("app", "still.fail"), ("version", text(Some(v), "versionName"))]),
        )
      _ => ()
    }
  })
}

///|
/// What went wrong with an update as the host said it, in the words Android's Updates.kt says it in: a download cut
/// short, the download's answer ("status 404", as Updates.java says it: 下载返回 404), else as said.
pub fn update_error(e : String) -> String {
  match e {
    "incomplete" => @sf.t("android-misc.updates.incomplete")
    e if e.has_prefix("status ") =>
      @sf.t("android-misc.updates.httpStatus", args=[("status", e.exact_view(start=7).to_owned())])
    e => e
  }
}

///|
/// How the update goes as the host tells it (@ui.update_state's JSON): its phase (idle, waiting, downloading,
/// retrying, ready, allow, installing, failed), how far (-1 not known), what went wrong, the build it is about (its
/// file's name), and whether one ready is put in place by itself while the app is out of sight.
#derive(Eq)
priv struct UpdateHow {
  phase : String
  percent : Int
  error : String
  file : String
  away : Bool
}

///|
/// How the update goes, worked out of the host's word as that changes (a computed of @ui.update_state, a signal the
/// host's events set): what shows it reads it here and follows it, never a copy one reader refreshed (2026-10-27: the
/// small screen's update row read such a copy, which said idle while the host downloaded). Nothing told (a Tester, a
/// host that does not update itself): idle.
// kept across runs: worked out of a signal the Tester puts back
let update_how : @signals.Computed[UpdateHow] = @signals.computed(
  fn(_) {
    let v = try Some(@json.parse(@ui.update_state())) catch { _ => None }
    match v {
      Some(_) =>
        {
          phase: text(v, "phase"),
          percent: number(v, "percent").to_int(),
          error: text(v, "error"),
          file: text(v, "file"),
          away: flag(v, "away"),
        }
      None => { phase: "idle", percent: -1, error: "", file: "", away: false }
    }
  },
  same=fn(a, b) { a == b },
)

///|
/// Asked once the app is signed in (MainActivity's check at the start).
pub fn update_first(src : Source) -> Unit {
  if !update.asked {
    update.asked = true
    update_check(src, false)
  }
}

///|
/// How long the app, left open, waits before asking for a newer build again. A window never put away on a Mac that
/// never sleeps is never shown again: asked only as it started (right after the machine did, before the network was
/// up), it stayed three days on a build 400 behind (2026-11-07). The core asks the feed at most every 5 minutes.
pub let update_again_ms : Double = 60.0 * 60.0 * 1000.0

///|
// kept across runs: put back by update_reset
let update_again_n : Ref[Int] = Ref(0)

///|
/// Asked again each update_again_ms the app stays signed in, in every frame (signed_in_frame, beside update_first): as
/// a check as it is shown again, nothing said unless a newer build is found.
pub fn update_again(c : @ui.Ctx, src : Source) -> Unit {
  let n = update_again_n.val
  if @kit.after(c, "update-again/\{n}", true, update_again_ms, later=true) {
    update_again_n.val = n + 1
    c.tell("update-again", fn() { update_check(src, false) })
  }
}

///|
/// How this build's update stands, as 关于's version row says it: what pressing it does, the
/// line under it, how far (a bar while something is under way: None, a piece sweeping across), whether it is under way,
/// and whether newer builds are asked for here at all.
pub fn update_stands() -> @settings.VersionNow {
  match update_now() {
    // the person's check of a build known: said as that build stands, what is under way under it (正在检查最新版本,
    // the bar sweeping), not in other words for the while it takes
    Checking if update.available.get() is Some(_) => {
      let under = update_stands_of(update_known())
      { ..under, note: @sf.t("android-misc.updates.checking"), going: true, part: None }
    }
    now => update_stands_of(now)
  }
}

///|
/// How `now` stands, as 关于's version row says it (update_stands).
fn update_stands_of(now : UpdateNow) -> @settings.VersionNow {
  let version = fn(v : Json) { [("version", text(Some(v), "versionName"))] }
  let app = ("app", "still.fail")
  let check = @sf.t("android-settings.version.check")
  let (label, note, going, part) = match now {
    Quiet | Latest | CouldNot(_) => (check, "", false, None)
    Checking => (check, @sf.t("android-settings.version.checking"), true, None)
    Offered(v, waiting~) => {
      let size = update_size(v)
      (
        // (the first of the update's three stages, 有新版本, 正在下载, 重启以更新到: 2026-11-03 the user, 「所有能看到更新的
        // 地方，一定要有三个阶段」; pressed, downloaded now)
        @sf.t("desktop.update.available", args=version(v)),
        // (its size, what it waits for: a line under it from the first, the row as tall as it goes on)
        if size <= 0.0 {
          ""
        } else if waiting {
          @sf.t("android-misc.updates.waitWifi", args=[("size", @sf.file_size(size))])
        } else {
          @sf.file_size(size)
        },
        false,
        None,
      )
    }
    Coming(v, part) => {
      // (how far and how big, or that it goes on once the network is back: a line there all the way it comes, the
      // row as tall)
      let size = update_size(v)
      let said = [
        match part {
          Some(p) => "\{(p * 100.0).floor().to_int()}%"
          None => ""
        },
        if size > 0.0 {
          @sf.file_size(size)
        } else {
          ""
        },
      ].filter(fn(w) { w != "" })
      (
        @sf.t("android-misc.updates.downloadingVersion", args=version(v)),
        if update_how.get().phase == "retrying" {
          @sf.t("android-misc.updates.retrying")
        } else if said.is_empty() {
          @sf.t("android-misc.updates.downloading")
        } else {
          said.join(" · ")
        },
        true,
        part,
      )
    }
    Ready(v, away~) =>
      (
        @sf.t("android-misc.updates.ready", args=version(v)),
        // (which build is downloaded, from this one to it: 2026-11-03 the user, 「让用户知道已经有一个什么版本下载了，从哪个
        // 升级到哪个」)
        @sf.t(if away { "android-misc.updates.readyAway" } else { "android-misc.updates.readyQuit" }, args=[
          ("from", "0.1.\{this_version()}"),
          ("to", text(Some(v), "versionName")),
          app,
        ]),
        false,
        None,
      )
    Allow(_) => (@sf.t("android-misc.updates.allow"), @sf.t("android-misc.updates.allowWhy", args=[app]), false, None)
    Installing(v) => (@sf.t("android-misc.updates.installingVersion", args=version(v)), "", true, None)
    Failed(v, why) => (@sf.t("android-misc.updates.retry", args=version(v)), why, false, None)
  }
  let newer = now is (Offered(_, ..) | Coming(_, _) | Ready(_, ..) | Allow(_) | Installing(_) | Failed(_, _))
  { newer, label, note, going, part, ready: update_ready_version(), asks: update_asks() }
}

///|
/// The newer build's version where one is ready for the person's word (or wants their leave): "" otherwise.
fn update_ready_version() -> String {
  match update_now() {
    Ready(v, ..) | Allow(v) => text(Some(v), "versionName")
    _ => ""
  }
}

///|
/// The version row pressed: what is the person's to do done (update_go: downloaded now, put in place now), else the
/// dialog opened, saying how it goes (with none known, still.fail cloud asked now).
pub fn update_row_tapped(src : Source) -> Unit {
  match update_now() {
    Offered(_, ..) | Failed(_, _) | Ready(_, ..) | Allow(_) => update_go(src)
    _ => update_dialog(src)
  }
}

///|
/// 检查更新 chosen in the menu bar (menu_bar.mbt), as the desktop app's checkFromMenu: the dialog over what is open,
/// still.fail cloud asked now unless a newer build is known already.
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
/// newer build is known; then, as it goes, what it answered (none newer, why it could not ask: 重试), the newer build
/// and what it brings, how it comes and what the person can do (download it now, 重启更新, the leave to install apps,
/// try again). Open already, it stays the one.
pub fn update_dialog(src : Source) -> Unit {
  if update.available.get() is None && !update.checking.get() {
    update_ask_now(src)
  }
  if update_dialog_open() {
    return
  }
  let (title, lead) = update_dialog_words()
  @sf.panel_nodes(
    title,
    fn(v, _) { update_dialog_body(v) },
    from=Unanchored,
    description=lead,
    live=fn() {
      let (title, lead) = update_dialog_words()
      (title, "", lead)
    },
    foot=fn(v, close) { update_dialog_foot(v, src, close) },
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
/// The dialog's title and the line under it: what it is about, this build's version under it (why it could not ask
/// in its place).
fn update_dialog_words() -> (String, String) {
  let current = @sf.t("web-pages.changelog.build", args=[("build", this_version().to_string())])
  match update_dialog_now() {
    Quiet | Checking => (@sf.t("android-misc.updates.checking"), current)
    Latest => (@sf.t("desktop.update.latest"), current)
    CouldNot(why) => (@sf.t("desktop.update.checkFailed"), why)
    Offered(v, ..) | Coming(v, _) | Ready(v, ..) | Allow(v) | Installing(v) | Failed(v, _) =>
      (@sf.t("desktop.update.available", args=[("version", text(Some(v), "versionName"))]), current)
  }
}

///|
/// How the update stands as the dialog shows it: the person's check of a build known said as that build stands (its
/// title, what it brings, its bar), the check only in the line under the bar (update_stands), not in a dialog of
/// other words for the while it takes: the dialog as tall all the way.
fn update_dialog_now() -> UpdateNow {
  match update_now() {
    Checking if update.available.get() is Some(_) => update_known()
    now => now
  }
}

///|
/// How many of what a newer build brings the dialog says before 还有 n 项 (the changelog page has them all).
let update_news_most : Int = 5

///|
/// What the dialog holds, as it shows it: asking still.fail cloud, nothing more to say (none newer, or why it could not
/// ask: its title and the line under it say it), or a newer build (update_dialog_body).
#derive(Eq)
priv enum UpdateHolds {
  Asking
  Said
  Newer
}

///|
fn update_holds() -> UpdateHolds {
  match update_dialog_now() {
    Quiet | Checking => Asking
    Latest | CouldNot(_) => Said
    _ => Newer
  }
}

///|
/// What the dialog holds, in node `v` (its body's), made once as it opens: while still.fail cloud is asked, a bar going
/// to and fro; for a newer build, what it brings (its first few, 还有 n 项), then how it stands as 关于's row says it
/// (update_stands: its line; what went wrong in red) under its bar, each whole on its line, bound to how it stands: the
/// bar there in every stage (empty offered, full ready, how far while it comes, sweeping while it is under way unknown
/// how far), the dialog as tall all the way (2026-11-06 the user, 「这玩意儿为啥老抖动」「高度抖动」: the bar came and went
/// with each stage, the dialog shorter and taller again).
fn update_dialog_body(v : @view.View) -> Unit {
  // (none newer, or why it could not ask: nothing, its title and the line under it straight over its foot as the old
  // body's, the panel's body none of its room; asking, or a newer build, one in the other's place)
  v.show(fn() { update_holds() != Said }, fn(s) {
    s.pick(fn() { update_holds() == Newer }, fn(b, newer) {
      if newer {
        update_newer_node(b)
      } else {
        b.box(fn(col) {
          @sf.style_node(col, fn() { update_body.then(@sf.panel_words_in_node(col)) })
          update_bar(col, fn() { None })
        })
        |> ignore
      }
    })
  })
}

///|
/// A newer build in the dialog, in node `v`: what it brings, its bar and how it stands under it.
fn update_newer_node(v : @view.View) -> Unit {
  let now = fn() { update_dialog_now() }
  let news = fn() -> Array[String] {
    let out : Array[String] = []
    match now() {
      Offered(v, ..) | Coming(v, _) | Ready(v, ..) | Allow(v) | Installing(v) | Failed(v, _) =>
        for n in items(Some(v), "news") {
          if n is String(line) {
            out.push(line)
          }
        }
      _ => ()
    }
    out
  }
  v.box(fn(col) {
    @sf.style_node(col, fn() { update_body.then(@sf.panel_words_in_node(col)) })
    // (its first few, by where they stand)
    col.each(
      fn() {
        let all = news()
        all.mapi(fn(i, line) { (i, line) }).filter(fn(x) { x.0 < update_news_most })
      },
      fn(x) { x.0 },
      fn(row, x) { @sf.words_node(row, fn() { x.get().1 }, fn() { update_news_line }) |> ignore },
    )
    col.show(fn() { news().length() > update_news_most }, fn(more) {
      @sf.words_node(
        more,
        fn() { @sf.t("android-settings.changelog.more", args=[("n", (news().length() - update_news_most).to_string())]) },
        fn() { @sf.pg_note },
      )
      |> ignore
    })
    col.box(fn(going) {
      @sf.style_node(going, fn() { update_going })
      let part = fn() {
        let stands = update_stands()
        if stands.going {
          stands.part
        } else if now() is (Ready(_, ..) | Allow(_)) {
          Some(1.0)
        } else {
          Some(0.0)
        }
      }
      going.box(fn(room) {
        @sf.style_node(room, fn() { update_bar_room })
        update_bar(room, part)
      })
      |> ignore
      let said = fn() {
        let stands = update_stands()
        match now() {
          Coming(_, _) | Installing(_) => stands.label + (if stands.note == "" { "" } else { " · " + stands.note })
          _ => stands.note
        }
      }
      going.show(fn() { said() != "" }, fn(w) {
        @sf.words_node(w, said, fn() { if now() is Failed(_, _) { @sf.pg_note_bad } else { @sf.pg_note } }) |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The dialog's bar in `parent`, as wide as it, how far `part` says (None: sweeping), in the accent on the line's ink
/// (@sf.progress's).
fn update_bar(parent : @view.View, part : () -> Double?) -> Unit {
  @sf.progress_node(parent, part, fn() { @ui.tree_theme().line }, fn() { @sf.theme().p.accent }) |> ignore
}

///|
/// What the dialog's foot offers, in node `v` (its foot's), bound to how the update stands: 取消 while still.fail cloud
/// is asked; 确定 where none is newer; 重试 where it could not ask; for a newer build 稍后 (关闭 once it comes by itself)
/// and what is the person's to do: 下载 (offered), 重启更新 (turning while it comes or is put in place), the leave to
/// install apps, 重试 (failed).
fn update_dialog_foot(v : @view.View, src : Source, close : () -> Unit) -> Unit {
  let now = fn() { update_dialog_now() }
  let going = fn() { now() is (Coming(_, _) | Installing(_)) }
  // (none newer: its 确定 alone; each a place of the foot's, its share of a sheet's foot as a button standing there)
  @sf.foot_place_node(v, fn() { !(now() is Latest) }, fn(b) {
    @sf.button_node(
      b,
      fn() {
        match now() {
          Quiet | Checking | CouldNot(_) => @sf.t("common.cancel")
          _ => @sf.t(if going() { "common.close" } else { "desktop.update.later" })
        }
      },
      close,
      tone=Ghost,
    )
    |> ignore
  })
  // (still.fail cloud asked: its 取消 alone)
  @sf.foot_place_node(v, fn() { !(now() is (Quiet | Checking)) }, fn(b) {
    @sf.button_node(
      b,
      fn() {
        match now() {
          Latest => @sf.t("common.confirm")
          CouldNot(_) | Failed(_, _) => @sf.t("common.retry")
          Offered(_, ..) => @sf.t("desktop.update.download")
          Allow(_) => @sf.t("android-misc.updates.allow")
          _ => @sf.t("desktop.update.restart")
        }
      },
      fn() {
        match @signals.untracked(now) {
          Latest => close()
          CouldNot(_) => update_ask_now(src)
          _ => update_go(src)
        }
      },
      tone=Primary,
      // (the person's check under way: the key turning, as it does while the build comes)
      busy=fn() { !(now() is (Latest | CouldNot(_))) && (going() || update.checking.get()) },
    )
    |> ignore
  })
}

///|
/// One of what a newer build brings, whole, wrapping.
// kept across runs: a value (no field of it changes)
let update_news_line : @ui.TextStyle = @sf.body.then(@sf.full_words)

///|
/// What the dialog holds, in a column (8 apart); how the update goes, 8 more over it, the bar and the words under it 6
/// apart.
// kept across runs: a value (no field of it changes)
let update_body : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let update_going : @ui.Style = @ui.css("w=Full pt=S2")

///|
/// The bar's room: 6 under it, over the words.
// kept across runs: a value (no field of it changes)
let update_bar_room : @ui.Style = @ui.css("w=Full pb=S1_5")

///|
/// The core's word that a newer build may be out (the `releases` topic's `told`) as last heard (-1: none yet).
// kept across runs: put back by update_reset
let update_told : Ref[Int] = Ref(-1)

///|
/// Asked again each time the core says a newer build may be out (still.fail cloud said a release is out, or its socket
/// opened again), in every frame beside update_first: the build got ready is the newest, not one heard of before (one
/// put in as the app quits or while it is away, then another as the newer one asks: 2026-11-09, pengxiao, 「不会用最新
/// 的版本，而是会连续更新好几次」).
pub fn update_on_release(c : @ui.Ctx, src : Source) -> Unit {
  if !update_asks() {
    return
  }
  let v = src.topic("releases", {}).get().value
  if v is None {
    return
  }
  let told = count(v, "told")
  if told != update_told.val {
    c.tell("update-release", fn() {
      let first = update_told.val < 0
      update_told.val = told
      if !first {
        update_check(src, false)
      }
    })
  }
}

///|
/// The app's newer build as a row of a list of updates, the stations' beside it (sfpages station_updates.mbt: one
/// dialog for both where both wait, the user, 2026-11-14 「带 app 更新呢？」): None while none is to be shown there; else
/// what its row says under the app's name, as 关于's row says it (有新版本 0.1.1 · its size, 正在下载 … · 40%, 重启以更新到
/// …), how far while it comes, and what its press says ("": nothing to press, under way). Pressed: update_go.
pub fn update_as_row() -> (String, Double??, String)? {
  let said = fn() {
    let s = update_stands()
    if s.note == "" {
      s.label
    } else {
      s.label + " · " + s.note
    }
  }
  match update_now() {
    Offered(_, ..) | Failed(_, _) => Some((said(), None, @sf.t("web-main.versions.update")))
    Coming(_, part) => Some((said(), Some(part), ""))
    Ready(_, away~) if !away => Some((said(), None, @sf.t("desktop.update.restart")))
    Ready(_, ..) => Some((said(), None, ""))
    Allow(_) => Some((said(), None, @sf.t("web-main.versions.update")))
    Installing(_) => Some((said(), None, ""))
    _ => None
  }
}
