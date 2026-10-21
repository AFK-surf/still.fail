// Every model a run can move to (ember apps/android shared/screens/SettingParts.kt ModelList), by series as the core
// lists them: a field to filter them by once there are more than 8, a series' name over its models where there is
// more than one series, each model with its maker's mark, where it comes from after its name (ModelFrom), faint until
// borrowed when it is not usable here yet; said so when none matches.

///|
/// The list: all of the page under its bar, the filter over what scrolls.
// kept across runs: a value (no field of it changes)
let model_list_page : @ui.Style = @ui.style(w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let model_from_seen : @ui.Style = @ui.style(opacity=O100)

///|
/// The filter's room: 18 from the sides, 8 over it and 4 under.
// kept across runs: a value (no field of it changes)
let model_filter_room : @ui.Style = @ui.style(w=Full, px=S4_5, pt=S2, pb=S1)

///|
/// A series' name (Controls.kt GroupLabel: 13, muted, 14 over it and 4 under), at the rows' words.
// kept across runs: a value (no field of it changes)
let model_group_room : @ui.Style = @ui.style(w=Full, px=S5, pt=S3_5, pb=S1)

///|
// kept across runs: a value (no field of it changes)
let model_group_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted)

///|
/// None matching (14, muted, 16 over and under).
// kept across runs: a value (no field of it changes)
let model_none_room : @ui.Style = @ui.style(w=Full, px=S5, py=S4)

///|
// kept across runs: a value (no field of it changes)
let model_none_words : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, w=Full)

///|
/// Where a model comes from, small: half seen while it is not usable here yet.
// kept across runs: a value (no field of it changes)
let model_from_faint : @ui.Style = @ui.style(opacity=O50)

///|
// kept across runs: a value (no field of it changes)
let model_from_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The model the core's `picked` names: by its own name, else among the names it also goes by (optionOf).
fn model_option_of(models : Array[Json], picked : String) -> Json? {
  if picked == "" {
    return None
  }
  match models.iter().find_first(fn(m) { text(Some(m), "model") == picked }) {
    Some(m) => Some(m)
    None => models.iter().find_first(fn(m) { strings(Some(m), "ids").contains(picked) })
  }
}

///|
/// The list, as a page's body under its bar: `key` its scroll's, `on_pick` told the model tapped.
fn model_list(
  c : @ui.Ctx,
  key : String,
  models : Array[Json],
  runtime : String,
  picked : String,
  on_pick : (String) -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(style=model_list_page, fn() {
    let filter = if models.length() > 8 {
      let mut words = ""
      c.box(style=model_filter_room, fn() { words = field_box(c, key + "/filter", tr("android-chat.run.model.search")) }) |> ignore
      words.trim(chars=" ").to_string().to_lower()
    } else {
      ""
    }
    let shown = models.filter(fn(m) {
      let mv = Some(m)
      filter == "" ||
      [text(mv, "name"), text(mv, "model"), ..strings(mv, "ids")].iter().any(fn(w) { w.to_lower().contains(filter) })
    })
    let on = model_option_of(models, picked)
    // by series, in the core's order
    let groups : Array[(String, Array[Json])] = []
    for m in shown {
      let who = match text(Some(m), "family") {
        "" => tr("android-chat.pick.family.other")
        f => f
      }
      match groups.search_by(fn(g) { g.0 == who }) {
        Some(i) => groups[i].1.push(m)
        None => groups.push((who, [m]))
      }
    }
    let blocks : Array[() -> Unit] = []
    for g in groups {
      if groups.length() > 1 {
        let who = g.0
        blocks.push(fn() { c.box(style=model_group_room, fn() { c.text(who, style=model_group_words) |> ignore }) |> ignore })
      }
      for m in g.1 {
        blocks.push(fn() {
          let mv = Some(m)
          let model = text(mv, "model")
          let is_on = match on {
            Some(o) => text(Some(o), "model") == model
            None => false
          }
          // not usable here till borrowed: faint, until it is the one picked
          let faint = text(mv, "availability") == "borrowable" && !is_on
          let from = field(mv, "fromStation")
          if pick_row(
              c,
              key + "/" + model,
              text(mv, "name"),
              checked=is_on,
              color=if faint { t.p.muted } else { t.p.text },
              mark=fn() { @sf.maker_mark(c, text(field(mv, "maker"), "id"), runtime, 18.0) |> ignore },
              tag?=match from {
                Some(Object(_)) =>
                  Some(fn() {
                    c.box(style=if faint { model_from_faint } else { model_from_seen }, fn() {
                      if @sf.has_station_mark(text(from, "emoji"), text(from, "icon")) {
                        @sf.station_mark(c, text(from, "emoji"), text(from, "icon"), 14.0, t.p.muted)
                      } else {
                        c.text(text(from, "name"), style=model_from_words) |> ignore
                      }
                    })
                    |> ignore
                  })
                _ => None
              },
            ) {
            on_pick(model)
          }
        })
      }
    }
    if shown.length() == 0 {
      blocks.push(fn() {
        c.box(style=model_none_room, fn() { c.text(tr("android-chat.run.model.none"), style=model_none_words) |> ignore })
        |> ignore
      })
    }
    scroll_page(c, key, blocks)
  })
  |> ignore
}
