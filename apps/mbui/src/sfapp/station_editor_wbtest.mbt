///|
test "opening a second copy of a station page keeps each variables editor independent" {
  let t = settings_tester("station:ws1/st1", platform=1)
  @settings.station_parts["ws1/st1"] = "settings"
  t.check_looks(false)
  t.keep_parts(true)
  t.draw()
  t.draw()
  @sfbase.open_page(Setting(@settings.Route::Station("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
}
