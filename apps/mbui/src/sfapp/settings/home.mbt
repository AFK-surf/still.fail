// The settings' pages from the gear, by route, and what this device chose of how still.fail shows (AppearanceScreen):
// its theme, its prefs as chosen here a moment ago. The settings' list itself (the gear's page on a small screen, the
// sidebar beside these pages on a wider one) is sfpages' (settings_list.mbt), drawn by the frame's setting_route.

///|
/// A page of the settings, by its route: call for the page the app's stack shows. `root`: a place of the bottom
/// bar's at the stack's root (PlacePage.kt), under the app's own top bar, so without its compact one. `top`: where
/// that bar is over the page rather than above it, how far down what it shows starts (it scrolls under the bar).
pub fn page(
  c : @ui.Ctx,
  core : Core,
  here : Here,
  route : Route,
  root? : Bool = false,
  top? : Double = 0.0,
) -> Unit {
  frame(core, here, root~, top~)
  // the wide frame's words as the web's settings pages size them (their rows 13, what is under them 12, a section's
  // title 14): the scale's body (Lg), secondary (Sm) and values (Base) taken down there, every page's words with them,
  // and Xl2 (Android's back, 17, which these pages never say) the web's body for a section's title (the desktop's own
  // pages, ported from the web's, are src/sfdesk's, in the library's sizes)
  if wide.get() {
    let t = c.theme()
    c.with_theme({ ..t, text: { ..t.text, lg: wide_body, sm: wide_small, base: wide_body, xl2: wide_heading } }, fn() {
      route_page(c, core, here, route)
    })
  } else {
    // (laid out by its width, as a page of the library's is: the library's parts in it read it, @sf.look)
    @sf.with_look(@sf.look_for(c.width), fn() { route_page(c, core, here, route) })
  }
}

///|
/// What a page of the settings is drawn in (`page`'s, and the desktop's own pages', src/sfdesk): its core, where it
/// stands, the sheet a fixture's mode puts up over it.
pub fn frame(core : Core, here : Here, root? : Bool = false, top? : Double = 0.0) -> Unit {
  frame_core.val = Some(core)
  at_root.val = root
  root_top.val = if root { top } else { 0.0 }
  left_core.val = Some(core)
  fixture_sheet(core, here)
}

///|
/// The wide frame's body words (the web's text-ui: 13 on 20) and what is under them (text-meta: 12 on 18).
let wide_body : (Double, Double) = (13.0, 20.0)

///|
let wide_small : (Double, Double) = (12.0, 18.0)

///|
/// A section's title in the wide frame (the web's text-body: 14 on 22).
let wide_heading : (Double, Double) = (14.0, 22.0)

///|
fn route_page(c : @ui.Ctx, core : Core, here : Here, route : Route) -> Unit {
  match route {
    Stations => stations_page(c, core, here)
    Profiles(only) => profiles_page(c, core, here, only)
    Archive => archive_page(c, core, here)
    AdbShare(a) => adb_page(c, core, here, a)
    NewProfile(a) => new_profile_page(c, core, here, a)
    ProfileAccount(k) => profile_account_page(c, core, here, k)
    KeptFiles => kept_page(c, core)
    KeptChat(s, thread) => kept_chat_page(c, core, s, thread)
    // one page for every frame (src/sfpages about.mbt; the list, sfpages' settings_list.mbt), drawn by the frame's
    // setting_route
    Home | Appearance | Fonts | BarSettings | Changelog | About | Memories | Memory(_) | AutoDecisions | UsagePrices(_) | Usage | PickModels(_, _) | ProfileModels(_, _) | Me | Workspace | Security | SecurityOpen | Vault | VaultItems | VaultItem(_, _) | Connects(_) | Connect(_, _) | Station(_) | Profile(_, _) => ()
    // the web's desktop pages, one for every frame (src/sfpages), drawn by the frame's setting_route too
    Shortcuts | Notifications | Permissions | Archiving | StationArchiving(_) | LocalStation | MemoryDoc(_, _, _) | AutoCompletion | AutoPolicy(_) => ()
    RunSettings(s, key) => run_settings_page(c, core, s, key)
  }
}

///|
/// What was chosen here before the core's prefs say it (prefs.set on its way): by the pref's name.
let chosen : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// A pref as the core keeps it (the `prefs` topic), or as it was chosen here a moment ago.
pub fn pref(core : Core, name : String) -> String {
  let kept = text((core.topic)("prefs", Map::new()).value, name)
  match chosen.get(name) {
    Some(v) => {
      // the core has it now: what it keeps from here on (another device may change it)
      if v == kept {
        chosen.remove(name)
      }
      v
    }
    None => kept
  }
}

///|
/// A pref set (prefs.set), shown as chosen at once; "" takes it away (null: the default).
pub fn set_pref(core : Core, name : String, value : String) -> Unit {
  chosen[name] = value
  (core.call)(
    "prefs.set",
    obj([(name, if value == "" { Json::null() } else { str(value) })]),
    fn(r) {
      match r {
        Ok(_) => ()
        Err(e) => {
          chosen.remove(name)
          (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.appearance.title")), ("error", error_text(e))]))
        }
      }
    },
  )
}

///|
/// The theme chosen on this device: "system", "light" or "dark" (the prefs' `appearance`; the system's when none),
/// as chosen here before the core has it.
pub fn appearance(prefs : Json?) -> String {
  let kept = text(prefs, "appearance")
  let v = match chosen.get("appearance") {
    Some(v) => {
      if v == kept {
        chosen.remove("appearance")
      }
      v
    }
    None => kept
  }
  match v {
    "light" | "dark" => v
    _ => "system"
  }
}

///|
/// Whether the app is drawn dark: the theme chosen, or the system's (`system_dark`) when it follows it.
pub fn dark(prefs : Json?, system_dark : Bool) -> Bool {
  match appearance(prefs) {
    "dark" => true
    "light" => false
    _ => system_dark
  }
}

///|
/// still.fail's terms or privacy policy on the web (SettingsHome.kt Legal; the app speaks Chinese: no /en).
pub fn legal_url(page : String) -> String {
  "https://still.fail/" + page
}

///|
/// Notifications as switched here, until the core has answered (AppState.useNotify's `notify` meanwhile).
pub let notify_switched : @signals.Signal[Bool?] = @signals.signal(None)

///|
/// Notifications turned on or off on this device (SettingsHome.kt Notify, AppState.useNotify): turned on, the system
/// asked to allow them too; the core keeps it (`notify.set`), taking this device's pushes off the accounts when off,
/// and the push registration follows what it answers (Push.sync). Not done: said in a toast, the switch back.
pub fn use_notify(core : Core, on : Bool) -> Unit {
  if on {
    (core.notify_ask)()
  }
  notify_switched.set(Some(on))
  (core.call)("notify.set", obj([("on", Json::boolean(on))]), fn(r) {
    notify_switched.set(None)
    match r {
      Ok(v) =>
        (core.push_sync)(
          match field(Some(v), "push") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          },
        )
      Err(e) => {
        (core.say)(
          fill(
            if on {
              "android-misc.notify.onFailed"
            } else {
              "android-misc.notify.offFailed"
            },
            [("error", error_text(e))],
          ),
        )
        (core.push_sync)(None)
      }
    }
  })
}

///|
/// This build's version, as the version row says it after the app's name (SettingsHome.kt Version: its versionName,
/// 0.1.<build>): the build where the host knows it (Android's version code), the line alone where it does not.
pub fn build_version() -> String {
  let v = @ui.app_version()
  if v > 0 {
    "0.1." + v.to_string()
  } else {
    "0.1"
  }
}
