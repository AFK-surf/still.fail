// The app keeping itself current, for both frames (ember apps/android app/Updates.kt, Install.kt; the desktop app's
// appUpdate). What the person wants is the newest build, not to watch it come: a newer build is asked of the update
// source the app is given (`set_update_source`) as the app starts and each time it is shown again, and one found is
// handed to the host at once (@ui.update_fetch), which downloads it by itself and checks it (on a phone, on a network
// that is not metered): ready. The one thing that is the person's is when the app starts again as it: on Android the
// host puts it in place by itself once the app has been out of sight a while (the app opened next is the newer
// build), elsewhere as the app quits, or at once as the person says (@ui.update_apply: 重启更新, the desktop's sidebar
// key, ⌘K, 关于).
// So nothing about it is shown while it comes but in 关于 and the dialog; only what wants the person is shown where
// they are: a build ready where it is not put in by itself (the sidebar's key), the leave to install apps that
// Android wants (a card over the small screen's list: sfpages changelog.mbt update_card). How it stands is one thing
// for all that show it (update_now). Asked now (the menu bar's 检查更新…, 关于's version row, ⌘K), one dialog says it
// all as it goes (update_dialog, below): asking, none newer or why it could not ask, the newer build and what it
// brings, how it comes and what went wrong, in place. Hosts that do not update themselves (a version code of 0, or no
// source: iOS) never ask, and 关于 offers no check.
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
pub(all) enum UpdateSaid {
  Unsaid
  NoneNewer
  CouldNot(String)
} derive(Eq, Debug)

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
        update.available.set(Some(v))
        if now {
          update.said.set(Unsaid)
        }
        @hostapi.log("update: \{text(Some(v), "versionName")} (\{number(Some(v), "versionCode").to_int()}) is newer than this build (\{version})")
        update_fetch_found(v, false)
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
/// The build `v` (an AppRelease) by the name its file is downloaded as.
fn update_file_name(v : Json) -> String {
  let file = text(Some(v), "file")
  match file.rev_find("/") {
    Some(i) => file.view(start_offset=i + 1).to_owned()
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
      @ui.update_fetch((source.url)(file), text(Some(v), "sha256"), number(Some(v), "size"), update_file_name(v), now)
    }
    None => ()
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
/// install apps wanted, or one being put in place at their word (the sidebar's key, the small screen's card).
pub fn update_wants_you() -> Bool {
  match update_now() {
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
      @sf.t("android-misc.updates.httpStatus", args=[("status", e.view(start_offset=7).to_string())])
    e => e
  }
}

///|
/// How the update goes as the host tells it (@ui.update_state's JSON): its phase (idle, waiting, downloading,
/// retrying, ready, allow, installing, failed), how far (-1 not known), what went wrong, the build it is about (its
/// file's name), and whether one ready is put in place by itself while the app is out of sight.
priv struct UpdateHow {
  phase : String
  percent : Int
  error : String
  file : String
  away : Bool
} derive(Eq)

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
/// How this build's update stands, as 关于's version row says it (SettingsHome.kt Version): what pressing it does, the
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
      let size = number(Some(v), "size")
      (
        @sf.t("android-misc.updates.download", args=version(v)),
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
      let size = number(Some(v), "size")
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
        @sf.t(if away { "android-misc.updates.readyAway" } else { "android-misc.updates.readyQuit" }, args=[app]),
        false,
        None,
      )
    Allow(_) => (@sf.t("android-misc.updates.allow"), @sf.t("android-misc.updates.allowWhy", args=[app]), false, None)
    Installing(v) => (@sf.t("android-misc.updates.installingVersion", args=version(v)), "", true, None)
    Failed(v, why) => (@sf.t("android-misc.updates.retry", args=version(v)), why, false, None)
  }
  { label, note, going, part, ready: update_ready_version(), asks: update_asks() }
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
/// The dialog's title and the line under it: what it is about, this build's version under it (why it could not ask
/// in its place).
fn update_dialog_words() -> (String, String) {
  let current = @sf.t("web-pages.changelog.build", args=[("build", this_version().to_string())])
  match update_now() {
    Quiet | Checking => (@sf.t("android-misc.updates.checking"), current)
    Latest => (@sf.t("desktop.update.latest"), current)
    CouldNot(why) => (@sf.t("desktop.update.checkFailed"), why)
    Offered(v, ..) | Coming(v, _) | Ready(v, ..) | Allow(v) | Installing(v) | Failed(v, _) =>
      (@sf.t("desktop.update.available", args=[("version", text(Some(v), "versionName"))]), current)
  }
}

