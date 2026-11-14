// How the presets' menu names each preset (presets.mbt preset_menu_label): its name alone, its station's only beside
// another of the same name kept on another station.

///|
fn label_row(id : String, name : String, station : String, station_name : String) -> Json {
  { "id": Json::string(id), "name": Json::string(name), "station": Json::string(station), "stationName": Json::string(station_name) }
}

///|
test "a preset is named alone in the menu, though the workspace's presets are on several stations" {
  let all = [label_row("a", "设计", "ws1/st1", "Willow"), label_row("b", "后端", "ws1/st2", "Maple")]
  assert_eq(all.map(fn(p) { preset_menu_label(all, p) }), ["设计", "后端"])
}

///|
test "two presets of one name on two stations each say their station's name; one of a name on one station does not" {
  let all = [
    label_row("a", "still.fail", "ws1/st1", "Willow"),
    label_row("b", "still.fail", "ws1/st2", "Maple"),
    label_row("c", "设计", "ws1/st1", "Willow"),
    label_row("d", "设计", "ws1/st1", "Willow"),
  ]
  assert_eq(all.map(fn(p) { preset_menu_label(all, p) }), ["still.fail · Willow", "still.fail · Maple", "设计", "设计"])
}
