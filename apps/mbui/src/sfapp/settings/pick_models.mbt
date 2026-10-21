// The step right after a profile is added (ember apps/android settings/screens/Profiles.kt PickModelsScreen): its
// models chosen on a page of their own, since chats use only those enabled, or skipped; either way on to its page.
// Its models are read by the check the station runs once it is added (a few seconds, the core's `modelsReading`):
// until then, that.

///|
fn pick_models_page(c : @ui.Ctx, core : Core, here : Here, address : String, id : String) -> Unit {
  let topic = stations_of(core, here)
  let sv = match topic.value {
    Some(Array(a)) => a.iter().find_first(fn(x) { text(Some(x), "station") == address })
    _ => None
  }
  let p = items(field(sv, "overview"), "profiles").iter().find_first(fn(x) { text(Some(x), "id") == id })
  let title = tr("android-settings.profile.pickModels.title")
  // on to its page, in this one's place
  let leave = fn() {
    (core.pop)()
    (core.push)(Profile(address, id))
  }
  c.box(style=pick_body, fn() {
    match p {
      None => {
        nav_bar(c, core, "Profile", title)
        if field(sv, "overview") is Some(Object(_)) && topic.error is None {
          place_empty(c, tr("android-settings.profile.none"))
        } else {
          waiting_cards(
            c,
            error=match topic.error {
              Some(e) => error_text(e)
              None => ""
            },
          )
        }
      }
      Some(pj) => {
        let pv = Some(pj)
        let models = strings(pv, "models")
        let sub = fn() {
          c.text(fill("android-settings.profile.pickModels.selected", [("n", models.length().to_string())]), style=pick_selected)
          |> ignore
        }
        nav_bar(c, core, "Profile", title, sub?=if models.length() > 0 { Some(sub) } else { None }, on_back=leave)
        let listed = strings(pv, "available").length() > 0
        let blocks : Array[() -> Unit] = [
          fn() {
            c.box(style=pick_lead_room, fn() {
              c.text(fill("android-settings.profile.pickModels.lead", [("name", text(pv, "name"))]), style=pick_lead) |> ignore
            })
            |> ignore
          },
        ]
        if flag(pv, "modelsReading") {
          blocks.push(fn() {
            c.box(style=pick_said_room, fn() { wait_line(c, tr("android-settings.profile.pickModels.reading")) }) |> ignore
          })
        } else if !listed && !flag(pv, "canAddModel") {
          let check = field(pv, "check")
          let words = if text(check, "state") == "ok" {
            tr("android-settings.profile.pickModels.none")
          } else {
            match text(check, "detail") {
              "" => text(pv, "checkText")
              d => d
            }
          }
          blocks.push(fn() { c.box(style=pick_said_room, fn() { c.text(words, style=pick_lead) |> ignore }) |> ignore })
        } else {
          blocks.append(models_section(c, core, address, pv, bare=true))
        }
        c.box(style=pick_body, fn() { scroll_page(c, "pick-models/" + address + "/" + id, blocks) }) |> ignore
        c.box(style=pick_foot, fn() {
          c.box(style=pick_button, fn() {
            if button(c, "pick-models-skip", tr("android-settings.profile.pickModels.skip"), false) {
              leave()
            }
          })
          |> ignore
          c.box(style=pick_button, fn() {
            if button(c, "pick-models-done", tr("common.done"), true, enabled=models.length() > 0) {
              leave()
            }
          })
          |> ignore
        })
        |> ignore
      }
    }
  })
  |> ignore
}

///|
/// How many are chosen, under the title (11 muted: Profiles.kt:786).
// kept across runs: a value (no field of it changes)
let pick_selected : @ui.TextStyle = @ui.text_style(size=Xs2, color=Muted, wrap=false)

///|
/// What the page is for: 13 muted, 24 in, 8 under it, the page's words 8 under its bar (Profiles.kt:787-788).
// kept across runs: a value (no field of it changes)
let pick_lead_room : @ui.Style = @ui.style(w=Full, px=S6, pt=S2, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let pick_lead : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, w=Full)

///|
/// What is said in place of the list (its models being read; none listed): 24 in, 8 over and under.
// kept across runs: a value (no field of it changes)
let pick_said_room : @ui.Style = @ui.style(w=Full, px=S6, py=S2)

///|
// kept across runs: a value (no field of it changes)
let pick_body : @ui.Style = @ui.style(w=Full, h=Full)

///|
/// 跳过 and 完成, as wide as each other, 10 apart, 16 in and 12 over and under (Profiles.kt:799).
// kept across runs: a value (no field of it changes)
let pick_foot : @ui.Style = @ui.style(row=true, w=Full, px=S4, py=S3, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let pick_button : @ui.Style = @ui.style(w=Full)