///|
/// How many of what a newer build brings the dialog says before 还有 n 项 (the changelog page has them all).
let update_news_most : Int = 5

///|
/// What the dialog holds: while still.fail cloud is asked, a bar going to and fro; for a newer build, what it brings
/// (its first few, 还有 n 项), then how it stands as 关于's row says it (update_stands: its line, a bar while it is under
/// way; what went wrong in red), each whole on its line: the bar there from the first, the dialog as tall all the way.
fn update_dialog_body(c : @ui.Ctx) -> Unit {
  match update_now() {
    Quiet | Checking =>
      c.box(style=update_body.then(@sf.panel_words_in()), fn() { @sf.progress(c, "update/asking", None) }) |> ignore
    Latest | CouldNot(_) => ()
    Offered(v, ..) | Coming(v, _) | Ready(v, ..) | Allow(v) | Installing(v) | Failed(v, _) as now => {
      let news : Array[String] = []
      for n in items(Some(v), "news") {
        if n is String(line) {
          news.push(line)
        }
      }
      let stands = update_stands()
      c.box(style=update_body.then(@sf.panel_words_in()), fn() {
        for i, line in news {
          if i >= update_news_most {
            c.text(@sf.t("android-settings.changelog.more", args=[("n", (news.length() - i).to_string())]), style=@sf.pg_note) |> ignore
            break
          }
          c.text(line, style=update_news_line) |> ignore
        }
        c.box(style=update_going, fn() {
          // (the bar coming and going with what is under way, what is under it moving with it: not in a frame)
          let open = @motion.anim(c, "update/bar", if stands.going { 1.0 } else { 0.0 })
          open.follow(
            if stands.going { 1.0 } else { 0.0 },
            @motion.move().per_unit(@motion.reveal_height("update/bar")),
          )
          let share = open.get()
          if stands.going || share > 0.0 {
            // (the room between it and the words under it its own: none left when it has gone)
            @motion.reveal(c, "update/bar", share, middle=true, fn() {
              c.box(style=update_bar_room, fn() { @sf.progress(c, "update/part", stands.part) }) |> ignore
            })
          }
          let said = match now {
            Coming(_, _) | Installing(_) => stands.label + (if stands.note == "" { "" } else { " · " + stands.note })
            _ => stands.note
          }
          if said != "" {
            c.text(said, style=if now is Failed(_, _) { @sf.pg_note_bad } else { @sf.pg_note }) |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    }
  }
}

///|
/// What the dialog's foot offers: 取消 while still.fail cloud is asked; 确定 where none is newer; 重试 where it could not
/// ask; for a newer build 稍后 (关闭 once it comes by itself) and what is the person's to do: 下载 (offered), 重启更新
/// (turning while it comes or is put in place), the leave to install apps, 重试 (failed).
fn update_dialog_foot(c : @ui.Ctx, src : Source, close : () -> Unit) -> Unit {
  match update_now() {
    Quiet | Checking =>
      if @sf.button(c, @sf.t("common.cancel"), key="update/cancel", tone=Ghost) {
        close()
      }
    Latest =>
      if @sf.button(c, @sf.t("common.confirm"), key="update/ok", tone=Primary) {
        close()
      }
    CouldNot(_) => {
      if @sf.button(c, @sf.t("common.cancel"), key="update/cancel", tone=Ghost) {
        close()
      }
      if @sf.button(c, @sf.t("common.retry"), key="update/retry", tone=Primary) {
        update_ask_now(src)
      }
    }
    now => {
      let going = now is (Coming(_, _) | Installing(_))
      if @sf.button(c, @sf.t(if going { "common.close" } else { "desktop.update.later" }), key="update/later", tone=Ghost) {
        close()
      }
      let label = match now {
        Offered(_, ..) => @sf.t("desktop.update.download")
        Allow(_) => @sf.t("android-misc.updates.allow")
        Failed(_, _) => @sf.t("common.retry")
        _ => @sf.t("desktop.update.restart")
      }
      if @sf.button(c, label, key="update/go", tone=Primary, busy=going) {
        update_go(src)
      }
    }
  }
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
