// What the app does each frame and between frames whichever frame draws it (the phone's, the desktop's): its light
// or dark and language as the prefs say, where its attention is (told the core), the system's say (a link it was
// opened with, back on screen, the menu bar's items, the network), the number on its icon.

///|
/// Light or dark, as this device is set (the prefs' `appearance`, Appearance.kt), or as the system is (@hostapi.system_dark)
/// when it follows it; the host told when it changes (its bars follow, or are as dark as the frame's page says:
/// `page_dark`).
pub fn appearance(src : Source, page_dark : Bool?) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  // the words' language too, the core's (its `lang`: as chosen, else the device's), I18n.kt's follow
  @sf.set_language(if prefs is Some(_) { Some(text(prefs, "lang")) } else { None })
  // motion as this device is set (the prefs' `motion`: reduce, full), else as the system's
  @ui.set_motion_chosen(match text(prefs, "motion") {
    "reduce" => Some(true)
    "full" => Some(false)
    _ => None
  })
  let dark = @settings.dark(prefs, @ui.system_dark())
  @sf.set_dark(Some(dark))
  // (the host told once the prefs are read: not the system's first, then the one chosen)
  if prefs is Some(_) && told_dark.val != Some(dark) {
    told_dark.val = Some(dark)
    // (said on the log for scripted runs: e2e/flows checks the theme was taken)
    @hostapi.log(if dark { "theme: dark" } else { "theme: light" })
  }
  // the system bars follow the page under them: the player's and a picture's or a video's in the viewer are dark
  // whatever the theme, a reader's as dark as its paper
  let bars = match page_dark {
    Some(d) => d
    None => dark
  }
  // (told once the frame's builds are over, as the last saw the page)
  if prefs is Some(_) && told_bars.val != Some(bars) {
    @ui.current().after_build("bars", fn() {
      if told_bars.val != Some(bars) {
        told_bars.val = Some(bars)
        @hostapi.set_dark(bars)
      }
    })
  }
}

///|
let told_bars : Ref[Bool?] = Ref(None)

///|
let told_dark : Ref[Bool?] = Ref(None)

///|
/// What this app last told the core of its attention (`client.focus`): shown, in front, the workspace in view, whether
/// its new chat is the page shown; and where to tell it again when the system says the app left the front between
/// frames.
priv struct Attention {
  // (plain: what the core was last told, compared before it is told again; nothing shown reads it)
  mut told : Bool
  mut visible : Bool
  mut focused : Bool
  mut workspace : String
  mut new_chat : Bool
  mut src : Source?
}

///|
let attention : Attention = {
  told: false,
  visible: false,
  focused: false,
  workspace: "",
  new_chat: false,
  src: None,
}

///|
/// Tells the core where this app's attention is, as the Android app's activity and App.kt do: shown and in front or
/// not (`client.focus {visible, focused}`, as the system says: @ui.app_visible, app_focused) and the workspace in view
/// (`workspace`); a chat's own place (`chat`, `left`) is chat.mbt's. Only a change is told. What is read follows from
/// it: the core marks a chat read only while a page in view (visible) shows its end, and shows no notice of a chat
/// one in front shows. `new_chat`: the page on top is the workspace's new chat (`newChat`), which the core keeps as
/// what the workspace goes back to (the wide frame lands on it as the app opens again: sfdesk's frame.mbt land) in
/// place of the chat shown before it.
pub fn attend(src : Source, workspace : String, new_chat : Bool) -> Unit {
  if attention.src is None {
    // the system's say between frames (Android's activity pausing: no frame comes after it)
    @ui.on_app_change(fn(_, _) {
      match attention.src {
        Some(s) => {
          attend(s, attention.workspace, attention.new_chat)
          // what lives only while shown let go as the app goes behind (the screens live in their cards: ScreenLinks.kt
          // Peek, under STARTED)
          if !@ui.app_visible() {
            (shell.val.behind)(s)
          }
        }
        None => ()
      }
      notices_app_change(@ui.app_visible(), @ui.app_awake())
    })
  }
  attention.src = Some(src)
  let visible = @ui.app_visible()
  let focused = @ui.app_focused()
  if attention.told &&
    visible == attention.visible &&
    focused == attention.focused &&
    workspace == attention.workspace &&
    new_chat == attention.new_chat {
    return
  }
  attention.told = true
  attention.visible = visible
  attention.focused = focused
  attention.workspace = workspace
  attention.new_chat = new_chat
  let params : Map[String, Json] = {
    "visible": Json::boolean(visible),
    "focused": Json::boolean(focused),
    "workspace": Json::string(workspace),
  }
  if new_chat {
    params["newChat"] = Json::string(workspace)
  }
  (src.call)("client.focus", Json::object(params), fn(_) {  })
}

///|
/// What was chosen in the system's own bars (@hostapi.nav_bar) since the wide frame last took it, oldest first.
pub let nav_tapped : Array[String] = []

