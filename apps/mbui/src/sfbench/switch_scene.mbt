// A workspace picked in the workspaces' sheet on 小屏, for scripts/instrbench.sh's switch scenes
// (MBUI_FIXTURE=switch-real:<ms>): Home on the workspace of real size (src/sfrealsize, both workspaces holding it), its
// core made up and answering through the app's own client as a phone's does, late: the chats' list <ms> after it is
// asked, what the new workspace's first screen opens on besides at most that, and every other topic 10 to 40 ms after
// it is asked, by its name. The script opens the sheet by the switcher and presses the other workspace's row
// (switch-ws.drive), or closes it pressing outside it (switch-ws-close.drive).

///|
/// How late the made-up core answers a topic the switch does not wait for: 10 to 40 ms, by its name.
fn switch_real_other(name : String) -> Double {
  let mut h = 0
  for ch in name {
    h = (h * 31 + ch.to_int()) & 0x7fffffff
  }
  10.0 + (h % 31).to_double()
}

///|
/// The ms the chats' list is answered after it is asked, as the mode says it (25 where it says none of these).
fn switch_real_list_ms(mode : String) -> Double {
  for ms in [15, 25, 40, 100, 200] {
    if mode == "switch-real:\{ms}" {
      return ms.to_double()
    }
  }
  25.0
}

///|
/// The scene's source (the head says what).
fn switch_real_source(mode : String) -> @sfapp.Source {
  let list_ms = switch_real_list_ms(mode)
  let base = @sfapp.fixture_app("home")
  let c = @sfrealsize.RealSizeChanging::new()
  let late = fn(name : String, _ : Map[String, Json]) -> Double {
    match name {
      "chats" => list_ms
      "changelog" | "longJobs" => if list_ms < 15.0 { list_ms } else { 15.0 }
      _ => switch_real_other(name)
    }
  }
  { ..@sffixture.round_trip_again(c.source(base), 0.0, late~), reads_ahead: fn() { true } }
}
