// The phone's offers of a newer build (ember apps/android app/Updates.kt; Home.kt's update button, SettingsHome.kt
// Version): Home offers a build that brings something the changelog says (a download key with its dot; how far while
// it downloads), the settings' version row any (更新到 …; 检查更新 asks now, 已是最新 said when none). How an update
// stands, and where a build comes from, are both frames' (sfbase updates.mbt).

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
  fill(key, args)
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
        update_say(said)
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