///|
/// What the system said between frames (@hostapi.system_channel; its handler set as the package starts, before the first
/// frame takes what came with the app's start), to the core: back on screen after `away` ms off it, the
/// core gives up requests that went out before and reconnects links gone quiet (MainActivity.kt wake: `client.wake
/// {away}`, client/core-ts src/wake.ts), and a newer build is asked for again (onStart's checkUpdates); the default
/// network changed, every link it had is taken for dead (NetworkWatch: `client.wake {away: 0, network: true}`).
fn system_said(json : String) -> Unit {
  let said = @hostapi.system_said(json)
  for s in said {
    match s {
      // a link the system opened the app with (links.mbt): opened once the app can (signed in, its workspace known)
      Link(url) => link_later.push(app_link(url))
      // shown over another app, or in its own window again (share.mbt)
      Over(over) => share_over.val = over
      // a tab or an item of the system's own bars chosen (sfdesk's rail_native.mbt takes it as it draws)
      NavTapped(id) => nav_tapped.push(id)
      // (how far the bars reach in over the view: mbui keeps it, @ui.system_bars, bars.mbt)
      _ => ()
    }
  }
  let src = match attention.src {
    Some(s) => s
    None => return
  }
  if src.read_only {
    return
  }
  for s in said {
    match s {
      Shown(away~) => {
        (src.call)("client.wake", { "away": Json::number(away) }, fn(_) {  })
        update_check(src, false)
      }
      // 检查更新 from the menu bar (menu_bar.mbt)
      Menu("update.check") => update_from_menu(src)
      // one of the pages' actions from the menu bar: as its keys pressed (keymap.mbt action_pressed)
      Menu(action) => @settings.ask_action(action)
      // a package handed to the system's installer could not be installed (FilePreview.kt install's toast)
      InstallAllow(..) => toast_later(@sf.t("android-chat.file.allowInstall", args=[("app", "still.fail")]))
      InstallFailed(error~, ..) => toast_later(@sf.t("android-chat.file.installFailed", args=[("error", error)]))
      Network =>
        (src.call)(
          "client.wake",
          { "away": Json::number(0.0), "network": Json::boolean(true) },
          fn(_) {  },
        )
      _ => ()
    }
  }
}

///|
/// The system's say has its handler before the first frame (what is posted as the app starts, a link it was opened
/// with, would be left with none).
fn init {
  @ui.on_message(@hostapi.system_channel, fn(json, _) { system_said(json) })
  // what the phone has for 共享调试, as its host says by itself (the app's Android: AdbShare.java)
  @ui.on_message("native:adb.phone", fn(json, _) { @settings.adb_phone_said(json) })
  // its notifications' words, for a share a chat's grant starts with no page shown (AdbShare.java `adb.texts`)
  @ui.native_call("adb.texts", @settings.adb_texts()) |> ignore
}

///|
/// A link the system opened the app with, as the core reads it (`link.parse`): one of still.fail's desktop app's own
/// (stillfail://, ember://, stillfail-beta://: …//o/<workspace>/<station>/<chat>, as the web's /o/ page hands an item
/// to that app, which this one takes as it is built in its place: scripts/mac-app.sh) as the same page's on the
/// cloud; any other as it is.
pub fn app_link(url : String) -> String {
  for scheme in ["stillfail://", "ember://", "stillfail-beta://"] {
    if url.has_prefix(scheme) {
      return "\{cloud_origin()}/\{url.view(start_offset=scheme.length())}"
    }
  }
  url
}

///|
/// Shown over another app (the host's say, @hostapi.system_channel `over`): only the share sheet is drawn.
pub let share_over : Ref[Bool] = Ref(false)

///|
/// The workspace in view (the one switched to here, else the one last open, else the first once every account has
/// answered; None while none is known yet: the prefs, which say the one last open, not read yet among them), every
/// workspace, whether every account has answered, whether invitations wait.
pub fn workspace_in_view(src : Source) -> (Workspace?, Array[Workspace], Bool, Bool) {
  let ws = (src.topic)("workspaces", {})
  let prefs = (src.topic)("prefs", {})
  let (all, answered, invited) = workspaces_of(ws.value)
  // (the first before the prefs are read, the one last open once they are: a workspace shown, then another)
  if app.picked.get() == "" && prefs.value is None && prefs.error is None {
    return (None, all, answered, invited)
  }
  let kept = if app.picked.get() != "" {
    app.picked.get()
  } else {
    text(prefs.value, "workspace")
  }
  let current = match all.iter().find_first(fn(w) { w.id == kept }) {
    Some(w) => Some(w)
    None =>
      if all.length() > 0 && (kept == "" || answered) {
        Some(all[0])
      } else {
        None
      }
  }
  (current, all, answered, invited)
}

///|
/// The number last put on the app's icon (-1 none yet).
let badge_told : Ref[Int] = Ref(-1)

///|
/// Each frame signed in, `w` in view: the number on the app's icon (the desktop app's followBadge), the core's badge,
/// else what is wrong and what waits in every workspace; told as it changes, once the frame's builds are over.
pub fn badge_frame(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
  let badge = match field(marks, "badge") {
    Some(Number(_, ..)) => count(marks, "badge")
    _ =>
      match field(marks, "workspaces") {
        Some(Object(m)) => m.values().fold(init=0, fn(n, x) { n + count(Some(x), "alert") + count(Some(x), "wait") })
        _ => 0
      }
  }
  if marks is Some(_) && badge != badge_told.val {
    c.after_build("badge", fn() {
      badge_told.val = badge
      @ui.set_badge(badge)
    })
  }
}

///|
/// As at the start: nothing told the core, the host or the icon yet, nothing said by the system waiting.
fn app_frame_reset() -> Unit {
  badge_told.val = -1
  told_bars.val = None
  told_dark.val = None
  attention.told = false
  attention.visible = false
  attention.focused = false
  attention.workspace = ""
  attention.new_chat = false
  attention.src = None
  share_over.val = false
}

///|
/// Whether the app is shown (what it last told the core: `client.focus`); before it told anything, shown.
pub fn app_in_front() -> Bool {
  !attention.told || attention.visible
}
