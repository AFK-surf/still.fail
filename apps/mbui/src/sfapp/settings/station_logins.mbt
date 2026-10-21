// A station page's 登录 (ember apps/android shared/screens/LoginCards.kt StationLogins; docs/remote-login.md): only the
// logins done there through still.fail. One under way is its card, as in its chat (Core's login_card); one ended a row
// saying how it ended, which chat's agent started it and who ended it. Nothing at all when there are none (or the
// station is from before them).

///|
/// The cards under way: 12 from the page's sides, 10 under them, 2 apart.
// kept across runs: a value (no field of it changes)
let logins_active : @ui.Style = @ui.style(w=Full, px=S3, pb=S2_5, gap=S0_5)

///|
/// What they are (13 on 19, muted), 24 in, 4 under.
// kept across runs: a value (no field of it changes)
let logins_lead_room : @ui.Style = @ui.style(w=Full, px=S6, pb=S1)

///|
// kept across runs: a value (no field of it changes)
let logins_lead_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, leading=L4_75, w=Full)

///|
/// The station's logins, as blocks of its page.
fn station_logins(c : @ui.Ctx, core : Core, address : String) -> Array[() -> Unit] {
  let t = @sf.theme()
  let view = (core.topic)("machineLogins", { "station": str(address) }).value
  let logins = items(view, "logins")
  if !flag(view, "supported") || logins.length() == 0 {
    return []
  }
  let active = logins.filter(fn(l) { flag(Some(l), "active") })
  let past = logins.filter(fn(l) { !flag(Some(l), "active") })
  let blocks : Array[() -> Unit] = [fn() { section_header(c, tr("web-main.logins.title"), start=S6) }]
  if active.length() > 0 {
    blocks.push(fn() {
      c.box(style=logins_active, fn() {
        for l in active {
          let id = text(Some(l), "id")
          (core.login_card)(c, address, id, login_marked.val is Some((a, m, _)) && a == address && m == id)
        }
      })
      |> ignore
    })
  }
  if past.length() > 0 {
    blocks.push(fn() {
      list_card(c, fn() {
        for l in past {
          let lv = Some(l)
          let said = [
            match text(lv, "chatTitle") {
              "" => ""
              chat => fill("web-main.logins.startedIn", [("chat", chat)])
            },
            text(lv, "doneByText"),
            text(lv, "whenText"),
            if text(lv, "doneByText") != "" { "" } else { text(lv, "statusText") },
          ].filter(fn(w) { w != "" })
          list_row(c, fn() {
            row_lines(
              c,
              text(lv, "command"),
              join(said, " · "),
              wrap_title=false,
              sub_color?=if text(lv, "state") == "failed" { Some(t.p.red) } else { None },
            )
          })
          |> ignore
        }
      })
    })
  }
  blocks.push(fn() {
    c.box(style=logins_lead_room, fn() { c.text(tr("web-main.logins.lead"), style=logins_lead_words) |> ignore }) |> ignore
  })
  blocks
}

///|
/// The login a link pointed to (AppState.open's `login`: Screen.Station(address, login)), on the station's page that
/// opens: its card marked, brought into view once (`true` once it was).
let login_marked : Ref[(String, String, Bool)?] = Ref(None)

///|
/// A link's login: the station's page about to open shows it marked, brought into view.
pub fn mark_login(address : String, login : String) -> Unit {
  login_marked.val = Some((address, login, false))
}

///|
/// The station's page (list `key`) brought to its login a link pointed to, at block `at` (its cards under way), once
/// the page's list is there.
fn bring_marked_login(c : @ui.Ctx, address : String, key : String, at : Int) -> Unit {
  match login_marked.val {
    Some((a, m, false)) if a == address && c.list_info(key) is Some(_) => {
      c.list_scroll_to(key, at)
      login_marked.val = Some((a, m, true))
    }
    _ => ()
  }
}
